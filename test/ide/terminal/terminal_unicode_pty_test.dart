@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baocode/ide/terminal/pty.dart';
import 'package:baocode/ide/terminal/terminal_file_drop.dart';
import 'package:baocode/ide/terminal/terminal_xterm.dart';
import 'package:bao_xterm/typings/xterm.dart' show ITerminalOptions;
import 'package:flutter_test/flutter_test.dart';

String? _interactiveShell() {
  for (final path in ['/bin/zsh', '/bin/bash']) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

class _Shell {
  _Shell(this.directory, this.pty, this.executable, int columns)
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
  final String executable;
  final TerminalXterm screen;
  final printed = StringBuffer();
  late final StreamSubscription<String> subscription;

  static Future<_Shell> start({
    required String executable,
    int columns = 512,
  }) async {
    final directory = Directory.systemTemp.createTempSync(
      'baocode-unicode-pty',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final isZsh = executable.endsWith('/zsh');
    final args = isZsh ? ['-f', '-i'] : ['--norc', '--noprofile', '-i'];
    final pty = await spawnPty(
      await terminalLaunch(
        directory.path,
        shell: (executable: executable, arguments: args),
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
            'PS1': 'READY> ',
            'RPROMPT': '',
            'LANG': 'en_US.UTF-8',
          },
        ),
      ),
    );
    final shell = _Shell(directory, pty, executable, columns);
    addTearDown(() async {
      pty.kill();
      try {
        await pty.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        pty.kill(PtySignal.kill);
        await pty.exitCode.timeout(
          const Duration(seconds: 2),
          onTimeout: () => 0,
        );
      }
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
  final executable = _interactiveShell();

  test(
    'dropped Chinese and symbol paths stay literal, editable and resolvable',
    () async {
      final shell = await _Shell.start(executable: executable!);
      const name = "中文'★✓ [1]\$文件.txt";
      final path = '${shell.directory.path}/$name';
      await File(path).writeAsString('unicode path test');
      final text = terminalFileDropText([path], shell: executable)!;
      expect(text, isNot(contains(r"\u")));
      expect(text, isNot(contains(r"\U")));
      shell.drop(text);
      await shell.shows('READY> $text');

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
    },
    skip: executable == null,
  );

  test(
    'typing and backspacing emoji keeps cursor aligned with the shell prompt',
    () async {
      final shell = await _Shell.start(executable: executable!);
      expect(shell.screen.buffer.active.cursorX, 7);

      shell.pty.writeText('😂😂');
      await shell.shows('READY> 😂😂');
      expect(shell.screen.buffer.active.cursorX, 11);

      shell.pty.writeText('\x7f');
      await shell.shows('READY> 😂');
      expect(shell.screen.buffer.active.cursorX, 9);

      shell.pty.writeText('\x7f');
      await shell.shows('READY>');
      expect(shell.screen.buffer.active.cursorX, 7);
    },
    skip: executable == null,
  );

  test(
    'TerminalXterm uses Unicode 15 graphemes for emoji widths and redraws',
    () {
      final screen = TerminalXterm(ITerminalOptions(cols: 40, rows: 4));
      addTearDown(screen.dispose);
      expect(screen.core.unicodeService.activeVersion, '15-graphemes');

      // Simulate zsh-syntax-highlighting redrawing a wide emoji in place:
      // prompt + emoji, then 2 backspaces and colored emoji.
      screen.core.writeSync('✗ 😂\b\b\x1b[31m😂\x1b[0m');
      final line = screen.buffer.active.getLine(0)!;
      expect(line.translateToString(true), '✗ 😂');
      expect(screen.buffer.active.cursorX, 4);
      expect(line.getCell(2)!.getWidth(), 2);
      expect(line.getCell(3)!.getWidth(), 0);

      // Composite and Unicode 13/15 emojis occupy a single 2-cell grapheme.
      screen.core.writeSync('\r\n👩‍💻👨‍👩‍👧‍👦👍🏽🇨🇳❤️🥲');
      final emojiLine = screen.buffer.active.getLine(1)!;
      expect(emojiLine.translateToString(true), '👩‍💻👨‍👩‍👧‍👦👍🏽🇨🇳❤️🥲');
      expect(screen.buffer.active.cursorX, 12);
      for (var col = 0; col < 12; col += 2) {
        expect(emojiLine.getCell(col)!.getWidth(), 2, reason: 'col $col');
        expect(
          emojiLine.getCell(col + 1)!.getWidth(),
          0,
          reason: 'col ${col + 1}',
        );
      }
    },
  );

  for (final name in [
    '👩‍💻中文说明.txt',
    '👨‍👩‍👧‍👦 合照.txt',
    '👍🏽.txt',
    '🇨🇳.txt',
    '❤️.txt',
    '🙋 中文测试.txt',
    "中文'💻 [1]\$文件.txt",
  ]) {
    test('dropped emoji path resolves to original file: $name', () async {
      final shell = await _Shell.start(executable: executable!);
      final path = '${shell.directory.path}/$name';
      await File(path).writeAsString('emoji path test');
      final text = terminalFileDropText([path], shell: executable)!;
      expect(text, isNot(contains(r"\u")));
      expect(text, isNot(contains(r"\U")));
      shell.pty.writeText('test -f ');
      shell.drop(text);
      await shell.until(() => shell.printed.toString().contains('.txt'));
      shell.printed.clear();
      shell.pty.writeText("&& printf 'FOUND\\n'\r");
      await shell.until(
        () =>
            RegExp(r'(^|[\r\n])FOUND\r?\n').hasMatch(shell.printed.toString()),
      );
      await shell.shows('READY>');
      expect(shell.screen.buffer.active.cursorX, 7);
    }, skip: executable == null);
  }
}
