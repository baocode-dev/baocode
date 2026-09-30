import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/pty.dart';
import 'package:monad/ide/terminal/pty_io.dart';
import 'package:monad/ide/terminal/pty_windows.dart';
import 'package:monad/platform/child_process_registry.dart';
import 'package:path/path.dart' as p;

/// A console for [ConsolePoll]: the output waiting in its pipe, and what
/// the poll did, in order.
class _Console {
  final waiting = <int>[];
  bool ended = false;
  final log = <String>[];
  var now = 0;

  ConsolePoll poll({bool Function()? check}) => ConsolePoll(
    available: () => waiting.isEmpty && ended ? -1 : waiting.length,
    read: (count) {
      final data = Uint8List.fromList(waiting.take(count).toList());
      waiting.removeRange(0, data.length);
      return data;
    },
    onOutput: (data) => log.add('${data.length}'),
    onOutputDone: () => log.add('done'),
    check: () {
      log.add('check@$now');
      return check?.call() ?? false;
    },
  );

  /// Lets [ms] milliseconds go by, one at a time.
  Future<void> wait(WidgetTester tester, int ms) async {
    for (var i = 0; i < ms; i++) {
      now++;
      await tester.pump(const Duration(milliseconds: 1));
    }
  }
}

/// ConPTY: how its output is polled, and its command line and environment
/// made (anywhere), and real processes on it (on Windows only).
void main() {
  group('ConsolePoll', () {
    testWidgets('reads what waits, a chunk at a time and a few in one '
        'turn; quiet, it looks less and less often, and soon again when '
        'hurried', (tester) async {
      final console = _Console();
      final poll = console.poll()..start();
      const chunk = ConsolePoll.chunk;
      console.waiting.addAll(List.filled(5 * chunk + 10, 0x78));
      await tester.pump(Duration.zero);
      expect(console.log, [
        'check@0',
        '$chunk',
        '$chunk',
        '$chunk',
        '$chunk',
        'check@0',
        '$chunk',
        '10',
      ]);

      console.log.clear();
      await console.wait(tester, 100);
      // 1ms after output, then twice as long each time, up to 32ms.
      expect(console.log, [
        'check@1',
        'check@3',
        'check@7',
        'check@15',
        'check@31',
        'check@63',
        'check@95',
      ]);

      console.log.clear();
      poll.hurry();
      console.waiting.addAll([0x61, 0x62]);
      await console.wait(tester, 1);
      expect(console.log, ['check@101', '2']);
      poll.stop();
    });

    testWidgets('paused, it reads nothing but still looks; resumed, it '
        'reads at once', (tester) async {
      final console = _Console();
      final poll = console.poll()..pause();
      console.waiting.addAll([1, 2, 3]);
      poll.start();
      await tester.pump(Duration.zero);
      await console.wait(tester, 3);
      expect(console.log, ['check@0', 'check@2']);

      console.log.clear();
      poll.resume();
      await console.wait(tester, 1);
      expect(console.log, ['check@4', '3']);
      poll.stop();
    });

    testWidgets('the output ends once, what else is watched is still looked '
        'at, until stopped', (tester) async {
      final console = _Console();
      var exited = false;
      final poll = console.poll(check: () => exited);
      console
        ..waiting.addAll([1, 2])
        ..ended = true;
      poll.start();
      await tester.pump(Duration.zero);
      expect(console.log, ['check@0', '2', 'done']);

      console.log.clear();
      await console.wait(tester, 3);
      expect(console.log, ['check@1', 'check@3']);

      // Something happening keeps it looking often.
      console.log.clear();
      exited = true;
      await console.wait(tester, 5);
      expect(console.log, ['check@7', 'check@8']);

      console.log.clear();
      poll.stop();
      await console.wait(tester, 50);
      expect(console.log, isEmpty);
    });
  });

  group('windowsCommandLine quotes as node-pty does', () {
    void check(String executable, List<String> arguments, String line) =>
        expect(windowsCommandLine(executable, arguments), line);

    test('plain strings', () {
      check('asdf', [], 'asdf');
      check(r'\asdf\qwer\', [], r'\asdf\qwer\');
      check(r'asdf\\qwer', [], r'asdf\\qwer');
      check('"asdf"qwer"', [], r'\"asdf\"qwer\"');
      check(r'asdf\"qwer', [], r'asdf\\\"qwer');
    });

    test('strings with blanks, or none', () {
      check('asdf qwer', [], '"asdf qwer"');
      check('', [], '""');
      check('asdf\tqwer', [], '"asdf\tqwer"');
      check(r'\asdf \qwer\', [], r'"\asdf \qwer\\"');
      check(r'asdf \\qwer', [], r'"asdf \\qwer"');
      check(r'asdf \"qwer', [], r'"asdf \\\"qwer"');
      check(r'asdf qwer\\', [], r'"asdf qwer\\\\"');
    });

    test('several arguments', () {
      check('asdf', ['qwer zxcv', '', '"'], r'asdf "qwer zxcv" "" \"');
      check(r'C:\Program Files\PowerShell\7\pwsh.exe', [
        '-NoLogo',
      ], r'"C:\Program Files\PowerShell\7\pwsh.exe" -NoLogo');
    });
  });

  test('windowsEnvironmentBlock sorts by name in any case', () {
    expect(
      windowsEnvironmentBlock({'b': '2', 'A': '1', 'C': '3=4'}),
      'A=1\u0000b=2\u0000C=3=4\u0000\u0000',
    );
    expect(windowsEnvironmentBlock({}), '\u0000');
  });

  group('ConPTY', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('monad-conpty');
      PtyProcesses.registry = ChildProcessRegistry(
        file: File(p.join(dir.path, 'pty-processes.json')),
        lookup: (_) async => null,
        signal: (_) => false,
      );
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<(Pty, StringBuffer)> cmd(String command) async {
      final pty = await startPty(
        PtyLaunch(
          executable: 'cmd.exe',
          arguments: ['/d', '/c', command],
          workingDirectory: dir.path,
        ),
      );
      final printed = StringBuffer();
      const Utf8Decoder(allowMalformed: true)
          .bind(pty.output)
          .listen(printed.write);
      return (pty, printed);
    }

    const timeout = Duration(seconds: 15);

    test('gives the output, then the exit code', () async {
      final (pty, printed) = await cmd('echo hello& exit /b 3');
      expect(await pty.exitCode.timeout(timeout), 3);
      expect(printed.toString(), contains('hello'));
    });

    test('runs in the working directory', () async {
      final (pty, printed) = await cmd('cd');
      expect(await pty.exitCode.timeout(timeout), 0);
      expect(printed.toString(), contains(p.basename(dir.path)));
    });

    test('kill ends a running process promptly', () async {
      final (pty, _) = await cmd('ping -n 30 127.0.0.1 >nul');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      pty.kill();
      await pty.exitCode.timeout(timeout);
    });

    test('paused, its output stops and the process waits; resumed, it '
        'goes on to the end', () async {
      final (pty, printed) = await cmd(
        '(for /l %i in (1,1,20000) do @echo line%i)& echo done',
      );
      pty.pause();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final whilePaused = printed.length;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(printed.length, whilePaused);

      pty.resume();
      expect(await pty.exitCode.timeout(timeout), 0);
      expect(printed.toString(), contains('line20000'));
      expect(printed.toString(), contains('done'));
    });
  }, skip: Platform.isWindows ? false : 'ConPTY runs on Windows only');
}
