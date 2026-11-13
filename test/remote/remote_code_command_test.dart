@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/server.dart' show ServerCli, runCodeCommand;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'remote_harness.dart';

/// The `code` command of a remote host's terminals (#249): the script on
/// their PATH, and the server's binary handing what it was given to the
/// app.
void main() {
  late RemoteHarness remote;
  late Directory scratch;
  late String root;
  late File received;

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('baocode-code-command-');
    root = scratch.resolveSymbolicLinksSync();
    received = File(p.join(root, 'received'));
    // The server's binary as the script runs it: what it was given, kept.
    final binary = File(p.join(root, 'server'))
      ..writeAsStringSync(
        '#!/bin/sh\nprintf "%s\\n" "\$@" > "${received.path}"\n',
      );
    await Process.run('chmod', ['755', binary.path]);
    remote = await RemoteHarness.start(cliExecutable: binary.path);
  });
  tearDown(() async {
    await remote.close();
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  /// Runs [command] in a shell of a terminal there; what it printed.
  Future<String> inTerminal(String command) async {
    final pty = await remote.client.startPty(
      cwd: root,
      shellIntegration: false,
      shell: ['/bin/sh'],
    );
    final output = StringBuffer();
    pty.output.listen((data) => output.write(utf8.decode(data)));
    pty.write(utf8.encode('$command; exit 0\n'));
    await pty.exitCode.timeout(const Duration(seconds: 10));
    return '$output';
  }

  /// [ServerCli.hookVariable], as a terminal there has it.
  Future<String> hookOf() async {
    final output = await inTerminal('echo "HOOK=\$${ServerCli.hookVariable}"');
    return RegExp(r'HOOK=(\d+:\w+)').firstMatch(output)!.group(1)!;
  }

  /// Runs the server's `code` command with [arguments]; its exit code and
  /// what it printed to stderr.
  Future<(int, String)> code(List<String> arguments, String hook) async {
    final errors = StreamController<List<int>>();
    final text = utf8.decoder.bind(errors.stream).join();
    final sink = IOSink(errors.sink);
    final exit = await runCodeCommand(
      arguments,
      environment: {ServerCli.hookVariable: hook},
      errors: sink,
    );
    await sink.close();
    return (exit, await text);
  }

  test('the terminals have `code` first on their PATH, which runs the '
      'server\'s binary with the folder and what it was given', () async {
    Directory(p.join(root, 'sub')).createSync();
    final output = await inTerminal(
      "cd sub && command -v code && code -n 'a b' x.dart",
    );
    final directory = p.join(remote.dataDir.path, 'remote-cli');
    expect(output, contains(p.join(directory, 'code')));
    expect(received.readAsLinesSync(), [
      ServerCli.cliArgument,
      p.join(root, 'sub'),
      '-n',
      'a b',
      'x.dart',
    ]);
  });

  test(
    'the command asks the app, and prints what it says went wrong',
    () async {
      final hook = await hookOf();
      final asked = <List<String>>[];
      String? answer;
      remote.client.onCode = (cwd, args) async {
        asked.add([cwd, ...args]);
        return answer;
      };

      expect(await code(['/srv/app', '-g', 'a.dart:3'], hook), (0, ''));
      expect(asked, [
        ['/srv/app', '-g', 'a.dart:3'],
      ]);

      answer = "BaoCode's code command only opens files and folders.";
      final (exit, errors) = await code(['/srv/app', '--version'], hook);
      expect(exit, 1);
      expect(errors, contains('code: $answer'));
    },
  );

  test('another secret, or none, gets nowhere', () async {
    final hook = await hookOf();
    final asked = <String>[];
    remote.client.onCode = (cwd, args) async {
      asked.add(cwd);
      return null;
    };
    final port = hook.split(':').first;
    expect((await code(['/srv', 'x'], '$port:wrong')).$1, 1);
    expect((await code(['/srv', 'x'], '')).$1, 1);
    expect(asked, isEmpty);
  });

  test('no binary to run (the server from its sources): no command', () async {
    final plain = await RemoteHarness.start();
    try {
      final pty = await plain.client.startPty(
        cwd: root,
        shellIntegration: false,
        shell: ['/bin/sh'],
      );
      final output = StringBuffer();
      pty.output.listen((data) => output.write(utf8.decode(data)));
      pty.write(utf8.encode('echo "[\$${ServerCli.hookVariable}]"; exit 0\n'));
      await pty.exitCode.timeout(const Duration(seconds: 10));
      expect('$output', contains('[]'));
    } finally {
      await plain.close();
    }
  });
}
