// Tests of terminals following the workbench's color theme
// (terminalColorTheme), as VS Code's follow `onDidColorThemeChange`: a live
// terminal recolors (its grid, its scrollbar colors, its command marks and
// their overview ruler marks, its current find match), the colors escape
// sequences set give way to the new theme as in xterm.js, and the listeners
// go with the terminal. On fake processes only.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/terminal_colors.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/ide/terminal/terminal_service.dart';
import 'package:baocode/ide/terminal/terminal_tabs.dart';
import 'package:baocode/ide/terminal/terminal_view.dart';
import 'package:baocode/theme/codicons.dart';

import 'fake_pty.dart';
import 'fake_terminal.dart';
import 'terminal_color_themes.dart';

/// A terminal on a fake process in the test font at 10px (10 by 10 cells),
/// without the minimum contrast ratio.
({TerminalInstance terminal, List<FakePty> started}) _terminal() {
  final started = <FakePty>[];
  final terminal = TerminalInstance(
    id: 1,
    root: '/project',
    backend: fakeTerminalBackend(started),
  );
  terminal.xterm.options
    ..fontFamily = 'FlutterTest'
    ..fontSize = 10
    ..minimumContrastRatio = 1;
  return (terminal: terminal, started: started);
}

/// Lets the emulator parse what was written (on timers, in 12ms slices).
Future<void> _parsed(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 1));

Future<_Pixels> _capture(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final pixels = _Pixels(image.width, data!);
    image.dispose();
    return pixels;
  }))!;
}

class _Pixels {
  _Pixels(this.width, this.data);

  final int width;
  final ByteData data;

  Color at(int x, int y) {
    final i = (y * width + x) * 4;
    return Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
  }
}

/// VS Code's shell integration sequences (OSC 633) of a command.
String _command(String line, int exitCode) =>
    '\x1b]633;A\x07\$ \x1b]633;B\x07$line\r\n\x1b]633;C\x07'
    'out\r\n\x1b]633;D;$exitCode\x07';

void main() {
  tearDown(() => terminalColorTheme.value = TerminalColorTheme.dark2026);

  testWidgets('a live terminal recolors when the theme changes, and back', (
    tester,
  ) async {
    final (:terminal, :started) = _terminal();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: boundary,
            child: SizedBox(
              width: 600,
              height: 300,
              child: TerminalView(terminal),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      terminal.dispose();
    });
    // Line 0 the command (marked in the gutter), 1 its output, 2 text.
    started.single.emitText('${_command('true', 0)}hi \x1b[32mG\x1b[0m');
    await _parsed(tester);
    await tester.pump();

    // The grid is at (20, 8), inside VS Code's padding.
    Future<void> expectColors({
      required Color foreground,
      required Color background,
      required Color green,
      required Color mark,
      required String markCss,
    }) async {
      final pixels = await _capture(tester, boundary);
      expect(pixels.at(25, 33), foreground); // h
      expect(pixels.at(55, 33), green); // G
      expect(pixels.at(300, 150), background);
      expect(pixels.at(10, 150), background); // the padding
      final colors = terminal.source.themeService.colors;
      expect(colors.background.rgba >>> 8, background.toARGB32() & 0xFFFFFF);
      final decoration = terminal.shellIntegration!.decorations.single;
      expect(decoration.color, mark);
      expect(
        decoration.decoration.options.overviewRulerOptions!.color,
        markCss,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Codicons.circleFilled)).color,
        mark,
      );
    }

    await expectColors(
      foreground: const Color(0xFFCCCCCC),
      background: const Color(0xFF191A1B),
      green: const Color(0xFF0DBC79),
      mark: const Color(0xFF1B81A8),
      markCss: '#1b81a8',
    );
    final scrollbar =
        terminal.source.themeService.colors.scrollbarSliderBackground;
    expect(scrollbar.rgba, 0xA8A9AA85);

    terminalColorTheme.value = light2026;
    await tester.pump();
    await expectColors(
      foreground: const Color(0xFF3B3B3B),
      background: const Color(0xFFFAFAFD),
      green: const Color(0xFF107C10),
      mark: const Color(0xFF2090D3),
      markCss: '#2090d3',
    );
    expect(
      terminal.source.themeService.colors.scrollbarSliderBackground.rgba,
      0x646464BF,
    );

    terminalColorTheme.value = TerminalColorTheme.dark2026;
    await tester.pump();
    await expectColors(
      foreground: const Color(0xFFCCCCCC),
      background: const Color(0xFF191A1B),
      green: const Color(0xFF0DBC79),
      mark: const Color(0xFF1B81A8),
      markCss: '#1b81a8',
    );
    // Command detection's cursor-move debounce (500ms, upstream's).
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a new theme replaces the colors escape sequences set, as '
      "xterm.js' does; they restore to the new theme's", (tester) async {
    final (:terminal, :started) = _terminal();
    addTearDown(terminal.dispose);
    await tester.pump();
    final pty = started.single;
    final colors = terminal.source.themeService;

    pty.emitText(
      '\x1b]10;rgb:11/22/33\x07\x1b]11;rgb:ff/00/00\x07'
      '\x1b]12;rgb:00/ff/00\x07\x1b]4;2;rgb:00/00/ff\x07',
    );
    await _parsed(tester);
    expect(colors.colors.foreground.rgba, 0x112233FF);
    expect(colors.colors.background.rgba, 0xFF0000FF);
    expect(colors.colors.cursor.rgba, 0x00FF00FF);
    expect(colors.colors.ansi[2].rgba, 0x0000FFFF);

    terminalColorTheme.value = light2026;
    expect(colors.colors.foreground.rgba, 0x3B3B3BFF);
    expect(colors.colors.background.rgba, 0xFAFAFDFF);
    expect(colors.colors.cursor.rgba, 0x202020FF);
    expect(colors.colors.ansi[2].rgba, 0x107C10FF);

    // Set again, then restored: to the new theme's.
    pty.emitText('\x1b]11;rgb:ff/00/00\x07\x1b]4;2;rgb:00/00/ff\x07');
    await _parsed(tester);
    expect(colors.colors.background.rgba, 0xFF0000FF);
    pty.emitText('\x1b]111\x07\x1b]104\x07');
    await _parsed(tester);
    expect(colors.colors.background.rgba, 0xFAFAFDFF);
    expect(colors.colors.ansi[2].rgba, 0x107C10FF);

    // A report says the new theme's.
    pty.emitText('\x1b]11;?\x07');
    await _parsed(tester);
    expect(pty.written, contains('\x1b]11;rgb:fafa/fafa/fdfd'));
  });

  testWidgets('the current find match takes the new colors while the find '
      'widget shows, as VS Code finds again', (tester) async {
    final (:terminal, :started) = _terminal();
    addTearDown(terminal.dispose);
    await tester.pump();
    started.single.emitText('foo bar foo\r\n');
    await _parsed(tester);
    final find = terminal.find
      ..reveal()
      ..inputValue = 'foo';
    List<String?> layer(String layer) => [
      for (final d in terminal.decorations.decorations)
        if ((d.options.layer ?? 'bottom') == layer) d.options.backgroundColor,
    ];
    expect(layer('top'), ['rgba(39, 103, 130, 0.56)']);
    expect(layer('bottom'), ['#20404e', '#20404e']);

    terminalColorTheme.value = light2026;
    expect(find.decorations.activeMatchBackground, 'rgba(0, 105, 204, 0.25)');
    expect(find.decorations.matchBackground, '#e0ebf8');
    // Upstream searches again for the same query: the current match is
    // decorated anew, the others keep theirs.
    expect(layer('top'), ['rgba(0, 105, 204, 0.25)']);
    expect(layer('bottom'), ['#20404e', '#20404e']);

    // Hidden, a new theme does not search.
    find.hide();
    expect(terminal.decorations.decorations, isEmpty);
    terminalColorTheme.value = TerminalColorTheme.dark2026;
    expect(terminal.decorations.decorations, isEmpty);
    expect(find.decorations.matchBackground, '#20404e');
    // With the search's line cache timer.
    terminal.dispose();
  });

  testWidgets('a terminal takes the theme it is made in', (tester) async {
    terminalColorTheme.value = light2026;
    final (:terminal, started: _) = _terminal();
    addTearDown(terminal.dispose);
    expect(terminal.source.themeService.colors.background.rgba, 0xFAFAFDFF);
    expect(terminal.find.decorations.matchBackground, '#e0ebf8');
  });

  testWidgets("the tabs' border is the theme's terminal.border", (
    tester,
  ) async {
    final terminals = TerminalService(
      root: '/project',
      backend: fakeTerminalBackend([]),
    );
    terminals
      ..create()
      ..create();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: TerminalTabs.width,
          height: 200,
          child: TerminalTabs(terminals: terminals, onNew: () {}),
        ),
      ),
    );
    Color border() {
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(TerminalTabs),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return ((box.decoration as BoxDecoration).border! as Border).left.color;
    }

    expect(border(), const Color(0xFF2A2B2C));
    terminalColorTheme.value = light2026;
    await tester.pump();
    expect(border(), const Color(0xFFF0F1F2));

    await tester.pumpWidget(const SizedBox());
    for (final terminal in terminals.instances.toList()) {
      terminal.dispose();
    }
    terminals.dispose();
  });

  testWidgets('the listeners go with the terminal', (tester) async {
    final (:terminal, started: _) = _terminal();
    await tester.pump();
    // Its xterm's, its find's and its decoration addon's.
    expect(terminal.shellIntegration, isNotNull);
    terminal.find;
    // ignore: invalid_use_of_protected_member
    expect(terminalColorTheme.hasListeners, isTrue);
    terminal.dispose();
    // ignore: invalid_use_of_protected_member
    expect(terminalColorTheme.hasListeners, isFalse);
    terminalColorTheme.value = light2026;
  });
}
