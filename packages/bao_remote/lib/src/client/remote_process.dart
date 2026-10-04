import 'dart:async';
import 'dart:typed_data';

/// A process on the remote host: what it prints comes as [stdout] and
/// [stderr] (buffered until listened to), [exitCode] once it is gone. Lost
/// with the connection, it exits with [lostExitCode].
abstract interface class RemoteProcess {
  /// Its exit code when the connection went before the process did.
  static const lostExitCode = -1;

  int get pid;
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;

  void write(List<int> bytes);
  Future<void> closeStdin();

  /// Ends it: politely (SIGTERM), or at once when [force].
  void kill({bool force = false});
}

/// The client's record of a process: fed by the notifications of its id.
class RemoteProcessHandle implements RemoteProcess {
  RemoteProcessHandle({
    required this.id,
    required this.pid,
    required this._write,
    required this._closeStdin,
    required this._kill,
  });

  final int id;
  @override
  final int pid;
  final void Function(List<int> bytes) _write;
  final Future<void> Function() _closeStdin;
  final void Function(bool force) _kill;
  final StreamController<List<int>> _stdout = StreamController();
  final StreamController<List<int>> _stderr = StreamController();
  final Completer<int> _exitCode = Completer();
  bool _stdinClosed = false;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  bool get exited => _exitCode.isCompleted;

  /// Output of fd [fd] (1 or 2).
  void output(int fd, Uint8List data) {
    if (exited) return;
    (fd == 2 ? _stderr : _stdout).add(data);
  }

  void exit(int code) {
    if (exited) return;
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    _exitCode.complete(code);
  }

  @override
  void write(List<int> bytes) {
    if (exited || _stdinClosed) return;
    _write(bytes);
  }

  @override
  Future<void> closeStdin() async {
    if (exited || _stdinClosed) return;
    _stdinClosed = true;
    await _closeStdin();
  }

  @override
  void kill({bool force = false}) {
    if (exited) return;
    _kill(force);
  }
}
