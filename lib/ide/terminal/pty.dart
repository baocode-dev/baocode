import 'package:bao_pty/bao_pty.dart';

import 'pty_stub.dart' if (dart.library.io) 'pty_io.dart' as platform;
import 'terminal_profiles.dart';
import 'terminal_shell.dart';

export 'package:bao_pty/bao_pty.dart';

/// Starts [launch] on a pseudo terminal ([spawnPty]), recorded so that
/// [reapPtyProcesses] ends it if the app does not; fails with
/// [PtyException] (always on the web).
Future<Pty> startPty(PtyLaunch launch) => platform.PtyProcesses.start(launch);

/// How a terminal changes the environment it starts in, as VS Code's
/// `createTerminalEnvironment` and the extensions' environment variable
/// collections do: [env] over the terminal's environment (a null value
/// removes the variable) or, when [strict], instead of it; then [mutate]
/// (the collections, which a strict environment does not get).
class TerminalEnvironmentRequest {
  const TerminalEnvironmentRequest({
    this.env,
    this.strict = false,
    this.mutate,
  });

  final Map<String, String?>? env;
  final bool strict;
  final void Function(Map<String, String> environment)? mutate;

  /// [base] with [env] over it, or [env] alone when [strict]: before the
  /// terminal's own variables are added.
  Map<String, String> merge(Map<String, String> base) {
    final environment = strict ? <String, String>{} : <String, String>{...base};
    env?.forEach((name, value) {
      if (value != null) {
        environment[name] = value;
      } else {
        environment.remove(name);
      }
    });
    return environment;
  }

  /// [environment], the terminal's, [mutate]d: last, unless [strict].
  Map<String, String> finish(Map<String, String> environment) {
    if (!strict) mutate?.call(environment);
    return environment;
  }
}

/// What a new terminal runs in [root]: [shell] (a profile's), else the
/// user's shell, in the environment a terminal gives (see
/// terminal_shell.dart) changed as [environment] asks, with VS Code's
/// shell integration injected unless [shellIntegration] is off (its
/// `terminal.integrated.shellIntegration.enabled`; see
/// shell_integration/shell_integration_files.dart); fails with
/// [PtyException] on the web.
Future<PtyLaunch> terminalLaunch(
  String root, {
  int columns = 80,
  int rows = 24,
  bool shellIntegration = true,
  TerminalShell? shell,
  TerminalEnvironmentRequest? environment,
}) => platform.PtyProcesses.terminalLaunch(
  root,
  columns: columns,
  rows: rows,
  shellIntegration: shellIntegration,
  shell: shell,
  environment: environment,
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
