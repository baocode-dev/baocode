/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The context keys extensions' `when` clauses read most, written by the
// workbench through a [ContextKeyFeed]. Their names and values are VS
// Code's.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/common/contextkeys.ts (`ResourceContextKey`'s
// `resource*` keys, `WorkbenchStateContext`, `WorkspaceFolderCountContext`,
// `SideBarVisibleContext`, `PanelVisibleContext`, `ActiveViewletContext`,
// `FocusedViewContext`, `ActiveEditorContext`…),
// src/vs/editor/common/editorContextKeys.ts (`editorTextFocus`,
// `editorFocus`, `editorLangId`, `editorHasSelection`, `editorReadonly`,
// `textInputFocus`), src/vs/workbench/contrib/debug/common/debug.ts
// (`inDebugMode`, `debugType`, `debugState`),
// src/vs/workbench/contrib/files/common/files.ts (`explorerViewletVisible`,
// `explorerResourceIsFolder`), src/vs/workbench/contrib/terminal/common/
// terminalContextKey.ts (`terminalFocus`).
//
// How the workbench feeds them (the lead wires it): make one
// [WorkbenchContextKeys] over the workspace's [ContextKeyService] and call
// its setters when the state changes (the active editor, focus, layout,
// debug, SCM); keys it computes lazily already (its `keyContext`) can be
// read instead by setting [ContextKeyService.fallback] and calling
// [ContextKeyService.notifyExternalChange] when they may have changed.
// Per-item keys (`view`, `viewItem`, `scmResourceGroup`,
// `scmResourceState`, an explorer item's `resource*`) go in an overlay for
// the one menu ([resourceContextKeys], [AbstractContextKeyService.createOverlay]).

import 'package:bao_exthost/bao_exthost.dart';
import 'package:path/path.dart' as p;

import 'context_key_service.dart';

/// The well-known keys' names.
abstract final class WorkbenchContextKeyNames {
  static const editorTextFocus = 'editorTextFocus';
  static const editorFocus = 'editorFocus';
  static const textInputFocus = 'textInputFocus';
  static const inputFocus = 'inputFocus';
  static const editorLangId = 'editorLangId';
  static const editorHasSelection = 'editorHasSelection';
  static const editorReadonly = 'editorReadonly';
  static const activeEditor = 'activeEditor';
  static const activeEditorIsDirty = 'activeEditorIsDirty';
  static const resource = 'resource';
  static const resourceScheme = 'resourceScheme';
  static const resourceFilename = 'resourceFilename';
  static const resourceDirname = 'resourceDirname';
  static const resourcePath = 'resourcePath';
  static const resourceLangId = 'resourceLangId';
  static const resourceExtname = 'resourceExtname';
  static const resourceSet = 'resourceSet';
  static const isFileSystemResource = 'isFileSystemResource';
  static const isWindows = 'isWindows';
  static const isMac = 'isMac';
  static const isLinux = 'isLinux';
  static const isWeb = 'isWeb';
  static const workspaceFolderCount = 'workspaceFolderCount';
  static const workbenchState = 'workbenchState';
  static const explorerResourceIsFolder = 'explorerResourceIsFolder';
  static const explorerViewletVisible = 'explorerViewletVisible';
  static const sideBarVisible = 'sideBarVisible';
  static const panelVisible = 'panelVisible';
  static const activeViewlet = 'activeViewlet';
  static const activePanel = 'activePanel';
  static const focusedView = 'focusedView';
  static const view = 'view';
  static const viewItem = 'viewItem';
  static const inDebugMode = 'inDebugMode';
  static const debugType = 'debugType';
  static const debugState = 'debugState';
  static const scmProvider = 'scmProvider';
  static const scmResourceGroup = 'scmResourceGroup';
  static const scmResourceState = 'scmResourceState';
  static const terminalFocus = 'terminalFocus';
  static const gitOpenRepositoryCount = 'gitOpenRepositoryCount';
}

/// The `resource*` keys of [resource] (`ResourceContextKey.set`): for the
/// global context (the active editor's) or an overlay (an explorer item's).
/// [windows]: whether `file:` paths are Windows paths.
Map<String, Object?> resourceContextKeys(
  VsUri? resource, {
  String? languageId,
  bool? isFileSystemResource,
  bool windows = false,
}) {
  if (resource == null) {
    return const {
      WorkbenchContextKeyNames.resource: null,
      WorkbenchContextKeyNames.resourceScheme: null,
      WorkbenchContextKeyNames.resourceFilename: null,
      WorkbenchContextKeyNames.resourceDirname: null,
      WorkbenchContextKeyNames.resourcePath: null,
      WorkbenchContextKeyNames.resourceLangId: null,
      WorkbenchContextKeyNames.resourceExtname: null,
      WorkbenchContextKeyNames.resourceSet: false,
      WorkbenchContextKeyNames.isFileSystemResource: false,
    };
  }
  String uriToPath(VsUri uri) =>
      uri.scheme == 'file' ? uri.fsPath(windows: windows) : uri.path;
  final path = resource.path;
  final basename = p.posix.basename(path);
  final dirPath = p.posix.dirname(path);
  final dirname = resource.replace(path: dirPath.isEmpty ? '/' : dirPath);
  final dot = basename.lastIndexOf('.');
  return {
    WorkbenchContextKeyNames.resource: resource.toString(),
    WorkbenchContextKeyNames.resourceScheme: resource.scheme,
    WorkbenchContextKeyNames.resourceFilename: basename,
    WorkbenchContextKeyNames.resourceDirname: uriToPath(dirname),
    WorkbenchContextKeyNames.resourcePath: uriToPath(resource),
    WorkbenchContextKeyNames.resourceLangId: languageId,
    // `resources.extname`: from the last dot of the last segment.
    WorkbenchContextKeyNames.resourceExtname: dot <= 0
        ? ''
        : basename.substring(dot),
    WorkbenchContextKeyNames.resourceSet: true,
    WorkbenchContextKeyNames.isFileSystemResource:
        isFileSystemResource ??
        const {'file', 'vscode-remote', 'vscode-userdata'}.contains(
          resource.scheme,
        ),
  };
}

/// The keys of one SCM item, for an overlay
/// ([AbstractContextKeyService.createOverlay]) while its menus are
/// evaluated: `scmProvider`, `scmResourceGroup`, `scmResourceState`.
Map<String, Object?> scmContextKeys({
  String? provider,
  String? resourceGroup,
  String? resourceState,
}) => {
  WorkbenchContextKeyNames.scmProvider: provider,
  WorkbenchContextKeyNames.scmResourceGroup: resourceGroup,
  WorkbenchContextKeyNames.scmResourceState: resourceState,
};

/// The keys of one view item (`view`, `viewItem`), for an overlay while a
/// `view/item/context` or `view/title` menu is evaluated.
Map<String, Object?> viewContextKeys({required String view, String? item}) => {
  WorkbenchContextKeyNames.view: view,
  WorkbenchContextKeyNames.viewItem: item,
};

/// Typed setters for the well-known keys, writing through [feed].
final class WorkbenchContextKeys {
  WorkbenchContextKeys(this.feed, {this.windows = false});

  final ContextKeyFeed feed;

  /// Whether `file:` paths are Windows paths.
  final bool windows;

  void _setAll(Map<String, Object?> values) => feed.bufferChangeEvents(() {
    for (final MapEntry(:key, :value) in values.entries) {
      if (value == null) {
        feed.removeContext(key);
      } else {
        feed.setContext(key, value);
      }
    }
  });

  /// `workspaceFolderCount`, `workbenchState` (`empty`, `folder` or
  /// `workspace`).
  void setWorkspace({required int folderCount, required String state}) =>
      _setAll({
        WorkbenchContextKeyNames.workspaceFolderCount: folderCount,
        WorkbenchContextKeyNames.workbenchState: state,
      });

  /// The active editor: its resource's keys, `editorLangId`,
  /// `activeEditor` (an editor type id, `workbench.editors.files.textFileEditor`),
  /// `editorReadonly`, `activeEditorIsDirty`. Null [resource]: none.
  void setActiveEditor({
    VsUri? resource,
    String? languageId,
    String? editorId,
    bool readonly = false,
    bool dirty = false,
  }) => _setAll({
    ...resourceContextKeys(resource, languageId: languageId, windows: windows),
    WorkbenchContextKeyNames.editorLangId: resource == null ? null : languageId,
    WorkbenchContextKeyNames.activeEditor: editorId,
    WorkbenchContextKeyNames.editorReadonly: readonly,
    WorkbenchContextKeyNames.activeEditorIsDirty: dirty,
  });

  /// Focus: `editorFocus`, `editorTextFocus`, `textInputFocus`,
  /// `inputFocus`, `terminalFocus`, `focusedView` (a view id, '' for none).
  void setFocus({
    bool editorFocus = false,
    bool editorTextFocus = false,
    bool textInputFocus = false,
    bool inputFocus = false,
    bool terminalFocus = false,
    String focusedView = '',
  }) => _setAll({
    WorkbenchContextKeyNames.editorFocus: editorFocus,
    WorkbenchContextKeyNames.editorTextFocus: editorTextFocus,
    WorkbenchContextKeyNames.textInputFocus: textInputFocus,
    WorkbenchContextKeyNames.inputFocus: inputFocus,
    WorkbenchContextKeyNames.terminalFocus: terminalFocus,
    WorkbenchContextKeyNames.focusedView: focusedView,
  });

  /// `editorHasSelection`.
  void setEditorSelection({required bool hasSelection}) => _setAll({
    WorkbenchContextKeyNames.editorHasSelection: hasSelection,
  });

  /// `sideBarVisible`, `panelVisible`, `activeViewlet`
  /// (`workbench.view.explorer`, `workbench.view.extension.<id>`…),
  /// `activePanel`, `explorerViewletVisible`.
  void setLayout({
    required bool sideBarVisible,
    required bool panelVisible,
    String? activeViewlet,
    String? activePanel,
  }) => _setAll({
    WorkbenchContextKeyNames.sideBarVisible: sideBarVisible,
    WorkbenchContextKeyNames.panelVisible: panelVisible,
    WorkbenchContextKeyNames.activeViewlet: activeViewlet ?? '',
    WorkbenchContextKeyNames.activePanel: activePanel ?? '',
    WorkbenchContextKeyNames.explorerViewletVisible:
        sideBarVisible && activeViewlet == 'workbench.view.explorer',
  });

  /// The explorer's focused item: `explorerResourceIsFolder`.
  void setExplorerSelection({required bool isFolder}) => _setAll({
    WorkbenchContextKeyNames.explorerResourceIsFolder: isFolder,
  });

  /// `inDebugMode`, `debugType`, `debugState` (`inactive`, `initializing`,
  /// `stopped`, `running`).
  void setDebug({
    required bool inDebugMode,
    String? debugType,
    String debugState = 'inactive',
  }) => _setAll({
    WorkbenchContextKeyNames.inDebugMode: inDebugMode,
    WorkbenchContextKeyNames.debugType: debugType,
    WorkbenchContextKeyNames.debugState: debugState,
  });

  /// `gitOpenRepositoryCount` (the git extension sets it itself through
  /// `setContext` when it runs; BaoCode's own Git view may set it too).
  void setGitOpenRepositoryCount(int count) => _setAll({
    WorkbenchContextKeyNames.gitOpenRepositoryCount: '$count',
  });
}
