import 'package:bao_remote/terminal.dart';

import '../pty.dart';

export 'package:bao_remote/terminal.dart'
    show
        ShellIntegrationConfigInjection,
        ShellIntegrationInjectionFailure,
        ShellIntegrationInjectionFailureReason,
        ShellIntegrationInjectionResult,
        generateShellIntegrationNonce,
        getShellIntegrationInjection,
        shellIntegrationApplied;

/// [launch] as TerminalProcess.start runs it after [injection]: the new
/// arguments and the environment mixed in; after a failure, [launch] with
/// only [nonce] added (so a shell's own integration can still use it). A
/// launch without an environment (the app's own) gets just the mixin.
PtyLaunch applyShellIntegrationInjection(
  PtyLaunch launch,
  ShellIntegrationInjectionResult injection, {
  String nonce = '',
}) {
  final (:arguments, :mixin) = shellIntegrationApplied(
    launch.arguments,
    injection,
    nonce: nonce,
  );
  if (identical(arguments, launch.arguments) && mixin.isEmpty) return launch;
  return PtyLaunch(
    executable: launch.executable,
    arguments: arguments,
    workingDirectory: launch.workingDirectory,
    environment: {...?launch.environment, ...mixin},
    columns: launch.columns,
    rows: launch.rows,
  );
}

/// The shell integration nonce [launch] passes its shell (`VSCODE_NONCE`),
/// which the terminal's `ShellIntegration` must be given to trust the
/// command lines and folders the scripts report; empty when there is none.
String shellIntegrationNonce(PtyLaunch launch) =>
    launch.environment?['VSCODE_NONCE'] ?? '';
