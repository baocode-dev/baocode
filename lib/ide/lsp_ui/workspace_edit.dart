import 'package:bao_editor/monaco/flutter/editor_document_model.dart';

import '../ide_workspace.dart';
import '../language/language_types.dart';
import 'lsp_convert.dart';

/// Applies an [IdeDocument]'s share of a workspace edit; returns whether it
/// handled it (the editor maps its cursors through the edits).
typedef IdeDocumentEditApplier = bool Function(
  IdeDocument document,
  List<EditorOffsetEdit> edits,
);

/// Applies [edit] to [workspace] as one undo step per document.
///
/// Documents that are not open are opened (as dirty tabs, unsaved, so the
/// change can be reviewed and undone) and the previously active document is
/// selected again. The edit is refused as a whole (returning false, nothing
/// changed) when it has file create/rename/delete operations, targets a
/// non-`file:` URI, has overlapping edits, or a document cannot be read.
/// [versions] optionally pins document versions the edit was computed for:
/// a document that changed since refuses the edit too.
Future<bool> applyLspWorkspaceEdit(
  IdeWorkspace workspace,
  LspWorkspaceEdit edit, {
  IdeDocumentEditApplier? applyTo,
  Map<String, int> versions = const {},
}) async {
  if (edit.resourceOperations.isNotEmpty) return false;
  final byPath = <String, List<LspTextEdit>>{};
  for (final MapEntry(key: uri, value: edits) in edit.changes.entries) {
    if (edits.isEmpty) continue;
    final path = lspPathOfUri(uri);
    if (path == null) return false;
    byPath.putIfAbsent(path, () => []).addAll(edits);
  }
  if (byPath.isEmpty) return true;

  IdeDocument? find(String path) =>
      workspace.documents.where((d) => d.path == path).firstOrNull;

  final missing = [
    for (final path in byPath.keys)
      if (find(path) == null) path,
  ];
  if (missing.isNotEmpty) {
    final previous = workspace.active?.path;
    try {
      for (final path in missing) {
        await workspace.open(path);
      }
    } catch (_) {
      return false;
    } finally {
      if (previous != null) workspace.select(previous);
    }
  }

  final planned = <(IdeDocument, List<EditorOffsetEdit>)>[];
  for (final MapEntry(key: path, value: edits) in byPath.entries) {
    final doc = find(path);
    if (doc == null) return false;
    if (versions[path] case final version? when version != doc.model.version) {
      return false;
    }
    final offsets = lspOffsetEdits(doc.model.snapshot, edits);
    if (offsets == null) return false;
    planned.add((doc, offsets));
  }

  for (final (doc, edits) in planned) {
    if (applyTo?.call(doc, edits) ?? false) continue;
    doc.model.closeUndoGroup();
    final changed = doc.model.applyOffsetEdits(edits);
    doc.model.closeUndoGroup();
    if (changed) workspace.notifyDocumentChanged(doc);
  }
  return true;
}
