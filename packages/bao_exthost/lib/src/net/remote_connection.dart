/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Connecting to a VS Code server: the HTTP upgrade to a raw socket, then
// the auth → sign → connectionType handshake.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/remote/common/remoteAgentConnection.ts
// (`connectToRemoteExtensionHostAgent`, `ConnectionType`, the handshake
// messages) and src/vs/platform/remote/common/managedSocket.ts
// (`makeRawSocketHeaders`).
//
// Deviations:
// - No `vsda` signing: a server without it (every Code-OSS build) accepts
//   any signed data, and we send its data back as signed.
// - No reconnection; a fresh reconnection token for every connection.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'persistent_protocol.dart';
import 'socket.dart';

/// `ConnectionType`.
enum ConnectionType {
  management(1),
  extensionHost(2),
  tunnel(3);

  const ConnectionType(this.value);

  final int value;
}

/// Where a server listens and how to get in.
final class ServerAddress {
  const ServerAddress({
    required this.host,
    required this.port,
    required this.connectionToken,
    required this.commit,
  });

  final String host;
  final int port;

  /// The server's `--connection-token`.
  final String connectionToken;

  /// The server's product commit: it refuses another.
  final String commit;
}

/// The server refused, or the handshake broke.
final class RemoteConnectionException implements Exception {
  const RemoteConnectionException(this.message);

  final String message;

  @override
  String toString() => 'RemoteConnectionException: $message';
}

/// Opens a socket to [address] (local TCP by default).
typedef SocketConnector =
    Future<ExtHostSocket> Function(String host, int port);

Future<ExtHostSocket> _connectTcp(String host, int port) async =>
    IoExtHostSocket(
      await Socket.connect(host, port, timeout: const Duration(seconds: 10)),
    );

final _random = Random.secure();

String _uuid() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// The socket after the HTTP upgrade, with what arrived past the headers.
final class _UpgradedSocket implements ExtHostSocket {
  _UpgradedSocket(this._inner, this._data);

  final ExtHostSocket _inner;
  final Stream<Uint8List> _data;

  @override
  Stream<Uint8List> get data => _data;

  @override
  void write(Uint8List bytes) => _inner.write(bytes);

  @override
  Future<void> drain() => _inner.drain();

  @override
  Future<void> close() => _inner.close();
}

/// `makeRawSocketHeaders` + `connectManagedSocket`: the upgrade request,
/// then everything after the response's headers.
Future<ExtHostSocket> _upgrade(ExtHostSocket socket, String query) async {
  final nonce = base64.encode(List<int>.generate(16, (_) => _random.nextInt(256)));
  socket.write(
    utf8.encode(
      [
        'GET ws://localhost/?$query&skipWebSocketFrames=true HTTP/1.1',
        'Connection: Upgrade',
        'Upgrade: websocket',
        'Sec-WebSocket-Key: $nonce',
        '',
        '',
      ].join('\r\n'),
    ),
  );
  final rest = StreamController<Uint8List>();
  final headers = Completer<String>();
  final soFar = BytesBuilder();
  late final StreamSubscription<Uint8List> sub;
  sub = socket.data.listen(
    (chunk) {
      if (headers.isCompleted) {
        rest.add(chunk);
        return;
      }
      soFar.add(chunk);
      final bytes = soFar.toBytes();
      final end = _indexOfHeaderEnd(bytes);
      if (end == -1) return;
      headers.complete(latin1.decode(bytes.sublist(0, end)));
      if (end + 4 < bytes.length) {
        rest.add(Uint8List.sublistView(bytes, end + 4));
      }
    },
    onError: (Object e) {
      if (!headers.isCompleted) headers.completeError(e);
      rest.addError(e);
    },
    onDone: () {
      if (!headers.isCompleted) {
        headers.completeError(
          const RemoteConnectionException('socket closed during upgrade'),
        );
      }
      rest.close();
    },
  );
  rest.onCancel = sub.cancel;
  final response = await headers.future.timeout(
    const Duration(seconds: 10),
    onTimeout: () {
      sub.cancel();
      throw const RemoteConnectionException('upgrade timed out');
    },
  );
  final status = response.split('\r\n').first;
  if (!status.contains(' 101 ')) {
    await sub.cancel();
    await socket.close();
    throw RemoteConnectionException('upgrade refused: $status');
  }
  return _UpgradedSocket(socket, rest.stream);
}

int _indexOfHeaderEnd(Uint8List b) {
  for (var i = 0; i + 3 < b.length; i++) {
    if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) {
      return i;
    }
  }
  return -1;
}

/// A connection after its handshake: the protocol, and the server's first
/// message after `connectionType` (`{type: 'ok'}`, or `{debugPort}` for an
/// extension host).
final class RemoteConnection {
  RemoteConnection(this.protocol, this.firstMessage, this.reconnectionToken);

  final PersistentProtocol protocol;
  final Map<String, Object?> firstMessage;
  final String reconnectionToken;
}

/// Connects to [address] as [type] (`connectToRemoteExtensionHostAgent` and
/// `connectToRemoteExtensionHostAgentAndReadOneMessage`).
Future<RemoteConnection> connectToServer(
  ServerAddress address,
  ConnectionType type, {
  Object? args,
  SocketConnector connector = _connectTcp,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final reconnectionToken = _uuid();
  final raw = await connector(address.host, address.port);
  final socket = await _upgrade(
    raw,
    'reconnectionToken=$reconnectionToken&reconnection=false',
  );
  final protocol = PersistentProtocol(socket);
  Future<Map<String, Object?>> nextControl() {
    final completer = Completer<Map<String, Object?>>();
    protocol.onControlMessage.listener = (raw) {
      protocol.onControlMessage.listener = null;
      try {
        completer.complete(
          (jsonDecode(utf8.decode(raw)) as Map).cast<String, Object?>(),
        );
      } on Object catch (e) {
        completer.completeError(e);
      }
    };
    protocol.onDidDispose.listener = (_) {
      if (!completer.isCompleted) {
        completer.completeError(
          const RemoteConnectionException('connection closed during handshake'),
        );
      }
    };
    return completer.future.timeout(timeout);
  }

  try {
    protocol.sendControl(
      utf8.encode(
        jsonEncode({
          'type': 'auth',
          'auth': address.connectionToken,
          'data': _uuid(),
        }),
      ),
    );
    final sign = await nextControl();
    if (sign['type'] == 'error') {
      throw RemoteConnectionException('${sign['reason']}');
    }
    if (sign['type'] != 'sign' || sign['data'] is! String) {
      throw const RemoteConnectionException('Unexpected handshake message');
    }
    protocol.sendControl(
      utf8.encode(
        jsonEncode({
          'type': 'connectionType',
          'commit': address.commit,
          'signedData': sign['data'],
          'desiredConnectionType': type.value,
          'args': ?args,
        }),
      ),
    );
    final first = await nextControl();
    if (first['type'] == 'error') {
      throw RemoteConnectionException('${first['reason']}');
    }
    protocol.onDidDispose.listener = null;
    return RemoteConnection(protocol, first, reconnectionToken);
  } on Object {
    protocol.dispose();
    await socket.close();
    rethrow;
  }
}
