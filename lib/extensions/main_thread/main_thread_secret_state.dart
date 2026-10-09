/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadSecretState.ts.
//
// Deviations: the secrets are kept by ExtensionSecretService (one for the
// app) in the system's store by extension id and key, not under a JSON key
// in VS Code's secret storage; `$getKeys` reads that service's key index,
// so it works on every store (upstream throws where the storage cannot
// list keys). No trace logging.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../window/secrets/extension_secret_service.dart';
import '../window/secrets/keyed_sequencer.dart';
import 'main_thread_context.dart';

/// `vscode.SecretStorage` (`context.secrets`) of one extension host.
final class MainThreadSecretState extends MainThreadSecretStateUnsupported {
  MainThreadSecretState(this._secrets);

  final ExtensionSecretService _secrets;

  /// Upstream's `_sequencer`: one extension's calls in the order they came.
  final _sequencer = KeyedSequencer<String>();

  /// The actor of [context]'s host: every change of the app's secrets, by
  /// any host, goes to it as `$onDidChangePassword`.
  static RpcActor customer(MainThreadContext context) {
    final secrets = context.service<ExtensionSecretService>();
    final proxy = ExtHostSecretStateProxy(context.rpc);
    context.listen(
      secrets.changes.listen((change) {
        unawaited(
          proxy
              .$onDidChangePassword({
                'extensionId': change.extensionId,
                'key': change.key,
              })
              .catchError((Object _) {}),
        );
      }),
    );
    return MainThreadSecretStateActor(MainThreadSecretState(secrets));
  }

  @override
  Future<String?> $getPassword(String extensionId, String key) =>
      _sequencer.queue(extensionId, () => _secrets.get(extensionId, key));

  @override
  Future<void> $setPassword(String extensionId, String key, String value) =>
      _sequencer.queue(
        extensionId,
        () => _secrets.set(extensionId, key, value),
      );

  @override
  Future<void> $deletePassword(String extensionId, String key) =>
      _sequencer.queue(extensionId, () => _secrets.delete(extensionId, key));

  @override
  Future<List<String>> $getKeys(String extensionId) =>
      _sequencer.queue(extensionId, () => _secrets.keys(extensionId));
}
