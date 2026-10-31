import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'connection.dart';
import 'protocol.dart';
import 'session_mirror.dart';

/// A request the other end turned down, or could not carry out.
class LinkRemoteException implements Exception {
  const LinkRemoteException(this.code, this.message);

  /// What went wrong, for code: `unknown`, `notFound`, `failed`, …
  final String code;
  final String message;

  @override
  String toString() => 'LinkRemoteException($code): $message';
}

/// Something one end tells the other, unasked.
class LinkEvent {
  const LinkEvent(this.name, this.data);

  final String name;
  final Object? data;
}

/// Answers a request: what it returns (as JSON) is the result; a
/// [LinkRemoteException] thrown, the error.
typedef LinkRequestHandler = FutureOr<Object?> Function(
  String method,
  Map<String, Object?> params,
);

/// Requests, answers and events, as JSON, over a [LinkConnection]: the same
/// on both ends.
///
/// The dialler opens the first stream, the control stream: requests,
/// answers and events in order.
///
/// - a request: `{"id": 1, "m": "send", "p": {…}}`;
/// - its answer: `{"id": 1, "r": …}`, or `{"id": 1, "e": {"c": …, "m": …}}`;
/// - an event: `{"ev": "session", "p": …}`.
///
/// A request for something large ([LinkMethods.bulk]: a file, a picture)
/// goes on a stream of its own instead, its answer back on it, so that it
/// holds up nothing on the control stream.
class LinkPeer {
  LinkPeer._(this.connection, this._control, this._onRequest, this.mirror) {
    _control.messages.listen(
      _receive,
      onError: (Object _) => _end(),
      onDone: _end,
    );
    unawaited(connection.closed.then((_) => _end()));
  }

  /// The dialler's end: opens the control stream. With [mirror], session
  /// updates come out whole however slim they come in (the phone's).
  static Future<LinkPeer> connect(
    LinkConnection connection, {
    LinkRequestHandler? onRequest,
    LinkSessionMirror? mirror,
  }) async {
    final control = await connection.open();
    final peer = LinkPeer._(connection, control, onRequest, mirror);
    peer._takeStreams(connection.incoming);
    return peer;
  }

  /// The other end: the first stream the dialler opens is the control
  /// stream; it has [timeout] to open it.
  static Future<LinkPeer> accept(
    LinkConnection connection, {
    LinkRequestHandler? onRequest,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final first = Completer<LinkStream>();
    final rest = StreamController<LinkStream>();
    late final StreamSubscription<LinkStream> subscription;
    subscription = connection.incoming.listen(
      (stream) => first.isCompleted ? rest.add(stream) : first.complete(stream),
      onError: (Object error) {
        if (!first.isCompleted) first.completeError(error);
      },
      onDone: () {
        if (!first.isCompleted) {
          first.completeError(const LinkClosedException('no control stream'));
        }
        unawaited(rest.close());
      },
    );
    final LinkStream control;
    try {
      control = await first.future.timeout(timeout);
    } on Object {
      await subscription.cancel();
      connection.close();
      rethrow;
    }
    final peer = LinkPeer._(connection, control, onRequest, null);
    peer._takeStreams(rest.stream);
    return peer;
  }

  final LinkConnection connection;
  final LinkStream _control;
  LinkRequestHandler? _onRequest;

  /// What makes whole session updates of slim ones, on the phone.
  final LinkSessionMirror? mirror;

  set onRequest(LinkRequestHandler? handler) => _onRequest = handler;

  int _nextId = 1;
  final Map<int, _Pending> _pending = {};
  final _events = StreamController<LinkEvent>.broadcast();
  final _done = Completer<void>();

  /// The other end's events.
  Stream<LinkEvent> get events => _events.stream;

  /// Completes once the connection has ended.
  Future<void> get done => _done.future;

  bool get isClosed => _done.isCompleted;

  /// The other end's id, as the connection proved it.
  String get remote => connection.remote;

  /// Asks the other end [method]; its result.
  Future<Object?> call(
    String method, [
    Map<String, Object?> params = const {},
    Duration timeout = const Duration(seconds: 30),
  ]) {
    if (isClosed) return Future.error(const LinkClosedException('closed'));
    if (LinkMethods.bulk.contains(method)) {
      return _callOnStream(method, params, timeout);
    }
    final id = _nextId++;
    final pending = _pending[id] = _Pending(method, params);
    if (method == LinkMethods.close && params['session'] is String) {
      mirror?.closed(params['session']! as String);
    }
    _write(_control, {'id': id, 'm': method, 'p': params});
    return pending.completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('$method took too long', timeout);
      },
    );
  }

  Future<Object?> _callOnStream(
    String method,
    Map<String, Object?> params,
    Duration timeout,
  ) async {
    final stream = await connection.open();
    try {
      return await () async {
        _write(stream, {'id': 0, 'm': method, 'p': params});
        unawaited(stream.finish().catchError((Object _) {}));
        final message = await stream.messages.first;
        return switch (_decode(message)) {
          {'e': {'c': final String code, 'm': final String text}} =>
            throw LinkRemoteException(code, text),
          final Map<String, Object?> answer => answer['r'],
          _ => throw const LinkRemoteException('failed', 'Bad answer'),
        };
      }().timeout(timeout);
    } on StateError {
      // Ended with no answer.
      throw const LinkClosedException('no answer');
    } on TimeoutException {
      stream.reset();
      throw TimeoutException('$method took too long', timeout);
    }
  }

  /// Tells the other end [name].
  void emit(String name, [Object? data]) {
    if (!isClosed) _write(_control, {'ev': name, 'p': data});
  }

  void _write(LinkStream stream, Map<String, Object?> message) {
    stream
        .send(Uint8List.fromList(utf8.encode(jsonEncode(message))))
        .catchError((Object _) {});
  }

  static Object? _decode(Uint8List bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
  }

  void _receive(Uint8List bytes) {
    final message = _decode(bytes);
    switch (message) {
      case {'ev': final String name}:
        _event(name, message['p']);
      case {'id': final int id, 'm': final String method}:
        unawaited(
          _answer(method, message['p']).then((answer) {
            if (!isClosed) _write(_control, {'id': id, ...answer});
          }),
        );
      case {
        'id': final int id,
        'e': {'c': final String code, 'm': final String text},
      }:
        _pending
            .remove(id)
            ?.completer
            .completeError(LinkRemoteException(code, text));
      case {'id': final int id}:
        final pending = _pending.remove(id);
        if (pending == null) return;
        // Kept in step here, in the order things came, whenever the
        // caller gets to the answer.
        if (mirror case final mirror?) {
          _mirrorAnswer(mirror, pending, message['r']);
        }
        pending.completer.complete(message['r']);
    }
  }

  void _mirrorAnswer(
    LinkSessionMirror mirror,
    _Pending pending,
    Object? result,
  ) {
    switch ((pending.method, result)) {
      case (LinkMethods.open, final Map<String, Object?> update):
        mirror.opened(update);
      case (LinkMethods.earlier, {'items': final List<Object?> items}):
        if (pending.params['session'] case final String session) {
          mirror.earlier(session, items);
        }
    }
  }

  void _event(String name, Object? data) {
    final mirror = this.mirror;
    if (name == LinkEvents.session &&
        data is Map<String, Object?> &&
        mirror != null) {
      final whole = mirror.apply(data);
      _events.add(
        whole == null
            ? LinkEvent(LinkEvents.resync, {'session': data['session']})
            : LinkEvent(name, whole),
      );
      return;
    }
    _events.add(LinkEvent(name, data));
  }

  /// Takes the request streams the other end opens.
  void _takeStreams(Stream<LinkStream> streams) {
    streams.listen(
      (stream) => unawaited(_serve(stream)),
      onError: (Object _) {},
    );
  }

  Future<void> _serve(LinkStream stream) async {
    try {
      final message = await stream.messages.first.timeout(
        const Duration(seconds: 30),
      );
      final request = _decode(message);
      final answer = request is Map<String, Object?> && request['m'] is String
          ? await _answer(request['m']! as String, request['p'])
          : const {
              'e': {'c': 'failed', 'm': 'Bad request'},
            };
      if (isClosed) return;
      _write(stream, {'id': 0, ...answer});
      await stream.finish();
    } on Object {
      stream.reset();
    }
  }

  Future<Map<String, Object?>> _answer(String method, Object? params) async {
    final handler = _onRequest;
    try {
      if (handler == null) {
        throw LinkRemoteException('unknown', 'No such request: $method');
      }
      final result = await handler(
        method,
        params is Map<String, Object?> ? params : const {},
      );
      return {'r': result};
    } on LinkRemoteException catch (error) {
      return {
        'e': {'c': error.code, 'm': error.message},
      };
    } catch (error) {
      return {
        'e': {'c': 'failed', 'm': '$error'},
      };
    }
  }

  void _end() {
    if (_done.isCompleted) return;
    for (final pending in _pending.values) {
      pending.completer.completeError(const LinkClosedException('closed'));
    }
    _pending.clear();
    if (!_events.isClosed) unawaited(_events.close());
    _done.complete();
    connection.close();
  }

  Future<void> close() async => _end();
}

class _Pending {
  _Pending(this.method, this.params);

  final String method;
  final Map<String, Object?> params;
  final completer = Completer<Object?>();
}
