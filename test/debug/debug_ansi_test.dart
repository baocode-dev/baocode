// The Debug Console's ANSI handling, as upstream's
// src/vs/workbench/contrib/debug/test/browser/debugANSIHandling.test.ts
// (1.135.0) checks it: the runs and their classes and colors.

import 'package:bao_editor/monaco/vs/base/common/color.dart' as vs;
import 'package:baocode/debug/ui/debug_ansi.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The run of [sequence] followed by text (upstream's
/// `assertSingleSequenceElement`).
AnsiRun _single(String sequence) {
  final runs = handleAnsiOutput('${sequence}content');
  expect(runs, hasLength(1), reason: sequence);
  expect(runs.single.text, 'content');
  return runs.single;
}

Matcher _rgba(int r, int g, int b) =>
    isA<vs.RGBA>().having((c) => [c.r, c.g, c.b], 'rgb', [r, g, b]);

void main() {
  test('Expected single sequence operation', () {
    expect(_single('\x1b[1m').classes, contains('code-bold'));
    expect(_single('\x1b[3m').classes, contains('code-italic'));
    expect(_single('\x1b[4m').classes, contains('code-underline'));

    for (var i = 30; i <= 37; i++) {
      final run = _single('\x1b[${i}m');
      expect(run.classes, contains('code-foreground-colored'));
      expect(run.foreground, startsWith('terminal.ansi'));
      final cancelled = _single('\x1b[$i;39m');
      expect(cancelled.classes, isNot(contains('code-foreground-colored')));
      expect(cancelled.foreground, isNull);
    }
    for (var i = 40; i <= 47; i++) {
      expect(_single('\x1b[${i}m').classes, contains('code-background-colored'));
      final cancelled = _single('\x1b[$i;49m');
      expect(cancelled.classes, isNot(contains('code-background-colored')));
      expect(cancelled.background, isNull);
    }
    for (var i = 0; i <= 255; i++) {
      expect(_single('\x1b[58;5;${i}m').classes, contains('code-underline-colored'));
      final cancelled = _single('\x1b[58;5;${i}m\x1b[59m');
      expect(cancelled.classes, isNot(contains('code-underline-colored')));
      expect(cancelled.underline, isNull);
    }

    // Different codes do not cancel each other.
    expect(
      _single('\x1b[1;3;4;30;41m').classes,
      unorderedEquals([
        'code-bold',
        'code-italic',
        'code-underline',
        'code-foreground-colored',
        'code-background-colored',
      ]),
    );

    // Nor accumulate more than one copy of each class.
    expect(
      _single('\x1b[1;1;2;2;3;3;4;4;5;5;6;6;8;8;9;9;21;21;53;53;73;73;74;74m').classes,
      unorderedEquals([
        'code-bold',
        'code-italic',
        'code-dim',
        'code-blink',
        'code-rapid-blink',
        'code-double-underline',
        'code-hidden',
        'code-strike-through',
        'code-overline',
        'code-subscript',
      ]),
    );
    expect(
      _single('\x1b[1;2;5;6;21;8;9m').classes,
      unorderedEquals([
        'code-bold',
        'code-dim',
        'code-blink',
        'code-rapid-blink',
        'code-double-underline',
        'code-hidden',
        'code-strike-through',
      ]),
    );

    // New foreground codes don't remove old background codes and vice versa.
    expect(
      _single('\x1b[40;31;42;33m').classes,
      unorderedEquals(['code-background-colored', 'code-foreground-colored']),
    );
    // Duplicates and a terminating semicolon change nothing.
    expect(_single('\x1b[1;1;4;1;4;4;1;4m').classes, containsAll(['code-bold', 'code-underline']));
    expect(_single('\x1b[1;4;m').classes, containsAll(['code-bold', 'code-underline']));

    // Reset clears everything.
    final reset = _single('\x1b[1;4;30;41;32;43;34;45;36;47;0m');
    expect(reset.classes, isEmpty);
    expect(reset.foreground, isNull);
    expect(reset.background, isNull);
  });

  test('Expected single 8-bit color sequence operation', () {
    for (var i = 0; i <= 15; i++) {
      expect(_single('\x1b[38;5;${i}m').classes, contains('code-foreground-colored'));
      expect(_single('\x1b[48;5;${i}m').classes, contains('code-background-colored'));
    }
    for (var i = 16; i <= 255; i++) {
      final c = calcAnsi8bitColor(i)!;
      final fg = _single('\x1b[38;5;${i}m');
      expect(fg.classes, contains('code-foreground-colored'));
      expect(fg.foreground, _rgba(c.r, c.g, c.b));
      final bg = _single('\x1b[48;5;${i}m');
      expect(bg.classes, contains('code-background-colored'));
      expect(bg.background, _rgba(c.r, c.g, c.b));
      final underline = _single('\x1b[58;5;${i}m');
      expect(underline.classes, contains('code-underline-colored'));
      expect(underline.underline, _rgba(c.r, c.g, c.b));
    }

    // A nonexistent color has no effect; codes after the color are ignored.
    expect(_single('\x1b[48;5;300m').classes, isEmpty);
    final extra = _single('\x1b[48;5;100;42;77;99;4;24m');
    expect(extra.classes, ['code-background-colored']);
    final c = calcAnsi8bitColor(100)!;
    expect(extra.background, _rgba(c.r, c.g, c.b));
  });

  test('Expected single 24-bit color sequence operation', () {
    for (var r = 0; r <= 255; r += 64) {
      for (var g = 0; g <= 255; g += 64) {
        for (var b = 0; b <= 255; b += 64) {
          expect(_single('\x1b[38;2;$r;$g;${b}m').foreground, _rgba(r, g, b));
          expect(_single('\x1b[48;2;$r;$g;${b}m').background, _rgba(r, g, b));
          expect(_single('\x1b[58;2;$r;$g;${b}m').underline, _rgba(r, g, b));
        }
      }
    }
    final invalid = _single('\x1b[38;2;4;4m');
    expect(invalid.classes, isEmpty);
    expect(invalid.foreground, isNull);
    expect(_single('\x1b[48;2;150;300;5m').classes, isEmpty);
    final extra = _single('\x1b[48;2;100;42;77;99;200;75m');
    expect(extra.classes, ['code-background-colored']);
    expect(extra.background, _rgba(100, 42, 77));
  });

  test('Expected multiple sequence operation', () {
    // Multiple codes affect the same text.
    expect(
      _single('\x1b[1m\x1b[3m\x1b[4m\x1b[32m').classes,
      containsAll(['code-bold', 'code-italic', 'code-underline', 'code-foreground-colored']),
    );

    // Styles apply to the text after them, until changed.
    final runs = handleAnsiOutput('\x1b[31mred\x1b[0m plain \x1b[1;32mbold green');
    expect([for (final r in runs) r.text], ['red', ' plain ', 'bold green']);
    expect(runs[0].foreground, 'terminal.ansiRed');
    expect(runs[1].classes, isEmpty);
    expect(runs[2].foreground, 'terminal.ansiGreen');
    expect(runs[2].classes, contains('code-bold'));

    // Inversion swaps the colors, and back.
    final inverted = handleAnsiOutput('\x1b[31;42m\x1b[7mA\x1b[27mB');
    expect(inverted[0].foreground, 'terminal.ansiGreen');
    expect(inverted[0].background, 'terminal.ansiRed');
    expect(inverted[1].foreground, 'terminal.ansiRed');
    expect(inverted[1].background, 'terminal.ansiGreen');

    // Bright colors.
    expect(_single('\x1b[91m').foreground, 'terminal.ansiBrightRed');
    expect(_single('\x1b[38;5;9m').foreground, 'terminal.ansiBrightRed');
    expect(_single('\x1b[104m').background, 'terminal.ansiBrightBlue');
  });

  test('Invalid codes treated as regular text', () {
    for (final sequence in ['\x1b', '[', '\x1b[', 'a1b2-c3d4', '\x1b[31']) {
      expect(handleAnsiOutput(sequence).map((r) => r.text).join(), sequence);
    }
  });

  test('Empty sequence output', () {
    for (final sequence in ['', '\x1b[;m', '\x1b[1;;m', '\x1b[m', '\x1b[99m']) {
      final run = _single(sequence);
      expect(run.classes, isEmpty, reason: sequence);
    }
    // The other terminators end (and hide) a sequence too.
    for (final terminator in 'ABCDHIJKfhmpsu'.split('')) {
      expect(handleAnsiOutput('\x1b[content${terminator}content').single.text, 'content');
    }
  });

  test('calcANSI8bitColor', () {
    for (var i = -10.0; i <= 15; i += 0.5) {
      expect(calcAnsi8bitColor(i), isNull);
    }
    for (var i = 16.5; i < 254; i += 1) {
      expect(calcAnsi8bitColor(i), isNull);
    }
    for (var i = 256.0; i < 300; i += 0.5) {
      expect(calcAnsi8bitColor(i), isNull);
    }
    for (var red = 0; red <= 5; red++) {
      for (var green = 0; green <= 5; green++) {
        for (var blue = 0; blue <= 5; blue++) {
          final color = calcAnsi8bitColor(16 + red * 36 + green * 6 + blue)!;
          expect(color.r, (red * (255 / 5)).round());
          expect(color.g, (green * (255 / 5)).round());
          expect(color.b, (blue * (255 / 5)).round());
        }
      }
    }
    for (var i = 232; i <= 255; i++) {
      final gray = calcAnsi8bitColor(i)!;
      expect([gray.g, gray.b], [gray.r, gray.r]);
      expect(gray.r, ((i - 232) / 23 * 255).round());
    }
  });

  test('the runs drawn: styles and theme colors made to stand out', () {
    const base = TextStyle(fontSize: 13, color: Color(0xFFCCCCCC));
    const background = Color(0xFF181818);
    final span = ansiTextSpan(
      '\x1b[1;31mred\x1b[0m \x1b[3;4mu\x1b[0m\x1b[2mdim\x1b[0m\x1b[38;2;10;20;30mrgb',
      base,
      background: background,
    );
    final runs = span.children!.cast<TextSpan>();
    expect([for (final r in runs) r.text], ['red', ' ', 'u', 'dim', 'rgb']);
    expect(runs[0].style!.fontWeight, FontWeight.bold);
    // The theme's red, far enough from the background (ratio 4).
    final red = runs[0].style!.color!;
    expect(red, isNot(base.color));
    expect(red.r, greaterThan(red.g));
    expect(runs[1].style!.color, base.color);
    expect(runs[2].style!.fontStyle, FontStyle.italic);
    expect(runs[2].style!.decoration, TextDecoration.underline);
    expect(runs[3].style!.color!.a, closeTo(0.4, 0.01));
    // A color of its own is drawn as it is.
    expect(runs[4].style!.color, const Color(0xFF0A141E));
  });
}
