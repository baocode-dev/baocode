import 'dart:async';
import 'dart:convert';

import 'rpc_error.dart';

/// A request's answer is no longer wanted: [RpcPeer.request]'s `cancel`
/// completed, and the other side told (`$/cancel`).
class RpcCancelled implements Exception {
  const RpcCancelled();

  @override
  String toString() => 'Cancelled';
}

/// The connection ended before the answer came.
class RpcClosed implements Exception {
  const RpcClosed();

  @override
  String toString() => 'The connection to the remote host closed';
}

/// A request being answered: [cancelled] completes when the asker gave up
/// on it.
class RpcCall {
  RpcCall._(this.method);

  final String method;
  final Completer<void> _cancelled = Completer();

  Future<void> get cancelled => _cancelled.future;
  bool get isCancelled => _cancelled.isCompleted;
}

/// Answers a request: its result is sent back, as is what it throws (see
/// [RpcError.from]).
typedef RpcHandler = FutureOr<Object?> Function(Object? params, RpcCall call);

/// One side of a JSON-RPC 2.0 connection over lines of text: a JSON object
/// a line, as the server's stdin and stdout carry them over SSH.
///
/// Both sides ask and answer: [request] and [notify] go out, and what comes
/// in is answered by the [handlers] (requests) and passed to the
/// [notificationHandlers] (notifications). A request the other side
/// cancels (`$/cancel`) has its [RpcCall.cancelled] complete, and is
/// answered with [RpcError.requestCancelled].
class RpcPeer {
  RpcPeer(Stream<String> lines, this._send) {
    _subscription = lines.listen(
      _receive,
      onDone: _closed,
      onError: (Object _) => _closed(),
    );
  }

  final void Function(String line) _send;
  late final StreamSubscription<String> _subscription;
  final Map<int, Completer<Object?>> _pending = {};
  final Map<Object, RpcCall> _calls = {};
  final Completer<void> _done = Completer();
  int _nextId = 0;

  /// What answers a request, by method.
  final Map<String, RpcHandler> handlers = {};

  /// What hears a notification, by method.
  final Map<String, void Function(Object? params)> notificationHandlers = {};

  /// Completes once the connection is gone (its lines ended, or [close]).
  Future<void> get done => _done.future;

  bool get isClosed => _done.isCompleted;

  /// Asks [method]; completes with the result, or with the error the other
  /// side answered (see [RpcError.toException]). Completing [cancel] gives
  /// up on it: the future fails with [RpcCancelled].
  Future<Object?> request(
    String method, [
    Object? params,
    Future<void>? cancel,
  ]) {
    if (isClosed) return Future.error(const RpcClosed());
    final id = ++_nextId;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _write({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params});
    cancel?.then((_) {
      if (_pending.remove(id) case final pending?) {
        notify(r'$/cancel', {'id': id});
        pending.completeError(const RpcCancelled());
      }
    });
    return completer.future;
  }

  /// Tells [method], expecting no answer.
  void notify(String method, [Object? params]) {
    if (isClosed) return;
    _write({'jsonrpc': '2.0', 'method': method, 'params': ?params});
  }

  /// Ends the connection: what is pending fails with [RpcClosed], and the
  /// calls being answered are cancelled.
  void close() {
    unawaited(_subscription.cancel());
    _closed();
  }

  void _write(Map<String, Object?> message) {
    try {
      _send(jsonEncode(message));
    } on Object {
      // The other side is gone: [done] follows from its lines ending.
    }
  }

  void _closed() {
    if (_done.isCompleted) return;
    _done.complete();
    final pending = [..._pending.values];
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(const RpcClosed());
    }
    for (final call in _calls.values) {
      if (!call._cancelled.isCompleted) call._cancelled.complete();
    }
    _calls.clear();
  }

  void _receive(String line) {
    if (line.trim().isEmpty) return;
    final Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException {
      return;
    }
    if (message is! Map) return;
    final id = message['id'];
    final method = message['method'];
    if (method is String) {
      if (id == null) {
        _notification(method, message['params']);
      } else {
        unawaited(_answer(id as Object, method, message['params']));
      }
      return;
    }
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null) return;
    if (message['error'] case final Map error) {
      completer.completeError(
        RpcError.fromJson(error.cast<String, Object?>()).toException(),
      );
    } else {
      completer.complete(message['result']);
    }
  }

  void _notification(String method, Object? params) {
    if (method == r'$/cancel') {
      if (params case {'id': final Object id}) {
        final call = _calls[id];
        if (call != null && !call._cancelled.isCompleted) {
          call._cancelled.complete();
        }
      }
      return;
    }
    notificationHandlers[method]?.call(params);
  }

  Future<void> _answer(Object id, String method, Object? params) async {
    final handler = handlers[method];
    if (handler == null) {
      _write({
        'jsonrpc': '2.0',
        'id': id,
        'error': RpcError(
          RpcError.methodNotFound,
          'No such method: $method',
        ).toJson(),
      });
      return;
    }
    final call = RpcCall._(method);
    _calls[id] = call;
    Map<String, Object?> answer;
    try {
      // Whichever comes first; the other's outcome is no one's.
      final work = Future.sync(() => handler(params, call))..ignore();
      final cancelled = call.cancelled.then<Object?>(
        (_) => throw const RpcCancelled(),
      )..ignore();
      final result = await Future.any([work, cancelled]);
      answer = {'result': result};
    } on Object catch (error, stack) {
      answer = {'error': RpcError.from(error, stack).toJson()};
    } finally {
      _calls.remove(id);
    }
    _write({'jsonrpc': '2.0', 'id': id, ...answer});
  }
}
