import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_editor/monaco/flutter/editor_view_styles.dart';
import 'package:baocode/extensions/editors/editor_ports.dart';
import 'package:baocode/extensions/workbench/ide_text_editors.dart';
import 'package:baocode/ide/ide_editor_features.dart';
import 'package:baocode/ide/ide_editor_views.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../ide/workbench/fake_files.dart';

void main() {
  const a = '/p/a.ts';
  const b = '/p/b.ts';
  late IdeWorkspace workspace;
  late IdeTextEditors editors;

  setUp(() {
    workspace = IdeWorkspace(
      '/p',
      files: TreeFiles({a: 'one\ntwo\n', b: 'three\n'}),
      extensionLanguageId: (_) => 'typescript',
    );
    editors = IdeTextEditors(workspace);
  });

  tearDown(() {
    editors.dispose();
    workspace.dispose();
  });

  IdeEditorView viewOf(IdeDocument doc) {
    final controller = EditorSurfaceController(document: doc.model);
    final features = IdeEditorFeatures(
      controller: controller,
      types: workspace.editorViews.decorationTypes,
    );
    addTearDown(() {
      features.dispose();
      controller.dispose();
    });
    return IdeEditorView(
      document: doc,
      controller: controller,
      features: features,
      visibleLines: () => (first: 1, last: 2),
      hasFocus: () => true,
      focus: () {},
      reveal: (_, _, {center = false}) {},
    );
  }

  test(
    'the editor on screen moving its carets tells the extension host',
    () async {
      await workspace.open(a);
      final shown = viewOf(workspace.active!);
      await workspace.open(b);
      final hidden = viewOf(workspace.active!);
      workspace.editorViews.show(shown);
      final changed = <String>[];
      editors.onEditorStateChanged = changed.add;

      shown.controller.setSelections([
        const TextSelection.collapsed(offset: 4),
      ]);
      workspace.editorViews.changed(shown);
      expect(changed, [editors.activeEditorId]);
      expect(editors.uiOf(changed.single)!.selections.single.activeLine, 2);

      // Not on screen: not an editor the host has.
      workspace.editorViews.changed(hidden);
      expect(changed, hasLength(1));
    },
  );

  test(
    'an extension\'s cursor style and line numbers reach the editor',
    () async {
      await workspace.open(a);
      final view = viewOf(workspace.active!);
      workspace.editorViews.show(view);
      final ui = editors.uiOf(editors.activeEditorId!)!;
      expect(ui.options.cursorStyle, EditorCursorStyle.line);

      ui.updateOptions(
        cursorStyle: EditorCursorStyle.block,
        lineNumbers: EditorLineNumbers.relative,
      );
      expect(view.controller.caretStyle, EditorCaretStyle.block);
      expect(view.controller.lineNumbersStyle, EditorLineNumbersStyle.relative);
      expect(ui.options.cursorStyle, EditorCursorStyle.block);
      expect(ui.options.lineNumbers, EditorLineNumbers.relative);
    },
  );
}
