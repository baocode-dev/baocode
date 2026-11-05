// The active text editor's status bar entries (upstream's
// `EditorStatusContribution`, editorStatus.ts): the caret's line and column
// with what is selected, the indentation, the encoding, the line endings
// and the language mode, right to left of the notifications' bell; each
// runs its command when clicked.

import 'package:flutter/foundation.dart';

import '../../../keybindings/keybinding_service.dart';
import '../../../l10n/l10n.dart';
import '../../ide_status_bar.dart';
import '../../ide_workspace.dart';
import '../../services/editors.dart';
import '../contributions.dart';
import '../services.dart';
import '../statusbar.dart';

/// Their priorities on the right, left to right.
abstract final class EditorStatusPriority {
  static const selection = 100.0;
  static const indentation = 90.0;
  static const encoding = 80.0;
  static const eol = 70.0;
  static const mode = 60.0;
}

class EditorStatusContribution extends WorkbenchRegistrations {
  EditorStatusContribution(WorkbenchServices services) {
    final editors = services.get<EditorService>();
    final host = services.get<WorkbenchHost>();
    final statusbar = services.get<StatusbarService>();
    final keys = KeybindingService.instance;
    final changes = Listenable.merge([editors.caret, keys]);

    /// The active document, when it shows as text.
    IdeDocument? text() => switch (services.find<IdeWorkspace>()?.active) {
      final doc? when doc.openError == null && !doc.isMedia => doc,
      _ => null,
    };

    void entry(String id, double priority, StatusbarEntryBuilder build) => add(
      statusbar
          .addEntry(
            id,
            StatusbarAlignment.right,
            priority: priority,
            changes: changes,
            (context) => text() == null ? null : build(context),
          )
          .dispose,
    );

    entry('status.editor.selection', EditorStatusPriority.selection, (context) {
      final l10n = context.l10n;
      final caret = editors.caret.value;
      return IdeStatusBarItem(
        l10n.referencesPosition(caret.position.lineNumber, caret.statusColumn) +
            switch ((caret.selectionLength, caret.selectionLines)) {
              (0, _) => '',
              (final count, final lines) when lines > 1 =>
                ' ${l10n.wbSelectedLines(lines, count)}',
              (final count, _) => ' ${l10n.wbSelectedCount(count)}',
            },
        tooltip: keys.titleWithKeybinding(
          l10n.wbGoToLineColumn,
          'workbench.action.gotoLine',
        ),
        onTap: () => host.executeCommand('workbench.action.gotoLine'),
      );
    });
    entry('status.editor.indentation', EditorStatusPriority.indentation, (
      context,
    ) {
      final l10n = context.l10n;
      return IdeStatusBarItem(
        editors.editor?.localizedIndentationLabel(l10n) ?? l10n.wbSpaces(4),
        tooltip: l10n.wbIndentation,
      );
    });
    entry(
      'status.editor.encoding',
      EditorStatusPriority.encoding,
      (context) => IdeStatusBarItem(
        ideEncodingLabel(text()!.model.snapshot.text),
        tooltip: context.l10n.wbEncoding,
      ),
    );
    // Read again only once the text has changed.
    Object? eolOf;
    var eol = 'LF';
    entry('status.editor.eol', EditorStatusPriority.eol, (context) {
      final l10n = context.l10n;
      final snapshot = text()!.model.snapshot;
      if (!identical(snapshot, eolOf)) {
        eolOf = snapshot;
        eol = ideEolLabel(snapshot);
      }
      return IdeStatusBarItem(
        eol == 'Mixed' ? l10n.wbEolMixed : eol,
        tooltip: keys.titleWithKeybinding(
          l10n.wbSelectEol,
          'workbench.action.editor.changeEOL',
        ),
        onTap: () => host.executeCommand('workbench.action.editor.changeEOL'),
      );
    });
    entry(
      'status.editor.mode',
      EditorStatusPriority.mode,
      (context) => IdeStatusBarItem(
        IdeLanguageNames.forPath(text()!.path),
        tooltip: keys.titleWithKeybinding(
          context.l10n.languageModePlaceholder,
          'workbench.action.editor.changeLanguageMode',
        ),
        onTap: () =>
            host.executeCommand('workbench.action.editor.changeLanguageMode'),
      ),
    );
  }
}
