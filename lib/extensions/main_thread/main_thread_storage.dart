/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadStorage.ts.
//
// Deviations: no storage migration (see extension_storage.dart).

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../extension_host_service_io.dart';
import '../window/extension_storage.dart';
import 'main_thread_context.dart';

final class MainThreadStorage extends MainThreadStorageUnsupported {
  MainThreadStorage(
    this._storage,
    this._proxy, {
    required this.workspaceId,
    MainThreadContext? context,
  }) {
    // Changes of the global state (from any workspace's host) go to the
    // extensions that read it here.
    final subscription = _storage.global.changes.listen((change) {
      final value = change.value;
      if (value != null && _sharedKeysToWatch.contains(change.key)) {
        unawaited(
          _proxy.$acceptValue(true, change.key, value).catchError((Object _) {}),
        );
      }
    });
    context?.listen(subscription);
  }

  final ExtensionStorageService _storage;
  final ExtHostStorageProxy _proxy;
  final String workspaceId;
  final Set<String> _sharedKeysToWatch = {};

  static RpcActor customer(MainThreadContext context) => MainThreadStorageActor(
    MainThreadStorage(
      context.service<ExtensionStorageService>(),
      ExtHostStorageProxy(context.rpc),
      workspaceId: context.service<ExtensionHostService>().workspace.id,
      context: context,
    ),
  );

  @override
  Future<String?> $initializeExtensionStorage(
    bool shared,
    String extensionId,
  ) {
    if (shared) _sharedKeysToWatch.add(extensionId);
    return _storage.getExtensionStateRaw(
      extensionId,
      global: shared,
      workspaceId: workspaceId,
    );
  }

  @override
  Future<void> $setValue(
    bool shared,
    String extensionId,
    Object? value,
  ) => _storage.setExtensionState(
    extensionId,
    value,
    global: shared,
    workspaceId: workspaceId,
  );

  @override
  void $registerExtensionStorageKeysToSync(
    Map<String, Object?> extension,
    List<String> keys,
  ) => unawaited(
    _storage.setKeysForSync(
      '${extension['id']}',
      '${extension['version']}',
      keys,
    ),
  );
}
