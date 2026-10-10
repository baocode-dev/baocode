/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/extensionManagement/common/extensionStorage.ts
// (`ExtensionStorageService`: an extension's state is one JSON string
// under its id, global or the workspace's; the keys it syncs under
// `extensionKeys/<id>@<version>`).
//
// Deviations: kept in JSON files (`<data>/User/globalStorage/state.json`
// and `<data>/User/workspaceStorage/<workspace id>/state.json`) where
// upstream has SQLite databases; no migration list (it serves renamed
// extensions and Settings Sync, which BaoCode does not have).

import 'package:path/path.dart' as p;

import 'json_state_store.dart';

/// The extensions' global and workspace state of the app.
final class ExtensionStorageService {
  ExtensionStorageService({required this.userDir});

  /// `<data>/User`.
  final String userDir;

  late final JsonStateStore global = JsonStateStore(
    p.join(userDir, 'globalStorage', 'state.json'),
  );

  final Map<String, JsonStateStore> _workspaces = {};

  /// The state of workspace [workspaceId].
  JsonStateStore workspace(String workspaceId) => _workspaces[workspaceId] ??=
      JsonStateStore(
        p.join(userDir, 'workspaceStorage', workspaceId, 'state.json'),
      );

  JsonStateStore _store(bool global, String workspaceId) =>
      global ? this.global : workspace(workspaceId);

  /// `getExtensionStateRaw`.
  Future<String?> getExtensionStateRaw(
    String extensionId, {
    required bool global,
    required String workspaceId,
  }) async {
    final store = _store(global, workspaceId);
    await store.load();
    return store.get(extensionId);
  }

  /// `setExtensionState`: null removes it.
  Future<void> setExtensionState(
    String extensionId,
    Object? state, {
    required bool global,
    required String workspaceId,
  }) async {
    final store = _store(global, workspaceId);
    await store.load();
    if (state == null) {
      store.remove(extensionId);
    } else {
      store.setJson(extensionId, state);
    }
  }

  /// `setKeysForSync`.
  Future<void> setKeysForSync(
    String extensionId,
    String version,
    List<String> keys,
  ) async {
    await global.load();
    global.setJson('extensionKeys/${extensionId.toLowerCase()}@$version', keys);
  }

  /// `getKeysForSync`.
  List<String>? getKeysForSync(String extensionId, String version) =>
      switch (global.getJson(
        'extensionKeys/${extensionId.toLowerCase()}@$version',
      )) {
        final List<Object?> keys => keys.whereType<String>().toList(),
        _ => null,
      };

  /// Writes what is pending.
  Future<void> flush() async {
    await global.flush();
    for (final store in _workspaces.values) {
      await store.flush();
    }
  }
}
