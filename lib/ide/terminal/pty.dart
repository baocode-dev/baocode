import 'dart:convert';
import 'dart:typed_data';

import 'pty_stub.dart' if (dart.library.io) 'pty_io.dart' as platform;

/// Whether processes can run on a pseudo terminal here: on the desktop, not
/// in the browser.
bool get ptySupported => platform.PtyProcesses.supported;

/// How to start a process on a pseudo terminal.
class PtyLaunch {
  const PtyLaunch({
    required this.executable,
    this.arguments = const [],
    required this.workingDirectory,
    this.environment,
    this.columns = 80,
    this.rows = 24,
  });

  /// A path, or a name looked up on the `PATH` of [environment].
  final String executable;
  final List<String> arguments;
  final String workingDirectory;

  /// The whole environment of the process; the app's own when null.
  final Map<String, String>? environment;
  final int columns;
  final int rows;
}

/// A signal for [Pty.kill]; its number is the same on macOS and Linux.
/// Windows has no signals: any of them ends the process.
enum PtySignal {
  hangup(1),
  interrupt(2),
  quit(3),
  kill(9),
  terminate(15);

  const PtySignal(this.number);

  final int number;
}

/// A process on a pseudo terminal: what it prints comes out of [output],
/// what the user types goes in by [write].
abstract class Pty {
  int get pid;

  /// The bytes the terminal gives, as the process printed them through the
  /// terminal's line discipline. Closes once the process has exited and its
  /// last output is read.
  Stream<Uint8List> get output;

  /// Sends [data] to the process as typed input; nothing once it exited.
  void write(Uint8List data);

  /// [write]s [text] in UTF-8.
  void writeText(String text) => write(utf8.encode(text));

  /// Resizes the terminal; the process is told (SIGWINCH).
  void resize(int columns, int rows);

  /// Sends [signal] to the process, its process group and the job in the
  /// terminal's foreground: the hangup a closing terminal gives, by default.
  /// On Windows, closes the console and ends the process.
  void kill([PtySignal signal = PtySignal.hangup]);

  /// The exit code, once the process has exited and [output] is closed;
  /// minus the signal number when a signal ended it.
  Future<int> get exitCode;
}

typedef PtyStarter = Future<Pty> Function(PtyLaunch launch);

/// Starts [launch] on a pseudo terminal, recorded so that
/// [reapPtyProcesses] ends it if the app does not; fails with
/// [PtyException] (always on the web).
Future<Pty> startPty(PtyLaunch launch) => platform.PtyProcesses.start(launch);

/// What a new terminal runs in [root]: the user's shell, in the
/// environment a terminal gives (see terminal_shell.dart); fails with
/// [PtyException] on the web.
Future<PtyLaunch> terminalLaunch(
  String root, {
  int columns = 80,
  int rows = 24,
}) => platform.PtyProcesses.terminalLaunch(root, columns: columns, rows: rows);

/// Hangs up every terminal the app started, and waits for their processes
/// to end: for when the app quits.
Future<void> stopPtyProcesses() => platform.PtyProcesses.stopAll();

/// Ends the terminal processes an earlier run of the app left running;
/// none on the web.
Future<void> reapPtyProcesses() => platform.PtyProcesses.reapLeftovers();

class PtyException implements Exception {
  const PtyException(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message: $detail';
}
