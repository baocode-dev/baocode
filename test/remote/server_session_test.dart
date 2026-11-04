// A session's bridge on a host with no place for its socket where it is
// looked for first, or none at all: the server built from the sources, run
// as `ssh` would run it, its stdin and stdout the link.
@TestOn('mac-os || linux')
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/client.dart';
import 'package:bao_remote/server.dart' show RemoteServer, ServerSession;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late String server;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('bao session ');
    server = p.join(dir.path, 'baocode_server.dill');
    final built = await Process.run('dart', [
      'compile',
      'kernel',
      '-o',
      server,
      'bin/baocode_server.dart',
    ], workingDirectory: 'packages/bao_remote');
    expect(built.exitCode, 0, reason: '${built.stdout}${built.stderr}');
  });

  tearDownAll(() => dir.delete(recursive: true));

  /// A bridge to session [id], as `ssh` runs it, with [run] its folder of
  /// sockets and [temp] the system's temporary one: the link of [channel]
  /// (one of its own by default).
  Future<({Process process, ResumableChannel channel, List<String> said})>
  bridge(
    String id, {
    required String run,
    String? temp,
    bool resume = false,
    ResumableChannel? channel,
  }) async {
    final process = await Process.start(
      'dart',
      [
        server,
        '--session',
        id,
        '--run',
        run,
        '--data',
        p.join(dir.path, 'data'),
        if (resume) '--resume',
      ],
      environment: {'TMPDIR': ?temp},
    );
    final said = <String>[];
    process.stderr
        .transform(const SystemEncoding().decoder)
        .listen((text) => said.add(text));
    channel ??= ResumableChannel();
    unawaited(
      channel.attach(
        ChannelLink(
          input: process.stdout,
          write: process.stdin.add,
          close: process.kill,
        ),
      ),
    );
    return (process: process, channel: channel, said: said);
  }

  /// A path no folder can be made at: a file is there.
  String blocked(String name) =>
      (File(p.join(dir.path, name))..writeAsStringSync('')).path;

  test(
    'no socket in its folder: the session is in /tmp, resumed there',
    () async {
      final run = p.join(blocked('run-file'), 'run');
      final id = 'a1b2c3d4e5f60718';
      final first = await bridge(id, run: run);
      final client = RemoteClient(
        RpcPeer(first.channel.messages, first.channel.send),
      );
      await client.initialize().timeout(const Duration(seconds: 30));
      expect(
        first.said.join(),
        isNot(contains('serving this connection alone')),
      );
      // The link lost: the next bridge carries on the same session.
      final relinked = first.channel.linkChanges.firstWhere((up) => up);
      first.process.kill();
      await first.process.exitCode;
      final second = await bridge(
        id,
        run: run,
        resume: true,
        channel: first.channel,
      );
      expect(await relinked.timeout(const Duration(seconds: 10)), isTrue);
      await client.initialize().timeout(const Duration(seconds: 30));
      await client.shutdown();
      await second.process.exitCode.timeout(const Duration(seconds: 10));
    },
  );

  test('no place for a socket at all: this connection is served alone, '
      'not to be resumed', () async {
    final run = p.join(blocked('run-file-2'), 'run');
    final temp = blocked('tmp-file');
    final id = 'b1b2c3d4e5f60718';
    final first = await bridge(id, run: run, temp: temp);
    final client = RemoteClient(
      RpcPeer(first.channel.messages, first.channel.send),
    );
    final hello = await client.initialize().timeout(
      const Duration(seconds: 30),
    );
    expect(hello, isNotNull);
    expect(first.said.join(), contains('serving this connection alone'));
    first.process.kill();
    await first.process.exitCode;

    final second = await bridge(id, run: run, temp: temp, resume: true);
    expect(
      await second.channel.ended.timeout(const Duration(seconds: 10)),
      ChannelEnd.gone,
    );
  });

  test('as on Windows: the daemon listens on a port of the loopback, said '
      'in a file with a token, and only one that says it is let in; the '
      'link lost, the next carries on', () async {
    final run = p.join(dir.path, 'tcp-run');
    final session = ServerSession(
      id: 'c0ffee0123456789',
      runDirectory: run,
      heartbeat: const Duration(seconds: 1),
      tcp: true,
    );
    final ended = session.runDaemon(
      serve: (peer) => RemoteServer(
        peer,
        dataDir: p.join(dir.path, 'tcp-data'),
        version: 'test',
      ),
    );
    final file = File(session.portPath);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!file.existsSync() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final [port, token] = file.readAsStringSync().split(' ');
    expect(token, matches(RegExp(r'^[0-9a-f]{32}$')));

    Future<Socket> dial(String said) async {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        int.parse(port),
      );
      socket.add(utf8.encode('$said\n'));
      return socket;
    }

    // Another's: closed, never served.
    final stranger = await dial('not-the-token');
    expect(await stranger.fold<int>(0, (n, data) => n + data.length), 0);

    final channel = ResumableChannel(heartbeat: const Duration(seconds: 1));
    Future<void> link() async {
      final socket = await dial(token);
      unawaited(
        channel.attach(
          ChannelLink(input: socket, write: socket.add, close: socket.destroy),
        ),
      );
    }

    await link();
    final client = RemoteClient(RpcPeer(channel.messages, channel.send));
    await client.initialize().timeout(const Duration(seconds: 30));
    final relinked = channel.linkChanges
        .firstWhere((up) => !up)
        .then((_) => channel.linkChanges.firstWhere((up) => up));
    channel.detach();
    await link();
    expect(await relinked.timeout(const Duration(seconds: 10)), isTrue);
    await client.initialize().timeout(const Duration(seconds: 30));
    await client.shutdown();
    expect(await ended.timeout(const Duration(seconds: 10)), isTrue);
    // Gone with it.
    expect(file.existsSync(), isFalse);
  });
}
