// A save runs upstream's save participants in their order against a real
// extension host running test/fixtures/extensions/save-fixture: trailing
// whitespace trimmed, the source.fixAll code action applied, the document
// formatted, a final newline inserted, then the extension's
// onWillSaveTextDocument edit, all in the file written.
@Tags(['exthost'])
@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

import '../acceptance/open_vsx_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'save participants: trim, code actions, format, final newline, '
    'onWillSaveTextDocument',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const [],
        settings: {
          'files.trimTrailingWhitespace': true,
          'files.insertFinalNewline': true,
          'editor.formatOnSave': true,
          'editor.codeActionsOnSave': {'source.fixAll': 'explicit'},
        },
        files: {'a.fix': 'fix-me format-me   \nlast'},
        development: const ['test/fixtures/extensions/save-fixture'],
      );
      final file = await w.open('a.fix');
      await w.activated('baocode-test.save-fixture');
      final doc = w.workspace.documents.singleWhere((d) => d.path == file);
      // An edit, so the save writes.
      doc.model.applyOffsetEdits([
        EditorOffsetEdit(doc.text.length, doc.text.length, '\n'),
      ]);
      w.workspace.notifyDocumentChanged(doc);
      await w.workspace.save(doc);

      expect(
        File(file).readAsStringSync(),
        '// will save\nfixed formatted\nlast\n',
        reason: w.report(),
      );
      expect(doc.dirty, isFalse);
      final reasons = await w.extensions.commands.executeCommand(
        'saveFixture.reasons',
      );
      expect(reasons, [IdeSaveReason.explicit.value]);

      // Off: written as it is.
      final settings = w.app.userSettings;
      await settings.write(['editor.formatOnSave'], false);
      await settings.write(['editor.codeActionsOnSave'], null);
      doc.model.applyOffsetEdits([
        EditorOffsetEdit(doc.text.length, doc.text.length, 'format-me fix-me'),
      ]);
      w.workspace.notifyDocumentChanged(doc);
      await w.workspace.save(doc);
      expect(
        File(file).readAsStringSync(),
        '// will save\n// will save\nfixed formatted\nlast\nformat-me fix-me\n',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: openVsxSkip(),
  );
}
