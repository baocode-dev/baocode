import 'dart:convert';

import '../../models/launch_environment.dart';
import '../commit_attribution.dart';

export 'package:bao_remote/claude.dart' show ClaudeUnavailable;

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
    this.thinking,
    this.autocompact,
    this.autoModeDuringPlan,
    this.attribution = CommitAttribution.agent,
    this.persist = true,
    this.env,
    this.settingsPath,
  });

  final String cwd;

  /// The session id to continue.
  final String? resume;
  final String? model;
  final String? permissionMode;
  final String? effort;

  /// Whether the model thinks, as Claude Code's `alwaysThinkingEnabled`
  /// setting: false turns it off; null leaves the user's own.
  final bool? thinking;

  /// The context the conversation fills before it is compacted; null for
  /// the CLI's own. Only taken at start: `apply_flag_settings` stores it,
  /// but the session goes on with the one it started with.
  final int? autocompact;

  /// Whether Plan's commands are left to the auto mode classifier, as
  /// Claude Code's `useAutoModeDuringPlan` setting; null for the user's
  /// own.
  final bool? autoModeDuringPlan;

  /// Who its commits and pull requests credit, as Claude Code's
  /// `attribution` setting, given as a flag setting (over the user's own);
  /// none for [CommitAttribution.agent], so theirs stands.
  final CommitAttribution attribution;

  /// Whether the session is saved, to be resumed and listed later.
  final bool persist;

  /// The environment of a session on a provider of the user's
  /// (`ANTHROPIC_BASE_URL`, its key, its models: see
  /// [launchEnvironment]), as the flag settings' `env`, over the user's
  /// own; null for Claude Code as the user set it up.
  final Map<String, String>? env;

  /// A file the flag settings ([settings]) are written to, given in their
  /// place: so that a key in them is in no command line.
  final String? settingsPath;

  /// Whether [settings] hold a secret: they then go in a file
  /// ([settingsPath]), not the command line.
  bool get hasSecrets => switch (env) {
    final env? => ClaudeModelVariables.secrets.any(
      (name) => env[name]?.isNotEmpty ?? false,
    ),
    null => false,
  };

  /// This launch with its flag settings in the file at [path].
  ClaudeLaunch withSettingsFile(String path) => copyWith(settingsPath: path);

  /// This launch in [cwd], or with [env], or its flag settings in the file
  /// at [settingsPath].
  ClaudeLaunch copyWith({
    String? cwd,
    Map<String, String>? env,
    String? settingsPath,
  }) => ClaudeLaunch(
    cwd: cwd ?? this.cwd,
    resume: resume,
    model: model,
    permissionMode: permissionMode,
    effort: effort,
    thinking: thinking,
    autocompact: autocompact,
    autoModeDuringPlan: autoModeDuringPlan,
    attribution: attribution,
    persist: persist,
    env: env ?? this.env,
    settingsPath: settingsPath ?? this.settingsPath,
  );

  Map<String, String>? get _attribution => switch (attribution) {
    CommitAttribution.baocode => const {
      'commit': CommitAttribution.baoCodeCommit,
      'pr': CommitAttribution.baoCodePullRequest,
    },
    CommitAttribution.agent => null,
    CommitAttribution.none => const {'commit': '', 'pr': ''},
  };

  /// Given as flag settings, over the user's own: one `--settings`.
  Map<String, Object?> get settings => {
    'attribution': ?_attribution,
    'useAutoModeDuringPlan': ?autoModeDuringPlan,
    'alwaysThinkingEnabled': ?thinking,
    if (env case final env? when env.isNotEmpty) 'env': env,
  };

  List<String> get arguments => _arguments(withSettings: true);

  /// [arguments] without the flag settings, for when they are given
  /// another way (written to a file on another machine).
  List<String> get argumentsWithoutSettings => _arguments(withSettings: false);

  List<String> _arguments({required bool withSettings}) => [
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
    if (!withSettings)
      ...const <String>[]
    else if (settingsPath case final path?) ...[
      '--settings',
      path,
    ] else if (settings case final settings when settings.isNotEmpty) ...[
      '--settings',
      jsonEncode(settings),
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
