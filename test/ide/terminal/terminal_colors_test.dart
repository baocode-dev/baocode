import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/terminal_colors.dart';

void main() {
  group('TerminalColors', () {
    test("are Dark 2026's", () {
      expect(TerminalColors.background, const Color(0xFF191A1B));
      expect(TerminalColors.foreground, const Color(0xFFCCCCCC));
      expect(TerminalColors.cursorForeground, const Color(0xFFBFBFBF));
      expect(TerminalColors.selectionBackground, const Color(0x333994BC));
      expect(
        TerminalColors.inactiveSelectionBackground,
        const Color(0xFF3A3D41),
      );
      expect(TerminalColors.selectionForeground, isNull);
    });

    test('the 16 ANSI colors are the registry dark defaults', () {
      expect(TerminalColors.ansi, hasLength(16));
      expect(TerminalColors.ansi[0], const Color(0xFF000000));
      expect(TerminalColors.ansi[1], const Color(0xFFCD3131));
      expect(TerminalColors.ansi[2], const Color(0xFF0DBC79));
      expect(TerminalColors.ansi[8], const Color(0xFF666666));
      expect(TerminalColors.ansi[15], const Color(0xFFE5E5E5));
    });

    test('the opaque match background is the highlight on the background', () {
      final alpha = TerminalColors.findMatchHighlightBackground.a;
      int channel(double fg, double bg) =>
          ((fg * alpha + bg * (1 - alpha)) * 255).floor();
      const fg = TerminalColors.findMatchHighlightBackground;
      const bg = TerminalColors.background;
      expect(
        TerminalColors.findMatchHighlightBackgroundOpaque,
        Color.fromARGB(
          0xFF,
          channel(fg.r, bg.r),
          channel(fg.g, bg.g),
          channel(fg.b, bg.b),
        ),
      );
    });
  });

  group('terminalAnsiColors', () {
    final palette = terminalAnsiColors();

    test('has 256 colors, the theme first', () {
      expect(palette, hasLength(256));
      expect(palette.sublist(0, 16), TerminalColors.ansi);
    });

    test('has the 6x6x6 color cube', () {
      expect(palette[16], const Color(0xFF000000));
      expect(palette[17], const Color(0xFF00005F));
      expect(palette[21], const Color(0xFF0000FF));
      expect(palette[22], const Color(0xFF005F00));
      expect(palette[52], const Color(0xFF5F0000));
      expect(palette[196], const Color(0xFFFF0000));
      expect(palette[208], const Color(0xFFFF8700));
      expect(palette[231], const Color(0xFFFFFFFF));
    });

    test('has the grayscale ramp', () {
      expect(palette[232], const Color(0xFF080808));
      expect(palette[233], const Color(0xFF121212));
      expect(palette[244], const Color(0xFF808080));
      expect(palette[255], const Color(0xFFEEEEEE));
    });

    test('builds on other 16 colors', () {
      final other = List.filled(16, const Color(0xFF123456));
      final colors = terminalAnsiColors(other);
      expect(colors.sublist(0, 16), other);
      expect(colors.sublist(16), palette.sublist(16));
    });
  });
}
