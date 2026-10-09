import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../platform/app_paths.dart';
import 'claude_unavailable.dart';
import 'claude_environment.dart';

/// Where the `claude` CLI is, and the environment to run it in.
class ClaudeCli {
  const ClaudeCli(this.executable, this.environment);

  final String executable;
  final Map<String, String> environment;

  /// Whether starting it goes through the shell, which only `cmd.exe` runs a
  /// `.cmd` / `.bat` for. Windows runs the native build (see [_candidates]),
  /// so this is its answer elsewhere.
  bool get throughShell =>
      Platform.isWindows &&
      const {'.cmd', '.bat'}.contains(p.extension(executable).toLowerCase());
}

/// Finds the `claude` CLI as the user's terminal would: the build
/// [overrideVariable] names, else the PATH, else the usual install
/// locations.
abstract final class CliLocator {
  /// Names another build to run instead of the installed one, e.g. set in
  /// the user's environment (on macOS, `~/.zshenv`) to try a fork.
  static const overrideVariable = 'BAOCODE_CLAUDE_PATH';

  static Future<ClaudeCli>? _located;

  /// Where to look instead of the usual places, under test: so that a test
  /// of Claude Code not installed never finds the machine's own.
  @visibleForTesting
  static List<String> Function(Map<String, String> environment)?
  candidatesOverride;

  static Future<ClaudeCli> locate() async {
    if (_located case final located?) {
      final cli = await located;
      if (File(cli.executable).existsSync()) return cli;
      // Gone since, removed or uninstalled: looked for again.
      if (identical(_located, located)) _located = null;
    }
    return _located ??= _locate().then(
      (cli) => cli,
      onError: (Object error) {
        _located = null; // Look again next time: it may be installed now.
        throw error;
      },
    );
  }

  /// Looks again next time, the one found having failed to start: what
  /// the user changed since to mend it is then seen on a retry.
  static void forget() => _located = null;

  static Future<ClaudeCli> _locate() async {
    final environment = await ClaudeEnvironment.of();
    if (environment[overrideVariable] case final override?
        when override.isNotEmpty) {
      if (!File(override).existsSync()) {
        throw ClaudeUnavailable(
          'Claude Code is not at $overrideVariable',
          detail:
              '$override does not exist. Unset $overrideVariable to run the '
              'installed Claude Code.',
        );
      }
      return ClaudeCli(override, environment);
    }
    final broken = <String>[];
    for (final candidate in (candidatesOverride ?? _candidates)(environment)) {
      if (!File(candidate).existsSync()) continue;
      if (runnable(candidate)) return ClaudeCli(candidate, environment);
      broken.add(candidate);
    }
    throw ClaudeNotInstalled(
      'Claude Code is not installed',
      detail: [
        if (broken.isNotEmpty)
          'Not a program this machine can run, an install that did not '
              'finish:\n${broken.join('\n')}\n',
        'Install it with `npm install -g @anthropic-ai/claude-code`, '
            'then try again; or set $overrideVariable to the build to run.',
      ].join('\n'),
    );
  }

  /// Whether [path] is a program this machine can run, by its first bytes:
  /// on Windows a PE image (or an npm `.cmd` shim), elsewhere Mach-O, ELF
  /// or a `#!` script.
  ///
  /// The npm package's `bin/claude.exe` is a shell script until its
  /// postinstall puts the native build there: one that never ran leaves
  /// it, which Windows refuses to start (error 216, "%1 is not compatible
  /// with the version of Windows") and passes over for the next. One that
  /// cannot be read is given the benefit of the doubt. [windows] asks as
  /// Windows would, elsewhere too.
  @visibleForTesting
  static bool runnable(String path, {bool? windows}) {
    windows ??= Platform.isWindows;
    if (windows &&
        const {'.cmd', '.bat'}.contains(p.extension(path).toLowerCase())) {
      return true;
    }
    try {
      final file = File(path).openSync();
      try {
        final head = file.readSync(64);
        if (!windows) return _posixProgram(head);
        // MZ, and at the offset it gives, PE\0\0.
        if (head.length < 64 || head[0] != 0x4D || head[1] != 0x5A) {
          return false;
        }
        file.setPositionSync(
          head[0x3C] | head[0x3D] << 8 | head[0x3E] << 16 | head[0x3F] << 24,
        );
        final signature = file.readSync(4);
        return signature.length == 4 &&
            signature[0] == 0x50 &&
            signature[1] == 0x45 &&
            signature[2] == 0 &&
            signature[3] == 0;
      } finally {
        file.closeSync();
      }
    } on FileSystemException {
      return true;
    }
  }

  static bool _posixProgram(List<int> head) {
    if (head.length < 4) return false;
    if (head[0] == 0x23 && head[1] == 0x21) return true; // #!
    if (head[0] == 0x7F && head[1] == 0x45 && head[2] == 0x4C) return true;
    final magic = head[0] << 24 | head[1] << 16 | head[2] << 8 | head[3];
    return const {
      0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE, // Mach-O
      0xCAFEBABE, 0xBEBAFECA, // universal
    }.contains(magic);
  }

  /// Where the CLI usually is: on the PATH first, then where npm and the
  /// installers put it.
  ///
  /// On Windows it is the native `claude.exe`, never the npm `.cmd` shim that
  /// stands beside it. The shim only forwards to that exe, but reaching it
  /// means `cmd.exe`, which parses the arguments as a command line of its own
  /// first: `<` and `>` in them are redirections there, and the `--settings`
  /// JSON carries the angle brackets in BaoCode's own attribution (see
  /// [ClaudeLaunch.arguments]). A shim is only a fallback for a layout
  /// [_besideShim] does not know.
  ///
  /// Volta's shim is an `.exe` of its own, but it too runs the package's
  /// build through `cmd.exe /C`, which takes the newlines and quotes of the
  /// arguments apart and reports the build "not recognized": its package's
  /// build is run instead ([behindVolta]).
  static List<String> _candidates(Map<String, String> environment) {
    final home = AppPaths.home(environment);
    final path = environment['PATH'] ?? '';
    if (Platform.isWindows) {
      final npm = p.join(environment['APPDATA'] ?? home, 'npm');
      return [
        // The native build behind each shim on the PATH, and the npm one
        // where it is not on the PATH itself.
        for (final dir in path.split(';'))
          if (dir.isNotEmpty) ...[
            ?_besideShim(p.join(dir, 'claude.cmd')),
            ?behindVolta(dir, environment),
          ],
        ?_besideShim(p.join(npm, 'claude.cmd')),
        // A native build standing on its own.
        for (final dir in path.split(';'))
          if (dir.isNotEmpty) p.join(dir, 'claude.exe'),
        p.join(npm, 'claude.exe'),
        p.join(
          environment['LOCALAPPDATA'] ?? home,
          'Programs',
          'claude',
          'claude.exe',
        ),
        p.join(home, '.claude', 'local', 'claude.exe'),
        p.join(home, '.local', 'bin', 'claude.exe'),
      ];
    }
    return [
      for (final dir in path.split(':'))
        if (dir.isNotEmpty) '$dir/claude',
      '$home/.claude/local/claude',
      '$home/.local/bin/claude',
      '/opt/homebrew/bin/claude',
      '/usr/local/bin/claude',
    ];
  }

  /// The native build the npm shim at [shim] forwards to, or the shim itself
  /// when it is not where npm puts it (`bin/` of its package): the shim then
  /// stands, and only the shell can run it. Null with no shim there: a
  /// package left behind without one is not an install, and `cmd.exe`,
  /// which looks for the shim, passes over it too.
  static String? _besideShim(String shim) {
    if (!File(shim).existsSync()) return null;
    final exe = _nativePackageExe(
      p.join(p.dirname(shim), 'node_modules', '@anthropic-ai', 'claude-code'),
    );
    return File(exe).existsSync() ? exe : shim;
  }

  /// The native build of the package Volta installed, when [dir] is Volta's
  /// own `bin` (its shims); null otherwise, or with no build there, which
  /// leaves the shim to the PATH's turn.
  @visibleForTesting
  static String? behindVolta(String dir, Map<String, String> environment) {
    final volta = switch (environment['VOLTA_HOME']) {
      final home? when home.isNotEmpty => home,
      _ => p.join(
        environment['LOCALAPPDATA'] ?? AppPaths.home(environment),
        'Volta',
      ),
    };
    if (!p.equals(p.join(volta, 'bin'), dir)) return null;
    final exe = _nativePackageExe(
      p.join(
        volta,
        'tools',
        'image',
        'packages',
        '@anthropic-ai',
        'claude-code',
        'node_modules',
        '@anthropic-ai',
        'claude-code',
      ),
    );
    return File(exe).existsSync() ? exe : null;
  }

  /// Where the npm package puts its native build.
  static String _nativePackageExe(String package) =>
      p.join(package, 'bin', 'claude.exe');

  /// Replaces the environment the CLI is found in, and looks again, e.g.
  /// with one set up under test. Null asks the login shell again.
  static void use(Map<String, String>? environment) {
    _located = null;
    ClaudeEnvironment.use(environment);
  }
}
