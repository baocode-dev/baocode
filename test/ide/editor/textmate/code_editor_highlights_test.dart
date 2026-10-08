// IdeCodeEditor's highlighting kept in IdeCodeHighlights: a text shown
// again in a new editor (the side panel's tab selected again) is colored on
// its first frame, not tokenized anew.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:baocode/ide/ide_code_editor.dart';

void main() {
  EditorSurfaceController controllerOf(String text) {
    final controller = EditorSurfaceController(
      document: EditorDocumentModel(text),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> show(
    WidgetTester tester,
    EditorSurfaceController controller,
    String path,
    IdeCodeHighlights? highlights,
  ) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // A new editor for each file, as the side panel's previews are.
        body: IdeCodeEditor(
          key: ValueKey(path),
          controller: controller,
          path: path,
          highlights: highlights,
        ),
      ),
    ),
  );

  List<TextSpan>? firstLine(WidgetTester tester) =>
      tester.widget<EditorSurface>(find.byType(EditorSurface)).styledLines?[1];

  Future<void> highlighted(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      if (firstLine(tester)?.isNotEmpty ?? false) return;
      await tester.pump(const Duration(milliseconds: 20));
    }
    fail('Never highlighted');
  }

  testWidgets('a text shown again is colored at once', (tester) async {
    final highlights = IdeCodeHighlights();
    final a = controllerOf('const a: number = 1;\n');
    final b = controllerOf('let b = "b";\n');

    await show(tester, a, '/w/a.ts', highlights);
    await highlighted(tester);
    final colored = firstLine(tester);
    await show(tester, b, '/w/b.ts', highlights);
    await highlighted(tester);

    await show(tester, a, '/w/a.ts', highlights);
    expect(firstLine(tester), same(colored));

    // Let go of: tokenized anew.
    await show(tester, b, '/w/b.ts', highlights);
    highlights.release(a);
    await show(tester, a, '/w/a.ts', highlights);
    expect(firstLine(tester), isNull);
    await highlighted(tester);

    // As the side panel does once its previews are gone.
    await tester.pumpWidget(const SizedBox());
    highlights.dispose();
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('without highlights an editor tokenizes its text anew', (
    tester,
  ) async {
    final a = controllerOf('const a: number = 1;\n');
    final b = controllerOf('let b = "b";\n');
    await show(tester, a, '/w/a.ts', null);
    await highlighted(tester);
    await show(tester, b, '/w/b.ts', null);
    await highlighted(tester);
    await show(tester, a, '/w/a.ts', null);
    expect(firstLine(tester), isNull);
    await highlighted(tester);
  });
}
