import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/flutter/bracket_matching.dart';
import 'package:baocode/ide/editor/monaco/flutter/document_snapshot.dart';
import 'package:baocode/ide/editor/monaco/flutter/editor_decorations.dart';
import 'package:baocode/ide/editor/monaco/flutter/editor_document_model.dart';
import 'package:baocode/ide/editor/monaco/flutter/editor_folding.dart';
import 'package:baocode/ide/editor/monaco/flutter/editor_minimap.dart';
import 'package:baocode/ide/editor/monaco/flutter/editor_scrollbar.dart';
import 'package:baocode/ide/editor/monaco/flutter/editor_surface.dart';
import 'package:baocode/ide/editor/monaco/flutter/editor_surface_controller.dart';
import 'package:baocode/ide/editor/monaco/flutter/editor_view_painters.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/languages/language_configuration.dart';

EditorSurfaceController _controller(String text) {
  final document = EditorDocumentModel(text);
  final controller = EditorSurfaceController(document: document);
  addTearDown(() {
    controller.dispose();
    document.dispose();
  });
  return controller;
}

Future<FocusNode> _mount(
  WidgetTester tester,
  EditorSurfaceController controller, {
  Size size = const Size(600, 300),
  List<EditorDecoration> decorations = const [],
  bool wrap = false,
  FoldingRules? foldingRules,
}) async {
  final focus = FocusNode();
  addTearDown(focus.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: size,
          child: EditorSurface(
            controller: controller,
            focusNode: focus,
            decorations: decorations,
            wrap: wrap,
            foldingRules: foldingRules,
          ),
        ),
      ),
    ),
  );
  return focus;
}

T _painter<T>(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(EditorSurface),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((paint) => paint.painter)
    .whereType<T>()
    .single;

EditorGutterPainter _gutter(WidgetTester tester) =>
    _painter<EditorGutterPainter>(tester);

Offset _origin(WidgetTester tester) =>
    tester.getTopLeft(find.byType(EditorSurface));

/// A mouse click with an explicit timestamp (multi-click detection uses it).
Future<void> _click(
  WidgetTester tester,
  Offset position, {
  required Duration at,
  Offset? dragTo,
}) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.down(position, timeStamp: at);
  await tester.pump();
  if (dragTo != null) {
    await gesture.moveTo(dragTo, timeStamp: at);
    await tester.pump();
  }
  await gesture.up(timeStamp: at);
  await tester.pump();
  await gesture.removePointer();
}

/// Offset of the middle of [column] (zero-based) on one-based [line] in
/// global coordinates, via the painted layout.
Offset _textPoint(WidgetTester tester, int line, int column) {
  final gutter = _gutter(tester);
  final layout = gutter.layout;
  final offset = layout.snapshot.lineStarts[line - 1] + column;
  final caret = layout.caretRect(offset);
  return _origin(tester) +
      Offset(gutter.geometry.contentLeft + caret.left + 2, caret.center.dy);
}

void main() {
  testWidgets('gutter shows Monaco layout parts and click/drag selects lines', (
    tester,
  ) async {
    final controller = _controller(
      List.generate(30, (i) => 'line ${i + 1}').join('\n'),
    );
    await _mount(tester, controller);
    final gutter = _gutter(tester);
    final geometry = gutter.geometry;
    final lineHeight = gutter.layout.lineHeight;
    expect(geometry.glyphMarginWidth, lineHeight.roundToDouble());
    // lineNumbersMinChars = 5 digits, then 26px of decorations and folding.
    expect(
      geometry.lineNumbersWidth,
      (5 * gutter.glyphs.digitWidth).roundToDouble(),
    );
    expect(geometry.contentLeft, geometry.decorationsLeft + 26);
    expect(geometry.minimapWidth, 80);
    expect(
      geometry.contentWidth,
      600 - geometry.contentLeft - 80 - geometry.verticalScrollbarWidth,
    );

    final origin = _origin(tester);
    final numbersX = geometry.lineNumbersLeft + 4;
    await _click(
      tester,
      origin + Offset(numbersX, lineHeight * 1.5),
      at: Duration.zero,
    );
    final snapshot = controller.document.snapshot;
    expect(
      controller.value.selection,
      TextSelection(
        baseOffset: snapshot.lineStarts[1],
        extentOffset: snapshot.lineStarts[2],
      ),
    );
    expect(_gutter(tester).activeLines, {3});

    await _click(
      tester,
      origin + Offset(numbersX, lineHeight * 1.5),
      at: const Duration(seconds: 5),
      dragTo: origin + Offset(numbersX, lineHeight * 3.5),
    );
    expect(
      controller.value.selection,
      TextSelection(
        baseOffset: snapshot.lineStarts[1],
        extentOffset: snapshot.lineStarts[4],
      ),
    );
    // Dragging upwards keeps the anchor line selected.
    await _click(
      tester,
      origin + Offset(numbersX, lineHeight * 3.5),
      at: const Duration(seconds: 10),
      dragTo: origin + Offset(numbersX, lineHeight * 0.5),
    );
    expect(
      controller.value.selection,
      TextSelection(
        baseOffset: snapshot.lineStarts[4],
        extentOffset: snapshot.lineStarts[0],
      ),
    );
  });

  testWidgets('double, triple, shift and alt clicks follow Monaco', (
    tester,
  ) async {
    final controller = _controller('alpha beta gamma\nsecond line');
    await _mount(tester, controller);
    final beta = _textPoint(tester, 1, 7);
    await _click(tester, beta, at: const Duration(seconds: 1));
    expect(
      controller.value.selection,
      const TextSelection.collapsed(offset: 7),
    );
    await _click(
      tester,
      beta,
      at: const Duration(seconds: 1, milliseconds: 200),
    );
    expect(
      controller.value.selection,
      const TextSelection(baseOffset: 6, extentOffset: 10),
    );
    await _click(
      tester,
      beta,
      at: const Duration(seconds: 1, milliseconds: 400),
    );
    expect(controller.value.selection.start, 0);
    expect(controller.value.selection.end, 17); // includes the line break

    // A slow second click is a new single click.
    await _click(tester, beta, at: const Duration(seconds: 3));
    expect(
      controller.value.selection,
      const TextSelection.collapsed(offset: 7),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _click(
      tester,
      _textPoint(tester, 2, 3),
      at: const Duration(seconds: 5),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(
      controller.value.selection,
      const TextSelection(baseOffset: 7, extentOffset: 20),
    );

    await _click(tester, beta, at: const Duration(seconds: 7));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await _click(
      tester,
      _textPoint(tester, 2, 2),
      at: const Duration(seconds: 9),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(controller.selections, hasLength(2));
    final carets = _painter<EditorCaretPainter>(tester);
    expect(carets.selections, hasLength(2));
    expect(carets.selections.last, const TextSelection.collapsed(offset: 19));

    // Secondary and middle buttons never move the selection.
    final before = controller.selections;
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await gesture.down(_textPoint(tester, 2, 5));
    await gesture.up();
    await gesture.removePointer();
    await tester.pump();
    expect(controller.selections, before);
  });

  testWidgets('multiple selections and carets are painted', (tester) async {
    final controller = _controller('one two one\nthree one');
    final focus = await _mount(tester, controller);
    focus.requestFocus();
    await tester.pump();
    controller.setSelections(const [
      TextSelection(baseOffset: 0, extentOffset: 3),
      TextSelection(baseOffset: 8, extentOffset: 11),
      TextSelection.collapsed(offset: 14),
    ]);
    await tester.pump();
    expect(tester.takeException(), isNull);
    final overlay = _painter<EditorOverlayPainter>(tester);
    expect(overlay.selections, hasLength(3));
    expect(_painter<EditorCaretPainter>(tester).selections, hasLength(3));
    expect(_gutter(tester).activeLines, {1, 2});

    // Paint the overlay: both selection ranges get the selection color.
    final recorder = ui.PictureRecorder();
    final size = tester.getSize(find.byType(EditorSurface));
    overlay.paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    final image = await tester.runAsync(
      () => picture.toImage(size.width.ceil(), size.height.ceil()),
    );
    final bytes = (await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    Color pixel(Offset global) {
      final local = global - _origin(tester);
      final index =
          (local.dy.floor() * size.width.ceil() + local.dx.floor()) * 4;
      return Color.fromARGB(
        bytes.getUint8(index + 3),
        bytes.getUint8(index),
        bytes.getUint8(index + 1),
        bytes.getUint8(index + 2),
      );
    }

    const selection = Color(0xff264f78);
    expect(pixel(_textPoint(tester, 1, 1)), selection);
    expect(pixel(_textPoint(tester, 1, 9)), selection);
    expect(pixel(_textPoint(tester, 1, 5)), isNot(selection));
    image!.dispose();
    picture.dispose();
  });

  testWidgets('caret blinks on its own layer and is solid after changes', (
    tester,
  ) async {
    final controller = _controller('abc');
    final focus = await _mount(tester, controller);
    focus.requestFocus();
    await tester.pump();
    final visible = _painter<EditorCaretPainter>(tester).visible;
    expect(visible.value, isTrue);
    await tester.pump(const Duration(milliseconds: 540));
    expect(visible.value, isFalse);
    await tester.pump(const Duration(milliseconds: 540));
    expect(visible.value, isTrue);
    await tester.pump(const Duration(milliseconds: 540));
    expect(visible.value, isFalse);
    controller.select(1, 1);
    await tester.pump();
    expect(visible.value, isTrue);
    focus.unfocus();
    await tester.pump(const Duration(seconds: 2));
    expect(visible.value, isTrue); // no timer while unfocused
  });

  testWidgets('indent folding hides lines and unfolds for selections', (
    tester,
  ) async {
    final controller = _controller(
      ['class A {', '  void foo() {', '    x;', '  }', '}', 'tail'].join('\n'),
    );
    await _mount(tester, controller);
    controller.select(0, 0);
    await tester.pump();
    var gutter = _gutter(tester);
    expect(gutter.folding.regions.length, 2);
    final lineHeight = gutter.layout.lineHeight;
    final chevron =
        _origin(tester) +
        Offset(
          gutter.geometry.foldingLeft + gutter.geometry.foldingWidth / 2,
          lineHeight * 1.5,
        );
    await _click(tester, chevron, at: Duration.zero);
    gutter = _gutter(tester);
    expect(gutter.folding.isCollapsedAt(2), isTrue);
    // Indent regions end before the closing brace (upstream behavior).
    expect(gutter.layout.viewLineCount, 5);
    expect(gutter.layout.visibleLineNumbers.toList(), [1, 2, 4, 5, 6]);
    expect(
      controller.value.selection,
      const TextSelection.collapsed(offset: 0),
    );

    // Moving a selection into the hidden range reveals it.
    final snapshot = controller.document.snapshot;
    controller.select(snapshot.lineStarts[2] + 2, snapshot.lineStarts[2] + 2);
    await tester.pump();
    gutter = _gutter(tester);
    expect(gutter.folding.hasCollapsed, isFalse);
    expect(gutter.layout.viewLineCount, 6);

    // Collapsing around the caret moves it to the header line's end.
    await _click(
      tester,
      chevron - Offset(0, lineHeight),
      at: const Duration(seconds: 2),
    );
    gutter = _gutter(tester);
    expect(gutter.layout.visibleLineNumbers.toList(), [1, 5, 6]);
    expect(
      controller.value.selection,
      TextSelection.collapsed(offset: snapshot.contentEnds[0]),
    );

    // Edits below shift the fold; clicking the placeholder expands it.
    controller.value = TextEditingValue(
      text: '// head\n${controller.value.text}',
      selection: const TextSelection.collapsed(offset: 0),
    );
    await tester.pump();
    gutter = _gutter(tester);
    expect(gutter.folding.isCollapsedAt(2), isTrue);
    expect(gutter.layout.visibleLineNumbers.toList(), [1, 2, 6, 7]);
    final placeholder = EditorTextPainter.placeholderRect(
      gutter.layout,
      gutter.glyphs,
      2,
    );
    await _click(
      tester,
      _origin(tester) +
          Offset(gutter.geometry.contentLeft, 0) +
          placeholder.center,
      at: const Duration(seconds: 4),
    );
    expect(_gutter(tester).folding.hasCollapsed, isFalse);
  });

  testWidgets('folding markers come from rules or language configuration', (
    tester,
  ) async {
    final controller = _controller(
      ['// #region', 'a', '// #endregion', 'b'].join('\n'),
    );
    final rules = FoldingRules(
      markers: FoldingMarkers(
        RegExp(r'^\s*//\s*#region\b'),
        RegExp(r'^\s*//\s*#endregion\b'),
      ),
    );
    await _mount(tester, controller, foldingRules: rules);
    final regions = _gutter(tester).folding.regions;
    expect(regions.length, 1);
    expect(
      (regions.getStartLineNumber(0), regions.getEndLineNumber(0)),
      (1, 3),
    );
  });

  testWidgets('vertical scrollbar drags, pages, and overview marks', (
    tester,
  ) async {
    final controller = _controller(
      List.generate(200, (i) => 'line $i').join('\n'),
    );
    controller.select(0, 0);
    await _mount(
      tester,
      controller,
      decorations: const [EditorDecoration.findMatch(700, 704)],
    );
    final scrollbar = _painter<EditorScrollbarPainter>(tester);
    expect(scrollbar.vertical.needed, isTrue);
    final track = scrollbar.verticalTrack;
    final origin = _origin(tester);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(origin + Offset(track.center.dx, 5));
    await tester.pump();
    await gesture.moveTo(origin + Offset(track.center.dx, 55));
    await tester.pump();
    expect(
      _painter<EditorScrollbarPainter>(tester).dragging,
      ScrollbarPart.vertical,
    );
    await gesture.up();
    await gesture.removePointer();
    await tester.pump();
    final dragged = _gutter(tester).scrollTop;
    expect(dragged, closeTo(50 / scrollbar.vertical.ratio, 0.5));
    // Selection was not changed by scrollbar interaction.
    expect(
      controller.value.selection,
      const TextSelection.collapsed(offset: 0),
    );

    // Clicking the track below the slider pages down by one viewport.
    await _click(
      tester,
      origin + Offset(track.center.dx, track.bottom - 3),
      at: const Duration(seconds: 1),
    );
    expect(_gutter(tester).scrollTop, closeTo(dragged + 300, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wheel scrolls, shift+wheel scrolls horizontally, beyond end', (
    tester,
  ) async {
    final long = 'x' * 400;
    final controller = _controller(
      [...List.generate(40, (i) => 'line $i'), long].join('\n'),
    );
    controller.select(0, 0);
    await _mount(tester, controller);
    final center = tester.getCenter(find.byType(EditorSurface));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, 1e6)),
    );
    await tester.pump();
    final gutter = _gutter(tester);
    // scrollBeyondLastLine: the last line can reach the top of the viewport.
    expect(
      gutter.scrollTop,
      closeTo(gutter.layout.contentHeight - gutter.layout.lineHeight, 0.01),
    );
    expect(gutter.layout.visibleLineNumbers.toList(), [41]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, 120)),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(_painter<EditorTextPainter>(tester).scrollLeft, 120);
    expect(_painter<EditorScrollbarPainter>(tester).horizontal.needed, isTrue);
  });

  testWidgets('drag selection auto-scrolls while outside the viewport', (
    tester,
  ) async {
    final controller = _controller(
      List.generate(100, (i) => 'line $i').join('\n'),
    );
    controller.select(0, 0);
    await _mount(tester, controller);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(_textPoint(tester, 2, 1));
    await tester.pump();
    final bottom = tester.getBottomLeft(find.byType(EditorSurface));
    await gesture.moveTo(Offset(_textPoint(tester, 2, 1).dx, bottom.dy + 40));
    await tester.pump();
    final before = controller.value.selection.extentOffset;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_gutter(tester).scrollTop, greaterThan(0));
    expect(controller.value.selection.extentOffset, greaterThan(before));
    expect(
      controller.value.selection.baseOffset,
      controller.document.snapshot.lineStarts[1] + 1,
    );
    final scrolled = _gutter(tester).scrollTop;
    await gesture.up();
    await gesture.removePointer();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_gutter(tester).scrollTop, scrolled); // timer stopped
  });

  testWidgets('minimap renders chunks and clicking jumps the viewport', (
    tester,
  ) async {
    final controller = _controller(
      List.generate(400, (i) => '  token $i;').join('\n'),
    );
    controller.select(0, 0);
    await _mount(
      tester,
      controller,
      decorations: const [EditorDecoration.currentFindMatch(0, 2)],
    );
    final minimap = _painter<EditorMinimapPainter>(tester);
    expect(minimap.rect.width, 80);
    final origin = _origin(tester);
    await _click(
      tester,
      origin + Offset(minimap.rect.center.dx, 250),
      at: Duration.zero,
    );
    final layout = _gutter(tester).layout;
    final top = _gutter(tester).scrollTop;
    // Minimap line 125 (2px per line, minimap unscrolled) is centered.
    expect(top, closeTo(125 * layout.lineHeight - 150, 0.5));
    expect(tester.takeException(), isNull);

    final geometry = MinimapGeometry.compute(
      height: 300,
      lineHeight: 10,
      viewportHeight: 300,
      scrollTop: 0,
      scrollHeight: 4000,
    );
    expect(geometry.scrollTop, 0);
    expect(geometry.sliderHeight, 60);
    final bottom = MinimapGeometry.compute(
      height: 300,
      lineHeight: 10,
      viewportHeight: 300,
      scrollTop: 3700,
      scrollHeight: 4000,
    );
    expect(bottom.sliderTop + bottom.sliderHeight, closeTo(300, 0.001));
  });

  testWidgets('decorations are sorted, painted and marked in the ruler', (
    tester,
  ) async {
    final controller = _controller('find me and find me\nfind');
    controller.select(0, 0);
    const decorations = [
      EditorDecoration.currentFindMatch(12, 16),
      EditorDecoration.findMatch(0, 4),
      EditorDecoration(start: 20, end: 24, kind: EditorDecorationKind.error),
    ];
    await _mount(tester, controller, decorations: decorations);
    final overlay = _painter<EditorOverlayPainter>(tester);
    expect(overlay.decorations.items.map((d) => d.start), [0, 12, 20]);
    expect(overlay.decorations.intersecting(5, 11), isEmpty);
    expect(
      overlay.decorations.intersecting(13, 13).single.kind,
      EditorDecorationKind.currentFindMatch,
    );
    // Same content in a new list keeps the sorted instance (no repaint).
    await _mount(tester, controller, decorations: List.of(decorations));
    expect(
      _painter<EditorOverlayPainter>(tester).decorations,
      same(overlay.decorations),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('after text is painted past the end of its line', (tester) async {
    final controller = _controller('abc\nlonger line\nend');
    controller.select(0, 0);
    await _mount(
      tester,
      controller,
      decorations: const [
        EditorDecoration(
          start: 15,
          end: 15,
          afterText: 'Ada, 2 days ago',
          afterColor: Color(0xff808080),
          afterMargin: 50,
        ),
      ],
    );
    final end = _painter<EditorTextPainter>(tester).layout
        .caretRect(15, affinity: TextAffinity.upstream);
    RenderObject text() => tester.renderObject(
      find.descendant(
        of: find.byType(EditorSurface),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is EditorTextPainter,
        ),
      ),
    );
    bool afterText(Symbol method, List<dynamic> arguments) {
      if (method != #drawParagraph) return false;
      final at = arguments[1] as Offset;
      return at.dx == end.left + 50 && at.dy >= end.top && at.dy < end.bottom;
    }

    expect(text(), paints..something(afterText));
    await _mount(tester, controller);
    expect(text(), isNot(paints..something(afterText)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('50k-line typing reshapes only visible lines', (tester) async {
    final controller = _controller(
      List.generate(50000, (i) => '  value_$i = $i;').join('\n'),
    );
    controller.select(0, 0);
    final focus = await _mount(tester, controller);
    focus.requestFocus();
    await tester.pump();
    final first = _gutter(tester).layout;
    final visibleRows = first.visibleRowRange.end - first.visibleRowRange.start;
    expect(first.shapedLineCount, lessThanOrEqualTo(visibleRows));
    for (var i = 0; i < 5; i++) {
      controller.replaceSelection('x');
      await tester.pump();
      final layout = _gutter(tester).layout;
      expect(layout, isNot(same(first)));
      // Only the edited line is new; everything else comes from the cache.
      expect(layout.shapedLineCount, lessThanOrEqualTo(1));
    }
    // Selection-only changes keep the same layout object.
    final layout = _gutter(tester).layout;
    controller.select(3, 3);
    await tester.pump();
    expect(_gutter(tester).layout, same(layout));
    // Folding for large files is computed after a debounce.
    await tester.pump(const Duration(milliseconds: 300));
    expect(_gutter(tester).folding.isStale, isFalse);
  });

  test('bracket matching finds pairs around the caret', () {
    final snapshot = DocumentSnapshot('f(a[1], {b: (c)})');
    expect(matchBracket(snapshot, 1), (
      open: 1,
      openLength: 1,
      close: 16,
      closeLength: 1,
    ));
    expect(matchBracket(snapshot, 2), (
      open: 1,
      openLength: 1,
      close: 16,
      closeLength: 1,
    ));
    // Between `)` and `}` the right-side bracket wins.
    expect(matchBracket(snapshot, 15)?.close, 15);
    expect(matchBracket(snapshot, 15)?.open, 8);
    expect(matchBracket(snapshot, 5), (
      open: 3,
      openLength: 1,
      close: 5,
      closeLength: 1,
    ));
    expect(matchBracket(DocumentSnapshot('(()'), 0), isNull);
    expect(matchBracket(DocumentSnapshot('a\n(\nb\n)'), 3), (
      open: 2,
      openLength: 1,
      close: 6,
      closeLength: 1,
    ));
    expect(
      matchBracket(
        DocumentSnapshot('begin x end'),
        0,
        pairs: const [('begin', 'end')],
      ),
      (open: 0, openLength: 5, close: 8, closeLength: 3),
    );
    expect(matchBracket(DocumentSnapshot('(\n\n\n)'), 0, maxLines: 2), isNull);
  });

  test('folding model shifts regions by line deltas between recomputes', () {
    final model = EditorFoldingModel();
    const text = 'a\n  b\n  c\nd\n  e\n  f';
    model.updateSnapshot(DocumentSnapshot(text));
    model.recompute(tabSize: 4);
    expect(model.regions.length, 2);
    expect(model.toggle(4), isTrue);
    expect(model.hiddenLines.ranges.toList(), [(5, 6)]);
    final shift = computeLineShift(
      DocumentSnapshot(text),
      DocumentSnapshot('x\n$text'),
    );
    expect(shift, (firstChangedLine: 1, firstShiftedLine: 1, delta: 1));
    // Typing inside a line shifts nothing.
    expect(
      computeLineShift(
        DocumentSnapshot(text),
        DocumentSnapshot(text.replaceFirst('b', 'bX')),
      ),
      (firstChangedLine: 3, firstShiftedLine: 3, delta: 0),
    );
    // Deleting lines 2-3 shifts later lines up.
    expect(
      computeLineShift(
        DocumentSnapshot(text),
        DocumentSnapshot(text.replaceFirst('  b\n  c\n', '')),
      ),
      (firstChangedLine: 2, firstShiftedLine: 4, delta: -2),
    );
    expect(model.updateSnapshot(DocumentSnapshot('x\n$text')), isTrue);
    expect(model.isCollapsedAt(5), isTrue);
    expect(model.hiddenLines.ranges.toList(), [(6, 7)]);
    model.recompute(tabSize: 4);
    expect(model.isCollapsedAt(5), isTrue);
    expect(model.reveal([7]), isTrue);
    expect(model.hasCollapsed, isFalse);
  });

  test('sorted decorations find intersecting items by binary search', () {
    final sorted = SortedDecorations([
      for (var i = 0; i < 1000; i++)
        EditorDecoration.findMatch(i * 10, i * 10 + 3),
      const EditorDecoration(start: 0, end: 5000, isWholeLine: true),
    ]);
    expect(sorted.intersecting(4995, 5004).map((d) => d.start), [0, 5000]);
    expect(sorted.intersecting(20000, 30000), isEmpty);
    final slider = ScrollbarSlider.compute(
      trackSize: 100,
      visibleSize: 100,
      scrollSize: 10000,
      scrollPosition: 9900,
    );
    expect(slider.size, ScrollbarSlider.minimumSliderSize);
    expect(slider.position, closeTo(80, 1e-9));
  });
}
