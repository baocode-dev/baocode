import 'dart:io';

import 'package:bao_remote/local.dart';

import '../pty.dart';
import 'shell_integration_injection.dart';

export 'package:bao_remote/local.dart'
    show
        ShellIntegrationFolder,
        copyShellIntegrationFiles,
        windowsBuildNumber,
        writeShellIntegrationScripts;

/// [launch] with VS Code's shell integration: the scripts written to
/// [folder] (the app's by default), and the shell given the arguments and
/// environment that load them (see getShellIntegrationInjection), with
/// [nonce] (a new one by default) as `VSCODE_NONCE`. A shell that cannot
/// have it starts as it would have, with only the nonce added.
PtyLaunch injectShellIntegration(
  PtyLaunch launch, {
  required TerminalOs os,
  String? nonce,
  ShellIntegrationFolder? folder,
}) {
  nonce ??= generateShellIntegrationNonce();
  final injection = prepareShellIntegration(
    executable: launch.executable,
    arguments: launch.arguments,
    environment: launch.environment ?? Platform.environment,
    os: os,
    nonce: nonce,
    folder: folder,
  );
  return applyShellIntegrationInjection(launch, injection, nonce: nonce);
}
