import 'dart:convert';

import '../commit_attribution.dart';

/// Claude Code's side of the adapter (the Adaptee): the messages of
/// `claude -p --input-format stream-json --output-format stream-json`, one
/// JSON object per line.
abstract interface class ClaudeCodeTransport {
  /// What the CLI prints: `system`, `stream_event`, `assistant`, `user`,
  /// `result`, `control_request` and `control_response` messages, and last,
  /// when the process ends, a [ClaudeExit.type] message.
  Stream<Map<String, Object?>> get messages;

  /// Writes a `user` message, a `control_request` or a `control_response`
  /// to its stdin.
  void write(Map<String, Object?> message);

  /// Ends the process.
  void close();

  /// Completes once the process is gone, closed or not.
  Future<void> get exited;
}

/// The message a transport ends with: the process is gone.
abstract final class ClaudeExit {
  static const type = 'transport_exit';

  static Map<String, Object?> message(int code, String stderr) => {
    'type': type,
    'code': code,
    'stderr': stderr,
  };
}

/// How to start Claude Code for one session.
class ClaudeLaunch {
  const ClaudeLaunch({
    required this.cwd,
    this.resume,
    this.model,
    this.permissionMode,
    this.effort,
    this.autocompact,
    this.attribution = CommitAttribution.agent,
    this.persist = true,
  });

  final String cwd;

  /// The session id to continue.
  final String? resume;
  final String? model;
  final String? permissionMode;
  final String? effort;

  /// The context the conversation fills before it is compacted; null for
  /// the CLI's own. Only taken at start: `apply_flag_settings` stores it,
  /// but the session goes on with the one it started with.
  final int? autocompact;

  /// Who its commits and pull requests credit, as Claude Code's
  /// `attribution` setting, given as a flag setting (over the user's own);
  /// none for [CommitAttribution.agent], so theirs stands.
  final CommitAttribution attribution;

  /// Whether the session is saved, to be resumed and listed later.
  final bool persist;

  Map<String, String>? get _attribution => switch (attribution) {
    CommitAttribution.baocode => const {
      'commit': CommitAttribution.baoCodeCommit,
      'pr': CommitAttribution.baoCodePullRequest,
    },
    CommitAttribution.agent => null,
    CommitAttribution.none => const {'commit': '', 'pr': ''},
  };

  List<String> get arguments => [
    '-p',
    '--input-format',
    'stream-json',
    '--output-format',
    'stream-json',
    '--verbose',
    '--include-partial-messages',
    '--replay-user-messages',
    '--permission-prompt-tool',
    'stdio',
    '--allow-dangerously-skip-permissions',
    '--thinking-display',
    'summarized',
    // A prompt_suggestion message after each turn.
    '--prompt-suggestions',
    if (permissionMode case final mode?) ...['--permission-mode', mode],
    if (model case final model? when model != 'default') ...['--model', model],
    if (effort case final effort?) ...['--effort', effort],
    if (autocompact case final tokens?) ...['--autocompact', '$tokens'],
    if (resume case final id?) ...['--resume', id],
    if (_attribution case final attribution?) ...[
      '--settings',
      jsonEncode({'attribution': attribution}),
    ],
    if (!persist) '--no-session-persistence',
    '--append-system-prompt',
    citingCode,
  ];

  /// Has the agent cite code as ```` ```12:15:path ```` blocks, which the
  /// chat shows as cards that open the file there (see code_citation.dart).
  static const citingCode = '''
<citing_code>
You MUST use the following format when citing code regions or blocks:

```12:15:app/components/Todo.tsx
// ... existing code ...
```

This is the ONLY acceptable format for code citations. The format is ```startLine:endLine:filepath where startLine and endLine are line numbers.
</citing_code>''';

  /// Lets the host rewind the files a turn changed, and has the CLI say
  /// when it is at work and when idle (`session_state_changed`).
  static const environment = {
    'CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING': '1',
    'CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS': '1',
  };
}

/// Starts Claude Code; throws [ClaudeUnavailable] when it cannot.
typedef ClaudeTransportFactory = Future<ClaudeCodeTransport> Function(
  ClaudeLaunch launch,
);

class ClaudeUnavailable implements Exception {
  const ClaudeUnavailable(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => message;
}
