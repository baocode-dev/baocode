/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// How a new terminal's shell is made to run VS Code's shell integration
// scripts (shell_integration_scripts.dart) as it starts: the arguments and
// environment that load them, the files zsh needs, or why it cannot be done.
// Pure: the platform, the folders and the environment are passed in.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/terminal/node/terminalEnvironment.ts
// (`getShellIntegrationInjection` and the argument checks) and
// src/vs/platform/terminal/node/terminalProcess.ts (`start`, which applies
// the result).
//
// Unlike VS Code, which ships the scripts in its install folder, the app
// writes them to [scriptRoot] (shell_integration_files.dart), and zsh's
// ZDOTDIR is a folder under it rather than `<tmp>/<user>-<app>-zsh` with the
// sticky bit set. There are no extension environment variable collections,
// so `VSCODE_PATH_PREFIX` is never set. fish's script only runs when
// `TERM_PROGRAM` is `vscode` (it is `monad` here, see terminal_shell.dart):
// its init command says so while it sources the script, then puts it back.

import 'dart:math';

import 'package:path/path.dart' as p;

import '../pty.dart';
import '../terminal_shell.dart';
import 'uuid.dart';

/// Why a shell gets no shell integration, as VS Code's
/// `ShellIntegrationInjectionFailureReason`.
enum ShellIntegrationInjectionFailureReason {
  /// The setting is disabled.
  injectionSettingDisabled,

  /// There is no executable (so there's no way to determine how to inject).
  noExecutable,

  /// It's a feature terminal (tasks, debug), unless it's explicitly being
  /// forced.
  featureTerminal,

  /// The ignoreShellIntegration flag is passed (eg. relaunching without
  /// shell integration).
  ignoreShellIntegrationFlag,

  /// Shell integration doesn't work on older Windows builds that don't
  /// support ConPTY.
  unsupportedWindowsBuild,

  /// We're conservative whether we inject when we don't recognize the
  /// arguments used for the shell as we would prefer launching one without
  /// shell integration than breaking their profile.
  unsupportedArgs,

  /// The shell doesn't have built-in shell integration. Note that this
  /// doesn't mean the shell won't have shell integration in the end.
  unsupportedShell,

  /// For zsh, we failed to set the sticky bit on the shell integration
  /// script folder.
  failedToSetStickyBit,

  /// For zsh, we failed to create a temp directory for the shell
  /// integration script.
  failedToCreateTmpDir,
}

/// What [getShellIntegrationInjection] says.
sealed class ShellIntegrationInjectionResult {
  const ShellIntegrationInjectionResult();
}

/// Upstream `IShellIntegrationConfigInjection` (`type: 'injection'`).
final class ShellIntegrationConfigInjection
    extends ShellIntegrationInjectionResult {
  const ShellIntegrationConfigInjection({
    required this.newArgs,
    this.envMixin,
    this.filesToCopy,
  });

  /// A new set of arguments to use.
  final List<String>? newArgs;

  /// An optional environment to mixin to the real environment.
  final Map<String, String>? envMixin;

  /// An optional array of files to copy from `source` to `dest`.
  final List<({String source, String dest})>? filesToCopy;
}

/// Upstream `IShellIntegrationInjectionFailure` (`type: 'failure'`).
final class ShellIntegrationInjectionFailure
    extends ShellIntegrationInjectionResult {
  const ShellIntegrationInjectionFailure(this.reason);

  final ShellIntegrationInjectionFailureReason reason;
}

/// For a shell [executable] started with [args] (a `String` or a
/// `List<String>`, as upstream's `SingleOrMany<string>`; null for none),
/// returns the arguments to replace them and an environment to mix into
/// [env] (the terminal's) so that it runs VS Code's shell integration, or
/// why it cannot.
///
/// [enabled] is `terminal.integrated.shellIntegration.enabled`; [nonce]
/// the terminal's shell integration nonce (none when empty). [scriptRoot]
/// is the folder with the scripts, [zdotdir] where zsh's startup files are
/// copied to, [home] the user's home folder. [windowsBuildNumber] is read
/// on Windows only; [isStable] is VS Code's `quality === 'stable'`.
ShellIntegrationInjectionResult getShellIntegrationInjection({
  required String executable,
  Object? args,
  bool isFeatureTerminal = false,
  bool forceShellIntegration = false,
  bool ignoreShellIntegration = false,
  bool shellIntegrationEnvironmentReporting = false,
  bool enabled = true,
  String nonce = '',
  bool windowsUseConptyDll = false,
  bool isScreenReaderOptimized = false,
  Map<String, String>? env,
  required TerminalOs os,
  required String scriptRoot,
  required String zdotdir,
  required String home,
  int windowsBuildNumber = 0,
  bool isStable = true,
}) {
  assert(args == null || args is String || args is List<String>);
  // The global setting is disabled
  if (!enabled) {
    return const ShellIntegrationInjectionFailure(
      ShellIntegrationInjectionFailureReason.injectionSettingDisabled,
    );
  }
  // There is no executable (so there's no way to determine how to inject)
  if (executable.isEmpty) {
    return const ShellIntegrationInjectionFailure(
      ShellIntegrationInjectionFailureReason.noExecutable,
    );
  }
  // It's a feature terminal (tasks, debug), unless it's explicitly being
  // forced
  if (isFeatureTerminal && !forceShellIntegration) {
    return const ShellIntegrationInjectionFailure(
      ShellIntegrationInjectionFailureReason.featureTerminal,
    );
  }
  // The ignoreShellIntegration flag is passed (eg. relaunching without shell
  // integration)
  if (ignoreShellIntegration) {
    return const ShellIntegrationInjectionFailure(
      ShellIntegrationInjectionFailureReason.ignoreShellIntegrationFlag,
    );
  }
  final isWindows = os == TerminalOs.windows;
  // Shell integration requires Windows 10 build 18309+ (ConPTY support)
  if (isWindows && windowsBuildNumber < 18309) {
    return const ShellIntegrationInjectionFailure(
      ShellIntegrationInjectionFailureReason.unsupportedWindowsBuild,
    );
  }

  final originalArgs = args;
  final shell = isWindows
      ? p.windows.basename(executable).toLowerCase()
      : p.posix.basename(executable);
  List<String>? newArgs;
  final envMixin = <String, String>{'VSCODE_INJECTION': '1'};

  if (nonce.isNotEmpty) {
    envMixin['VSCODE_NONCE'] = nonce;
  }
  // Temporarily pass list of hardcoded env vars for shell env api
  const scopedDownShellEnvs = ['PATH', 'VIRTUAL_ENV', 'HOME', 'SHELL', 'PWD'];
  if (shellIntegrationEnvironmentReporting) {
    if (isWindows) {
      final enableWindowsEnvReporting =
          windowsUseConptyDll ||
          windowsBuildNumber >= 22631 && shell != 'bash.exe';
      if (enableWindowsEnvReporting) {
        envMixin['VSCODE_SHELL_ENV_REPORTING'] = scopedDownShellEnvs.join(',');
      }
    } else {
      envMixin['VSCODE_SHELL_ENV_REPORTING'] = scopedDownShellEnvs.join(',');
    }
  }
  final stable = isStable ? '1' : '0';

  // Windows
  if (isWindows) {
    if (shell == 'pwsh.exe' || shell == 'powershell.exe') {
      envMixin['VSCODE_A11Y_MODE'] = isScreenReaderOptimized ? '1' : '0';

      if (_isFalsy(originalArgs) || _arePwshImpliedArgs(originalArgs!)) {
        newArgs =
            _shellIntegrationArgs[_ShellIntegrationExecutable.windowsPwsh];
      } else if (_arePwshLoginArgs(originalArgs)) {
        newArgs =
            _shellIntegrationArgs[_ShellIntegrationExecutable.windowsPwshLogin];
      }
      if (newArgs == null) {
        return const ShellIntegrationInjectionFailure(
          ShellIntegrationInjectionFailureReason.unsupportedArgs,
        );
      }
      newArgs = [...newArgs];
      newArgs[newArgs.length - 1] = _format(newArgs.last, [scriptRoot, '']);
      envMixin['VSCODE_STABLE'] = stable;
      return ShellIntegrationConfigInjection(
        newArgs: newArgs,
        envMixin: envMixin,
      );
    } else if (shell == 'bash.exe') {
      if (_isFalsy(originalArgs) || _isEmptyList(originalArgs)) {
        newArgs = _shellIntegrationArgs[_ShellIntegrationExecutable.bash];
      } else if (_areZshBashFishLoginArgs(originalArgs!)) {
        envMixin['VSCODE_SHELL_LOGIN'] = '1';
        newArgs = _shellIntegrationArgs[_ShellIntegrationExecutable.bash];
      }
      if (newArgs == null) {
        return const ShellIntegrationInjectionFailure(
          ShellIntegrationInjectionFailureReason.unsupportedArgs,
        );
      }
      // Shallow clone the array to avoid setting the default array
      newArgs = [...newArgs];
      newArgs[newArgs.length - 1] = _format(newArgs.last, [scriptRoot]);
      envMixin['VSCODE_STABLE'] = stable;
      return ShellIntegrationConfigInjection(
        newArgs: newArgs,
        envMixin: envMixin,
      );
    }
    return const ShellIntegrationInjectionFailure(
      ShellIntegrationInjectionFailureReason.unsupportedShell,
    );
  }

  // Linux & macOS
  switch (shell) {
    case 'bash':
      if (_isFalsy(originalArgs) || _isEmptyList(originalArgs)) {
        newArgs = _shellIntegrationArgs[_ShellIntegrationExecutable.bash];
      } else if (_areZshBashFishLoginArgs(originalArgs!)) {
        envMixin['VSCODE_SHELL_LOGIN'] = '1';
        newArgs = _shellIntegrationArgs[_ShellIntegrationExecutable.bash];
      }
      if (newArgs == null) {
        return const ShellIntegrationInjectionFailure(
          ShellIntegrationInjectionFailureReason.unsupportedArgs,
        );
      }
      // Shallow clone the array to avoid setting the default array
      newArgs = [...newArgs];
      newArgs[newArgs.length - 1] = _format(newArgs.last, [scriptRoot]);
      envMixin['VSCODE_STABLE'] = stable;
      return ShellIntegrationConfigInjection(
        newArgs: newArgs,
        envMixin: envMixin,
      );
    case 'fish':
      if (_isFalsy(originalArgs) || _isEmptyList(originalArgs)) {
        newArgs = _shellIntegrationArgs[_ShellIntegrationExecutable.fish];
      } else if (_areZshBashFishLoginArgs(originalArgs!)) {
        newArgs = _shellIntegrationArgs[_ShellIntegrationExecutable.fishLogin];
      } else if (identical(
            originalArgs,
            _shellIntegrationArgs[_ShellIntegrationExecutable.fish],
          ) ||
          identical(
            originalArgs,
            _shellIntegrationArgs[_ShellIntegrationExecutable.fishLogin],
          )) {
        newArgs = originalArgs as List<String>;
      }
      if (newArgs == null) {
        return const ShellIntegrationInjectionFailure(
          ShellIntegrationInjectionFailureReason.unsupportedArgs,
        );
      }

      // On fish, '$fish_user_paths' is always prepended to the PATH, for both
      // login and non-login shells: VS Code re-applies the prefix of its
      // environment variable collections (none here).

      // Shallow clone the array to avoid setting the default array
      newArgs = [...newArgs];
      newArgs[newArgs.length - 1] = _format(newArgs.last, [scriptRoot]);
      return ShellIntegrationConfigInjection(
        newArgs: newArgs,
        envMixin: envMixin,
      );
    case 'pwsh':
      if (_isFalsy(originalArgs) || _arePwshImpliedArgs(originalArgs!)) {
        newArgs = _shellIntegrationArgs[_ShellIntegrationExecutable.pwsh];
      } else if (_arePwshLoginArgs(originalArgs)) {
        newArgs = _shellIntegrationArgs[_ShellIntegrationExecutable.pwshLogin];
      }
      if (newArgs == null) {
        return const ShellIntegrationInjectionFailure(
          ShellIntegrationInjectionFailureReason.unsupportedArgs,
        );
      }
      // Shallow clone the array to avoid setting the default array
      newArgs = [...newArgs];
      newArgs[newArgs.length - 1] = _format(newArgs.last, [scriptRoot, '']);
      envMixin['VSCODE_STABLE'] = stable;
      return ShellIntegrationConfigInjection(
        newArgs: newArgs,
        envMixin: envMixin,
      );
    case 'zsh':
      if (_isFalsy(originalArgs) || _isEmptyList(originalArgs)) {
        newArgs = _shellIntegrationArgs[_ShellIntegrationExecutable.zsh];
      } else if (_areZshBashFishLoginArgs(originalArgs!)) {
        newArgs = _shellIntegrationArgs[_ShellIntegrationExecutable.zshLogin];
      } else if (identical(
            originalArgs,
            _shellIntegrationArgs[_ShellIntegrationExecutable.zsh],
          ) ||
          identical(
            originalArgs,
            _shellIntegrationArgs[_ShellIntegrationExecutable.zshLogin],
          )) {
        newArgs = originalArgs as List<String>;
      }
      if (newArgs == null) {
        return const ShellIntegrationInjectionFailure(
          ShellIntegrationInjectionFailureReason.unsupportedArgs,
        );
      }
      // Shallow clone the array to avoid setting the default array
      newArgs = [...newArgs];
      newArgs[newArgs.length - 1] = _format(newArgs.last, [scriptRoot]);

      // Move .zshrc into $ZDOTDIR as the way to activate the script
      envMixin['ZDOTDIR'] = zdotdir;
      final userZdotdir = env?['ZDOTDIR'] ?? (home.isEmpty ? '~' : home);
      envMixin['USER_ZDOTDIR'] = userZdotdir;
      return ShellIntegrationConfigInjection(
        newArgs: newArgs,
        envMixin: envMixin,
        filesToCopy: [
          (
            source: p.posix.join(scriptRoot, 'shellIntegration-rc.zsh'),
            dest: p.posix.join(zdotdir, '.zshrc'),
          ),
          (
            source: p.posix.join(scriptRoot, 'shellIntegration-profile.zsh'),
            dest: p.posix.join(zdotdir, '.zprofile'),
          ),
          (
            source: p.posix.join(scriptRoot, 'shellIntegration-env.zsh'),
            dest: p.posix.join(zdotdir, '.zshenv'),
          ),
          (
            source: p.posix.join(scriptRoot, 'shellIntegration-login.zsh'),
            dest: p.posix.join(zdotdir, '.zlogin'),
          ),
        ],
      );
  }
  return const ShellIntegrationInjectionFailure(
    ShellIntegrationInjectionFailureReason.unsupportedShell,
  );
}

/// [launch] as TerminalProcess.start runs it after [injection]: the new
/// arguments and the environment mixed in; after a failure, [launch] with
/// only [nonce] added (so a shell's own integration can still use it). A
/// launch without an environment (the app's own) gets just the mixin.
PtyLaunch applyShellIntegrationInjection(
  PtyLaunch launch,
  ShellIntegrationInjectionResult injection, {
  String nonce = '',
}) {
  final (arguments, mixin) = switch (injection) {
    ShellIntegrationConfigInjection(:final newArgs, :final envMixin) => (
      newArgs ?? launch.arguments,
      envMixin ?? const <String, String>{},
    ),
    ShellIntegrationInjectionFailure() => (
      launch.arguments,
      {if (nonce.isNotEmpty) 'VSCODE_NONCE': nonce},
    ),
  };
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

/// A new nonce, as VS Code's terminal process manager makes one per
/// terminal: a random UUID.
String generateShellIntegrationNonce([Random? random]) => generateUuid(random);

enum _ShellIntegrationExecutable {
  windowsPwsh,
  windowsPwshLogin,
  pwsh,
  pwshLogin,
  zsh,
  zshLogin,
  bash,
  fish,
  fishLogin,
}

/// fish's script only runs where `TERM_PROGRAM` is `vscode`: it is so
/// while the script is sourced.
const _fishSource =
    r'set -g __monad_term_program $TERM_PROGRAM; '
    r'set -gx TERM_PROGRAM vscode; '
    'source "{0}/shellIntegration.fish"; '
    r'set -gx TERM_PROGRAM $__monad_term_program; '
    'set -e __monad_term_program';

const _shellIntegrationArgs = <_ShellIntegrationExecutable, List<String>>{
  // The try catch swallows execution policy errors in the case of the archive
  // distributable
  _ShellIntegrationExecutable.windowsPwsh: [
    '-noexit',
    '-command',
    'try { . "{0}\\shellIntegration.ps1" } catch {}{1}',
  ],
  _ShellIntegrationExecutable.windowsPwshLogin: [
    '-l',
    '-noexit',
    '-command',
    'try { . "{0}\\shellIntegration.ps1" } catch {}{1}',
  ],
  _ShellIntegrationExecutable.pwsh: [
    '-noexit',
    '-command',
    '. "{0}/shellIntegration.ps1"{1}',
  ],
  _ShellIntegrationExecutable.pwshLogin: [
    '-l',
    '-noexit',
    '-command',
    '. "{0}/shellIntegration.ps1"',
  ],
  _ShellIntegrationExecutable.zsh: ['-i'],
  _ShellIntegrationExecutable.zshLogin: ['-il'],
  _ShellIntegrationExecutable.bash: [
    '--init-file',
    '{0}/shellIntegration-bash.sh',
  ],
  _ShellIntegrationExecutable.fish: ['--init-command', _fishSource],
  _ShellIntegrationExecutable.fishLogin: ['-l', '--init-command', _fishSource],
};
const _pwshLoginArgs = ['-login', '-l'];
const _shLoginArgs = ['--login', '-l'];
const _shInteractiveArgs = ['-i', '--interactive'];
const _pwshImpliedArgs = ['-nol', '-nologo'];

/// JavaScript's `!args`: none, or an empty string.
bool _isFalsy(Object? args) => args == null || args == '';

/// `args.length === 0` for an array (a string is handled as upstream does).
bool _isEmptyList(Object? args) => args is List<String> && args.isEmpty;

bool _arePwshLoginArgs(Object originalArgs) {
  if (originalArgs is String) {
    return _pwshLoginArgs.contains(originalArgs.toLowerCase());
  }
  final args = originalArgs as List<String>;
  return args.length == 1 && _pwshLoginArgs.contains(args[0].toLowerCase()) ||
      (args.length == 2 &&
          ((_pwshLoginArgs.contains(args[0].toLowerCase())) ||
              _pwshLoginArgs.contains(args[1].toLowerCase())) &&
          ((_pwshImpliedArgs.contains(args[0].toLowerCase())) ||
              _pwshImpliedArgs.contains(args[1].toLowerCase())));
}

bool _arePwshImpliedArgs(Object originalArgs) {
  if (originalArgs is String) {
    return _pwshImpliedArgs.contains(originalArgs.toLowerCase());
  }
  final args = originalArgs as List<String>;
  return args.isEmpty ||
      args.length == 1 && _pwshImpliedArgs.contains(args[0].toLowerCase());
}

bool _areZshBashFishLoginArgs(Object originalArgs) {
  if (originalArgs is String) {
    return _shLoginArgs.contains(originalArgs.toLowerCase());
  }
  final args = [
    for (final arg in originalArgs as List<String>)
      if (!_shInteractiveArgs.contains(arg.toLowerCase())) arg,
  ];
  return args.length == 1 && _shLoginArgs.contains(args[0].toLowerCase());
}

/// VS Code's `format` (base/common/strings.ts): `{n}` is the n-th of
/// [args], and stays when there is none.
String _format(String value, List<String> args) =>
    value.replaceAllMapped(RegExp(r'{(\d+)}'), (match) {
      final index = int.parse(match[1]!);
      return index < args.length ? args[index] : match[0]!;
    });
