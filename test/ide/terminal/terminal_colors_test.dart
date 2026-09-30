// Tests of the terminal's colors: Dark 2026's constants, the palette, and
// TerminalColorTheme.resolve as VS Code's getXtermTheme, _updateFindColors
// and the decorations take a theme's colors (Dark 2026's and a light one's,
// through xterm.js' ThemeService and the renderer's minimum contrast).

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/platform/theme/common/theme.dart'
    show ColorScheme;
import 'package:monad/ide/terminal/terminal_colors.dart';
import 'package:monad/ide/terminal/terminal_render_adapter.dart';
import 'package:monad/ide/terminal/terminal_render_theme.dart';
import 'package:monad/ide/terminal/terminal_renderer.dart';
import 'package:monad/ide/terminal/xterm/headless/terminal.dart' as headless;

import 'terminal_color_themes.dart';

/// A terminal with [theme]'s colors, its colors as xterm.js' ThemeService
/// resolves them, and its renderer.
({
  headless.Terminal terminal,
  TerminalCoreSource source,
  TerminalRenderer renderer,
})
_terminal(TerminalColorTheme theme) {
  final terminal = headless.Terminal(
    vscodeTerminalOptions(cols: 10, rows: 2, theme: theme)
      ..fontFamily = 'FlutterTest'
      ..fontSize = 10
      ..showCursorImmediately = true,
  );
  final source = TerminalCoreSource(terminal);
  final renderer = TerminalRenderer(source, onNeedsPaint: () {});
  addTearDown(() {
    renderer.dispose();
    source.dispose();
    terminal.dispose();
  });
  return (terminal: terminal, source: source, renderer: renderer);
}

/// Brings the renderer's rows up to date.
void _paint(TerminalRenderer renderer) {
  final recorder = PictureRecorder();
  renderer.paint(Canvas(recorder), Offset.zero);
  recorder.endRecording().dispose();
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance() + 0.05;
  final lb = b.computeLuminance() + 0.05;
  return math.max(la, lb) / math.min(la, lb);
}

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

  group('TerminalColorTheme.dark2026', () {
    final theme = TerminalColorTheme.dark2026;

    test('is the constants', () {
      expect(theme.type, ColorScheme.dark);
      expect(theme.foreground, TerminalColors.foreground);
      expect(theme.background, TerminalColors.background);
      expect(theme.cursorForeground, TerminalColors.cursorForeground);
      expect(theme.cursorBackground, TerminalColors.cursorBackground);
      expect(theme.selectionBackground, TerminalColors.selectionBackground);
      expect(
        theme.inactiveSelectionBackground,
        TerminalColors.inactiveSelectionBackground,
      );
      expect(
        theme.inactiveSelectionBackgroundTransparent,
        TerminalColors.inactiveSelectionBackgroundTransparent,
      );
      expect(theme.selectionForeground, TerminalColors.selectionForeground);
      expect(theme.findMatchBackground, TerminalColors.findMatchBackground);
      expect(theme.findMatchBorder, TerminalColors.findMatchBorder);
      expect(
        theme.findMatchHighlightBackground,
        TerminalColors.findMatchHighlightBackground,
      );
      expect(
        theme.findMatchHighlightBackgroundOpaque,
        TerminalColors.findMatchHighlightBackgroundOpaque,
      );
      expect(
        theme.findMatchHighlightBorder,
        TerminalColors.findMatchHighlightBorder,
      );
      expect(
        theme.hoverHighlightBackground,
        TerminalColors.hoverHighlightBackground,
      );
      expect(
        theme.commandDecorationDefaultBackground,
        TerminalColors.commandDecorationDefaultBackground,
      );
      expect(
        theme.commandDecorationSuccessBackground,
        TerminalColors.commandDecorationSuccessBackground,
      );
      expect(
        theme.commandDecorationErrorBackground,
        TerminalColors.commandDecorationErrorBackground,
      );
      expect(
        theme.overviewRulerCursorForeground,
        TerminalColors.overviewRulerCursorForeground,
      );
      expect(
        theme.overviewRulerFindMatchForeground,
        TerminalColors.overviewRulerFindMatchForeground,
      );
      expect(theme.overviewRulerBorder, TerminalColors.overviewRulerBorder);
      expect(theme.border, TerminalColors.border);
      expect(theme.dropBackground, TerminalColors.dropBackground);
      expect(theme.initialHintForeground, TerminalColors.initialHintForeground);
      expect(
        theme.scrollbarSliderBackground,
        TerminalColors.scrollbarSliderBackground,
      );
      expect(
        theme.scrollbarSliderHoverBackground,
        TerminalColors.scrollbarSliderHoverBackground,
      );
      expect(
        theme.scrollbarSliderActiveBackground,
        TerminalColors.scrollbarSliderActiveBackground,
      );
      expect(theme.ansi, TerminalColors.ansi);
      expect(theme.palette, terminalAnsiColors());
    });

    test('is the default', () {
      expect(terminalColorTheme.value, same(theme));
      expect(
        TerminalColorTheme.resolve(
          (id) =>
              id == 'terminal.foreground' ? TerminalColors.foreground : null,
          type: ColorScheme.dark,
        ),
        isNot(theme),
      );
    });

    test('hands xterm.js CSS as VS Code does: the alpha to two decimals', () {
      final xterm = theme.toXtermTheme();
      expect(xterm.background, '#191a1b');
      expect(xterm.foreground, '#cccccc');
      expect(xterm.cursor, '#bfbfbf');
      expect(xterm.cursorAccent, '#191a1b');
      expect(xterm.selectionBackground, 'rgba(57, 148, 188, 0.2)');
      expect(xterm.selectionInactiveBackground, '#3a3d41');
      expect(xterm.selectionForeground, isNull);
      expect(xterm.overviewRulerBorder, '#2a2b2c');
      expect(xterm.scrollbarSliderBackground, 'rgba(168, 169, 170, 0.52)');
      // #A8A9AA90: 0.565 to two decimals, 0x8F in xterm.js.
      expect(xterm.scrollbarSliderHoverBackground, 'rgba(168, 169, 170, 0.56)');
      expect(
        xterm.scrollbarSliderActiveBackground,
        'rgba(168, 169, 170, 0.61)',
      );
      expect([
        xterm.black,
        xterm.red,
        xterm.green,
        xterm.yellow,
        xterm.blue,
        xterm.magenta,
        xterm.cyan,
        xterm.white,
        xterm.brightBlack,
        xterm.brightRed,
        xterm.brightGreen,
        xterm.brightYellow,
        xterm.brightBlue,
        xterm.brightMagenta,
        xterm.brightCyan,
        xterm.brightWhite,
      ], TerminalColors.ansi.map(cssColor));
      expect(xterm.extendedAnsi, isNull);
      expect(
        theme.toXtermTheme(hideOverviewRuler: true).overviewRulerBorder,
        '#0000',
      );
      // A new one each time: xterm.js' option is the object.
      expect(theme.toXtermTheme(), isNot(same(theme.toXtermTheme())));
    });

    test("through xterm.js' ThemeService", () {
      final (terminal: _, :source, renderer: _) = _terminal(theme);
      final colors = source.themeService.colors;
      expect(colors.foreground.rgba, 0xCCCCCCFF);
      expect(colors.background.rgba, 0x191A1BFF);
      expect(colors.cursor.rgba, 0xBFBFBFFF);
      expect(colors.cursorAccent.rgba, 0x191A1BFF);
      expect(colors.selectionBackgroundTransparent.rgba, 0x3994BC33);
      expect(
        argbOfRgba(colors.selectionInactiveBackgroundTransparent.rgba),
        TerminalColors.inactiveSelectionBackgroundTransparent.toARGB32(),
      );
      expect(colors.scrollbarSliderBackground.rgba, 0xA8A9AA85);
      // 0x90 is 0.56 in VS Code's CSS: one step off the theme's.
      expect(colors.scrollbarSliderHoverBackground.rgba, 0xA8A9AA8F);
      expect(colors.scrollbarSliderActiveBackground.rgba, 0xA8A9AA9C);
      expect(colors.overviewRulerBorder.rgba, 0x2A2B2CFF);
      for (var i = 0; i < 256; i++) {
        expect(argbOfRgba(colors.ansi[i].rgba), theme.palette[i].toARGB32());
      }
    });

    test("gives the search addon _updateFindColors' decorations", () {
      final decorations = theme.toSearchDecorations();
      expect(decorations.activeMatchBackground, 'rgba(39, 103, 130, 0.56)');
      expect(decorations.activeMatchBorder, 'transparent');
      expect(
        decorations.activeMatchColorOverviewRuler,
        'rgba(160, 160, 160, 0.8)',
      );
      // Blended onto the background: decorations take no alpha.
      expect(decorations.matchBackground, '#20404e');
      expect(decorations.matchBorder, 'transparent');
      expect(decorations.matchOverviewRuler, 'rgba(58, 148, 188, 0.6)');
    });

    test('reads the color ids VS Code reads', () {
      final read = <String>[];
      TerminalColorTheme.resolve((id) {
        read.add(id);
        return null;
      }, type: ColorScheme.dark);
      expect(read, [
        // getXtermTheme
        'terminal.foreground',
        'terminal.background',
        'panel.background',
        'terminalCursor.foreground',
        'terminalCursor.background',
        'terminal.selectionBackground',
        'terminal.inactiveSelectionBackground',
        'terminal.selectionForeground',
        'terminalOverviewRuler.border',
        'scrollbarSlider.activeBackground',
        'scrollbarSlider.background',
        'scrollbarSlider.hoverBackground',
        ...ansiColorIdentifiers,
        // _updateFindColors
        'terminal.findMatchBackground',
        'terminal.findMatchBorder',
        'terminalOverviewRuler.cursorForeground',
        'terminal.findMatchHighlightBackground',
        'terminal.findMatchHighlightBorder',
        'terminalOverviewRuler.findMatchForeground',
        // The decorations
        'terminalCommandDecoration.defaultBackground',
        'terminalCommandDecoration.successBackground',
        'terminalCommandDecoration.errorBackground',
        // terminal.css
        'terminal.hoverHighlightBackground',
        'terminal.border',
        'terminal.dropBackground',
        'terminal.initialHintForeground',
      ]);
      expect(ansiColorIdentifiers.first, 'terminal.ansiBlack');
      expect(ansiColorIdentifiers.last, 'terminal.ansiBrightWhite');
    });
  });

  group('TerminalColorTheme.resolve', () {
    test('a light theme', () {
      final theme = light2026;
      expect(theme.type, ColorScheme.light);
      // No terminal.background: the panel's.
      expect(theme.background, const Color(0xFFFAFAFD));
      expect(theme.foreground, const Color(0xFF3B3B3B));
      expect(theme.cursorForeground, const Color(0xFF202020));
      expect(theme.cursorBackground, const Color(0xFFFFFFFF));
      expect(theme.selectionForeground, isNull);
      // Opaque: xterm.js draws it at 0.3 opacity.
      expect(
        theme.inactiveSelectionBackgroundTransparent,
        const Color(0x4DE5EBF1),
      );
      expect(theme.findMatchHighlightBackgroundOpaque, const Color(0xFFE0EBF8));
      expect(theme.ansi[3], const Color(0xFF949800));
      expect(theme.palette.sublist(0, 16), theme.ansi);
      expect(theme.palette.sublist(16), terminalAnsiColors().sublist(16));
      expect(theme, isNot(TerminalColorTheme.dark2026));

      final xterm = theme.toXtermTheme();
      expect(xterm.background, '#fafafd');
      expect(xterm.foreground, '#3b3b3b');
      expect(xterm.cursor, '#202020');
      expect(xterm.cursorAccent, '#ffffff');
      expect(xterm.selectionBackground, 'rgba(0, 105, 204, 0.15)');
      expect(xterm.selectionInactiveBackground, '#e5ebf1');
      expect(xterm.selectionForeground, isNull);
      expect(xterm.overviewRulerBorder, '#f0f1f2');
      expect(xterm.scrollbarSliderBackground, 'rgba(100, 100, 100, 0.75)');
      expect(xterm.scrollbarSliderHoverBackground, 'rgba(100, 100, 100, 0.82)');
      expect(
        xterm.scrollbarSliderActiveBackground,
        'rgba(100, 100, 100, 0.88)',
      );
      expect(xterm.yellow, '#949800');

      final decorations = theme.toSearchDecorations();
      expect(decorations.activeMatchBackground, 'rgba(0, 105, 204, 0.25)');
      expect(decorations.activeMatchBorder, 'transparent');
      expect(
        decorations.activeMatchColorOverviewRuler,
        'rgba(160, 160, 160, 0.8)',
      );
      expect(decorations.matchBackground, '#e0ebf8');
      expect(decorations.matchOverviewRuler, 'rgba(0, 105, 204, 0.6)');
    });

    test("a light theme through xterm.js' ThemeService", () {
      final (terminal: _, :source, renderer: _) = _terminal(light2026);
      final colors = source.themeService.colors;
      expect(colors.foreground.rgba, 0x3B3B3BFF);
      expect(colors.background.rgba, 0xFAFAFDFF);
      expect(colors.cursor.rgba, 0x202020FF);
      expect(colors.cursorAccent.rgba, 0xFFFFFFFF);
      expect(colors.selectionBackgroundTransparent.rgba, 0x0069CC26);
      // The inactive selection is opaque: at 0.3 opacity, and its opaque
      // form (blended before that) is itself.
      expect(colors.selectionInactiveBackgroundTransparent.rgba, 0xE5EBF14D);
      expect(colors.selectionInactiveBackgroundOpaque.rgba, 0xE5EBF1FF);
      expect(colors.selectionForeground, isNull);
      // The alphas VS Code rounds to two decimals: 0xC0 is 0.75, 0xBF.
      expect(colors.scrollbarSliderBackground.rgba, 0x646464BF);
      expect(colors.scrollbarSliderHoverBackground.rgba, 0x646464D1);
      expect(colors.scrollbarSliderActiveBackground.rgba, 0x646464E0);
      expect(colors.overviewRulerBorder.rgba, 0xF0F1F2FF);
      expect(colors.ansi[3].rgba, 0x949800FF);
      expect(colors.ansi[11].rgba, 0xB5BA00FF);
      expect(colors.ansi[16].rgba, 0x000000FF);
      expect(colors.ansi[255].rgba, 0xEEEEEEFF);
    });

    test('the minimum contrast ratio against a light background', () {
      final light = _terminal(light2026);
      light.terminal.writeSync('\x1b[33mY\x1b[0mT');
      _paint(light.renderer);
      const background = Color(0xFFFAFAFD);
      final yellow = light.renderer.debugCellColors(0, 0)!.fg!;
      // #949800 is 3:1 on it: darkened to 4.5:1.
      expect(yellow, isNot(const Color(0xFF949800)));
      expect(_contrast(yellow, background), greaterThanOrEqualTo(4.5));
      expect(light.renderer.debugCellColors(1, 0)!.fg, const Color(0xFF3B3B3B));

      // Dark 2026's yellow is far enough from its background.
      final dark = _terminal(TerminalColorTheme.dark2026);
      dark.terminal.writeSync('\x1b[33mY');
      _paint(dark.renderer);
      expect(dark.renderer.debugCellColors(0, 0)!.fg, const Color(0xFFE5E510));
    });

    test('what a theme lacks: upstream fallbacks', () {
      final theme = TerminalColorTheme.resolve(
        (id) => switch (id) {
          'terminal.foreground' => const Color(0xFF111111),
          'panel.background' => const Color(0xFF222222),
          'terminal.findMatchHighlightBackground' => const Color(0x80FFFFFF),
          _ => null,
        },
        type: ColorScheme.highContrastDark,
      );
      expect(theme.type, ColorScheme.highContrastDark);
      // The cursor is the foreground, the character under it the background.
      expect(theme.cursorForeground, const Color(0xFF111111));
      expect(theme.cursorBackground, const Color(0xFF222222));
      // The default palette's.
      expect(theme.ansi, TerminalColors.ansi);
      // xterm.js' default selection, unfocused too.
      expect(
        theme.inactiveSelectionBackgroundTransparent,
        const Color(0x4DFFFFFF),
      );
      expect(theme.findMatchHighlightBackgroundOpaque, const Color(0xFF909090));

      final xterm = theme.toXtermTheme();
      expect(xterm.selectionBackground, isNull);
      expect(xterm.selectionInactiveBackground, isNull);
      expect(xterm.overviewRulerBorder, isNull);
      expect(xterm.scrollbarSliderBackground, isNull);

      final decorations = theme.toSearchDecorations();
      expect(decorations.activeMatchBackground, isNull);
      expect(decorations.activeMatchBorder, 'transparent');
      expect(decorations.activeMatchColorOverviewRuler, 'transparent');
      expect(decorations.matchBackground, '#909090');
      expect(decorations.matchBorder, 'transparent');
      expect(decorations.matchOverviewRuler, 'transparent');

      // No background, no blended match background.
      final bare = TerminalColorTheme.resolve(
        (id) => id == 'terminal.findMatchHighlightBackground'
            ? const Color(0x80FFFFFF)
            : null,
        type: ColorScheme.dark,
      );
      expect(bare.background, isNull);
      expect(bare.findMatchHighlightBackgroundOpaque, isNull);
      expect(bare.toSearchDecorations().matchBackground, isNull);
    });
  });

  test("cssColor is VS Code's Color.toString()", () {
    expect(cssColor(const Color(0xFF1B81A8)), '#1b81a8');
    expect(cssColor(const Color(0x40FFFFFF)), 'rgba(255, 255, 255, 0.25)');
    expect(cssColor(const Color(0x00000000)), 'rgba(0, 0, 0, 0)');
    // VS Code keeps the alpha to three decimals first: 0x58 is 0.345,
    // which is 0.34.
    expect(cssColor(const Color(0x58000000)), 'rgba(0, 0, 0, 0.34)');
    expect(
      cssColor(const Color.from(alpha: 0.999, red: 1, green: 0, blue: 0)),
      'rgba(255, 0, 0, 1)',
    );
  });
}
