import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../network/network_proxy_io.dart';
import 'model_provider.dart';
import 'model_providers.dart';
import 'model_runtime.dart' show UpstreamException;
import 'upstream.dart';
import 'upstream_quota.dart';
import 'upstream_quota_minimax.dart';

/// The upstreams' plan quotas, over the app's upstreams: what their
/// services say of the quota left, as last asked.
class UpstreamQuotaIo extends UpstreamQuotaService {
  UpstreamQuotaIo({required this.key, required this.findProxy});

  final Future<String?> Function(String id) key;
  final String Function(Uri url) findProxy;

  final Map<String, UpstreamQuota> _quotas = {};
  final Map<String, String> _errors = {};

  /// The queries under way, by upstream: one at a time.
  final Map<String, Future<void>> _running = {};

  @override
  bool supports(ModelProvider provider) => isMiniMaxHost(provider.host);

  @override
  Future<void> refresh(ModelProvider provider, {bool force = false}) async {
    if (!supports(provider)) return;
    final running = _running[provider.id];
    if (running != null) return running;
    final query = _refresh(provider, force: force);
    _running[provider.id] = query;
    try {
      await query;
    } finally {
      _running.remove(provider.id);
    }
  }

  @override
  UpstreamQuota? quota(String providerId) => _quotas[providerId];

  @override
  String? error(String providerId) => _errors[providerId];

  Future<void> _refresh(ModelProvider provider, {required bool force}) async {
    final known = _quotas[provider.id];
    if (!force &&
        known != null &&
        DateTime.now().difference(known.at) < UpstreamQuotaService.maxAge) {
      return;
    }
    try {
      final quota = await _ask(provider);
      if (quota == null) {
        _errors[provider.id] = 'The service says of no plan.';
      } else {
        _quotas[provider.id] = quota;
        _errors.remove(provider.id);
      }
    } on Object catch (error) {
      _errors[provider.id] = '$error';
    }
    notifyListeners();
  }

  /// What [provider]'s service says of the quota left.
  Future<UpstreamQuota?> _ask(ModelProvider provider) async {
    final apiKey = await key(provider.id);
    if (apiKey == null || apiKey.isEmpty) {
      throw const UpstreamException('The upstream has no API key.');
    }
    final url = miniMaxQuotaUrl(provider.host);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..findProxy = findProxy;
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      // Its coding plan's key goes as a bearer token, as its service wants
      // it (not as an API key, as the models of the upstream take it).
      request.headers.set('authorization', 'Bearer $apiKey');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final text = await utf8.decodeStream(response);
      if (response.statusCode >= 400) {
        throw UpstreamException(
          upstreamErrorMessage(response.statusCode, text),
        );
      }
      final Object? json;
      try {
        json = jsonDecode(text);
      } on FormatException {
        throw const UpstreamException('The answer is not JSON.');
      }
      return parseMiniMaxQuota(json, DateTime.now());
    } on SocketException catch (error) {
      throw UpstreamException('Could not connect: ${error.message}');
    } on HandshakeException catch (error) {
      throw UpstreamException('TLS failed: ${error.message}');
    } on TimeoutException {
      throw const UpstreamException('No answer in time.');
    } finally {
      client.close(force: true);
    }
  }
}

/// The upstreams' plan quotas, over the app's upstreams.
UpstreamQuotaService upstreamQuotaService() => UpstreamQuotaIo(
  key: (id) => ModelProviders.current.key(id),
  findProxy: (url) => NetworkProxy.instance.findProxy(url),
);
