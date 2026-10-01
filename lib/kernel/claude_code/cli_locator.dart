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

  /// Whether starting it goes through the shell: on Windows the CLI is an
  /// npm `.cmd` shim, which only `cmd.exe` runs.
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
  static List<String> _candidates(Map<String, String> environment) {
    final home = AppPaths.home(environment);
    final path = environment['PATH'] ?? '';
    if (Platform.isWindows) {
      return [
        for (final dir in path.split(';'))
          if (dir.isNotEmpty)
            for (final name in const ['claude.cmd', 'claude.exe', 'claude.bat'])
              p.join(dir, name),
        p.join(environment['APPDATA'] ?? home, 'npm', 'claude.cmd'),
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

  /// Replaces the environment the CLI is found in, and looks again, e.g.
  /// with one set up under test. Null asks the login shell again.
  static void use(Map<String, String>? environment) {
    _located = null;
    ClaudeEnvironment.use(environment);
  }
}
