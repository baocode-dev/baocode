import 'dart:async';
import 'dart:io';

import 'package:baocode/network/network_proxy_io.dart';
import 'package:baocode/network/proxy_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

final _clash = ProxyRoute(
  source: ProxySource.system,
  http: const ProxyServer('127.0.0.1', 7890),
  https: const ProxyServer('127.0.0.1', 7890),
);

class _Settings extends ChangeNotifier {
  final Map<String, Object?> values = {};

  Object? operator [](String key) => values[key];

  void set(String key, Object? value) {
    values[key] = value;
    notifyListeners();
  }
}

void main() {
  late _Settings settings;
  late ProxyRoute system;
  late Map<String, String> environment;
  late int systemReads;

  NetworkProxy make({DateTime Function()? clock}) => NetworkProxy(
    system: () async {
      systemReads++;
      return system;
    },
    environment: () async => environment,
    clock: clock,
  )..follow(settings, (key) => settings[key]);

  setUp(() {
    settings = _Settings();
    system = _clash;
    environment = const {};
    systemReads = 0;
  });

  test('follows the system proxy by default', () async {
    final proxy = make();
    expect(await proxy.resolve(), _clash);
    expect(
      proxy.findProxy(Uri.parse('https://api.anthropic.com/')),
      'PROXY 127.0.0.1:7890',
    );
    expect((await proxy.environment())['HTTPS_PROXY'], 'http://127.0.0.1:7890');
  });

  test('reads the system again for a session: Clash turned on since', () async {
    system = const ProxyRoute.direct();
    final proxy = make();
    expect((await proxy.resolve()).direct, isTrue);
    system = _clash;
    expect(await proxy.resolve(), _clash);
  });

  test('takes the environment when the system has none', () async {
    system = const ProxyRoute.direct();
    environment = const {'HTTPS_PROXY': 'http://10.0.0.1:3128'};
    final route = await make().resolve();
    expect(route.source, ProxySource.environment);
    expect(route.https, const ProxyServer('10.0.0.1', 3128));
  });

  test('takes the environment when the system cannot be read', () async {
    environment = const {'https_proxy': 'http://10.0.0.1:3128'};
    final proxy = NetworkProxy(
      system: () async => throw const ProcessException('scutil', []),
      environment: () async => environment,
    )..follow(settings, (key) => settings[key]);
    expect((await proxy.resolve()).source, ProxySource.environment);
  });

  test(
    'a manual proxy over the system\'s, the environment\'s bypass kept',
    () async {
      environment = const {'NO_PROXY': 'corp.example'};
      final proxy = make();
      settings
        ..set(ProxyMode.settingKey, 'manual')
        ..set(ProxyMode.urlKey, 'http://192.168.1.5:8080');
      final route = await proxy.resolve();
      expect(route.source, ProxySource.manual);
      expect(route.https, const ProxyServer('192.168.1.5', 8080));
      expect(route.bypasses('git.corp.example'), isTrue);
    },
  );

  test('a manual mode without an address goes direct', () async {
    final proxy = make();
    settings.set(ProxyMode.settingKey, 'manual');
    expect((await proxy.resolve()).direct, isTrue);
  });

  test('off goes direct and clears the inherited proxy', () async {
    environment = const {'HTTPS_PROXY': 'http://10.0.0.1:3128'};
    final proxy = make();
    settings.set(ProxyMode.settingKey, 'off');
    final route = await proxy.resolve();
    expect(route.source, ProxySource.off);
    expect((await proxy.environment())['HTTPS_PROXY'], '');
    expect(systemReads, lessThanOrEqualTo(1));
  });

  test('a setting changed while it reads is not lost', () async {
    final gate = Completer<void>();
    final proxy = NetworkProxy(
      system: () async {
        await gate.future;
        return _clash;
      },
      environment: () async => const {},
    )..follow(settings, (key) => settings[key]);
    final reading = proxy.resolve();
    settings.set(ProxyMode.settingKey, 'off');
    gate.complete();
    expect((await reading).source, ProxySource.off);
    expect(proxy.current.source, ProxySource.off);
  });

  test('a connection takes what was read last, read again when old', () async {
    var now = DateTime(2026);
    final proxy = make(clock: () => now);
    await proxy.resolve();
    final reads = systemReads;
    proxy.findProxy(Uri.parse('https://x.example/'));
    await pumpEventQueue();
    expect(systemReads, reads);
    now = now.add(NetworkProxy.connectionMaxAge);
    system = const ProxyRoute.direct();
    expect(
      proxy.findProxy(Uri.parse('https://x.example/')),
      'PROXY 127.0.0.1:7890',
    );
    await pumpEventQueue();
    expect(systemReads, reads + 1);
    expect(proxy.findProxy(Uri.parse('https://x.example/')), 'DIRECT');
  });

  test('every HttpClient the app makes asks it', () async {
    final proxy = make();
    await proxy.resolve();
    final requested = <String>[];
    // An HTTP proxy on this machine: it is asked for the absolute URL.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      requested.add('${request.uri}');
      request.response
        ..statusCode = 204
        ..close();
    });
    addTearDown(() => server.close(force: true));
    system = ProxyRoute(
      source: ProxySource.system,
      http: ProxyServer('127.0.0.1', server.port),
    );
    await proxy.resolve();
    await HttpOverrides.runWithHttpOverrides(() async {
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://example.invalid/x'),
        );
        final response = await request.close();
        await response.drain<void>();
        expect(response.statusCode, 204);
      } finally {
        client.close(force: true);
      }
    }, NetworkProxyOverrides(proxy));
    expect(requested, ['http://example.invalid/x']);
  });
}
