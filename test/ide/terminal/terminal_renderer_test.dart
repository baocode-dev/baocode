// Tests of the terminal renderer: what it paints for known screens, in
// pixels (the test font's glyphs fill their em square, so a cell of text is
// a solid block of its color), and which rows it rebuilds.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/terminal_colors.dart';
import 'package:monad/ide/terminal/terminal_render_adapter.dart';
import 'package:monad/ide/terminal/terminal_render_source.dart';
import 'package:monad/ide/terminal/terminal_render_theme.dart';
import 'package:monad/ide/terminal/terminal_renderer.dart';
import 'package:monad/ide/terminal/xterm/addons/addon_unicode11/unicode_v11.dart';
import 'package:monad/ide/terminal/xterm/common/buffer/attribute_data.dart';
import 'package:monad/ide/terminal/xterm/common/buffer/constants.dart';
import 'package:monad/ide/terminal/xterm/common/services/buffer_service.dart';
import 'package:monad/ide/terminal/xterm/common/services/core_service.dart';
import 'package:monad/ide/terminal/xterm/common/services/decoration_service.dart';
import 'package:monad/ide/terminal/xterm/common/services/log_service.dart';
import 'package:monad/ide/terminal/xterm/common/services/options_service.dart';
import 'package:monad/ide/terminal/xterm/headless/terminal.dart' as headless;
import 'package:monad/ide/terminal/xterm/typings/xterm.dart';

const _fg = Color(0xFFCCCCCC); // Dark 2026 terminal.foreground
const _bg = Color(0xFF191A1B); // terminal.background
const _cursor = Color(0xFFBFBFBF); // terminalCursor.foreground

/// VS Code's options with the test font at 10px: 10x10 cells at dpr 1.
ITerminalOptions _options({int cols = 10, int rows = 4}) =>
    vscodeTerminalOptions(cols: cols, rows: rows)
      ..fontFamily = 'FlutterTest'
      ..fontSize = 10
      ..minimumContrastRatio = 1
      ..showCursorImmediately = true;

class _Pixels {
  _Pixels(this.width, this.height, this.data, this.dpr);

  final int width;
  final int height;
  final ByteData data;
  final double dpr;

  /// The color at logical pixel ([x], [y]) (its device pixel's top left).
  Color at(num x, num y) {
    final dx = (x * dpr).floor();
    final dy = (y * dpr).floor();
    final i = (dy * width + dx) * 4;
    return Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
  }

  /// The color at device pixel ([x], [y]).
  Color device(int x, int y) {
    final i = (y * width + x) * 4;
    return Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
  }
}

class _Harness {
  _Harness({
    int cols = 10,
    int rows = 4,
    void Function(ITerminalOptions options)? configure,
    double devicePixelRatio = 1,
    bool focused = true,
  }) {
    final options = _options(cols: cols, rows: rows);
    configure?.call(options);
    terminal = headless.Terminal(options);
    source = TerminalCoreSource(terminal);
    renderer = TerminalRenderer(
      source,
      onNeedsPaint: () => paintRequests++,
      devicePixelRatio: devicePixelRatio,
      isFocused: focused,
    );
  }

  late final headless.Terminal terminal;
  late final TerminalCoreSource source;
  late final TerminalRenderer renderer;
  int paintRequests = 0;

  void write(String data) => terminal.writeSync(data);

  /// Paints into a recording without reading pixels back.
  void paintOnly() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final dims = renderer.dimensions;
    canvas.clipRect(
      Rect.fromLTWH(
        0,
        0,
        source.cols * dims.cellWidth,
        source.rows * dims.cellHeight,
      ),
    );
    renderer.paint(canvas, Offset.zero);
    recorder.endRecording().dispose();
  }

  Future<_Pixels> paint() async {
    final dims = renderer.dimensions;
    final dpr = dims.devicePixelRatio;
    final width = source.cols * dims.deviceCellWidth;
    final height = source.rows * dims.deviceCellHeight;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);
    final bounds = Rect.fromLTWH(0, 0, width / dpr, height / dpr);
    canvas
      ..clipRect(bounds)
      ..drawRect(bounds, Paint()..color = renderer.backgroundColor);
    renderer.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    return _Pixels(width, height, data!, dpr);
  }

  void dispose() {
    renderer.dispose();
    source.dispose();
    terminal.dispose();
  }
}

void main() {
  group('TerminalRenderer', () {
    test('paints text, backgrounds and the block cursor in cells', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.write('AB\x1b[44m C\x1b[0m');
      final pixels = await h.paint();
      expect(h.renderer.dimensions.cellWidth, 10);
      expect(h.renderer.dimensions.cellHeight, 10);
      expect(pixels.at(5, 5), _fg);
      expect(pixels.at(15, 5), _fg);
      final blue = Color(terminalAnsiColors()[4].toARGB32());
      // A background run under a space and under text.
      expect(pixels.at(25, 5), blue);
      expect(pixels.at(30, 0), isNot(blue)); // the C glyph covers its cell
      expect(pixels.at(35, 5), _fg);
      // The cursor, after the text: a block in the cursor color.
      expect(pixels.at(45, 5), _cursor);
      expect(pixels.at(55, 5), _bg);
      expect(h.renderer.debugRowText(0), 'AB C');
    });

    test('resolves palette, 256 and truecolor foregrounds', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.write('\x1b[31mR\x1b[38;5;208mO\x1b[38;2;1;2;3mT\x1b[48;5;21mU');
      final ansi = terminalAnsiColors();
      expect(h.renderer.debugCellColors(0, 0), isNull); // before a paint
      final pixels = await h.paint();
      expect(pixels.at(5, 5), Color(ansi[1].toARGB32()));
      expect(pixels.at(15, 5), Color(ansi[208].toARGB32()));
      expect(pixels.at(25, 5), const Color(0xFF010203));
      expect(h.renderer.debugCellColors(3, 0)!.bg, Color(ansi[21].toARGB32()));
    });

    test('inverse swaps the colors, bold is bright, dim is half', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.write('\x1b[7mI\x1b[0m\x1b[1;31mB\x1b[0m\x1b[2mD\x1b[0m\x1b[8mH');
      final pixels = await h.paint();
      final colors = h.renderer.debugCellColors;
      expect(colors(0, 0)!.bg, _fg);
      expect(colors(0, 0)!.fg, _bg);
      expect(pixels.at(5, 5), _bg);
      expect(colors(1, 0)!.fg, Color(terminalAnsiColors()[9].toARGB32()));
      expect(colors(2, 0)!.fg, _fg.withAlpha(128));
      // Invisible text draws nothing.
      expect(colors(3, 0)!.fg, isNull);
      expect(pixels.at(35, 5), _bg);
    });

    test('bold stays in its color without drawBoldTextInBrightColors', () {
      final h = _Harness(
        configure: (o) => o.drawBoldTextInBrightColors = false,
      );
      addTearDown(h.dispose);
      h.write('\x1b[1;31mB');
      h.paintOnly();
      expect(
        h.renderer.debugCellColors(0, 0)!.fg,
        Color(terminalAnsiColors()[1].toARGB32()),
      );
    });

    test('a new theme redraws everything: no picture is kept, not even '
        'one whose model is the same', () async {
      // A negative glyph draws its shape in the background color, which
      // its model (foreground, default background) does not hold.
      const text = '\u{1FBBD}A \x1b[32mG';
      final h = _Harness();
      addTearDown(h.dispose);
      h.write(text);
      await h.paint();
      final theme = vscodeTerminalTheme()..background = '#000080';
      h.terminal.options.theme = theme;
      final pixels = await h.paint();

      final fresh = _Harness(configure: (o) => o.theme = theme);
      addTearDown(fresh.dispose);
      fresh.write(text);
      final expected = await fresh.paint();
      expect(pixels.at(15, 5), _fg);
      expect(pixels.at(25, 5), const Color(0xFF000080));
      expect(
        pixels.data.buffer.asUint8List(),
        expected.data.buffer.asUint8List(),
      );
    });

    test('meets the minimum contrast ratio, dim text half of it', () {
      final h = _Harness(configure: (o) => o.minimumContrastRatio = 4.5);
      addTearDown(h.dispose);
      h.write('\x1b[38;2;40;40;40mC\x1b[2mD\x1b[0m\x1b[38;2;40;40;40m█');
      h.paintOnly();
      final fg = h.renderer.debugCellColors(0, 0)!.fg!;
      final dim = h.renderer.debugCellColors(1, 0)!.fg!;
      double contrast(Color a, Color b) {
        final la = a.computeLuminance() + 0.05;
        final lb = b.computeLuminance() + 0.05;
        return math.max(la, lb) / math.min(la, lb);
      }

      expect(contrast(fg, _bg), greaterThanOrEqualTo(4.5));
      expect(contrast(dim, _bg), greaterThanOrEqualTo(2.25));
      expect(contrast(dim, _bg), lessThan(contrast(fg, _bg)));
      // Blocks are left out: they draw a background.
      expect(h.renderer.debugCellColors(2, 0)!.fg, const Color(0xFF282828));
    });

    test('a wide character takes two cells', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      // Unicode 11's widths, as VS Code activates them: the emoji is wide.
      h.terminal.unicodeService
        ..register(UnicodeV11())
        ..activeVersion = '11';
      h.write('中A\u{1F600}e\u0301!');
      final pixels = await h.paint();
      expect(h.renderer.debugRowText(0), '中A\u{1F600}e\u0301!');
      // The ideograph (one em of the test font) is drawn at the left of its
      // two cells, as upstream draws it; A is in the third cell, the
      // combined e in the sixth.
      expect(pixels.at(5, 5), _fg);
      expect(pixels.at(15, 5), _bg);
      expect(pixels.at(25, 5), _fg);
      expect(pixels.at(55, 5), _fg);
      expect(pixels.at(65, 5), _fg);
      expect(h.terminal.buffer.x, 7);
      expect(pixels.at(75, 5), _cursor);
    });

    test('squeezes a glyph wider than its cell', () async {
      Future<_Pixels> paint({required bool rescale}) async {
        // Letter spacing makes 6 pixel cells (from -2) of the glyph, wider
        // than 9.
        final h = _Harness(
          configure: (o) => o
            ..letterSpacing = -4
            ..rescaleOverlappingGlyphs = rescale,
        );
        addTearDown(h.dispose);
        h.write('\x1b[?25l\u216B');
        return h.paint();
      }

      // Ink right of the cell's first 4 pixels.
      int inkPast(_Pixels p) {
        var ink = 0;
        for (var y = 0; y < 10; y++) {
          for (var x = 4; x < 20; x++) {
            if (p.at(x, y) != _bg) ink++;
          }
        }
        return ink;
      }

      expect(inkPast(await paint(rescale: true)), 0);
      expect(inkPast(await paint(rescale: false)), greaterThan(0));
    });

    test('box drawing and blocks meet without seams', () async {
      for (final dpr in [1.0, 2.0, 1.5]) {
        final h = _Harness(devicePixelRatio: dpr);
        h.write('${'─' * 6}\r\n${'█' * 3}\r\n${'█' * 3}');
        final pixels = await h.paint();
        final dims = h.renderer.dimensions;
        // The horizontal line: find its row, then it is lit all along.
        var lineY = -1;
        for (var y = 0; y < dims.deviceCellHeight; y++) {
          if (pixels.device(1, y) == _fg) lineY = y;
        }
        expect(lineY, isNot(-1), reason: 'dpr $dpr');
        for (var x = 0; x < 6 * dims.deviceCellWidth; x++) {
          expect(pixels.device(x, lineY), _fg, reason: 'dpr $dpr x $x');
        }
        // Full blocks tile their rows and columns.
        for (
          var y = dims.deviceCellHeight;
          y < 3 * dims.deviceCellHeight;
          y++
        ) {
          for (var x = 0; x < 3 * dims.deviceCellWidth; x++) {
            if (pixels.device(x, y) != _fg) {
              fail('dpr $dpr: seam at $x, $y');
            }
          }
        }
        h.dispose();
      }
    });

    test('draws the cursor styles', () async {
      Future<_Pixels> cursor(String style, {bool focused = true}) async {
        final h = _Harness(
          configure: (o) => o.cursorStyle = style,
          focused: focused,
        );
        addTearDown(h.dispose);
        return h.paint();
      }

      final block = await cursor('block');
      expect(block.at(5, 5), _cursor);
      final underline = await cursor('underline');
      expect(underline.at(5, 9), _cursor);
      expect(underline.at(5, 5), _bg);
      final bar = await cursor('bar');
      expect(bar.at(0, 5), _cursor);
      expect(bar.at(5, 5), _bg);
      // Unfocused: VS Code's inactive style, an outline.
      final outline = await cursor('block', focused: false);
      expect(outline.at(0, 5), _cursor);
      expect(outline.at(9, 5), _cursor);
      expect(outline.at(5, 0), _cursor);
      expect(outline.at(5, 9), _cursor);
      expect(outline.at(5, 5), _bg);
    });

    test('hides the cursor with DECTCEM and follows DECSCUSR', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.write('\x1b[?25l');
      expect((await h.paint()).at(5, 5), _bg);
      h.write('\x1b[?25h\x1b[6 q'); // steady bar
      final pixels = await h.paint();
      expect(pixels.at(0, 5), _cursor);
      expect(pixels.at(5, 5), _bg);
    });

    test('paints the selection, inactive when unfocused', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.write('hello\r\nworld\r\n');
      h.renderer.selection = const TerminalSelectionRange(
        start: (x: 3, y: 0),
        end: (x: 2, y: 1),
      );
      await h.paint();
      final colors = h.source.themeService.colors;
      final active = Color(argbOfRgba(colors.selectionBackgroundOpaque.rgba));
      final inactive = Color(
        argbOfRgba(colors.selectionInactiveBackgroundOpaque.rgba),
      );
      final cell = h.renderer.debugCellColors;
      expect(cell(2, 0)!.bg, isNull);
      expect(cell(3, 0)!.bg, active);
      expect(cell(9, 0)!.bg, active);
      expect(cell(1, 1)!.bg, active);
      expect(cell(2, 1)!.bg, isNull);
      // The text keeps its color.
      expect(cell(3, 0)!.fg, _fg);
      h.renderer.isFocused = false;
      final pixels = await h.paint();
      expect(cell(3, 0)!.bg, inactive);
      // Behind a space (no glyph over it).
      expect(pixels.at(85, 5), inactive);
    });

    test('a column selection covers the same columns on each row', () {
      final h = _Harness();
      addTearDown(h.dispose);
      h.renderer.selection = const TerminalSelectionRange(
        start: (x: 2, y: 0),
        end: (x: 4, y: 2),
        columnSelectMode: true,
      );
      h.paintOnly();
      final cell = h.renderer.debugCellColors;
      for (var y = 0; y < 3; y++) {
        expect(cell(1, y)!.bg, isNull);
        expect(cell(2, y)!.bg, isNotNull);
        expect(cell(3, y)!.bg, isNotNull);
        expect(cell(4, y)!.bg, isNull);
      }
      expect(cell(2, 3)!.bg, isNull);
    });

    test('draws underline styles, overline and strikethrough', () async {
      final h = _Harness(cols: 12, rows: 3);
      addTearDown(h.dispose);
      // Spaces carry the lines alone.
      h.write('\x1b[4m \x1b[4:2m \x1b[4:3m \x1b[4:4m \x1b[4:5m \x1b[0m');
      h.write('\x1b[4;58;2;255;0;0m \x1b[0m\x1b[9m \x1b[0m\x1b[53m \x1b[0m');
      final p = await h.paint();
      // Single: the character box's last pixel row.
      expect(p.at(5, 9), _fg);
      expect(p.at(5, 5), _bg);
      // Double: a second line two widths lower (into the next row).
      expect(p.at(15, 9), _fg);
      expect(p.at(15, 11), _fg);
      expect(p.at(15, 10), _bg);
      // Curly: a zigzag within the last rows of the cell.
      var curly = 0;
      for (var x = 20; x < 30; x++) {
        for (var y = 7; y < 10; y++) {
          if (p.at(x, y).a > 0 && p.at(x, y) != _bg) curly++;
        }
      }
      expect(curly, greaterThan(5));
      expect(p.at(25, 3), _bg);
      // Dotted: dots and gaps of one pixel.
      expect(p.at(30, 9), _fg);
      expect(p.at(31, 9), _bg);
      expect(p.at(32, 9), _fg);
      // Dashed: 6 on, 3 off, the rest on.
      expect(p.at(40, 9), _fg);
      expect(p.at(45, 9), _fg);
      expect(p.at(47, 9), _bg);
      expect(p.at(49, 9), _fg);
      // SGR 58: the underline's own color.
      expect(p.at(55, 9), const Color(0xFFFF0000));
      // Strikethrough through the middle, overline at the top.
      expect(p.at(65, 4), _fg);
      expect(p.at(65, 8), _bg);
      expect(p.at(75, 0), _fg);
      expect(p.at(75, 5), _bg);
    });

    test('underlines a hovered link at the bottom of its cells', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.renderer.linkUnderline = const TerminalLinkUnderline(
        x1: 2,
        y1: 1,
        x2: 5,
        y2: 1,
        cols: 10,
      );
      expect(h.paintRequests, greaterThan(0));
      final p = await h.paint();
      expect(p.at(25, 18), _fg);
      expect(p.at(45, 18), _fg);
      expect(p.at(55, 18), _bg);
      expect(p.at(15, 18), _bg);
    });

    test('rebuilds only dirty rows and reuses pictures on scroll', () {
      final h = _Harness(rows: 4);
      addTearDown(h.dispose);
      h.renderer.debugTrackRows();
      h.write('\x1b[3;1H');
      h.paintOnly();
      expect(h.renderer.debugLastModelRows, [0, 1, 2, 3]);
      final pictures = h.renderer.debugPictureBuilds;

      h.write('x');
      h.paintOnly();
      expect(h.renderer.debugLastModelRows, [2]);
      expect(h.renderer.debugLastPictureRows, [2]);
      expect(h.renderer.debugPictureBuilds, pictures + 1);

      // Nothing changed: nothing is rebuilt.
      h.paintOnly();
      expect(h.renderer.debugLastModelRows, isEmpty);

      // Scrolled up a line: rows move; only the row entering is recorded.
      for (var i = 0; i < 8; i++) {
        h.write('line $i\r\n');
      }
      h.paintOnly();
      h.source.scrollLines(-1);
      h.paintOnly();
      expect(h.renderer.debugLastModelRows, [0, 1, 2, 3]);
      expect(h.renderer.debugLastPictureRows, [0]);
      expect(h.renderer.debugRowText(3), 'line 7');
    });

    test('paints only the rows in the clip', () {
      final h = _Harness(rows: 4);
      addTearDown(h.dispose);
      h.renderer.debugTrackRows();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..clipRect(const Rect.fromLTWH(0, 12, 100, 10));
      h.renderer.paint(canvas, Offset.zero);
      recorder.endRecording().dispose();
      expect(h.renderer.debugLastModelRows, [1, 2]);
    });

    test('holds rows while synchronized output is on', () {
      final h = _Harness();
      addTearDown(h.dispose);
      h.paintOnly();
      h.write('\x1b[?2026hZ');
      h.paintOnly();
      expect(h.renderer.debugRowText(0), '');
      h.write('\x1b[?2026l');
      h.paintOnly();
      expect(h.renderer.debugRowText(0), 'Z');
    });

    testWidgets('ends synchronized output after a second', (tester) async {
      final h = _Harness();
      h.write('\x1b[?2026hZ');
      h.paintOnly();
      expect(h.renderer.debugRowText(0), isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(h.source.synchronizedOutput, isFalse);
      h.paintOnly();
      expect(h.renderer.debugRowText(0), 'Z');
      h.dispose();
    });

    testWidgets('blinks text with blinkIntervalDuration, and the cursor', (
      tester,
    ) async {
      final h = _Harness(
        configure: (o) => o
          ..blinkIntervalDuration = 600
          ..cursorBlink = true,
      );
      h.write('\x1b[5mB\x1b[0m');
      h.paintOnly();
      expect(h.renderer.debugCellColors(0, 0)!.fg, _fg);
      expect(h.renderer.debugCellColors(1, 0)!.bg, _cursor);
      await tester.pump(const Duration(milliseconds: 600));
      h.paintOnly();
      expect(h.renderer.debugCellColors(0, 0)!.fg, isNull);
      expect(h.renderer.debugCellColors(1, 0)!.bg, isNull);
      await tester.pump(const Duration(milliseconds: 600));
      h.paintOnly();
      expect(h.renderer.debugCellColors(0, 0)!.fg, _fg);
      expect(h.renderer.debugCellColors(1, 0)!.bg, _cursor);
      h.dispose();
    });

    test('applies decoration colors', () {
      final h = _Harness();
      addTearDown(h.dispose);
      final decorations = DecorationService(
        h.terminal.logService,
        h.terminal.bufferService,
      );
      addTearDown(decorations.dispose);
      final source = TerminalCoreSource(
        h.terminal,
        decorationService: decorations,
      );
      addTearDown(source.dispose);
      final renderer = TerminalRenderer(source, onNeedsPaint: () {});
      addTearDown(renderer.dispose);
      h.write('\r\nabc');
      decorations.registerDecoration(
        IDecorationOptions(
          marker: h.terminal.registerMarker(0),
          x: 1,
          width: 1,
          backgroundColor: '#ff0000',
          foregroundColor: '#00ff00',
        ),
      );
      final recorder = ui.PictureRecorder();
      renderer.paint(Canvas(recorder), Offset.zero);
      recorder.endRecording().dispose();
      expect(renderer.debugCellColors(1, 1)!.bg, const Color(0xFFFF0000));
      expect(renderer.debugCellColors(1, 1)!.fg, const Color(0xFF00FF00));
      expect(renderer.debugCellColors(0, 1)!.bg, isNull);
    });

    test('renders from the services directly', () async {
      // As a terminal assembled from its services draws: cells written with
      // BufferLine's API, rows reported by hand.
      final options = OptionsService(_options(cols: 6, rows: 2));
      final log = LogService(options);
      final bufferService = BufferService(options, log);
      final core = CoreService(bufferService, log, options);
      final source = TerminalServicesSource(
        bufferService: bufferService,
        coreService: core,
        optionsService: options,
      );
      final renderer = TerminalRenderer(
        source,
        onNeedsPaint: () {},
        isFocused: true,
      );
      addTearDown(() {
        renderer.dispose();
        source.dispose();
        core.dispose();
        bufferService.dispose();
      });
      final attrs = AttributeData()
        ..fg = Attributes.cmP16 | 2
        ..bg = Attributes.cmRgb | 0x0000FF;
      final line = bufferService.buffer.lines.get(1)!;
      line.setCellFromCodepoint(0, 'O'.codeUnitAt(0), 1, attrs);
      line.setCellFromCodepoint(1, 'K'.codeUnitAt(0), 1, attrs);
      source.refreshRows(1, 1);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 60, 20),
        Paint()..color = renderer.backgroundColor,
      );
      renderer.paint(canvas, Offset.zero);
      final image = await recorder.endRecording().toImage(60, 20);
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final pixels = _Pixels(60, 20, data, 1);
      expect(renderer.debugRowText(1), 'OK');
      expect(pixels.at(5, 15), Color(terminalAnsiColors()[2].toARGB32()));
      expect(renderer.debugCellColors(1, 1)!.bg, const Color(0xFF0000FF));
      // The cursor at the origin (shown immediately).
      expect(pixels.at(5, 5), _cursor);
    });

    test('answers OSC color requests and repaints in new colors', () {
      final h = _Harness();
      addTearDown(h.dispose);
      final replies = <String>[];
      final sub = h.terminal.onData(replies.add);
      addTearDown(sub.dispose);
      h.write('\x1b]11;?\x07');
      expect(replies, ['\x1b]11;rgb:1919/1a1a/1b1b\x1b\\']);
      h.write('\x1b]10;#00ff00\x07X');
      h.paintOnly();
      expect(h.renderer.debugCellColors(0, 0)!.fg, const Color(0xFF00FF00));
    });

    test('benchmark: 200 x 120 SGR-heavy screen', () {
      final h = _Harness(cols: 120, rows: 200);
      addTearDown(h.dispose);
      final random = math.Random(1);
      final text = StringBuffer();
      for (var y = 0; y < 200; y++) {
        for (var x = 0; x < 120; x++) {
          final sgr = switch (random.nextInt(6)) {
            0 => '\x1b[3${random.nextInt(8)}m',
            1 => '\x1b[38;5;${random.nextInt(256)}m',
            2 => '\x1b[38;2;${random.nextInt(256)};0;${random.nextInt(256)}m',
            3 => '\x1b[1;4${random.nextInt(8)}m',
            4 => '\x1b[0m',
            _ => '',
          };
          text
            ..write(sgr)
            ..writeCharCode(0x21 + random.nextInt(90));
        }
      }
      h.write(text.toString());
      final full = Stopwatch()..start();
      h.paintOnly();
      full.stop();
      h.write('\x1b[100;1H');
      h.paintOnly();
      h.renderer.debugTrackRows();
      h.write('\x1b[31mchanged');
      final partial = Stopwatch()..start();
      h.paintOnly();
      partial.stop();
      final partialRows = h.renderer.debugLastModelRows;
      final idle = Stopwatch()..start();
      h.paintOnly();
      idle.stop();
      // ignore: avoid_print
      print(
        'terminal renderer 200x120: full ${full.elapsedMicroseconds}us, '
        'one row ${partial.elapsedMicroseconds}us '
        '(rows $partialRows), '
        'unchanged ${idle.elapsedMicroseconds}us',
      );
      expect(h.renderer.debugLastModelRows, isEmpty);
    });
  });
}
