import 'package:bao_pty/bao_pty.dart';

import 'pty_stub.dart' if (dart.library.io) 'pty_io.dart' as platform;
import 'terminal_profiles.dart';
import 'terminal_shell.dart';

export 'package:bao_pty/bao_pty.dart';

/// Starts [launch] on a pseudo terminal ([spawnPty]), recorded so that
/// [reapPtyProcesses] ends it if the app does not; fails with
/// [PtyException] (always on the web).
Future<Pty> startPty(PtyLaunch launch) => platform.PtyProcesses.start(launch);

/// What a new terminal runs in [root]: [shell] (a profile's), else the
/// user's shell, in the environment a terminal gives (see
/// terminal_shell.dart), with VS Code's shell integration injected unless
/// [shellIntegration] is off (its
/// `terminal.integrated.shellIntegration.enabled`; see
/// shell_integration/shell_integration_files.dart); fails with
/// [PtyException] on the web.
Future<PtyLaunch> terminalLaunch(
  String root, {
  int columns = 80,
  int rows = 24,
  bool shellIntegration = true,
  TerminalShell? shell,
}) => platform.PtyProcesses.terminalLaunch(
  root,
  columns: columns,
  rows: rows,
  shellIntegration: shellIntegration,
  shell: shell,
);

/// The terminal profiles of this system, [configured] (the user's
/// `terminal.integrated.profiles.<os>`) over VS Code's defaults, and the
/// shell a terminal starts with none set (see terminal_profiles.dart); none
/// on the web.
Future<TerminalProfiles> terminalProfiles({Object? configured}) =>
    platform.PtyProcesses.terminalProfiles(configured: configured);

/// Hangs up every terminal the app started, and waits for their processes
/// to end: for when the app quits.
Future<void> stopPtyProcesses() => platform.PtyProcesses.stopAll();

/// Ends the terminal processes an earlier run of the app left running;
/// none on the web.
Future<void> reapPtyProcesses() => platform.PtyProcesses.reapLeftovers();
