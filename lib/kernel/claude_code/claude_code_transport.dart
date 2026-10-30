import 'dart:convert';

import '../../models/launch_environment.dart';
import '../commit_attribution.dart';
import '../extension_switches.dart';

export 'package:bao_remote/claude.dart'
    show ClaudeFolderGone, ClaudeNoModel, ClaudeUnavailable;

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

  /// [executable] is the CLI run, where the transport knows it.
  static Map<String, Object?> message(
    int code,
    String stderr, {
    String? executable,
  }) => {
    'type': type,
    'code': code,
    'stderr': stderr,
    'executable': ?executable,
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
    this.directories = const [],
    this.folderInstructions = true,
    this.readable = const [],
    this.instructions,
    this.ownPrompt = false,
    this.models = const [],
    this.sdkServers = const [],
    this.tools,
    this.allowed = const [],
    this.promptSuggestions = true,
    this.switches = ExtensionSwitches.none,
  });

  /// The skills, MCP servers and tools turned off (Settings → Customize):
  /// permission rules and `skillOverrides` of the flag settings.
  final ExtensionSwitches switches;

  /// Whether it suggests the next prompt after each turn
  /// (`--prompt-suggestions`), each a request of its own.
  final bool promptSuggestions;

  /// Folders it may read without asking, its tools' work outside them
  /// aside: where the long pastes it is told of are kept (PasteStore).
  final List<String> readable;

  final String cwd;

  /// The app's own MCP servers (see claude_sdk_tools.dart), their tools
  /// allowed without asking: they only do what the app does.
  final List<String> sdkServers;

  /// The only built-in tools it has (`--tools`; none for an empty list),
  /// [sdkServers]' tools aside; all when null. Set, [sdkServers] are its
  /// only MCP servers too (`--strict-mcp-config`): not the user's own,
  /// configured for Claude Code.
  final List<String>? tools;

  /// Built-in tools it uses without asking (permission rules: `WebFetch`,
  /// say), as the flag settings allow them.
  final List<String> allowed;

  /// Folders it works in besides [cwd] (a multi-folder workspace's): each
  /// an `--add-dir`, their `CLAUDE.md` read as [cwd]'s is.
  final List<String> directories;

  /// Whether the `CLAUDE.md` of [directories] is read; not for those it
  /// only reaches into (a bot's, the user's projects).
  final bool folderInstructions;

  /// Told the agent after [appendedSystemPrompt] (what the workspace it
  /// works in is); none when null.
  final String? instructions;

  /// Whether [instructions] are all its system prompt (`--system-prompt`),
  /// in place of Claude Code's own and [appendedSystemPrompt]: an agent
  /// that does not code (a bot's).
  final bool ownPrompt;

  /// The session id to continue.
  final String? resume;
  final String? model;

  /// The models it may be switched to (`set_model`) without Claude Code
  /// first sending each a request of its own, to see that it is one: a
  /// provider's, as `modelPicker` rows, which it takes as known.
  final List<String> models;
  final String? permissionMode;
  final String? effort;

  /// Whether the model thinks, as Claude Code's `alwaysThinkingEnabled`
  /// setting: false turns it off; null leaves the user's own.
  final bool? thinking;

  /// The context the conversation fills before it is compacted; null for
  /// the CLI's own. Only taken at start: `apply_flag_settings` stores it,
  /// but the session goes on with the one it started with.
  final int? autocompact;

  /// The most `--autocompact` takes (a decimal million): a window larger
  /// still (a model of 1,048,576 tokens, say) is passed as this.
  static const maxAutocompact = 1000000;

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
    directories: directories,
    folderInstructions: folderInstructions,
    readable: readable,
    instructions: instructions,
    ownPrompt: ownPrompt,
    models: models,
    sdkServers: sdkServers,
    tools: tools,
    allowed: allowed,
    promptSuggestions: promptSuggestions,
    switches: switches,
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
    if (models.isNotEmpty) ...{
      'modelPicker': {
        'options': [
          for (final model in models) {'model': model},
        ],
      },
      'availableModels': allowlist,
    },
    ...switchSettings(switches),
    'env': {
      ...unsetEnvironment,
      ...?env,
      if (directories.isNotEmpty && folderInstructions)
        ...additionalDirectoriesEnvironment,
    },
  };

  /// The flag settings' `permissions` and `skillOverrides` with [switches]
  /// in them: given at start, and again whole (`apply_flag_settings`
  /// replaces each key, not merges into it) when they change, an empty one
  /// taking back what was turned off.
  Map<String, Object?> switchSettings(
    ExtensionSwitches switches, {
    bool whole = false,
  }) {
    final allow = [for (final folder in readable) readRule(folder), ...allowed];
    final deny = switches.denyRules;
    final overrides = switches.skillOverrides;
    return {
      if (whole || allow.isNotEmpty || deny.isNotEmpty)
        'permissions': {
          if (whole || allow.isNotEmpty) 'allow': allow,
          if (whole || deny.isNotEmpty) 'deny': deny,
        },
      if (whole || overrides.isNotEmpty) 'skillOverrides': overrides,
    };
  }

  /// A provider's session's models, let through the user's own
  /// `availableModels`: those it is switched to and starts on, and its
  /// roles' (see [allowedModels]).
  List<String> get allowlist => allowedModels(env, [...models, ?model]);

  /// The user's own setup set empty, in the shell's environment or their
  /// settings' `env`: `CLAUDE_CODE_EFFORT_LEVEL` would hold every request
  /// to its effort, over `--effort` and the one picked since.
  static const unsetEnvironment = {'CLAUDE_CODE_EFFORT_LEVEL': ''};

  /// The permission rule that lets it read what is in [folder] (absolute):
  /// `Read(//Users/me/x/**)`, a Windows path as Claude Code matches it
  /// (`C:\\x` as `/c/x`).
  static String readRule(String folder) => folderRule('Read', folder);

  /// The permission rule for [tool] (`Read`, `Edit`) on what is in
  /// [folder] (absolute), as [readRule]'s.
  static String folderRule(String tool, String folder) {
    var path = folder.replaceAll(r'\', '/');
    if (RegExp(r'^[A-Za-z]:').hasMatch(path)) {
      path = '/${path[0].toLowerCase()}${path.substring(2)}';
    }
    if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    return '$tool(/$path/**)';
  }

  /// Has Claude Code read the `CLAUDE.md` of the folders given with
  /// `--add-dir`, as it does its working directory's.
  static const additionalDirectoriesEnvironment = {
    'CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD': '1',
  };

  /// How the model's thinking comes back: summarized, for the chat to
  /// show (the newest models leave it out unless asked).
  static const thinkingDisplay = 'summarized';

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
    '--thinking-display',
    thinkingDisplay,
    // A prompt_suggestion message after each turn.
    if (promptSuggestions) '--prompt-suggestions',
    if (permissionMode case final mode?) ...['--permission-mode', mode],
    if (model case final model? when model != 'default') ...['--model', model],
    if (effort case final effort?) ...['--effort', effort],
    if (autocompact case final tokens?) ...[
      '--autocompact',
      '${tokens > maxAutocompact ? maxAutocompact : tokens}',
    ],
    if (resume case final id?) ...['--resume', id],
    for (final directory in directories) ...['--add-dir', directory],
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
    if (tools case final tools?) ...[
      '--tools',
      tools.join(','),
      '--strict-mcp-config',
    ],
    if (sdkServers.isNotEmpty) ...[
      '--mcp-config',
      jsonEncode({
        'mcpServers': {
          for (final name in sdkServers) name: {'type': 'sdk', 'name': name},
        },
      }),
      '--allowedTools',
      sdkServers.map((name) => 'mcp__$name').join(','),
    ],
    if (ownPrompt) ...[
      '--system-prompt',
      instructions ?? '',
    ] else ...[
      '--append-system-prompt',
      switch (instructions) {
        final instructions? when instructions.isNotEmpty =>
          '$appendedSystemPrompt\n\n$instructions',
        _ => appendedSystemPrompt,
      },
    ],
  ];

  /// What the chat asks of the agent besides Claude Code's own prompt: how
  /// to cite code and point at files, so the chat can open them, and what
  /// of Markdown the chat draws besides GitHub's.
  static const appendedSystemPrompt =
      '$citingCode\n\n$fileLinks\n\n$formatting';

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

  /// Has the agent point at files as markdown links (`[a.dart](lib/a.dart#L12)`),
  /// which the chat opens in its side panel (see file_link.dart): over
  /// Claude Code's own `file_path:line_number`, which the chat reads too.
  static const fileLinks = '''
<file_links>
When you mention a specific file or folder in your reply (one you read, changed, created or point the user to), write it as a markdown link so the user can open it with a click:

[display name](path/relative/to/working/directory#L42)

- The target is the path relative to the current working directory; for a file outside it (another added directory, a temp file), the full absolute path. Never ~/, file://, vscode://, http:// or https:// for local files.
- Add a line with #L42, or a range with #L42-L58; not :42 in the target.
- If the path contains spaces, wrap the target in angle brackets: [notes.md](<docs/release notes.md#L3>).
- The display name is usually the file name, optionally with the line: [chat_screen.dart:42](lib/chat/chat_screen.dart#L42).
- Link only paths you have seen exist, spelled exactly; do not guess or shorten them.
- Write each path as a link, not as bare text or in backticks; links do not work inside inline code or code blocks, which keep the format of <citing_code>.
</file_links>''';

  /// Tells the agent what the chat draws besides GitHub's Markdown: TeX
  /// (markdown_math.dart), Mermaid (mermaid_code_block.dart, its limits),
  /// local images, and `<details>` folding (markdown_tags.dart).
  static const formatting = r'''
<formatting>
The chat renders GitHub-flavored Markdown, and also:
- Math (TeX): inline $E=mc^2$ or \(...\); display $$...$$ or \[...\] on lines of their own. Not in a ```math fence, which shows as code.
- Mermaid: a ```mermaid block is drawn as a diagram (flowchart, sequence, class, state, ER, gantt, pie, mindmap, timeline, gitGraph…). Prefer flowchart LR to TD: the chat is wider than it is tall. Keep it under about 100 nodes and 200 lines, and quote labels with symbols: A["load (cached)"]; a larger or invalid one shows as its source.
- Images: ![alt](path/to/shot.png) shows a local image inline.
- Folding: <details><summary>Title</summary> … </details>, the tags on lines of their own, folds long logs or output away.
Use them where they make the answer clearer (a diagram for a flow or a structure, math for a formula), not as decoration. Other HTML shows as text.
</formatting>''';

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
