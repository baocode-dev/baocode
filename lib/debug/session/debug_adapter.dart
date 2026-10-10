/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A debug adapter as the debug session talks to it: DAP requests with
// sequence numbers and their responses, events and reverse requests, over
// a [DebugAdapterTransport] that carries the messages (the extension host,
// for adapters extensions provide; a process's stdio or a socket in tests).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/common/abstractDebugAdapter.ts
// (`AbstractDebugAdapter`).
//
// Deviations: how messages travel is a separate [DebugAdapterTransport]
// rather than the subclass (upstream's `ExtensionHostDebugAdapter` and
// `StreamDebugAdapter` are subclasses); the glue's transport for the
// extension host forwards `$startDASession`, `$sendDAMessage` and
// `$stopDASession`, and feeds `$acceptDAMessage`/`$acceptDAError`/
// `$acceptDAExit` into [EmitterDebugAdapterTransport].

import 'dart:async';

import '../base/event.dart';
import '../common/debug_types.dart';

/// What carries DAP messages between the client and one debug adapter.
abstract interface class DebugAdapterTransport {
  /// Starts the adapter, or connects to it.
  Future<void> start();

  /// Sends one DAP message (a request, a response to a reverse request).
  void send(Json message);

  /// Stops the adapter, or disconnects.
  Future<void> stop();

  /// A message from the adapter.
  DebugDisposable onMessage(void Function(Json message) listener);

  /// The adapter failed (it could not start, the connection broke).
  DebugDisposable onError(void Function(Object error) listener);

  /// The adapter went away, with its exit code where known.
  DebugDisposable onExit(void Function(int? code) listener);

  void dispose();
}

/// A transport whose incoming side is fed from outside: the extension
/// host's `$acceptDAMessage`, `$acceptDAError` and `$acceptDAExit`.
abstract class EmitterDebugAdapterTransport implements DebugAdapterTransport {
  final Emitter<Json> _onMessage = Emitter<Json>();
  final Emitter<Object> _onError = Emitter<Object>();
  final Emitter<int?> _onExit = Emitter<int?>();

  /// A message from the adapter.
  void acceptMessage(Json message) => _onMessage.fire(message);

  void fireError(Object error) => _onError.fire(error);

  void fireExit(int? code) => _onExit.fire(code);

  @override
  DebugDisposable onMessage(void Function(Json message) listener) =>
      _onMessage.listen(listener);

  @override
  DebugDisposable onError(void Function(Object error) listener) =>
      _onError.listen(listener);

  @override
  DebugDisposable onExit(void Function(int? code) listener) =>
      _onExit.listen(listener);

  @override
  void dispose() {
    _onMessage.dispose();
    _onError.dispose();
    _onExit.dispose();
  }
}

/// `IDebugAdapter` over a transport (`AbstractDebugAdapter`).
class DebugAdapter {
  DebugAdapter(this.transport) {
    _subscriptions
      ..add(transport.onMessage(acceptMessage))
      ..add(transport.onError(_onError.fire))
      ..add(transport.onExit(_onExit.fire));
  }

  final DebugAdapterTransport transport;
  final DisposableStore _subscriptions = DisposableStore();

  int _sequence = 1;
  final Map<int, void Function(Json response)> _pendingRequests = {};
  final Map<int, Timer> _pendingRequestTimers = {};
  void Function(Json request)? _requestCallback;
  void Function(Json event)? _eventCallback;
  void Function(Json message)? _messageCallback;
  List<Json> _queue = [];
  final Emitter<Object> _onError = Emitter<Object>();
  final Emitter<int?> _onExit = Emitter<int?>();
  bool _disposed = false;

  DebugDisposable onError(void Function(Object error) listener) =>
      _onError.listen(listener);

  DebugDisposable onExit(void Function(int? code) listener) =>
      _onExit.listen(listener);

  Future<void> startSession() => transport.start();

  Future<void> stopSession() async {
    await cancelPendingRequests();
    await transport.stop();
  }

  void sendMessage(Json message) => transport.send(message);

  /// Every message, instead of their dispatch (used by tracing).
  void onMessage(void Function(Json message) callback) {
    if (_messageCallback != null) {
      _onError.fire(StateError("attempt to set more than one 'Message' callback"));
    }
    _messageCallback = callback;
  }

  void onEvent(void Function(Json event) callback) {
    if (_eventCallback != null) {
      _onError.fire(StateError("attempt to set more than one 'Event' callback"));
    }
    _eventCallback = callback;
  }

  void onRequest(void Function(Json request) callback) {
    if (_requestCallback != null) {
      _onError.fire(StateError("attempt to set more than one 'Request' callback"));
    }
    _requestCallback = callback;
  }

  void sendResponse(Json response) {
    final seq = response['seq'];
    if (seq is int && seq > 0) {
      _onError.fire(
        StateError(
          'attempt to send more than one response for command ${response['command']}',
        ),
      );
    } else {
      _internalSend('response', response);
    }
  }

  /// Sends [command]; [callback] gets its response (a failed one after
  /// [timeout]). Returns the request's sequence number.
  int sendRequest(
    String command,
    Object? args,
    void Function(Json response)? callback, {
    Duration? timeout,
  }) {
    final request = <String, Object?>{'command': command};
    if (args is Map && args.isNotEmpty) request['arguments'] = args;
    _internalSend('request', request);
    final seq = request['seq']! as int;
    if (timeout != null) {
      _pendingRequestTimers[seq] = Timer(timeout, () {
        _pendingRequestTimers.remove(seq);
        final clb = _pendingRequests.remove(seq);
        clb?.call({
          'type': 'response',
          'seq': 0,
          'request_seq': seq,
          'success': false,
          'command': command,
          'message': "Timeout after ${timeout.inMilliseconds} ms for '$command'",
        });
      });
    }
    if (callback != null) _pendingRequests[seq] = callback;
    return seq;
  }

  /// A message from the adapter: dispatched in order, each in a task of
  /// its own unless both are events (`needsTaskBoundaryBetween`).
  void acceptMessage(Json message) {
    if (_messageCallback case final callback?) {
      callback(message);
      return;
    }
    _queue.add(message);
    if (_queue.length == 1) unawaited(_processQueue());
  }

  bool needsTaskBoundaryBetween(Json a, Json b) =>
      a['type'] != 'event' || b['type'] != 'event';

  Future<void> _processQueue() async {
    Json? message;
    while (_queue.isNotEmpty) {
      if (message == null || needsTaskBoundaryBetween(_queue.first, message)) {
        await Future<void>.delayed(Duration.zero);
      }
      if (_queue.isEmpty) return;
      message = _queue.removeAt(0);
      switch (message['type']) {
        case 'event':
          _eventCallback?.call(message);
        case 'request':
          _requestCallback?.call(message);
        case 'response':
          final requestSeq = message['request_seq'];
          if (requestSeq is int) {
            final clb = _pendingRequests.remove(requestSeq);
            if (clb != null) {
              _clearPendingRequestTimer(requestSeq);
              clb(message);
            }
          }
      }
    }
  }

  void _internalSend(String type, Json message) {
    if (_disposed) return;
    message['type'] = type;
    message['seq'] = _sequence++;
    sendMessage(message);
  }

  /// Fails what is still waiting for an answer, half a second on.
  Future<void> cancelPendingRequests() async {
    if (_pendingRequests.isEmpty) return;
    final pending = Map.of(_pendingRequests);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    pending.forEach((requestSeq, callback) {
      callback({
        'type': 'response',
        'seq': 0,
        'request_seq': requestSeq,
        'success': false,
        'command': 'canceled',
        'message': 'canceled',
      });
      _pendingRequests.remove(requestSeq);
      _clearPendingRequestTimer(requestSeq);
    });
  }

  void _clearPendingRequestTimer(int requestSeq) =>
      _pendingRequestTimers.remove(requestSeq)?.cancel();

  List<int> get pendingRequestIds => _pendingRequests.keys.toList();

  void dispose() {
    _disposed = true;
    for (final timer in _pendingRequestTimers.values) {
      timer.cancel();
    }
    _pendingRequestTimers.clear();
    _subscriptions.dispose();
    _onError.dispose();
    _onExit.dispose();
    _queue = [];
    transport.dispose();
  }
}
