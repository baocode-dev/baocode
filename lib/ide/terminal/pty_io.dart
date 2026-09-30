import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../kernel/claude_code/claude_environment.dart';
import '../../platform/app_paths.dart';
import '../../platform/child_process_registry.dart';
import 'pty.dart';
import 'pty_native.dart';
import 'pty_windows.dart';
import 'shell_integration/shell_integration_files.dart';
import 'terminal_shell.dart';

abstract final class PtyProcesses {
  /// Where the running terminal processes are kept track of across runs. A
  /// leftover is hung up, as closing its terminal would have.
  @visibleForTesting
  static ChildProcessRegistry registry = ChildProcessRegistry(
    file: File(
      p.join(AppPaths.dataDir(Platform.environment), 'pty-processes.json'),
    ),
    signal: (pid) => Process.killPid(pid, ProcessSignal.sighup),
  );

  static final Set<Pty> _live = {};

  static bool get supported => Platform.isWindows
      ? WindowsPty.supported
      : (Platform.isMacOS || Platform.isLinux) && _PosixPty.supported;

  static Future<Pty> start(PtyLaunch launch) async {
    await registry.reaped;
    if (!Directory(launch.workingDirectory).existsSync()) {
      throw PtyException('The folder is gone', detail: launch.workingDirectory);
    }
    final environment = launch.environment ?? Platform.environment;
    final pty = Platform.isWindows
        ? await WindowsPty.start(launch, environment)
        : await _PosixPty.start(launch, environment);
    _live.add(pty);
    unawaited(registry.add(pty.pid));
    unawaited(
      pty.exitCode.then((_) {
        _live.remove(pty);
        unawaited(registry.remove(pty.pid));
      }),
    );
    return pty;
  }

  static Future<PtyLaunch> terminalLaunch(
    String root, {
    required int columns,
    required int rows,
    required bool shellIntegration,
  }) async {
    final os = Platform.isWindows
        ? TerminalOs.windows
        : Platform.isMacOS
        ? TerminalOs.macOS
        : TerminalOs.linux;
    // As VS Code, whose terminals inherit the environment it resolved from
    // the login shell.
    final base = await ClaudeEnvironment.of();
    final shell = defaultTerminalShell(
      os,
      base,
      exists: (path) => File(path).existsSync(),
      list: (directory) {
        try {
          return [
            for (final entity in Directory(directory).listSync())
              p.basename(entity.path),
          ];
        } on FileSystemException {
          return const [];
        }
      },
    );
    final launch = PtyLaunch(
      executable: shell.executable,
      arguments: shell.arguments,
      workingDirectory: root,
      environment: terminalEnvironment(
        base,
        os: os,
        locale: Platform.localeName,
      ),
      columns: columns,
      rows: rows,
    );
    return shellIntegration ? injectShellIntegration(launch, os: os) : launch;
  }

  /// Hangs up every terminal this run started, and waits (up to [timeout]
  /// each) for its process to end: killed if it does not.
  static Future<void> stopAll({
    Duration timeout = const Duration(seconds: 2),
  }) => Future.wait([
    for (final pty in [..._live]) _stop(pty, timeout),
  ]);

  static Future<void> _stop(Pty pty, Duration timeout) async {
    pty.kill();
    try {
      await pty.exitCode.timeout(timeout);
    } on TimeoutException {
      pty.kill(PtySignal.kill);
      await pty.exitCode.timeout(timeout, onTimeout: () => 0);
    }
  }

  static Future<void> reapLeftovers() => registry.reaped;
}

/// A process on a pseudo terminal of macOS or Linux, forked by
/// native/pty/monad_pty.c.
///
/// A helper isolate waits on the terminal and on the process: it sends what
/// the terminal gives, then the exit code, and last that it is done; only
/// then are the descriptors closed, here. Writes do not block: what the
/// terminal does not take yet is tried again shortly.
final class _PosixPty extends Pty {
  _PosixPty._(
    this.pid,
    this._master,
    this._exitFd,
    this._wakeRead,
    this._wakeWrite,
  );

  /// Whether the native library is there (the build hook built it).
  static final bool supported = () {
    try {
      ptyFree(nullptr);
      return true;
    } on ArgumentError {
      return false;
    }
  }();

  /// How long the last output may take after the process exits: node-pty's
  /// wait for its socket to close. A process it left in the background may
  /// keep the terminal open for good.
  static const _flushTimeout = Duration(milliseconds: 200);

  /// How soon a write the terminal did not take is tried again, as node-pty
  /// does.
  static const _writeRetry = Duration(milliseconds: 5);

  static const _chunk = 64 * 1024;

  /// How often a paused helper looks whether it may read again, in ms.
  static const _pausedPoll = 10;

  static Future<Pty> start(
    PtyLaunch launch,
    Map<String, String> environment,
  ) async {
    if (!supported) {
      throw const PtyException(
        'The terminal is missing its native library',
        detail: 'monad_pty was not built.',
      );
    }
    final cwd = launch.workingDirectory;
    final executable = _locate(launch.executable, cwd, environment);
    final memory = _Memory();
    try {
      final out = memory<Int32>(3 * sizeOf<Int32>());
      final pid = ptySpawn(
        memory.string(executable),
        memory.strings([executable, ...launch.arguments]),
        memory.strings([
          for (final MapEntry(:key, :value) in environment.entries)
            '$key=$value',
        ]),
        memory.string(cwd),
        launch.columns.clamp(1, 0xffff),
        launch.rows.clamp(1, 0xffff),
        out,
        out + 1,
        out + 2,
      );
      if (pid < 0) throw _failure(-pid, out[2], executable, cwd);
      final (master, exitFd) = (out[0], out[1]);
      final wake = memory<Int32>(2 * sizeOf<Int32>());
      if (ptyPipe(wake) < 0) {
        ptyKill(pid, master, PtySignal.kill.number);
        for (final fd in [master, exitFd]) {
          if (fd >= 0) ptyClose(fd);
        }
        throw const PtyException('The terminal could not be set up');
      }
      final pty = _PosixPty._(pid, master, exitFd, wake[0], wake[1]);
      await pty._serve();
      return pty;
    } finally {
      memory.free();
    }
  }

  /// [executable] as a path: looked up on the `PATH` when it is a name.
  static String _locate(
    String executable,
    String cwd,
    Map<String, String> environment,
  ) {
    if (executable.contains('/')) {
      return p.isAbsolute(executable) ? executable : p.join(cwd, executable);
    }
    final path = environment['PATH'];
    // execvp's default when there is none.
    for (final dir
        in (path == null || path.isEmpty ? '/usr/bin:/bin' : path).split(':')) {
      final candidate = p.join(p.join(cwd, dir), executable);
      final stat = FileStat.statSync(candidate);
      // Executable by anyone at all; execve tells whether by the user.
      if (stat.type == FileSystemEntityType.file && stat.mode & 0x49 != 0) {
        return candidate;
      }
    }
    throw PtyException(
      '$executable was not found',
      detail: 'It is not on the PATH.',
    );
  }

  static PtyException _failure(
    int error,
    int stage,
    String executable,
    String cwd,
  ) {
    final reason = _cString(ptyDescribe(error));
    return switch (stage) {
      ptyStageDirectory => PtyException(
        'The folder could not be opened',
        detail: '$cwd: $reason',
      ),
      ptyStageExec => PtyException(
        '$executable could not start',
        detail: reason,
      ),
      _ => PtyException('The terminal could not be set up', detail: reason),
    };
  }

  @override
  final int pid;
  final int _master;
  final int _exitFd;
  final int _wakeRead;
  final int _wakeWrite;

  final _port = ReceivePort();
  final _output = StreamController<Uint8List>();
  final _exitCode = Completer<int>();

  /// Set while [pause]d, for the helper to see: native memory, which both
  /// isolates reach. Freed once the helper has ended.
  Pointer<Int32>? _paused = ptyAlloc(sizeOf<Int32>()).cast<Int32>();

  /// What the terminal has not taken yet, and how far into the first.
  final _pending = Queue<Uint8List>();
  int _pendingOffset = 0;
  Timer? _retry;

  int? _code;
  Timer? _flush;
  bool _closed = false;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  Future<void> _serve() async {
    _port.listen(_receive);
    try {
      await Isolate.spawn(_watch, (
        _port.sendPort,
        _master,
        _exitFd,
        _wakeRead,
        pid,
        _paused!.address,
      ), debugName: 'pty $pid');
    } on Object catch (error) {
      ptyKill(pid, _master, PtySignal.kill.number);
      _close();
      _freePaused();
      throw PtyException('The terminal could not be set up', detail: '$error');
    }
  }

  void _receive(Object? message) {
    switch (message) {
      case TransferableTypedData data:
        _output.add(data.materialize().asUint8List());
      case int code:
        _code = code;
        // What is left is read before the flush wakes the helper.
        resume();
        _flush = Timer(_flushTimeout, () => ptyWake(_wakeWrite));
      case null:
        _close();
        _freePaused();
        // Nothing else ends the helper before the process: 0 is for a
        // failure of the wait itself.
        final code = _code ?? 0;
        // The exit code comes once a listener has had the end of the output.
        final closed = _output.close();
        if (_output.hasListener) {
          unawaited(closed.then((_) => _exitCode.complete(code)));
        } else {
          _exitCode.complete(code);
        }
    }
  }

  void _close() {
    _closed = true;
    _flush?.cancel();
    _retry?.cancel();
    _pending.clear();
    _port.close();
    for (final fd in [_master, _exitFd, _wakeRead, _wakeWrite]) {
      if (fd >= 0) ptyClose(fd);
    }
  }

  @override
  void write(Uint8List data) {
    if (_closed || _code != null || data.isEmpty) return;
    _pending.add(Uint8List.fromList(data));
    if (_retry == null) _drain();
  }

  void _drain() {
    _retry = null;
    while (_pending.isNotEmpty && !_closed) {
      final chunk = _pending.first;
      final rest = Uint8List.sublistView(chunk, _pendingOffset);
      final written = ptyWrite(_master, rest.address, rest.length);
      if (written < 0) {
        // The terminal is gone.
        _pending.clear();
        _pendingOffset = 0;
        return;
      }
      if (written == 0) {
        _retry = Timer(_writeRetry, _drain);
        return;
      }
      _pendingOffset += written;
      if (_pendingOffset == chunk.length) {
        _pending.removeFirst();
        _pendingOffset = 0;
      }
    }
  }

  @override
  void resize(int columns, int rows) {
    if (_closed) return;
    ptyResize(_master, columns.clamp(1, 0xffff), rows.clamp(1, 0xffff));
  }

  @override
  void pause() {
    if (!_closed && _code == null) _paused?.value = 1;
  }

  @override
  void resume() => _paused?.value = 0;

  void _freePaused() {
    final paused = _paused;
    _paused = null;
    if (paused != null) ptyFree(paused.cast());
  }

  @override
  void kill([PtySignal signal = PtySignal.hangup]) {
    if (_closed || _code != null) return;
    ptyKill(pid, _master, signal.number);
  }

  /// The helper isolate: reads the terminal until its end, and waits for
  /// the process to exit (or for a wake, which ends it at once). While
  /// paused it looks again every [_pausedPoll] instead of reading.
  static void _watch((SendPort, int, int, int, int, int) setup) {
    final (port, master, exitFd, wake, pid, pausedAddress) = setup;
    final paused = Pointer<Int32>.fromAddress(pausedAddress);
    final buffer = ptyAlloc(_chunk).cast<Uint8>();
    final status = ptyAlloc(sizeOf<Int32>()).cast<Int32>();
    var reading = true;
    var exited = false;
    try {
      while (reading || !exited) {
        final hold = reading && paused.value != 0;
        // Without a descriptor to wait on the exit, the exit is polled.
        final ready = ptyPoll(
          reading && !hold ? master : -1,
          exited ? -1 : exitFd,
          wake,
          hold
              ? _pausedPoll
              : !exited && exitFd < 0
              ? 50
              : -1,
        );
        if (ready < 0 || ready & ptyWoken != 0) break;
        if (ready & ptyOutput != 0) {
          final count = ptyRead(master, buffer, _chunk);
          if (count > 0) {
            port.send(
              TransferableTypedData.fromList([buffer.asTypedList(count)]),
            );
          } else if (count < 0) {
            reading = false;
          }
        }
        if (!exited && (ready & ptyExited != 0 || exitFd < 0)) {
          if (ptyExitStatus(pid, exitFd, status) == 1) {
            exited = true;
            port.send(status.value);
          }
        }
      }
    } finally {
      ptyFree(buffer.cast());
      ptyFree(status.cast());
      port.send(null);
    }
  }
}

/// Native memory for one call, freed together.
final class _Memory {
  final _allocated = <Pointer<Void>>[];

  /// [bytes] of zeroes.
  Pointer<T> call<T extends NativeType>(int bytes) {
    final pointer = ptyAlloc(bytes);
    if (pointer == nullptr) throw const PtyException('Out of memory');
    _allocated.add(pointer);
    return pointer.cast();
  }

  Pointer<Uint8> string(String value) {
    final bytes = utf8.encode(value);
    final pointer = call<Uint8>(bytes.length + 1);
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  /// [values] as a NULL-terminated array.
  Pointer<Pointer<Uint8>> strings(List<String> values) {
    final array = call<Pointer<Uint8>>(
      (values.length + 1) * sizeOf<Pointer<Uint8>>(),
    );
    for (var i = 0; i < values.length; i++) {
      array[i] = string(values[i]);
    }
    return array;
  }

  void free() {
    for (final pointer in _allocated) {
      ptyFree(pointer);
    }
    _allocated.clear();
  }
}

String _cString(Pointer<Uint8> pointer) {
  if (pointer == nullptr) return '';
  var length = 0;
  while (pointer[length] != 0) {
    length++;
  }
  return utf8.decode(pointer.asTypedList(length), allowMalformed: true);
}
