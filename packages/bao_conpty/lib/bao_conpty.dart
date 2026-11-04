/// Processes on a Windows pseudo console (ConPTY), by `dart:ffi` alone:
/// no native library, so no build hook, and a program using it compiles
/// with `dart compile exe` (the remote server does). Its types are
/// package:bao_pty's, which starts processes on macOS and Linux too.
library;

export 'src/pty_types.dart';
export 'src/windows_pty.dart' show WindowsPty;
