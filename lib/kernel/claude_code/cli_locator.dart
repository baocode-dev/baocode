import 'dart:io';

import 'package:path/path.dart' as p;

import '../../platform/app_paths.dart';
import 'claude_code_transport.dart';
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

  static Future<ClaudeCli> locate() => _located ??= _locate().then(
    (cli) => cli,
    onError: (Object error) {
      _located = null; // Look again next time: it may be installed now.
      throw error;
    },
  );

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
    for (final candidate in _candidates(environment)) {
      if (File(candidate).existsSync()) {
        return ClaudeCli(candidate, environment);
      }
    }
    throw ClaudeUnavailable(
      'Claude Code is not installed',
      detail:
          'Install it with `npm install -g @anthropic-ai/claude-code`, '
          'then try again; or set $overrideVariable to the build to run.',
    );
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
  static List<String> _candidates(Map<String, String> environment) {
    final home = AppPaths.home(environment);
    final path = environment['PATH'] ?? '';
    if (Platform.isWindows) {
      final npm = p.join(environment['APPDATA'] ?? home, 'npm');
      return [
        // The native build behind each shim on the PATH, and the npm one
        // where it is not on the PATH itself.
        for (final dir in path.split(';'))
          if (dir.isNotEmpty) _besideShim(p.join(dir, 'claude.cmd')),
        _besideShim(p.join(npm, 'claude.cmd')),
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
  /// stands, and only the shell can run it.
  static String _besideShim(String shim) {
    final exe = _nativePackageExe(
      p.join(p.dirname(shim), 'node_modules', '@anthropic-ai', 'claude-code'),
    );
    return File(exe).existsSync() ? exe : shim;
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
