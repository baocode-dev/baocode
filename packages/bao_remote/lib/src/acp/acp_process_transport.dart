import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'acp_connection.dart';

/// An `agy acp` process, its stdio as an [AcpTransport].
class AcpProcessTransport implements AcpTransport {
  AcpProcessTransport(this._process, {void Function(int code)? onExit}) {
    _process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_line, onDone: _stdoutDone);
    _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_stderrLine);
    unawaited(
      _process.exitCode.then((code) {
        _code = code;
        onExit?.call(code);
        _finish();
      }),
    );
  }

  final Process _process;
  final StreamController<Map<String, Object?>> _messages =
      StreamController.broadcast();
  final List<String> _stderr = [];
  final Completer<AcpExit> _exit = Completer();
  int? _code;
  bool _stdoutClosed = false;

  int get pid => _process.pid;

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  Future<AcpExit> get exited => _exit.future;

  void _line(String line) {
    if (line.trim().isEmpty) return;
    try {
      if (jsonDecode(line) case final Map<String, Object?> message) {
        _messages.add(message);
        return;
      }
    } on FormatException {
      // Not protocol: kept to say why it failed.
    }
    _stderrLine(line);
  }

  void _stderrLine(String line) {
    _stderr.add(line);
    if (_stderr.length > 30) _stderr.removeAt(0);
  }

  void _stdoutDone() {
    _stdoutClosed = true;
    _finish();
  }

  /// Whether it is gone, or going.
  bool get ended => _code != null || _closing;
  bool _closing = false;

  void _finish() {
    final code = _code;
    if (code == null || !_stdoutClosed || _exit.isCompleted) return;
    _exit.complete(AcpExit(code, _stderr.join('\n')));
    unawaited(_messages.close());
  }

  @override
  void write(Map<String, Object?> message) {
    if (_code != null) return;
    try {
      _process.stdin.writeln(jsonEncode(message));
    } on StateError {
      // Closed under us: the exit follows.
    }
  }

  @override
  void close() {
    if (_code != null) return;
    _closing = true;
    unawaited(_process.stdin.close().catchError((_) {}));
    if (Platform.isWindows) {
      unawaited(
        Process.run('taskkill', [
          '/pid',
          '${_process.pid}',
          '/T',
          '/F',
        ]).then<void>((_) {}, onError: (Object _) => _process.kill()),
      );
    } else {
      _process.kill();
    }
  }
}
