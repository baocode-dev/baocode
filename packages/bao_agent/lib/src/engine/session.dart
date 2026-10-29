import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../api/anthropic_client.dart';
import '../api/message_accumulator.dart';
import '../api/model_catalog.dart';
import '../api/model_client.dart';
import '../config/extensions.dart';
import '../config/memory.dart';
import '../config/output_styles.dart';
import '../config/paths.dart';
import '../config/settings.dart';
import '../hooks/hooks.dart';
import '../mcp/mcp_manager.dart';
import '../permissions/permission_engine.dart';
import '../tools/agent_tool.dart';
import 'scheduler.dart';
import 'worktrees.dart';
import '../tools/file_index.dart';
import '../util/cancel.dart';
import '../util/ids.dart';
import '../util/json.dart';
import '../util/processes.dart';
import 'agent_run.dart';
import 'checkpoints.dart';
import 'context.dart';
import 'session_store.dart';
import 'tasks.dart';
import 'toolbox.dart';

/// How a session is started: Claude Code's command line, as options.
class EngineOptions {
  const EngineOptions({
    required this.cwd,
    this.resume,
    this.sessionId,
    this.model,
    this.permissionMode,
    this.effort,
    this.thinkingDisplay,
    this.autocompact,
    this.persist = true,
    this.directories = const [],
    this.flagSettings = const {},
    this.sdkServers = const [],
    this.appendSystemPrompt,
    this.promptSuggestions = false,
    this.environment = const {},
    this.configDir,
    this.productName = 'BaoCode',
    this.systemPrompt,
    this.tools,
    this.maxTurns,
    this.strictMcpConfig = false,
    this.slashCommands = true,
    this.canAsk = true,
  });

  factory EngineOptions.fromJson(Map<String, Object?> json) => EngineOptions(
    cwd: '${json['cwd']}',
    resume: asText(json['resume']),
    sessionId: asText(json['sessionId']),
    model: asText(json['model']),
    permissionMode: asText(json['permissionMode']),
    effort: asText(json['effort']),
    thinkingDisplay: asText(json['thinkingDisplay']),
    autocompact: asInt(json['autocompact']),
    persist: json['persist'] != false,
    directories: [...asList(json['directories']).whereType<String>()],
    flagSettings: asMap(json['flagSettings']),
    sdkServers: [...asList(json['sdkServers']).whereType<String>()],
    appendSystemPrompt: asString(json['appendSystemPrompt']),
    promptSuggestions: json['promptSuggestions'] == true,
    environment: {
      for (final MapEntry(:key, :value) in asMap(json['environment']).entries)
        if (value is String) key: value,
    },
    configDir: asText(json['configDir']),
    productName: asText(json['productName']) ?? 'BaoCode',
    systemPrompt: asString(json['systemPrompt']),
    tools: json['tools'] is List
        ? [...asList(json['tools']).whereType<String>()]
        : null,
    maxTurns: asInt(json['maxTurns']),
    strictMcpConfig: json['strictMcpConfig'] == true,
    slashCommands: json['slashCommands'] != false,
    canAsk: json['canAsk'] != false,
  );

  final String cwd;

  /// The session to continue.
  final String? resume;

  /// The id a new session takes; one is made up when not given.
  final String? sessionId;
  final String? model;
  final String? permissionMode;
  final String? effort;

  /// How the model's thinking comes back (`--thinking-display`):
  /// `summarized`, or `omitted`; the API's own way when null.
  final String? thinkingDisplay;

  /// The context the conversation may fill before it is compacted.
  final int? autocompact;
  final bool persist;

  /// Folders worked in besides [cwd] (`--add-dir`).
  final List<String> directories;

  /// Settings over the user's own (`--settings`).
  final Map<String, Object?> flagSettings;

  /// The host's own MCP servers.
  final List<String> sdkServers;

  /// Added to the system prompt (`--append-system-prompt`).
  final String? appendSystemPrompt;
  final bool promptSuggestions;

  /// The environment of the user's shell, which commands run in and the
  /// API's settings are read from.
  final Map<String, String> environment;

  /// Where Claude Code's files are, if not where the environment says.
  final String? configDir;

  /// What the agent is built into, as the system prompt names it.
  final String productName;

  /// The system prompt in place of the agent's own (`--system-prompt`).
  final String? systemPrompt;

  /// The only tools offered (`--tools`); all when null.
  final List<String>? tools;

  /// The most requests a turn makes (`--max-turns`).
  final int? maxTurns;

  /// Only the servers given here, none of the user's (`--strict-mcp-config`).
  final bool strictMcpConfig;

  /// Whether `/name` runs a command (`--disable-slash-commands` when not).
  final bool slashCommands;

  /// Whether a host is there to answer questions and approve plans (the
  /// app, or `--permission-prompt-tool`): without one, the tools that ask
  /// are not offered.
  final bool canAsk;

  Map<String, Object?> toJson() => {
    'cwd': cwd,
    'resume': ?resume,
    'sessionId': ?sessionId,
    'model': ?model,
    'permissionMode': ?permissionMode,
    'effort': ?effort,
    'thinkingDisplay': ?thinkingDisplay,
    'autocompact': ?autocompact,
    'persist': persist,
    'directories': directories,
    'flagSettings': flagSettings,
    'sdkServers': sdkServers,
    'appendSystemPrompt': ?appendSystemPrompt,
    'promptSuggestions': promptSuggestions,
    'environment': environment,
    'configDir': ?configDir,
    'productName': productName,
    'systemPrompt': ?systemPrompt,
    'tools': ?tools,
    'maxTurns': ?maxTurns,
    'strictMcpConfig': strictMcpConfig,
    'slashCommands': slashCommands,
    'canAsk': canAsk,
  };
}

/// Why the session cannot reach a model.
class MissingCredentials implements Exception {
  const MissingCredentials();

  static const message =
      'No API key for the built-in Claude Code core. Add an Anthropic (or '
      'compatible) provider in BaoCode\'s settings, set ANTHROPIC_API_KEY '
      '(or ANTHROPIC_AUTH_TOKEN, or an apiKeyHelper in ~/.claude/settings.json), '
      'or switch the core to the Claude Code CLI in Settings → General. '
      'A Claude subscription login is only usable by the Claude Code CLI.';

  @override
  String toString() => message;
}

/// Everything one session works with: where it is, its settings, the
/// model, its tools' state, and how it talks to the host.
class AgentSession {
  AgentSession({
    required this.options,
    required this._emit,
    required this.hostRequest,
    ModelClient Function(ApiConfig config)? clientFactory,
  }) : cwd = p.normalize(options.cwd),
       _clientFactory = clientFactory ?? AnthropicClient.new {
    paths = AgentPaths.from(options.environment, configDir: options.configDir);
    settings = AgentSettings(
      paths: paths,
      cwd: cwd,
      flag: options.flagSettings,
    );
    sessionId = options.resume ?? options.sessionId ?? newUuid();
    model = options.model ?? settings.model ?? ModelCatalog.defaultAlias;
    permissionMode = _initialMode();
    effort = options.effort;
    permissions = PermissionEngine(this);
    checkpoints = FileCheckpoints(this);
    tasks = TaskManager(this);
    hooks = HookRunner(this);
    mainRun = AgentRun(session: this);
  }

  final EngineOptions options;
  final String cwd;
  late final AgentPaths paths;
  late final AgentSettings settings;
  late final String sessionId;
  final void Function(Map<String, Object?>) _emit;
  final ModelClient Function(ApiConfig config) _clientFactory;

  /// Sends a control request to the host and waits for its answer.
  final Future<Map<String, Object?>> Function(
    String subtype,
    Map<String, Object?> fields,
  )
  hostRequest;

  late final PermissionEngine permissions;
  late final FileCheckpoints checkpoints;
  late final TaskManager tasks;
  late final HookRunner hooks;
  late final McpManager mcp = McpManager(this);
  late final AgentRun mainRun;
  late SessionStore store;
  late final FileIndex fileIndex = FileIndex(environment);
  late final Toolbox toolbox = Toolbox(this);
  late final SessionContext context = SessionContext(this);
  late final Shell shell = Shell.find(environment);

  /// The host's own MCP servers.
  List<String> get sdkServers => options.sdkServers;

  List<Plugin> plugins = const [];
  List<PromptCommand> promptCommands = const [];
  List<AgentDefinition> agentDefinitions = builtInAgents;
  List<MemoryFile> memory = const [];
  late final MemoryLoader memoryLoader = MemoryLoader(paths);
  List<OutputStyle> outputStyles = OutputStyle.builtIn;

  /// The output style chosen, if not the default.
  OutputStyle? get outputStyle =>
      OutputStyle.find(outputStyles, asText(settings['outputStyle']));

  /// The folder the agent's own memory of this project is kept in; null
  /// when that is turned off (`autoMemoryEnabled`,
  /// `CLAUDE_CODE_DISABLE_AUTO_MEMORY`).
  String? get autoMemoryDir {
    if (settings['autoMemoryEnabled'] == false) return null;
    final off = environment['CLAUDE_CODE_DISABLE_AUTO_MEMORY'];
    if (off != null && off.isNotEmpty && off != '0' && off != 'false') {
      return null;
    }
    if (asText(settings['autoMemoryDirectory']) case final dir?) {
      return p.normalize(paths.expandHome(dir));
    }
    return p.join(paths.projectDir(_realCwd), 'memory');
  }

  /// [cwd] with its links followed, as the memory folder is named after.
  late final String _realCwd = () {
    try {
      return Directory(cwd).resolveSymbolicLinksSync();
    } on FileSystemException {
      return cwd;
    }
  }();

  /// The model as asked for: an alias (`opus`, `default`) or an id.
  late String model;
  String? effort;
  late String permissionMode;

  /// The id of what the user last typed: hooks are told it, so theirs of a
  /// turn can be told apart.
  String? promptId;

  /// The mode before plan mode was entered, to go back to.
  String? modeBeforePlan;

  /// The subagents started in the session, by id: to send messages to,
  /// and to list.
  final Map<String, SubagentJob> subagents = {};

  /// The prompts scheduled for later (CronCreate, ScheduleWakeup).
  late final Scheduler scheduler = Scheduler(cwd: cwd);

  /// Told of a message a subagent sends the main conversation.
  void Function(String from, String text)? onAgentMessage;

  /// Gives the main conversation [message] from the subagent [from].
  void deliverToMain(String from, String message) => onAgentMessage?.call(
    from,
    '<agent-message from="$from">\n$message\n</agent-message>',
  );

  /// The worktree EnterWorktree moved the main agent into, and where it
  /// was before.
  Worktree? worktree;
  String? _cwdBeforeWorktree;

  /// Moves [run] into [worktree].
  void enterWorktree(Worktree worktree, AgentRun run) {
    if (run.isMain) {
      _cwdBeforeWorktree ??= run.cwd;
      this.worktree = worktree;
    }
    run.cwd = worktree.path;
    sessionDirectories.add(worktree.path);
  }

  /// Moves [run] back out of the worktree; returns where it is now.
  String leaveWorktree(AgentRun run) {
    final back = _cwdBeforeWorktree ?? cwd;
    run.cwd = back;
    if (worktree case final left?) sessionDirectories.remove(left.path);
    worktree = null;
    _cwdBeforeWorktree = null;
    return back;
  }

  /// Folders added to the session's (`addDirectories` for the session).
  final List<String> sessionDirectories = [];

  /// The words the plan file is named by.
  String? planSlug;

  /// The goal the user set (`/goal`), if any.
  String? goal;
  DateTime? goalSetAt;
  int goalChecks = 0;
  int goalTokensAtStart = 0;

  /// The session's cost so far, and each model's share of it.
  double totalCost = 0;
  final Map<String, Map<String, num>> modelUsage = {};

  /// The main agent's last request's usage: how full its context is.
  Map<String, Object?>? lastUsage;

  /// Whether the model ever answered a request: the session is real.
  bool requested = false;

  /// Told when a background task ends, with what to tell the model.
  void Function(BackgroundTask task, String notification)? onTaskEnded;

  /// Told when the mode changes, by the model or the user.
  void Function(String mode)? onModeChanged;

  String _initialMode() {
    final asked = options.permissionMode ?? settings.defaultMode ?? 'default';
    return const {
          'default',
          'acceptEdits',
          'plan',
          'bypassPermissions',
          'dontAsk',
          'auto',
        }.contains(asked)
        ? asked
        : 'default';
  }

  // --- Environment -------------------------------------------------------------

  Map<String, String>? _environment;

  /// The environment the API's settings are read from: the user's shell's,
  /// with the settings' `env` over it.
  Map<String, String> get environment =>
      _environment ??= {...options.environment, ...settings.env};

  Map<String, String>? _commandEnvironment;

  /// The environment commands run in: [environment], but for the keys a
  /// provider was given (they are the session's, not the user's), and
  /// with what tells a program it runs under the agent.
  Map<String, String> get commandEnvironment => _commandEnvironment ??= {
    ...options.environment,
    for (final MapEntry(:key, :value) in settings.env.entries)
      if (!_secret(key) || options.environment[key] == value) key: value,
    'CLAUDECODE': '1',
    'CLAUDE_CODE_ENTRYPOINT': 'baocode-dart',
    'GIT_EDITOR': 'true',
  };

  /// The effort of a turn, as hooks and commands are told it: none for a
  /// model known to take none; a model not known is sent none, and works
  /// as at `high`.
  String? get turnEffort {
    final info = modelInfo;
    if (info.known && !info.supportsEffort) return null;
    return reportedEffort ?? 'high';
  }

  /// [commandEnvironment], with the effort of the turn (`CLAUDE_EFFORT`):
  /// what the model's commands and the hooks run in.
  Map<String, String> get shellEnvironment => {
    ...commandEnvironment,
    'CLAUDE_EFFORT': ?turnEffort,
  };

  static bool _secret(String name) =>
      name == 'ANTHROPIC_API_KEY' || name == 'ANTHROPIC_AUTH_TOKEN';

  /// Reads the settings again (a file changed, a rule was saved).
  void reloadSettings() {
    settings.reload();
    _environment = null;
    _commandEnvironment = null;
  }

  late final ModelCatalog catalog = ModelCatalog(environment);

  // --- The model ----------------------------------------------------------------

  ModelClient? _client;
  String? _helperKey;
  DateTime? _helperAt;

  /// The client requests go through; [MissingCredentials] when there is
  /// no key to send.
  ModelClient get client {
    if (_client case final client?) return client;
    return _client = _clientFactory(apiConfig());
  }

  /// Puts [client] in place of the one made from the environment (tests).
  set client(ModelClient client) => _client = client;

  /// Forgets the client, to be made again (a key from the helper expired).
  void resetClient() => _client = null;

  ApiConfig apiConfig() {
    final env = environment;
    var apiKey = asText(env['ANTHROPIC_API_KEY']);
    final authToken = asText(env['ANTHROPIC_AUTH_TOKEN']);
    if (apiKey == null && authToken == null) apiKey = _keyFromHelper();
    if (apiKey == null && authToken == null) throw const MissingCredentials();
    final headers = <String, String>{};
    for (final line in (env['ANTHROPIC_CUSTOM_HEADERS'] ?? '').split('\n')) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      headers[line.substring(0, colon).trim()] = line
          .substring(colon + 1)
          .trim();
    }
    return ApiConfig(
      baseUrl: asText(env['ANTHROPIC_BASE_URL']) ?? ApiConfig.defaultBaseUrl,
      apiKey: apiKey,
      authToken: authToken,
      headers: headers,
      environment: env,
      maxRetries: asInt(env['CLAUDE_CODE_MAX_RETRIES']) ?? 10,
      idleTimeout: Duration(
        milliseconds: asInt(env['API_TIMEOUT_MS']) ?? 300000,
      ),
      userAgent: 'baocode-agent/1.0 (dart)',
      // As the CLI gives it (JSON with a `session_id`): what our model
      // proxy and the gateways read the session from.
      userId: jsonEncode({'session_id': sessionId}),
      deviceId: deviceId,
    );
  }

  /// The machine's id as Claude Code keeps it (`userID` in
  /// `~/.claude.json`), else one made up for this session.
  late final String deviceId =
      asText(AgentSettings.readJson(paths.claudeJson)['userID']) ??
      randomHex(32);

  /// The key the settings' `apiKeyHelper` prints, kept for five minutes.
  String? _keyFromHelper() {
    final helper = settings.apiKeyHelper;
    if (helper == null) return null;
    final ttl = Duration(
      milliseconds:
          asInt(environment['CLAUDE_CODE_API_KEY_HELPER_TTL_MS']) ?? 300000,
    );
    if (_helperKey != null &&
        _helperAt != null &&
        DateTime.now().difference(_helperAt!) < ttl) {
      return _helperKey;
    }
    try {
      final result = Process.runSync(
        shell.executable,
        shell.posix ? ['-c', helper] : ['/c', helper],
        environment: commandEnvironment,
        includeParentEnvironment: false,
      );
      final key = '${result.stdout}'.trim();
      if (result.exitCode == 0 && key.isNotEmpty) {
        _helperKey = key;
        _helperAt = DateTime.now();
        return key;
      }
    } on ProcessException {
      return null;
    }
    return null;
  }

  /// Whether a key is set up at all.
  bool get hasCredentials {
    try {
      apiConfig();
      return true;
    } on MissingCredentials {
      return false;
    }
  }

  /// The model's id, its `[1m]` taken off.
  String get resolvedModel => catalog.resolve(model);

  /// Whether the model was asked for with its million-token window.
  bool get longContext =>
      model.toLowerCase().endsWith('[1m]') ||
      (asInt(environment['CLAUDE_CODE_MAX_CONTEXT_TOKENS']) ?? 0) > 200000;

  ModelInfo get modelInfo => catalog.info(resolvedModel);

  /// The model's own window.
  int get modelWindow {
    final info = modelInfo;
    final env = asInt(environment['CLAUDE_CODE_MAX_CONTEXT_TOKENS']);
    if (env != null && env > 0) return env;
    if (!info.known) return 200000;
    return longContext
        ? info.contextWindow
        : info.contextWindow.clamp(0, 200000);
  }

  /// The window the conversation is compacted at.
  int get contextWindow {
    final asked = options.autocompact ?? settings.autoCompactWindow;
    if (asked != null && asked > 0) return asked.clamp(20000, modelWindow);
    return modelWindow;
  }

  /// The free room kept before compacting.
  int get compactBuffer => contextWindow >= 100000 ? 33000 : contextWindow ~/ 5;

  /// The effort in effect: the one asked for, else the settings', else the
  /// model's own.
  String? get effectiveEffort =>
      effort ?? settings.effortFor(resolvedModel) ?? settings.effortFor(model);

  /// The model's default effort, as reported.
  String? get reportedEffort => effectiveEffort ?? modelInfo.defaultEffort;

  // --- Output -------------------------------------------------------------------

  /// Sends [message] to the host, with the session's id.
  void emit(Map<String, Object?> message) =>
      _emit({...message, 'session_id': sessionId});

  /// A `system` message of [subtype].
  void emitSystem(String subtype, Map<String, Object?> fields) => emit({
    'type': 'system',
    'subtype': subtype,
    ...fields,
    'uuid': newUuid(),
  });

  /// [task] ended: the model is to be told.
  void taskEnded(BackgroundTask task, String notification) =>
      onTaskEnded?.call(task, notification);

  // --- Mode ---------------------------------------------------------------------

  /// Switches to [mode]; [byModel] when the model did (it entered or left
  /// plan mode), so the host is told.
  void setPermissionMode(String mode, {bool byModel = false}) {
    if (mode == permissionMode) return;
    if (mode == 'plan') modeBeforePlan = permissionMode;
    permissionMode = mode;
    onModeChanged?.call(mode);
    if (byModel) {
      emitSystem('status', {'status': null, 'permissionMode': mode});
    }
  }

  /// Whether the plan was written yet.
  bool get planExists => File(planFilePath).existsSync();

  /// The trailer commits end with and the line pull requests end with:
  /// the settings', else the agent's own; empty for none.
  ({String commit, String pr}) get attribution {
    final set = settings.attribution;
    return (
      commit: set.commit ?? 'Co-Authored-By: Claude <noreply@anthropic.com>',
      pr:
          set.pr ??
          '🤖 Generated with [${options.productName}](https://baocode.dev)',
    );
  }

  /// Where the session's plan is written.
  String get planFilePath {
    planSlug ??= randomSlug();
    return p.join(settings.plansDirectory, '$planSlug.md');
  }

  // --- Folders ------------------------------------------------------------------

  /// The folders the agent works in: the project first.
  List<String> get workingDirectories {
    final out = <String>[cwd];
    for (final dir in [
      ...options.directories,
      ...settings.additionalDirectories,
      ...sessionDirectories,
    ]) {
      final normalized = p.normalize(paths.expandHome(dir));
      if (!out.any((d) => p.equals(d, normalized))) out.add(normalized);
    }
    return out;
  }

  /// The folders the agent keeps its own things in, which it may read.
  List<String> get _internalFolders => [
    settings.plansDirectory,
    tasks.outputDir,
    paths.projectDir(cwd),
    ?autoMemoryDir,
    p.join(paths.configDir, 'skills'),
    p.join(paths.configDir, 'agents'),
    p.join(paths.configDir, 'commands'),
    for (final plugin in plugins) plugin.root,
  ];

  bool internalReadable(String path) => _internalFolders.any(
    (dir) => p.equals(dir, path) || p.isWithin(dir, path),
  );

  /// Whether the agent may write [path] whatever the mode: its plan file,
  /// its memory.
  bool internalWritable(String path) =>
      p.equals(path, planFilePath) ||
      switch (autoMemoryDir) {
        final dir? => p.isWithin(dir, path),
        null => false,
      };

  // --- Files --------------------------------------------------------------------

  /// [path] changed (an edit, a write): the file index is out of date.
  void fileChanged(String path) {
    _suggestionIndex = null;
  }

  /// Forgets that [path] was read, by every agent: it changed underfoot.
  void forgetRead(String path) => mainRun.readFiles.remove(path);

  List<String>? _suggestionIndex;
  DateTime? _suggestionIndexAt;

  /// The files and folders matching [query], for `@` mentions.
  Future<List<String>> suggestFiles(String query) async {
    final now = DateTime.now();
    if (_suggestionIndex == null ||
        _suggestionIndexAt == null ||
        now.difference(_suggestionIndexAt!) > const Duration(seconds: 30)) {
      final files = await fileIndex.list(cwd);
      final relative = [for (final f in files) p.relative(f, from: cwd)];
      final folders = <String>{
        for (final f in relative)
          for (var dir = p.dirname(f); dir != '.'; dir = p.dirname(dir))
            '$dir/',
      };
      _suggestionIndex = [...folders, ...relative];
      _suggestionIndexAt = now;
    }
    final all = _suggestionIndex!;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return [
        ...all.where(
          (f) =>
              !f.contains('/') ||
              (f.endsWith('/') && '/'.allMatches(f).length == 1),
        ),
      ].take(15).toList();
    }
    final scored = <(int, String)>[];
    for (final path in all) {
      final lower = path.toLowerCase();
      final name = p.basename(
        lower.endsWith('/') ? lower.substring(0, lower.length - 1) : lower,
      );
      int? score;
      if (name == q) {
        score = 0;
      } else if (name.startsWith(q)) {
        score = 1;
      } else if (name.contains(q)) {
        score = 2;
      } else if (lower.contains(q)) {
        score = 3;
      } else if (_subsequence(q, lower)) {
        score = 4;
      }
      if (score != null) scored.add((score * 1000 + path.length, path));
    }
    scored.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, path) in scored.take(15)) path];
  }

  static bool _subsequence(String needle, String hay) {
    var i = 0;
    for (var j = 0; j < hay.length && i < needle.length; j++) {
      if (hay[j] == needle[i]) i++;
    }
    return i == needle.length;
  }

  // --- Memory -------------------------------------------------------------------

  /// What instructions apply to [path] that [run] has not been given yet:
  /// a `CLAUDE.md` of a folder below the project, a rule for such files.
  List<String> memoryFor(String path, AgentRun run) {
    final out = <String>[];
    final given = run.givenMemory;
    // What the prompt had: all but the rules for some paths only.
    if (given.isEmpty) {
      given.addAll([
        for (final m in memory)
          if (!m.conditional) m.path,
      ]);
    }
    final folder = p.dirname(path);
    final root = workingDirectories.firstWhere(
      (dir) => p.isWithin(dir, folder) || p.equals(dir, folder),
      orElse: () => '',
    );
    if (root.isNotEmpty && !p.equals(root, folder)) {
      final folders = <String>[];
      for (var dir = folder; p.isWithin(root, dir); dir = p.dirname(dir)) {
        folders.add(dir);
      }
      for (final dir in folders.reversed) {
        for (final file in memoryLoader.nested(dir, given)) {
          given.add(file.path);
          out.add('${file.path} (${file.description}):\n\n${file.content}');
        }
      }
    }
    for (final rule in MemoryLoader.rulesFor(memory, path, cwd)) {
      if (!given.add(rule.path)) continue;
      out.add('${rule.path} (${rule.description}):\n\n${rule.content}');
    }
    return out;
  }

  // --- Usage --------------------------------------------------------------------

  /// Adds a request's [usage] to the session's cost.
  double addUsage(String model, Map<String, Object?> usage) {
    final info = catalog.info(model);
    final cost = info.cost(usage);
    totalCost += cost;
    int count(String key) => asInt(usage[key]) ?? 0;
    final entry = modelUsage[model] ??= {
      'inputTokens': 0,
      'outputTokens': 0,
      'cacheReadInputTokens': 0,
      'cacheCreationInputTokens': 0,
      'webSearchRequests': 0,
      'costUSD': 0.0,
    };
    entry['inputTokens'] = entry['inputTokens']! + count('input_tokens');
    entry['outputTokens'] = entry['outputTokens']! + count('output_tokens');
    entry['cacheReadInputTokens'] =
        entry['cacheReadInputTokens']! + count('cache_read_input_tokens');
    entry['cacheCreationInputTokens'] =
        entry['cacheCreationInputTokens']! +
        count('cache_creation_input_tokens');
    entry['webSearchRequests'] =
        entry['webSearchRequests']! +
        (asInt(asMap(usage['server_tool_use'])['web_search_requests']) ?? 0);
    entry['costUSD'] = entry['costUSD']! + cost;
    return cost;
  }

  /// The models' usage as the result reports it.
  Map<String, Object?> modelUsageReport() => {
    for (final MapEntry(key: model, value: usage) in modelUsage.entries)
      model: {
        ...usage,
        'contextWindow': model == resolvedModel
            ? modelWindow
            : catalog.info(model).contextWindow,
        'maxOutputTokens': catalog.info(model).maxOutput,
      },
  };

  // --- Errands -----------------------------------------------------------------

  /// Asks the small, fast model (or [model]) [prompt], with [system], and
  /// returns its answer's text. Falls back to the main model when the
  /// small one is not offered (another provider's).
  Future<String> quickQuery({
    required String system,
    required String prompt,
    String? model,
    CancelToken? cancel,
    int maxTokens = 2048,
  }) async {
    final first = model == null ? catalog.smallFast : catalog.resolve(model);
    try {
      return await _query(first, system, prompt, cancel, maxTokens);
    } on ApiError catch (error) {
      final main = resolvedModel;
      if (first == main || error.authentication) rethrow;
      if (error.status == 404 || error.status == 400 || error.status == 403) {
        return _query(main, system, prompt, cancel, maxTokens);
      }
      rethrow;
    }
  }

  Future<String> _query(
    String model,
    String system,
    String prompt,
    CancelToken? cancel,
    int maxTokens,
  ) async {
    final info = catalog.info(model);
    var accumulator = MessageAccumulator();
    await for (final event in client.stream(
      ModelRequest({
        'model': model,
        'max_tokens': maxTokens,
        'system': [
          {'type': 'text', 'text': system},
        ],
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        if (info.known &&
            info.canDisableThinking &&
            info.thinking != ThinkingStyle.none)
          'thinking': {'type': 'disabled'},
      }),
      cancel: cancel,
    )) {
      if (event['type'] == 'stream_restart') {
        accumulator = MessageAccumulator();
        continue;
      }
      accumulator.add(event);
    }
    addUsage(model, accumulator.usage);
    return [
      for (final block in accumulator.content)
        if (block['type'] == 'text') '${block['text']}',
    ].join().trim();
  }
}
