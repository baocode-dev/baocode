import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/diff_editor.dart';
import 'package:bao_editor/monaco/flutter/diff_editor_model.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';

/// The diff editor: side by side, two editors scrolling each on its own,
/// kept level through the changes; inline, the modified alone.
void main() {
  // Ten lines put in after the 50th of 200.
  final before = [for (var i = 1; i <= 200; i++) 'line $i'];
  final after = [
    ...before.take(50),
    for (var i = 1; i <= 10; i++) 'new $i',
    ...before.skip(50),
  ];
  const style = TextStyle(fontSize: 10, height: 1);

  late ValueNotifier<String?> original;
  late EditorDocumentModel modifiedDocument;
  late EditorSurfaceController originalController;
  late EditorSurfaceController modifiedController;
  late DiffEditorModel model;
  late ValueNotifier<Offset> scroll;
  final sides = <DiffEditorSide>[];

  setUp(() {
    original = ValueNotifier(before.join('\n'));
    modifiedDocument = EditorDocumentModel(after.join('\n'));
    originalController = EditorSurfaceController(
      document: EditorDocumentModel(before.join('\n')),
    );
    modifiedController = EditorSurfaceController(document: modifiedDocument);
    model = DiffEditorModel(original: original, modified: modifiedDocument);
    scroll = ValueNotifier(Offset.zero);
    sides.clear();
  });

  tearDown(() {
    model.dispose();
    originalController.dispose();
    modifiedController.dispose();
    modifiedDocument.dispose();
    original.dispose();
    scroll.dispose();
  });

  Future<void> pump(WidgetTester tester, {required bool sideBySide}) async {
    tester.view.physicalSize = const Size(1200, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget surface(EditorSurfaceController controller, DiffEditorSide side) {
      sides.add(side);
      return EditorSurface(
        controller: controller,
        readOnly: true,
        decorations: side.decorations,
        viewZones: side.zones,
        scrollPosition: side.scrollPosition,
        lineNumbers: side.lineNumbers,
        hiddenLines: side.hiddenLines,
        showMinimap: false,
        verticalScrollbar: false,
        style: style,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: DiffEditor(
          model: model,
          scrollPosition: scroll,
          sideBySide: sideBySide,
          style: style,
          theme: const EditorViewTheme(),
          colors: DiffEditorColors.from((_) => null),
          dark: true,
          original: (context, side) => surface(originalController, side),
          modified: (context, side) => surface(modifiedController, side),
        ),
      ),
    );
    // Long texts are compared on another isolate.
    await tester.runAsync(() async {
      while (model.mappings == null ||
          !identical(model.mappedSnapshot, modifiedDocument.snapshot) ||
          model.originalSnapshot?.text != original.value) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump();
  }

  testWidgets('side by side, scrolled past lines put in, the original is '
      'that many lines less down; scrolled itself, the modified follows', (
    tester,
  ) async {
    await pump(tester, sideBySide: true);
    expect(find.byType(EditorSurface), findsNWidgets(2));
    final originalSide = sides.firstWhere((side) => !side.lineNumbers);
    expect(originalSide.zones, isEmpty);
    final lineHeight = (tester.state(
      find.byType(EditorSurface).last,
    ) as EditorSurfaceView).lineHeight;

    scroll.value = Offset(0, 120 * lineHeight);
    await tester.pump();
    expect(
      originalSide.scrollPosition.value.dy,
      moreOrLessEquals(110 * lineHeight),
    );

    originalSide.scrollPosition.value = Offset(0, 20 * lineHeight);
    await tester.pump();
    expect(scroll.value.dy, moreOrLessEquals(20 * lineHeight));
  });

  testWidgets('inline, the modified alone, the deleted code numbered as the '
      'original numbers it', (tester) async {
    original.value = [...before.take(9), 'gone', ...before.skip(9)].join('\n');
    await pump(tester, sideBySide: false);
    expect(find.byType(EditorSurface), findsOneWidget);
    final zone = sides.last.zones.singleWhere(
      (zone) => zone.firstLineNumber != null,
    );
    expect(zone.firstLineNumber, 10);
    expect(zone.afterLineNumber, 9);
  });
}
