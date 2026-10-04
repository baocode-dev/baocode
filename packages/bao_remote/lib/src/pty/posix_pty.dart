/// A pseudo terminal on Linux (and macOS) through libc alone: no native
/// library of its own to build, so that the server cross-compiles with
/// `dart compile exe`.
///
/// The child is started by `posix_spawn` (fork and exec happen in libc,
/// never in Dart): a new session (`POSIX_SPAWN_SETSID`) whose stdin, stdout
/// and stderr are the terminal's other end, opened after the session is
/// made so that Linux gives it the terminal as its controlling one. A
/// helper isolate makes the calls that block: reading the output, then
/// waiting for the exit.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Starting the process failed.
class PosixPtyException implements Exception {
  const PosixPtyException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A process on a pseudo terminal.
class PosixPty {
  PosixPty._(this.pid, this._master, this._receive) {
    _receive.listen((message) {
      switch (message) {
        case TransferableTypedData data:
          _output.add(data.materialize().asUint8List());
        case int code:
          _closeMaster();
          unawaited(_output.close());
          _exitCode.complete(code);
          _receive.close();
      }
    });
  }

  /// Starts [executable] (a path, or a name looked up on [environment]'s
  /// `PATH`) with [arguments] in [workingDirectory], on a terminal of
  /// [columns] by [rows].
  static Future<PosixPty> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required Map<String, String> environment,
    int columns = 80,
    int rows = 24,
  }) async {
    final libc = _Libc.instance;
    final path = _resolve(executable, environment['PATH'] ?? '');
    if (path == null) {
      throw PosixPtyException('$executable was not found');
    }
    if (!Directory(workingDirectory).existsSync()) {
      throw PosixPtyException('The folder is gone: $workingDirectory');
    }
    final arena = _Arena();
    var master = -1;
    try {
      master = libc.posixOpenpt(_Constants.oRdwr | _Constants.oNoctty);
      if (master < 0) throw PosixPtyException('posix_openpt: ${libc.errno}');
      if (libc.grantpt(master) != 0 || libc.unlockpt(master) != 0) {
        throw PosixPtyException('grantpt: ${libc.errno}');
      }
      final namePointer = libc.ptsname(master);
      if (namePointer == nullptr) {
        throw PosixPtyException('ptsname: ${libc.errno}');
      }
      final slave = _string(namePointer);
      _resize(master, columns, rows);

      final actions = arena.allocate(512);
      final attributes = arena.allocate(1024);
      libc.fileActionsInit(actions);
      libc.spawnattrInit(attributes);
      final slavePath = arena.string(slave);
      // In the child, after setsid: the terminal becomes its controlling
      // one as it is opened.
      libc.fileActionsAddclose(actions, master);
      libc.fileActionsAddopen(actions, 0, slavePath, _Constants.oRdwr, 0);
      libc.fileActionsAdddup2(actions, 0, 1);
      libc.fileActionsAdddup2(actions, 0, 2);
      var program = path;
      var argv = [path, ...arguments];
      if (libc.fileActionsAddchdir != null) {
        libc.fileActionsAddchdir!(actions, arena.string(workingDirectory));
      } else {
        // No posix_spawn_file_actions_addchdir_np (an old glibc): the shell
        // changes folder, then becomes the program.
        program = '/bin/sh';
        argv = [
          '/bin/sh',
          '-c',
          r'cd "$0" && exec "$@"',
          workingDirectory,
          path,
          ...arguments,
        ];
      }
      // Signals as a new process has them: the server's VM blocks and
      // ignores some.
      final signals = arena.allocate(256);
      libc.sigemptyset(signals);
      libc.spawnattrSetsigmask(attributes, signals);
      final defaults = arena.allocate(256);
      libc.sigfillset(defaults);
      libc.spawnattrSetsigdefault(attributes, defaults);
      libc.spawnattrSetflags(
        attributes,
        _Constants.spawnSetsid |
            _Constants.spawnSetsigmask |
            _Constants.spawnSetsigdef,
      );
      final pidPointer = arena.allocate(8).cast<Int32>();
      final result = libc.posixSpawn(
        pidPointer,
        arena.string(program),
        actions,
        attributes,
        arena.strings(argv),
        arena.strings([
          for (final MapEntry(:key, :value) in environment.entries)
            '$key=$value',
        ]),
      );
      libc.fileActionsDestroy(actions);
      libc.spawnattrDestroy(attributes);
      if (result != 0) {
        throw PosixPtyException('$executable could not start (error $result)');
      }
      final pid = pidPointer.value;
      // macOS keeps no size given before the other end first opened.
      if (Platform.isMacOS) _resize(master, columns, rows);
      final receive = ReceivePort();
      await Isolate.spawn(_watch, (receive.sendPort, master, pid));
      return PosixPty._(pid, master, receive);
    } on Object {
      if (master >= 0) libc.close(master);
      rethrow;
    } finally {
      arena.release();
    }
  }

  final int pid;
  int _master;
  final ReceivePort _receive;
  final StreamController<Uint8List> _output = StreamController();
  final Completer<int> _exitCode = Completer();

  /// What the terminal gives; closes once the process has exited.
  Stream<Uint8List> get output => _output.stream;

  /// The exit code; 128 and the signal for a process a signal ended.
  Future<int> get exitCode => _exitCode.future;

  void write(List<int> data) {
    if (_master < 0 || data.isEmpty) return;
    final libc = _Libc.instance;
    final buffer = libc.malloc(data.length).cast<Uint8>();
    try {
      buffer.asTypedList(data.length).setAll(0, data);
      var written = 0;
      while (written < data.length) {
        final count = libc.write(
          _master,
          (buffer + written).cast(),
          data.length - written,
        );
        if (count < 0) {
          if (libc.errnoValue == _Constants.eintr) continue;
          if (libc.errnoValue == _Constants.eagain) {
            sleep(const Duration(milliseconds: 1));
            continue;
          }
          return;
        }
        written += count;
      }
    } finally {
      libc.free(buffer.cast());
    }
  }

  void resize(int columns, int rows) {
    if (_master >= 0) _resize(_master, columns, rows);
  }

  /// Sends [signal] (a hangup by default) to the process and its group.
  void kill([int signal = 1]) {
    if (_exitCode.isCompleted) return;
    final libc = _Libc.instance;
    // The session's group first (the shell and its jobs), then the process.
    libc.kill(-pid, signal);
    libc.kill(pid, signal);
  }

  void _closeMaster() {
    if (_master < 0) return;
    _Libc.instance.close(_master);
    _master = -1;
  }

  static void _resize(int master, int columns, int rows) {
    final libc = _Libc.instance;
    final size = libc.malloc(8).cast<Uint16>();
    try {
      size[0] = rows;
      size[1] = columns;
      size[2] = 0;
      size[3] = 0;
      libc.ioctl(master, _Constants.tiocswinsz, size.cast());
    } finally {
      libc.free(size.cast());
    }
  }

  static String? _resolve(String executable, String path) {
    if (executable.contains('/')) {
      return File(executable).existsSync() ? executable : null;
    }
    for (final dir in path.split(':')) {
      if (dir.isEmpty) continue;
      final candidate = p.join(dir, executable);
      final stat = FileStat.statSync(candidate);
      if (stat.type == FileSystemEntityType.file && stat.mode & 0x49 != 0) {
        return candidate;
      }
    }
    return null;
  }
}

/// The helper isolate: the output until the terminal closes, then the exit
/// code.
void _watch((SendPort, int, int) arguments) {
  final (port, master, pid) = arguments;
  final libc = _Libc.instance;
  const size = 64 * 1024;
  final buffer = libc.malloc(size).cast<Uint8>();
  try {
    while (true) {
      final count = libc.read(master, buffer.cast(), size);
      if (count > 0) {
        port.send(
          TransferableTypedData.fromList([
            Uint8List.fromList(buffer.asTypedList(count)),
          ]),
        );
        continue;
      }
      if (count < 0 && libc.errnoValue == _Constants.eintr) continue;
      // EIO once every process holding the other end is gone.
      break;
    }
  } finally {
    libc.free(buffer.cast());
  }
  final status = libc.malloc(4).cast<Int32>();
  var code = 0;
  try {
    while (libc.waitpid(pid, status, 0) < 0) {
      if (libc.errnoValue != _Constants.eintr) break;
    }
    final value = status.value;
    final signal = value & 0x7f;
    code = signal == 0 ? (value >> 8) & 0xff : 128 + signal;
  } finally {
    libc.free(status.cast());
  }
  port.send(code);
}

String _string(Pointer<Uint8> pointer) {
  var length = 0;
  while (pointer[length] != 0) {
    length++;
  }
  return String.fromCharCodes(pointer.asTypedList(length));
}

/// Native memory of one call, freed together.
class _Arena {
  final List<Pointer<Void>> _pointers = [];

  Pointer<Void> allocate(int size) {
    final pointer = _Libc.instance.malloc(size);
    for (var i = 0; i < size; i++) {
      pointer.cast<Uint8>()[i] = 0;
    }
    _pointers.add(pointer);
    return pointer;
  }

  Pointer<Uint8> string(String value) {
    final bytes = [...utf8.encode(value), 0];
    final pointer = allocate(bytes.length).cast<Uint8>();
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  Pointer<Pointer<Uint8>> strings(List<String> values) {
    final array = allocate((values.length + 1) * 8).cast<Pointer<Uint8>>();
    for (var i = 0; i < values.length; i++) {
      array[i] = string(values[i]);
    }
    array[values.length] = nullptr;
    return array;
  }

  void release() {
    for (final pointer in _pointers) {
      _Libc.instance.free(pointer);
    }
    _pointers.clear();
  }
}

/// The values of the constants, which Linux and macOS number differently.
abstract final class _Constants {
  static final bool _mac = Platform.isMacOS;
  static const oRdwr = 2;
  static final oNoctty = _mac ? 0x20000 : 0x100;
  static final tiocswinsz = _mac ? 0x80087467 : 0x5414;
  static const spawnSetsigdef = 0x04;
  static const spawnSetsigmask = 0x08;
  static final spawnSetsid = _mac ? 0x0400 : 0x80;
  static const eintr = 4;
  static final eagain = _mac ? 35 : 11;
}

typedef _IntInt = int Function(int);

/// The libc functions, looked up in the process (the VM links libc).
class _Libc {
  _Libc._(DynamicLibrary lib)
    : posixOpenpt = lib.lookupFunction<Int32 Function(Int32), _IntInt>(
        'posix_openpt',
      ),
      grantpt = lib.lookupFunction<Int32 Function(Int32), _IntInt>('grantpt'),
      unlockpt = lib.lookupFunction<Int32 Function(Int32), _IntInt>('unlockpt'),
      ptsname = lib
          .lookupFunction<
            Pointer<Uint8> Function(Int32),
            Pointer<Uint8> Function(int)
          >('ptsname'),
      fileActionsInit = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('posix_spawn_file_actions_init'),
      fileActionsDestroy = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('posix_spawn_file_actions_destroy'),
      fileActionsAddopen = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32, Pointer<Uint8>, Int32, Uint32),
            int Function(Pointer<Void>, int, Pointer<Uint8>, int, int)
          >('posix_spawn_file_actions_addopen'),
      fileActionsAdddup2 = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32, Int32),
            int Function(Pointer<Void>, int, int)
          >('posix_spawn_file_actions_adddup2'),
      fileActionsAddclose = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32),
            int Function(Pointer<Void>, int)
          >('posix_spawn_file_actions_addclose'),
      fileActionsAddchdir =
          lib.providesSymbol('posix_spawn_file_actions_addchdir_np')
          ? lib.lookupFunction<
              Int32 Function(Pointer<Void>, Pointer<Uint8>),
              int Function(Pointer<Void>, Pointer<Uint8>)
            >('posix_spawn_file_actions_addchdir_np')
          : null,
      spawnattrInit = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('posix_spawnattr_init'),
      spawnattrDestroy = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('posix_spawnattr_destroy'),
      spawnattrSetflags = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int16),
            int Function(Pointer<Void>, int)
          >('posix_spawnattr_setflags'),
      spawnattrSetsigmask = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Void>),
            int Function(Pointer<Void>, Pointer<Void>)
          >('posix_spawnattr_setsigmask'),
      spawnattrSetsigdefault = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Void>),
            int Function(Pointer<Void>, Pointer<Void>)
          >('posix_spawnattr_setsigdefault'),
      sigemptyset = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sigemptyset'),
      sigfillset = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sigfillset'),
      posixSpawn = lib
          .lookupFunction<
            Int32 Function(
              Pointer<Int32>,
              Pointer<Uint8>,
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Pointer<Uint8>>,
              Pointer<Pointer<Uint8>>,
            ),
            int Function(
              Pointer<Int32>,
              Pointer<Uint8>,
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Pointer<Uint8>>,
              Pointer<Pointer<Uint8>>,
            )
          >('posix_spawn'),
      read = lib
          .lookupFunction<
            IntPtr Function(Int32, Pointer<Void>, IntPtr),
            int Function(int, Pointer<Void>, int)
          >('read'),
      write = lib
          .lookupFunction<
            IntPtr Function(Int32, Pointer<Void>, IntPtr),
            int Function(int, Pointer<Void>, int)
          >('write'),
      close = lib.lookupFunction<Int32 Function(Int32), _IntInt>('close'),
      ioctl = lib
          .lookupFunction<
            // Variadic: Apple's arm64 passes the third on the stack.
            Int32 Function(Int32, UnsignedLong, VarArgs<(Pointer<Void>,)>),
            int Function(int, int, Pointer<Void>)
          >('ioctl'),
      kill = lib
          .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
            'kill',
          ),
      waitpid = lib
          .lookupFunction<
            Int32 Function(Int32, Pointer<Int32>, Int32),
            int Function(int, Pointer<Int32>, int)
          >('waitpid'),
      malloc = lib
          .lookupFunction<
            Pointer<Void> Function(IntPtr),
            Pointer<Void> Function(int)
          >('malloc'),
      free = lib
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('free'),
      _errnoLocation = lib
          .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
            Platform.isMacOS ? '__error' : '__errno_location',
          );

  static final instance = _Libc._(DynamicLibrary.process());

  final int Function(int) posixOpenpt;
  final int Function(int) grantpt;
  final int Function(int) unlockpt;
  final Pointer<Uint8> Function(int) ptsname;
  final int Function(Pointer<Void>) fileActionsInit;
  final int Function(Pointer<Void>) fileActionsDestroy;
  final int Function(Pointer<Void>, int, Pointer<Uint8>, int, int)
  fileActionsAddopen;
  final int Function(Pointer<Void>, int, int) fileActionsAdddup2;
  final int Function(Pointer<Void>, int) fileActionsAddclose;
  final int Function(Pointer<Void>, Pointer<Uint8>)? fileActionsAddchdir;
  final int Function(Pointer<Void>) spawnattrInit;
  final int Function(Pointer<Void>) spawnattrDestroy;
  final int Function(Pointer<Void>, int) spawnattrSetflags;
  final int Function(Pointer<Void>, Pointer<Void>) spawnattrSetsigmask;
  final int Function(Pointer<Void>, Pointer<Void>) spawnattrSetsigdefault;
  final int Function(Pointer<Void>) sigemptyset;
  final int Function(Pointer<Void>) sigfillset;
  final int Function(
    Pointer<Int32>,
    Pointer<Uint8>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Pointer<Uint8>>,
    Pointer<Pointer<Uint8>>,
  )
  posixSpawn;
  final int Function(int, Pointer<Void>, int) read;
  final int Function(int, Pointer<Void>, int) write;
  final int Function(int) close;
  final int Function(int, int, Pointer<Void>) ioctl;
  final int Function(int, int) kill;
  final int Function(int, Pointer<Int32>, int) waitpid;
  final Pointer<Void> Function(int) malloc;
  final void Function(Pointer<Void>) free;
  final Pointer<Int32> Function() _errnoLocation;

  int get errnoValue => _errnoLocation().value;

  String get errno => 'error $errnoValue';
}
