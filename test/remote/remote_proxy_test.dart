import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/client.dart';
import 'package:baocode/network/network_proxy_io.dart';
import 'package:baocode/network/proxy_settings.dart';
import 'package:baocode/remote/remote_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'remote_harness.dart';

/// A [RemoteClient] wrapper that counts [forward] calls and can inject
/// transient failures to test caching and retry behavior.
class _CountingRemoteClient extends RemoteClient {
  _CountingRemoteClient(super.peer);

  final List<int> forwardedLocalPorts = [];
  int failNextForwards = 0;
  Completer<void>? gate;

  @override
  Future<RemoteForward> forward(
    int localPort, {
    String localHost = '127.0.0.1',
    int? remotePort,
  }) async {
    forwardedLocalPorts.add(localPort);
    final pendingGate = gate;
    if (pendingGate != null) {
      await pendingGate.future;
    }
    if (failNextForwards > 0) {
      failNextForwards--;
      throw StateError('transient forward failure for $localPort');
    }
    return super.forward(
      localPort,
      localHost: localHost,
      remotePort: remotePort,
    );
  }
}

void main() {
  late RemoteHarness harness;

  setUp(() async {
    harness = await RemoteHarness.start();
  });

  tearDown(() async {
    await harness.close();
  });

  test('direct routes return empty map without forwarding', () async {
    final noneEnv = await remoteProxyEnvironment(
      harness.client,
      route: const ProxyRoute.direct(),
    );
    final offEnv = await remoteProxyEnvironment(
      harness.client,
      route: const ProxyRoute.direct(ProxySource.off),
    );

    expect(noneEnv, isEmpty);
    expect(offEnv, isEmpty);
    expect(harness.client.forwardedPorts, isEmpty);
  });

  test('loopback proxy is reverse-forwarded and actually reachable', () async {
    final localProxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => localProxy.close(force: true));
    localProxy.listen((request) {
      request.response
        ..write('proxy-ok:${request.uri.path}')
        ..close();
    });

    final env = await remoteProxyEnvironment(
      harness.client,
      route: ProxyRoute.manual(ProxyServer('127.0.0.1', localProxy.port)),
    );

    final remotePort = harness.client.forwardedPorts.single;
    final expectedUrl = 'http://127.0.0.1:$remotePort';

    expect(env['HTTP_PROXY'], expectedUrl);
    expect(env['HTTPS_PROXY'], expectedUrl);
    expect(env['ALL_PROXY'], expectedUrl);
    expect(env['http_proxy'], expectedUrl);
    expect(env['https_proxy'], expectedUrl);
    expect(env['all_proxy'], expectedUrl);
    expect(env['NO_PROXY'], '127.0.0.1,localhost,::1');
    expect(env['no_proxy'], '127.0.0.1,localhost,::1');

    // Verify traffic to the rewritten remote port actually reaches localProxy.
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      remotePort,
    );
    socket.write('GET /ping HTTP/1.0\r\nHost: localhost\r\n\r\n');
    await socket.flush();
    final response = await utf8.decoder.bind(socket).join();
    socket.destroy();
    expect(response, contains('proxy-ok:/ping'));
  });

  test('rewrites localhost and ::1 loopback hosts and preserves userInfo', () async {
    final env = await remoteProxyEnvironment(
      harness.client,
      route: const ProxyRoute(
        source: ProxySource.manual,
        http: ProxyServer(
          'LOCALHOST',
          7890,
          username: 'alice',
          password: 'p@ss:word',
        ),
        https: ProxyServer('::1', 7891, username: 'bob'),
      ),
    );

    final httpUri = Uri.parse(env['HTTP_PROXY']!);
    final httpsUri = Uri.parse(env['HTTPS_PROXY']!);

    expect(httpUri.scheme, 'http');
    expect(httpUri.host, '127.0.0.1');
    expect(httpUri.port, isNot(7890));
    expect(httpUri.userInfo, 'alice:p%40ss%3Aword');

    expect(httpsUri.scheme, 'http');
    expect(httpsUri.host, '127.0.0.1');
    expect(httpsUri.port, isNot(7891));
    expect(httpsUri.port, isNot(httpUri.port));
    expect(httpsUri.userInfo, 'bob');

    expect(env['http_proxy'], env['HTTP_PROXY']);
    expect(env['https_proxy'], env['HTTPS_PROXY']);
    expect(env['ALL_PROXY'], env['HTTPS_PROXY']);
    expect(env['all_proxy'], env['HTTPS_PROXY']);
  });

  test('non-loopback proxy is preserved without forwarding', () async {
    const server = ProxyServer(
      'proxy.corp.example',
      8080,
      username: 'user',
      password: 'secret',
    );
    final env = await remoteProxyEnvironment(
      harness.client,
      route: ProxyRoute.manual(server),
    );

    expect(harness.client.forwardedPorts, isEmpty);
    expect(env['HTTP_PROXY'], 'http://user:secret@proxy.corp.example:8080');
    expect(env['HTTPS_PROXY'], 'http://user:secret@proxy.corp.example:8080');
    expect(env['ALL_PROXY'], 'http://user:secret@proxy.corp.example:8080');
    expect(env['http_proxy'], 'http://user:secret@proxy.corp.example:8080');
    expect(env['https_proxy'], 'http://user:secret@proxy.corp.example:8080');
    expect(env['all_proxy'], 'http://user:secret@proxy.corp.example:8080');
    expect(env['NO_PROXY'], '127.0.0.1,localhost,::1');
    expect(env['no_proxy'], '127.0.0.1,localhost,::1');
  });

  test('mixed route forwards loopback and preserves non-loopback', () async {
    final env = await remoteProxyEnvironment(
      harness.client,
      route: const ProxyRoute(
        source: ProxySource.system,
        http: ProxyServer('localhost', 7890),
        https: ProxyServer('corp-proxy.example', 8443),
      ),
    );

    final forwardedPort = harness.client.forwardedPorts.single;
    expect(env['HTTP_PROXY'], 'http://127.0.0.1:$forwardedPort');
    expect(env['HTTPS_PROXY'], 'http://corp-proxy.example:8443');
    expect(env['ALL_PROXY'], 'http://corp-proxy.example:8443');
  });

  test('merges NO_PROXY with bypass entries and deduplicates loopback', () async {
    final env = await remoteProxyEnvironment(
      harness.client,
      route: const ProxyRoute(
        source: ProxySource.environment,
        https: ProxyServer('proxy.example.com', 3128),
        bypass: [
          'LOCALHOST',
          '.internal.corp',
          '127.0.0.1',
          '100.64.0.0/10',
          '10.*', // Windows-only glob filtered out by ProxyRoute.noProxy
          'api.local',
        ],
      ),
    );

    expect(env['HTTP_PROXY'], '');
    expect(env['http_proxy'], '');
    expect(env['HTTPS_PROXY'], 'http://proxy.example.com:3128');
    expect(env['ALL_PROXY'], 'http://proxy.example.com:3128');
    expect(
      env['NO_PROXY'],
      '127.0.0.1,localhost,::1,.internal.corp,100.64.0.0/10,api.local',
    );
    expect(env['no_proxy'], env['NO_PROXY']);
  });

  test('caches forwards per client + localPort and evicts on failure', () async {
    final dataDir = Directory.systemTemp.createTempSync('baocode-proxy-cache-');
    addTearDown(() {
      if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
    });
    final link = await MemoryLink.open(dataDir.path);
    final countingClient = _CountingRemoteClient(link.client.peer);
    addTearDown(link.server.shutdown);

    // 1. Failed forward is removed from cache so retry succeeds.
    countingClient.failNextForwards = 1;
    final route = ProxyRoute.manual(const ProxyServer('127.0.0.1', 9090));
    await expectLater(
      remoteProxyEnvironment(countingClient, route: route),
      throwsA(isA<StateError>()),
    );
    expect(countingClient.forwardedLocalPorts, [9090]);

    // 2. Concurrent retries share the same in-flight forward future.
    final gate = Completer<void>();
    countingClient.gate = gate;
    final first = remoteProxyEnvironment(countingClient, route: route);
    final second = remoteProxyEnvironment(
      countingClient,
      route: const ProxyRoute(
        source: ProxySource.manual,
        http: ProxyServer('localhost', 9090),
        https: ProxyServer('127.0.0.1', 9090),
      ),
    );
    gate.complete();
    final [env1, env2] = await Future.wait([first, second]);

    expect(countingClient.forwardedLocalPorts, [9090, 9090]);
    expect(env1['HTTP_PROXY'], env2['HTTP_PROXY']);
    expect(env1['HTTPS_PROXY'], env2['HTTPS_PROXY']);

    // 3. Subsequent call hits cache without another forward RPC.
    final env3 = await remoteProxyEnvironment(countingClient, route: route);
    expect(countingClient.forwardedLocalPorts, [9090, 9090]);
    expect(env3['HTTP_PROXY'], env1['HTTP_PROXY']);

    // 4. Separate RemoteClient gets its own forward.
    final envOther = await remoteProxyEnvironment(harness.client, route: route);
    expect(envOther['HTTP_PROXY'], isNot(env1['HTTP_PROXY']));
  });

  test('resolves route from NetworkProxy.instance when route is omitted', () async {
    final previous = NetworkProxy.instance;
    addTearDown(() => NetworkProxy.instance = previous);
    NetworkProxy.instance = NetworkProxy(
      system: () async =>
          ProxyRoute.manual(const ProxyServer('127.0.0.1', 7899)),
      environment: () async => const {},
    );

    final env = await remoteProxyEnvironment(harness.client);
    final forwardedPort = harness.client.forwardedPorts.single;
    expect(env['HTTP_PROXY'], 'http://127.0.0.1:$forwardedPort');
    expect(env['HTTPS_PROXY'], 'http://127.0.0.1:$forwardedPort');
    expect(env['NO_PROXY'], '127.0.0.1,localhost,::1');
  });
}
