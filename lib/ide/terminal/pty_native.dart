/// The native half of the pseudo terminal on macOS and Linux:
/// native/pty/monad_pty.c, built by hook/build.dart. The calls that may
/// block are not leaf calls; only a helper isolate makes those.
@DefaultAsset('package:monad/ide/terminal/pty_native.dart')
library;

import 'dart:ffi';

/// What [ptyPoll] found ready.
const ptyOutput = 1, ptyExited = 2, ptyWoken = 4;

/// Where [ptySpawn] failed.
const ptyStageSetup = 0, ptyStageDirectory = 1, ptyStageExec = 2;

@Native<
  Int32 Function(
    Pointer<Uint8>,
    Pointer<Pointer<Uint8>>,
    Pointer<Pointer<Uint8>>,
    Pointer<Uint8>,
    Int32,
    Int32,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Int32>,
  )
>(symbol: 'monad_pty_spawn')
external int ptySpawn(
  Pointer<Uint8> path,
  Pointer<Pointer<Uint8>> argv,
  Pointer<Pointer<Uint8>> envp,
  Pointer<Uint8> cwd,
  int columns,
  int rows,
  Pointer<Int32> master,
  Pointer<Int32> exitFd,
  Pointer<Int32> stage,
);

@Native<Int32 Function(Int32, Int32, Int32, Int32)>(symbol: 'monad_pty_poll')
external int ptyPoll(int master, int exitFd, int wake, int timeout);

@Native<Int32 Function(Int32, Pointer<Uint8>, Int32)>(symbol: 'monad_pty_read')
external int ptyRead(int master, Pointer<Uint8> buffer, int length);

@Native<Int32 Function(Int32, Pointer<Uint8>, Int32)>(
  symbol: 'monad_pty_write',
  isLeaf: true,
)
external int ptyWrite(int master, Pointer<Uint8> data, int length);

@Native<Int32 Function(Int32, Int32, Pointer<Int32>)>(
  symbol: 'monad_pty_exit_status',
)
external int ptyExitStatus(int pid, int exitFd, Pointer<Int32> code);

@Native<Int32 Function(Int32, Int32, Int32)>(
  symbol: 'monad_pty_resize',
  isLeaf: true,
)
external int ptyResize(int master, int columns, int rows);

@Native<Int32 Function(Int32, Int32, Int32)>(
  symbol: 'monad_pty_kill',
  isLeaf: true,
)
external int ptyKill(int pid, int master, int signal);

@Native<Int32 Function(Pointer<Int32>)>(symbol: 'monad_pty_pipe', isLeaf: true)
external int ptyPipe(Pointer<Int32> fds);

@Native<Void Function(Int32)>(symbol: 'monad_pty_wake', isLeaf: true)
external void ptyWake(int fd);

@Native<Void Function(Int32)>(symbol: 'monad_pty_close', isLeaf: true)
external void ptyClose(int fd);

@Native<Pointer<Uint8> Function(Int32)>(
  symbol: 'monad_pty_describe',
  isLeaf: true,
)
external Pointer<Uint8> ptyDescribe(int error);

@Native<Pointer<Void> Function(Size)>(symbol: 'monad_pty_alloc', isLeaf: true)
external Pointer<Void> ptyAlloc(int size);

@Native<Void Function(Pointer<Void>)>(symbol: 'monad_pty_free', isLeaf: true)
external void ptyFree(Pointer<Void> pointer);
