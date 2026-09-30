/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// VS Code's shell integration scripts on disk, and a terminal's launch with
// them injected: the scripts are written to a folder of this run of the app,
// the files zsh needs copied, and the launch given the arguments and the
// environment getShellIntegrationInjection says.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/terminal/node/terminalProcess.ts (`start`: the files are
// copied and a failure to copy them is swallowed) and
// src/vs/platform/terminal/node/terminalEnvironment.ts (the zsh folder).
//
// VS Code keeps zsh's startup files in `<tmp>/<user>-<app>-zsh`, a fixed
// name it guards with the sticky bit and 0700. Dart cannot chmod, so the
// folder is made like mkdtemp instead (a new name, 0700, the user's own):
// no one else can put scripts in it for a shell to run.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../platform/app_paths.dart';
import '../pty.dart';
import '../terminal_shell.dart';
import 'shell_integration_injection.dart';
import 'shell_integration_scripts.dart';

/// Where the scripts are written: VS Code's scripts folder, with zsh's
/// ZDOTDIR in `zsh/` under it.
class ShellIntegrationFolder {
  /// A folder made under [temp], the system's temp folder by default.
  ShellIntegrationFolder([this._temp]);

  /// The app's.
  static final app = ShellIntegrationFolder();

  final Directory? _temp;
  Directory? _folder;

  /// The folder, with the scripts written in it: made on first use, and made
  /// again should the system have cleaned it away. Throws a
  /// [FileSystemException] when it cannot be made.
  String get path {
    var folder = _folder;
    if (folder == null || !folder.existsSync()) {
      final temp =
          _temp ?? Directory(Directory.systemTemp.resolveSymbolicLinksSync());
      folder = _folder = temp.createTempSync('monad-shell-integration-');
    }
    writeShellIntegrationScripts(folder.path);
    return folder.path;
  }

  /// zsh's ZDOTDIR in [root].
  static String zdotdir(String root) => p.join(root, 'zsh');
}

/// Writes each of VS Code's scripts to [folder] unless it is there already.
void writeShellIntegrationScripts(String folder) {
  for (final MapEntry(key: name, value: script)
      in shellIntegrationScripts.entries) {
    _writeIfChanged(File(p.join(folder, name)), script);
  }
}

/// Copies [files], as VS Code's TerminalProcess.start does before the shell
/// starts: a failure is swallowed, as it can only be that another user's
/// app shares the folder with the same scripts.
void copyShellIntegrationFiles(List<({String source, String dest})> files) {
  for (final file in files) {
    try {
      Directory(p.dirname(file.dest)).createSync(recursive: true);
      _writeIfChanged(File(file.dest), File(file.source).readAsStringSync());
    } on FileSystemException {
      // Swallow error, this should only happen when multiple users are on the
      // same machine.
    }
  }
}

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
  final String root;
  try {
    root = (folder ?? ShellIntegrationFolder.app).path;
  } on FileSystemException {
    return applyShellIntegrationInjection(
      launch,
      const ShellIntegrationInjectionFailure(
        ShellIntegrationInjectionFailureReason.failedToCreateTmpDir,
      ),
      nonce: nonce,
    );
  }
  final injection = getShellIntegrationInjection(
    executable: launch.executable,
    args: launch.arguments,
    nonce: nonce,
    env: launch.environment ?? Platform.environment,
    os: os,
    scriptRoot: root,
    zdotdir: ShellIntegrationFolder.zdotdir(root),
    home: AppPaths.home(Platform.environment),
    windowsBuildNumber: os == TerminalOs.windows
        ? windowsBuildNumber(Platform.operatingSystemVersion)
        : 0,
  );
  if (injection case ShellIntegrationConfigInjection(:final filesToCopy?)) {
    copyShellIntegrationFiles(filesToCopy);
  }
  return applyShellIntegrationInjection(launch, injection, nonce: nonce);
}

/// The build in Dart's description of Windows (`"Windows 10 Pro" 10.0
/// (Build 19045)`); 0 when there is none.
int windowsBuildNumber(String operatingSystemVersion) =>
    int.tryParse(
      RegExp(r'Build (\d+)').firstMatch(operatingSystemVersion)?[1] ??
          RegExp(r'\d+\.\d+\.(\d+)').firstMatch(operatingSystemVersion)?[1] ??
          '',
    ) ??
    0;

/// Writes [content] to [file] unless it has it already: to a file beside it
/// first, then renamed over it, so that a shell reading it meanwhile gets the
/// old or the new file, never half of one.
void _writeIfChanged(File file, String content) {
  try {
    if (file.readAsStringSync() == content) return;
  } on FileSystemException {
    // Missing or unreadable: written below.
  }
  final temporary = File('${file.path}.$pid.tmp');
  temporary.writeAsStringSync(content, flush: true);
  temporary.renameSync(file.path);
}
