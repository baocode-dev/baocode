import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/chat_models.dart';
import 'package:monad/chat/widgets/chat_item_view.dart';
import 'package:monad/chat/widgets/terminal_output.dart';
import 'package:monad/ide/terminal/terminal_colors.dart';
import 'package:monad/theme/cursor_theme.dart';

const _red = Color(0xFFCD3131);
const _brightGreen = Color(0xFF23D18B);

void main() {
  group('plain output', () {
    test('comes back as it is, trimmed at the end', () {
      const output = 'Flutter 3.47.5\n\tTools • Dart 3.12  \n\n';
      final shown = terminalOutput(output);
      expect(shown.text, output.trimRight());
      expect(shown.styled, isFalse);
      expect(shown.runs, [TerminalRun(output.trimRight())]);
    });

    test('nothing printed has no runs', () {
      expect(terminalOutput('').runs, isEmpty);
      expect(terminalOutput(' \n').text, '');
    });
  });

  group('colors', () {
    test('become runs, from the VS Code palette', () {
      final shown = terminalOutput(
        '\x1b[31merror\x1b[0m: \x1b[1;32mok\x1b[0m\n',
      );
      expect(shown.text, 'error: ok');
      expect(shown.styled, isTrue);
      expect(shown.runs, [
        const TerminalRun('error', foreground: _red),
        const TerminalRun(': '),
        // Bold brightens the first eight, as VS Code's terminal draws it.
        const TerminalRun('ok', foreground: _brightGreen, bold: true),
      ]);
      expect(TerminalColors.ansi[1], _red);
      expect(TerminalColors.ansi[10], _brightGreen);
    });

    test('256 colors, true colors and backgrounds', () {
      final shown = terminalOutput(
        '\x1b[38;5;208mA\x1b[38;2;1;2;3mB\x1b[0;44mC\x1b[0m',
      );
      expect(shown.runs, [
        TerminalRun('A', foreground: terminalAnsiColors()[208]),
        const TerminalRun('B', foreground: Color(0xFF010203)),
        const TerminalRun('C', background: Color(0xFF2472C8)),
      ]);
    });

    test('inverse swaps the colors, the default ones for the step\'s', () {
      final shown = terminalOutput('\x1b[7mA\x1b[31mB\x1b[0m');
      expect(shown.runs, [
        const TerminalRun(
          'A',
          foreground: CursorColors.code,
          background: CursorColors.textMuted,
        ),
        const TerminalRun('B', foreground: CursorColors.code, background: _red),
      ]);
    });

    test('dim, italic, underline, strikethrough; hidden text', () {
      final shown = terminalOutput(
        '\x1b[2mdim\x1b[0m \x1b[3mit\x1b[0m \x1b[4mun\x1b[0m '
        '\x1b[9mst\x1b[0m \x1b[8mpw\x1b[0m',
      );
      expect(shown.text, 'dim it un st pw');
      expect(shown.runs, [
        TerminalRun(
          'dim',
          foreground: CursorColors.textMuted.withValues(alpha: 0.5),
        ),
        const TerminalRun(' '),
        const TerminalRun('it', italic: true),
        const TerminalRun(' '),
        const TerminalRun('un', underline: true),
        const TerminalRun(' '),
        const TerminalRun('st', strikethrough: true),
        const TerminalRun(' '),
        const TerminalRun('pw', foreground: Color(0x00000000)),
      ]);
      final style = shown.runs[4].style!;
      expect(style.decoration, TextDecoration.underline);
      expect(shown.runs[0].style!.color!.a, 0.5);
      expect(shown.runs[0].style!.fontWeight, isNull);
    });

    test('runs of one style merge across lines', () {
      final shown = terminalOutput('\x1b[31ma\nb\x1b[0m\nc');
      // A line break goes with what comes before it.
      expect(shown.runs, [
        const TerminalRun('a\nb\n', foreground: _red),
        const TerminalRun('c'),
      ]);
    });
  });

  group('what it wrote over', () {
    test('a \\r progress line shows as it ended', () {
      final shown = terminalOutput(
        'Downloading  10%\rDownloading  50%\rDownloading 100%\ndone\n',
      );
      expect(shown.text, 'Downloading 100%\ndone');
      expect(shown.styled, isFalse);
      // Shorter over longer: as a terminal shows it, unless erased.
      expect(terminalOutput('100%\r5%').text, '5%0%');
      expect(terminalOutput('100%\r\x1b[K5%').text, '5%');
    });

    test('lines erased and printed again after moving up', () {
      final shown = terminalOutput(
        'layer 1: waiting\n'
        'layer 2: waiting\n'
        '\x1b[2A\x1b[2Klayer 1: \x1b[32mdone\x1b[0m\n'
        '\x1b[2Klayer 2: \x1b[32mdone\x1b[0m\n',
      );
      expect(shown.text, 'layer 1: done\nlayer 2: done');
      expect(shown.runs, [
        const TerminalRun('layer 1: '),
        const TerminalRun('done\n', foreground: Color(0xFF0DBC79)),
        const TerminalRun('layer 2: '),
        const TerminalRun('done', foreground: Color(0xFF0DBC79)),
      ]);
    });

    test('backspaces and Windows line ends', () {
      expect(terminalOutput('ab\bc\n').text, 'ac');
      final crlf = terminalOutput('one\r\ntwo\r\n');
      expect(crlf.text, 'one\ntwo');
      expect(crlf.styled, isFalse);
    });

    test('a full-screen program leaves what was before it', () {
      expect(
        terminalOutput('before\n\x1b[?1049hscreen\x1b[?1049lafter\n').text,
        'before\nafter',
      );
      // Cut short on its screen: that follows.
      expect(
        terminalOutput('before\n\x1b[?1049h\x1b[Hscreen').text,
        'before\nscreen',
      );
    });

    test('a clear keeps what was printed before it', () {
      expect(terminalOutput('old\n\x1b[H\x1b[2Jnew\n').text, 'old\nnew');
    });
  });

  group('size', () {
    test('long lines do not wrap', () {
      final line = List.generate(1200, (i) => '${i % 10}').join();
      final shown = terminalOutput('\x1b[1m$line\x1b[0m\nnext\n');
      expect(shown.text, '$line\nnext');
      expect(shown.runs, [
        TerminalRun('$line\n', bold: true),
        const TerminalRun('next'),
      ]);
    });

    test('moving right goes past a short line', () {
      expect(terminalOutput('a\x1b[30Cb').text, 'a${' ' * 30}b');
    });

    test('many lines are all kept', () {
      final lines = [for (var i = 0; i < 3000; i++) 'line $i'];
      final shown = terminalOutput('\x1b[32m${lines.join('\n')}\x1b[0m\n');
      expect(shown.text, lines.join('\n'));
    });
  });

  test('is parsed once per output', () {
    final output = '\x1b[31m${DateTime.now().microsecondsSinceEpoch}\x1b[0m';
    expect(identical(terminalOutput(output), terminalOutput(output)), isTrue);
  });

  test('copying the step gives the text shown, without escapes', () {
    const item = TerminalItem(
      command: 'npm install',
      output: '\x1b[33mwarn\x1b[0m deprecated\n[1/2] 50%\r[2/2] 100%\n',
    );
    expect(
      chatItemPlainText(item, expanded: true),
      'Ran npm install\n\$ npm install\nwarn deprecated\n[2/2] 100%',
    );
  });
}
