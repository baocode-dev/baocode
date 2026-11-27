@TestOn('mac-os')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baocode/ide/terminal/pty.dart';
import 'package:baocode/ide/terminal/terminal_file_drop.dart';
import 'package:baocode/ide/terminal/terminal_xterm.dart';
import 'package:bao_xterm/typings/xterm.dart' show ITerminalOptions;
import 'package:flutter_test/flutter_test.dart';

class _Shell {
  _Shell(this.directory, this.pty, int columns)
    : screen = TerminalXterm(
        ITerminalOptions(cols: columns, rows: 24, allowProposedApi: true),
      ) {
    subscription = const Utf8Decoder(allowMalformed: true)
        .bind(pty.output)
        .listen((text) {
          printed.write(text);
          screen.write(text);
        });
  }

  final Directory directory;
  final Pty pty;
  final TerminalXterm screen;
  final printed = StringBuffer();
  late final StreamSubscription<String> subscription;

  static Future<_Shell> start({
    Map<String, String> inherited = const {},
    int columns = 512,
  }) async {
    final directory = Directory.systemTemp.createTempSync(
      'baocode-unicode-pty',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final pty = await spawnPty(
      await terminalLaunch(
        directory.path,
        shell: (executable: '/bin/zsh', arguments: ['-f', '-i']),
        shellIntegration: false,
        columns: columns,
        rows: 24,
        environment: TerminalEnvironmentRequest(
          strict: true,
          env: {
            'PATH': '/usr/bin:/bin',
            'HOME': directory.path,
            'ZDOTDIR': directory.path,
            'PROMPT': 'READY> ',
            'RPROMPT': '',
            'LANG': 'en_US.UTF-8',
            ...inherited,
          },
        ),
      ),
    );
    final shell = _Shell(directory, pty, columns);
    addTearDown(() async {
      pty.kill();
      await pty.exitCode.timeout(const Duration(seconds: 5));
      await shell.subscription.cancel();
      shell.screen.dispose();
    });
    await shell.until(() => shell.line == 'READY>');
    return shell;
  }

  String get line {
    final buffer = screen.buffer.active;
    return buffer
        .getLine(buffer.baseY + buffer.cursorY)!
        .translateToString(true)
        .trimRight();
  }

  Future<void> until(bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out. Screen: $line\nOutput: $printed');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> shows(String expected) =>
      until(() => line == expected.trimRight());

  void drop(String text) => pty.writeText('\x1b[200~$text\x1b[201~');
}

void main() {
  test(
    'wrapped emoji input remains editable and returns to a clean prompt',
    () async {
      final shell = await _Shell.start(columns: 48);
      final path = '${shell.directory.path}/👨‍👩‍👧‍👦 中文合照.txt';
      await File(path).writeAsString('wrapped emoji path');
      final text = terminalFileDropText([path], shell: '/bin/zsh')!;
      shell.drop(text);
      await shell.until(() => shell.printed.toString().contains('.txt'));
      expect(shell.screen.buffer.active.cursorY, greaterThan(0));
      shell.pty.writeText('\x01test -f ');
      shell.pty.writeText('\x05');
      shell.printed.clear();
      shell.pty.writeText("&& printf 'FOUND\\n'\r");
      await shell.until(
        () =>
            RegExp(r'(^|[\r\n])FOUND\r?\n').hasMatch(shell.printed.toString()),
      );
      await shell.shows('READY>');
      expect(shell.screen.buffer.active.cursorX, 7);
      expect(shell.printed.toString(), isNot(contains('<200d>')));
    },
    skip: !File('/bin/zsh').existsSync(),
  );

  for (final name in [
    '👩‍💻中文说明.txt',
    '👨‍👩‍👧‍👦 合照.txt',
    '👍🏽.txt',
    '🇨🇳.txt',
    '❤️.txt',
    "中文'💻 [1]\$文件.txt",
  ]) {
    test('emoji drop keeps the prompt and cursor aligned: $name', () async {
      final shell = await _Shell.start();
      final path = '${shell.directory.path}/$name';
      await File(path).writeAsString('emoji path test');
      final text = terminalFileDropText([path], shell: '/bin/zsh')!;
      shell.drop(text);
      await shell.shows('READY> $text');
      // ASCII shell escapes occupy one cell; these Chinese characters two.
      final input = 'READY> $text';
      final width =
          input.runes.length + RegExp(r'[一-鿿]').allMatches(input).length;
      expect(shell.screen.buffer.active.cursorX, width);
      expect(shell.printed.toString(), isNot(contains('<200d>')));

      // Edit the pasted line with Home/End, then check the actual file.
      const prefix = 'test -f ';
      shell.pty.writeText('\x01$prefix');
      await shell.shows('READY> $prefix$text');
      shell.pty.writeText('\x05');
      shell.pty.writeText(r"&& printf 'FOUND\n'");
      await shell.shows("READY> $prefix$text&& printf 'FOUND\\n'");
      shell.printed.clear();
      shell.pty.writeText('\r');
      await shell.until(
        () =>
            RegExp(r'(^|[\r\n])FOUND\r?\n').hasMatch(shell.printed.toString()),
      );
      await shell.shows('READY>');
      expect(shell.screen.buffer.active.cursorX, 7);
    }, skip: !File('/bin/zsh').existsSync());
  }
}
