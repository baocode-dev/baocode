import 'dart:async';

/// A control request the CLI refused or never answered.
class ControlError implements Exception {
  const ControlError(this.subtype, this.message);

  final String subtype;
  final String message;

  @override
  String toString() => '$subtype: $message';
}

/// The control side of Claude Code's stream-json protocol: our requests
/// and their responses, matched by request id, and the CLI's requests to
/// us (tool permissions), answered once.
class ControlChannel {
  ControlChannel(this._write);

  final void Function(Map<String, Object?> message) _write;
  final Map<String, ({String subtype, Completer<Map<String, Object?>> done})>
  _pending = {};
  int _next = 0;

  /// Sends a `control_request`; completes with its response payload.
  Future<Map<String, Object?>> request(
    String subtype, [
    Map<String, Object?> fields = const {},
    Duration timeout = const Duration(seconds: 60),
  ]) {
    final id = 'monad-${++_next}';
    final done = Completer<Map<String, Object?>>();
    _pending[id] = (subtype: subtype, done: done);
    _write({
      'type': 'control_request',
      'request_id': id,
      'request': {'subtype': subtype, ...fields},
    });
    return done.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw ControlError(subtype, 'no response');
      },
    );
  }

  /// Takes a `control_response`; returns whether it was ours.
  bool receive(Map<String, Object?> message) {
    if (message['type'] != 'control_response') return false;
    final response = message['response'];
    if (response is! Map) return false;
    final pending = _pending.remove(response['request_id']);
    if (pending == null) return true;
    if (response['subtype'] == 'success') {
      final payload = response['response'];
      pending.done.complete(
        payload is Map ? payload.cast<String, Object?>() : const {},
      );
    } else {
      pending.done.completeError(
        ControlError(pending.subtype, '${response['error'] ?? 'failed'}'),
      );
    }
    return true;
  }

  /// Answers the CLI's request [requestId].
  void respond(String requestId, Map<String, Object?> payload) => _write({
    'type': 'control_response',
    'response': {
      'subtype': 'success',
      'request_id': requestId,
      'response': payload,
    },
  });

  void refuse(String requestId, String error) => _write({
    'type': 'control_response',
    'response': {'subtype': 'error', 'request_id': requestId, 'error': error},
  });

  /// Fails every request still waiting, e.g. when the process is gone.
  void failAll(String why) {
    final pending = [..._pending.values];
    _pending.clear();
    for (final (:subtype, :done) in pending) {
      done.completeError(ControlError(subtype, why));
    }
  }
}
