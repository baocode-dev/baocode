/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Starting an extension host through a server: the connection, the
// Ready → init data → Initialized handshake, then RPC.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/extensions/common/remoteExtensionHost.ts
// (`RemoteExtensionHost.start`, `_onExtHostConnection`) and
// src/vs/workbench/services/extensions/common/extensionHostProtocol.ts
// (`MessageType`, `isMessageOfType`).
//
// Deviations:
// - No reconnection: a lost connection ends this host (and its owner
//   starts a new one).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';

import 'extension_host_manager.dart';

/// `MessageType` of the extension host handshake.
abstract final class ExtHostMessageType {
  static const initialized = 1;
  static const ready = 2;
  static const terminate = 3;
}

/// The extension host could not start.
final class ExtHostStartException implements Exception {
  const ExtHostStartException(this.message);

  final String message;

  @override
  String toString() => 'Extension host: $message';
}

/// An extension host after its handshake: [rpc] talks to it.
final class ExtHostConnection implements ExtHostSession {
  ExtHostConnection._(this._connection, this.rpc, this.debugPort);

  final RemoteConnection _connection;
  @override
  final RpcProtocol rpc;

  /// The inspector port when started for debugging.
  final int? debugPort;

  final _closed = Completer<void>();

  @override
  Future<void> get closed => _closed.future;
  bool get isClosed => _closed.isCompleted;

  /// Connects to the server at [address], starts an extension host with
  /// [initData] (an `IExtensionHostInitData`), and sets up [actors] (rpc id
  /// → main thread actor) before any request is read. [actorsFor] may
  /// instead make them from the new protocol.
  static Future<ExtHostConnection> start(
    ServerAddress address, {
    required Map<String, Object?> Function() initData,
    required Map<int, RpcActor> Function(RpcProtocol rpc) actorsFor,
    required Map<int, String> actorNames,
    String language = 'en',
    Map<String, String> environment = const {},
    int? debugPort,
    bool breakOnStart = false,
    SocketConnector? connector,
    RpcLogger? logger,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final args = <String, Object?>{
      'language': language,
      'env': environment,
      'port': ?debugPort,
      if (debugPort != null) 'break': breakOnStart,
    };
    final connection = connector == null
        ? await connectToServer(
            address,
            ConnectionType.extensionHost,
            args: args,
          )
        : await connectToServer(
            address,
            ConnectionType.extensionHost,
            args: args,
            connector: connector,
          );
    final protocol = connection.protocol;
    final ready = Completer<void>();
    final initialized = Completer<void>();
    protocol.onMessage.listener = (Uint8List message) {
      if (_isMessageOfType(message, ExtHostMessageType.ready)) {
        if (!ready.isCompleted) ready.complete();
      } else if (_isMessageOfType(message, ExtHostMessageType.initialized)) {
        // What follows is RPC: stop listening now, so that it is buffered
        // until the protocol below takes over.
        protocol.onMessage.listener = null;
        if (!initialized.isCompleted) initialized.complete();
      }
    };
    protocol.onDidDispose.listener = (_) {
      const error = ExtHostStartException('connection closed while starting');
      if (!ready.isCompleted) ready.completeError(error);
      if (!initialized.isCompleted) initialized.completeError(error);
    };
    try {
      await ready.future.timeout(timeout);
      protocol.send(utf8.encode(jsonEncode(initData(), toEncodable: _json)));
      await initialized.future.timeout(timeout);
    } on Object catch (e) {
      protocol.dispose();
      await protocol.close();
      if (e is TimeoutException) {
        throw const ExtHostStartException('did not answer in time');
      }
      rethrow;
    }
    final rpc = RpcProtocol(
      ProtocolMessagePassing(protocol),
      actorNames: actorNames,
      logger: logger,
    );
    // Set before the buffered requests are delivered (a microtask later).
    try {
      actorsFor(rpc).forEach(rpc.set);
    } on Object {
      protocol.dispose();
      await protocol.close();
      rethrow;
    }
    final result = ExtHostConnection._(
      connection,
      rpc,
      connection.firstMessage['debugPort'] as int?,
    );
    void end([_]) {
      if (!result._closed.isCompleted) result._closed.complete();
    }

    protocol.onDidDispose.listener = end;
    protocol.onSocketClose.listener = end;
    return result;
  }

  /// Asks the extension host to end (`MessageType.Terminate`), then closes.
  @override
  Future<void> terminate() async {
    if (isClosed) return;
    final protocol = _connection.protocol;
    try {
      protocol.send(Uint8List.fromList(_message(ExtHostMessageType.terminate)));
      await protocol.drain();
    } on Object {
      // Already gone.
    }
    rpc.dispose();
    protocol.dispose();
    await protocol.close();
    if (!_closed.isCompleted) _closed.complete();
  }

  static Object? _json(Object? value) => switch (value) {
    VsUri() => value.toJson(),
    _ => throw JsonUnsupportedObjectError(value),
  };
}

/// `createMessageOfType`: the 1-byte messages are the type itself.
List<int> _message(int type) => [type];

/// `isMessageOfType`.
bool _isMessageOfType(Uint8List message, int type) =>
    message.length == 1 && message[0] == type;
