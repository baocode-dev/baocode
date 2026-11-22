import 'dart:async';

/// An ACP agent's end of its stdio (the Agent Client Protocol): what it
/// prints, one JSON-RPC message per line, and what is written to it.
abstract interface class AcpTransport {
  /// What it prints, until it is gone.
  Stream<Map<String, Object?>> get messages;

  void write(Map<String, Object?> message);

  /// Ends it.
  void close();

  /// Completes once it is gone: its exit code, and the last lines it put
  /// on stderr (to say why).
  Future<AcpExit> get exited;
}

/// How an agent's process ended.
class AcpExit {
  const AcpExit(this.code, [this.stderr = '']);

  final int code;
  final String stderr;
}

/// An error an agent answered a request with, or the connection's own.
class AcpError implements Exception {
  const AcpError(this.code, this.message, {this.data});

  /// What a request still waiting gets once the agent is gone.
  static const closedCode = -32099;

  final int code;
  final String message;
  final Object? data;

  bool get closed => code == closedCode;

  @override
  String toString() => 'AcpError($code): $message';
}

/// Answers a request the agent makes of the client (`session/request_permission`,
/// `fs/read_text_file`): its result, or throws an [AcpError].
typedef AcpRequestHandler = Future<Object?> Function(
  String method,
  Map<String, Object?> params,
);

/// The client side of a JSON-RPC 2.0 connection to an ACP agent: requests
/// it sends and waits on, notifications both ways, and the agent's own
/// requests answered by [onRequest].
class AcpConnection {
  AcpConnection(
    this._transport, {
    required this.onRequest,
    required this.onNotification,
  }) {
    _subscription = _transport.messages.listen(
      _receive,
      onDone: _closed,
      onError: (Object _) {},
    );
  }

  final AcpTransport _transport;
  final AcpRequestHandler onRequest;
  final void Function(String method, Map<String, Object?> params)
  onNotification;
  late final StreamSubscription<Map<String, Object?>> _subscription;

  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  int _nextId = 0;
  bool _done = false;

  /// Whether the agent is gone.
  bool get done => _done;

  Future<AcpExit> get exited => _transport.exited;

  /// Sends [method] and waits for its result; throws [AcpError] for an
  /// error, or once the agent is gone.
  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) {
    if (_done) {
      return Future.error(const AcpError(AcpError.closedCode, 'Agent stopped'));
    }
    final id = ++_nextId;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _transport.write({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    return completer.future;
  }

  void notify(String method, [Map<String, Object?> params = const {}]) {
    if (_done) return;
    _transport.write({'jsonrpc': '2.0', 'method': method, 'params': params});
  }

  void close() {
    _transport.close();
  }

  void _receive(Map<String, Object?> message) {
    final method = message['method'];
    final id = message['id'];
    final params = switch (message['params']) {
      final Map<Object?, Object?> params => params.cast<String, Object?>(),
      _ => const <String, Object?>{},
    };
    if (method is String) {
      if (id == null) {
        onNotification(method, params);
      } else {
        unawaited(_answer(id, method, params));
      }
      return;
    }
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null) return;
    if (message['error'] case final Map<Object?, Object?> error) {
      completer.completeError(
        AcpError(
          error['code'] as int? ?? -32603,
          error['message'] as String? ?? 'Error',
          data: error['data'],
        ),
      );
      return;
    }
    completer.complete(switch (message['result']) {
      final Map<Object?, Object?> result => result.cast<String, Object?>(),
      _ => const <String, Object?>{},
    });
  }

  Future<void> _answer(
    Object id,
    String method,
    Map<String, Object?> params,
  ) async {
    Map<String, Object?> reply;
    try {
      reply = {'result': await onRequest(method, params)};
    } on AcpError catch (error) {
      reply = {
        'error': {
          'code': error.code,
          'message': error.message,
          if (error.data != null) 'data': error.data,
        },
      };
    } on Object catch (error) {
      reply = {
        'error': {'code': -32603, 'message': '$error'},
      };
    }
    if (_done) return;
    _transport.write({'jsonrpc': '2.0', 'id': id, ...reply});
  }

  void _closed() {
    _done = true;
    for (final completer in _pending.values) {
      completer.completeError(
        const AcpError(AcpError.closedCode, 'Agent stopped'),
      );
    }
    _pending.clear();
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    _closed();
  }
}
