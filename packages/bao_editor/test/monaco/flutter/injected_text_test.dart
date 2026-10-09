import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_decorations.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_editor/monaco/flutter/editor_tracked_decorations.dart';
import 'package:bao_editor/monaco/flutter/viewport_layout.dart';

const _style = TextStyle(
  fontFamily: 'InjectedRoboto',
  fontSize: 20,
  color: Color(0xff000000),
);

ViewportLayout _layout(
  String text, [
  List<EditorDecoration> decorations = const [],
]) {
  final snapshot = DocumentSnapshot(text);
  final set = SortedDecorations(decorations);
  final layout = ViewportLayout(
    snapshot: snapshot,
    style: _style,
    viewportSize: const Size(600, 200),
    wrap: false,
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
    lineDecorations: decorations.isEmpty
        ? null
        : (line) => ViewportLineDecorations.of(set, snapshot, line),
  );
  addTearDown(layout.dispose);
  return layout;
}

EditorDecoration _after(
  int offset,
  String text, {
  InjectedTextCursorStops stops = InjectedTextCursorStops.left,
}) => EditorDecoration(
  start: offset,
  end: offset,
  after: EditorInjectedText(text, cursorStops: stops),
);

EditorDecoration _before(
  int offset,
  String text, {
  InjectedTextCursorStops stops = InjectedTextCursorStops.right,
}) => EditorDecoration(
  start: offset,
  end: offset,
  before: EditorInjectedText(text, cursorStops: stops),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT']!;
    final font = File(
      '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    );
    final loader = FontLoader('InjectedRoboto')
      ..addFont(font.readAsBytes().then(ByteData.sublistView));
    await loader.load();
  });

  group('line decorations', () {
    test('order by column, before ahead of after, then given order', () {
      final snapshot = DocumentSnapshot('abc\ndef');
      final set = SortedDecorations([
        _after(5, 'A1'),
        _before(5, 'B1'),
        _after(5, 'A2'),
        _before(4, 'B0'),
        EditorDecoration(
          start: 1,
          end: 6,
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ]);
      final line2 = ViewportLineDecorations.of(set, snapshot, 2);
      expect(line2.injections.map((i) => (i.offset, i.text.text)), [
        (0, 'B0'),
        (1, 'B1'),
        (1, 'A1'),
        (1, 'A2'),
      ]);
      // The style covers the line's part of its range.
      expect(line2.styles.single.start, 0);
      expect(line2.styles.single.end, 2);
      final line1 = ViewportLineDecorations.of(set, snapshot, 1);
      expect(line1.injections, isEmpty);
      expect((line1.styles.single.start, line1.styles.single.end), (1, 3));
    });
  });

  group('layout with injected text', () {
    test('columns map around text injected mid-line', () {
      final plain = _layout('abcdef');
      final injected = _layout('abcdef', [_after(3, 'XYZ')]);
      final width = injected
          .injectionAt(Offset(injected.caretRect(3).left + 2, 10))!
          .rect
          .width;
      expect(width, greaterThan(20));
      // Up to the injection columns stay; past it they move by its width.
      for (final offset in [0, 1, 2, 3]) {
        expect(
          injected.caretRect(offset).left,
          closeTo(plain.caretRect(offset).left, 0.01),
        );
      }
      for (final offset in [4, 5, 6]) {
        expect(
          injected.caretRect(offset).left,
          closeTo(plain.caretRect(offset).left + width, 0.01),
        );
      }
      // Hit-testing skips it: its left half is column 3, and beyond.
      final box = injected.injectionAt(Offset(injected.caretRect(3).left, 10));
      expect(box, isNotNull);
      expect(box!.injection.text.text, 'XYZ');
      expect(injected.hitTest(Offset(box.rect.left + 1, 10)), 3);
      expect(injected.hitTest(Offset(box.rect.right + 1, 10)), 3);
      expect(injected.hitTest(Offset(injected.caretRect(5).left + 1, 10)), 5);
      // Ranges include it when they span it.
      final rects = injected.offsetRangeRects(2, 4);
      expect(
        rects.last.right - rects.first.left,
        closeTo(plain.offsetRangeRects(2, 4).single.width + width, 0.01),
      );
    });

    test('cursor stops pick the caret side', () {
      final plain = _layout('abcdef');
      final right = _layout('abcdef', [_before(3, 'XYZ')]);
      final none = _layout('abcdef', [
        _before(3, 'XYZ', stops: InjectedTextCursorStops.none),
      ]);
      final width = right.caretRect(4).left - plain.caretRect(4).left;
      expect(width, greaterThan(20));
      // `before` content: the caret goes after it.
      expect(
        right.caretRect(3).left,
        closeTo(plain.caretRect(3).left + width, 0.01),
      );
      // No stop at all: before it.
      expect(none.caretRect(3).left, closeTo(plain.caretRect(3).left, 0.01));
      // Between two: after the first that has a right stop.
      final two = _layout('abcdef', [
        _before(3, 'P', stops: InjectedTextCursorStops.right),
        _after(3, 'Q', stops: InjectedTextCursorStops.left),
      ]);
      final p = two.injectionAt(Offset(two.caretRect(3).left - 1, 10))!;
      expect(p.injection.text.text, 'P');
      expect(two.caretRect(3).left, closeTo(p.rect.right, 0.01));
    });

    test('text at the end of a line goes before line end decorations', () {
      final plain = _layout('abc');
      final injected = _layout('abc', [_after(3, ' // note')]);
      expect(
        injected.caretRect(3).left,
        closeTo(plain.caretRect(3).left, 0.01),
      );
      expect(
        injected.lineEndRect(1).left,
        greaterThan(plain.lineEndRect(1).left + 40),
      );
      // Clicking past the line puts the caret at its end.
      expect(injected.hitTest(const Offset(590, 10)), 3);
    });

    test('inline styles reshape text; a hidden range has no width', () {
      final plain = _layout('abcdef');
      final hidden = _layout('abcdef', [
        const EditorDecoration(
          start: 2,
          end: 6,
          textStyle: TextStyle(fontSize: 0.001, letterSpacing: 0),
          opacity: 0,
        ),
      ]);
      expect(hidden.caretRect(6).left, closeTo(plain.caretRect(2).left, 0.5));
      final bold = _layout('abcdef', [
        const EditorDecoration(
          start: 0,
          end: 6,
          textStyle: TextStyle(fontSize: 30),
        ),
      ]);
      expect(
        bold.caretRect(6).left,
        greaterThan(plain.caretRect(6).left * 1.3),
      );
    });
  });

  group('surface', () {
    testWidgets('the caret moves over injected text by columns', (
      tester,
    ) async {
      final document = EditorDocumentModel('let x = 1;\nfoo(a, b);');
      final controller = EditorSurfaceController(document: document);
      final tracked = EditorTrackedDecorations(document);
      addTearDown(() {
        tracked.dispose();
        controller.dispose();
        document.dispose();
      });
      tracked.set('hints', [
        EditorTrackedDecoration(
          start: 5,
          end: 5,
          decoration: const EditorDecoration(
            start: 5,
            end: 5,
            after: EditorInjectedText(
              ': number',
              cursorStops: InjectedTextCursorStops.right,
            ),
          ),
        ),
      ]);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              height: 200,
              child: EditorSurface(
                key: key,
                controller: controller,
                focusNode: focus,
                style: _style,
                decorationProviders: [tracked],
              ),
            ),
          ),
        ),
      );
      focus.requestFocus();
      controller.setSelections([const TextSelection.collapsed(offset: 4)]);
      await tester.pump();
      final view = key.currentState! as EditorSurfaceView;
      final at4 = view.caretRectAt(4)!;
      final at5 = view.caretRectAt(5)!;
      final at6 = view.caretRectAt(6)!;
      // The hint lies after `x` (offset 4..5), the caret right of it.
      expect(at6.left - at5.left, lessThan(at5.left - at4.left));
      expect(at5.left - at4.left, greaterThan(40));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(controller.value.selection.extentOffset, 5);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(controller.value.selection.extentOffset, 6);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(controller.value.selection.extentOffset, 4);

      // Typing moves the hint with its anchor; the text stays the text.
      controller.setSelections([const TextSelection.collapsed(offset: 0)]);
      controller.type('  ');
      await tester.pump();
      expect(document.text, '  let x = 1;\nfoo(a, b);');
      expect(tracked.rangesOf('hints').single.start, 7);
      final moved = view.caretRectAt(7)!.left - view.caretRectAt(6)!.left;
      expect(moved, greaterThan(40));

      // A click on the hint puts the caret at its column.
      final box = view.caretRectAt(7)!;
      final origin = tester.getTopLeft(find.byType(EditorSurface));
      await tester.tapAt(origin + Offset(box.left - 10, box.center.dy));
      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.value.selection.extentOffset, 7);
    });
  });
}
