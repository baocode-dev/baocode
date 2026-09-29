import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/flutter/editor_surface.dart';
import 'package:monad/ide/ide_editor.dart';
import 'package:monad/ide/ide_find_widget.dart';

import 'fake_files.dart';

/// The workbench with the default painted Monaco surface, not the fallback.
void main() {
  Future<void> settleAssets(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }

  testWidgets('palette editor commands run against the painted editor', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      {'lib/main.dart': 'void main() {\n  print(1);\n}\n'},
      open: ['lib/main.dart'],
      nativeEditor: true,
    );
    await settleAssets(tester);
    expect(find.byType(EditorSurface), findsOneWidget);
    final editor = tester.state<IdeEditorState>(find.byType(IdeEditor));
    // Two-space indentation is detected from the file for the status bar.
    expect(editor.indentationLabel, 'Spaces: 2');
    expect(find.text('Spaces: 2'), findsOneWidget);

    final commands = editor.editorCommands;
    final comment = commands.singleWhere(
      (command) => command.id == 'editor.action.commentLine',
    );
    expect(comment.category, 'Editor');
    tester
        .widget<EditorSurface>(find.byType(EditorSurface))
        .controller
        .select(0, 0);
    comment.run();
    await tester.pump();
    await tester.pump();
    expect(workspace.active!.text, startsWith('// void main() {'));
    // Retokenizing the edit may yield to the event loop when the machine is
    // busy; let it finish before the test ends.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('find matches are painted as surface decorations', (
    tester,
  ) async {
    await pumpWorkbench(
      tester,
      {'a.txt': 'one two one two one'},
      open: ['a.txt'],
      nativeEditor: true,
    );
    await settleAssets(tester);
    final editor = tester.state<IdeEditorState>(find.byType(IdeEditor));
    editor.openFind();
    await tester.pump();
    await tester.enterText(
      find
          .descendant(
            of: find.byType(IdeFindWidget),
            matching: find.byType(TextField),
          )
          .first,
      'one',
    );
    await tester.pump();
    final surface = tester.widget<EditorSurface>(find.byType(EditorSurface));
    expect(surface.decorations, hasLength(3));
    expect(surface.decorations.map((d) => d.start), [0, 8, 16]);
  });
}
