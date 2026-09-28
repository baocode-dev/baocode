import 'dart:io';

import 'claude_code_transport.dart';
import 'claude_environment.dart';

/// Where the `claude` CLI is, and the environment to run it in.
class ClaudeCli {
  const ClaudeCli(this.executable, this.environment);

  final String executable;
  final Map<String, String> environment;
}

/// Finds the `claude` CLI as the user's terminal would: the build
/// [overrideVariable] names, else the login shell's PATH, else the usual
/// install locations.
abstract final class CliLocator {
  /// Names another build to run instead of the installed one, e.g. set in
  /// `~/.zshenv` to try a fork.
  static const overrideVariable = 'MONAD_CLAUDE_PATH';

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
              '$override does not exist. Unset $overrideVariable (in '
              '~/.zshenv) to run the installed Claude Code.',
        );
      }
      return ClaudeCli(override, environment);
    }
    final home = environment['HOME'] ?? '';
    final path = environment['PATH'] ?? '';
    final candidates = [
      for (final dir in path.split(':'))
        if (dir.isNotEmpty) '$dir/claude',
      '$home/.claude/local/claude',
      '$home/.local/bin/claude',
      '/opt/homebrew/bin/claude',
      '/usr/local/bin/claude',
    ];
    for (final candidate in candidates) {
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

  /// Replaces the environment the CLI is found in, and looks again, e.g.
  /// with one set up under test. Null asks the login shell again.
  static void use(Map<String, String>? environment) {
    _located = null;
    ClaudeEnvironment.use(environment);
  }
}
