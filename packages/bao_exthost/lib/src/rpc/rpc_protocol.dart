/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The extension host's RPC: requests to numbered actors on either side,
// their acknowledgements, replies, errors and cancellation.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/extensions/common/rpcProtocol.ts (`MessageType`,
// `ArgType`, `MessageBuffer`, `MessageIO`, `RPCProtocol`,
// `stringifyJsonWithBufferRefs`, `parseJsonAndRestoreBufferRefs`).
//
// Deviations:
// - No URI transformer: the main thread never has one (only a remote
//   extension host does, and ours gets no authority).
// - Dart `null` replies as `undefined` (`ReplyOKEmpty`); [rpcNull] replies a
//   JSON `null`. [rpcUndefined] passes `undefined` as an argument.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../base/cancellation.dart';
import '../ipc/ipc.dart' show MessagePassingProtocol;

/// `MessageType`.
abstract final class RpcMessageType {
  static const requestJsonArgs = 1;
  static const requestJsonArgsWithCancellation = 2;
  static const requestMixedArgs = 3;
  static const requestMixedArgsWithCancellation = 4;
  static const acknowledged = 5;
  static const cancel = 6;
  static const replyOkEmpty = 7;
  static const replyOkVSBuffer = 8;
  static const replyOkJson = 9;
  static const replyOkJsonWithBuffers = 10;
  static const replyErrError = 11;
  static const replyErrEmpty = 12;
}

/// `ArgType`.
abstract final class RpcArgType {
  static const string = 1;
  static const vsBuffer = 2;
  static const serializedObjectWithBuffers = 3;
  static const undefined = 4;
}

/// JavaScript's `undefined`, as an argument.
final class RpcUndefined {
  const RpcUndefined._();
}

const rpcUndefined = RpcUndefined._();

/// JavaScript's `null`, as a reply.
final class RpcNull {
  const RpcNull._();
}

const rpcNull = RpcNull._();

/// A `VSBuffer`.
final class RpcBuffer {
  const RpcBuffer(this.bytes);

  final Uint8List bytes;

  Map<String, Object?> toJson() =>
      throw StateError('An RpcBuffer must be sent as an argument or reply');
}

/// `SerializableObjectWithBuffers`: a JSON value with [RpcBuffer]s inside.
final class RpcObjectWithBuffers {
  const RpcObjectWithBuffers(this.value);

  final Object? value;
}

/// An error the other side replied with (`$isError` objects), or another
/// value it rejected with.
final class RpcRemoteError implements Exception {
  RpcRemoteError({required this.name, required this.message, this.stack, this.value});

  final String name;
  final String message;
  final String? stack;

  /// What was rejected, when it was not an error.
  final Object? value;

  @override
  String toString() => '$name: $message';
}

/// A request to an actor that has no such method, or no actor.
final class RpcUnsupported implements Exception {
  const RpcUnsupported(this.what);

  final String what;

  @override
  String toString() => 'Unsupported: $what';
}

/// Handles requests to one numbered actor on our side.
abstract interface class RpcActor {
  /// Runs [method] with [args] (JSON values, [RpcBuffer]s, `null` for
  /// `undefined`); a request that can be cancelled has a [CancellationToken]
  /// last, as upstream appends one.
  FutureOr<Object?> invoke(String method, List<Object?> args);
}

/// Logs traffic (`IRPCProtocolLogger`).
typedef RpcLogger =
    void Function(bool incoming, int req, String what, Object? data);

enum ResponsiveState { responsive, unresponsive }

const _refSymbol = r'$$ref$$';

/// `RPCProtocol`.
final class RpcProtocol {
  RpcProtocol(this._protocol, {required this.actorNames, this.logger}) {
    _protocol.onMessage = _receiveOneMessage;
  }

  final MessagePassingProtocol _protocol;

  /// The proxy identifiers' names, by number (for messages and logs).
  final Map<int, String> actorNames;
  final RpcLogger? logger;

  final _locals = <int, RpcActor>{};
  final _pending = <int, Completer<Object?>>{};
  final _cancelInvoked = <int, CancellationTokenSource>{};
  int _lastMessageId = 0;
  bool _disposed = false;

  static const unresponsiveTime = Duration(seconds: 3);
  int _unacknowledgedCount = 0;
  DateTime _unresponsiveAt = DateTime.now();
  Timer? _checkTimer;
  ResponsiveState _responsiveState = ResponsiveState.responsive;
  final _responsive = StreamController<ResponsiveState>.broadcast();

  Stream<ResponsiveState> get onDidChangeResponsiveState => _responsive.stream;
  ResponsiveState get responsiveState => _responsiveState;

  /// Registers our actor [rpcId] (`set`).
  void set(int rpcId, RpcActor actor) => _locals[rpcId] = actor;

  /// Calls [method] on the other side's actor [rpcId] (`_remoteCall`).
  Future<Object?> call(
    int rpcId,
    String method,
    List<Object?> args, {
    CancellationToken? token,
  }) {
    if (_disposed) return Future.error(const CancellationException());
    if (token != null && token.isCancellationRequested) {
      return Future.error(const CancellationException());
    }
    final req = ++_lastMessageId;
    final completer = Completer<Object?>();
    _pending[req] = completer;
    if (token != null) {
      token.whenCancelled.then((_) {
        if (_pending.containsKey(req) && !_disposed) {
          _send(_header(RpcMessageType.cancel, req, 0).takeBytes());
        }
      });
    }
    _onWillSendRequest();
    logger?.call(false, req, 'request: ${actorNames[rpcId]}.$method', args);
    _send(_serializeRequest(req, rpcId, method, args, token != null));
    return completer.future;
  }

  void _send(Uint8List message) {
    if (!_disposed) _protocol.send(message);
  }

  void _onWillSendRequest() {
    if (_unacknowledgedCount == 0) {
      _unresponsiveAt = DateTime.now().add(unresponsiveTime);
    }
    _unacknowledgedCount++;
    _checkTimer ??= Timer(const Duration(seconds: 1), _checkUnresponsive);
  }

  void _onDidReceiveAcknowledge() {
    _unresponsiveAt = DateTime.now().add(unresponsiveTime);
    _unacknowledgedCount--;
    if (_unacknowledgedCount <= 0) {
      _unacknowledgedCount = 0;
      _checkTimer?.cancel();
      _checkTimer = null;
    }
    _setResponsiveState(ResponsiveState.responsive);
  }

  void _checkUnresponsive() {
    _checkTimer = null;
    if (_unacknowledgedCount == 0 || _disposed) return;
    if (DateTime.now().isAfter(_unresponsiveAt)) {
      _setResponsiveState(ResponsiveState.unresponsive);
    }
    _checkTimer = Timer(const Duration(seconds: 1), _checkUnresponsive);
  }

  void _setResponsiveState(ResponsiveState state) {
    if (_responsiveState == state) return;
    _responsiveState = state;
    _responsive.add(state);
  }

  void _receiveOneMessage(Uint8List raw) {
    if (_disposed) return;
    final r = _Reader(raw);
    final type = r.u8();
    final req = r.u32();
    switch (type) {
      case RpcMessageType.requestJsonArgs:
      case RpcMessageType.requestJsonArgsWithCancellation:
        final rpcId = r.u8();
        final method = r.shortString();
        final args = (jsonDecode(r.longString()) as List).toList();
        _receiveRequest(
          req,
          rpcId,
          method,
          args,
          type == RpcMessageType.requestJsonArgsWithCancellation,
        );
      case RpcMessageType.requestMixedArgs:
      case RpcMessageType.requestMixedArgsWithCancellation:
        final rpcId = r.u8();
        final method = r.shortString();
        final args = r.mixedArray();
        _receiveRequest(
          req,
          rpcId,
          method,
          args,
          type == RpcMessageType.requestMixedArgsWithCancellation,
        );
      case RpcMessageType.acknowledged:
        logger?.call(true, req, 'ack', null);
        _onDidReceiveAcknowledge();
      case RpcMessageType.cancel:
        _cancelInvoked.remove(req)?.cancel();
      case RpcMessageType.replyOkEmpty:
        _receiveReply(req, null);
      case RpcMessageType.replyOkJson:
        _receiveReply(req, jsonDecode(r.longString()));
      case RpcMessageType.replyOkJsonWithBuffers:
        final count = r.u32();
        final json = r.longString();
        final buffers = [for (var i = 0; i < count; i++) r.vsBuffer()];
        _receiveReply(req, _restoreBufferRefs(json, buffers));
      case RpcMessageType.replyOkVSBuffer:
        _receiveReply(req, RpcBuffer(r.vsBuffer()));
      case RpcMessageType.replyErrError:
        _receiveReplyErr(req, jsonDecode(r.longString()));
      case RpcMessageType.replyErrEmpty:
        _receiveReplyErr(req, null);
    }
  }

  void _receiveRequest(
    int req,
    int rpcId,
    String method,
    List<Object?> args,
    bool usesCancellation,
  ) {
    logger?.call(true, req, 'receiveRequest ${actorNames[rpcId]}.$method', args);
    if (usesCancellation) {
      final source = CancellationTokenSource();
      _cancelInvoked[req] = source;
      args.add(source.token);
    }
    // Acknowledge the request.
    _send(_header(RpcMessageType.acknowledged, req, 0).takeBytes());
    Future<Object?> result;
    try {
      final actor = _locals[rpcId];
      if (actor == null) {
        throw RpcUnsupported('Unknown actor ${actorNames[rpcId] ?? rpcId}');
      }
      result = Future.sync(() => actor.invoke(method, args));
    } on Object catch (e, st) {
      result = Future.error(e, st);
    }
    result.then(
      (value) {
        _cancelInvoked.remove(req);
        logger?.call(false, req, 'reply:', value);
        _send(_serializeReplyOk(req, value));
      },
      onError: (Object error, StackTrace stack) {
        _cancelInvoked.remove(req);
        logger?.call(false, req, 'replyErr:', error);
        _send(_serializeReplyErr(req, error, stack));
      },
    );
  }

  void _receiveReply(int req, Object? value) {
    logger?.call(true, req, 'receiveReply:', value);
    _pending.remove(req)?.complete(value);
  }

  void _receiveReplyErr(int req, Object? value) {
    logger?.call(true, req, 'receiveReplyErr:', value);
    final completer = _pending.remove(req);
    if (completer == null) return;
    if (value is Map && value[r'$isError'] == true) {
      final name = '${value['name'] ?? 'Error'}';
      if (name == 'Canceled') {
        completer.completeError(const CancellationException());
        return;
      }
      completer.completeError(
        RpcRemoteError(
          name: name,
          message: '${value['message'] ?? ''}',
          stack: value['stack'] as String?,
        ),
      );
    } else {
      completer.completeError(
        RpcRemoteError(name: 'Error', message: '$value', value: value),
      );
    }
  }

  /// Rejects what is pending; ignores what arrives later.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _checkTimer?.cancel();
    for (final completer in _pending.values) {
      completer.completeError(const CancellationException());
    }
    _pending.clear();
    for (final source in _cancelInvoked.values) {
      source.cancel();
    }
    _cancelInvoked.clear();
    _protocol.onMessage = null;
    _responsive.close();
  }
}

// --- Serialization ----------------------------------------------------------

BytesBuilder _header(int type, int req, int _) {
  final b = BytesBuilder(copy: false);
  b.addByte(type);
  b.add(_u32(req));
  return b;
}

Uint8List _u32(int n) => (ByteData(4)..setUint32(0, n)).buffer.asUint8List();

void _shortString(BytesBuilder b, Uint8List s) {
  b.addByte(s.length);
  b.add(s);
}

void _longString(BytesBuilder b, Uint8List s) {
  b.add(_u32(s.length));
  b.add(s);
}

Object? _encodable(Object? value) {
  if (value is RpcUndefined) return null;
  if (value is RpcNull) return null;
  try {
    return (value as dynamic).toJson();
  } on NoSuchMethodError {
    throw JsonUnsupportedObjectError(value);
  }
}

/// `JSON.stringify` of a value with no buffers.
String rpcStringify(Object? value) => jsonEncode(value, toEncodable: _encodable);

/// `stringifyJsonWithBufferRefs`.
(String, List<Uint8List>) _stringifyWithBufferRefs(Object? value) {
  final buffers = <Uint8List>[];
  Object? walk(Object? v) {
    if (v is RpcBuffer) {
      buffers.add(v.bytes);
      return {_refSymbol: buffers.length - 1};
    }
    if (v is RpcUndefined) return {_refSymbol: -1};
    if (v is Map) return v.map((k, e) => MapEntry('$k', walk(e)));
    if (v is List) return [for (final e in v) walk(e)];
    if (v == null || v is String || v is num || v is bool) return v;
    if (v is RpcNull) return null;
    return walk((v as dynamic).toJson());
  }

  return (jsonEncode(walk(value)), buffers);
}

/// `parseJsonAndRestoreBufferRefs`.
Object? _restoreBufferRefs(String json, List<Uint8List> buffers) {
  Object? walk(Object? v) {
    if (v is Map) {
      final ref = v[_refSymbol];
      if (ref is int && v.length == 1) {
        return ref >= 0 && ref < buffers.length ? RpcBuffer(buffers[ref]) : null;
      }
      return v.map((k, e) => MapEntry(k as String, walk(e)));
    }
    if (v is List) return [for (final e in v) walk(e)];
    return v;
  }

  return walk(jsonDecode(json));
}

bool _useMixed(List<Object?> args) => args.any(
  (a) => a is RpcBuffer || a is RpcObjectWithBuffers || a is RpcUndefined,
);

Uint8List _serializeRequest(
  int req,
  int rpcId,
  String method,
  List<Object?> args,
  bool usesCancellation,
) {
  final methodBuff = utf8.encode(method);
  if (!_useMixed(args)) {
    final b = _header(
      usesCancellation
          ? RpcMessageType.requestJsonArgsWithCancellation
          : RpcMessageType.requestJsonArgs,
      req,
      0,
    );
    b.addByte(rpcId);
    _shortString(b, methodBuff);
    _longString(b, utf8.encode(rpcStringify(args)));
    return b.takeBytes();
  }
  final b = _header(
    usesCancellation
        ? RpcMessageType.requestMixedArgsWithCancellation
        : RpcMessageType.requestMixedArgs,
    req,
    0,
  );
  b.addByte(rpcId);
  _shortString(b, methodBuff);
  b.addByte(args.length);
  for (final arg in args) {
    switch (arg) {
      case RpcBuffer():
        b.addByte(RpcArgType.vsBuffer);
        _longString(b, arg.bytes);
      case RpcUndefined():
        b.addByte(RpcArgType.undefined);
      case RpcObjectWithBuffers():
        final (json, buffers) = _stringifyWithBufferRefs(arg.value);
        b.addByte(RpcArgType.serializedObjectWithBuffers);
        b.add(_u32(buffers.length));
        _longString(b, utf8.encode(json));
        for (final buffer in buffers) {
          _longString(b, buffer);
        }
      default:
        b.addByte(RpcArgType.string);
        _longString(b, utf8.encode(rpcStringify(arg)));
    }
  }
  return b.takeBytes();
}

Uint8List _serializeReplyOk(int req, Object? value) {
  if (value == null || value is RpcUndefined) {
    return _header(RpcMessageType.replyOkEmpty, req, 0).takeBytes();
  }
  if (value is RpcBuffer) {
    final b = _header(RpcMessageType.replyOkVSBuffer, req, 0);
    _longString(b, value.bytes);
    return b.takeBytes();
  }
  if (value is RpcObjectWithBuffers) {
    final (json, buffers) = _stringifyWithBufferRefs(value.value);
    final b = _header(RpcMessageType.replyOkJsonWithBuffers, req, 0);
    b.add(_u32(buffers.length));
    _longString(b, utf8.encode(json));
    for (final buffer in buffers) {
      _longString(b, buffer);
    }
    return b.takeBytes();
  }
  String json;
  try {
    json = rpcStringify(value);
  } on Object {
    json = 'null';
  }
  final b = _header(RpcMessageType.replyOkJson, req, 0);
  _longString(b, utf8.encode(json));
  return b.takeBytes();
}

/// `serializeReplyErr` with `transformErrorForSerialization`'s shape.
Uint8List _serializeReplyErr(int req, Object error, StackTrace stack) {
  final Map<String, Object?> err;
  if (error is CancellationException) {
    err = {r'$isError': true, 'name': 'Canceled', 'message': 'Canceled', 'stack': null};
  } else if (error is RpcRemoteError) {
    err = {r'$isError': true, 'name': error.name, 'message': error.message, 'stack': error.stack};
  } else {
    err = {
      r'$isError': true,
      'name': error is RpcUnsupported ? 'Unsupported' : 'Error',
      'message': '$error',
      'stack': '$stack',
    };
  }
  final b = _header(RpcMessageType.replyErrError, req, 0);
  _longString(b, utf8.encode(jsonEncode(err)));
  return b.takeBytes();
}

final class _Reader {
  _Reader(this._buff) : _view = ByteData.sublistView(_buff);

  final Uint8List _buff;
  final ByteData _view;
  int _offset = 0;

  int u8() => _view.getUint8(_offset++);

  int u32() {
    final n = _view.getUint32(_offset);
    _offset += 4;
    return n;
  }

  String shortString() {
    final len = u8();
    final s = utf8.decode(Uint8List.sublistView(_buff, _offset, _offset + len));
    _offset += len;
    return s;
  }

  String longString() {
    final len = u32();
    final s = utf8.decode(Uint8List.sublistView(_buff, _offset, _offset + len));
    _offset += len;
    return s;
  }

  Uint8List vsBuffer() {
    final len = u32();
    final b = Uint8List.fromList(
      Uint8List.sublistView(_buff, _offset, _offset + len),
    );
    _offset += len;
    return b;
  }

  List<Object?> mixedArray() {
    final len = u8();
    final out = <Object?>[];
    for (var i = 0; i < len; i++) {
      switch (u8()) {
        case RpcArgType.string:
          out.add(jsonDecode(longString()));
        case RpcArgType.vsBuffer:
          out.add(RpcBuffer(vsBuffer()));
        case RpcArgType.serializedObjectWithBuffers:
          final count = u32();
          final json = longString();
          final buffers = [for (var j = 0; j < count; j++) vsBuffer()];
          out.add(_restoreBufferRefs(json, buffers));
        case RpcArgType.undefined:
          out.add(null);
      }
    }
    return out;
  }
}
