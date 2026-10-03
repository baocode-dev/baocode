import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../kernel/claude_code/claude_environment.dart';
import 'launch_environment.dart';
import 'model_provider.dart';
import 'model_providers.dart';
import 'model_runtime.dart';
import 'proxy/model_proxy.dart';
import 'upstream.dart';

/// The app's proxy, over [ModelProviders.current].
final ModelProxy _proxy = ModelProxy(
  provider: (id) => ModelProviders.current.provider(id),
  key: (id) => ModelProviders.current.key(id),
  onError: (id, error) => ModelProviders.current.reportError(id, error),
  environment: ClaudeEnvironment.of,
);

Future<List<RemoteModel>> listUpstreamModels(
  ModelProvider provider,
  String? key,
) async {
  final url = UpstreamUrls.models(provider);
  if (url == null) {
    throw const UpstreamException('The base URL is not an http(s) URL.');
  }
  final environment = await ClaudeEnvironment.of();
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..findProxy = (url) =>
        HttpClient.findProxyFromEnvironment(url, environment: environment);
  try {
    final models = <RemoteModel>[];
    // Anthropic's list comes in pages.
    String? after;
    for (var page = 0; page < 20; page++) {
      final pageUrl = provider.protocol == ProviderProtocol.anthropic
          ? url.replace(queryParameters: {'limit': '1000', 'after_id': ?after})
          : url;
      final request = await client.getUrl(pageUrl);
      upstreamHeaders(provider, key).forEach(request.headers.set);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final text = await utf8.decodeStream(response);
      if (response.statusCode >= 400) {
        // Where it was asked: a wrong base URL shows in it.
        throw UpstreamException(
          '${upstreamErrorMessage(response.statusCode, text)} (GET $pageUrl)',
        );
      }
      final Object? json;
      try {
        json = jsonDecode(text);
      } on FormatException {
        throw UpstreamException(
          'The answer is not JSON: ${text.length > 200 ? '${text.substring(0, 200)}…' : text}',
        );
      }
      models.addAll(parseModelList(json));
      if (json case {'has_more': true, 'last_id': final String last}) {
        after = last;
        continue;
      }
      break;
    }
    return models;
  } on SocketException catch (error) {
    throw UpstreamException('Could not connect: ${error.message}');
  } on HandshakeException catch (error) {
    throw UpstreamException('TLS failed: ${error.message}');
  } on TimeoutException {
    throw const UpstreamException('No answer in time.');
  } on HttpException catch (error) {
    throw UpstreamException(error.message);
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, String>> providerLaunchEnvironment(
  ModelProvider provider,
  String model,
) async {
  final key = await ModelProviders.current.key(provider.id);
  final proxy = provider.protocol.proxied
      ? await _proxy.endpoint(provider.id)
      : null;
  final environment = await ClaudeEnvironment.of();
  return launchEnvironment(
    provider: provider,
    model: model,
    key: key,
    proxy: proxy,
    noProxy: environment['NO_PROXY'] ?? environment['no_proxy'],
  );
}

Future<void> stopModelProxy() => _proxy.close();
