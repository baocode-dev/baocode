import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';

void main() {
  EditorSurfaceController controllerOf(String text) {
    final document = EditorDocumentModel(text);
    final controller = EditorSurfaceController(document: document);
    addTearDown(() {
      controller.dispose();
      document.dispose();
    });
    return controller;
  }

  String lines(int count, [String prefix = 'line']) =>
      List.generate(count, (i) => '$prefix ${i + 1}').join('\n');

  final key = GlobalKey();
  EditorSurfaceView view() => key.currentState! as EditorSurfaceView;

  Future<void> show(
    WidgetTester tester,
    EditorSurfaceController? controller, {
    bool wrap = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          height: 200,
          child: controller == null
              ? const SizedBox()
              : EditorSurface(key: key, controller: controller, wrap: wrap),
        ),
      ),
    ),
  );

  /// Scrolls [line] (one-based) to the top.
  Future<void> scrollTo(
    WidgetTester tester,
    EditorSurfaceController controller,
    int line,
  ) async {
    final snapshot = controller.document.snapshot;
    final offset = snapshot.lineStarts[line - 1];
    view().revealRange(offset, offset, center: true);
    await tester.pump();
  }

  testWidgets('each controller shown again is where it was left', (
    tester,
  ) async {
    final a = controllerOf(lines(200, 'a'));
    final b = controllerOf(lines(200, 'b'));
    await show(tester, a);
    await scrollTo(tester, a, 120);
    final left = view().viewState!;
    expect(left.firstLine, greaterThan(100));

    // Another starts at its top, not where the first was.
    await show(tester, b);
    expect(view().scrollOffset, Offset.zero);
    await scrollTo(tester, b, 40);
    final bLeft = view().viewState!;

    await show(tester, a);
    expect(view().viewState, left);
    expect(view().visibleLineRange!.first, left.firstLine);
    await show(tester, b);
    expect(view().viewState, bLeft);
  });

  testWidgets('the line at the top stays there as lines above it wrap', (
    tester,
  ) async {
    final long = List.generate(200, (i) => 'line ${i + 1} ${'w' * 80}');
    final a = controllerOf(long.join('\n'));
    final b = controllerOf(lines(10, 'b'));
    await show(tester, a);
    await scrollTo(tester, a, 120);
    final top = view().visibleLineRange!.first;

    await show(tester, b);
    await show(tester, a, wrap: true);
    expect(view().visibleLineRange!.first, top);
  });

  testWidgets('a surface let go leaves its view with its controller', (
    tester,
  ) async {
    final a = controllerOf(lines(200));
    await show(tester, a);
    await scrollTo(tester, a, 90);
    final left = view().viewState!;
    await show(tester, null);
    expect(a.viewState, left);
    await show(tester, a);
    expect(view().viewState, left);
  });

  testWidgets('folds come back while their lines are as they were', (
    tester,
  ) async {
    const text = 'a\n  b\n  c\nd\n  e\n  f\ng';
    final folded = controllerOf(text);
    final checksum = foldChecksum('  b\n  c');
    folded.viewState = EditorViewState(
      firstLine: 1,
      folds: [
        EditorFoldState(1, 3, checksum: checksum),
        // Its lines changed since.
        const EditorFoldState(4, 6, checksum: 1),
      ],
    );
    await show(tester, folded);
    final state = view().viewState!;
    expect(state.folds, [EditorFoldState(1, 3, checksum: checksum)]);
  });

  test('view state goes through JSON', () {
    final state = EditorViewState(
      firstLine: 42,
      firstLineOffset: 3.5,
      scrollLeft: 12,
      folds: [
        EditorFoldState(3, 9, checksum: foldChecksum('x')),
        const EditorFoldState(20, 30, userDefined: true),
      ],
    );
    expect(EditorViewState.fromJson(state.toJson()), state);
    expect(EditorViewState.fromJson({'line': 0}), isNull);
    expect(EditorViewState.fromJson('nope'), isNull);
    expect(foldChecksum('hello'), foldChecksum('hello'));
    expect(foldChecksum('hello'), isNot(foldChecksum('hellp')));
  });
}
