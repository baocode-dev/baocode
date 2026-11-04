@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:baocode/remote/port_forwards.dart';
import 'package:baocode/remote/remote_host_settings.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'remote_harness.dart';

/// Ports forwarded both ways over a host's connection (a server in memory,
/// on this machine: "there" is here too, so the ports asked for are taken
/// and others are listened on).
void main() {
  late Directory dir;
  late MemoryConnector connector;
  late SshHosts hosts;
  late RemoteHostSettings settings;
  late PortForwards forwards;
  late HttpServer web;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('baocode-ports-');
    connector = MemoryConnector(dir.path);
    hosts = SshHosts(connect: connector.call);
    settings = RemoteHostSettings(file: p.join(dir.path, 'remote-hosts.json'));
    forwards = PortForwards(hosts: hosts, settings: settings, adbPort: null);
    web = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    web.listen((request) {
      request.response
        ..write('hello from ${request.uri.path}')
        ..close();
    });
  });

  tearDown(() async {
    forwards.dispose();
    await web.close(force: true);
    await hosts.closeAll();
    dir.deleteSync(recursive: true);
  });

  /// [path] of the server on [port], over a socket (flutter_test's
  /// HttpClient answers nothing).
  Future<String> get(int port, String path) async {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    socket.write('GET $path HTTP/1.0\r\nHost: localhost\r\n\r\n');
    await socket.flush();
    final response = await utf8.decoder.bind(socket).join();
    socket.destroy();
    final body = response.indexOf('\r\n\r\n');
    return body < 0 ? '' : response.substring(body + 4);
  }

  test("a host's server opened here: on another port where its own is "
      'taken, kept for the host', () async {
    await hosts['dev'].ready;
    final forward = await forwards.open(
      'dev',
      PortForwardSpec(direction: ForwardDirection.toLocal, port: web.port),
    );
    expect(forward.active, isTrue);
    expect(forward.remotePort, web.port);
    expect(forward.localPort, isNot(web.port));
    expect(forward.localUrl, 'http://localhost:${forward.localPort}');
    expect(await get(forward.localPort!, '/a'), 'hello from /a');
    expect(forwards.of('dev'), [forward]);
    expect(settings.forwards('dev'), [forward.spec]);

    // Read again by the next run of the app.
    final again = RemoteHostSettings(
      file: p.join(dir.path, 'remote-hosts.json'),
    );
    expect(again.forwards('dev'), [forward.spec]);

    final port = forward.localPort!;
    await forwards.close(forward);
    expect(forwards.of('dev'), isEmpty);
    expect(settings.forwards('dev'), isEmpty);
    await expectLater(
      Socket.connect(InternetAddress.loopbackIPv4, port),
      throwsA(isA<SocketException>()),
    );
  });

  test("a server here reached by the host's commands", () async {
    await hosts['dev'].ready;
    final forward = await forwards.open(
      'dev',
      PortForwardSpec(direction: ForwardDirection.toRemote, port: web.port),
    );
    expect(forward.localPort, web.port);
    // Taken there (it is here): another.
    expect(forward.remotePort, isNot(web.port));
    expect(await get(forward.remotePort!, '/b'), 'hello from /b');
    // A port asked for that is taken fails, rather than another.
    await expectLater(
      forwards.open(
        'dev',
        PortForwardSpec(
          direction: ForwardDirection.toRemote,
          port: web.port + 1,
          listen: web.port,
        ),
      ),
      throwsA(isA<PortForwardException>()),
    );
  });

  test("the host's kept forwards made as it connects; a session lost, "
      'those there made again', () async {
    settings.keepForward(
      'dev',
      PortForwardSpec(direction: ForwardDirection.toLocal, port: web.port),
    );
    settings.keepForward(
      'dev',
      PortForwardSpec(direction: ForwardDirection.toRemote, port: web.port),
    );
    forwards.watch();
    await hosts['dev'].ready;
    await pumpUntil(() => forwards.of('dev').length == 2);
    final [toLocal, toRemote] = forwards.of('dev');
    expect(await get(toLocal.localPort!, '/c'), 'hello from /c');
    expect(await get(toRemote.remotePort!, '/d'), 'hello from /d');

    // The session gone: a new one, and the forward there made on it.
    final before = toRemote.remotePort;
    await connector.links.last.drop();
    await pumpUntil(
      () =>
          hosts['dev'].state == SshHostState.connected &&
          toRemote.active &&
          toRemote.remotePort != before,
      reconnect: hosts['dev'],
    );
    expect(await get(toRemote.remotePort!, '/e'), 'hello from /e');
    // Here, the same: it carries on over the new session.
    expect(await get(toLocal.localPort!, '/f'), 'hello from /f');
  });

  test('servers found in what is printed, colours and all', () async {
    expect(
      PortForwards.portsIn(
        '  ➜  Local:   http://localhost:\x1b[1m5173\x1b[22m/\n'
        'Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...\n'
        ' * Running on http://127.0.0.1:5000\n'
        'see https://example.com:443 and localhost:3000',
      ),
      {5173, 8000, 5000},
    );

    await hosts['dev'].ready;
    forwards.notice('dev', 'listening on http://localhost:${web.port}');
    await pumpUntil(() => forwards.of('dev').isNotEmpty);
    final [found] = forwards.of('dev');
    expect(found.spec.auto, isTrue);
    expect(await get(found.localPort!, '/g'), 'hello from /g');
    // Once.
    forwards.notice('dev', 'again http://127.0.0.1:${web.port}/');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(forwards.of('dev'), hasLength(1));

    // A host's localhost URL opened here: on the port it is forwarded to.
    final url = await forwards.localUrl(
      'dev',
      Uri.parse('http://localhost:${web.port}/x?y=1'),
    );
    expect(url, Uri.parse('http://localhost:${found.localPort}/x?y=1'));
    expect(
      await forwards.localUrl('dev', Uri.parse('https://example.com/')),
      Uri.parse('https://example.com/'),
    );
  });
}

/// Waits (in real time) for [done], [reconnect] asked to connect again
/// meanwhile.
Future<void> pumpUntil(bool Function() done, {SshHost? reconnect}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out');
    if (reconnect != null && reconnect.state != SshHostState.connected) {
      await reconnect.ready.then((_) {}, onError: (Object _) {});
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
