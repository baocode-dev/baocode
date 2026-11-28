import 'dart:io';

import 'package:bao_remote/client.dart';

import '../network/network_proxy_io.dart';
import '../network/proxy_settings.dart';

/// Required loopback entries in `NO_PROXY` / `no_proxy` so remote processes
/// (such as `agy` calling a local `McpHttpServer` on the remote host) never
/// route remote-loopback traffic back through a proxy.
const _requiredNoProxy = ['127.0.0.1', 'localhost', '::1'];

/// Cached reverse forwards per [RemoteClient], keyed by local proxy port.
final Expando<Map<int, Future<RemoteForward>>> _forwards = Expando();

/// Proxy environment variables for a process running on [client]'s remote host.
///
/// Uses [route] when given, otherwise resolves the current local proxy route
/// via [NetworkProxy.instance]. Returns `const {}` when [route] is direct.
///
/// Any proxy pointing at a local loopback address (`127.0.0.1`, `localhost`,
/// `::1`) is reverse-forwarded onto the remote host with [RemoteClient.forward]
/// (cached per `client` + local port, evicted on failure so retries succeed)
/// and rewritten to `http://127.0.0.1:<remotePort>` while preserving scheme and
/// credentials. Non-loopback proxies are forwarded as-is.
///
/// `NO_PROXY` and `no_proxy` always include `127.0.0.1,localhost,::1`.
Future<Map<String, String>> remoteProxyEnvironment(
  RemoteClient client, {
  ProxyRoute? route,
}) async {
  final resolved = route ?? await NetworkProxy.instance.resolve();
  if (resolved.direct) return const {};

  final httpUrl = await _resolveProxyUrl(client, resolved.http);
  final httpsUrl = await _resolveProxyUrl(client, resolved.https);
  final allUrl = httpsUrl ?? httpUrl ?? '';
  final noProxy = _mergeNoProxy(resolved);

  return {
    'HTTP_PROXY': httpUrl ?? '',
    'HTTPS_PROXY': httpsUrl ?? '',
    'ALL_PROXY': allUrl,
    'http_proxy': httpUrl ?? '',
    'https_proxy': httpsUrl ?? '',
    'all_proxy': allUrl,
    'NO_PROXY': noProxy,
    'no_proxy': noProxy,
  };
}

Future<String?> _resolveProxyUrl(
  RemoteClient client,
  ProxyServer? server,
) async {
  if (server == null) return null;
  if (!_isLoopbackHost(server.host)) return server.url;
  final forward = await _forwardFor(client, server.port);
  return _rewriteLoopbackUrl(server, forward.remotePort);
}

Future<RemoteForward> _forwardFor(RemoteClient client, int localPort) {
  final forwards = _forwards[client] ??= {};
  final existing = forwards[localPort];
  if (existing != null) return existing;

  late final Future<RemoteForward> future;
  future = client.forward(localPort).catchError((
    Object error,
    StackTrace stack,
  ) {
    if (identical(forwards[localPort], future)) {
      forwards.remove(localPort);
    }
    Error.throwWithStackTrace(error, stack);
  });
  forwards[localPort] = future;
  return future;
}

bool _isLoopbackHost(String host) {
  var normalized = host.trim().toLowerCase();
  if (normalized.startsWith('[') && normalized.endsWith(']')) {
    normalized = normalized.substring(1, normalized.length - 1);
  }
  if (normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1') {
    return true;
  }
  return InternetAddress.tryParse(normalized)?.isLoopback ?? false;
}

String _rewriteLoopbackUrl(ProxyServer server, int remotePort) {
  final parsed = Uri.parse(server.url);
  final scheme = parsed.scheme.isEmpty ? 'http' : parsed.scheme;
  final userInfo = parsed.userInfo.isEmpty ? '' : '${parsed.userInfo}@';
  return '$scheme://${userInfo}127.0.0.1:$remotePort';
}

String _mergeNoProxy(ProxyRoute route) {
  final entries = <String>[];
  final seen = <String>{};

  void add(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    if (seen.add(trimmed.toLowerCase())) {
      entries.add(trimmed);
    }
  }

  for (final requiredEntry in _requiredNoProxy) {
    add(requiredEntry);
  }
  for (final entry in route.noProxy.split(',')) {
    add(entry);
  }
  return entries.join(',');
}
