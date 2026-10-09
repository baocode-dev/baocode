import 'package:flutter/foundation.dart';

import 'proxy_settings.dart';

Future<void> startNetworkProxy(
  Listenable changes,
  Object? Function(String key) setting,
) async {}

Future<ProxyRoute> currentProxyRoute() async => const ProxyRoute.direct();

Future<Duration> probeConnection(Uri url) =>
    throw UnsupportedError('No proxy on the web');
