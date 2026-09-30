import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/pty.dart';
import 'package:monad/ide/terminal/pty_io.dart';
import 'package:monad/ide/terminal/pty_windows.dart';
import 'package:monad/platform/child_process_registry.dart';
import 'package:path/path.dart' as p;

/// ConPTY: how its command line and environment are made (anywhere), and
/// real processes on it (on Windows only).
void main() {
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
  }, skip: Platform.isWindows ? false : 'ConPTY runs on Windows only');
}
