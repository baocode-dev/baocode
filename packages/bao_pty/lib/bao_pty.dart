/// Processes on a pseudo terminal: forkpty on macOS and Linux (a little C,
/// built by hook/build.dart), ConPTY on Windows. None on the web, where
/// [ptySupported] is false and [spawnPty] fails.
library;

export 'src/pty.dart';
