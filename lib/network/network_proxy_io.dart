import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../kernel/claude_code/claude_environment.dart';
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
        final environment = ProxyRoute.fromEnvironment(await _inherited());
        return ProxyRoute.manual(server, bypass: environment.bypass);
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

  /// Whether [url] answers through the proxy now: how long it took, or
  /// what went wrong. Any HTTP status is an answer.
  Future<Duration> probe(Uri url, {Duration timeout = const Duration(seconds: 10)}) async {
    final route = await resolve();
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..findProxy = route.findProxy;
    final watch = Stopwatch()..start();
    try {
      final request = await client.headUrl(url).timeout(timeout);
      final response = await request.close().timeout(timeout);
      await response.drain<void>();
      if (response.statusCode == HttpStatus.proxyAuthenticationRequired) {
        throw const HttpException('407 Proxy Authentication Required');
      }
      return watch.elapsed;
    } finally {
      client.close(force: true);
    }
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
) {
  final proxy = NetworkProxy.instance..follow(changes, setting);
  HttpOverrides.global = NetworkProxyOverrides(proxy);
  return proxy.resolve();
}

Future<ProxyRoute> currentProxyRoute() => NetworkProxy.instance.resolve();

Future<Duration> probeConnection(Uri url) => NetworkProxy.instance.probe(url);
