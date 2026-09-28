import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'claude_code_transport.dart';

/// Where the `claude` CLI is, and the environment to run it in.
class ClaudeCli {
  const ClaudeCli(this.executable, this.environment);

  final String executable;
  final Map<String, String> environment;
}

/// Finds `claude` as the user's terminal would. An app opened from the
/// Finder gets a bare PATH, so the login shell is asked for its
/// environment (the commands Claude runs need it too), and the usual
/// install locations are tried after it.
abstract final class CliLocator {
  static Future<ClaudeCli>? _located;

  static Future<ClaudeCli> locate() => _located ??= _locate().then(
    (cli) => cli,
    onError: (Object error) {
      _located = null; // Look again next time: it may be installed now.
      throw error;
    },
  );

  static Future<ClaudeCli> _locate() async {
    final environment = await _loginEnvironment();
    final home = environment['HOME'] ?? Platform.environment['HOME'] ?? '';
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
    throw const ClaudeUnavailable(
      'Claude Code is not installed',
      detail:
          'Install it with `npm install -g @anthropic-ai/claude-code`, '
          'then try again.',
    );
  }

  /// The login shell's environment; the app's own if that fails.
  static Future<Map<String, String>> _loginEnvironment() async {
    final fallback = Map<String, String>.of(Platform.environment);
    final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
    try {
      const marker = '__MONAD_ENV__';
      final result = await Process.run(shell, [
        '-l',
        '-c',
        'echo $marker; env',
      ], stdoutEncoding: utf8).timeout(const Duration(seconds: 8));
      final output = result.stdout as String;
      final start = output.indexOf(marker);
      if (result.exitCode != 0 || start < 0) return fallback;
      final environment = <String, String>{};
      for (final line in const LineSplitter().convert(
        output.substring(start + marker.length),
      )) {
        final equals = line.indexOf('=');
        if (equals > 0) {
          environment[line.substring(0, equals)] = line.substring(equals + 1);
        }
      }
      return environment.containsKey('PATH')
          ? {...fallback, ...environment}
          : fallback;
    } on Object {
      return fallback;
    }
  }
}
