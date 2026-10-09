// Which extensions are disabled, globally and per workspace, as VS Code's
// `IGlobalExtensionEnablementService` and `IWorkbenchExtensionEnablementService`
// keep them: the global disabled list, and per workspace the extensions
// disabled there and those enabled there though disabled globally.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/extensionManagement/common/extensionEnablementService.ts
// and src/vs/workbench/services/extensionManagement/browser/
// extensionEnablementService.ts (`_isDisabledGlobally`,
// `_isEnabledWorkspace`, `_isDisabledWorkspace`, the storage keys).
//
// Deviations:
// - Upstream keeps the lists in its storage service under
//   `extensionsIdentifiers/disabled` (profile and workspace scope) and
//   `extensionsIdentifiers/enabled` (workspace scope); BaoCode keeps them in
//   one JSON file in the data folder's state, the workspace's under its id.
// - Only the user's choices: environment-disabled extensions
//   (`--disable-extension`), virtual-workspace and trust gating are not here.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../window/json_state_store.dart';
import 'extension_management_backend.dart' show EnablementScope;

/// The user's extension enablement, kept in [store].
final class ExtensionEnablementStore extends ChangeNotifier {
  ExtensionEnablementStore(this.store);

  final JsonStateStore store;

  static const _globalDisabled = 'extensionsIdentifiers/disabled';
  static String _workspaceDisabled(String workspaceId) =>
      '$workspaceId/extensionsIdentifiers/disabled';
  static String _workspaceEnabled(String workspaceId) =>
      '$workspaceId/extensionsIdentifiers/enabled';

  Future<void> load() => store.load();

  Set<String> _ids(String key) => {
    for (final id in switch (store.getJson(key)) {
      final List<Object?> list => list,
      _ => const <Object?>[],
    })
      if (id is String) id.toLowerCase(),
  };

  void _setIds(String key, Set<String> ids) {
    if (ids.isEmpty) {
      store.remove(key);
    } else {
      store.setJson(key, ids.toList()..sort());
    }
  }

  /// Disabled everywhere unless a workspace enables it.
  bool isDisabledGlobally(String id) =>
      _ids(_globalDisabled).contains(id.toLowerCase());

  /// The workspace's own choice for [id]: true enabled there, false
  /// disabled there, null following the global one.
  bool? workspaceEnablement(String id, String workspaceId) {
    final lower = id.toLowerCase();
    if (_ids(_workspaceDisabled(workspaceId)).contains(lower)) return false;
    if (_ids(_workspaceEnabled(workspaceId)).contains(lower)) return true;
    return null;
  }

  /// Whether [id] runs in [workspaceId] (`isEnabledEnablementState`).
  bool isEnabled(String id, {String? workspaceId}) {
    if (workspaceId != null) {
      switch (workspaceEnablement(id, workspaceId)) {
        case final bool choice:
          return choice;
        case null:
          break;
      }
    }
    return !isDisabledGlobally(id);
  }

  /// `setEnablement`: [scope] global sets the global list (and drops the
  /// workspace's own choice, as upstream's `EnabledGlobally` does);
  /// workspace sets the workspace's.
  void setEnabled(
    String id,
    bool enabled, {
    EnablementScope scope = EnablementScope.global,
    String? workspaceId,
  }) {
    final lower = id.toLowerCase();
    switch (scope) {
      case EnablementScope.global:
        final disabled = _ids(_globalDisabled);
        enabled ? disabled.remove(lower) : disabled.add(lower);
        _setIds(_globalDisabled, disabled);
        if (workspaceId != null) _clearWorkspace(lower, workspaceId);
      case EnablementScope.workspace:
        if (workspaceId == null) {
          throw ArgumentError('A workspace enablement needs a workspace');
        }
        final disabled = _ids(_workspaceDisabled(workspaceId));
        final enabledThere = _ids(_workspaceEnabled(workspaceId));
        if (enabled) {
          disabled.remove(lower);
          // Enabled there only when it is disabled globally.
          if (isDisabledGlobally(lower)) {
            enabledThere.add(lower);
          } else {
            enabledThere.remove(lower);
          }
        } else {
          enabledThere.remove(lower);
          disabled.add(lower);
        }
        _setIds(_workspaceDisabled(workspaceId), disabled);
        _setIds(_workspaceEnabled(workspaceId), enabledThere);
    }
    notifyListeners();
  }

  void _clearWorkspace(String lower, String workspaceId) {
    final disabled = _ids(_workspaceDisabled(workspaceId))..remove(lower);
    final enabledThere = _ids(_workspaceEnabled(workspaceId))..remove(lower);
    _setIds(_workspaceDisabled(workspaceId), disabled);
    _setIds(_workspaceEnabled(workspaceId), enabledThere);
  }

  /// Forgets an uninstalled extension's choices everywhere it is global.
  void forget(String id) {
    final disabled = _ids(_globalDisabled)..remove(id.toLowerCase());
    _setIds(_globalDisabled, disabled);
    notifyListeners();
  }

  Future<void> flush() => store.flush();
}
