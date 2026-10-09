/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// VS Code's IPC channels, as the server's management connection serves
// them: a context, then requests to named channels and their replies and
// events.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/base/parts/ipc/common/ipc.ts (`RequestType`, `ResponseType`,
// `DataType`, `serialize`, `deserialize`, the VQL integers, `ChannelClient`,
// `ChannelServer`, `IPCClient`).
//
// Deviations:
// - JavaScript's `undefined` is Dart's `null` (both serialize as
//   `DataType.Undefined`); a JSON `null` inside an object stays `null`.
// - Our `ChannelServer` serves no channels: requests to it are answered
//   with an error at once instead of waiting for a channel to appear.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// `RequestType`.
abstract final class IpcRequestType {
  static const promise = 100;
  static const promiseCancel = 101;
  static const eventListen = 102;
  static const eventDispose = 103;
}

/// `ResponseType`.
abstract final class IpcResponseType {
  static const initialize = 200;
  static const promiseSuccess = 201;
  static const promiseError = 202;
  static const promiseErrorObj = 203;
  static const eventFire = 204;
}

/// `DataType`.
abstract final class IpcDataType {
  static const undefined = 0;
  static const string = 1;
  static const buffer = 2;
  static const vsBuffer = 3;
  static const array = 4;
  static const object = 5;
  static const int = 6;
}

/// Bytes, as the IPC serializes a `VSBuffer` (and reads a Node `Buffer`).
final class IpcBuffer {
  const IpcBuffer(this.bytes);

  final Uint8List bytes;
}

void _writeVql(BytesBuilder out, int value) {
  // `writeInt32VQL` takes the value as an unsigned 32-bit integer.
  var v = value & 0xFFFFFFFF;
  if (v == 0) {
    out.addByte(0);
    return;
  }
  while (v != 0) {
    var b = v & 0x7F;
    v = v >> 7;
    if (v > 0) b |= 0x80;
    out.addByte(b);
  }
}

/// Reads a serialized message.
final class IpcReader {
  IpcReader(this._bytes);

  final Uint8List _bytes;
  int _pos = 0;

  int _readVql() {
    var value = 0;
    for (var n = 0; ; n += 7) {
      final next = _bytes[_pos++];
      value |= (next & 0x7F) << n;
      if (next & 0x80 == 0) return value.toSigned(32);
    }
  }

  Uint8List _read(int count) {
    final end = (_pos + count).clamp(0, _bytes.length);
    final result = Uint8List.sublistView(_bytes, _pos, end);
    _pos = end;
    return result;
  }

  bool get isAtEnd => _pos >= _bytes.length;

  /// `deserialize`.
  Object? read() {
    final type = _bytes[_pos++];
    switch (type) {
      case IpcDataType.undefined:
        return null;
      case IpcDataType.string:
        return utf8.decode(_read(_readVql()));
      case IpcDataType.buffer:
      case IpcDataType.vsBuffer:
        return IpcBuffer(Uint8List.fromList(_read(_readVql())));
      case IpcDataType.array:
        final length = _readVql();
        return [for (var i = 0; i < length; i++) read()];
      case IpcDataType.object:
        return jsonDecode(utf8.decode(_read(_readVql())));
      case IpcDataType.int:
        return _readVql();
      default:
        throw FormatException('Unknown IPC data type $type');
    }
  }
}

/// `serialize`, appending [data] to [out].
void ipcSerialize(BytesBuilder out, Object? data) {
  switch (data) {
    case null:
      out.addByte(IpcDataType.undefined);
    case String():
      final bytes = utf8.encode(data);
      out.addByte(IpcDataType.string);
      _writeVql(out, bytes.length);
      out.add(bytes);
    case IpcBuffer():
      out.addByte(IpcDataType.vsBuffer);
      _writeVql(out, data.bytes.length);
      out.add(data.bytes);
    case List():
      out.addByte(IpcDataType.array);
      _writeVql(out, data.length);
      for (final el in data) {
        ipcSerialize(out, el);
      }
    case int() when data >= -0x80000000 && data <= 0x7FFFFFFF:
      // JavaScript's `(data | 0) === data`: a 32-bit integer.
      out.addByte(IpcDataType.int);
      _writeVql(out, data);
    default:
      final bytes = utf8.encode(jsonEncode(data, toEncodable: _toEncodable));
      out.addByte(IpcDataType.object);
      _writeVql(out, bytes.length);
      out.add(bytes);
  }
}

Object? _toEncodable(Object? value) {
  try {
    return (value as dynamic).toJson();
  } on NoSuchMethodError {
    throw JsonUnsupportedObjectError(value);
  }
}

/// A message: [header] then [body].
Uint8List ipcMessage(Object? header, [Object? body]) {
  final out = BytesBuilder(copy: false);
  ipcSerialize(out, header);
  ipcSerialize(out, body);
  return out.takeBytes();
}

/// A message's header and body.
(Object?, Object?) ipcReadMessage(Uint8List bytes) {
  final reader = IpcReader(bytes);
  final header = reader.read();
  final body = reader.isAtEnd ? null : reader.read();
  return (header, body);
}

/// A failed channel call, as the server reported it.
final class IpcError implements Exception {
  IpcError(this.message, {this.name, this.stack, this.data});

  final String message;
  final String? name;
  final List<String>? stack;

  /// A `PromiseErrorObj`'s object.
  final Object? data;

  @override
  String toString() => name == null ? message : '$name: $message';
}

/// Sends and receives raw messages (`IMessagePassingProtocol`).
abstract interface class MessagePassingProtocol {
  void send(Uint8List message);

  /// Sets the one receiver of incoming messages.
  set onMessage(void Function(Uint8List message)? listener);
}

/// One named channel of an [IpcClient].
final class IpcChannel {
  IpcChannel(this._client, this.name);

  final IpcClient _client;
  final String name;

  /// `channel.call(command, arg)`.
  Future<Object?> call(String command, [Object? arg]) =>
      _client._requestPromise(name, command, arg);

  /// `channel.listen(event, arg)`: a broadcast stream that subscribes on
  /// first listen and unsubscribes on last cancel.
  Stream<Object?> listen(String event, [Object? arg]) =>
      _client._requestEvent(name, event, arg);
}

/// `IPCClient`: the client side of a management connection, with an empty
/// server side.
final class IpcClient {
  IpcClient(this._protocol, Object? ctx) {
    _protocol.onMessage = _onMessage;
    // `IPCClient`: the context alone (`serialize(writer, ctx)`, no body);
    // then `ChannelServer`'s initialize.
    final out = BytesBuilder(copy: false);
    ipcSerialize(out, ctx);
    _protocol.send(out.takeBytes());
    _protocol.send(ipcMessage([IpcResponseType.initialize]));
  }

  final MessagePassingProtocol _protocol;
  final _initialized = Completer<void>();
  final _handlers = <int, void Function(int type, Object? data)>{};
  int _lastRequestId = 0;
  bool _disposed = false;

  Future<void> get whenInitialized => _initialized.future;

  IpcChannel getChannel(String name) => IpcChannel(this, name);

  void _onMessage(Uint8List message) {
    final (header, body) = ipcReadMessage(message);
    if (header is! List || header.isEmpty) return;
    final type = header[0] as int;
    if (type >= 100 && type < 200) {
      _onServerRequest(type, header, body);
      return;
    }
    if (type == IpcResponseType.initialize) {
      if (!_initialized.isCompleted) _initialized.complete();
      return;
    }
    final id = header[1] as int;
    _handlers[id]?.call(type, body);
  }

  /// Requests the server makes of our (empty) side.
  void _onServerRequest(int type, List<Object?> header, Object? body) {
    if (type != IpcRequestType.promise) return;
    final id = header[1] as int;
    _protocol.send(
      ipcMessage(
        [IpcResponseType.promiseError, id],
        {
          'message': 'Unknown channel: ${header[2]}',
          'name': 'Unknown channel',
          'stack': null,
        },
      ),
    );
  }

  Future<Object?> _requestPromise(
    String channel,
    String name,
    Object? arg,
  ) async {
    if (_disposed) throw StateError('IPC client disposed');
    await whenInitialized;
    final id = _lastRequestId++;
    final completer = Completer<Object?>();
    _handlers[id] = (type, data) {
      _handlers.remove(id);
      switch (type) {
        case IpcResponseType.promiseSuccess:
          completer.complete(data);
        case IpcResponseType.promiseError:
          final err = (data as Map?)?.cast<String, Object?>() ?? const {};
          completer.completeError(
            IpcError(
              '${err['message'] ?? ''}',
              name: err['name'] as String?,
              stack: (err['stack'] as List?)?.cast<String>(),
            ),
          );
        default:
          completer.completeError(IpcError('$data', data: data));
      }
    };
    _protocol.send(ipcMessage([IpcRequestType.promise, id, channel, name], arg));
    return completer.future;
  }

  Stream<Object?> _requestEvent(String channel, String name, Object? arg) {
    late final StreamController<Object?> controller;
    int? id;
    controller = StreamController<Object?>.broadcast(
      onListen: () async {
        await whenInitialized;
        if (_disposed || !controller.hasListener) return;
        final myId = id = _lastRequestId++;
        _handlers[myId] = (type, data) {
          if (type == IpcResponseType.eventFire) controller.add(data);
        };
        _protocol.send(
          ipcMessage([IpcRequestType.eventListen, myId, channel, name], arg),
        );
      },
      onCancel: () {
        final myId = id;
        if (myId == null) return;
        id = null;
        _handlers.remove(myId);
        if (!_disposed) {
          _protocol.send(ipcMessage([IpcRequestType.eventDispose, myId]));
        }
      },
    );
    return controller.stream;
  }

  void dispose() {
    _disposed = true;
    for (final handler in _handlers.values.toList()) {
      handler(IpcResponseType.promiseErrorObj, 'disposed');
    }
    _handlers.clear();
    _protocol.onMessage = null;
  }
}
