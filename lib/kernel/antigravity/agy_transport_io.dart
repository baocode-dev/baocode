import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_agent/bao_agent.dart'
    show AgentPaths, ForeignBrief, SessionStore, newUuid;

import '../acp/acp_connection.dart';
import '../acp/mcp_endpoint.dart';
import '../acp/mcp_http_server.dart';
import '../claude_code/claude_code_transport.dart';
import '../claude_code/claude_environment.dart';
import '../claude_code/control_channel.dart';
import 'acp_to_claude.dart';
import 'agy_context.dart';
import 'agy_runtime.dart';
import 'handoff.dart';

/// A session on Google's Antigravity CLI (`agy acp`), spoken to as Claude
/// Code is: what agy does turned into what the CLI prints (stream-json),
/// what the kernel asks into ACP. The conversation is kept as Claude Code
/// keeps its own (the session's jsonl, its tools as Claude Code's), so the
/// chat reads it back as any, and a model of another upstream goes on with
/// it; agy's own session is noted beside it (`antigravity-session`), with
/// the last message it saw: what came after, it is told as it takes the
/// conversation up again ([handoffReminder]).
///
/// agy is started on the first message, not as the conversation opens, and
/// ended once idle a while; started again, it resumes its session.
class AgyTransport implements ClaudeCodeTransport {
  AgyTransport._(this.launch, this._runtime, this._store, this._environment) {
    _mode = launch.permissionMode ?? 'default';
    _model = launch.model;
    _effort = launch.effort;
    _sdkServers = [...launch.sdkServers];
    if (_syncLine case final line?) {
      _agySession = line.session;
      _synced = line.synced;
      _handedOff = line.handedOff;
    }
    _running[_store.sessionId] = this;
  }

  /// Those open, by the conversation's session id.
  static final Map<String, AgyTransport> _running = {};

  /// Deletes what agy keeps of the conversation [sessionId] (Claude Code's
  /// session, kept under [configDir]), its process ended first: each
  /// session of agy's its file notes. The file itself is left to delete.
  static Future<void> forget(
    String sessionId,
    String configDir, {
    AgyRuntime? runtime,
  }) async {
    await _running[sessionId]?._end();
    final ids = <String>{};
    final projects = Directory('$configDir/projects');
    if (projects.existsSync()) {
      for (final project in projects.listSync().whereType<Directory>()) {
        final file = File('${project.path}/$sessionId.jsonl');
        if (!file.existsSync()) continue;
        for (final line in await file.readAsLines()) {
          if (!line.contains('"$syncType"')) continue;
          try {
            if (jsonDecode(line) case {
              'type': syncType,
              'agySessionId': final String id,
            }) {
              ids.add(id);
            }
          } on FormatException {
            // Cut short: no id in it.
          }
        }
      }
    }
    runtime ??= AgyRuntime.local;
    for (final id in ids) {
      await runtime.deleteSession(id);
    }
  }

  /// Closes it, and waits a while for agy to be gone: its files are let
  /// go of then.
  Future<void> _end() async {
    final gone = _connection?.exited;
    close();
    try {
      await gone?.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Deleted all the same: what it holds goes once it ends.
    }
  }

  final ClaudeLaunch launch;
  final AgyRuntime _runtime;
  final SessionStore _store;
  final Map<String, String> _environment;

  static Future<ClaudeCodeTransport> start(
    ClaudeLaunch launch, {
    AgyRuntime? runtime,
  }) async {
    if (!Directory(launch.cwd).existsSync()) {
      throw ClaudeFolderGone(launch.cwd);
    }
    runtime ??= AgyRuntime.local;
    if (await runtime.version() == null) {
      throw const ClaudeUnavailable(
        'Antigravity is not installed',
        detail: 'Install it in Settings → Models → Antigravity.',
      );
    }
    final base = await ClaudeEnvironment.of();
    final environment = {...base, ...ClaudeEnvironment.stateDirectory(base)};
    final id = launch.resume ?? newUuid();
    final file = AgentPaths.from(environment).sessionFile(launch.cwd, id);
    final store = launch.resume != null && File(file).existsSync()
        ? SessionStore.resume(
            sessionId: id,
            cwd: launch.cwd,
            file: file,
            persist: launch.persist,
          )
        : SessionStore(
            sessionId: id,
            cwd: launch.cwd,
            file: launch.persist ? file : null,
          );
    // Booted while the user writes, for the first message to go at once.
    runtime.warm();
    return AgyTransport._(launch, runtime, store, environment);
  }

  /// What the kernel reads: asynchronous, as a process's output is.
  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast();

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  @override
  Future<void> get exited => _out.done;

  void _emit(Map<String, Object?> message) {
    if (!_out.isClosed) {
      _out.add({...message, 'session_id': _store.sessionId});
    }
  }

  /// What this asks the kernel: tools' approvals, the edit watch's hooks,
  /// the app's MCP servers.
  late final ControlChannel _kernel = ControlChannel(_emit);

  late String _mode;
  String? _model;
  String? _effort;
  List<String> _sdkServers = const [];

  /// The hooks the kernel has called back (`initialize`'s), by event.
  Map<String, Object?> _hooks = const {};

  // --- What the kernel says ------------------------------------------------------

  @override
  void write(Map<String, Object?> message) {
    if (_closed) return;
    switch (message['type']) {
      case 'control_request':
        unawaited(
          _control(
            message['request_id'] as String,
            (message['request'] as Map).cast<String, Object?>(),
          ),
        );
      case 'control_response':
        _kernel.receive(message);
      case 'user':
        _queue.add(message);
        _next();
    }
  }

  void _respond(String id, [Map<String, Object?> payload = const {}]) => _emit({
    'type': 'control_response',
    'response': {'subtype': 'success', 'request_id': id, 'response': payload},
  });

  void _refuse(String id, String error) => _emit({
    'type': 'control_response',
    'response': {'subtype': 'error', 'request_id': id, 'error': error},
  });

  Future<void> _control(String id, Map<String, Object?> request) async {
    switch (request['subtype']) {
      case 'initialize':
        _hooks = (request['hooks'] as Map? ?? const {}).cast<String, Object?>();
        if (request['sdkMcpServers'] case final List<Object?> servers) {
          _sdkServers = [for (final name in servers) '$name'];
        }
        _respond(id, {
          'commands': _commandList,
          'models': const [],
          'current_permission_mode': _mode,
        });
      case 'set_model':
        _model = switch (request['model']) {
          final String model when model.isNotEmpty && model != 'default' =>
            model,
          _ => _model,
        };
        _respond(id);
        unawaited(_applyOption('model', _model));
      case 'apply_flag_settings':
        final settings = request['settings'] as Map? ?? const {};
        if (settings['effortLevel'] case final String effort) {
          _effort = effort;
          unawaited(_applyOption('thought_level', _effort));
        }
        _respond(id);
      case 'get_settings':
        _respond(id, {
          'applied': {'model': _model, 'effort': _effort},
        });
      case 'set_permission_mode':
        _mode = request['mode'] as String? ?? _mode;
        _respond(id, {'mode': _mode});
      case 'interrupt':
        _respond(id);
        _interrupt();
      case 'rename_session':
        final title = '${request['title'] ?? ''}'.trim();
        if (title.isEmpty) {
          _refuse(id, 'A title is required');
          return;
        }
        _store.note({'type': 'custom-title', 'customTitle': title});
        _respond(id);
        _emit({
          'type': 'system',
          'subtype': 'session_title_changed',
          'title': title,
        });
      case 'get_context_usage':
        _respond(
          id,
          agyContextUsage(
            used: _used ?? 0,
            size: _size ?? launch.autocompact ?? 0,
            brief: _toldBrief ??= _brief(),
            chain: _store.chain,
            handedOff: _handedOff,
          ),
        );
      case 'rewind_conversation':
        _respond(id, await _rewind(request));
      case 'mcp_status':
        _respond(id, {'mcpServers': const []});
      case 'cancel_async_message':
        final uuid = request['message_uuid'];
        final queued = _queue.indexWhere((m) => m['uuid'] == uuid);
        if (queued >= 0) {
          _queue.removeAt(queued);
          _emit({
            'type': 'command_lifecycle',
            'command_uuid': uuid,
            'state': 'cancelled',
          });
        }
        _respond(id, {'cancelled': queued >= 0});
      default:
        _refuse(id, 'Not supported on Antigravity');
    }
  }

  // --- Turns -----------------------------------------------------------------------

  /// Messages waiting for the turn running to end: agy takes one prompt
  /// at a time.
  final List<Map<String, Object?>> _queue = [];
  _Turn? _turn;

  void _next() {
    if (_turn != null || _queue.isEmpty || _closed) return;
    unawaited(_run(_queue.removeAt(0)));
  }

  Future<void> _run(Map<String, Object?> message) async {
    final uuid = message['uuid'] as String? ?? newUuid();
    final turn = _turn = _Turn(uuid);
    _idleTimer?.cancel();
    final content = ((message['message'] as Map?)?['content'] as List? ?? [])
        .whereType<Map<Object?, Object?>>()
        .map((block) => block.cast<String, Object?>())
        .toList();
    _emit({
      'type': 'system',
      'subtype': 'init',
      'cwd': launch.cwd,
      'model': _model,
      'effort': _effort,
      'permissionMode': _mode,
      'tools': const <String>[],
    });
    _emit({
      'type': 'system',
      'subtype': 'session_state_changed',
      'state': 'running',
    });
    // What agy has not seen: the conversation as it was before this.
    final before = [..._store.chain];
    final entry = _store.append({
      'type': 'user',
      'message': {'role': 'user', 'content': content},
      'uuid': uuid,
    });
    _emit({
      'type': 'user',
      'message': entry['message'],
      'parent_tool_use_id': null,
      'uuid': uuid,
      'isReplay': true,
      'timestamp': entry['timestamp'],
    });
    _emit({
      'type': 'command_lifecycle',
      'command_uuid': uuid,
      'state': 'started',
    });
    String? error;
    String? stopReason;
    final watchdog = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_asked.isNotEmpty ||
          DateTime.now().difference(turn.heard) < stallAfter) {
        return;
      }
      turn.stalled = true;
      _interrupt();
      _dropConnection();
    });
    try {
      final session = await _session();
      final handoff = handoffReminder(before, syncedUuid: _synced);
      if (handoff != null) _handedOff += agyTokens(handoff);
      final response = await _connection!.request('session/prompt', {
        'sessionId': session,
        'prompt': [
          if (handoff != null) {'type': 'text', 'text': handoff},
          ..._acpPrompt(content),
        ],
      });
      stopReason = response['stopReason'] as String?;
      _usageOf(response['usage']);
    } on AgyUnavailable catch (unavailable) {
      error = unavailable.signIn
          ? 'Sign in to Antigravity in Settings → Models → Antigravity.'
          : '$unavailable';
    } on AcpError catch (failure) {
      error = turn.stalled
          ? 'Antigravity stopped answering, and was restarted.'
          : failure.closed && turn.cancelled
          ? null
          : _said(failure.message, failure.data);
      if (failure.closed) _dropConnection();
    } finally {
      watchdog.cancel();
    }
    _closeOpen();
    final interrupted = turn.cancelled || stopReason == 'cancelled';
    _settleCalls(interrupted: interrupted || error != null);
    if (interrupted) {
      _appendUser('[Request interrupted by user]');
    }
    if (error == null && _agySession != null) {
      _synced = _store.leaf;
      _store.note({
        'type': syncType,
        'agySessionId': _agySession,
        'syncedUuid': _synced,
        'handedOff': _handedOff,
      });
    }
    _turn = null;
    final size = _size;
    _emit({
      'type': 'result',
      'subtype': interrupted || error != null
          ? 'error_during_execution'
          : 'success',
      'is_error': error != null,
      'result': ?error,
      'duration_ms': DateTime.now().difference(turn.started).inMilliseconds,
      'usage': {
        'input_tokens': turn.inputTokens ?? _used ?? 0,
        'output_tokens': turn.outputTokens ?? 0,
        'cache_read_input_tokens': turn.cacheRead,
        'cache_creation_input_tokens': turn.cacheWrite,
        'reasoning_tokens': turn.thought,
      },
      if (_model case final model?)
        'modelUsage': {
          model: {'contextWindow': ?size},
        },
    });
    _emit({
      'type': 'system',
      'subtype': 'session_state_changed',
      'state': 'idle',
    });
    _idleSoon();
    _next();
  }

  /// [content] (Claude's blocks) as ACP's.
  static List<Map<String, Object?>> _acpPrompt(
    List<Map<String, Object?>> content,
  ) => [
    for (final block in content)
      switch (block) {
        {'type': 'text', 'text': final String text} => {
          'type': 'text',
          'text': text,
        },
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': final String type,
            'data': final String data,
          },
        } =>
          {'type': 'image', 'mimeType': type, 'data': data},
        _ => null,
      },
  ].nonNulls.toList();

  static String _said(String message, Object? data) => switch (data) {
    final String detail when detail.isNotEmpty => '$message: $detail',
    {'details': final String detail} when detail.isNotEmpty =>
      '$message: $detail',
    _ => message,
  };

  /// How long a turn goes without a word from agy before it is taken to
  /// hang (a known fault of agy's: no word after a tool is approved, and
  /// a cancel not heard): Google's models take a minute or two at times,
  /// retrying when busy, saying nothing meanwhile.
  static const stallAfter = Duration(minutes: 8);

  void _interrupt() {
    final turn = _turn;
    if (turn == null || turn.cancelled) return;
    turn.cancelled = true;
    for (final asked in [..._asked.values]) {
      if (!asked.isCompleted) asked.complete(null);
    }
    _asked.clear();
    if (_agySession case final session?) {
      _connection?.notify('session/cancel', {'sessionId': session});
    }
  }

  Future<Map<String, Object?>> _rewind(Map<String, Object?> request) async {
    final target = request['target_message_uuid'] as String?;
    if (target == null) return {'rewound': false, 'error': 'No message given'};
    if (_turn case final turn?) {
      if (request['interrupt_if_running'] != true) {
        return {'rewound': false, 'error': 'A turn is running'};
      }
      _interrupt();
      while (identical(_turn, turn)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
    if (!_store.rewindTo(target)) {
      return {'rewound': false, 'error': 'Message not found: $target'};
    }
    // agy saw what is rewound: it starts over, told the rest.
    if (_synced != null && !_onChain(_synced!)) {
      _synced = null;
      _agySession = null;
      _handedOff = 0;
    }
    return {'rewound': true};
  }

  bool _onChain(String uuid) => _store.chain.any((e) => e['uuid'] == uuid);

  // --- agy -------------------------------------------------------------------------

  /// How the session is noted beside the conversation.
  static const syncType = 'antigravity-session';

  /// The last note of agy's session in the conversation's file.
  ({String session, String? synced, int handedOff})? get _syncLine {
    for (final entry in _store.extras.reversed) {
      if (entry case {'type': syncType, 'agySessionId': final String id}) {
        return (
          session: id,
          synced: entry['syncedUuid'] as String?,
          handedOff: (entry['handedOff'] as num?)?.toInt() ?? 0,
        );
      }
    }
    return null;
  }

  AcpConnection? _connection;
  Future<String>? _starting;

  /// agy's session; the last message of the conversation it saw.
  String? _agySession;
  String? _synced;

  /// What its session was told of turns on other models, in tokens as
  /// estimated ([agyTokens]): for what fills its context to be told.
  int _handedOff = 0;

  /// The instructions and skills its session was told as it started; the
  /// user's as they are now, for one resumed.
  ForeignBrief? _toldBrief;

  /// Whether [_agySession] is open on [_connection].
  bool _open = false;

  final List<McpEndpoint> _endpoints = [];

  /// agy's session, on an agy started (or resumed) for it.
  Future<String> _session() {
    if (_open && _connection?.done == false && _agySession != null) {
      return Future.value(_agySession);
    }
    return _starting ??= _startSession().whenComplete(() => _starting = null);
  }

  Future<String> _startSession() async {
    _dropConnection();
    final transport = await _runtime.start(launch.cwd);
    final connection = _connection = AcpConnection(
      transport,
      onRequest: _agentRequest,
      onNotification: _notification,
    );
    unawaited(
      connection.exited.then((_) {
        if (identical(_connection, connection)) _dropConnection();
      }),
    );
    await connection.request('initialize', agyHello);
    final base = <String, Object?>{
      'cwd': launch.cwd,
      'mcpServers': await _mcpServers(),
      if (launch.directories.isNotEmpty)
        'additionalDirectories': launch.directories,
    };
    var resumed = false;
    if ((_agySession, _synced) case (final id?, final synced?)
        when _onChain(synced)) {
      try {
        await connection.request('session/resume', {...base, 'sessionId': id});
        resumed = true;
      } on AcpError catch (error) {
        if (error.closed) rethrow;
        // Gone (deleted, another account's): a new one, told all of it.
      }
    }
    if (!resumed) {
      final started = await connection.request('session/new', {
        ...base,
        '_meta': {
          'antigravity': {
            'systemPrompt': {'append': _appendedPrompt()},
          },
        },
      });
      _agySession = started['sessionId'] as String?;
      _synced = null;
      _handedOff = 0;
      _commandsOf(started);
      if (_agySession == null) {
        throw const AcpError(-32603, 'Antigravity started no session');
      }
    }
    _open = true;
    await _applyOption('model', _model);
    await _applyOption('thought_level', _effort);
    return _agySession!;
  }

  /// What agy is told past its own prompt, as the session starts: how the
  /// chat cites code and draws Markdown, the workspace's instructions, and
  /// the user's rules and skills as Claude Code has them.
  String _appendedPrompt() => [
    ClaudeLaunch.appendedSystemPrompt,
    if (launch.instructions case final text? when text.isNotEmpty) text,
    ?(_toldBrief = _brief()).text,
    'Notes from BaoCode, the app you run in, come in <system-reminder> '
        'tags in the user\'s messages: take them in, without mentioning '
        'them to the user. One may tell you what was said and done in this '
        'conversation with another model while you were not in it.',
  ].join('\n\n');

  ForeignBrief _brief() {
    try {
      return ForeignBrief.of(
        environment: _environment,
        cwd: launch.cwd,
        additional: launch.directories,
        readAdditional: launch.folderInstructions,
        flagSettings: launch.settings,
      );
    } on Object {
      return const ForeignBrief();
    }
  }

  Future<void> _applyOption(String id, String? value) async {
    final connection = _connection;
    final session = _agySession;
    if (value == null || connection == null || session == null || !_open) {
      return;
    }
    try {
      await connection.request('session/set_config_option', {
        'sessionId': session,
        'configId': id,
        'value': value,
      });
    } on AcpError {
      // Not one agy has (a level the model lacks): its own stays.
    }
  }

  /// The app's own MCP servers, served to agy over HTTP on this machine:
  /// each message to them asked of the kernel (`mcp_message`), as the
  /// CLI asks it.
  Future<List<Map<String, Object?>>> _mcpServers() async {
    if (_endpoints.isEmpty) {
      for (final name in _sdkServers) {
        _endpoints.add(
          await McpHttpServer.start((message) => _mcp(name, message)),
        );
      }
    }
    return [
      for (final (i, endpoint) in _endpoints.indexed)
        {
          'type': 'http',
          'name': _sdkServers[i],
          'url': '${endpoint.url}',
          'headers': [
            for (final MapEntry(:key, :value) in endpoint.headers.entries)
              {'name': key, 'value': value},
          ],
        },
    ];
  }

  Future<Map<String, Object?>?> _mcp(
    String server,
    Map<String, Object?> message,
  ) async {
    final response = await _kernel.request('mcp_message', {
      'server_name': server,
      'message': message,
    }, const Duration(hours: 1));
    if (!message.containsKey('id')) return null;
    return (response['mcp_response'] as Map?)?.cast<String, Object?>();
  }

  /// Ends agy's process: the session stays agy's, resumed on the next.
  void _dropConnection() {
    final connection = _connection;
    _connection = null;
    _open = false;
    connection?.close();
  }

  // --- Ended when idle -------------------------------------------------------------

  Timer? _idleTimer;

  /// How long agy is kept once a turn is over: its process is big.
  static const idleFor = Duration(minutes: 10);

  void _idleSoon() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleFor, () {
      // Commands it left running in the background keep it.
      if (_turn != null || _calls.values.any((c) => c.acp.running)) {
        _idleSoon();
        return;
      }
      _dropConnection();
    });
  }

  // --- What agy asks ---------------------------------------------------------------

  final Map<String, Completer<Map<String, Object?>?>> _asked = {};

  /// Rules the user gave to allow a tool from now on ("always allow").
  final List<({String tool, String? content})> _allowed = [];

  Future<Object?> _agentRequest(
    String method,
    Map<String, Object?> params,
  ) async {
    if (method != 'session/request_permission') {
      throw AcpError(-32601, 'Method not found: $method');
    }
    final options = [
      for (final option in params['options'] as List? ?? const [])
        if (option is Map) option.cast<String, Object?>(),
    ];
    String? optionOf(String kind) => options
        .where((option) => option['kind'] == kind)
        .map((option) => option['optionId'] as String?)
        .firstOrNull;
    final allow = optionOf('allow_once') ?? optionOf('allow_always');
    final reject = optionOf('reject_once') ?? optionOf('reject_always');
    Map<String, Object?> selected(String? id) => id == null
        ? const {
            'outcome': {'outcome': 'cancelled'},
          }
        : {
            'outcome': {'outcome': 'selected', 'optionId': id},
          };
    final update = (params['toolCall'] as Map?)?.cast<String, Object?>();
    final call = update == null ? null : _toolCall(update);
    if (call == null || _turn?.cancelled != false) return selected(null);
    _closeOpen();
    _tell(call);
    final allowed = await _allows(call);
    if (!allowed) return selected(reject);
    // An edit allowed: the edit watch told before it lands.
    if (call.edits && !call.preHooked) {
      call.preHooked = true;
      await _hook('PreToolUse', call);
    }
    return selected(allow);
  }

  /// Whether [call] may go ahead: as the mode says, else as the user does.
  Future<bool> _allows(_Call call) async {
    final input = call.input;
    if (_mode == 'bypassPermissions') return true;
    if (call.edits && (_mode == 'acceptEdits' || _mode == 'auto')) return true;
    if (call.acp.kind case 'read' || 'search' || 'fetch') return true;
    final command = input['command'] as String?;
    for (final rule in _allowed) {
      if (rule.tool != call.name) continue;
      final content = rule.content;
      if (content == null) return true;
      if (command == null) continue;
      if (content == command) return true;
      if (content.endsWith(':*') &&
          command.startsWith(content.substring(0, content.length - 2))) {
        return true;
      }
    }
    final requestId = 'agy-perm-${++_requests}';
    final asked = _asked[requestId] = Completer();
    unawaited(
      _kernel
          .request('can_use_tool', {
            'tool_name': call.name,
            'input': input,
            'tool_use_id': call.claudeId,
            'permission_suggestions': [
              if (call.name == 'Bash' && command != null)
                {
                  'type': 'addRules',
                  'rules': [
                    {'toolName': 'Bash', 'ruleContent': command},
                  ],
                  'behavior': 'allow',
                  'destination': 'session',
                }
              else if (call.edits)
                {
                  'type': 'setMode',
                  'mode': 'acceptEdits',
                  'destination': 'session',
                },
            ],
          }, const Duration(days: 1))
          .then<void>(
            (answer) {
              if (!asked.isCompleted) asked.complete(answer);
            },
            onError: (Object _) {
              if (!asked.isCompleted) asked.complete(null);
            },
          ),
    );
    final answer = await asked.future;
    _asked.remove(requestId);
    if (answer == null || answer['behavior'] != 'allow') {
      if (call.edits) await _hook('PermissionDenied', call);
      return false;
    }
    for (final raw in answer['updatedPermissions'] as List? ?? const []) {
      if (raw is! Map) continue;
      switch (raw['type']) {
        case 'setMode':
          if (raw['mode'] case final String mode) _mode = mode;
        case 'addRules' || 'replaceRules' when raw['behavior'] == 'allow':
          for (final rule in raw['rules'] as List? ?? const []) {
            if (rule case {'toolName': final String tool}) {
              _allowed.add((
                tool: tool,
                content: rule['ruleContent'] as String?,
              ));
            }
          }
      }
    }
    return true;
  }

  int _requests = 0;

  /// Calls back the kernel's hooks of [event] for [call], as Claude Code
  /// does, each once the one before is answered.
  Future<void> _hook(String event, _Call call) async {
    for (final raw in _hooks[event] as List? ?? const []) {
      final matcher = (raw as Map).cast<String, Object?>();
      final pattern = matcher['matcher'] as String? ?? '';
      if (pattern.isNotEmpty &&
          !RegExp('^(?:$pattern)\$').hasMatch(call.name)) {
        continue;
      }
      for (final callback in matcher['hookCallbackIds'] as List? ?? const []) {
        try {
          await _kernel.request('hook_callback', {
            'callback_id': callback,
            'input': {
              'hook_event_name': event,
              'tool_name': call.name,
              'tool_input': call.input,
              'tool_use_id': call.claudeId,
            },
            'tool_use_id': call.claudeId,
          }, const Duration(seconds: 15));
        } on ControlError {
          // The edit goes on all the same.
        }
      }
    }
  }

  // --- What agy tells ---------------------------------------------------------------

  void _notification(String method, Map<String, Object?> params) {
    if (method != 'session/update') return;
    if (params['sessionId'] != _agySession) return;
    final update = (params['update'] as Map?)?.cast<String, Object?>();
    if (update == null) return;
    _turn?.heard = DateTime.now();
    switch (update['sessionUpdate']) {
      case 'agent_message_chunk':
        _chunk(_BlockKind.text, _text(update['content']));
      case 'agent_thought_chunk':
        _chunk(_BlockKind.thinking, _text(update['content']));
      case 'tool_call' || 'tool_call_update':
        _closeOpen();
        final call = _toolCall(update);
        if (call != null) _progress(call);
      case 'plan':
        _closeOpen();
        _todos(update);
      case 'usage_update':
        _usageOf(update);
      case 'session_info_update':
        if (update['title'] case final String said) {
          final title = withoutReminders(said);
          if (title.isNotEmpty) {
            _store.note({'type': 'ai-title', 'aiTitle': title});
            _emit({
              'type': 'system',
              'subtype': 'session_title_changed',
              'title': title,
            });
          }
        }
      case 'available_commands_update':
        final before = jsonEncode(_commandList);
        _commandsOf(update);
        // Told again as each session starts: the same, as a rule.
        if (jsonEncode(_commandList) == before) return;
        _emit({
          'type': 'system',
          'subtype': 'commands_changed',
          'commands': _commandList,
        });
    }
  }

  static String _text(Object? content) => switch (content) {
    {'type': 'text', 'text': final String text} => text,
    _ => '',
  };

  int? _used;
  int? _size;

  void _usageOf(Object? usage) {
    if (usage is! Map) return;
    if (usage['used'] case final num used) _used = used.toInt();
    if (usage['size'] case final num size when size > 0) {
      _size = size.toInt();
    }
    final turn = _turn;
    if (turn == null) return;
    if (usage['inputTokens'] case final num input) {
      turn.inputTokens = input.toInt();
    }
    if (usage['outputTokens'] case final num output) {
      turn.outputTokens = output.toInt();
    }
    if (usage['cachedReadTokens'] case final num read) {
      turn.cacheRead = read.toInt();
    }
    if (usage['cachedWriteTokens'] case final num written) {
      turn.cacheWrite = written.toInt();
    }
    if (usage['thoughtTokens'] case final num thought) {
      turn.thought = thought.toInt();
    }
  }

  List<Map<String, Object?>> _commands = const [];

  List<Map<String, Object?>> get _commandList => [
    for (final command in _commands)
      {
        'name': command['name'],
        'description': '${command['description'] ?? ''}',
        'argumentHint': switch (command['input']) {
          {'hint': final String hint} => hint,
          _ => '',
        },
      },
  ];

  void _commandsOf(Map<String, Object?> said) {
    if (said['availableCommands'] case final List<Object?> commands) {
      _commands = [
        for (final command in commands)
          if (command case {'name': final String _}) command.cast(),
      ];
    }
  }

  // --- Text and thoughts ----------------------------------------------------------

  _Block? _block;
  int _messages = 0;

  String _messageId() =>
      'msg_agy_${_store.sessionId.substring(0, 8)}_'
      '${DateTime.now().microsecondsSinceEpoch}_${++_messages}';

  void _event(Map<String, Object?> event) => _emit({
    'type': 'stream_event',
    'event': event,
    'parent_tool_use_id': null,
  });

  void _chunk(_BlockKind kind, String text) {
    if (text.isEmpty) return;
    var block = _block;
    if (block == null || block.kind != kind) {
      _closeOpen();
      block = _block = _Block(kind, _messageId());
      _emit({'type': 'system', 'subtype': 'status', 'status': 'requesting'});
      _event({
        'type': 'message_start',
        'message': {'id': block.id, 'role': 'assistant', 'model': _model},
      });
      _event({
        'type': 'content_block_start',
        'index': 0,
        'content_block': kind == _BlockKind.text
            ? const {'type': 'text', 'text': ''}
            : const {'type': 'thinking', 'thinking': ''},
      });
    }
    block.text.write(text);
    _event({
      'type': 'content_block_delta',
      'index': 0,
      'delta': kind == _BlockKind.text
          ? {'type': 'text_delta', 'text': text}
          : {'type': 'thinking_delta', 'thinking': text},
    });
  }

  /// Ends the text or thought being written: the text kept, the thought
  /// shown only (unsigned, a thought would be turned away by Anthropic's
  /// API as the conversation goes on there).
  void _closeOpen() {
    final block = _block;
    if (block == null) return;
    _block = null;
    _event({'type': 'content_block_stop', 'index': 0});
    _event({'type': 'message_stop'});
    final text = '${block.text}';
    if (block.kind == _BlockKind.thinking) {
      _emit({
        'type': 'assistant',
        'message': _message(block.id, [
          {'type': 'thinking', 'thinking': text, 'signature': ''},
        ]),
        'parent_tool_use_id': null,
        'uuid': newUuid(),
      });
      return;
    }
    _assistant(block.id, [
      {'type': 'text', 'text': text},
    ]);
  }

  Map<String, Object?> _message(
    String id,
    List<Map<String, Object?>> content,
  ) => {
    'id': id,
    'type': 'message',
    'role': 'assistant',
    'model': _model ?? 'antigravity',
    'content': content,
    'stop_reason': null,
    'stop_sequence': null,
    'usage': const {'input_tokens': 0, 'output_tokens': 0},
  };

  /// An answer's block, kept and told.
  void _assistant(String id, List<Map<String, Object?>> content) {
    final entry = _store.append({
      'type': 'assistant',
      'message': _message(id, content),
    });
    _emit({
      'type': 'assistant',
      'message': entry['message'],
      'parent_tool_use_id': null,
      'uuid': entry['uuid'],
    });
  }

  void _appendUser(String text) => _store.append({
    'type': 'user',
    'message': {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': text},
      ],
    },
  });

  // --- Tool calls -----------------------------------------------------------------

  final Map<String, _Call> _calls = {};

  _Call? _toolCall(Map<String, Object?> update) {
    final id = update['toolCallId'];
    if (id is! String) return null;
    final call = _calls.putIfAbsent(id, () => _Call(AcpToolCall(id)));
    call.acp.merge(update);
    return call;
  }

  /// [call] as it goes: told once it is known what it does (an edit once
  /// its change is), its result once done.
  void _progress(_Call call) {
    if (!call.told &&
        (!call.edits || call.acp.diff != null || !call.acp.running)) {
      _tell(call);
    }
    if (call.told && !call.acp.running && !call.done) _finish(call);
  }

  void _tell(_Call call) {
    if (call.told) return;
    final use = claudeToolUse(call.acp, servers: _sdkServers);
    call
      ..told = true
      ..name = use.name
      ..input = use.input;
    _assistant(_messageId(), [
      {
        'type': 'tool_use',
        'id': call.claudeId,
        'name': use.name,
        'input': use.input,
      },
    ]);
  }

  void _finish(_Call call) {
    call.done = true;
    String? fileText;
    final diff = call.edits ? call.acp.diff : null;
    if (diff != null) {
      try {
        fileText = File(diff.path).readAsStringSync();
      } on Object {
        // Gone, or not text: the patch numbered from its start.
      }
    }
    final result = claudeToolResult(call.acp, call.name, fileText: fileText);
    _result(
      call,
      result.content,
      isError: result.isError,
      structured: result.structured,
    );
    if (call.edits) {
      unawaited(
        _hook(call.acp.failed ? 'PostToolUseFailure' : 'PostToolUse', call),
      );
    }
  }

  void _result(
    _Call call,
    String content, {
    bool isError = false,
    Map<String, Object?>? structured,
  }) {
    final entry = _store.append({
      'type': 'user',
      'message': {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': call.claudeId,
            'content': content,
            if (isError) 'is_error': true,
          },
        ],
      },
      'toolUseResult': ?structured,
    });
    _emit({
      'type': 'user',
      'message': entry['message'],
      'parent_tool_use_id': null,
      'uuid': entry['uuid'],
      'tool_use_result': ?structured,
    });
  }

  /// The turn is over: the calls told and not done are answered, for the
  /// conversation to stay whole (each call its result); [interrupted], as
  /// stopped.
  void _settleCalls({required bool interrupted}) {
    for (final call in _calls.values) {
      if (!call.told || call.done) continue;
      if (!interrupted && call.acp.running) continue;
      call.done = true;
      _result(
        call,
        interrupted
            ? 'The user interrupted this tool call.'
            : call.acp.output ?? '(no output)',
        isError: interrupted,
      );
    }
    if (interrupted) _calls.clear();
  }

  int _plans = 0;

  void _todos(Map<String, Object?> update) {
    final call = _Call(AcpToolCall('plan_${++_plans}'))
      ..told = true
      ..done = true
      ..name = 'TodoWrite'
      ..input = claudeTodos(update);
    _assistant(_messageId(), [
      {
        'type': 'tool_use',
        'id': call.claudeId,
        'name': call.name,
        'input': call.input,
      },
    ]);
    _result(
      call,
      'Todos have been modified successfully.',
      structured: {'newTodos': call.input['todos']},
    );
  }

  // --- Closing --------------------------------------------------------------------

  bool _closed = false;

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    if (identical(_running[_store.sessionId], this)) {
      _running.remove(_store.sessionId);
    }
    _idleTimer?.cancel();
    _interrupt();
    _dropConnection();
    _kernel.failAll('Antigravity stopped');
    for (final endpoint in _endpoints) {
      unawaited(endpoint.close());
    }
    _endpoints.clear();
    if (_out.isClosed) return;
    _out
      ..add(ClaudeExit.message(0, ''))
      ..close();
  }
}

class _Turn {
  _Turn(this.uuid);

  final String uuid;
  final DateTime started = DateTime.now();
  DateTime heard = DateTime.now();
  bool cancelled = false;
  bool stalled = false;
  int? inputTokens;
  int? outputTokens;
  int cacheRead = 0;
  int cacheWrite = 0;
  int thought = 0;
}

enum _BlockKind { text, thinking }

class _Block {
  _Block(this.kind, this.id);

  final _BlockKind kind;
  final String id;
  final StringBuffer text = StringBuffer();
}

/// A tool call of agy's, and what it was told as.
class _Call {
  _Call(this.acp) : claudeId = claudeToolId(acp.id);

  final AcpToolCall acp;
  final String claudeId;

  /// Told as a tool_use; answered with its result.
  bool told = false;
  bool done = false;
  bool preHooked = false;
  String name = '';
  Map<String, Object?> input = const {};

  /// Whether it changes a file.
  bool get edits => acp.kind == 'edit' || name == 'Edit' || name == 'Write';
}
