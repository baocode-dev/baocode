import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_websearch/bao_websearch.dart';
import 'package:path/path.dart' as p;

import '../kernel/antigravity/agy_runtime.dart';
import '../network/network_proxy_io.dart';
import '../platform/data_dir.dart';
import '../network/tls.dart';
import '../usage/usage_ledger.dart';
import '../workspace/editor_launcher.dart';
import 'antigravity/antigravity_accounts_io.dart';
import 'antigravity/antigravity_signatures_io.dart';
import 'codex/codex_accounts_io.dart';
import 'codex/codex_service.dart';
import 'image_api.dart';
import 'image_generation_io.dart';
import 'launch_environment.dart';
import 'model_provider.dart';
import 'model_providers.dart';
import 'model_runtime.dart';
import 'provider_accounts_io.dart';
import 'proxy/model_proxy.dart';
import 'upstream.dart';

/// The app's ChatGPT (Codex) accounts, over [ModelProviders.current].
final CodexAccounts _codex = CodexAccounts(
  providers: () => ModelProviders.current,
  findProxy: (url) => NetworkProxy.instance.findProxy(url),
  openBrowser: openExternal,
);

/// The app's Antigravity accounts, over [ModelProviders.current].
final AntigravityAccounts _antigravity = AntigravityAccounts(
  providers: () => ModelProviders.current,
  findProxy: (url) => NetworkProxy.instance.findProxy(url),
  openBrowser: openExternal,
);

/// Every provider's accounts, each asked of its own.
final ProviderAccounts _accounts = ProviderAccounts(
  providers: () => ModelProviders.current,
  codex: _codex,
  antigravity: _antigravity,
);

CodexService get codexService => _accounts;

/// The app's proxy, over [ModelProviders.current].
final ModelProxy _proxy = ModelProxy(
  provider: (id) => ModelProviders.current.provider(id),
  key: (id) => ModelProviders.current.key(id),
  onError: (id, error) => ModelProviders.current.reportError(id, error),
  findProxy: (url) => NetworkProxy.instance.findProxy(url),
  codex: _codex,
  antigravity: _antigravity,
  signatures: FileSignatureStore(
    () => p.join(DataDirectory.current.path, 'cache', 'gemini-signatures'),
  ),
  // Which models run the web search tool themselves, kept across runs.
  searchSupport: NativeSearchSupport(
    path: () =>
        p.join(DataDirectory.current.path, 'cache', 'web-search-support.json'),
  ),
  usage: () => UsageLedger.current,
);

/// The app's image generation, over [ModelProviders.current].
final ImageGenerator _images = ImageGenerator(
  codex: _codex,
  antigravity: _antigravity,
  key: (id) => ModelProviders.current.key(id),
);

Future<List<GeneratedImage>> generateImages(
  ModelProvider provider,
  ProviderModel model,
  ImageRequest request, {
  String? session,
}) => _images.generate(provider, model, request, session: session);

Future<List<RemoteModel>> listUpstreamModels(
  ModelProvider provider,
  String? key,
) async {
  if (provider.protocol == ProviderProtocol.codex) {
    return _codex.listModels(provider);
  }
  if (provider.protocol == ProviderProtocol.antigravity) {
    return _antigravity.listModels(provider);
  }
  if (provider.protocol == ProviderProtocol.agy) {
    try {
      return [
        for (final model in await AgyRuntime.local.models())
          RemoteModel(
            model.id,
            label: model.label,
            efforts: model.efforts.isEmpty ? null : model.efforts,
            images: true,
          ),
      ];
    } on AgyUnavailable catch (error) {
      throw UpstreamException(error.message);
    }
  }
  final urls = UpstreamUrls.models(provider);
  if (urls.isEmpty) {
    throw const UpstreamException('The base URL is not an http(s) URL.');
  }
  // The proxy as it is now: the settings page's test of a key may follow
  // turning Clash on.
  final route = await NetworkProxy.instance.resolve();
  final client = HttpClient(context: await upstreamSecurityContext())
    ..connectionTimeout = const Duration(seconds: 15)
    ..findProxy = route.findProxy;
  try {
    // The first that lists any; else none, when one answered (the others,
    // guesses at where the list is, may refuse a key that is right: their
    // errors are not the user's to see) and the first, where the list is
    // most likely, did not refuse the key; else the first error that is not
    // a missing path (a wrong key shows past it), or the first.
    UpstreamException? error;
    _Refused? refusedFirst;
    var answered = false;
    for (final (i, url) in urls.indexed) {
      try {
        final models = await _listModels(client, url, provider, key);
        if (models.isNotEmpty) return models;
        answered = true;
      } on UpstreamException catch (failed) {
        if (i == 0 && failed is _Refused) refusedFirst = failed;
        if (error == null || error is _NotFound && failed is! _NotFound) {
          error = failed;
        }
      }
    }
    if (refusedFirst != null) throw refusedFirst;
    if (error != null && !answered) throw error;
    return const [];
  } on SocketException catch (error) {
    throw UpstreamException('Could not connect: ${error.message}');
  } on HandshakeException catch (error) {
    throw UpstreamException('TLS failed: ${handshakeFailure(error)}');
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
    // Its own query kept (magpie's `kind`).
    final pageUrl = provider.protocol == ProviderProtocol.anthropic
        ? url.replace(
            queryParameters: {
              ...url.queryParameters,
              'limit': '1000',
              'after_id': ?after,
            },
          )
        : url;
    final request = await client.getUrl(pageUrl);
    upstreamHeaders(provider, key).forEach(request.headers.set);
    // The provider's own headers too, so a listing an upstream gates on
    // one (a session or tenant header) is answered: no model or session
    // to stand for here, so those variables go as written.
    customUpstreamHeaders(provider).forEach(request.headers.set);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 30));
    final text = await utf8.decodeStream(response);
    if (response.statusCode >= 400) {
      // Where it was asked: a wrong base URL shows in it.
      final message =
          '${upstreamErrorMessage(response.statusCode, text)} (GET $pageUrl)';
      throw switch (response.statusCode) {
        404 || 405 => _NotFound(message),
        401 || 403 => _Refused(message),
        _ => UpstreamException(message),
      };
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

/// The key refused (401, 403).
class _Refused extends UpstreamException {
  const _Refused(super.message);
}

Future<Map<String, String>> providerLaunchEnvironment(
  ModelProvider provider,
  String model,
) async {
  final key = await ModelProviders.current.key(provider.id);
  // Its calls kept (Settings → Usage): through the proxy, which keeps
  // them, whatever it speaks.
  final recordUsage = UsageLedger.current.enabled;
  final proxy = provider.throughProxy || recordUsage
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
    recordUsage: recordUsage,
  );
}

Future<void> stopModelProxy() async {
  // What was kept of the calls but not yet written.
  UsageLedger.current.flush();
  _codex.close();
  _antigravity.close();
  await _proxy.close();
}
