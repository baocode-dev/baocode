@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/pty.dart';
import 'package:baocode/ide/terminal/pty_io.dart';
import 'package:baocode/ide/terminal/terminal_shell.dart';
import 'package:baocode/platform/child_process_registry.dart';
import 'package:path/path.dart' as p;

/// The app's side of its terminals' processes: the record of them, stopping
/// them all, and the environment a terminal gives. The pseudo terminal
/// itself is bao_pty's, tested there. Only `/bin/sh -c` with fixed
/// commands, in a folder of the test's own.
void main() {
  late Directory dir;
  late File registryFile;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('baocode-pty');
    registryFile = File(p.join(dir.path, 'pty-processes.json'));
    // Never the user's own list, nor their processes.
    PtyProcesses.registry = ChildProcessRegistry(
      file: registryFile,
      lookup: (_) async => null,
      signal: (_) => false,
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  const timeout = Duration(seconds: 10);

  /// A terminal running `/bin/sh -c script`, with what it printed so far.
  Future<(Pty, StringBuffer)> sh(
    String script, {
    Map<String, String>? environment,
  }) async {
    final pty = await startPty(
      PtyLaunch(
        executable: '/bin/sh',
        arguments: ['-c', script],
        workingDirectory: dir.path,
        environment:
            environment ??
            const {'PATH': '/usr/bin:/bin', 'TERM': 'xterm-256color'},
      ),
    );
    final printed = StringBuffer();
    const Utf8Decoder(allowMalformed: true)
        .bind(pty.output)
        .listen(printed.write);
    return (pty, printed);
  }

  test('runs with the environment a terminal gives', () async {
    final environment = terminalEnvironment(
      const {'PATH': '/usr/bin:/bin', 'LANG': 'C'},
      os: Platform.isMacOS ? TerminalOs.macOS : TerminalOs.linux,
      locale: 'en_US',
    );
    final (pty, printed) = await sh(
      r'echo "term=$TERM program=$TERM_PROGRAM lang=$LANG"',
      environment: environment,
    );
    expect(await pty.exitCode.timeout(timeout), 0);
    expect(
      printed.toString(),
      contains('term=xterm-256color program=baocode lang=en_US.UTF-8'),
    );
  });

  test('is recorded while it runs', () async {
    final (pty, _) = await sh('read x');
    await PtyProcesses.registry.reaped;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(jsonDecode(registryFile.readAsStringSync()), [
      {'pid': pty.pid, 'parent': pid},
    ]);
    pty.writeText('\n');
    await pty.exitCode.timeout(timeout);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(jsonDecode(registryFile.readAsStringSync()), isEmpty);
  });

  test('stopPtyProcesses hangs up every terminal and waits', () async {
    final (first, _) = await sh('sleep 10');
    final (second, _) = await sh(
      "trap '' HUP INT TERM; while :; do sleep 1; done",
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await PtyProcesses.stopAll(timeout: const Duration(milliseconds: 500));
    expect(await first.exitCode.timeout(timeout), -PtySignal.hangup.number);
    expect(await second.exitCode.timeout(timeout), -PtySignal.kill.number);
  });
}
