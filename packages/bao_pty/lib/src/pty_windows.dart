import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import 'pty.dart';

/// A process on a Windows pseudo console (ConPTY, Windows 10 1809 and
/// later), run as node-pty's conpty agent runs one, over anonymous pipes.
///
/// No Dart isolate waits in a blocking call: the Dart VM's sampling
/// profiler (on in debug builds) walks such a thread's stack by its frame
/// pointer, which Windows does not keep in system calls, and crashes the
/// app reading a page of the stack not committed (see HANDOFF). So the
/// output is read, and the process's exit seen, by [ConsolePoll] on this
/// isolate; the console is closed on a thread of Windows' own; and a helper
/// isolate writes the input, blocking only while a write waits. The console
/// outlives the process: it is closed once the output has been quiet a
/// while, and closing it ends the output.
final class WindowsPty extends Pty {
  WindowsPty._(
    this.pid,
    this._process,
    this._console,
    this._inputHandle,
    this._outputHandle,
  ) {
    _poll = ConsolePoll(
      available: _available,
      read: _read,
      onOutput: _received,
      onOutputDone: _outputEnded,
      check: _check,
    );
  }

  static bool get supported {
    try {
      return _kernel32.providesSymbol('CreatePseudoConsole');
    } on Object {
      return false;
    }
  }

  /// How long the output must be quiet after the process exits before the
  /// console is closed: node-pty's FLUSH_DATA_INTERVAL.
  static const _flushDelay = Duration(seconds: 1);

  static Future<Pty> start(
    PtyLaunch launch,
    Map<String, String> environment,
  ) async {
    if (!supported) {
      throw const PtyException(
        'Terminals need Windows 10 version 1809 or later',
        detail: 'This Windows has no pseudo console (ConPTY).',
      );
    }
    final cwd = launch.workingDirectory;
    final executable = _locate(launch.executable, cwd, environment);
    final heap = _Heap();
    final opened = <int>[];
    var console = 0;
    try {
      final ends = heap<IntPtr>(4 * sizeOf<IntPtr>());
      if (_createPipe(ends, ends + 1, nullptr, 0) == 0) {
        throw _error('The console could not be set up');
      }
      opened.addAll([ends[0], ends[1]]);
      if (_createPipe(ends + 2, ends + 3, nullptr, 0) == 0) {
        throw _error('The console could not be set up');
      }
      opened.addAll([ends[2], ends[3]]);
      final (inputRead, inputWrite, outputRead, outputWrite) = (
        ends[0],
        ends[1],
        ends[2],
        ends[3],
      );

      final size = heap<_Coord>(sizeOf<_Coord>());
      size.ref
        ..x = launch.columns.clamp(1, 0x7fff)
        ..y = launch.rows.clamp(1, 0x7fff);
      final handle = heap<IntPtr>(sizeOf<IntPtr>());
      final result = _createPseudoConsole(
        size.ref,
        inputRead,
        outputWrite,
        0,
        handle,
      );
      if (result != 0) {
        throw PtyException(
          'The console could not be created',
          detail: 'HRESULT 0x${result.toUnsigned(32).toRadixString(16)}',
        );
      }
      console = handle.value;

      final listSize = heap<IntPtr>(sizeOf<IntPtr>());
      // Asked once for the size it needs, which fails by design.
      _initializeProcThreadAttributeList(nullptr, 1, 0, listSize);
      final list = heap<Void>(listSize.value);
      if (_initializeProcThreadAttributeList(list, 1, 0, listSize) == 0) {
        throw _error('The console could not be set up');
      }
      final int created;
      final int lastError;
      final info = heap<_ProcessInformation>(sizeOf<_ProcessInformation>());
      try {
        if (_updateProcThreadAttribute(
              list,
              0,
              _procThreadAttributePseudoConsole,
              Pointer.fromAddress(console),
              sizeOf<IntPtr>(),
              nullptr,
              nullptr,
            ) ==
            0) {
          throw _error('The console could not be set up');
        }
        final startup = heap<_StartupInfoEx>(sizeOf<_StartupInfoEx>());
        // Null standard handles, so that the child takes the console's and
        // not ones the app may have.
        startup.ref
          ..cb = sizeOf<_StartupInfoEx>()
          ..dwFlags = _startfUseStdHandles
          ..lpAttributeList = list;
        created = _createProcess(
          nullptr,
          heap.utf16(windowsCommandLine(executable, launch.arguments)),
          nullptr,
          nullptr,
          0,
          _extendedStartupInfoPresent | _createUnicodeEnvironment,
          heap.utf16(windowsEnvironmentBlock(environment)).cast(),
          heap.utf16(cwd),
          startup,
          info,
        );
        lastError = _getLastError();
      } finally {
        _deleteProcThreadAttributeList(list);
      }
      // The console holds its own ends of the pipes.
      _closeHandle(inputRead);
      _closeHandle(outputWrite);
      opened.removeWhere((end) => end == inputRead || end == outputWrite);
      if (created == 0) {
        throw PtyException(
          '$executable could not start',
          detail: 'Windows error $lastError',
        );
      }
      _closeHandle(info.ref.hThread);
      final pty = WindowsPty._(
        info.ref.dwProcessId,
        info.ref.hProcess,
        console,
        inputWrite,
        outputRead,
      );
      opened.clear();
      console = 0;
      await pty._serve();
      return pty;
    } finally {
      // After a failure. The output's read end goes first, or closing the
      // console could wait on it.
      for (final end in opened.reversed) {
        _closeHandle(end);
      }
      if (console != 0) _closePseudoConsole(console);
      heap.free();
    }
  }

  /// [executable] as a path, looked up as VS Code's findExecutable does: on
  /// the `PATH` when it is a name, with each of `PATHEXT` first.
  static String _locate(
    String executable,
    String cwd,
    Map<String, String> environment,
  ) {
    final extensions =
        (_lookUp(environment, 'PATHEXT') ?? '.COM;.EXE;.BAT;.CMD')
            .split(';')
            .where((extension) => extension.isNotEmpty);
    String? find(String path) {
      for (final candidate in [
        for (final extension in extensions) '$path$extension',
        path,
      ]) {
        if (File(candidate).existsSync()) return candidate;
      }
      return null;
    }

    if (executable.contains(RegExp(r'[\\/]'))) {
      final path = p.windows.isAbsolute(executable)
          ? executable
          : p.windows.join(cwd, executable);
      return find(path) ?? path;
    }
    for (final dir in (_lookUp(environment, 'PATH') ?? '').split(';')) {
      if (dir.isEmpty) continue;
      if (find(p.windows.join(p.windows.join(cwd, dir), executable))
          case final found?) {
        return found;
      }
    }
    throw PtyException(
      '$executable was not found',
      detail: 'It is not on the PATH.',
    );
  }

  static PtyException _error(String message) =>
      PtyException(message, detail: 'Windows error ${_getLastError()}');

  @override
  final int pid;
  final int _process;
  final int _console;
  final int _inputHandle;
  final int _outputHandle;

  final _output = StreamController<Uint8List>();
  final _exitCode = Completer<int>();
  SendPort? _writer;
  late final ConsolePoll _poll;

  /// The output's buffer and a count, for the calls on this isolate; freed
  /// once all is over.
  final _io = _Heap();
  late final Pointer<Uint8> _buffer = _io<Uint8>(ConsolePoll.chunk);
  late final Pointer<Uint32> _count = _io<Uint32>(sizeOf<Uint32>());

  /// The thread closing the console, 0 when none; and whether the process
  /// is ended once it has.
  int _closer = 0;
  bool _terminate = false;

  int? _code;
  Timer? _flush;
  bool _consoleClosing = false;
  bool _consoleClosed = false;
  bool _outputDone = false;
  bool _finished = false;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  Future<void> _serve() async {
    final writer = ReceivePort();
    await Isolate.spawn(_writeConsole, (
      writer.sendPort,
      _inputHandle,
    ), debugName: 'conpty input');
    _writer = await writer.first as SendPort;
    _poll.start();
  }

  /// The bytes waiting in the output pipe; -1 once it is broken, the console
  /// having closed its end, and empty.
  int _available() =>
      _peekNamedPipe(_outputHandle, nullptr, 0, nullptr, _count, nullptr) == 0
      ? -1
      : _count.value;

  /// [count] bytes that are waiting: the read does not block.
  Uint8List _read(int count) {
    if (_readFile(_outputHandle, _buffer, count, _count, nullptr) == 0) {
      return Uint8List(0);
    }
    return Uint8List.fromList(_buffer.asTypedList(_count.value));
  }

  void _received(Uint8List data) {
    _output.add(data);
    if (_code != null) _closeWhenQuiet();
  }

  void _outputEnded() {
    _closeHandle(_outputHandle);
    _outputDone = true;
    _finish();
  }

  /// Whether the process has exited, or the console closed, since last
  /// looked.
  bool _check() {
    var changed = false;
    if (_code == null && _waitForSingleObject(_process, 0) == _waitObject0) {
      _exited(
        _getExitCodeProcess(_process, _count) == 0
            ? 0
            : _count.value.toSigned(32),
      );
      changed = true;
    }
    final closer = _closer;
    if (closer != 0 && _waitForSingleObject(closer, 0) == _waitObject0) {
      _closer = 0;
      _closeHandle(closer);
      _consoleGone();
      changed = true;
    }
    return changed;
  }

  void _exited(int code) {
    _code = code;
    // What is left is read before the console closes.
    resume();
    _closeWhenQuiet();
    _finish();
  }

  void _closeWhenQuiet() {
    if (_consoleClosing) return;
    _flush?.cancel();
    _flush = Timer(_flushDelay, _close);
  }

  /// Closes the console: what still runs in it gets CTRL_CLOSE_EVENT; with
  /// [terminate], the process is ended too, as node-pty's kill does.
  ///
  /// ClosePseudoConsole waits for the console to go (up to seconds before
  /// Windows 11 24H2), so it runs as the start routine of a thread of its
  /// own, not a Dart isolate's (see [ConsolePoll]): it takes one
  /// pointer-sized argument as one does, and what it leaves in the return
  /// register is the thread's exit code, unused.
  void _close({bool terminate = false}) {
    if (_consoleClosing) return;
    _consoleClosing = true;
    _terminate = terminate;
    resume();
    _flush?.cancel();
    _closer = _createThread(
      nullptr,
      0,
      _closePseudoConsoleRoutine,
      Pointer.fromAddress(_console),
      0,
      nullptr,
    );
    if (_closer == 0) {
      final console = _console;
      unawaited(
        Isolate.run(() => _closePseudoConsole(console)).then((_) {
          if (!_finished) _consoleGone();
        }),
      );
    }
    _poll.hurry();
  }

  void _consoleGone() {
    if (_terminate) _terminateProcess(_process, 1);
    _consoleClosed = true;
    _finish();
  }

  void _finish() {
    final code = _code;
    if (!_outputDone || !_consoleClosed || code == null || _finished) return;
    _finished = true;
    _poll.stop();
    _io.free();
    _writer?.send(null);
    _writer = null;
    _closeHandle(_process);
    // The exit code comes once a listener has had the end of the output.
    final closed = _output.close();
    if (_output.hasListener) {
      unawaited(closed.then((_) => _exitCode.complete(code)));
    } else {
      _exitCode.complete(code);
    }
  }

  @override
  void write(Uint8List data) {
    if (_code != null || _consoleClosing || data.isEmpty) return;
    _writer?.send(data);
    // Its echo is on the way.
    _poll.hurry();
  }

  @override
  void resize(int columns, int rows) {
    if (_consoleClosing) return;
    final heap = _Heap();
    try {
      final size = heap<_Coord>(sizeOf<_Coord>());
      size.ref
        ..x = columns.clamp(1, 0x7fff)
        ..y = rows.clamp(1, 0x7fff);
      _resizePseudoConsole(_console, size.ref);
    } finally {
      heap.free();
    }
  }

  @override
  void kill([PtySignal signal = PtySignal.hangup]) {
    if (_code != null) return;
    _close(terminate: true);
  }

  @override
  void pause() {
    if (_code == null && !_consoleClosing) _poll.pause();
  }

  @override
  void resume() => _poll.resume();
}

/// Reads a console's output, and looks at what else is watched (the
/// process's exit, the console's closing), from the isolate that runs it:
/// by polling, so that no isolate waits in a blocking call (see
/// [WindowsPty]). Looks again at once while output floods in, soon after it
/// came or input was sent, and less and less often, up to [slowest], while
/// all is quiet. Paused (flow control), it reads nothing: the pipe fills,
/// then the console and the process wait.
@visibleForTesting
final class ConsolePoll {
  ConsolePoll({
    required this.available,
    required this.read,
    required this.onOutput,
    required this.onOutputDone,
    required this.check,
  });

  /// The bytes waiting in the output pipe; negative once it has ended.
  final int Function() available;

  /// Reads that many bytes, which are waiting.
  final Uint8List Function(int count) read;

  final void Function(Uint8List data) onOutput;
  final void Function() onOutputDone;

  /// Looks at what else is watched; returns whether anything happened.
  final bool Function() check;

  /// The most read at a time, and in one turn of the event loop: a flood
  /// leaves the app its turns.
  static const chunk = 64 * 1024;
  static const budget = 4 * chunk;

  static const fastest = Duration(milliseconds: 1);
  static const slowest = Duration(milliseconds: 32);

  Timer? _timer;
  Duration _interval = fastest;
  bool _ticking = false;
  bool _paused = false;
  bool _outputDone = false;
  bool _stopped = false;

  void start() => _schedule(Duration.zero);

  void pause() => _paused = true;

  void resume() {
    if (!_paused) return;
    _paused = false;
    hurry();
  }

  /// Looks again soon, something being expected.
  void hurry() {
    _interval = fastest;
    if (!_ticking && !_stopped) _schedule(fastest);
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, _tick);
  }

  void _tick() {
    _timer = null;
    _ticking = true;
    var busy = false;
    var total = 0;
    try {
      busy = check();
      while (!_stopped && !_paused && !_outputDone && total < budget) {
        final count = available();
        if (count < 0) {
          _outputDone = true;
          busy = true;
          onOutputDone();
          break;
        }
        if (count == 0) break;
        final data = read(math.min(count, chunk));
        if (data.isEmpty) break;
        total += data.length;
        onOutput(data);
      }
    } finally {
      _ticking = false;
    }
    if (_stopped) return;
    if (total >= budget && !_paused) {
      _schedule(Duration.zero);
      return;
    }
    final slower = _interval * 2;
    _interval = busy || total > 0
        ? fastest
        : slower > slowest
        ? slowest
        : slower;
    _schedule(_interval);
  }
}

/// The command line for [executable] and [arguments], quoted for the C
/// runtime's parsing as node-pty's argsToCommandLine quotes it.
@visibleForTesting
String windowsCommandLine(String executable, List<String> arguments) {
  final line = StringBuffer();
  final argv = [executable, ...arguments];
  for (var i = 0; i < argv.length; i++) {
    if (i > 0) line.write(' ');
    final argument = argv[i];
    // Quoted when empty, or when it has blanks and is not quoted already.
    final quoted = argument.startsWith('"') && argument.endsWith('"');
    final quote =
        argument.isEmpty ||
        (argument.contains(' ') || argument.contains('\t')) &&
            argument.length > 1 &&
            !quoted;
    if (quote) line.write('"');
    var backslashes = 0;
    for (final character in argument.split('')) {
      if (character == r'\') {
        backslashes++;
      } else if (character == '"') {
        line
          ..write(r'\' * (backslashes * 2 + 1))
          ..write('"');
        backslashes = 0;
      } else {
        line
          ..write(r'\' * backslashes)
          ..write(character);
        backslashes = 0;
      }
    }
    line.write(r'\' * (quote ? backslashes * 2 : backslashes));
    if (quote) line.write('"');
  }
  return line.toString();
}

/// [environment] as CreateProcessW takes it: `name=value` strings, each
/// ended by a NUL, sorted by name whatever the case, then a NUL.
@visibleForTesting
String windowsEnvironmentBlock(Map<String, String> environment) {
  final names = environment.keys.toList()
    ..sort((a, b) => a.toUpperCase().compareTo(b.toUpperCase()));
  return '${[for (final name in names) '$name=${environment[name]}\u0000'].join()}\u0000';
}

String? _lookUp(Map<String, String> environment, String name) {
  if (environment[name] case final value?) return value;
  final upper = name.toUpperCase();
  for (final MapEntry(:key, :value) in environment.entries) {
    if (key.toUpperCase() == upper) return value;
  }
  return null;
}

/// The input isolate: writes what it is sent, in order, until sent null.
void _writeConsole((SendPort, int) setup) {
  final (reply, handle) = setup;
  final port = ReceivePort();
  reply.send(port.sendPort);
  var broken = false;
  port.listen((message) {
    if (message is Uint8List) {
      if (!broken) broken = !_writeAll(handle, message);
      return;
    }
    _closeHandle(handle);
    port.close();
  });
}

bool _writeAll(int handle, Uint8List data) {
  final heap = _Heap();
  try {
    final buffer = heap<Uint8>(data.length);
    buffer.asTypedList(data.length).setAll(0, data);
    final written = heap<Uint32>(sizeOf<Uint32>());
    var offset = 0;
    while (offset < data.length) {
      final ok = _writeFile(
        handle,
        buffer + offset,
        data.length - offset,
        written,
        nullptr,
      );
      if (ok == 0) return false;
      offset += written.value;
    }
    return true;
  } finally {
    heap.free();
  }
}

/// Native memory for one call, freed together.
final class _Heap {
  final _allocated = <Pointer<Void>>[];

  /// [bytes] of zeroes.
  Pointer<T> call<T extends NativeType>(int bytes) {
    final pointer = _heapAlloc(_getProcessHeap(), _heapZeroMemory, bytes);
    if (pointer == nullptr) throw const PtyException('Out of memory');
    _allocated.add(pointer);
    return pointer.cast();
  }

  /// [value] in UTF-16, NUL-terminated.
  Pointer<Uint16> utf16(String value) {
    final units = value.codeUnits;
    final pointer = call<Uint16>((units.length + 1) * sizeOf<Uint16>());
    pointer.asTypedList(units.length).setAll(0, units);
    return pointer;
  }

  void free() {
    final heap = _getProcessHeap();
    for (final pointer in _allocated) {
      _heapFree(heap, 0, pointer);
    }
    _allocated.clear();
  }
}

// kernel32, by hand: handles are pointer-sized integers, BOOL an Int32.

const _waitObject0 = 0;
const _heapZeroMemory = 0x00000008;
const _startfUseStdHandles = 0x00000100;
const _extendedStartupInfoPresent = 0x00080000;
const _createUnicodeEnvironment = 0x00000400;
const _procThreadAttributePseudoConsole = 0x00020016;

final class _Coord extends Struct {
  @Int16()
  external int x;

  @Int16()
  external int y;
}

final class _StartupInfoEx extends Struct {
  @Uint32()
  external int cb;

  external Pointer<Uint16> lpReserved;
  external Pointer<Uint16> lpDesktop;
  external Pointer<Uint16> lpTitle;

  @Uint32()
  external int dwX;

  @Uint32()
  external int dwY;

  @Uint32()
  external int dwXSize;

  @Uint32()
  external int dwYSize;

  @Uint32()
  external int dwXCountChars;

  @Uint32()
  external int dwYCountChars;

  @Uint32()
  external int dwFillAttribute;

  @Uint32()
  external int dwFlags;

  @Uint16()
  external int wShowWindow;

  @Uint16()
  external int cbReserved2;

  external Pointer<Uint8> lpReserved2;

  @IntPtr()
  external int hStdInput;

  @IntPtr()
  external int hStdOutput;

  @IntPtr()
  external int hStdError;

  external Pointer<Void> lpAttributeList;
}

final class _ProcessInformation extends Struct {
  @IntPtr()
  external int hProcess;

  @IntPtr()
  external int hThread;

  @Uint32()
  external int dwProcessId;

  @Uint32()
  external int dwThreadId;
}

final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _createPipe = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<Void>, Uint32),
      int Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<Void>, int)
    >('CreatePipe', isLeaf: true);

final _createPseudoConsole = _kernel32
    .lookupFunction<
      Int32 Function(_Coord, IntPtr, IntPtr, Uint32, Pointer<IntPtr>),
      int Function(_Coord, int, int, int, Pointer<IntPtr>)
    >('CreatePseudoConsole');

final _resizePseudoConsole = _kernel32
    .lookupFunction<Int32 Function(IntPtr, _Coord), int Function(int, _Coord)>(
      'ResizePseudoConsole',
      isLeaf: true,
    );

final _closePseudoConsole = _kernel32
    .lookupFunction<Void Function(IntPtr), void Function(int)>(
      'ClosePseudoConsole',
    );

/// ClosePseudoConsole, as a thread's start routine (see
/// [WindowsPty._close]).
final _closePseudoConsoleRoutine = _kernel32
    .lookup<NativeFunction<Uint32 Function(Pointer<Void>)>>(
      'ClosePseudoConsole',
    );

final _createThread = _kernel32
    .lookupFunction<
      IntPtr Function(
        Pointer<Void>,
        IntPtr,
        Pointer<NativeFunction<Uint32 Function(Pointer<Void>)>>,
        Pointer<Void>,
        Uint32,
        Pointer<Uint32>,
      ),
      int Function(
        Pointer<Void>,
        int,
        Pointer<NativeFunction<Uint32 Function(Pointer<Void>)>>,
        Pointer<Void>,
        int,
        Pointer<Uint32>,
      )
    >('CreateThread');

final _initializeProcThreadAttributeList = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Uint32, Pointer<IntPtr>),
      int Function(Pointer<Void>, int, int, Pointer<IntPtr>)
    >('InitializeProcThreadAttributeList', isLeaf: true);

final _updateProcThreadAttribute = _kernel32
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Uint32,
        IntPtr,
        Pointer<Void>,
        IntPtr,
        Pointer<Void>,
        Pointer<IntPtr>,
      ),
      int Function(
        Pointer<Void>,
        int,
        int,
        Pointer<Void>,
        int,
        Pointer<Void>,
        Pointer<IntPtr>,
      )
    >('UpdateProcThreadAttribute', isLeaf: true);

final _deleteProcThreadAttributeList = _kernel32
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'DeleteProcThreadAttributeList',
      isLeaf: true,
    );

final _createProcess = _kernel32
    .lookupFunction<
      Int32 Function(
        Pointer<Uint16>,
        Pointer<Uint16>,
        Pointer<Void>,
        Pointer<Void>,
        Int32,
        Uint32,
        Pointer<Void>,
        Pointer<Uint16>,
        Pointer<_StartupInfoEx>,
        Pointer<_ProcessInformation>,
      ),
      int Function(
        Pointer<Uint16>,
        Pointer<Uint16>,
        Pointer<Void>,
        Pointer<Void>,
        int,
        int,
        Pointer<Void>,
        Pointer<Uint16>,
        Pointer<_StartupInfoEx>,
        Pointer<_ProcessInformation>,
      )
    >('CreateProcessW');

final _readFile = _kernel32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint32>,
        Pointer<Void>,
      ),
      int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
    >('ReadFile');

final _peekNamedPipe = _kernel32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Void>,
        Uint32,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Uint32>,
      ),
      int Function(
        int,
        Pointer<Void>,
        int,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Uint32>,
      )
    >('PeekNamedPipe', isLeaf: true);

final _writeFile = _kernel32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint32>,
        Pointer<Void>,
      ),
      int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
    >('WriteFile');

final _waitForSingleObject = _kernel32
    .lookupFunction<Uint32 Function(IntPtr, Uint32), int Function(int, int)>(
      'WaitForSingleObject',
    );

final _getExitCodeProcess = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)
    >('GetExitCodeProcess', isLeaf: true);

final _terminateProcess = _kernel32
    .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
      'TerminateProcess',
      isLeaf: true,
    );

final _closeHandle = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'CloseHandle',
      isLeaf: true,
    );

final _getLastError = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>(
      'GetLastError',
      isLeaf: true,
    );

final _getProcessHeap = _kernel32
    .lookupFunction<IntPtr Function(), int Function()>(
      'GetProcessHeap',
      isLeaf: true,
    );

final _heapAlloc = _kernel32
    .lookupFunction<
      Pointer<Void> Function(IntPtr, Uint32, IntPtr),
      Pointer<Void> Function(int, int, int)
    >('HeapAlloc', isLeaf: true);

final _heapFree = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<Void>),
      int Function(int, int, Pointer<Void>)
    >('HeapFree', isLeaf: true);
