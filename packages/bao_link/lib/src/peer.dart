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
/// [LinkRemoteException] thrown, the error. A request on a stream of its
/// own ([LinkMethods.bulk]) may be answered with [LinkPieces], and may
/// have come with them ([LinkPeer.piecesOf]).
typedef LinkRequestHandler = FutureOr<Object?> Function(
  String method,
  Map<String, Object?> params,
);

/// A file's bytes, of any size, on a stream of their own: after the
/// request ([LinkPeer.callWithPieces]), or after the answer, `{"size",
/// "pieces": true}` ([LinkPeer.fetch]); one message a piece, of at most
/// [LinkLimits.piece], till the stream is finished.
class LinkPieces {
  const LinkPieces(this.size, this.bytes);

  /// All the bytes there are, as said beforehand.
  final int size;

  /// The bytes, in pieces as they come; an error if fewer than [size]
  /// came. Listened to once; cancelled, the stream is given up.
  final Stream<Uint8List> bytes;
}

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
    if (method == LinkMethods.open && params['have'] == null) {
      // What is had of it from before: only what changed comes.
      if ((mirror, params['session']) case (final mirror?, final String id)) {
        if (mirror.have(id) case final have?) {
          params = {...params, 'have': have};
        }
      }
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

  /// Asks the other end [method] on a stream of its own, an answer of any
  /// size: [LinkPieces] when it comes in them (waiting [idle] at most for
  /// each), else the result as [call]'s.
  Future<Object?> fetch(
    String method, [
    Map<String, Object?> params = const {},
    Duration timeout = const Duration(seconds: 30),
    Duration idle = const Duration(seconds: 30),
  ]) async {
    if (isClosed) throw const LinkClosedException('closed');
    final stream = await connection.open();
    final messages = StreamIterator(stream.messages);
    try {
      _write(stream, {'id': 0, 'm': method, 'p': params});
      unawaited(stream.finish().catchError((Object _) {}));
      if (!await messages.moveNext().timeout(timeout)) {
        throw const LinkClosedException('no answer');
      }
      final result = _result(messages.current);
      if (result case {'pieces': true, 'size': final int size}) {
        return LinkPieces(size, _pieces(stream, messages, size, idle));
      }
      unawaited(messages.cancel());
      return result;
    } on TimeoutException {
      stream.reset();
      throw TimeoutException('$method took too long', timeout);
    } on Object {
      stream.reset();
      rethrow;
    }
  }

  /// Asks the other end [method] on a stream of its own, [pieces] (a
  /// file's bytes, [size] of them, in any pieces) sent after the request,
  /// waiting [idle] at most for the other end to take each; its result.
  /// The other end gets them as [piecesOf] its params.
  Future<Object?> callWithPieces(
    String method,
    Map<String, Object?> params,
    int size,
    Stream<Uint8List> pieces, {
    Duration timeout = const Duration(seconds: 30),
    Duration idle = const Duration(seconds: 30),
  }) async {
    if (isClosed) throw const LinkClosedException('closed');
    final stream = await connection.open();
    final messages = StreamIterator(stream.messages);
    // An answer before all is sent (turned down, a desktop before pieces,
    // which reads none of them, its flow control holding a send back): no
    // more of them.
    final answered = messages.moveNext();
    var done = false;
    final settled = answered
        .then((_) {}, onError: (Object _) {})
        .whenComplete(() => done = true);
    try {
      _write(stream, {
        'id': 0,
        'm': method,
        'p': {...params, 'size': size},
        'pieces': true,
      });
      var sent = 0;
      await for (final piece in pieces) {
        for (final part in _parts(piece)) {
          if (done) break;
          final send = stream.send(part)..catchError((Object _) {});
          await Future.any([send, settled]).timeout(idle);
          if (done) break;
          sent += part.length;
        }
        if (done) break;
      }
      if (!done && sent != size) {
        throw StateError('$sent bytes of $size');
      }
      final early = done;
      if (!early) await stream.finish().timeout(idle);
      if (!await answered.timeout(timeout)) {
        throw const LinkClosedException('no answer');
      }
      // Not all sent: the rest, queued, dropped.
      if (early) stream.reset();
      return _result(messages.current);
    } on TimeoutException {
      stream.reset();
      throw TimeoutException('$method took too long', timeout);
    } on Object {
      stream.reset();
      rethrow;
    } finally {
      unawaited(messages.cancel());
    }
  }

  /// The pieces sent with the request [params] came in, if it came with
  /// any ([callWithPieces]).
  static LinkPieces? piecesOf(Map<String, Object?> params) =>
      switch (params[_piecesKey]) {
        final LinkPieces pieces => pieces,
        _ => null,
      };

  /// Where [piecesOf] finds them: no key of JSON's, which a request could
  /// only give a string or such, never [LinkPieces].
  static const _piecesKey = r'$pieces';

  /// [bytes] in parts of at most [LinkLimits.piece].
  static Iterable<Uint8List> _parts(Uint8List bytes) sync* {
    if (bytes.length <= LinkLimits.piece) {
      yield bytes;
      return;
    }
    for (var start = 0; start < bytes.length; start += LinkLimits.piece) {
      final end = start + LinkLimits.piece;
      yield Uint8List.sublistView(
        bytes,
        start,
        end < bytes.length ? end : bytes.length,
      );
    }
  }

  /// What is left of [messages], [stream]'s, as the pieces of [size]
  /// bytes; each waited on [idle] at most. Given up when no longer
  /// listened to.
  static Stream<Uint8List> _pieces(
    LinkStream stream,
    StreamIterator<Uint8List> messages,
    int size,
    Duration idle,
  ) async* {
    var got = 0;
    var ended = false;
    try {
      while (await messages.moveNext().timeout(idle)) {
        got += messages.current.length;
        if (got > size) throw StateError('More than $size bytes');
        yield messages.current;
      }
      ended = true;
      if (got != size) {
        throw LinkClosedException('$got bytes of $size');
      }
    } finally {
      if (!ended) {
        stream.reset();
        unawaited(messages.cancel());
      }
    }
  }

  /// An answer's result; its error thrown.
  static Object? _result(Uint8List message) => switch (_decode(message)) {
    {'e': {'c': final String code, 'm': final String text}} =>
      throw LinkRemoteException(code, text),
    final Map<String, Object?> answer => answer['r'],
    _ => throw const LinkRemoteException('failed', 'Bad answer'),
  };

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
            if (isClosed) return;
            _write(_control, {
              'id': id,
              // Pieces go on a stream of their own, not this one.
              ...answer['r'] is LinkPieces
                  ? const {
                      'e': {'c': 'failed', 'm': 'Pieces on the control stream'},
                    }
                  : answer,
            });
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
        // caller gets to the answer; and told the app in that order too,
        // among the updates (which it would otherwise get to first, or
        // after, as it happens).
        if (mirror case final mirror?) {
          if (_mirrorAnswer(mirror, pending, message['r']) case final event?) {
            _events.add(event);
          }
        }
        pending.completer.complete(message['r']);
    }
  }

  /// [result] of [pending] kept by [mirror]; the event that tells the app
  /// of it, if it is of a session.
  LinkEvent? _mirrorAnswer(
    LinkSessionMirror mirror,
    _Pending pending,
    Object? result,
  ) {
    switch ((pending.method, result)) {
      case (LinkMethods.open, final Map<String, Object?> update):
        return switch (mirror.opened(update)) {
          final whole? => LinkEvent(LinkEvents.session, whole),
          null => LinkEvent(LinkEvents.resync, {'session': update['session']}),
        };
      case (LinkMethods.earlier, {'items': final List<Object?> items}):
        if (pending.params['session'] case final String session) {
          mirror.earlier(session, items);
          return LinkEvent(LinkEvents.earlier, {
            'session': session,
            'items': items,
            'earlier': (result as Map)['earlier'],
          });
        }
    }
    return null;
  }

  void _event(String name, Object? data) {
    final mirror = this.mirror;
    if (name == LinkEvents.session &&
        data is Map<String, Object?> &&
        mirror != null) {
      if (mirror.stale(data)) return;
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
    final messages = StreamIterator(stream.messages);
    try {
      if (!await messages.moveNext().timeout(const Duration(seconds: 30))) {
        throw const LinkClosedException('no request');
      }
      final request = _decode(messages.current);
      final Map<String, Object?> answer;
      if (request is Map<String, Object?> && request['m'] is String) {
        var params = switch (request['p']) {
          final Map<String, Object?> params => params,
          _ => const <String, Object?>{},
        };
        if (request['pieces'] == true) {
          final size = params['size'];
          if (size is! int || size < 0) {
            throw const LinkRemoteException('bad', 'No size');
          }
          params = {
            ...params,
            _piecesKey: LinkPieces(
              size,
              _pieces(stream, messages, size, const Duration(seconds: 30)),
            ),
          };
        }
        answer = await _answer(request['m']! as String, params);
      } else {
        answer = const {
          'e': {'c': 'failed', 'm': 'Bad request'},
        };
      }
      if (isClosed) return;
      if (answer['r'] case final LinkPieces pieces) {
        _write(stream, {
          'id': 0,
          'r': {'size': pieces.size, 'pieces': true},
        });
        var sent = 0;
        await for (final piece in pieces.bytes) {
          for (final part in _parts(piece)) {
            await stream.send(part);
            sent += part.length;
          }
        }
        // Fewer than said: given up, for the other end to see it cut short.
        if (sent != pieces.size) throw StateError('$sent of ${pieces.size}');
      } else {
        _write(stream, {'id': 0, ...answer});
      }
      await stream.finish();
    } on Object {
      stream.reset();
    } finally {
      unawaited(messages.cancel());
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
