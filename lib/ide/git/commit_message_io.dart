import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../kernel/claude_code/claude_environment.dart';
import '../../kernel/claude_code/cli_locator.dart';
import 'commit_message.dart';

/// `claude -p --model haiku`: the prompt on stdin, one JSON result on
/// stdout. No tools, MCP servers or slash commands, and no session kept;
/// run outside the project so that its CLAUDE.md is not read.
Future<String> claudeCommitMessage(
  IdeCommitMessagePrompt prompt, {
  Future<void>? cancel,
}) async {
  final cli = await CliLocator.locate();
  final Process process;
  try {
    process = await Process.start(
      cli.executable,
      [
        '-p',
        '--model',
        'haiku',
        '--output-format',
        'json',
        '--no-session-persistence',
        '--strict-mcp-config',
        '--disable-slash-commands',
        // Takes several: the next option ends the list.
        '--tools',
        '',
        '--system-prompt',
        prompt.system,
      ],
      workingDirectory: Directory.systemTemp.path,
      environment: {
        ...cli.environment,
        ...ClaudeEnvironment.stateDirectory(cli.environment),
      },
      includeParentEnvironment: Platform.isWindows,
      runInShell: cli.throughShell,
    );
  } on ProcessException catch (error) {
    throw IdeCommitMessageException(
      'Claude Code could not start: ${error.message}',
    );
  }
  var cancelled = false;
  unawaited(
    cancel?.then((_) {
      cancelled = true;
      process.kill();
    }),
  );
  final stdout = process.stdout.transform(utf8.decoder).join();
  final stderr = process.stderr.transform(utf8.decoder).join();
  process.stdin.add(utf8.encode(prompt.user));
  unawaited(process.stdin.close().catchError((Object _) {}));
  final code = await process.exitCode.timeout(
    const Duration(minutes: 2),
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      throw const IdeCommitMessageException(
        'Generating the commit message took too long.',
      );
    },
  );
  if (cancelled) throw const IdeCommitMessageCancelled();
  final output = await stdout;
  Object? result;
  try {
    result = jsonDecode(output);
  } on FormatException {
    result = null;
  }
  if (result case {'is_error': false, 'result': final String text}
      when text.trim().isNotEmpty) {
    return ideCleanCommitMessage(text);
  }
  final reason = switch (result) {
    {'result': final String text} when text.trim().isNotEmpty => text.trim(),
    _ => (await stderr).trim(),
  };
  throw IdeCommitMessageException(
    reason.isEmpty
        ? 'Claude Code could not generate a commit message (exit $code).'
        : reason,
  );
}
