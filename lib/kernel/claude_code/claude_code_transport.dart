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
  });

  final String cwd;

  /// The session id to continue.
  final String? resume;
  final String? model;
  final String? permissionMode;
  final String? effort;

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
    if (resume case final id?) ...['--resume', id],
  ];

  /// Lets the host rewind the files a turn changed.
  static const environment = {'CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING': '1'};
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
