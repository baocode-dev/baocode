import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../api/anthropic_client.dart';
import '../api/model_client.dart';
import '../config/extensions.dart';
import '../config/memory.dart';
import '../config/output_styles.dart';
import '../config/settings.dart';
import '../hooks/hooks.dart';
import '../prompts/system_prompt.dart';
import '../prompts/task_prompts.dart';
import '../tools/file_state.dart';
import '../tools/skill_tool.dart';
import '../util/cancel.dart';
import '../util/ids.dart';
import '../util/json.dart';
import 'agent_loop.dart';
import 'compaction.dart';
import 'context.dart';
import 'session.dart';
import 'session_store.dart';
import 'tasks.dart';
import 'transcript.dart';

/// The version the engine reports itself as.
const engineVersion = '1.0.0';

/// A command of the agent's own, as `initialize` lists it.
class BuiltInCommand {
  const BuiltInCommand(
    this.name,
    this.description, {
    this.argumentHint = '',
    this.aliases = const [],
  });

  /// One of the bundled prompts ([bundledSkills]), listed in its place
  /// among the agent's own.
  const BuiltInCommand.bundled(this.name)
    : description = '',
      argumentHint = '',
      aliases = const [];

  final String name;
  final String description;
  final String argumentHint;
  final List<String> aliases;

  bool get isBundled => description.isEmpty;

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'argumentHint': argumentHint,
    if (aliases.isNotEmpty) 'aliases': aliases,
    'builtin': true,
  };
}

/// The agent's own commands, in the order they are listed (after the
/// bundled skills).
const builtInCommands = [
  BuiltInCommand(
    'autocompact',
    'Set when the conversation gets compacted: by the model\'s window, or '
        'at a number of tokens',
    argumentHint: '[auto|<tokens>]',
  ),
  BuiltInCommand(
    'clear',
    'Start again with an empty context; what was said so far stays in the '
        'transcript',
    argumentHint: '[name]',
    aliases: ['reset', 'new'],
  ),
  BuiltInCommand(
    'compact',
    'Replace the conversation so far with a summary of it, to free up '
        'context',
    argumentHint: '<what the summary should keep>',
  ),
  BuiltInCommand(
    'config',
    'Change a setting, by its key',
    argumentHint: 'key=value',
    aliases: ['settings'],
  ),
  BuiltInCommand(
    'output-style',
    'List the output styles, or switch to one',
    argumentHint: '[style]',
  ),
  BuiltInCommand('context', 'How full the context window is, and with what'),
  BuiltInCommand(
    'effort',
    'Set how hard the model works',
    argumentHint: '<low|medium|high|xhigh|max|auto>',
  ),
  BuiltInCommand.bundled('init'),
  BuiltInCommand(
    'mcp',
    'The MCP servers: how they are, or reconnect, switch on or off',
    argumentHint: '[reconnect|enable|disable [<server>|all]]',
  ),
  BuiltInCommand('model', 'Switch to another model', argumentHint: '<model>'),
  BuiltInCommand(
    'reload-plugins',
    'Take up the plugins installed or switched on since the session began',
    argumentHint: '[--force]',
  ),
  BuiltInCommand(
    'reload-skills',
    'Take up the skills added or changed on disk since the session began',
  ),
  BuiltInCommand(
    'rename',
    'Give this conversation a name',
    argumentHint: '[name]',
    aliases: ['name'],
  ),
  BuiltInCommand.bundled('security-review'),
  BuiltInCommand(
    'usage',
    'What this session has used and cost so far',
    aliases: ['cost', 'stats'],
  ),
  BuiltInCommand.bundled('insights'),
  BuiltInCommand('recap', 'Sum the session up in a line, now'),
  BuiltInCommand(
    'goal',
    'Set a goal the agent keeps working toward until it is met',
  ),
  BuiltInCommand(
    'list-agents',
    'List the agents of this session a message can be sent to',
    aliases: ['peers'],
  ),
];

/// A message of the user's, sent and not yet taken up.
class _Queued {
  _Queued(this.message)
    : uuid = asString(message['uuid']) ?? newUuid(),
      priority = asString(message['priority']) ?? 'later';

  final Map<String, Object?> message;
  final String uuid;

  /// `next`: taken up within the turn running, between its tool calls;
  /// `later` (and anything else): once it ends.
  final String priority;

  /// Written by the agent itself (a background task's notice), not sent.
  bool own = false;

  Map<String, Object?> get body => asMap(message['message']);

  List<Map<String, Object?>> get blocks => switch (body['content']) {
    final String text => [
      {'type': 'text', 'text': text},
    ],
    final List<Object?> blocks => [for (final b in blocks) asMap(b)],
    _ => const [],
  };

  /// What the user typed: the text blocks, the notes sent along left out.
  String get text => [
    for (final block in blocks)
      if (block['type'] == 'text' &&
          !'${block['text'] ?? ''}'.trimLeft().startsWith(
            '<system-reminder>',
          ) &&
          !RegExp(r'^\[Image #\d+\]$')
              .hasMatch('${block['text'] ?? ''}'.trim()))
        '${block['text'] ?? ''}',
  ].join('\n');

  /// The slash command it is (`/name args`), if it is one.
  ({String name, String args})? get command {
    if (own) return null;
    final typed = text.trimLeft();
    final match = RegExp(r'^/([A-Za-z0-9_:.\-]+)(?:\s+([\s\S]*))?$')
        .firstMatch(typed);
    if (match == null) return null;
    return (name: match[1]!, args: (match[2] ?? '').trim());
  }
}

/// A turn under way.
class _Turn {
  final CancelToken cancel = CancelToken();
  final DateTime started = DateTime.now();
}

/// The agent as a program speaks: Claude Code's stream-json protocol, over
/// messages in and out. A host sends user messages and control requests,
/// and answers the requests the agent sends it (permission to use a tool,
/// an MCP server's question); the agent sends what it does, as it does it.
class AgentEngine {
  AgentEngine(
    this.options, {
    required void Function(Map<String, Object?> message) send,
    ModelClient Function(ApiConfig config)? clientFactory,
  }) : _send = send {
    session = AgentSession(
      options: options,
      emit: send,
      hostRequest: _hostRequest,
      clientFactory: clientFactory,
    );
    session.onTaskEnded = _taskEnded;
    session.onAgentMessage = _agentMessage;
    session.scheduler.onFire = _scheduledPrompt;
    _ready = _start();
    // A failure to start is told with the first request.
    unawaited(_ready.catchError((Object _) {}));
  }

  final EngineOptions options;
  final void Function(Map<String, Object?>) _send;
  late final AgentSession session;
  late final Future<void> _ready;
  Future<void>? _mcpReady;

  final Map<String, Completer<Map<String, Object?>>> _pending = {};
  final List<_Queued> _queue = [];
  _Turn? _turn;
  bool _closed = false;
  bool _promptSuggestions = false;

  /// What the session's start hooks had the model told, with the first
  /// prompt.
  String? _startContext;
  bool _titled = false;

  // --- Start and end --------------------------------------------------------------

  Future<void> _start() async {
    _promptSuggestions = options.promptSuggestions;
    await session.context.load();
    final branch = session.context.git?.branch;
    final resume = options.resume;
    if (resume != null) {
      final file =
          session.paths.findSession(resume) ??
          session.paths.sessionFile(session.cwd, resume);
      session.store = SessionStore.resume(
        sessionId: resume,
        cwd: session.cwd,
        file: file,
        gitBranch: branch,
        persist: options.persist,
      );
      session.checkpoints.load(session.store.extras);
      _titled = session.store.title != null;
      _restoreGoal();
    } else {
      session.store = SessionStore(
        sessionId: session.sessionId,
        cwd: session.cwd,
        file: options.persist
            ? session.paths.sessionFile(session.cwd, session.sessionId)
            : null,
        gitBranch: branch,
      );
    }
    _mcpReady = session.mcp.start().catchError((Object _) {});
    session.scheduler.load();
    for (final file in session.memory) {
      // Auto memory is no instructions file: not told.
      if (file.type == MemoryType.auto) continue;
      final type = file.type.name;
      session.hooks.notify(HookEvent.instructionsLoaded, {
        'file_path': file.path,
        'memory_type': '${type[0].toUpperCase()}${type.substring(1)}',
        'load_reason': 'session_start',
      }, query: 'session_start');
    }
    if (session.hooks.has(HookEvent.sessionStart)) {
      final outcome = await session.hooks.run(HookEvent.sessionStart, {
        'source': resume == null ? 'startup' : 'resume',
      }, query: resume == null ? 'startup' : 'resume');
      final context = [...outcome.additionalContext, ...outcome.outputs];
      if (context.isNotEmpty) _startContext = context.join('\n\n');
    }
  }

  final Completer<void> _done = Completer<void>();

  /// Whether the session has been ended.
  bool get closed => _closed;

  /// Completes once the session has ended (closed by the host, or by
  /// `end_session`).
  Future<void> get done => _done.future;

  /// Ends the session: the turn stopped, the tasks and servers too.
  Future<void> close() async {
    if (_closed) return _done.future;
    _closed = true;
    _turn?.cancel.cancel('closed');
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(const Cancelled('closed'));
      }
    }
    _pending.clear();
    try {
      await _ready.timeout(const Duration(seconds: 5));
      if (session.hooks.has(HookEvent.sessionEnd)) {
        await session.hooks
            .run(HookEvent.sessionEnd, {'reason': 'other'})
            .timeout(const Duration(seconds: 10));
      }
    } on Object {
      // Ending all the same.
    }
    session.scheduler.dispose();
    await session.tasks.stopAll().catchError((Object _) {});
    await session.mcp.close().catchError((Object _) {});
    _done.complete();
  }

  // --- Messages in ----------------------------------------------------------------

  /// Takes a message from the host.
  void receive(Map<String, Object?> message) {
    if (_closed) return;
    switch (message['type']) {
      case 'user':
        _enqueue(_Queued(message));
      case 'control_request':
        final id = asString(message['request_id']);
        if (id == null) return;
        unawaited(_control(id, asMap(message['request'])));
      case 'control_response':
        final response = asMap(message['response']);
        final id = asString(response['request_id']);
        final pending = id == null ? null : _pending.remove(id);
        if (pending == null || pending.isCompleted) return;
        if (response['subtype'] == 'error') {
          pending.completeError(
            StateError('${response['error'] ?? 'refused'}'),
          );
        } else {
          pending.complete(asMap(response['response']));
        }
      case 'control_cancel_request':
        // The host gave up on one of its requests: nothing to stop here.
        break;
    }
  }

  /// Sends the host a request, and waits for its answer.
  Future<Map<String, Object?>> _hostRequest(
    String subtype,
    Map<String, Object?> fields,
  ) {
    if (_closed) return Future.error(const Cancelled('closed'));
    final id = randomId(16);
    final done = Completer<Map<String, Object?>>();
    _pending[id] = done;
    _send({
      'type': 'control_request',
      'request_id': id,
      'request': {'subtype': subtype, ...fields},
    });
    return done.future;
  }

  /// Tells the host its pending requests are moot (the turn stopped).
  void _cancelHostRequests() {
    for (final MapEntry(key: id, value: done) in [..._pending.entries]) {
      _send({'type': 'control_cancel_request', 'request_id': id});
      _pending.remove(id);
      if (!done.isCompleted) done.completeError(const Cancelled('interrupted'));
    }
  }

  Future<void> _control(String id, Map<String, Object?> request) async {
    try {
      final response = await _answer(request);
      _send({
        'type': 'control_response',
        'response': {
          'subtype': 'success',
          'request_id': id,
          'response': response,
        },
      });
    } on Object catch (error) {
      _send({
        'type': 'control_response',
        'response': {
          'subtype': 'error',
          'request_id': id,
          'error': error is StateError ? error.message : '$error',
        },
      });
    }
  }

  Future<Map<String, Object?>> _answer(Map<String, Object?> request) async {
    final subtype = asString(request['subtype']);
    if (subtype == 'interrupt') {
      _interrupt();
      return const {};
    }
    await _ready;
    switch (subtype) {
      case 'initialize':
        if (request['promptSuggestions'] is bool) {
          _promptSuggestions = request['promptSuggestions'] == true;
        }
        if (asString(request['appendSystemPrompt']) case final extra?) {
          _appendedByHost = extra;
        }
        return _initialize();
      case 'set_permission_mode':
        final mode = asString(request['mode']) ?? 'default';
        if (!_modes.contains(mode)) throw StateError('Unknown mode: $mode');
        session.setPermissionMode(mode);
        return {'mode': session.permissionMode};
      case 'set_model':
        await _switchModel(asText(request['model']) ?? 'default');
        return const {};
      case 'apply_flag_settings':
        final settings = asMap(request['settings']);
        session.settings.applyFlag(settings);
        session.reloadSettings();
        if (settings.containsKey('effortLevel')) {
          session.effort = asText(settings['effortLevel']);
        }
        if (settings.containsKey('model')) {
          await _switchModel(asText(settings['model']) ?? session.model);
        }
        session.hooks.notify(HookEvent.configChange, {
          'source': SettingsSource.flag.wire,
          'changes': settings,
        }, query: SettingsSource.flag.wire);
        return const {};
      case 'get_settings':
        return {
          'applied': {
            'model': session.resolvedModel,
            'effort': _effortShown,
            'permissionMode': session.permissionMode,
          },
          'effective': session.settings.merged,
        };
      case 'cancel_async_message':
        final uuid = asString(request['message_uuid']);
        final at = _queue.indexWhere((q) => q.uuid == uuid);
        if (at < 0) return {'cancelled': false};
        _queue.removeAt(at);
        session.emit({
          'type': 'command_lifecycle',
          'command_uuid': uuid,
          'state': 'cancelled',
        });
        return {'cancelled': true};
      case 'rewind_conversation':
        return _rewindConversation(request);
      case 'rewind_files':
        final messageId = asString(request['user_message_id']) ?? '';
        final changed = session.checkpoints.rewind(
          messageId,
          dryRun: request['dry_run'] == true,
        );
        if (changed == null) {
          return {
            'canRewind': false,
            'error': 'No file checkpoint found for this message.',
          };
        }
        return {'canRewind': true, 'filesChanged': changed};
      case 'rename_session':
        final title = asText(request['title']);
        if (title == null) throw StateError('A title is required');
        session.store.note({'type': 'custom-title', 'customTitle': title});
        _titled = true;
        return const {};
      case 'stop_task':
        final taskId = asString(request['task_id']) ?? '';
        if (!await session.tasks.stop(taskId)) {
          throw StateError('No running task with ID: $taskId');
        }
        return const {};
      case 'background_tasks':
        return {
          'backgrounded': _toBackground(asString(request['tool_use_id'])),
        };
      case 'mcp_status':
        await _mcpReady;
        return session.mcp.status();
      case 'mcp_toggle':
        await _mcpReady;
        await session.mcp.toggle(
          '${request['serverName']}',
          request['enabled'] == true,
        );
        return const {};
      case 'mcp_reconnect':
        await _mcpReady;
        await session.mcp.reconnect('${request['serverName']}');
        return const {};
      case 'mcp_authenticate':
        await _mcpReady;
        final url = await session.mcp.authenticate('${request['serverName']}');
        if (url == null) return const {};
        return {
          'authUrl': '$url',
          'requiresUserAction': true,
          'callbackExpected': true,
        };
      case 'file_suggestions':
        final suggestions = await session.suggestFiles(
          asString(request['query']) ?? '',
        );
        return {
          'suggestions': [
            for (final path in suggestions) {'path': path},
          ],
          'cwd': session.cwd,
        };
      case 'get_hooks_listing':
        return session.hooks.listing();
      case 'get_usage':
        return {
          'session': {'total_cost_usd': session.totalCost},
          'subscription_type': null,
          'rate_limits_available': false,
          'behaviors': null,
        };
      case 'get_context_usage':
        return contextUsage();
      case 'reload_plugins' || 'reload_extensions':
        session.context.reloadPlugins();
        await _mcpReady;
        await session.mcp.connectNew();
        return {
          'commands': _commands(),
          'agents': [for (final agent in session.agentDefinitions) agent.name],
          'plugins': [
            for (final plugin in session.plugins)
              {'name': plugin.name, 'path': plugin.root},
          ],
          ...session.mcp.status(),
        };
      case 'end_session':
        unawaited(close());
        return const {};
      default:
        throw StateError('Unsupported control request: $subtype');
    }
  }

  static const _modes = {
    'default',
    'acceptEdits',
    'plan',
    'bypassPermissions',
    'dontAsk',
    'auto',
  };

  String? _appendedByHost;

  String? get _effortShown {
    final info = session.modelInfo;
    if (info.known && !info.supportsEffort) return null;
    return session.reportedEffort;
  }

  List<Map<String, Object?>> _commands() => [
    for (final command in session.promptCommands)
      if (command.userInvocable && command.source != 'bundled')
        command.toCommandJson(),
    for (final command in session.promptCommands)
      if (command.source == 'bundled' && command.isSkill)
        command.toCommandJson(),
    for (final command in builtInCommands)
      if (!command.isBundled)
        command.toJson()
      else if (_bundled(command.name) case final bundled?)
        bundled.toCommandJson(),
    for (final server in session.mcp.servers.values)
      if (server.connected)
        for (final prompt in server.prompts)
          {
            'name': 'mcp__${server.name}__${prompt['name']}',
            'description': '${prompt['description'] ?? ''}',
            'argumentHint': [
              for (final argument in asList(prompt['arguments']))
                '<${asMap(argument)['name']}>',
            ].join(' '),
          },
  ];

  /// The bundled prompt [name] names, unless one of the user's has the
  /// name.
  PromptCommand? _bundled(String name) => session.promptCommands
      .where((c) => c.name == name && c.source == 'bundled')
      .firstOrNull;

  /// The command [typed] runs: by its name, else by one of its aliases.
  String _commandName(String typed) {
    if (builtInCommands.any((c) => c.name == typed && !c.isBundled) ||
        session.promptCommands.any((c) => c.name == typed)) {
      return typed;
    }
    for (final command in builtInCommands) {
      if (command.aliases.contains(typed)) return command.name;
    }
    for (final command in session.promptCommands) {
      if (command.aliases.contains(typed)) return command.name;
    }
    return typed;
  }

  Map<String, Object?> _initialize() {
    final picker = [
      for (final option in asList(
        asMap(session.settings['modelPicker'])['options'],
      ))
        ?asText(asMap(option)['model']),
    ];
    final agents = [...session.agentDefinitions]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return {
      'commands': _commands(),
      'agents': [for (final agent in agents) agent.toJson()],
      'output_style': asText(session.settings['outputStyle']) ?? 'default',
      'available_output_styles': [
        'default',
        for (final style in session.outputStyles) style.name,
      ],
      'user_output_styles_dir': OutputStyle.userDir(session.paths),
      'models': [
        ...session.catalog.listed(),
        for (final model in picker)
          {
            'value': model,
            'resolvedModel': model,
            'displayName': model,
            'description': '',
            'supportsEffort': session.catalog.info(model).supportsEffort,
            'supportedEffortLevels': session.catalog.info(model).effortLevels,
          },
      ],
      'account': {
        'tokenSource': 'none',
        'apiKeySource': _apiKeySource,
        'apiProvider':
            ApiConfig.isFirstParty(
              asText(session.environment['ANTHROPIC_BASE_URL']) ??
                  ApiConfig.defaultBaseUrl,
              session.environment,
            )
            ? 'firstParty'
            : 'custom',
      },
      'pid': pid,
      'current_permission_mode': session.permissionMode,
      'feedback_mode': {'kind': 'disabled'},
      'analytics_disabled': true,
      'fast_mode_state': 'off',
      'fast_mode_disabled_reason': 'unsupported',
      'session_state': _turn == null ? 'idle' : 'running',
      'capabilities': const ['ui_surface_v1'],
    };
  }

  String get _apiKeySource {
    final env = session.environment;
    if (asText(env['ANTHROPIC_API_KEY']) != null) return 'ANTHROPIC_API_KEY';
    if (asText(env['ANTHROPIC_AUTH_TOKEN']) != null) {
      return 'ANTHROPIC_AUTH_TOKEN';
    }
    if (session.settings.apiKeyHelper != null) return 'apiKeyHelper';
    return 'none';
  }

  // --- The context ----------------------------------------------------------------

  /// What the main agent is told besides the conversation.
  AgentPrompt _mainPrompt(ToolSet tools) => session.context.main(
    own: options.systemPrompt,
    appended: [?options.appendSystemPrompt, ?_appendedByHost],
    notes: [
      if (_startContext case final start?)
        '<system-reminder>\nA SessionStart hook adds: $start\n</system-reminder>',
      if (session.goal case final goal?) goalInstruction(goal),
    ],
    tools: tools,
  );

  /// What the context holds, by kind (`get_context_usage`, `/context`).
  Map<String, Object?> contextUsage() {
    final toolSet = session.toolbox.main();
    final prompt = _mainPrompt(toolSet);
    final systemTokens = estimateTokens(
      [...prompt.system, prompt.context].join('\n'),
    );
    final tools = toolSet.tools;
    final builtIn = estimateTokens([
      for (final tool in tools)
        if (!tool.name.startsWith('mcp__')) tool.toApi(session),
    ]);
    final mcp = estimateTokens([
      for (final tool in tools)
        if (tool.name.startsWith('mcp__')) tool.toApi(session),
    ]);
    final memory = estimateTokens(prompt.reminders.join('\n'));
    final fixed = systemTokens + builtIn + mcp + memory;
    final compaction = Compaction(session);
    final used = session.lastUsage == null
        ? fixed + estimateTokens(session.store.apiMessages())
        : compaction.usedTokens(session.store);
    final messages = (used - fixed).clamp(0, 1 << 40);
    final window = session.contextWindow;
    final buffer = compaction.autoEnabled ? session.compactBuffer : 0;
    final total = fixed + messages;
    return {
      'categories': [
        {'name': 'System prompt', 'tokens': systemTokens, 'kind': 'used'},
        {'name': 'System tools', 'tokens': builtIn, 'kind': 'used'},
        if (mcp > 0) {'name': 'MCP tools', 'tokens': mcp, 'kind': 'used'},
        {'name': 'Memory files', 'tokens': memory, 'kind': 'used'},
        {'name': 'Messages', 'tokens': messages, 'kind': 'used'},
        if (buffer > 0)
          {'name': 'Autocompact buffer', 'tokens': buffer, 'kind': 'buffer'},
        {
          'name': 'Free space',
          'tokens': (window - total - buffer).clamp(0, window),
          'kind': 'free',
        },
      ],
      'totalTokens': total,
      'maxTokens': window,
      'rawMaxTokens': window,
      'percentage': window == 0 ? 0 : (total * 100 / window).round(),
      'model': session.resolvedModel,
      'memoryFiles': [
        for (final file in session.memory)
          {'path': file.path, 'type': file.type.name},
      ],
    };
  }

  // --- Turns ------------------------------------------------------------------------

  void _enqueue(_Queued queued) {
    _queue.add(queued);
    _pump();
  }

  /// Starts the next turn, if none runs: the messages waiting, together
  /// (a command alone).
  void _pump() {
    if (_turn != null || _closed || _queue.isEmpty) return;
    final batch = <_Queued>[];
    if (_queue.first.command != null && options.slashCommands) {
      batch.add(_queue.removeAt(0));
    } else {
      while (_queue.isNotEmpty &&
          (_queue.first.command == null || !options.slashCommands)) {
        batch.add(_queue.removeAt(0));
      }
    }
    final turn = _turn = _Turn();
    unawaited(_runTurn(turn, batch));
  }

  /// The messages sent to be taken up within the turn running: those of
  /// priority `next`, commands aside.
  List<Map<String, Object?>> _takeNext() {
    final taken = <Map<String, Object?>>[];
    _queue.removeWhere((queued) {
      if (queued.priority != 'next' || queued.command != null) {
        return false;
      }
      taken.add({'uuid': queued.uuid, 'message': queued.body});
      return true;
    });
    return taken;
  }

  void _state(String state) =>
      session.emitSystem('session_state_changed', {'state': state});

  void _emitInit() {
    final tools = session.toolbox.main().tools;
    session.emitSystem('init', {
      'cwd': session.cwd,
      'tools': [for (final tool in tools) tool.name],
      'mcp_servers': [
        for (final server in session.mcp.servers.values)
          {'name': server.name, 'status': server.status},
      ],
      'model': session.resolvedModel,
      'permissionMode': session.permissionMode,
      'slash_commands': [for (final command in _commands()) command['name']],
      'terminal_slash_commands': const <String>[],
      'apiKeySource': _apiKeySource,
      'claude_code_version': engineVersion,
      'output_style': asText(session.settings['outputStyle']) ?? 'default',
      'agents': [for (final agent in session.agentDefinitions) agent.name],
      'skills': [
        for (final command in session.promptCommands)
          if (command.isSkill) command.name,
      ],
      'plugins': [
        for (final plugin in session.plugins)
          {'name': plugin.name, 'path': plugin.root},
      ],
      'capabilities': const ['msg_lifecycle_v1', 'ui_surface_v1'],
      'analytics_disabled': true,
      'product_feedback_disabled': true,
      if (session.autoMemoryDir case final dir?)
        'memory_paths': {'auto': '$dir${Platform.pathSeparator}'},
      'fast_mode_state': 'off',
      'fast_mode_disabled_reason': 'unsupported',
      'effort': _effortShown,
    });
  }

  Future<void> _runTurn(_Turn turn, List<_Queued> batch) async {
    _state('running');
    try {
      await _ready;
      // The MCP servers' tools, if they come up soon.
      await _mcpReady?.timeout(const Duration(seconds: 5), onTimeout: () {});
      _emitInit();
      for (final queued in batch) {
        if (queued.own) continue;
        session.emit({
          ...queued.message,
          'type': 'user',
          'uuid': queued.uuid,
          'parent_tool_use_id': null,
          'isReplay': true,
        });
        session.emit({
          'type': 'command_lifecycle',
          'command_uuid': queued.uuid,
          'state': 'started',
        });
      }
      // What the user typed starts a prompt of its own, for the hooks.
      if (batch.any((q) => !q.own)) session.promptId = newUuid();
      final command = options.slashCommands ? batch.first.command : null;
      if (command != null) {
        await _runCommand(turn, batch.first, command.name, command.args);
      } else {
        await _runPrompt(turn, batch);
      }
    } on Object catch (error) {
      _emitResult(
        turn,
        LoopResult(
          reason: 'error',
          lastText: '',
          requests: 0,
          usage: const {},
          apiDuration: Duration.zero,
          error: error is MissingCredentials
              ? MissingCredentials.message
              : '$error',
        ),
      );
    } finally {
      _turn = null;
      _state('idle');
      _pump();
    }
  }

  /// A turn of the model's: [batch] (the user's messages) added, the agent
  /// at work until it ends its turn.
  Future<void> _runPrompt(
    _Turn turn,
    List<_Queued> batch, {
    List<String> context = const [],
  }) async {
    final store = session.store;
    final notes = [...context];
    final typed = batch.where((q) => !q.own).map((q) => q.text).join('\n');
    if (typed.trim().isNotEmpty) {
      if (session.hooks.has(HookEvent.userPromptSubmit)) {
        final hook = await session.hooks.run(HookEvent.userPromptSubmit, {
          'prompt': typed,
        }, cancel: turn.cancel);
        if (hook.blocked || hook.stop) {
          final reason = hook.blocked
              ? hook.blockReason
              : (hook.stopReason ?? '');
          _localReply(
            'A UserPromptSubmit hook held this prompt back:\n$reason'.trim(),
            store: false,
          );
          _emitResult(
            turn,
            _localResult('', error: 'Blocked by a hook: $reason'),
          );
          return;
        }
        notes.addAll([...hook.additionalContext, ...hook.outputs]);
      }
      notes.addAll(_mentions(typed));
    }
    for (final (i, queued) in batch.indexed) {
      final blocks = [...queued.blocks];
      if (i == batch.length - 1) {
        for (final note in notes) {
          blocks.add({
            'type': 'text',
            'text': '<system-reminder>\n$note\n</system-reminder>',
          });
        }
      }
      store.append({
        'type': 'user',
        'message': {'role': 'user', 'content': blocks},
        'uuid': queued.uuid,
        if (queued.own) 'isMeta': false,
      });
      session.checkpoints.begin(queued.uuid);
    }
    if (!_titled && typed.trim().isNotEmpty) {
      _titled = true;
      unawaited(_nameSession(typed));
    }
    await _runModel(turn);
  }

  /// Runs the main agent on the conversation as it stands, and reports.
  Future<LoopResult> _runModel(_Turn turn) async {
    final tools = session.toolbox.main();
    final loop = AgentLoop(
      session: session,
      run: session.mainRun,
      store: session.store,
      tools: tools,
      prompt: _mainPrompt(tools),
      model: session.resolvedModel,
      maxTurns: options.maxTurns,
      takeQueued: _takeNext,
    );
    final result = await loop.runTurn(turn.cancel);
    _emitResult(turn, result, denials: loop.denials);
    if (result.ok && _promptSuggestions && _queue.isEmpty) {
      unawaited(_suggest());
    }
    return result;
  }

  void _emitResult(
    _Turn turn,
    LoopResult result, {
    List<Map<String, Object?>> denials = const [],
  }) {
    final subtype = switch (result.reason) {
      'interrupted' => 'error_during_execution',
      'max_turns' => 'error_max_turns',
      _ => 'success',
    };
    final error = result.reason == 'error';
    session.emit({
      'type': 'result',
      'subtype': subtype,
      'is_error': error,
      'duration_ms': DateTime.now().difference(turn.started).inMilliseconds,
      'duration_api_ms': result.apiDuration.inMilliseconds,
      'num_turns': result.requests,
      'result': error ? (result.error ?? 'Error') : result.lastText,
      'stop_reason': result.reason == 'end_turn' ? 'end_turn' : null,
      'total_cost_usd': session.totalCost,
      'usage': {
        'input_tokens': 0,
        'cache_creation_input_tokens': 0,
        'cache_read_input_tokens': 0,
        'output_tokens': 0,
        ...result.usage,
      },
      'modelUsage': session.modelUsageReport(),
      'permission_denials': denials,
      'uuid': newUuid(),
    });
  }

  static LoopResult _localResult(String text, {String? error}) => LoopResult(
    reason: error == null ? 'end_turn' : 'error',
    lastText: text,
    requests: 0,
    usage: const {},
    apiDuration: Duration.zero,
    error: error,
  );

  /// Says [text] as the agent's own (a command's output): kept in the
  /// conversation unless not [store], and shown.
  void _localReply(String text, {bool store = true}) {
    final message = {
      'id': 'msg_${randomId(20)}',
      'type': 'message',
      'role': 'assistant',
      'model': '<synthetic>',
      'content': [
        {'type': 'text', 'text': text},
      ],
      'stop_reason': 'stop_sequence',
      'stop_sequence': '',
      'usage': const {'input_tokens': 0, 'output_tokens': 0},
    };
    final uuid = store
        ? session.store.append({
            'type': 'assistant',
            'message': message,
          })['uuid']
        : newUuid();
    session.emit({
      'type': 'assistant',
      'message': message,
      'parent_tool_use_id': null,
      'uuid': uuid,
    });
  }

  void _interrupt() {
    final turn = _turn;
    if (turn == null) return;
    turn.cancel.cancel('interrupted');
    _cancelHostRequests();
  }

  // --- Mentions ---------------------------------------------------------------------

  /// The files and folders `@`-mentioned in [text], read for the model.
  List<String> _mentions(String text) {
    final out = <String>[];
    final seen = <String>{};
    for (final match in RegExp(
      r'(?:^|\s)@("[^"]+"|[^\s"]+)',
    ).allMatches(text)) {
      var mention = match[1]!;
      if (mention.startsWith('"')) {
        mention = mention.substring(1, mention.length - 1);
      }
      // `path#L10-20` reads those lines.
      int? from;
      int? to;
      final lines = RegExp(r'#L(\d+)(?:-(\d+))?$').firstMatch(mention);
      if (lines != null) {
        from = int.parse(lines[1]!);
        to = lines[2] == null ? from : int.parse(lines[2]!);
        mention = mention.substring(0, lines.start);
      }
      mention = mention.replaceAll(RegExp(r'[,.;:!?)]+$'), '');
      if (mention.isEmpty) continue;
      final path = session.permissions.absolute(mention, session.cwd);
      if (!seen.add('$path#$from-$to')) continue;
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        out.add(_folderMention(path));
      } else if (type == FileSystemEntityType.file) {
        if (_fileMention(path, from, to) case final read?) out.add(read);
      }
    }
    return out;
  }

  String _folderMention(String path) {
    final entries = <String>[];
    try {
      for (final entity in Directory(
        path,
      ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
        final name = p.basename(entity.path);
        entries.add(entity is Directory ? '$name/' : name);
        if (entries.length >= 200) break;
      }
    } on FileSystemException {
      // Listed as empty.
    }
    return 'The user mentioned the folder $path, which holds '
        '(`ls ${_quote(path)}`):\n${entries.map((e) => '- $e').join('\n')}';
  }

  String? _fileMention(String path, int? from, int? to) {
    try {
      final file = File(path);
      if (file.lengthSync() > 256 * 1024) {
        return 'The user mentioned $path. It is too large to include: read it '
            'with the Read tool (offset and limit) as needed.';
      }
      final bytes = file.readAsBytesSync();
      if (looksBinary(bytes)) return null;
      final text = decodeText(bytes);
      final all = text.text.split('\n');
      final start = (from ?? 1).clamp(1, all.length);
      final end = (to ?? (start + 1999)).clamp(start, all.length);
      final shown = all.sublist(start - 1, end);
      session.mainRun.readFiles[path] = FileRecord(
        content: text.text,
        modified: file.lastModifiedSync(),
        offset: from == null ? null : start,
        limit: from == null && end == all.length ? null : end - start + 1,
      );
      final input = {
        'file_path': path,
        if (from != null) 'offset': start,
        if (from != null) 'limit': end - start + 1,
      };
      return 'The user mentioned $path, which Read gives as follows '
          '(${_json(input)}):\n${numberLines(shown, start)}';
    } on FileSystemException {
      return null;
    }
  }

  static String _quote(String path) => path.contains(' ') ? '"$path"' : path;

  static String _json(Map<String, Object?> value) => [
    '{',
    value.entries
        .map(
          (e) => '"${e.key}":${e.value is String ? '"${e.value}"' : e.value}',
        )
        .join(','),
    '}',
  ].join();

  // --- Commands ---------------------------------------------------------------------

  Future<void> _runCommand(
    _Turn turn,
    _Queued queued,
    String name,
    String args,
  ) async {
    final store = session.store;
    void typed() {
      store.append({
        'type': 'user',
        'message': {
          'role': 'user',
          'content':
              '<command-message>$name</command-message>\n'
              '<command-name>/$name</command-name>\n'
              '${args.isEmpty ? '' : '<command-args>$args</command-args>\n'}',
        },
        'uuid': queued.uuid,
      });
      session.checkpoints.begin(queued.uuid);
    }

    void reply(String text) {
      _localReply(text, store: false);
      _emitResult(turn, _localResult(text));
    }

    /// The command as a prompt to the model, once the UserPromptExpansion
    /// hooks let it.
    Future<void> prompt(String text, {String? source}) async {
      if (session.hooks.has(HookEvent.userPromptExpansion)) {
        final hook = await session.hooks.run(HookEvent.userPromptExpansion, {
          'expansion_type': name.startsWith('mcp__')
              ? 'mcp_prompt'
              : 'slash_command',
          'command_name': name,
          'command_args': args,
          'command_source': ?switch (source) {
            'user' => 'userSettings',
            'project' => 'projectSettings',
            final other => other,
          },
          'prompt': queued.text,
        }, query: name);
        if (hook.blocked || hook.stop) {
          final why = hook.blockReason.isEmpty
              ? (hook.stopReason ?? 'a hook said no')
              : hook.blockReason;
          reply('/$name was blocked: $why');
          return;
        }
        if (hook.additionalContext.isNotEmpty) {
          text =
              '$text\n\n<system-reminder>\n'
              '${hook.additionalContext.join('\n')}\n</system-reminder>';
        }
      }
      // Then, as any prompt, what the user typed goes by its hooks.
      if (session.hooks.has(HookEvent.userPromptSubmit)) {
        final hook = await session.hooks.run(HookEvent.userPromptSubmit, {
          'prompt': queued.text,
        }, cancel: turn.cancel);
        if (hook.blocked || hook.stop) {
          final reason = hook.blocked
              ? hook.blockReason
              : (hook.stopReason ?? '');
          _localReply(
            'A UserPromptSubmit hook held this prompt back:\n$reason'.trim(),
            store: false,
          );
          _emitResult(
            turn,
            _localResult('', error: 'Blocked by a hook: $reason'),
          );
          return;
        }
        final added = [...hook.additionalContext, ...hook.outputs];
        if (added.isNotEmpty) {
          text =
              '$text\n\n<system-reminder>\n${added.join('\n')}\n'
              '</system-reminder>';
        }
      }
      typed();
      final images = [
        for (final block in queued.blocks)
          if (block['type'] == 'image') block,
      ];
      final entry = store.append({
        'type': 'user',
        'message': {
          'role': 'user',
          'content': [
            ...images,
            {'type': 'text', 'text': text},
          ],
        },
        'isMeta': true,
      });
      session.emit({
        'type': 'user',
        'message': entry['message'],
        'parent_tool_use_id': null,
        'uuid': entry['uuid'],
        'isMeta': true,
      });
      await _runModel(turn);
    }

    switch (_commandName(name)) {
      case 'compact':
        if (store.apiMessages().isEmpty) {
          reply('Nothing to compact.');
          return;
        }
        typed();
        try {
          final done = await Compaction(session).compact(
            store,
            trigger: 'manual',
            instructions: args.isEmpty ? null : args,
            cancel: turn.cancel,
          );
          _emitResult(
            turn,
            _localResult(done ? 'Compacted.' : 'Nothing to compact.'),
          );
        } on Cancelled {
          _emitResult(turn, _localResult('')._interrupted);
        } on ApiError catch (error) {
          _localReply(
            'Error compacting conversation: ${error.message}',
            store: false,
          );
          _emitResult(turn, _localResult('', error: '$error'));
        }
      case 'clear':
        _clear(args);
        _emitResult(turn, _localResult(''));
      case 'context':
        reply(_contextReport());
      case 'usage':
        reply(_costReport());
      case 'goal':
        await _goalCommand(turn, queued, args, typed);
      case 'model':
        reply(await _modelCommand(args));
      case 'effort':
        reply(_effortCommand(args));
      case 'config':
        reply(await _configCommand(args));
      case 'output-style':
        reply(_outputStyleCommand(args));
      case 'autocompact':
        reply(_autocompactCommand(args));
      case 'mcp':
        reply(await _mcpCommand(args));
      case 'reload-skills':
        session.context.reloadExtensions();
        final skills = session.promptCommands.where((c) => c.isSkill).length;
        reply('Skills read again: $skills available.');
      case 'reload-plugins':
        session.context.reloadPlugins();
        await _mcpReady;
        await session.mcp.connectNew();
        reply(
          'Plugins read again: ${session.plugins.length} '
          'plugin${session.plugins.length == 1 ? '' : 's'}, '
          '${session.promptCommands.length} commands and skills, '
          '${session.agentDefinitions.length} agents.',
        );
      case 'rename':
        reply(await _rename(args));
      case 'list-agents':
        reply(_agentsReport());
      case 'recap':
        reply(await _recap());
      default:
        if (name.startsWith('mcp__')) {
          final text = await _mcpPrompt(name, args);
          if (text == null) {
            reply('Unknown command: /$name');
          } else {
            await prompt(text);
          }
          return;
        }
        final resolved = _commandName(name);
        final custom =
            SkillTool.find(session, resolved) ??
            session.promptCommands.where((c) => c.name == resolved).firstOrNull;
        if (custom == null || !custom.userInvocable) {
          reply('Unknown skill: $name');
          return;
        }
        if (custom.allowedTools.isNotEmpty) {
          session.settings.addRules(
            custom.allowedTools,
            'allow',
            SettingsSource.session,
          );
        }
        await prompt(
          custom.withBaseDir(custom.expand(args)),
          source: custom.source,
        );
    }
  }

  /// An MCP server's prompt (`/mcp__server__prompt args`), as text.
  Future<String?> _mcpPrompt(String name, String args) async {
    for (final server in session.mcp.servers.values) {
      if (!server.connected) continue;
      for (final prompt in server.prompts) {
        if ('mcp__${server.name}__${prompt['name']}' != name) continue;
        final names = [
          for (final argument in asList(prompt['arguments']))
            '${asMap(argument)['name']}',
        ];
        final values = args.isEmpty ? <String>[] : args.split(RegExp(r'\s+'));
        final arguments = <String, String>{
          for (final (i, key) in names.indexed)
            if (i < values.length)
              key: i == names.length - 1
                  ? values.sublist(i).join(' ')
                  : values[i],
        };
        final result = await session.mcp.getPrompt(
          server,
          '${prompt['name']}',
          arguments,
        );
        return [
          for (final message in asList(result['messages']))
            switch (asMap(message)['content']) {
              final Map<Object?, Object?> content
                  when content['type'] == 'text' =>
                '${content['text']}',
              final List<Object?> parts => [
                for (final part in parts)
                  if (asMap(part)['type'] == 'text') '${asMap(part)['text']}',
              ].join('\n'),
              _ => '',
            },
        ].where((t) => t.isNotEmpty).join('\n\n');
      }
    }
    return null;
  }

  String _contextReport() {
    final usage = contextUsage();
    final total = usage['totalTokens'] as int;
    final max = usage['maxTokens'] as int;
    String k(int tokens) =>
        tokens >= 1000 ? '${(tokens / 1000).toStringAsFixed(1)}k' : '$tokens';
    final rows = [
      for (final raw in asList(usage['categories']))
        '| ${asMap(raw)['name']} | ${k(asInt(asMap(raw)['tokens']) ?? 0)} | '
            '${max == 0 ? 0 : ((asInt(asMap(raw)['tokens']) ?? 0) * 100 / max).toStringAsFixed(1)}% |',
    ];
    return [
      '## Context Usage',
      '',
      '**Model:** ${session.resolvedModel}  ',
      '**Tokens:** ${k(total)} / ${k(max)} (${usage['percentage']}%)',
      '',
      '| Category | Tokens | Percentage |',
      '|----------|--------|------------|',
      ...rows,
      if (session.memory.isNotEmpty) ...[
        '',
        '### Memory Files',
        for (final file in session.memory) '- ${file.path}',
      ],
    ].join('\n');
  }

  final DateTime _startedAt = DateTime.now();

  String _costReport() {
    final elapsed = DateTime.now().difference(_startedAt);
    final lines = [
      'Total cost:            \$${session.totalCost.toStringAsFixed(4)}',
      'Total duration (wall): ${_duration(elapsed)}',
      'Usage by model:',
      for (final MapEntry(key: model, value: usage)
          in session.modelUsage.entries)
        '    $model:  ${usage['inputTokens']} input, '
            '${usage['outputTokens']} output, '
            '${usage['cacheReadInputTokens']} cache read, '
            '${usage['cacheCreationInputTokens']} cache write '
            '(\$${(usage['costUSD'] ?? 0).toStringAsFixed(4)})',
    ];
    return lines.join('\n');
  }

  static String _duration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m ${d.inSeconds % 60}s';
    }
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }

  /// `/clear`: the conversation starts again from nothing; what came
  /// before stays in the transcript, behind a boundary.
  void _clear(String name) {
    final store = session.store;
    if (store.chain.isNotEmpty) {
      store.append({
        'type': 'system',
        'subtype': 'compact_boundary',
        'content': 'Conversation cleared',
        'isMeta': false,
        'level': 'info',
        'parentUuid': null,
        'logicalParentUuid': store.leaf,
        'compactMetadata': {'trigger': 'clear', 'preTokens': 0},
      });
    }
    if (session.goal != null) _endGoal(met: false, sentinel: true);
    session.lastUsage = null;
    session.mainRun.readFiles.clear();
    if (name.trim().isNotEmpty) {
      store.note({'type': 'custom-title', 'customTitle': name.trim()});
      _titled = true;
    }
  }

  Future<String> _modelCommand(String args) async {
    if (args.isEmpty) return 'Model: ${session.resolvedModel}';
    if (await _switchModel(args) case final refused?) return refused;
    return 'Model set to ${session.resolvedModel}';
  }

  /// Switches to [model], unless a PreModelSwitch hook says not to: then
  /// why. The PostModelSwitch hooks are told.
  Future<String?> _switchModel(String model) async {
    final from = session.resolvedModel;
    final to = session.catalog.resolve(model);
    if (session.hooks.has(HookEvent.preModelSwitch)) {
      final outcome = await session.hooks.run(HookEvent.preModelSwitch, {
        'from_model': from,
        'to_model': to,
      }, query: to);
      if (outcome.blocked || outcome.stop) {
        final why = outcome.blockReason.isEmpty
            ? (outcome.stopReason ?? 'a hook said no')
            : outcome.blockReason;
        return 'Model not switched: $why';
      }
    }
    session.model = model;
    if (from != session.resolvedModel) {
      session.hooks.notify(HookEvent.postModelSwitch, {
        'from_model': from,
        'to_model': session.resolvedModel,
      }, query: session.resolvedModel);
    }
    return null;
  }

  static const _effortLevels = ['low', 'medium', 'high', 'xhigh', 'max'];

  String _effortCommand(String args) {
    final level = args.toLowerCase();
    if (level.isEmpty) {
      return 'Effort: ${_effortShown ?? 'the model\'s own'}';
    }
    if (level == 'auto') {
      session.effort = null;
      return 'Effort set to auto: ${_effortShown ?? 'the model\'s own'}';
    }
    if (!_effortLevels.contains(level)) {
      return 'Unknown effort "$args": one of ${_effortLevels.join(', ')}, '
          'or auto.';
    }
    final info = session.modelInfo;
    if (info.known && !info.supportsEffort) {
      return '${session.resolvedModel} has no effort setting.';
    }
    session.effort = level;
    return 'Effort set to $level';
  }

  /// Writes [key] to the user's settings (null removes it), and reads the
  /// settings again.
  void _saveSetting(String key, Object? value, {SettingsSource? to}) {
    final path = session.settings.fileOf(to ?? SettingsSource.user);
    if (path == null) return;
    AgentSettings.editJson(path, (json) {
      if (value == null) {
        json.remove(key);
      } else {
        json[key] = value;
      }
    });
    session.reloadSettings();
    session.hooks.notify(HookEvent.configChange, {
      'source': (to ?? SettingsSource.user).wire,
      'file_path': path,
      'changes': {key: value},
    }, query: (to ?? SettingsSource.user).wire);
  }

  Future<String> _configCommand(String args) async {
    final at = args.indexOf('=');
    if (at <= 0) {
      return 'Usage: /config key=value (the value as JSON, or as text). '
          'An empty value removes the key.';
    }
    final key = args.substring(0, at).trim();
    final raw = args.substring(at + 1).trim();
    Object? value;
    if (raw.isNotEmpty) {
      try {
        value = jsonDecode(raw);
      } on FormatException {
        value = raw;
      }
    }
    _saveSetting(key, value);
    if (key == 'model' && value is String) await _switchModel(value);
    if (key == 'effortLevel') session.effort = asText(value);
    return value == null
        ? 'Removed $key from the user settings.'
        : 'Set $key to ${jsonEncode(value)} in the user settings.';
  }

  String _outputStyleCommand(String args) {
    final styles = session.outputStyles;
    final current = asText(session.settings['outputStyle']) ?? 'default';
    if (args.isEmpty) {
      return [
        'Output styles (current: $current):',
        '- default: the agent as it is, for software work',
        for (final style in styles) '- ${style.name}: ${style.description}',
      ].join('\n');
    }
    final String name;
    if (args.toLowerCase() == 'default') {
      name = 'default';
    } else if (OutputStyle.find(styles, args) case final style?) {
      name = style.name;
    } else {
      return 'No output style "$args". Run /output-style to list them.';
    }
    _saveSetting(
      'outputStyle',
      name == 'default' ? null : name,
      to: SettingsSource.local,
    );
    return 'Output style set to $name';
  }

  String _autocompactCommand(String args) {
    final value = args.toLowerCase().replaceAll(',', '').replaceAll('_', '');
    if (value.isEmpty) {
      final asked = session.settings.autoCompactWindow;
      return 'Compacts at ${session.contextWindow} tokens '
          '(${asked == null ? 'auto: the model\'s window' : 'set'}).';
    }
    if (value == 'auto') {
      _saveSetting('autoCompactWindow', null);
      return 'Compacts by the model\'s window again '
          '(${session.contextWindow} tokens).';
    }
    final match = RegExp(r'^(\d+(?:\.\d+)?)(k|m)?$').firstMatch(value);
    if (match == null) return 'Usage: /autocompact [auto|<tokens>]';
    final tokens =
        (double.parse(match[1]!) *
                switch (match[2]) {
                  'k' => 1000,
                  'm' => 1000000,
                  _ => 1,
                })
            .round();
    _saveSetting('autoCompactWindow', tokens);
    return 'Compacts at ${session.contextWindow} tokens.';
  }

  Future<String> _mcpCommand(String args) async {
    await _mcpReady;
    final mcp = session.mcp;
    final words = args.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final action = words.firstOrNull;
    final target = words.skip(1).join(' ');
    if (action == null) {
      if (mcp.servers.isEmpty) return 'No MCP servers are set up.';
      return [
        'MCP servers:',
        for (final server in mcp.servers.values)
          '- ${server.name}: ${server.status}',
      ].join('\n');
    }
    if (!const {'reconnect', 'enable', 'disable'}.contains(action)) {
      return 'Usage: /mcp [reconnect|enable|disable [<server>|all]]';
    }
    final names = target.isEmpty || target == 'all'
        ? mcp.servers.keys.toList()
        : [target];
    if (names.isEmpty) return 'No MCP servers are set up.';
    final done = <String>[];
    for (final name in names) {
      if (!mcp.servers.containsKey(name)) return 'No MCP server "$name".';
      if (action == 'reconnect') {
        await mcp.reconnect(name);
      } else {
        await mcp.toggle(name, action == 'enable');
      }
      done.add('$name: ${mcp.servers[name]?.status ?? 'gone'}');
    }
    return done.join('\n');
  }

  Future<String> _rename(String args) async {
    var name = args.trim();
    if (name.isEmpty) {
      final conversation = transcriptText(
        session.store.apiMessages(),
        maxChars: 2000,
        withTools: false,
      );
      if (conversation.trim().isEmpty) return 'Nothing to name yet.';
      try {
        name =
            (await session.quickQuery(
                  system: titleSystem,
                  prompt: titlePrompt(conversation),
                  maxTokens: 60,
                ))
                .split('\n')
                .first
                .replaceAll(RegExp(r'''^["'#\s]+|["'.\s]+$'''), '')
                .trim();
      } on Object catch (error) {
        return 'Could not make up a name: $error';
      }
      if (name.isEmpty) return 'Could not make up a name.';
    }
    session.store.note({'type': 'custom-title', 'customTitle': name});
    _titled = true;
    return 'Conversation named: $name';
  }

  String _agentsReport() {
    final jobs = session.subagents.values;
    if (jobs.isEmpty) return 'No agents in this session yet.';
    return [
      'Agents of this session (send to one with SendMessage):',
      for (final job in jobs)
        '- ${job.agentId}: ${job.description} '
            '(${job.agent.name}, ${job.running ? 'busy' : job.status})',
    ].join('\n');
  }

  Future<String> _recap() async {
    final conversation = transcriptText(
      session.store.apiMessages(),
      maxChars: 8000,
      withTools: false,
    );
    if (conversation.trim().isEmpty) return 'Nothing has happened yet.';
    try {
      final line = await session.quickQuery(
        system: recapSystem,
        prompt: recapPrompt(conversation),
        maxTokens: 120,
      );
      return line.trim().split('\n').first;
    } on Object catch (error) {
      return 'Could not sum it up: $error';
    }
  }

  // --- The goal ---------------------------------------------------------------------

  static const _maxGoalChecks = 100;

  Future<void> _goalCommand(
    _Turn turn,
    _Queued queued,
    String args,
    void Function() typed,
  ) async {
    final current = session.goal;
    if (args.isEmpty) {
      _localReply(
        current == null ? 'No goal set' : 'Goal active: $current',
        store: false,
      );
      _emitResult(turn, _localResult(''));
      return;
    }
    if (args == 'clear' || args == 'off' || args == 'none') {
      typed();
      if (current == null) {
        _localReply('No goal set');
      } else {
        _endGoal(met: true, sentinel: true);
        _localReply('Goal cleared: $current');
      }
      _emitResult(turn, _localResult(''));
      return;
    }
    typed();
    if (current != null) _endGoal(met: true, sentinel: true);
    setGoal(args);
    _localReply('Goal set: $args');
    // The agent goes to work on it at once.
    final entry = session.store.append({
      'type': 'user',
      'message': {
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text':
                'The user set this goal for the session; work toward it '
                'now:\n\n$args',
          },
        ],
      },
      'isMeta': true,
    });
    session.emit({
      'type': 'user',
      'message': entry['message'],
      'parent_tool_use_id': null,
      'uuid': entry['uuid'],
      'isMeta': true,
    });
    await _runModel(turn);
  }

  /// Sets [condition] as the session's goal: a Stop hook of the session's
  /// that checks it each time the agent would stop.
  void setGoal(String condition) {
    session.goal = condition;
    session.goalSetAt = DateTime.now();
    session.goalChecks = 0;
    session.goalTokensAtStart = _tokensSoFar;
    session.hooks.sessionHooks
      ..removeWhere(
        (hook) => hook.source == 'sessionHook' && hook.event == HookEvent.stop,
      )
      ..add(
        Hook(
          event: HookEvent.stop,
          type: 'prompt',
          text: condition,
          source: 'sessionHook',
          evaluate: _checkGoal,
        ),
      );
    _goalRecord({'condition': condition, 'met': false, 'sentinel': true});
  }

  int get _tokensSoFar => session.modelUsage.values.fold(
    0,
    (sum, usage) =>
        sum +
        (usage['inputTokens'] ?? 0).toInt() +
        (usage['outputTokens'] ?? 0).toInt() +
        (usage['cacheReadInputTokens'] ?? 0).toInt() +
        (usage['cacheCreationInputTokens'] ?? 0).toInt(),
  );

  void _goalRecord(Map<String, Object?> record) {
    session.store.append({
      'type': 'attachment',
      'attachment': {'type': 'goal_status', ...record},
    });
  }

  /// Ends the goal: met (or cleared, as a [sentinel]), or given up on.
  void _endGoal({
    required bool met,
    bool sentinel = false,
    bool failed = false,
    String? reason,
  }) {
    final condition = session.goal;
    if (condition == null) return;
    session.hooks.sessionHooks.removeWhere(
      (hook) => hook.source == 'sessionHook' && hook.event == HookEvent.stop,
    );
    _goalRecord({
      'condition': condition,
      'met': met,
      if (sentinel) 'sentinel': true,
      if (failed) 'failed': true,
      'reason': ?reason,
      if (!sentinel) ...{
        'iterations': session.goalChecks,
        if (session.goalSetAt case final at?)
          'durationMs': DateTime.now().difference(at).inMilliseconds,
        'tokens': _tokensSoFar - session.goalTokensAtStart,
      },
    });
    session.goal = null;
    session.goalSetAt = null;
  }

  Future<HookResult> _checkGoal(
    Map<String, Object?> input,
    CancelToken cancel,
  ) async {
    final condition = session.goal;
    if (condition == null) return const HookResult();
    session.goalChecks++;
    final String answer;
    try {
      answer = await session.quickQuery(
        system: goalCheckSystem,
        prompt: goalCheckPrompt(
          condition,
          transcriptText(session.store.apiMessages(), maxChars: 40000),
        ),
        cancel: cancel,
        maxTokens: 600,
      );
    } on Cancelled {
      rethrow;
    } on Object catch (error) {
      return HookResult(error: 'The goal could not be checked: $error');
    }
    final verdict = extractJson(answer);
    final met = verdict['ok'] == true || verdict['met'] == true;
    final reason =
        asText(verdict['reason']) ??
        (met ? 'The goal is met.' : 'The goal is not met yet.');
    if (met) {
      _endGoal(met: true, reason: reason);
      return const HookResult();
    }
    if (session.goalChecks >= _maxGoalChecks) {
      _endGoal(met: false, failed: true, reason: reason);
      return const HookResult();
    }
    _goalRecord({'condition': condition, 'met': false, 'reason': reason});
    return HookResult(blocked: true, reason: reason);
  }

  /// Takes up the goal the session had when it was left, as kept.
  void _restoreGoal() {
    String? active;
    for (final entry in session.store.chain) {
      if (entry['type'] != 'attachment') continue;
      final record = asMap(entry['attachment']);
      if (record['type'] != 'goal_status') continue;
      final condition = asText(record['condition']);
      if (condition == null) continue;
      if (record['sentinel'] == true) {
        active = record['met'] == true ? null : condition;
      } else if (record['met'] == true || record['failed'] == true) {
        active = null;
      }
    }
    if (active == null) return;
    session.goal = active;
    session.goalSetAt = DateTime.now();
    session.hooks.sessionHooks.add(
      Hook(
        event: HookEvent.stop,
        type: 'prompt',
        text: active,
        source: 'sessionHook',
        evaluate: _checkGoal,
      ),
    );
  }

  // --- Rewinding --------------------------------------------------------------------

  Future<Map<String, Object?>> _rewindConversation(
    Map<String, Object?> request,
  ) async {
    final target = asString(request['target_message_uuid']);
    if (target == null) throw StateError('target_message_uuid is required');
    if (_turn case final turn?) {
      if (request['interrupt_if_running'] != true) {
        return {'rewound': false, 'error': 'A turn is running'};
      }
      _interrupt();
      while (identical(_turn, turn)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
    final store = session.store;
    if (!store.chain.any((entry) => entry['uuid'] == target)) {
      return {'rewound': false, 'error': 'Message not found: $target'};
    }
    store.rewindTo(target);
    // Kept as the conversation's branch from here: the next message
    // follows the one before the target.
    session.lastUsage = null;
    return {'rewound': true};
  }

  // --- Background -------------------------------------------------------------------

  /// Sends the work of the call [toolUseId] (all, when null) running in
  /// the foreground to the background. Returns the tasks sent.
  List<String> _toBackground(String? toolUseId) {
    final sent = <String>[];
    final tasks = session.tasks;
    for (final command in [...tasks.foreground.values]) {
      if (toolUseId != null && command.toolUseId != toolUseId) continue;
      sent.add(tasks.adoptShell(command).id);
    }
    for (final task in [...tasks.running]) {
      if (task.isShell || task.backgrounded) continue;
      if (toolUseId != null && task.toolUseId != toolUseId) continue;
      task.backgrounded = true;
      if (!task.toBackground.isCompleted) task.toBackground.complete();
      sent.add(task.id);
    }
    if (sent.isNotEmpty) {
      session.emitSystem('background_tasks_changed', {
        'tasks': [
          for (final task in tasks.running)
            if (task.backgrounded) {'task_id': task.id},
        ],
      });
    }
    return sent;
  }

  /// A subagent sent the main conversation [text]: taken up within the
  /// turn running, else in a turn of its own.
  void _agentMessage(String from, String text) {
    final queued = _Queued({
      'type': 'user',
      'message': {'role': 'user', 'content': text},
      'uuid': newUuid(),
      'priority': 'next',
    })..own = true;
    _enqueue(queued);
  }

  /// A scheduled prompt came due: sent as the user's, once no turn runs.
  void _scheduledPrompt(String prompt) {
    _enqueue(
      _Queued({
        'type': 'user',
        'message': {'role': 'user', 'content': prompt},
        'uuid': newUuid(),
        'priority': 'later',
      }),
    );
  }

  /// A background task ended: the model is told, in a turn of its own if
  /// none runs.
  void _taskEnded(BackgroundTask task, String notification) {
    final queued = _Queued({
      'type': 'user',
      'message': {'role': 'user', 'content': notification},
      'uuid': newUuid(),
      'priority': 'later',
    })..own = true;
    _enqueue(queued);
  }

  // --- Errands ----------------------------------------------------------------------

  Future<void> _nameSession(String prompt) async {
    try {
      final title = await session.quickQuery(
        system: titleSystem,
        prompt: titlePrompt(
          prompt.length > 2000 ? prompt.substring(0, 2000) : prompt,
        ),
        maxTokens: 60,
      );
      final cleaned = title
          .split('\n')
          .first
          .replaceAll(RegExp(r'''^["'#\s]+|["'.\s]+$'''), '')
          .trim();
      if (cleaned.isEmpty || session.store.title != null) return;
      session.store.note({'type': 'ai-title', 'aiTitle': cleaned});
    } on Object {
      // Untitled: the first prompt names it.
    }
  }

  Future<void> _suggest() async {
    try {
      final conversation = transcriptText(
        session.store.apiMessages(),
        maxChars: 6000,
        withTools: false,
      );
      final suggestion = await session.quickQuery(
        system: suggestionSystem,
        prompt: suggestionPrompt(conversation),
        maxTokens: 60,
      );
      if (_turn != null || _queue.isNotEmpty || _closed) return;
      final text = suggestion.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
      if (text.isEmpty || text.length > 200) return;
      session.emit({
        'type': 'prompt_suggestion',
        'suggestion': text,
        'uuid': newUuid(),
      });
    } on Object {
      // No suggestion.
    }
  }
}

extension on LoopResult {
  LoopResult get _interrupted => LoopResult(
    reason: 'interrupted',
    lastText: lastText,
    requests: requests,
    usage: usage,
    apiDuration: apiDuration,
  );
}
