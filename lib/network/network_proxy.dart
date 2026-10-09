// The proxy the app and the Claude Code it starts go through (settings.json's
// `http.proxyMode` and `http.proxy`). None of it on the web.

import 'package:flutter/foundation.dart';

import 'network_proxy_stub.dart'
    if (dart.library.io) 'network_proxy_io.dart'
    as platform;
import 'proxy_settings.dart';

export 'connection_test.dart';
export 'proxy_settings.dart';

/// Follows [setting] (settings.json's) as [changes] notifies, and sends
/// every request the app makes through the proxy it names. Completes as
/// it is first read.
Future<void> startNetworkProxy(
  Listenable changes,
  Object? Function(String key) setting,
) => platform.startNetworkProxy(changes, setting);

/// The proxy now, the system's read again.
Future<ProxyRoute> currentProxyRoute() => platform.currentProxyRoute();

/// How long [url] took to answer through it; throws a [ProbeFailure].
Future<Duration> probeConnection(Uri url) => platform.probeConnection(url);
