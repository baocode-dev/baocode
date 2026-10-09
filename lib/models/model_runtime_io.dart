import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../network/network_proxy_io.dart';
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
  findProxy: (url) => NetworkProxy.instance.findProxy(url),
);

Future<List<RemoteModel>> listUpstreamModels(
  ModelProvider provider,
  String? key,
) async {
  final urls = UpstreamUrls.models(provider);
  if (urls.isEmpty) {
    throw const UpstreamException('The base URL is not an http(s) URL.');
  }
  // The proxy as it is now: the settings page's test of a key may follow
  // turning Clash on.
  final route = await NetworkProxy.instance.resolve();
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..findProxy = route.findProxy;
  try {
    // The first that lists any; else the first error that is not a
    // missing path (a wrong key shows past it), or the first.
    UpstreamException? error;
    for (final url in urls) {
      try {
        final models = await _listModels(client, url, provider, key);
        if (models.isNotEmpty) return models;
      } on UpstreamException catch (failed) {
        if (error == null || error is _NotFound && failed is! _NotFound) {
          error = failed;
        }
      }
    }
    if (error != null) throw error;
    return const [];
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

/// The models [url] lists, all its pages.
Future<List<RemoteModel>> _listModels(
  HttpClient client,
  Uri url,
  ModelProvider provider,
  String? key,
) async {
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
    final response = await request.close().timeout(const Duration(seconds: 30));
    final text = await utf8.decodeStream(response);
    if (response.statusCode >= 400) {
      // Where it was asked: a wrong base URL shows in it.
      final message =
          '${upstreamErrorMessage(response.statusCode, text)} (GET $pageUrl)';
      throw response.statusCode == 404 || response.statusCode == 405
          ? _NotFound(message)
          : UpstreamException(message);
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
}

/// An upstream without the path asked.
class _NotFound extends UpstreamException {
  const _NotFound(super.message);
}

Future<Map<String, String>> providerLaunchEnvironment(
  ModelProvider provider,
  String model,
) async {
  final key = await ModelProviders.current.key(provider.id);
  final proxy = provider.protocol.proxied
      ? await _proxy.endpoint(provider.id)
      : null;
  // What the session's own NO_PROXY keeps out of the user's proxy, beside
  // this machine.
  final route = await NetworkProxy.instance.resolve();
  return launchEnvironment(
    provider: provider,
    model: model,
    key: key,
    proxy: proxy,
    noProxy: route.direct ? null : route.noProxy,
  );
}

Future<void> stopModelProxy() => _proxy.close();
