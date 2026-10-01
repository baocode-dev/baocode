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

/// Real processes on a real pseudo terminal: only `/bin/sh -c` with fixed
/// commands, in a folder of the test's own, with an environment of the
/// test's own (no user shell configuration is read).
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
    int columns = 80,
    int rows = 24,
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
        columns: columns,
        rows: rows,
      ),
    );
    final printed = StringBuffer();
    const Utf8Decoder(allowMalformed: true)
        .bind(pty.output)
        .listen(printed.write);
    return (pty, printed);
  }

  /// Waits until [printed] has [pattern].
  Future<void> expectPrinted(StringBuffer printed, Pattern pattern) async {
    final deadline = DateTime.now().add(timeout);
    while (!printed.toString().contains(pattern)) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Not printed: $pattern\nPrinted: $printed');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('is supported here', () {
    expect(ptySupported, isTrue);
  });

  test('gives the output, then the exit code', () async {
    final (pty, printed) = await sh('printf hello; exit 3');
    expect(pty.pid, greaterThan(0));
    expect(await pty.exitCode.timeout(timeout), 3);
    expect(printed.toString(), contains('hello'));
  });

  test('the output closes before the exit code comes', () async {
    final pty = await startPty(
      PtyLaunch(
        executable: '/bin/sh',
        arguments: const ['-c', 'echo done'],
        workingDirectory: dir.path,
        environment: const {},
      ),
    );
    var closed = false;
    pty.output.listen(null, onDone: () => closed = true);
    await pty.exitCode.timeout(timeout);
    expect(closed, isTrue);
  });

  test('stdin and stdout are a terminal', () async {
    final (pty, printed) = await sh('test -t 0 && test -t 1 && echo tty');
    expect(await pty.exitCode.timeout(timeout), 0);
    expect(printed.toString(), contains('tty'));
  });

  test('has the size it started with, and a later one', () async {
    final (pty, printed) = await sh(
      'stty size; read line; stty size',
      columns: 91,
      rows: 17,
    );
    await expectPrinted(printed, '17 91');
    pty
      ..resize(120, 33)
      ..writeText('\n');
    await expectPrinted(printed, '33 120');
    expect(await pty.exitCode.timeout(timeout), 0);
  });

  test('takes input as typed', () async {
    final (pty, printed) = await sh(r'read x; echo got:$x');
    pty.writeText('abc\n');
    expect(await pty.exitCode.timeout(timeout), 0);
    expect(printed.toString(), contains('got:abc'));
  });

  test('takes input larger than the terminal holds at once', () async {
    const size = 200000;
    final (pty, printed) = await sh(
      'stty raw -echo; echo ready; head -c $size > input; echo; echo stored',
    );
    await expectPrinted(printed, 'ready');
    pty.writeText('x' * size);
    await expectPrinted(printed, 'stored');
    expect(await pty.exitCode.timeout(timeout), 0);
    expect(File(p.join(dir.path, 'input')).lengthSync(), size);
  });

  test('gives all of a long output', () async {
    final (pty, printed) = await sh(
      r'i=0; while [ $i -lt 3000 ]; do echo line$i; i=$((i+1)); done',
    );
    expect(await pty.exitCode.timeout(timeout), 0);
    final lines = const LineSplitter().convert(printed.toString());
    expect(lines.where((line) => line.startsWith('line')), hasLength(3000));
    expect(lines.last, 'line2999');
  });

  test('paused, it stops reading and the process waits; resumed, all of '
      'the output comes', () async {
    final (pty, printed) = await sh(
      "head -c 3000000 /dev/zero | tr '\\0' x; echo; echo done",
    );
    pty.pause();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final whilePaused = printed.length;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(printed.length, whilePaused);
    expect(whilePaused, lessThan(3000000));

    pty.resume();
    expect(await pty.exitCode.timeout(timeout), 0);
    expect('x'.allMatches(printed.toString()).length, 3000000);
    expect(printed.toString(), endsWith('done\r\n'));
  });

  test('kill hangs up a running process promptly', () async {
    final (pty, _) = await sh('sleep 10');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final stopwatch = Stopwatch()..start();
    pty.kill();
    final code = await pty.exitCode.timeout(const Duration(seconds: 3));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(code, -PtySignal.hangup.number);
  });

  test('kill hangs up the process group too', () async {
    final (pty, printed) = await sh(r'sleep 10 & echo "child $!"; wait');
    await expectPrinted(printed, RegExp(r'child \d+'));
    final child = RegExp(r'child (\d+)').firstMatch('$printed')!.group(1)!;
    pty.kill();
    expect(await pty.exitCode.timeout(const Duration(seconds: 3)), isNonZero);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(Process.runSync('kill', ['-0', child]).exitCode, isNot(0));
  });

  test('kill reaches the job in the foreground', () async {
    // With job control, the sleep runs in a process group of its own; the
    // shell defers its trap until the sleep ends.
    final (pty, printed) = await sh(
      "set -m; trap 'echo trapped' TERM; echo started; sleep 10; echo after",
    );
    await expectPrinted(printed, 'started');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    pty.kill(PtySignal.terminate);
    await pty.exitCode.timeout(const Duration(seconds: 3));
    expect(printed.toString(), contains('trapped'));
  });

  test('runs in the working directory, with the environment given', () async {
    final environment = terminalEnvironment(
      const {'PATH': '/usr/bin:/bin', 'LANG': 'C'},
      os: Platform.isMacOS ? TerminalOs.macOS : TerminalOs.linux,
      locale: 'en_US',
    );
    final (pty, printed) = await sh(
      r'pwd -P; echo "term=$TERM program=$TERM_PROGRAM lang=$LANG"',
      environment: environment,
    );
    expect(await pty.exitCode.timeout(timeout), 0);
    expect(printed.toString(), contains(dir.resolveSymbolicLinksSync()));
    expect(
      printed.toString(),
      contains('term=xterm-256color program=baocode lang=en_US.UTF-8'),
    );
  });

  test('the app ignoring SIGPIPE does not carry into the child', () async {
    final (pty, _) = await sh(r'kill -PIPE $$; echo alive');
    expect(await pty.exitCode.timeout(timeout), -13);
  });

  test('finds a program on the PATH', () async {
    final pty = await startPty(
      PtyLaunch(
        executable: 'sh',
        arguments: const ['-c', 'exit 7'],
        workingDirectory: dir.path,
        environment: const {'PATH': '/usr/bin:/bin'},
      ),
    );
    expect(await pty.exitCode.timeout(timeout), 7);
  });

  test('fails to start what is not there', () async {
    await expectLater(
      startPty(
        PtyLaunch(
          executable: p.join(dir.path, 'missing'),
          workingDirectory: dir.path,
          environment: const {},
        ),
      ),
      throwsA(
        isA<PtyException>().having(
          (error) => error.message,
          'message',
          contains('could not start'),
        ),
      ),
    );
    await expectLater(
      startPty(
        PtyLaunch(
          executable: 'baocode-no-such-program',
          workingDirectory: dir.path,
          environment: const {'PATH': '/usr/bin:/bin'},
        ),
      ),
      throwsA(isA<PtyException>()),
    );
    await expectLater(
      startPty(
        PtyLaunch(
          executable: '/bin/sh',
          workingDirectory: p.join(dir.path, 'gone'),
        ),
      ),
      throwsA(isA<PtyException>()),
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

  test('writes, resizes and kills after the exit do nothing', () async {
    final (pty, _) = await sh('exit 0');
    await pty.exitCode.timeout(timeout);
    pty
      ..writeText('late\n')
      ..resize(10, 10)
      ..kill();
  });
}
