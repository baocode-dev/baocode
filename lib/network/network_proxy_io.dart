import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../kernel/claude_code/claude_environment.dart';
import 'connection_test.dart';
import 'proxy_settings.dart';

/// The proxy the app's requests and the Claude Code it starts go through,
/// as settings.json's [ProxyMode] says: the system's by default, read
/// again as it may change (Clash turned on or off while the app runs).
class NetworkProxy {
  NetworkProxy({
    Future<ProxyRoute> Function()? system,
    Future<Map<String, String>> Function()? environment,
    DateTime Function()? clock,
  }) : _system = system ?? readSystemProxy,
       _environment = environment ?? ClaudeEnvironment.of,
       _clock = clock ?? DateTime.now;

  /// The app's: followed from main().
  static NetworkProxy instance = NetworkProxy();

  final Future<ProxyRoute> Function() _system;
  final Future<Map<String, String>> Function() _environment;
  final DateTime Function() _clock;

  /// The setting asked for by key; none (the default mode) until
  /// [follow].
  Object? Function(String key)? _setting;
  Listenable? _changes;

  /// What requests go through until it is first read: the app's own
  /// environment.
  ProxyRoute _route = ProxyRoute.fromEnvironment(Platform.environment);
  DateTime? _readAt;
  Future<ProxyRoute>? _reading;

  /// Counts the settings' changes: a read begun before one is not kept.
  int _generation = 0;

  /// How long a connection's proxy is taken from what was read last.
  static const connectionMaxAge = Duration(seconds: 10);

  ProxyRoute get current => _route;

  /// Follows [setting] (settings.json's), read again when [changes]
  /// notifies.
  void follow(Listenable changes, Object? Function(String key) setting) {
    _changes?.removeListener(_changed);
    _setting = setting;
    _changes = changes..addListener(_changed);
    _changed();
  }

  void _changed() {
    _generation++;
    _readAt = null;
    unawaited(resolve());
  }

  /// The route now, read again when older than [maxAge] (always, by
  /// default: a session starts with the proxy as it is).
  Future<ProxyRoute> resolve({Duration maxAge = Duration.zero}) {
    final readAt = _readAt;
    if (readAt != null &&
        maxAge > Duration.zero &&
        _clock().difference(readAt) < maxAge) {
      return Future.value(_route);
    }
    return _reading ??= _read().whenComplete(() => _reading = null);
  }

  Future<ProxyRoute> _read() async {
    while (true) {
      final generation = _generation;
      final route = await _routeFor(
        ProxyMode.parse(_setting?.call(ProxyMode.settingKey)),
        _setting?.call(ProxyMode.urlKey),
      );
      if (generation != _generation) continue;
      _route = route;
      _readAt = _clock();
      return route;
    }
  }

  Future<ProxyRoute> _routeFor(ProxyMode mode, Object? url) async {
    switch (mode) {
      case ProxyMode.off:
        return const ProxyRoute.direct(ProxySource.off);
      case ProxyMode.manual:
        final server = url is String ? ProxyServer.parse(url) : null;
        if (server == null) return const ProxyRoute.direct();
        return ProxyRoute.manual(
          server,
          bypass: ProxyRoute.noProxyOf(await _inherited()),
        );
      case ProxyMode.system:
        final ProxyRoute system;
        try {
          system = await _system();
        } on Object catch (error) {
          debugPrint('System proxy not read: $error');
          return ProxyRoute.fromEnvironment(await _inherited());
        }
        if (!system.direct) return system;
        final environment = ProxyRoute.fromEnvironment(await _inherited());
        return environment.direct ? system : environment;
    }
  }

  Future<Map<String, String>> _inherited() async {
    try {
      return await _environment();
    } on Object {
      return Platform.environment;
    }
  }

  /// `HttpClient.findProxy` for the app's clients: what was read last,
  /// read again in the background when it is old.
  String findProxy(Uri url) {
    final readAt = _readAt;
    if (readAt == null || _clock().difference(readAt) >= connectionMaxAge) {
      unawaited(resolve());
    }
    return _route.findProxy(url);
  }

  /// What a Claude Code process is started with for it, over the
  /// environment it inherits ([ProxyRoute.environment]).
  Future<Map<String, String>> environment() async =>
      (await resolve()).environment;

  /// Whether [url] answers through the proxy now: how long until its
  /// answer's headers came, on a new connection (the name looked up, the
  /// proxy's tunnel, TLS), or throws a [ProbeFailure]. Any HTTP status is
  /// an answer; the body is not read.
  Future<Duration> probe(
    Uri url, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final route = await resolve();
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..findProxy = route.findProxy;
    final watch = Stopwatch()..start();
    try {
      final response = await client
          .getUrl(url)
          .then((request) => request.close())
          .timeout(timeout);
      if (response.statusCode == HttpStatus.proxyAuthenticationRequired) {
        throw const ProbeFailure(ProbeFailureKind.proxyAuth);
      }
      return watch.elapsed;
    } on ProbeFailure {
      rethrow;
    } on Object catch (error) {
      throw probeFailure(error);
    } finally {
      client.close(force: true);
    }
  }
}

/// [error], from asking a site, as why it was not reached.
@visibleForTesting
ProbeFailure probeFailure(Object error) {
  const refused = {61, 111, 10061};
  const reset = {54, 104, 10054};
  switch (error) {
    case TimeoutException():
      return const ProbeFailure(ProbeFailureKind.timeout);
    case SocketException(:final message, :final osError):
      final code = osError?.errorCode;
      final text = '$message ${osError?.message ?? ''}'.toLowerCase();
      final detail = osError?.message ?? message;
      if (refused.contains(code) || text.contains('refused')) {
        return ProbeFailure(ProbeFailureKind.refused, detail);
      }
      if (reset.contains(code) || text.contains('reset')) {
        return ProbeFailure(ProbeFailureKind.reset, detail);
      }
      if (text.contains('host lookup') || text.contains('nodename')) {
        return ProbeFailure(ProbeFailureKind.dns, detail);
      }
      if (text.contains('timed out')) {
        return ProbeFailure(ProbeFailureKind.timeout, detail);
      }
      return ProbeFailure(ProbeFailureKind.other, detail);
    case HandshakeException(:final message):
      // Cut off in the middle of it: blocked, as a reset is.
      return ProbeFailure(
        message.contains('terminated')
            ? ProbeFailureKind.reset
            : ProbeFailureKind.tls,
        message,
      );
    case TlsException(:final message):
      return ProbeFailure(ProbeFailureKind.tls, message);
    case HttpException(:final message) when message.contains('407'):
      return ProbeFailure(ProbeFailureKind.proxyAuth, message);
    case HttpException(:final message):
      return ProbeFailure(ProbeFailureKind.other, message);
    default:
      return ProbeFailure(ProbeFailureKind.other, '$error');
  }
}

/// Every [HttpClient] the app makes goes through [NetworkProxy]: the
/// updates', the usage data's, the downloads', the models'.
class NetworkProxyOverrides extends HttpOverrides {
  NetworkProxyOverrides(this.proxy);

  final NetworkProxy proxy;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = proxy.findProxy;
}

/// The system's proxy: `scutil --proxy` on macOS, the Internet Settings
/// in the registry on Windows (where Clash and the like set it); direct
/// elsewhere, and when it cannot be read.
Future<ProxyRoute> readSystemProxy() async {
  if (Platform.isMacOS) {
    final result = await Process.run('/usr/sbin/scutil', const [
      '--proxy',
    ]).timeout(const Duration(seconds: 3));
    if (result.exitCode != 0) return const ProxyRoute.direct();
    return parseScutilProxy('${result.stdout}');
  }
  if (Platform.isWindows) {
    final result = await Process.run('reg.exe', const [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
    ]).timeout(const Duration(seconds: 3));
    if (result.exitCode != 0) return const ProxyRoute.direct();
    return parseWindowsInternetSettings('${result.stdout}');
  }
  return const ProxyRoute.direct();
}

Future<void> startNetworkProxy(
  Listenable changes,
  Object? Function(String key) setting,
) async {
  final proxy = NetworkProxy.instance..follow(changes, setting);
  HttpOverrides.global = NetworkProxyOverrides(proxy);
  // A Future<void> of its own: a Future<ProxyRoute> passed on as one
  // would refuse main's `timeout(onTimeout: () {})` as it runs.
  await proxy.resolve();
}

Future<ProxyRoute> currentProxyRoute() => NetworkProxy.instance.resolve();

Future<Duration> probeConnection(Uri url) => NetworkProxy.instance.probe(url);
