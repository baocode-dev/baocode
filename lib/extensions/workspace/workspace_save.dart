// Saving editors for extensions (`workspace.save`, `workspace.saveAs`,
// `workspace.saveAll`), on the app's open documents.
//
// Follows VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadWorkspace.ts (`$save`: the
// editors of the resource saved with `force` unless Save As, the saved
// resource answered; `$saveAll`: whether all saved).

import 'package:bao_exthost/bao_exthost.dart';

import '../../ide/ide_workspace.dart';

/// Saves the app's editors.
abstract interface class WorkspaceSavePort {
  /// Saves [uri]'s editor (Save As when [saveAs]): the resource it was
  /// saved to; null when there is no such editor or it was not saved.
  Future<VsUri?> save(VsUri uri, {required bool saveAs});

  /// Saves every dirty editor ([includeUntitled]: new files too, asking
  /// where): whether all were saved.
  Future<bool> saveAll({bool includeUntitled = false});
}

/// [WorkspaceSavePort] on an [IdeWorkspace]'s documents: `file` URIs are
/// their paths, `untitled:Untitled-1` the new files'.
final class IdeWorkspaceSave implements WorkspaceSavePort {
  IdeWorkspaceSave(this.workspace);

  final IdeWorkspace workspace;

  IdeDocument? _find(VsUri uri) {
    for (final doc in workspace.documents) {
      if (doc.readOnly || doc.diff != null) continue;
      if (uri.scheme == 'untitled' && doc.isUntitled && doc.path == uri.path) {
        return doc;
      }
      if (uri.scheme == 'file' && doc.isFile && doc.path == uri.fsPath()) {
        return doc;
      }
    }
    return null;
  }

  static VsUri _uriOf(IdeDocument doc) => doc.isUntitled
      ? VsUri('untitled', path: doc.path)
      : VsUri.file(doc.path);

  @override
  Future<VsUri?> save(VsUri uri, {required bool saveAs}) async {
    final doc = _find(uri);
    if (doc == null) return null;
    if (saveAs || doc.isUntitled) {
      final saved = await workspace.saveAs(doc);
      return saved == null ? null : _uriOf(saved);
    }
    await workspace.save(doc);
    return _uriOf(doc);
  }

  @override
  Future<bool> saveAll({bool includeUntitled = false}) async {
    var success = true;
    for (final doc in [...workspace.documents]) {
      if (!doc.dirty || doc.diff != null) continue;
      if (doc.isUntitled && !includeUntitled) continue;
      try {
        if (doc.isUntitled) {
          success &= await workspace.saveAs(doc) != null;
        } else {
          await workspace.save(doc);
        }
      } on Object {
        success = false;
      }
    }
    return success;
  }
}
