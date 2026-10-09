/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The framing every connection to a VS Code server speaks: 13-byte headers,
// acknowledged regular messages, control messages and keep-alives.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/base/parts/ipc/common/ipc.net.ts (`ProtocolMessageType`,
// `ProtocolConstants`, `ProtocolReader`, `ProtocolWriter`,
// `PersistentProtocol`).
//
// Deviations:
// - No reconnection (`beginAcceptReconnection`): a lost connection to the
//   local server restarts the extension host instead.
// - No load estimator: a timeout fires after `timeoutTime` regardless.

import 'dart:async';
import 'dart:typed_data';

import 'socket.dart';

/// `ProtocolMessageType`.
abstract final class ProtocolMessageType {
  static const none = 0;
  static const regular = 1;
  static const control = 2;
  static const ack = 3;
  static const disconnect = 5;
  static const replayRequest = 6;
  static const pause = 7;
  static const resume = 8;
  static const keepAlive = 9;
}

/// `ProtocolConstants`.
abstract final class ProtocolConstants {
  static const headerLength = 13;
  static const acknowledgeTime = Duration(seconds: 2);
  static const timeoutTime = Duration(seconds: 20);
  static const keepAliveSendTime = Duration(seconds: 5);
}

final class ProtocolMessage {
  ProtocolMessage(this.type, this.id, this.ack, this.data);

  final int type;
  final int id;
  final int ack;
  final Uint8List data;
  DateTime writtenTime = DateTime.fromMillisecondsSinceEpoch(0);
}

/// Splits incoming bytes into [ProtocolMessage]s.
final class ProtocolReader {
  ProtocolReader(this.onMessage);

  final void Function(ProtocolMessage message) onMessage;
  final _incoming = ChunkStream();
  bool _readHead = true;
  int _readLen = ProtocolConstants.headerLength;
  int _type = ProtocolMessageType.none;
  int _id = 0;
  int _ack = 0;
  DateTime lastReadTime = DateTime.now();
  bool disposed = false;

  void accept(Uint8List data) {
    if (data.isEmpty) return;
    lastReadTime = DateTime.now();
    _incoming.accept(data);
    while (_incoming.byteLength >= _readLen) {
      final buff = _incoming.read(_readLen);
      if (_readHead) {
        final view = ByteData.sublistView(buff);
        _readHead = false;
        _readLen = view.getUint32(9);
        _type = view.getUint8(0);
        _id = view.getUint32(1);
        _ack = view.getUint32(5);
        if (_readLen == 0) {
          // An empty body is complete as soon as its header is.
          _emit(Uint8List(0));
        }
      } else {
        _emit(buff);
      }
      if (disposed) break;
    }
  }

  void _emit(Uint8List body) {
    final message = ProtocolMessage(_type, _id, _ack, body);
    _readHead = true;
    _readLen = ProtocolConstants.headerLength;
    _type = ProtocolMessageType.none;
    _id = 0;
    _ack = 0;
    onMessage(message);
  }

  /// What arrived but has not been read as messages.
  Uint8List readEntireBuffer() => _incoming.readAll();
}

/// Writes [ProtocolMessage]s, batching those written in one turn.
final class ProtocolWriter {
  ProtocolWriter(this._socket);

  final ExtHostSocket _socket;
  final _data = BytesBuilder(copy: false);
  bool _scheduled = false;
  bool _paused = false;
  bool _disposed = false;
  DateTime lastWriteTime = DateTime.fromMillisecondsSinceEpoch(0);

  void write(ProtocolMessage msg) {
    if (_disposed) return;
    msg.writtenTime = DateTime.now();
    lastWriteTime = msg.writtenTime;
    final header = ByteData(ProtocolConstants.headerLength)
      ..setUint8(0, msg.type)
      ..setUint32(1, msg.id)
      ..setUint32(5, msg.ack)
      ..setUint32(9, msg.data.length);
    _data
      ..add(header.buffer.asUint8List())
      ..add(msg.data);
    if (!_scheduled) {
      _scheduled = true;
      scheduleMicrotask(() {
        _scheduled = false;
        flush();
      });
    }
  }

  void flush() {
    if (_paused || _data.isEmpty || _disposed) return;
    _socket.write(_data.takeBytes());
  }

  void pause() => _paused = true;

  void resume() {
    _paused = false;
    flush();
  }

  Future<void> drain() {
    flush();
    return _socket.drain();
  }

  void dispose() {
    try {
      flush();
    } on Object {
      // The socket may be closed already.
    }
    _disposed = true;
  }
}

/// Why a connection was judged dead (`SocketTimeoutEvent`).
final class SocketTimeout {
  const SocketTimeout(this.reason, this.unacknowledgedCount);

  /// `unacknowledgedMessage` or `keepAlive`.
  final String reason;
  final int unacknowledgedCount;
}

/// Buffers events until someone listens (`BufferedEmitter`).
final class BufferedEvents<T> {
  final _buffer = <T>[];
  void Function(T event)? _listener;

  void fire(T event) {
    final listener = _listener;
    if (listener == null || _buffer.isNotEmpty) {
      _buffer.add(event);
      if (listener != null) _deliver();
    } else {
      listener(event);
    }
  }

  /// Sets the one listener, delivering what was buffered; null removes it.
  set listener(void Function(T event)? listener) {
    _listener = listener;
    if (listener != null && _buffer.isNotEmpty) scheduleMicrotask(_deliver);
  }

  void _deliver() {
    while (_listener != null && _buffer.isNotEmpty) {
      _listener!(_buffer.removeAt(0));
    }
  }

  void clear() => _buffer.clear();
}

/// `PersistentProtocol` without reconnection.
final class PersistentProtocol {
  PersistentProtocol(
    this._socket, {
    Uint8List? initialChunk,
    bool sendKeepAlive = true,
  }) {
    _writer = ProtocolWriter(_socket);
    _reader = ProtocolReader(_receiveMessage);
    _subscription = _socket.data.listen(
      _reader.accept,
      onDone: _socketClosed,
      onError: (Object _) => _socketClosed(),
      cancelOnError: true,
    );
    if (initialChunk != null && initialChunk.isNotEmpty) {
      _reader.accept(initialChunk);
    }
    if (sendKeepAlive) {
      _keepAlive = Timer.periodic(
        ProtocolConstants.keepAliveSendTime,
        (_) => _sendKeepAlive(),
      );
    }
  }

  final ExtHostSocket _socket;
  late final ProtocolWriter _writer;
  late final ProtocolReader _reader;
  late final StreamSubscription<Uint8List> _subscription;
  Timer? _keepAlive;
  Timer? _incomingAckTimer;
  Timer? _outgoingAckTimer;

  final _unacked = <ProtocolMessage>[];
  int _outgoingMsgId = 0;
  int _outgoingAckId = 0;
  int _incomingMsgId = 0;
  int _incomingAckId = 0;
  DateTime _incomingMsgLastTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastReplayRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSocketTimeoutTime = DateTime.now();
  bool _didSendDisconnect = false;
  bool _disposed = false;

  /// Regular messages, in order.
  final onMessage = BufferedEvents<Uint8List>();

  /// Control messages (the handshake's).
  final onControlMessage = BufferedEvents<Uint8List>();

  /// The other side said goodbye, or the socket closed.
  final onDidDispose = BufferedEvents<void>();

  /// The socket closed.
  final onSocketClose = BufferedEvents<void>();

  final onSocketTimeout = BufferedEvents<SocketTimeout>();

  ExtHostSocket get socket => _socket;

  int get unacknowledgedCount => _outgoingMsgId - _outgoingAckId;

  void send(Uint8List buffer) {
    final id = ++_outgoingMsgId;
    _incomingAckId = _incomingMsgId;
    final msg = ProtocolMessage(
      ProtocolMessageType.regular,
      id,
      _incomingAckId,
      buffer,
    );
    _unacked.add(msg);
    _writer.write(msg);
    _recvAckCheck();
  }

  void sendControl(Uint8List buffer) {
    _writer.write(ProtocolMessage(ProtocolMessageType.control, 0, 0, buffer));
  }

  void sendDisconnect() {
    if (_didSendDisconnect) return;
    _didSendDisconnect = true;
    _writer
      ..write(
        ProtocolMessage(ProtocolMessageType.disconnect, 0, 0, Uint8List(0)),
      )
      ..flush();
  }

  void sendPause() => _writer.write(
    ProtocolMessage(ProtocolMessageType.pause, 0, 0, Uint8List(0)),
  );

  void sendResume() => _writer.write(
    ProtocolMessage(ProtocolMessageType.resume, 0, 0, Uint8List(0)),
  );

  void flush() => _writer.flush();

  Future<void> drain() => _writer.drain();

  /// What arrived but was not read yet, for handing the socket over.
  Uint8List readEntireBuffer() => _reader.readEntireBuffer();

  void _receiveMessage(ProtocolMessage msg) {
    if (msg.ack > _outgoingAckId) {
      _outgoingAckId = msg.ack;
      while (_unacked.isNotEmpty && _unacked.first.id <= msg.ack) {
        _unacked.removeAt(0);
      }
    }
    switch (msg.type) {
      case ProtocolMessageType.regular:
        if (msg.id > _incomingMsgId) {
          if (msg.id != _incomingMsgId + 1) {
            final now = DateTime.now();
            if (now.difference(_lastReplayRequestTime).inMilliseconds >
                10000) {
              _lastReplayRequestTime = now;
              _writer.write(
                ProtocolMessage(
                  ProtocolMessageType.replayRequest,
                  0,
                  0,
                  Uint8List(0),
                ),
              );
            }
          } else {
            _incomingMsgId = msg.id;
            _incomingMsgLastTime = DateTime.now();
            _sendAckCheck();
            onMessage.fire(msg.data);
          }
        }
      case ProtocolMessageType.control:
        onControlMessage.fire(msg.data);
      case ProtocolMessageType.disconnect:
        onDidDispose.fire(null);
      case ProtocolMessageType.replayRequest:
        for (final m in _unacked) {
          _writer.write(m);
        }
        _recvAckCheck();
      case ProtocolMessageType.pause:
        _writer.pause();
      case ProtocolMessageType.resume:
        _writer.resume();
      default:
      // none, ack, keepAlive: nothing more to do.
    }
  }

  void _sendAckCheck() {
    if (_incomingMsgId <= _incomingAckId || _incomingAckTimer != null) return;
    final since = DateTime.now().difference(_incomingMsgLastTime);
    if (since >= ProtocolConstants.acknowledgeTime) {
      _sendAck();
      return;
    }
    _incomingAckTimer = Timer(
      ProtocolConstants.acknowledgeTime - since + const Duration(milliseconds: 5),
      () {
        _incomingAckTimer = null;
        _sendAckCheck();
      },
    );
  }

  void _sendAck() {
    if (_incomingMsgId <= _incomingAckId) return;
    _incomingAckId = _incomingMsgId;
    _writer.write(
      ProtocolMessage(ProtocolMessageType.ack, 0, _incomingAckId, Uint8List(0)),
    );
  }

  void _recvAckCheck() {
    if (_outgoingMsgId <= _outgoingAckId || _outgoingAckTimer != null) return;
    if (_unacked.isEmpty) return;
    final now = DateTime.now();
    final sinceOldest = now.difference(_unacked.first.writtenTime);
    final sinceData = now.difference(_reader.lastReadTime);
    final sinceTimeout = now.difference(_lastSocketTimeoutTime);
    const timeout = ProtocolConstants.timeoutTime;
    if (sinceOldest >= timeout && sinceData >= timeout && sinceTimeout >= timeout) {
      _lastSocketTimeoutTime = now;
      onSocketTimeout.fire(
        SocketTimeout('unacknowledgedMessage', _unacked.length),
      );
      return;
    }
    final wait = [
      timeout - sinceOldest,
      timeout - sinceData,
      timeout - sinceTimeout,
      const Duration(milliseconds: 500),
    ].reduce((a, b) => a > b ? a : b);
    _outgoingAckTimer = Timer(wait, () {
      _outgoingAckTimer = null;
      _recvAckCheck();
    });
  }

  void _sendKeepAlive() {
    _incomingAckId = _incomingMsgId;
    _writer.write(
      ProtocolMessage(
        ProtocolMessageType.keepAlive,
        0,
        _incomingAckId,
        Uint8List(0),
      ),
    );
    final now = DateTime.now();
    if (now.difference(_reader.lastReadTime) >= ProtocolConstants.timeoutTime &&
        now.difference(_lastSocketTimeoutTime) >=
            ProtocolConstants.timeoutTime) {
      _lastSocketTimeoutTime = now;
      onSocketTimeout.fire(SocketTimeout('keepAlive', _unacked.length));
    }
  }

  void _socketClosed() {
    if (_disposed) return;
    onSocketClose.fire(null);
    onDidDispose.fire(null);
  }

  /// Stops timers and reading; the socket stays open (see [close]).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _keepAlive?.cancel();
    _incomingAckTimer?.cancel();
    _outgoingAckTimer?.cancel();
    _reader.disposed = true;
    _writer.dispose();
    unawaited(_subscription.cancel());
  }

  /// Says goodbye, then disposes and closes the socket.
  Future<void> close() async {
    sendDisconnect();
    await drain().catchError((Object _) {});
    dispose();
    await _socket.close();
  }
}
