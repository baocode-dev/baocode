import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'engine.dart';
import 'session.dart';

/// A session's engine in an isolate of its own: its work (reading files,
/// running searches, parsing answers) off the caller's, messages in and
/// out as the protocol has them.
class AgentIsolate {
  AgentIsolate._(this._isolate, this._inbox, this._outbox, this._exits);

  final Isolate _isolate;
  final SendPort _inbox;
  final ReceivePort _outbox;
  final ReceivePort _exits;
  final StreamController<Map<String, Object?>> _messages =
      StreamController.broadcast();
  final Completer<void> _exited = Completer<void>();
  final List<String> _errors = [];
  bool _closing = false;

  /// Starts a session with [options].
  static Future<AgentIsolate> spawn(
    EngineOptions options, {
    String? debugName,
  }) async {
    final outbox = ReceivePort();
    final exits = ReceivePort();
    final errors = ReceivePort();
    final isolate = await Isolate.spawn(
      _main,
      (outbox.sendPort, options.toJson()),
      debugName: debugName ?? 'bao-agent',
      errorsAreFatal: false,
      onExit: exits.sendPort,
      onError: errors.sendPort,
    );
    final ready = Completer<SendPort>();
    final buffered = <Map<String, Object?>>[];
    late AgentIsolate agent;
    outbox.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      if (message is Map) {
        final map = message.cast<String, Object?>();
        if (!ready.isCompleted) {
          buffered.add(map);
        } else {
          agent._messages.add(map);
        }
      }
    });
    agent = AgentIsolate._(isolate, await ready.future, outbox, exits);
    errors.listen((error) {
      if (error is List && error.isNotEmpty) {
        agent._errors.add('${error.first}');
      }
    });
    exits.listen((_) => agent._onExit(errors));
    // What it said before it was ready, said after the listener is set.
    scheduleMicrotask(() {
      for (final message in buffered) {
        agent._messages.add(message);
      }
    });
    return agent;
  }

  /// What the engine says: the protocol's messages.
  Stream<Map<String, Object?>> get messages => _messages.stream;

  /// Errors no one caught in the isolate, for the record.
  List<String> get errors => List.unmodifiable(_errors);

  /// Completes once the isolate is gone.
  Future<void> get exited => _exited.future;

  /// Gives the engine a message (a user message, a control request or an
  /// answer to one of its own).
  void write(Map<String, Object?> message) {
    if (_exited.isCompleted || _closing) return;
    _inbox.send(message);
  }

  /// Ends the session: what runs is stopped, then the isolate ends.
  void close() {
    if (_closing || _exited.isCompleted) return;
    _closing = true;
    _inbox.send(_close);
    // One that will not end is ended.
    Timer(const Duration(seconds: 15), () {
      if (!_exited.isCompleted) _isolate.kill(priority: Isolate.immediate);
    });
  }

  void _onExit(ReceivePort errors) {
    _outbox.close();
    _exits.close();
    errors.close();
    if (!_exited.isCompleted) _exited.complete();
    unawaited(_messages.close());
  }

  static const _close = '__close__';

  static void _main((SendPort, Map<String, Object?>) start) {
    final (outbox, options) = start;
    final inbox = ReceivePort();
    outbox.send(inbox.sendPort);
    final parsed = EngineOptions.fromJson(options);
    // The host's own roots, as its own requests trust them: an upstream
    // may chain to one Mozilla's bundled ones do not have.
    if (parsed.rootCertificates.isNotEmpty) {
      HttpOverrides.global = _MachineCertificates(parsed.rootCertificates);
    }
    final engine = AgentEngine(parsed, send: outbox.send);
    // Ended by the host, or on its own (`end_session`): the isolate too.
    unawaited(
      engine.done.then((_) {
        inbox.close();
        Isolate.exit();
      }),
    );
    inbox.listen((message) {
      if (message == _close) {
        unawaited(engine.close());
      } else if (message is Map) {
        engine.receive(message.cast<String, Object?>());
      }
    });
  }
}

/// Every client the isolate makes trusts [certificates] (PEM) beside the
/// ones Dart bundles: the host's machine trusts more than Mozilla, and a
/// provider may chain to one of those (a company's CA, a proxy's).
class _MachineCertificates extends HttpOverrides {
  _MachineCertificates(List<String> certificates) {
    for (final certificate in certificates) {
      try {
        _context.setTrustedCertificatesBytes(utf8.encode(certificate));
      } on TlsException {
        // Among the bundled ones already: it is trusted either way.
      }
    }
  }

  final SecurityContext _context = SecurityContext(withTrustedRoots: true);

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(_context);
}
