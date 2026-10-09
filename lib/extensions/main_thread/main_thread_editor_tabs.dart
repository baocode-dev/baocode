/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The tab model: the tabs of BaoCode's editor and their properties, sent
// whole (`$acceptEditorTabModel`) with the smaller updates operations bring
// (`$acceptTabOperation`), and the three operations the extension can ask
// for (`$moveTab`, `$closeTab`, `$closeGroup`).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadEditorTabs.ts
// (`MainThreadEditorTabs._createTabsModel`, `_buildTabObject` with its
// `generateTabId`, `_editorInputToDto`, `_updateTabsModel`'s operations,
// `$moveTab`, `$closeTab`, `$closeGroup`).
//
// Deviations:
// - BaoCode has one editor group: every tab is in group 0 (viewColumn 1),
//   and `$closeGroup` only accepts it.
// - `_generateTabId` is `<path>\\0<label>`: stable while the tab lives and
//   unique per tab (the app's `IdeDocument.key`), so the extension can hold
//   a `Tab` across updates.
// - Tabs whose input is not text (an image preview, a diff of two texts)
//   are `UnknownInput`, as upstream's `_editorInputToDto` falls back to;
//   the app's diff tabs are `TextDiffInput` when both sides are files.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../editors/editor_ports.dart';
import 'main_thread_context.dart';

/// `TabInputKind`.
abstract final class TabInputKind {
  static const int unknownInput = 0;
  static const int textInput = 1;
  static const int textDiffInput = 2;
}

/// `TabModelOperationKind`.
abstract final class TabModelOperationKind {
  static const int tabOpen = 0;
  static const int tabClose = 1;
  static const int tabUpdate = 2;
  static const int tabMove = 3;
}

final class MainThreadEditorTabs extends MainThreadEditorTabsUnsupported {
  MainThreadEditorTabs({required this.tabs, required RpcProtocol rpc}) {
    _proxy = ExtHostEditorTabsProxy(rpc);
  }

  final EditorTabsHost tabs;
  late final ExtHostEditorTabsProxy _proxy;

  List<Map<String, Object?>>? _lastModel;
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// Sends the whole model, once, and again whenever the tab strip's set
  /// of tabs changes (`_createTabsModel`).
  void start() {
    _sendModel();
    _subscriptions.add(tabs.tabOperations.listen(_sendOperation));
  }

  void _sendModel() {
    final model = _tabGroupModel();
    if (model.isEmpty) return;
    _lastModel = model;
    unawaited(_proxy.$acceptEditorTabModel(model));
  }

  /// `_createTabsModel`: the groups with their tabs, as
  /// `IEditorTabGroupDto`s.
  List<Map<String, Object?>> _tabGroupModel() {
    final result = <Map<String, Object?>>[];
    for (final groupId in tabs.groupIds) {
      final groupTabs = [
        for (final tab in tabs.tabs)
          if (tab.groupId == groupId) editorTabDto(tab),
      ];
      if (groupTabs.isEmpty) continue;
      result.add({
        'groupId': groupId,
        'isActive': groupId == tabs.activeGroupId,
        'viewColumn': groupTabs.isEmpty ? 1 : _viewColumnOf(groupId),
        'tabs': groupTabs,
      });
    }
    return result;
  }

  int _viewColumnOf(int groupId) {
    for (final tab in tabs.tabs) {
      if (tab.groupId == groupId) return tab.viewColumn;
    }
    return groupId + 1;
  }

  void _sendOperation(Map<String, Object?> operation) {
    unawaited(_proxy.$acceptTabOperation(operation));
    // A group's tabs changed: a whole model keeps the extension's view
    // consistent (upstream rebuilds it for its non-optimized cases too).
    if (operation['kind'] == TabModelOperationKind.tabOpen ||
        operation['kind'] == TabModelOperationKind.tabClose) {
      _sendModel();
    }
  }

  // --- from the extension host

  @override
  void $moveTab(String tabId, num index, num viewColumn, bool? preserveFocus) =>
      tabs.moveTab(
        tabId,
        index.toInt(),
        column: viewColumn.toInt(),
        preserveFocus: preserveFocus,
      );

  @override
  Future<bool> $closeTab(List<String> tabIds, bool? preserveFocus) async {
    for (final tabId in tabIds) {
      if (!tabs.hasTab(tabId)) return false;
    }
    return tabs.closeTabs(tabIds, preserveFocus: preserveFocus);
  }

  @override
  Future<bool> $closeGroup(List<num> groupIds, bool? preservceFocus) async {
    for (final groupId in groupIds) {
      if (groupId.toInt() != 0) return false;
    }
    return tabs.closeGroup(0, preserveFocus: preservceFocus);
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  /// The model last sent (for checks).
  List<Map<String, Object?>>? get lastModel => _lastModel;
}

/// `_buildTabObject`: one tab's DTO (`IEditorTabDto`).
Map<String, Object?> editorTabDto(EditorTabInfo tab) => {
  'id': tab.tabId,
  'label': tab.label,
  'input': _inputDto(tab),
  'isActive': tab.isActive,
  'isPinned': tab.isPinned,
  'isPreview': tab.isPreview,
  'isDirty': tab.isDirty,
};

/// `_editorInputToDto`: a text editor's resource, a diff's two sides, or
/// unknown for anything else (an image preview).
Map<String, Object?> _inputDto(EditorTabInfo tab) {
  if (tab.isDiff) {
    return {
      'kind': TabInputKind.textDiffInput,
      'original': tab.originalUri!.toJson(),
      'modified': tab.modifiedUri!.toJson(),
    };
  }
  if (tab.uri case final uri?) {
    return {'kind': TabInputKind.textInput, 'uri': uri.toJson()};
  }
  return {'kind': TabInputKind.unknownInput};
}

/// The actor of `MainContext.mainThreadEditorTabs`.
RpcActor mainThreadEditorTabsActor(MainThreadContext context) {
  final tabs = context.service<EditorTabsHost>();
  final actor = MainThreadEditorTabs(tabs: tabs, rpc: context.rpc)..start();
  context.onDispose(actor.dispose);
  return MainThreadEditorTabsActor(actor);
}
