// One question to Claude Haiku, through Claude Code, for the small jobs
// the app does itself: commit messages, agents' titles.

import 'claude_haiku_stub.dart'
    if (dart.library.io) 'claude_haiku_io.dart'
    as platform;

/// Asks Claude Haiku [prompt], with [system] as its system prompt (one
/// line, so that it passes through a shell unchanged): one turn, no tools,
/// no session kept. Completing [cancel] stops it, and it then throws
/// [ClaudeHaikuCancelled]; it throws [ClaudeHaikuException] when it gets
/// no answer.
Future<String> askClaudeHaiku(
  String system,
  String prompt, {
  Future<void>? cancel,
}) => platform.askClaudeHaiku(system, prompt, cancel: cancel);

class ClaudeHaikuCancelled implements Exception {
  const ClaudeHaikuCancelled();
}

class ClaudeHaikuException implements Exception {
  const ClaudeHaikuException(this.message);

  final String message;

  @override
  String toString() => message;
}
