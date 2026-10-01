// Tests of the terminal widget: the fit it reports, where the grid sits and
// what it paints, one paint per frame, wheel and trackpad scrolling kept to
// the terminal or passed to the list around it, the scrollbar, focus, the
// grid coordinates for the input controllers and the composition view.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/terminal_render_adapter.dart';
import 'package:baocode/ide/terminal/terminal_render_theme.dart';
import 'package:baocode/ide/terminal/terminal_renderer.dart';
import 'package:baocode/ide/terminal/terminal_widget.dart';
import 'package:baocode/ide/terminal/xterm/headless/terminal.dart' as headless;

const _fg = Color(0xFFCCCCCC);
const _bg = Color(0xFF191A1B);

// Wheel gestures are app wide: each test's start well after the last's.
var _clock = Duration.zero;
Duration _tick([int ms = 16]) => _clock += Duration(milliseconds: ms);
Duration _newGesture() => _clock += const Duration(seconds: 10);

class _Terminal {
  _Terminal({int cols = 10, int rows = 5}) {
    terminal = headless.Terminal(
      vscodeTerminalOptions(cols: cols, rows: rows)
        ..fontFamily = 'FlutterTest'
        ..fontSize = 10
        ..minimumContrastRatio = 1
        ..showCursorImmediately = true,
    );
    source = TerminalCoreSource(terminal);
  }

  late final headless.Terminal terminal;
  late final TerminalCoreSource source;

  void write(String data) => terminal.writeSync(data);

  void dispose() {
    source.dispose();
    terminal.dispose();
  }
}

Future<ByteData> _capture(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!;
  }))!;
}

Color _pixel(ByteData data, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

void main() {
  testWidgets('reports the fit and draws the grid at the bottom', (
    tester,
  ) async {
    final t = _Terminal(cols: 10, rows: 5);
    addTearDown(t.dispose);
    final fits = <(int, int)>[];
    final controller = TerminalRenderController();
    addTearDown(controller.dispose);
    final boundary = GlobalKey();
    t.write('hi');
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: boundary,
          child: SizedBox(
            width: 215,
            height: 104,
            child: TerminalWidget(
              source: t.source,
              controller: controller,
              padding: const EdgeInsets.only(left: 20),
              onResize: (cols, rows) {
                fits.add((cols, rows));
                t.terminal.resize(cols, rows);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // 215 - 20 padding - 10 scrollbar: 18 columns; 104: 10 rows.
    expect(fits, [(18, 10)]);
    expect(t.source.cols, 18);
    expect(controller.cellSize, const Size(10, 10));
    // Bottom aligned: the 4 pixels left over are at the top.
    expect(controller.gridOrigin, const Offset(20, 4));
    expect(controller.scrollbarRect, const Rect.fromLTWH(205, 4, 10, 100));

    final data = await _capture(tester, boundary);
    expect(_pixel(data, 215, 25, 9), _fg); // 'h'
    expect(_pixel(data, 215, 35, 9), _fg); // 'i'
    expect(_pixel(data, 215, 10, 9), _bg); // padding: the background
    expect(_pixel(data, 215, 25, 2), _bg);

    // A smaller space: a new fit.
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 100,
          height: 50,
          child: TerminalWidget(
            source: t.source,
            controller: controller,
            onResize: (cols, rows) => fits.add((cols, rows)),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(fits.last, (9, 5));
  });

  testWidgets('paints at most once per frame', (tester) async {
    final t = _Terminal();
    addTearDown(t.dispose);
    final controller = TerminalRenderController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 110,
          height: 50,
          child: TerminalWidget(source: t.source, controller: controller),
        ),
      ),
    );
    final renderer = controller.renderer!;
    final paints = renderer.debugPaints;
    for (var i = 0; i < 20; i++) {
      t.write('x');
    }
    controller.selection = const TerminalSelectionRange(
      start: (x: 0, y: 0),
      end: (x: 3, y: 0),
    );
    await tester.pump();
    expect(renderer.debugPaints, paints + 1);
    await tester.pump();
    expect(renderer.debugPaints, paints + 1);
    expect(renderer.debugRowText(0), 'x' * 10);
  });

  group('wheel', () {
    late _Terminal t;
    late ScrollController list;

    Future<void> pumpInList(WidgetTester tester) async {
      t = _Terminal(cols: 10, rows: 10);
      addTearDown(t.dispose);
      for (var i = 0; i < 30; i++) {
        t.write('line $i\r\n');
      }
      list = ScrollController(initialScrollOffset: 100);
      addTearDown(list.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ListView(
            controller: list,
            children: [
              const SizedBox(height: 300),
              SizedBox(height: 100, child: TerminalWidget(source: t.source)),
              const SizedBox(height: 1000),
            ],
          ),
        ),
      );
    }

    // The terminal is at 200..300 in the list's viewport.
    const over = Offset(50, 250);

    testWidgets('scrolls the terminal, not the list around it', (tester) async {
      await pumpInList(tester);
      final buffer = t.terminal.buffer;
      expect(buffer.ydisp, 21);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(over));
      await tester.sendEventToBinding(
        pointer.scroll(const Offset(0, -30), timeStamp: _newGesture()),
      );
      await tester.pump();
      expect(buffer.ydisp, 18);
      expect(list.offset, 100);
      // Fractions of a line add up.
      await tester.sendEventToBinding(
        pointer.scroll(const Offset(0, -4), timeStamp: _tick()),
      );
      expect(buffer.ydisp, 18);
      await tester.sendEventToBinding(
        pointer.scroll(const Offset(0, -4), timeStamp: _tick()),
      );
      expect(buffer.ydisp, 17);
      await tester.pumpAndSettle();
    });

    testWidgets('keeps a gesture to the terminal at its end', (tester) async {
      await pumpInList(tester);
      final buffer = t.terminal.buffer;
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(over));
      await tester.sendEventToBinding(
        pointer.scroll(const Offset(0, -500), timeStamp: _newGesture()),
      );
      expect(buffer.ydisp, 0);
      // The same gesture goes on past the top: the list stays.
      await tester.sendEventToBinding(
        pointer.scroll(const Offset(0, -40), timeStamp: _tick()),
      );
      expect(buffer.ydisp, 0);
      expect(list.offset, 100);
      // A new gesture where the terminal cannot scroll goes to the list,
      // and stays there when the terminal could.
      await tester.sendEventToBinding(
        pointer.scroll(const Offset(0, -40), timeStamp: _newGesture()),
      );
      expect(list.offset, 60);
      await tester.sendEventToBinding(
        pointer.scroll(const Offset(0, 20), timeStamp: _tick()),
      );
      expect(list.offset, 80);
      expect(buffer.ydisp, 0);
      await tester.pumpAndSettle();
    });

    testWidgets('passes a gesture started elsewhere to the list', (
      tester,
    ) async {
      await pumpInList(tester);
      final buffer = t.terminal.buffer;
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(50, 100)));
      await tester.sendEventToBinding(
        pointer.scroll(const Offset(0, -20), timeStamp: _newGesture()),
      );
      expect(list.offset, 80);
      await tester.sendEventToBinding(pointer.hover(over));
      await tester.sendEventToBinding(
        pointer.scroll(const Offset(0, -20), timeStamp: _tick()),
      );
      expect(list.offset, 60);
      expect(buffer.ydisp, 21);
      await tester.pumpAndSettle();
    });

    testWidgets('takes what the input controller says to scroll', (
      tester,
    ) async {
      final t = _Terminal();
      addTearDown(t.dispose);
      final seen = <Offset>[];
      await tester.pumpWidget(
        Center(
          child: SizedBox(
            width: 110,
            height: 50,
            child: TerminalWidget(
              source: t.source,
              // As mouse reporting: the wheel is the app's.
              capturesWheel: () => true,
              onWheel: (event, position) {
                seen.add(position);
                return 0;
              },
            ),
          ),
        ),
      );
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      final center = tester.getCenter(find.byType(TerminalWidget));
      await tester.sendEventToBinding(pointer.hover(center));
      await tester.sendEventToBinding(
        pointer.scroll(const Offset(0, -30), timeStamp: _newGesture()),
      );
      expect(seen, [const Offset(55, 25)]);
      await tester.pumpAndSettle();
    });

    testWidgets('scrolls with a trackpad pan, not the list', (tester) async {
      await pumpInList(tester);
      final buffer = t.terminal.buffer;
      final pointer = TestPointer(2, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pointer.panZoomStart(over));
      await tester.sendEventToBinding(
        pointer.panZoomUpdate(over, pan: const Offset(0, 30)),
      );
      await tester.sendEventToBinding(
        pointer.panZoomUpdate(over, pan: const Offset(0, 60)),
      );
      await tester.sendEventToBinding(pointer.panZoomEnd());
      await tester.pump();
      expect(buffer.ydisp, 15);
      expect(list.offset, 100);
      await tester.pumpAndSettle();
    });
  });

  testWidgets('scrolls with the scrollbar', (tester) async {
    final t = _Terminal(cols: 10, rows: 10);
    addTearDown(t.dispose);
    for (var i = 0; i < 30; i++) {
      t.write('line $i\r\n');
    }
    final controller = TerminalRenderController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 110,
          height: 100,
          child: TerminalWidget(source: t.source, controller: controller),
        ),
      ),
    );
    final buffer = t.terminal.buffer;
    expect(controller.scrollbarRect, const Rect.fromLTWH(100, 0, 10, 100));
    // 31 lines, 10 shown: the slider is 32 high, at the bottom.
    final gesture = await tester.startGesture(const Offset(105, 10));
    // A click on the track centers the slider there.
    expect(buffer.ydisp, 0);
    // Then drags it: 34 pixels of the 68 it moves in are 105 of the 210
    // pixels there are to scroll, 10.5 lines.
    await gesture.moveBy(const Offset(0, 34));
    expect(buffer.ydisp, 11);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('follows the focus and focuses on a pointer down', (
    tester,
  ) async {
    final t = _Terminal();
    addTearDown(t.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final controller = TerminalRenderController();
    addTearDown(controller.dispose);
    final downs = <Offset>[];
    await tester.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 130,
          height: 50,
          child: Focus(
            focusNode: focusNode,
            child: TerminalWidget(
              source: t.source,
              controller: controller,
              focusNode: focusNode,
              padding: const EdgeInsets.only(left: 10),
              alignBottom: false,
              onPointerDown: (event, position) => downs.add(position),
            ),
          ),
        ),
      ),
    );
    expect(controller.renderer!.isFocused, isFalse);
    await tester.tapAt(const Offset(35, 12));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    expect(controller.renderer!.isFocused, isTrue);
    expect(downs, [const Offset(25, 12)]);
    expect(controller.getCoords(downs.single), (col: 3, row: 2));
    expect(controller.getCoords(downs.single, isSelection: true), (
      col: 3,
      row: 2,
    ));
    expect(controller.getCoords(const Offset(1000, -5), isSelection: true), (
      col: 11,
      row: 1,
    ));
    expect(controller.getMouseReportCoords(const Offset(25, 12)), (
      col: 2,
      row: 1,
      x: 25,
      y: 12,
    ));
    focusNode.unfocus();
    await tester.pump();
    expect(controller.renderer!.isFocused, isFalse);
  });

  testWidgets('shows the composition at the cursor', (tester) async {
    final t = _Terminal();
    addTearDown(t.dispose);
    final controller = TerminalRenderController();
    addTearDown(controller.dispose);
    t.write('ab');
    await tester.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 110,
          height: 50,
          child: TerminalWidget(source: t.source, controller: controller),
        ),
      ),
    );
    expect(find.text('にほん'), findsNothing);
    expect(controller.cursorRect, const Rect.fromLTWH(20, 0, 10, 10));
    controller.composition = 'にほん';
    await tester.pump();
    expect(find.text('にほん'), findsOneWidget);
    expect(tester.getTopLeft(find.text('にほん')), const Offset(20, 0));
    controller.composition = null;
    await tester.pump();
    expect(find.text('にほん'), findsNothing);
  });
}
