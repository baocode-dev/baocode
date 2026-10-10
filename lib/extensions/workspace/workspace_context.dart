/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The workspace an extension host serves: its folders as they change, and
// extensions changing them (`workspace.updateWorkspaceFolders`).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/workspace/common/workspace.ts (`getWorkspaceFolder`,
// `WorkbenchState`), src/vs/workbench/services/workspaces/browser/
// abstractWorkspaceEditingService.ts (`updateFolders`, `doAddFolders`:
// a folder's window enters a multi-folder workspace to get more).
//
// Deviations: folder names an extension gives are kept only as far as
// the app's workspace model keeps names ([WorkspaceFoldersPort]).

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import '../files/file_service.dart' show uriIsEqualOrParent, uriEqual;
import '../host/init_data.dart';

/// `WorkbenchState`.
enum WorkbenchState { empty, folder, workspace }

/// A folder an extension adds (`IWorkspaceFolderCreationData`).
typedef WorkspaceFolderToAdd = ({VsUri uri, String? name});

/// What the app does when an extension changes the folders.
abstract interface class WorkspaceFoldersPort {
  /// Has the open multi-folder workspace hold [folders] from now on.
  /// Throws when it cannot.
  Future<void> setFolders(List<WorkspaceFolderToAdd> folders);

  /// `createAndEnterWorkspace`: a folder's (or an empty) window becomes a
  /// multi-folder workspace of [folders]. Throws when it cannot.
  Future<void> enterWorkspace(List<WorkspaceFolderToAdd> folders);

  /// `notificationService.status`: [extensionName] [added] and [removed]
  /// folders.
  void showStatus(String extensionName, int added, int removed);
}

/// `IWorkspaceContextService`: the workspace, null for an empty window.
final class WorkspaceContextService extends ChangeNotifier {
  WorkspaceContextService(
    this._workspace, {
    this.isMultiRoot = false,
    this.ignorePathCase = false,
    this.folders,
  });

  ExtHostWorkspace? _workspace;

  /// Whether the workspace is a multi-folder one (even with one folder).
  bool isMultiRoot;

  /// Paths compare without case (macOS, Windows disks).
  final bool ignorePathCase;

  /// Applies extensions' folder changes; none refuses them.
  WorkspaceFoldersPort? folders;

  ExtHostWorkspace? get workspace => _workspace;

  set workspace(ExtHostWorkspace? value) {
    if (identical(value, _workspace)) return;
    _workspace = value;
    notifyListeners();
  }

  WorkbenchState get state => _workspace == null
      ? WorkbenchState.empty
      : isMultiRoot || _workspace!.configuration != null
      ? WorkbenchState.workspace
      : WorkbenchState.folder;

  List<ExtHostWorkspaceFolder> get workspaceFolders =>
      _workspace?.folders ?? const [];

  /// Replaces the folders, keeping the workspace's id and name (the
  /// app's model changed them).
  void setFolders(List<({VsUri uri, String name})> folders) {
    final current = _workspace;
    if (current == null) return;
    final next = [
      for (final (i, f) in folders.indexed) ExtHostWorkspaceFolder(f.uri, f.name, i),
    ];
    if (listEquals(
      [for (final f in next) (f.uri, f.name)],
      [for (final f in current.folders) (f.uri, f.name)],
    )) {
      return;
    }
    workspace = ExtHostWorkspace(
      id: current.id,
      name: current.name,
      folders: next,
      configuration: current.configuration,
      transient: current.transient,
    );
  }

  /// `getWorkspaceFolder`: the innermost folder holding [resource].
  ExtHostWorkspaceFolder? getWorkspaceFolder(VsUri resource) {
    ExtHostWorkspaceFolder? best;
    for (final folder in workspaceFolders) {
      if (uriIsEqualOrParent(resource, folder.uri, ignoreCase: ignorePathCase) &&
          (best == null || folder.uri.path.length > best.uri.path.length)) {
        best = folder;
      }
    }
    return best;
  }

  /// `IWorkspaceData` for the extension host; null for an empty window.
  Map<String, Object?>? toWorkspaceData() {
    final w = _workspace;
    if (w == null) return null;
    return {
      ...w.toJson(),
      'configuration': ?w.configuration?.toJson(),
    };
  }

  /// `IWorkspaceEditingService.updateFolders(index, deleteCount, add,
  /// donotNotifyError: true)`.
  Future<void> updateFolders(
    int index,
    int deleteCount,
    List<WorkspaceFolderToAdd> add,
  ) async {
    final current = workspaceFolders;
    final toDelete = current
        .skip(index)
        .take(deleteCount)
        .map((f) => f.uri)
        .toList();
    final toAdd = [
      for (final f in add) (uri: _trimTrailingSlash(f.uri), name: f.name),
    ];
    if (toAdd.isEmpty && toDelete.isEmpty) return;
    final port = folders;
    if (port == null) {
      throw StateError('This workspace cannot change its folders');
    }
    final kept = [
      for (final f in current) (uri: f.uri, name: f.name as String?),
    ];
    if (state != WorkbenchState.workspace) {
      // A folder's window: replacing the folder, or adding one, enters a
      // workspace of the result.
      List<WorkspaceFolderToAdd> next;
      if (toDelete.isNotEmpty &&
          toAdd.isNotEmpty &&
          state == WorkbenchState.folder &&
          toDelete.any((u) => uriEqual(u, current.first.uri))) {
        next = toAdd;
      } else if (toAdd.isNotEmpty) {
        next = [...kept]..insertAll(index.clamp(0, kept.length), toAdd);
        next = _distinct(next);
        if (state == WorkbenchState.empty && next.isEmpty ||
            state == WorkbenchState.folder && next.length == 1) {
          return;
        }
      } else {
        // Removing the only folder of a folder's window: nothing upstream
        // can do but leave it (`removeFolders` needs a workspace).
        return;
      }
      await port.enterWorkspace(next);
      return;
    }
    final next = [
      for (final f in kept)
        if (!toDelete.any((u) => uriEqual(u, f.uri, ignoreCase: ignorePathCase)))
          f,
    ];
    // `WorkspaceService.doUpdateFolders`: added at [index] of what is
    // left, or at the end.
    next.insertAll(index >= 0 && index < next.length ? index : next.length, toAdd);
    await port.setFolders(_distinct(next));
  }

  List<WorkspaceFolderToAdd> _distinct(List<WorkspaceFolderToAdd> folders) {
    final seen = <String>{};
    return [
      for (final f in folders)
        if (seen.add(
          ignorePathCase ? f.uri.toString().toLowerCase() : f.uri.toString(),
        ))
          f,
    ];
  }

  static VsUri _trimTrailingSlash(VsUri uri) =>
      uri.path.length > 1 && uri.path.endsWith('/')
      ? uri.replace(path: uri.path.substring(0, uri.path.length - 1))
      : uri;
}
