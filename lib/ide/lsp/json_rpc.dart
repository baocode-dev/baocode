/// JSON-RPC 2.0 over the Language Server Protocol's base protocol: messages
/// framed by `Content-Length` headers, UTF-8 JSON bodies, over any pair of
/// byte streams (a server process's stdout and stdin).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// An error answer to a request, or what a handler throws to send one.
class JsonRpcError implements Exception {
  const JsonRpcError(this.code, this.message, {this.data});

  static const parseError = -32700;
  static const invalidRequest = -32600;
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
  static const internalError = -32603;

  /// LSP: the server is not initialized yet.
  static const serverNotInitialized = -32002;

  /// LSP: the request was cancelled.
  static const requestCancelled = -32800;

  /// LSP: the document changed under the request.
  static const contentModified = -32801;

  final int code;
  final String message;
  final Object? data;

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'data': ?data,
  };

  @override
  String toString() => 'JsonRpcError($code): $message';
}

/// The connection ended before the request was answered.
class JsonRpcClosed implements Exception {
  const JsonRpcClosed(this.method);

  final String method;

  @override
  String toString() => 'JsonRpcClosed: $method was not answered';
}

/// The caller cancelled the request (see [JsonRpcCancelToken]).
class JsonRpcCancelled implements Exception {
  const JsonRpcCancelled(this.method);

  final String method;

  @override
  String toString() => 'JsonRpcCancelled: $method';
}

/// Cancels the requests it was passed to: they complete with
/// [JsonRpcCancelled] and the other side gets `$/cancelRequest`.
class JsonRpcCancelToken {
  final _listeners = <void Function()>[];
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in [..._listeners]) {
      listener();
    }
    _listeners.clear();
  }

  void _listen(void Function() listener) => _listeners.add(listener);
  void _forget(void Function() listener) => _listeners.remove(listener);
}

typedef JsonRpcRequestHandler = FutureOr<Object?> Function(Object? params);
typedef JsonRpcNotificationHandler = void Function(Object? params);

class _Pending {
  _Pending(this.method);

  final String method;
  final completer = Completer<Object?>();
  Timer? timer;
  void Function()? onCancel;
  JsonRpcCancelToken? token;

  void finish() {
    timer?.cancel();
    if (onCancel case final listener?) token?._forget(listener);
  }
}

/// One JSON-RPC peer. Requests are matched to responses by id; requests
/// and notifications from the other side go to registered handlers, and
/// an unknown request is answered with [JsonRpcError.methodNotFound].
class JsonRpcConnection {
  JsonRpcConnection(
    Stream<List<int>> input,
    void Function(List<int> bytes) output, {
    this.onUnhandledNotification,
    this.onProtocolError,
  }) : _output = output {
    _subscription = input.listen(
      _receive,
      onError: (Object error) => onProtocolError?.call('$error'),
      onDone: _closed,
      cancelOnError: false,
    );
  }

  final void Function(List<int> bytes) _output;

  /// Notifications no handler is registered for (`$/…` included).
  void Function(String method, Object? params)? onUnhandledNotification;

  /// Malformed input, which is skipped.
  void Function(String message)? onProtocolError;

  late final StreamSubscription<List<int>> _subscription;
  final _requestHandlers = <String, JsonRpcRequestHandler>{};
  final _notificationHandlers = <String, JsonRpcNotificationHandler>{};
  final _pending = <Object, _Pending>{};

  /// Requests from the other side still being handled, by id; true once
  /// the other side cancelled one.
  final _incoming = <Object, bool>{};
  final _done = Completer<void>();
  int _nextId = 0;
  bool _isClosed = false;

  // Input buffer: bytes [_start, _end) are unread.
  Uint8List _buffer = Uint8List(4096);
  int _start = 0;
  int _end = 0;

  /// The length of the body starting at [_start], once its header is read.
  int? _bodyLength;

  /// Completes when the input ends or [close] is called.
  Future<void> get done => _done.future;
  bool get isClosed => _isClosed;

  void onRequest(String method, JsonRpcRequestHandler handler) =>
      _requestHandlers[method] = handler;

  void onNotification(String method, JsonRpcNotificationHandler handler) =>
      _notificationHandlers[method] = handler;

  /// Sends a request and completes with its result. Fails with
  /// [JsonRpcError] for an error answer, [TimeoutException] after
  /// [timeout], [JsonRpcCancelled] when [cancel] fires, and [JsonRpcClosed]
  /// when the connection ends first; the latter three send
  /// `$/cancelRequest` when the connection is still open.
  Future<Object?> request(
    String method, [
    Object? params,
    Duration? timeout,
    JsonRpcCancelToken? cancel,
  ]) {
    if (_isClosed) return Future.error(JsonRpcClosed(method));
    if (cancel?.isCancelled ?? false) {
      return Future.error(JsonRpcCancelled(method));
    }
    final id = _nextId++;
    final pending = _Pending(method);
    _pending[id] = pending;
    void abandon(Object error) {
      if (_pending.remove(id) == null) return;
      pending.finish();
      _send({
        'jsonrpc': '2.0',
        'method': r'$/cancelRequest',
        'params': {'id': id},
      });
      pending.completer.completeError(error);
    }

    if (timeout != null) {
      pending.timer = Timer(
        timeout,
        () => abandon(TimeoutException('$method timed out', timeout)),
      );
    }
    if (cancel != null) {
      pending
        ..token = cancel
        ..onCancel = () => abandon(JsonRpcCancelled(method));
      cancel._listen(pending.onCancel!);
    }
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params});
    return pending.completer.future;
  }

  void notify(String method, [Object? params]) =>
      _send({'jsonrpc': '2.0', 'method': method, 'params': ?params});

  /// Stops reading and fails what is pending with [JsonRpcClosed].
  void close() {
    unawaited(_subscription.cancel());
    _closed();
  }

  void _send(Map<String, Object?> message) {
    if (_isClosed) return;
    final body = utf8.encode(jsonEncode(message));
    final header = ascii.encode('Content-Length: ${body.length}\r\n\r\n');
    try {
      _output(
        Uint8List(header.length + body.length)
          ..setRange(0, header.length, header)
          ..setRange(header.length, header.length + body.length, body),
      );
    } on Object catch (error) {
      // The other side is gone; the input's end fails what is pending.
      onProtocolError?.call('write failed: $error');
    }
  }

  void _closed() {
    if (_isClosed) return;
    _isClosed = true;
    for (final MapEntry(:value) in [..._pending.entries]) {
      value.finish();
      value.completer.completeError(JsonRpcClosed(value.method));
    }
    _pending.clear();
    if (!_done.isCompleted) _done.complete();
  }

  void _receive(List<int> chunk) {
    if (_end + chunk.length > _buffer.length) {
      final unread = _end - _start;
      if (unread + chunk.length > _buffer.length) {
        var size = _buffer.length * 2;
        while (size < unread + chunk.length) {
          size *= 2;
        }
        _buffer = Uint8List(size)..setRange(0, unread, _buffer, _start);
      } else {
        _buffer.setRange(0, unread, _buffer, _start);
      }
      _start = 0;
      _end = unread;
    }
    _buffer.setRange(_end, _end + chunk.length, chunk);
    _end += chunk.length;
    while (!_isClosed && _readMessage()) {}
  }

  /// Reads one framed message from the buffer; false when it is incomplete.
  bool _readMessage() {
    if (_bodyLength case final length?) {
      if (_end - _start < length) return false;
      _bodyLength = null;
      return _readBody(length);
    }
    var headerEnd = -1;
    for (var i = _start; i + 3 < _end; i++) {
      if (_buffer[i] == 13 &&
          _buffer[i + 1] == 10 &&
          _buffer[i + 2] == 13 &&
          _buffer[i + 3] == 10) {
        headerEnd = i;
        break;
      }
    }
    if (headerEnd < 0) return false;
    final headers = latin1.decode(
      Uint8List.sublistView(_buffer, _start, headerEnd),
    );
    int? length;
    for (final line in headers.split('\r\n')) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      if (line.substring(0, colon).trim().toLowerCase() == 'content-length') {
        length = int.tryParse(line.substring(colon + 1).trim());
      }
    }
    final bodyStart = headerEnd + 4;
    if (length == null || length < 0) {
      // Not a header (e.g. a line a server printed on stdout): skip it.
      onProtocolError?.call('missing Content-Length in "$headers"');
      _start = bodyStart;
      return true;
    }
    _start = bodyStart;
    if (_end - _start < length) {
      // Waiting for the rest of the body: the header is not read again.
      _bodyLength = length;
      return false;
    }
    return _readBody(length);
  }

  bool _readBody(int length) {
    final body = Uint8List.sublistView(_buffer, _start, _start + length);
    _start += length;
    if (_start == _end) _start = _end = 0;
    Object? message;
    try {
      message = jsonDecode(utf8.decode(body));
    } on FormatException catch (error) {
      onProtocolError?.call('malformed message: ${error.message}');
      return true;
    }
    if (message is List) {
      for (final item in message) {
        _dispatch(item);
      }
    } else {
      _dispatch(message);
    }
    return true;
  }

  void _dispatch(Object? message) {
    if (message is! Map) {
      onProtocolError?.call('not a message: $message');
      return;
    }
    final id = message['id'];
    final method = message['method'];
    if (method is String) {
      if (id is String || id is num) {
        unawaited(_handleRequest(id!, method, message['params']));
      } else {
        _handleNotification(method, message['params']);
      }
      return;
    }
    final pending = _pending.remove(id);
    if (pending == null) return; // Answered after a cancel or a timeout.
    pending.finish();
    if (message['error'] case final Map error) {
      pending.completer.completeError(
        JsonRpcError(
          (error['code'] as num?)?.toInt() ?? JsonRpcError.internalError,
          '${error['message'] ?? 'Unknown error'}',
          data: error['data'],
        ),
      );
    } else {
      pending.completer.complete(message['result']);
    }
  }

  void _handleNotification(String method, Object? params) {
    if (method == r'$/cancelRequest') {
      final id = params is Map ? params['id'] : null;
      if (id != null && _incoming.containsKey(id)) _incoming[id] = true;
      return;
    }
    final handler = _notificationHandlers[method];
    if (handler == null) {
      onUnhandledNotification?.call(method, params);
      return;
    }
    try {
      handler(params);
    } on Object catch (error) {
      onProtocolError?.call('$method handler failed: $error');
    }
  }

  Future<void> _handleRequest(Object id, String method, Object? params) async {
    final handler = _requestHandlers[method];
    if (handler == null) {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'error': JsonRpcError(
          JsonRpcError.methodNotFound,
          'Unhandled method $method',
        ).toJson(),
      });
      return;
    }
    _incoming[id] = false;
    Map<String, Object?> response;
    try {
      final result = await handler(params);
      response = _incoming[id] == true
          ? {
              'jsonrpc': '2.0',
              'id': id,
              'error': const JsonRpcError(
                JsonRpcError.requestCancelled,
                'Request cancelled',
              ).toJson(),
            }
          : {'jsonrpc': '2.0', 'id': id, 'result': result};
    } on JsonRpcError catch (error) {
      response = {'jsonrpc': '2.0', 'id': id, 'error': error.toJson()};
    } on Object catch (error) {
      response = {
        'jsonrpc': '2.0',
        'id': id,
        'error': JsonRpcError(JsonRpcError.internalError, '$error').toJson(),
      };
    }
    _incoming.remove(id);
    _send(response);
  }
}
