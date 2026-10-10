/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/secrets/common/secrets.ts (`BaseSecretStorageService`:
// operations queued by key, a change event only when a value really
// changed) and the key scheme of
// src/vs/workbench/api/browser/mainThreadSecretState.ts.
//
// Deviations: upstream encrypts each secret with Electron's safeStorage
// (whose key is in the system's keychain) and keeps it in the state
// database under `secret://{"extensionId":…,"key":…}`; this keeps each
// secret in the system's store itself ([SecretBackend]) under the account
// `<extensionId>/<key>`. The stores cannot all list their items, so the
// key names (not the values) of every extension are kept in a JSON file for
// `SecretStorage.keys()`. A set reads the old value first to tell whether
// it changed (upstream's storage compares the encrypted values).

import 'dart:async';

import '../json_state_store.dart';
import 'keyed_sequencer.dart';
import 'secret_backend.dart';

/// A secret of an extension changed (`{ extensionId, key }` of
/// `$onDidChangePassword`).
typedef ExtensionSecretChange = ({String extensionId, String key});

/// The extensions' secrets (`vscode.SecretStorage`), one for the app: every
/// workspace's extension host reads and writes through it and hears every
/// change ([changes]), as VS Code's windows share one secret storage.
final class ExtensionSecretService {
  /// Keeps the secrets in [backend] (see [SecretBackend.forPlatform]) and
  /// the extensions' key names in the JSON file [keyIndexPath] (for example
  /// `<data>/User/globalStorage/secret-keys.json`).
  ExtensionSecretService({required this.backend, required String keyIndexPath})
    : _index = JsonStateStore(keyIndexPath);

  final SecretBackend backend;
  final JsonStateStore _index;
  final _sequencer = KeyedSequencer<String>();
  final _changes = StreamController<ExtensionSecretChange>.broadcast(
    sync: true,
  );
  bool _disposed = false;

  /// Every secret set to another value or deleted, by any host; before the
  /// operation's future completes (upstream's storage fires as it stores).
  Stream<ExtensionSecretChange> get changes => _changes.stream;

  /// [extensionId]'s secret [key]; null when there is none.
  Future<String?> get(String extensionId, String key) =>
      _sequencer.queue(secretAccount(extensionId, key), () async {
        final value = await backend.read(secretAccount(extensionId, key));
        await _index.load();
        if (value == null) {
          _forget(extensionId, key);
        } else {
          _remember(extensionId, key);
        }
        return value;
      });

  /// Keeps [value] as [extensionId]'s secret [key].
  Future<void> set(String extensionId, String key, String value) =>
      _sequencer.queue(secretAccount(extensionId, key), () async {
        final account = secretAccount(extensionId, key);
        final (:known, :old) = await _readOld(account);
        await _index.load();
        if (known && old == value) {
          _remember(extensionId, key);
          return;
        }
        await backend.write(account, value);
        _remember(extensionId, key);
        _changed(extensionId, key);
      });

  /// Deletes [extensionId]'s secret [key].
  Future<void> delete(String extensionId, String key) =>
      _sequencer.queue(secretAccount(extensionId, key), () async {
        final account = secretAccount(extensionId, key);
        final (:known, :old) = await _readOld(account);
        await _index.load();
        if (known && old == null) {
          _forget(extensionId, key);
          return;
        }
        await backend.delete(account);
        _forget(extensionId, key);
        _changed(extensionId, key);
      });

  /// The keys of [extensionId]'s secrets, in the order they were first set.
  Future<List<String>> keys(String extensionId) async {
    await _index.load();
    return _keys(extensionId);
  }

  /// Writes the key index now.
  Future<void> flush() => _index.flush();

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _index.dispose();
    await _changes.close();
  }

  /// The value [account] has; `known` false when it could not be read (a
  /// set or delete then goes ahead and reports a change).
  Future<({bool known, String? old})> _readOld(String account) async {
    try {
      return (known: true, old: await backend.read(account));
    } on Object {
      return (known: false, old: null);
    }
  }

  List<String> _keys(String extensionId) =>
      switch (_index.getJson(extensionId)) {
        final List<Object?> keys => [...keys.whereType<String>()],
        _ => [],
      };

  void _remember(String extensionId, String key) {
    final keys = _keys(extensionId);
    if (keys.contains(key)) return;
    _index.setJson(extensionId, [...keys, key]);
  }

  void _forget(String extensionId, String key) {
    final keys = _keys(extensionId);
    if (!keys.remove(key)) return;
    if (keys.isEmpty) {
      _index.remove(extensionId);
    } else {
      _index.setJson(extensionId, keys);
    }
  }

  void _changed(String extensionId, String key) {
    if (!_disposed) _changes.add((extensionId: extensionId, key: key));
  }
}
