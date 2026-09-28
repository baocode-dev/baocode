import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import '../agent_kernel.dart';
import '../kernel_event.dart';
import '../kernel_types.dart';
import 'claude_code_transport.dart';
import 'claude_code_translator.dart';
import 'control_channel.dart';

/// Reads a kept session: its conversation lines, oldest first, along the
/// branch the session ended on.
typedef ClaudeHistoryReader = Future<List<Map<String, Object?>>> Function(
  SessionRecord session,
);

/// The setting Claude Code runs with that keeps it from asking for the
/// plan usage, if one does.
typedef ClaudeUsageSwitch = Future<String?> Function();

/// Adapts Claude Code, run as `claude -p` over stream-json, to
/// [AgentKernel].
///
/// One process per session, started when first needed: the conversation
/// goes to its stdin as user messages, settings and questions as control
/// requests; its output is translated by [ClaudeTranslator]. Tool
/// permissions, questions and plan approvals come back as control requests
/// of its own and become [InteractionRequest]s.
class ClaudeCodeKernel
    with KernelEventSource
    implements
        AgentKernel,
        SelectsModel,
        SelectsMode,
        SelectsPermission,
        SelectsEffort,
        SelectsContextSize,
        ProvidesCommands,
        SuggestsFiles,
        ReportsContext,
        ReportsUsage,
        RunsBackgroundTasks,
        QueuesMessages,
        RevertsChanges,
        RewindsConversation,
        RenamesSession,
        AcceptsImages,
        SuggestsPrompts,
        ManagesMcpServers {
  ClaudeCodeKernel(
    this.descriptor,
    this._context, {
    required this._start,
    ClaudeHistoryReader? readHistory,
    ClaudeUsageSwitch? usageOffBy,
  }) : _usageOffBy = usageOffBy ?? _usageOn {
    _translator = ClaudeTranslator(emit: emit, nextSeq: () => nextSeq);
    _live.add(this);
    _sessionId = _context.resume?.id;
    final settings = _context.settings;
    _work = _pick(settings[KernelChoiceKind.mode.name], _works, 'agent');
    _approval = _pick(
      settings[KernelChoiceKind.permission.name],
      _approvals,
      'default',
    );
    _model = settings[KernelChoiceKind.model.name];
    _effort = settings[KernelChoiceKind.effort.name];
    _window = _windows[settings[KernelChoiceKind.context.name]];
    if ((_context.resume, readHistory) case (final session?, final read?)) {
      _history = _replay(read, session);
    }
  }

  @override
  final KernelDescriptor descriptor;
  final KernelContext _context;
  final ClaudeTransportFactory _start;
  final ClaudeUsageSwitch _usageOffBy;
  late final ClaudeTranslator _translator;

  static Future<String?> _usageOn() async => null;

  ClaudeCodeTransport? _transport;
  ControlChannel? _control;
  StreamSubscription<Map<String, Object?>>? _subscription;
  Future<void>? _starting;
  Future<void> _history = Future.value();

  /// Writes wait on this: for the process to be ready, and for a rewind to
  /// land before the message that follows it.
  Future<void> _writes = Future.value();

  KernelHealth _health = KernelHealth.idle;
  String? _sessionId;
  bool _disposed = false;

  String? _turn;
  final Map<String, KernelTurn> _sent = {};
  final Set<String> _queued = {};
  final Map<String, _Permission> _permissions = {};
  String? _pendingTitle;

  // What the CLI offers and has in effect. The catalog of the last session
  // to start stands in until this one's arrives.
  static _Catalog _lastCatalog = const _Catalog();
  _Catalog _catalog = _lastCatalog;

  /// The model asked for, as the CLI names it (e.g. `opus[1m]`).
  String? _model;
  String? _reportedModel;
  // What the agent does (Agent, Ask, Plan) and how its actions are
  // approved: the CLI has one permission mode for both (see _cliMode).
  String _work = 'agent';
  String _approval = 'default';

  /// The permission mode the CLI was last told, or last reported.
  String _cliMode = 'default';

  /// The effort asked for, and the one the CLI has in effect (it may
  /// step down one the model does not take).
  String? _effort;
  String? _appliedEffort;

  /// The context the conversation may fill before it is compacted, as
  /// picked (the CLI's `autoCompactWindow`); null to leave the CLI's own.
  int? _window;

  /// The [_window] the process was started with: the CLI takes it only
  /// at start, so another is picked up by a restart (see [_applyWindow]).
  int? _launchedWindow;

  /// The context window, as the CLI reports it: the smaller of the
  /// model's and [_window].
  int _contextWindow = 200000;
  bool _contextReported = false;

  /// The models' own windows, by the model the CLI resolved them to, as
  /// reported while they were in use.
  static final Map<String, int> _modelWindows = {};
  double? _cost;

  // The account's limits are the same in every session: the last any of
  // them was told, shown in all of them.
  static List<RateLimitWindow> _limits = const [];
  static final Set<ClaudeCodeKernel> _live = {};
  String? _suggestion;
  List<McpServer>? _servers;

  // --- Lifecycle ------------------------------------------------------------------

  @override
  KernelHealth get health => _health;

  @override
  String? get sessionId => _sessionId;

  @override
  Future<void> get stopped => _stopped;
  Future<void> _stopped = Future.value();

  void _setHealth(KernelHealth health) {
    _health = health;
    emitInfoChanged();
  }

  bool get _running =>
      _control != null && _health.status == KernelHealthStatus.ready;

  String get _cwd => _context.cwd ?? _context.resume?.cwd ?? '.';

  /// Starts the process, if not yet, and waits until it is ready.
  Future<void> _ensureStarted() {
    if (_disposed) return Future.error(StateError('disposed'));
    if (_running) return Future.value();
    return _starting ??= _launch().whenComplete(() {
      _starting = null;
      // Picked while it started.
      _applyWindow();
    });
  }

  Future<void> _launch() async {
    await _history;
    // One process at a time on a session: the last one, if restarted.
    await _stopped;
    _setHealth(const KernelHealth(KernelHealthStatus.starting));
    try {
      final transport = await _start(
        ClaudeLaunch(
          cwd: _cwd,
          resume: _sessionId,
          model: _model,
          // Plan is entered once started: the CLI then keeps the
          // approvals it had, for the plan's research and for carrying it
          // out.
          permissionMode: _cliMode = _work == 'plan' ? _approval : _mode,
          effort: _effort,
          autocompact: _launchedWindow = _window,
        ),
      );
      if (_disposed) {
        transport.close();
        return;
      }
      _transport = transport;
      final control = _control = ControlChannel(transport.write);
      _subscription = transport.messages.listen(_receive);
      _applyInitialize(
        await control.request('initialize', {'promptSuggestions': true}),
      );
      if (_mode != _cliMode) {
        _cliMode = _mode;
        await control.request('set_permission_mode', {'mode': _mode});
      }
      _setHealth(KernelHealth.ready);
      final window = _window;
      _change([
        // A 1M variant, if its model has one, to fill past 200K.
        if ((window, _currentModel) case (final window?, final current?))
          ?_modelChange(
            (_models[_baseOf(current.value)] ?? const [])
                .where((v) => v.long == window > _windows['200k']!)
                .firstOrNull
                ?.value,
          ),
      ]);
      // The CLI builds its file index on the first lookup: start it now,
      // so `@` finds files by the time the user types it.
      _tell('file_suggestions', {'query': ''});
      if (_pendingTitle case final title?) {
        _pendingTitle = null;
        rename(title);
      }
      unawaited(_refreshContext());
    } on ClaudeUnavailable catch (error) {
      _fail(error.message, error.detail);
      rethrow;
    } on ControlError catch (error) {
      _fail('Claude Code did not start', '$error');
      rethrow;
    }
  }

  void _fail(String message, String? detail) {
    _teardown();
    _setHealth(
      KernelHealth(KernelHealthStatus.failed, message: message, detail: detail),
    );
  }

  void _teardown() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _control?.failAll('Claude Code stopped');
    _control = null;
    if (_transport case final transport?) {
      // A process that will not end is not waited on for ever.
      _stopped = transport.exited.timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
      transport.close();
    }
    _transport = null;
  }

  /// Runs [write] once ready and after the writes before it; a failure to
  /// start ends the turn.
  void _whenReady(void Function(ClaudeCodeTransport transport) write) {
    _writes = _writes
        .then((_) => _ensureStarted())
        .then((_) {
          if (_transport case final transport?) write(transport);
        })
        .catchError((Object error) {
          if (_turn case final turn?) {
            emit(
              ItemUpserted(
                nextSeq,
                'error:$turn',
                NoticeItem(NoticeKind.error, _health.message ?? '$error'),
              ),
            );
            _endTurn(interrupted: true);
          }
        });
  }

  Future<Map<String, Object?>> _request(
    String subtype, [
    Map<String, Object?> fields = const {},
    Duration timeout = const Duration(seconds: 60),
  ]) async {
    await _ensureStarted();
    return _control!.request(subtype, fields, timeout);
  }

  /// A request whose answer does not matter beyond its effect.
  void _tell(String subtype, [Map<String, Object?> fields = const {}]) {
    if (!_running) return;
    unawaited(
      _control!
          .request(subtype, fields)
          .catchError((_) => const <String, Object?>{}),
    );
  }

  @override
  void prepare() {
    if (_health.status == KernelHealthStatus.failed) return;
    unawaited(_ensureStarted().catchError((_) {}));
  }

  @override
  void restart() {
    _teardown();
    _setHealth(KernelHealth.idle);
    prepare();
  }

  bool get _busy =>
      _turn != null ||
      _queued.isNotEmpty ||
      _permissions.isNotEmpty ||
      _starting != null;

  @override
  void release() {
    if (_busy || _transport == null) return;
    _teardown();
    _setHealth(KernelHealth.idle);
  }

  /// Restarts the process on the same session if another [_window] was
  /// picked since it started, once nothing is under way: the CLI compacts
  /// where it was told at start, whatever it is told after. Whether it
  /// did.
  bool _applyWindow() {
    if (!_running || _busy || _window == _launchedWindow) return false;
    _teardown();
    _setHealth(KernelHealth.idle);
    prepare();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _live.remove(this);
    _teardown();
    closeEvents();
  }

  // --- The conversation -----------------------------------------------------------

  @override
  void send(KernelTurn turn) {
    if (_sent.containsKey(turn.id)) return;
    _sent[turn.id] = turn;
    final busy = _turn != null;
    if (busy) {
      _queued.add(turn.id);
    } else {
      _beginTurn(turn.id);
    }
    if (_suggestion != null) {
      _suggestion = null;
      emitInfoChanged();
    }
    emit(
      ItemUpserted(
        nextSeq,
        turn.id,
        UserMessageItem(text: turn.text, queued: busy, images: turn.images),
      ),
    );
    _whenReady(
      (transport) => transport.write({
        'type': 'user',
        'uuid': turn.id,
        'session_id': _sessionId ?? '',
        'parent_tool_use_id': null,
        'message': {
          'role': 'user',
          'content': [
            for (final image in turn.images)
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': image.mediaType,
                  'data': base64Encode(image.bytes),
                },
              },
            if (turn.text.isNotEmpty) {'type': 'text', 'text': turn.text},
            if (_work == 'ask') {'type': 'text', 'text': _askNote},
          ],
        },
      }),
    );
  }

  void _beginTurn(String id) {
    _turn = id;
    _translator.turnId = id;
    emit(TurnStarted(nextSeq, id));
    _translator.begin();
  }

  void _endTurn({required bool interrupted}) {
    final turn = _turn;
    if (turn == null) return;
    _turn = null;
    _translator.settle();
    for (final id in _permissions.keys) {
      emit(InteractionResolved(nextSeq, id));
    }
    _permissions.clear();
    emit(TurnEnded(nextSeq, turn, interrupted: interrupted));
  }

  @override
  void cancel() {
    if (_turn == null) return;
    _tell('interrupt');
    _endTurn(interrupted: true);
  }

  @override
  void cancelQueued(String turnId) {
    if (!_queued.contains(turnId) || !_running) return;
    unawaited(
      _control!
          .request('cancel_async_message', {'message_uuid': turnId})
          .then((response) {
            if (response['cancelled'] == true && _queued.remove(turnId)) {
              emit(ItemRemoved(nextSeq, turnId));
            }
          })
          .catchError((_) {}),
    );
  }

  @override
  void rewind({
    required String itemId,
    required int index,
    required int turns,
  }) {
    emit(Rewound(nextSeq, itemId: itemId, index: index));
    _writes = _writes
        .then(
          (_) =>
              _request('rewind_conversation', {'target_message_uuid': itemId}),
        )
        .then((_) {})
        .catchError((Object error) {
          emit(
            ItemUpserted(
              nextSeq,
              'rewind:$itemId',
              NoticeItem(NoticeKind.error, 'Could not rewind: $error'),
            ),
          );
        });
  }

  @override
  void revertChanges({required String sinceTurn}) {
    unawaited(
      _request('rewind_files', {'user_message_id': sinceTurn})
          .then((response) {
            if (response['canRewind'] == false) {
              throw ControlError(
                'rewind_files',
                '${response['error'] ?? 'nothing to restore'}',
              );
            }
            emit(ChangesReverted(nextSeq));
          })
          .catchError((Object error) {
            emit(
              ItemUpserted(
                nextSeq,
                'revert:$sinceTurn',
                NoticeItem(
                  NoticeKind.error,
                  'Could not undo the changes: $error',
                ),
              ),
            );
          }),
    );
  }

  @override
  void rename(String title) {
    if (!_running) {
      _pendingTitle = title;
      return;
    }
    _tell('rename_session', {'title': title, 'source': 'host'});
  }

  @override
  void stopTask(String taskId) => _tell('stop_task', {'task_id': taskId});

  @override
  void moveToBackground(String toolUseId) =>
      _tell('background_tasks', {'tool_use_id': toolUseId});

  @override
  String? get promptSuggestion => _suggestion;

  // --- MCP servers ------------------------------------------------------------------

  @override
  List<McpServer>? get mcpServers => _servers;

  @override
  void refreshMcpServers() {
    unawaited(
      _request(
        'mcp_status',
        const {},
        const Duration(seconds: 20),
      ).then(_applyServers).catchError((_) {}),
    );
  }

  @override
  void setMcpServerEnabled(String name, bool enabled) {
    _setServerStatus(
      name,
      enabled ? McpServerStatus.pending : McpServerStatus.disabled,
    );
    _serverRequest('mcp_toggle', {'serverName': name, 'enabled': enabled});
  }

  @override
  void reconnectMcpServer(String name) {
    _setServerStatus(name, McpServerStatus.pending);
    _serverRequest('mcp_reconnect', {'serverName': name});
  }

  @override
  Future<Uri?> authenticateMcpServer(String name) async {
    final response = await _request('mcp_authenticate', {
      'serverName': name,
    }, const Duration(seconds: 60));
    final url = Uri.tryParse('${response['authUrl'] ?? ''}');
    if (url == null || !url.hasScheme) {
      refreshMcpServers();
      return null;
    }
    // The CLI takes the callback and reconnects: watch for it.
    unawaited(_awaitSignIn(name));
    return url;
  }

  Future<void> _awaitSignIn(String name) async {
    for (var i = 0; i < 60 && !_disposed && _running; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!_running) return;
      try {
        _applyServers(await _control!.request('mcp_status'));
      } on Object {
        return;
      }
      final server = _servers?.where((s) => s.name == name).firstOrNull;
      if (server == null || server.status != McpServerStatus.needsAuth) return;
    }
  }

  /// Runs [subtype] on a server, then reports where they all stand (a
  /// failure shows as the server's status).
  void _serverRequest(String subtype, Map<String, Object?> fields) {
    unawaited(
      _request(
        subtype,
        fields,
        const Duration(seconds: 60),
      ).then((_) {}).catchError((_) {}).whenComplete(refreshMcpServers),
    );
  }

  /// Shows [name] as [status] until the CLI reports it.
  void _setServerStatus(String name, McpServerStatus status) {
    final servers = _servers;
    if (servers == null) return;
    _servers = [
      for (final server in servers)
        server.name == name
            ? McpServer(
                name: server.name,
                status: status,
                scope: server.scope,
                version: server.version,
                tools: server.tools,
              )
            : server,
    ];
    emitInfoChanged();
  }

  void _applyServers(Map<String, Object?> status) {
    _servers = [
      for (final raw in status['mcpServers'] as List? ?? const [])
        if (raw is Map) _server(raw.cast<String, Object?>()),
    ];
    emitInfoChanged();
  }

  static McpServer _server(Map<String, Object?> raw) {
    final info = raw['serverInfo'];
    return McpServer(
      name: '${raw['name']}',
      status: switch (raw['status']) {
        'connected' => McpServerStatus.connected,
        'failed' => McpServerStatus.failed,
        'needs-auth' => McpServerStatus.needsAuth,
        'disabled' => McpServerStatus.disabled,
        _ => McpServerStatus.pending,
      },
      error: raw['error'] as String?,
      scope: (raw['scope'] ?? raw['source']) as String?,
      version: info is Map ? info['version'] as String? : null,
      tools: [
        for (final tool in raw['tools'] as List? ?? const [])
          if (tool is Map && tool['name'] is String) tool['name'] as String,
      ],
    );
  }

  @override
  Future<List<FileSuggestion>> suggestFiles(String query) async {
    try {
      final response = await _request('file_suggestions', {
        'query': query,
      }, const Duration(seconds: 5));
      return [
        for (final raw in response['suggestions'] as List? ?? const [])
          if (raw is Map && raw['path'] is String)
            FileSuggestion(raw['path'] as String),
      ];
    } on Object {
      return const [];
    }
  }

  // --- Questions ---------------------------------------------------------------------

  @override
  void answer(String requestId, InteractionAnswer answer) {
    final permission = _permissions.remove(requestId);
    final control = _control;
    if (permission == null || control == null) return;
    emit(InteractionResolved(nextSeq, requestId));
    Map<String, Object?> allow({List<Object?>? rules}) => {
      'behavior': 'allow',
      'updatedInput': permission.input,
      'updatedPermissions': ?rules,
    };
    Map<String, Object?> deny(String message) => {
      'behavior': 'deny',
      'message': message,
    };
    control.respond(requestId, switch (answer) {
      QuestionAnswer(skipped: true) => deny(
        'The user dismissed the questions without answering.',
      ),
      QuestionAnswer(:final picks) => {
        'behavior': 'allow',
        'updatedInput': {
          ...permission.input,
          'answers': {
            for (final (i, question) in permission.questions.indexed)
              if (i < picks.length) question: picks[i].join(', '),
          },
        },
      },
      PlanAnswer(decision: PlanDecision.approve) => allow(
        rules: [_setMode(_startBuilding())],
      ),
      PlanAnswer(:final feedback) => deny(
        feedback == null || feedback.trim().isEmpty
            ? 'The user wants to keep planning. Do not start yet.'
            : 'The user wants to keep planning: $feedback',
      ),
      ApprovalAnswer(decision: ApprovalDecision.allowOnce) => allow(),
      ApprovalAnswer(decision: ApprovalDecision.allowAlways) => allow(
        rules: permission.suggestions,
      ),
      ApprovalAnswer(:final message) => deny(
        message == null || message.trim().isEmpty
            ? 'The user did not allow this.'
            : message,
      ),
    });
  }

  /// Out of Plan, into Agent with the approvals picked: the mode the CLI
  /// goes on in.
  String _startBuilding() {
    _work = 'agent';
    _cliMode = _approval;
    emitInfoChanged();
    return _approval;
  }

  static Map<String, Object?> _setMode(String mode) => {
    'type': 'setMode',
    'mode': mode,
    'destination': 'session',
  };

  Future<void> _permission(
    String requestId,
    Map<String, Object?> request,
  ) async {
    final tool = request['tool_name'] as String? ?? 'Tool';
    final input = (request['input'] as Map?)?.cast<String, Object?>() ?? {};
    final suggestions = request['permission_suggestions'] as List? ?? const [];
    final InteractionRequest interaction;
    var questions = const <String>[];
    switch (tool) {
      case 'AskUserQuestion':
        final raw = input['questions'] as List? ?? const [];
        questions = [
          for (final q in raw)
            if (q is Map) '${q['question']}',
        ];
        interaction = QuestionRequest(
          id: requestId,
          title: 'Claude has a question',
          questions: [
            for (final q in raw)
              if (q is Map)
                Question(
                  prompt: '${q['question']}',
                  header: '${q['header'] ?? ''}',
                  allowMultiple: q['multiSelect'] == true,
                  options: [
                    for (final option in q['options'] as List? ?? const [])
                      if (option is Map)
                        QuestionOption(
                          '${option['label']}',
                          description: '${option['description'] ?? ''}',
                          preview: option['preview'] as String?,
                        ),
                  ],
                ),
          ],
        );
      case 'ExitPlanMode':
        var plan = input['plan'] as String?;
        if (plan == null) {
          try {
            plan = (await _control!.request('get_plan'))['content'] as String?;
          } on Object {
            plan = null;
          }
        }
        interaction = PlanReviewRequest(
          id: requestId,
          title: 'Ready to code?',
          plan: plan ?? '(The plan could not be read.)',
          approveLabel: switch (_approvals
              .where((a) => a.id == _approval)
              .firstOrNull) {
            final approval? => 'Yes, start · ${approval.label}',
            null => 'Yes, start building',
          },
        );
      default:
        interaction = ApprovalRequest(
          id: requestId,
          title: _approvalTitle(tool, request),
          toolName: tool,
          reason: _clean(request['decision_reason'] as String?),
          preview: _preview(tool, input),
          alwaysAllowLabel: _describeRules(suggestions),
        );
    }
    _permissions[requestId] = _Permission(input, suggestions, questions);
    emit(InteractionRequested(nextSeq, interaction));
  }

  static String _approvalTitle(String tool, Map<String, Object?> request) {
    final name = request['display_name'] as String? ?? tool;
    final what = request['description'] as String?;
    return switch (tool) {
      'Bash' => 'Run this command?',
      'Edit' || 'MultiEdit' => 'Edit ${what ?? 'this file'}?',
      'Write' => 'Write ${what ?? 'this file'}?',
      'WebFetch' => 'Fetch ${what ?? 'this page'}?',
      _ => 'Use $name${what == null ? '' : ' · $what'}?',
    };
  }

  static ApprovalPreview? _preview(String tool, Map<String, Object?> input) {
    switch (tool) {
      case 'Bash':
        return CommandPreview(
          '${input['command'] ?? ''}',
          description: input['description'] as String?,
        );
      case 'Edit':
        return DiffPreview(
          '${input['file_path'] ?? ''}',
          _lines(
            '${input['old_string'] ?? ''}',
            '${input['new_string'] ?? ''}',
          ),
        );
      case 'MultiEdit':
        return DiffPreview('${input['file_path'] ?? ''}', [
          for (final edit in input['edits'] as List? ?? const [])
            if (edit is Map)
              ..._lines(
                '${edit['old_string'] ?? ''}',
                '${edit['new_string'] ?? ''}',
              ),
        ]);
      case 'Write':
        final content = '${input['content'] ?? ''}'.split('\n');
        return DiffPreview('${input['file_path'] ?? ''}', [
          for (final (i, line) in content.take(200).indexed)
            DiffLine(DiffLineType.added, i + 1, line),
        ]);
      default:
        if (input.isEmpty) return null;
        return TextPreview(const JsonEncoder.withIndent('  ').convert(input));
    }
  }

  static List<DiffLine> _lines(String before, String after) => [
    if (before.isNotEmpty)
      for (final (i, line) in before.split('\n').indexed)
        DiffLine(DiffLineType.removed, i + 1, line),
    if (after.isNotEmpty)
      for (final (i, line) in after.split('\n').indexed)
        DiffLine(DiffLineType.added, i + 1, line),
  ];

  /// What "always allow" would allow, in words; null when the CLI offers
  /// no rule.
  static String? _describeRules(List<Object?> suggestions) {
    final parts = <String>[];
    for (final raw in suggestions) {
      if (raw is! Map) continue;
      switch (raw['type']) {
        case 'setMode':
          parts.add(switch (raw['mode']) {
            'acceptEdits' => 'accept edits for this session',
            'bypassPermissions' => 'skip permissions for this session',
            final mode => 'switch to $mode',
          });
        case 'addRules' || 'replaceRules':
          for (final rule in raw['rules'] as List? ?? const []) {
            if (rule is! Map) continue;
            final content = rule['ruleContent'];
            parts.add(
              content == null
                  ? 'always allow ${rule['toolName']}'
                  : 'always allow ${rule['toolName']}($content)',
            );
          }
        case 'addDirectories':
          parts.add('allow ${(raw['directories'] as List?)?.join(', ')}');
      }
    }
    if (parts.isEmpty) return null;
    final text = parts.join(', ');
    return text[0].toUpperCase() + text.substring(1);
  }

  static String? _clean(String? text) =>
      text?.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '').trim();

  // --- Output -------------------------------------------------------------------------

  void _receive(Map<String, Object?> message) {
    if (_control?.receive(message) ?? false) return;
    switch (message['type']) {
      case ClaudeExit.type:
        _exited(
          message['code'] as int? ?? 0,
          message['stderr'] as String? ?? '',
        );
      case 'control_request':
        _controlRequest(message);
      case 'control_cancel_request':
        final id = message['request_id'] as String?;
        if (id != null && _permissions.remove(id) != null) {
          emit(InteractionResolved(nextSeq, id));
        }
      case 'system' when message['subtype'] == 'init':
        _sessionId = message['session_id'] as String? ?? _sessionId;
        _reportedModel = message['model'] as String?;
        if (message.containsKey('effort')) {
          _appliedEffort = message['effort'] as String?;
        }
        if (message['permissionMode'] case final String mode) {
          _reported(mode);
        }
        // Only the servers up at start: the full list is asked for.
        if (message['mcp_servers'] case final List<Object?> servers
            when servers.isNotEmpty && _servers == null) {
          _servers = [
            for (final raw in servers)
              if (raw is Map) _server(raw.cast<String, Object?>()),
          ];
        }
        _catalog = _catalog.copyWith(
          terminalOnly: [
            for (final name
                in message['terminal_slash_commands'] as List? ?? const [])
              '$name',
          ],
        );
        emitInfoChanged();
      case 'system' when message['subtype'] == 'status':
        if (message['permissionMode'] case final String mode) {
          _reported(mode);
        }
        _translator.translate(message);
      case 'system' when message['subtype'] == 'commands_changed':
        _catalog = _catalog.copyWith(
          commands: _commandsFrom(message['commands']),
        );
        emitInfoChanged();
      case 'result':
        _result(message);
      case 'rate_limit_event':
        _rateLimits(message['rate_limit_info']);
      case 'command_lifecycle':
        _lifecycle(message);
      case 'prompt_suggestion':
        final suggestion = (message['suggestion'] as String?)?.trim();
        if (_turn == null && _queued.isEmpty && suggestion != _suggestion) {
          _suggestion = suggestion == null || suggestion.isEmpty
              ? null
              : suggestion;
          emitInfoChanged();
        }
      default:
        _translator.translate(message);
    }
  }

  void _controlRequest(Map<String, Object?> message) {
    final id = message['request_id'] as String?;
    final request = (message['request'] as Map?)?.cast<String, Object?>();
    final control = _control;
    if (id == null || request == null || control == null) return;
    switch (request['subtype']) {
      case 'can_use_tool':
        unawaited(_permission(id, request));
      case 'elicitation':
        control.respond(id, {'action': 'decline'});
      default:
        control.refuse(id, 'Not supported by this client');
    }
  }

  void _lifecycle(Map<String, Object?> message) {
    final id = message['command_uuid'] as String?;
    if (id == null) return;
    switch (message['state']) {
      case 'started':
        if (_queued.remove(id)) {
          emit(
            ItemUpserted(
              nextSeq,
              id,
              UserMessageItem(
                text: _sent[id]?.text ?? '',
                images: _sent[id]?.images ?? const [],
              ),
            ),
          );
        }
        if (_turn != id && _sent.containsKey(id)) _beginTurn(id);
      case 'cancelled':
        if (_queued.remove(id)) emit(ItemRemoved(nextSeq, id));
    }
  }

  void _result(Map<String, Object?> message) {
    if (message['total_cost_usd'] case final num cost) {
      _cost = cost.toDouble();
      _reportStats();
    }
    // The models' own windows: the conversation's may be less (see
    // _window), as get_context_usage reports next.
    if (message['modelUsage'] case final Map<Object?, Object?> usage) {
      for (final MapEntry(:key, :value) in usage.entries) {
        if ((key, value) case (
          final String model,
          {'contextWindow': final int window},
        )) {
          _modelWindows[model] = window;
        }
      }
    }
    if (message['is_error'] == true && message['result'] is String) {
      final error = message['result'] as String;
      if (error.isNotEmpty) {
        emit(
          ItemUpserted(
            nextSeq,
            'error:${message['uuid'] ?? _turn}',
            NoticeItem(NoticeKind.error, error),
          ),
        );
      }
    }
    _endTurn(interrupted: message['subtype'] != 'success');
    unawaited(_refreshContext());
    // Picked during the turn.
    _applyWindow();
  }

  static String _limitLabel(Object? type) => switch (type) {
    'five_hour' => '5-hour limit',
    'seven_day' => 'Weekly limit',
    'seven_day_opus' => 'Weekly Opus limit',
    'seven_day_sonnet' => 'Weekly Sonnet limit',
    'seven_day_overage_included' => 'Weekly with extra usage',
    _ => '$type',
  };

  /// From a `rate_limit_event`, sent as a reply changes the usage: the
  /// windows, or near a limit just that one.
  void _rateLimits(Object? info) {
    if (info is! Map) return;
    RateLimitWindow window(Object? type, Object? utilization, Object? resets) =>
        RateLimitWindow(
          _limitLabel(type),
          (utilization! as num).toDouble(),
          resetsAt: resets is int
              ? DateTime.fromMillisecondsSinceEpoch(resets * 1000)
              : null,
        );
    if (info['unifiedWindows'] case final Map<Object?, Object?> windows) {
      _updateLimits([
        for (final MapEntry(:key, :value) in windows.entries)
          if (value is Map && value['utilization'] is num)
            window(key, value['utilization'], value['resetsAt']),
      ]);
    } else if (info['utilization'] is num && info['rateLimitType'] != null) {
      _updateLimits([
        window(info['rateLimitType'], info['utilization'], info['resetsAt']),
      ]);
    }
  }

  /// Takes [windows] in place of what was known of them, the others kept,
  /// and shows them in every session.
  static void _updateLimits(List<RateLimitWindow> windows) {
    if (windows.isEmpty) return;
    final fresh = {for (final window in windows) window.label: window};
    _limits = [
      for (final limit in _limits) fresh.remove(limit.label) ?? limit,
      ...fresh.values,
    ];
    _reportAll();
  }

  static void _reportAll() {
    for (final kernel in _live) {
      kernel._reportStats();
    }
  }

  @override
  List<RateLimitWindow> get accountLimits => _limits;

  // The account's usage, asked for (as `/usage` does): no more than once in
  // [_usageFresh], and one request at a time for all sessions.
  static Future<void>? _fetchingUsage;
  static DateTime? _usageFetchedAt;
  static LimitsState _limitsState = LimitsState.idle;
  static String? _limitsOffBy;
  static const _usageFresh = Duration(seconds: 30);

  /// How often, and how far apart, the usage is asked for while Claude
  /// Code has none to give: its own fetch of it may still be under way.
  @visibleForTesting
  static int usageAttempts = 3;
  @visibleForTesting
  static Duration usageRetryDelay = const Duration(seconds: 3);

  /// Forgets what is known of the account, as a new start of the app.
  @visibleForTesting
  static void forgetAccount() {
    _limits = const [];
    _usageFetchedAt = null;
    _limitsState = LimitsState.idle;
    _limitsOffBy = null;
  }

  @override
  Future<void> refreshUsage() {
    if (_usageFetchedAt case final at?
        when DateTime.now().difference(at) < _usageFresh) {
      return Future.value();
    }
    return _fetchingUsage ??= _fetchUsage().whenComplete(
      () => _fetchingUsage = null,
    );
  }

  Future<void> _fetchUsage() async {
    // Turned off, Claude Code would not send the request: not asked.
    if (await _usageOffBy() case final setting?) {
      _limitsOffBy = setting;
      return _setLimitsState(LimitsState.off);
    }
    _setLimitsState(LimitsState.checking);
    var state = LimitsState.unavailable;
    try {
      // A session's process, if one runs; else one of its own, briefly.
      final control = _live.where((k) => k._running).firstOrNull?._control;
      final ask = control != null ? _askUsage : _probeUsage;
      state = await ask(control) ?? state;
    } on Exception {
      // Unanswered (an older CLI, offline): the limits stay as the replies
      // report them.
    }
    _setLimitsState(state);
  }

  /// Asks [control] until it tells the limits, or tells they do not apply;
  /// null when it never does.
  Future<LimitsState?> _askUsage(ControlChannel? control) async {
    for (var attempt = 1; attempt <= usageAttempts; attempt++) {
      final usage = await control!.request('get_usage', {
        'skip_behaviors': true,
      }, const Duration(seconds: 20));
      if (usage['rate_limits_available'] == false || _accountUsage(usage)) {
        _usageFetchedAt = DateTime.now();
        return LimitsState.idle;
      }
      if (attempt < usageAttempts) await Future.delayed(usageRetryDelay);
    }
    return null;
  }

  /// Starts Claude Code just to ask for the usage: no model call, and no
  /// session left behind.
  Future<LimitsState?> _probeUsage(ControlChannel? _) async {
    final transport = await _start(
      ClaudeLaunch(cwd: _cwd, permissionMode: 'default', persist: false),
    );
    final control = ControlChannel(transport.write);
    final subscription = transport.messages.listen((message) {
      if (message['type'] == ClaudeExit.type) control.failAll('exited');
      control.receive(message);
    });
    try {
      await control.request('initialize', {}, const Duration(seconds: 30));
      return await _askUsage(control);
    } finally {
      unawaited(subscription.cancel());
      transport.close();
    }
  }

  static void _setLimitsState(LimitsState state) {
    if (_limitsState == state) return;
    _limitsState = state;
    _reportAll();
  }

  /// From a `get_usage` response: percentages, and ISO reset times.
  /// Whether it had them.
  static bool _accountUsage(Map<String, Object?> usage) {
    final limits = usage['rate_limits'];
    if (limits is! Map) return false;
    RateLimitWindow? window(String label, Object? value) {
      if (value is! Map || value['utilization'] is! num) return null;
      return RateLimitWindow(
        label,
        (value['utilization'] as num) / 100,
        resetsAt: switch (value['resets_at']) {
          final String at => DateTime.tryParse(at)?.toLocal(),
          _ => null,
        },
      );
    }

    final models = limits['model_scoped'];
    _updateLimits([
      for (final type in const [
        'five_hour',
        'seven_day',
        'seven_day_opus',
        'seven_day_sonnet',
      ])
        ?window(_limitLabel(type), limits[type]),
      if (models is List)
        for (final model in models)
          if (model is Map && model['display_name'] is String)
            ?window('Weekly ${model['display_name']} limit', model),
    ]);
    return true;
  }

  void _reportStats() => emit(
    StatsReported(
      nextSeq,
      UsageStats(
        costUsd: _cost,
        limits: _limits,
        limitsState: _limitsState,
        limitsOffBy: _limitsOffBy,
      ),
    ),
  );

  Future<void> _refreshContext() async {
    final control = _control;
    if (control == null) return;
    try {
      final usage = await control.request('get_context_usage', {
        'detail': 'summary',
      }, const Duration(seconds: 20));
      final max = usage['maxTokens'] as int? ?? _contextWindow;
      _contextWindow = max;
      _contextReported = true;
      // No more than the window it compacts at (the CLI reports that as
      // raw too): the model holds at least that.
      if ((usage['rawMaxTokens'], _reportedModel)
          case (final int raw, final model?)
          when raw > (_modelWindows[model] ?? 0)) {
        _modelWindows[model] = raw;
      }
      emitInfoChanged();
      emit(
        UsageReported(
          nextSeq,
          ContextUsage(
            window: max,
            used: usage['totalTokens'] as int? ?? 0,
            segments: [
              for (final raw in usage['categories'] as List? ?? const [])
                if (raw is Map && raw['tokens'] is int)
                  ContextSegment(
                    '${raw['name']}',
                    raw['tokens'] as int,
                    kind: switch (raw['kind']) {
                      'free' => ContextKind.free,
                      'buffer' => ContextKind.buffer,
                      'deferred' => ContextKind.deferred,
                      _ => ContextKind.used,
                    },
                  ),
            ],
          ),
        ),
      );
    } on Object {
      // Context usage is a nicety: an older CLI may not answer.
    }
  }

  void _exited(int code, String stderr) {
    final wasReady = _health.status == KernelHealthStatus.ready;
    _teardown();
    if (_turn != null) {
      emit(
        ItemUpserted(
          nextSeq,
          'exit:${_turn!}',
          const NoticeItem(
            NoticeKind.error,
            'Claude Code stopped unexpectedly',
          ),
        ),
      );
      _endTurn(interrupted: true);
    }
    for (final id in _queued) {
      emit(ItemRemoved(nextSeq, id));
    }
    _queued.clear();
    if (_disposed) return;
    if (code == 0 && wasReady) {
      _setHealth(KernelHealth.idle);
    } else {
      final lines = stderr.trim().split('\n');
      _setHealth(
        KernelHealth(
          KernelHealthStatus.failed,
          message: _failureMessage(stderr),
          detail: lines
              .skip(lines.length > 12 ? lines.length - 12 : 0)
              .join('\n'),
        ),
      );
    }
  }

  static String _failureMessage(String stderr) {
    final lower = stderr.toLowerCase();
    if (lower.contains('login') ||
        lower.contains('api key') ||
        lower.contains('authenticat')) {
      return 'Claude Code is not logged in. Run `claude` in a terminal and '
          'log in.';
    }
    if (lower.contains('no conversation found')) {
      return 'This session can no longer be resumed';
    }
    return 'Claude Code stopped';
  }

  // --- History ------------------------------------------------------------------------

  Future<void> _replay(ClaudeHistoryReader read, SessionRecord session) async {
    try {
      final lines = await read(session);
      _translator.replaying = true;
      for (final line in lines) {
        _translator.translate(line);
      }
    } on Object catch (error) {
      emit(
        ItemUpserted(
          nextSeq,
          'history-error',
          NoticeItem(NoticeKind.error, 'Could not read this session: $error'),
        ),
      );
    } finally {
      _translator.replaying = false;
    }
  }

  // --- Options ------------------------------------------------------------------------

  void _applyInitialize(Map<String, Object?> response) {
    _catalog = _lastCatalog = _catalog.copyWith(
      commands: _commandsFrom(response['commands']),
      models: [
        for (final raw in response['models'] as List? ?? const [])
          if (raw is Map) _ModelInfo.from(raw.cast<String, Object?>()),
      ],
    );
    // Its mode is the one it was started in: what it changes later comes
    // in `init` and `status` messages.
    emitInfoChanged();
  }

  static List<KernelCommand> _commandsFrom(Object? raw) => [
    for (final command in raw as List? ?? const [])
      if (command is Map && command['name'] is String)
        KernelCommand(
          command['name'] as String,
          '${command['description'] ?? ''}',
          command['builtin'] == true
              ? Icons.keyboard_command_key_rounded
              : Icons.auto_awesome_outlined,
          argumentHint: '${command['argumentHint'] ?? ''}',
        ),
  ];

  @override
  List<KernelCommand> get commands => _commandCache ??= [
    for (final command in _catalog.commands)
      if (!_catalog.terminalOnly.contains(command.name)) command,
  ];
  List<KernelCommand>? _commandCache;

  @override
  int get contextWindow => _contextWindow;

  _ModelInfo? get _currentModel {
    final models = _catalog.models;
    return models.where((m) => m.value == (_model ?? 'default')).firstOrNull ??
        models.where((m) => m.resolved == _reportedModel).firstOrNull ??
        models.firstOrNull;
  }

  static const _long = '1m';

  /// A 1M-context variant, e.g. `opus[1m]`.
  static bool _isLong(String model) => model.toLowerCase().endsWith('[1m]');

  static String _baseOf(String model) =>
      _isLong(model) ? model.substring(0, model.length - 4) : model;

  /// The models as picked, by name: a model and its 1M-context variant,
  /// listed apart by the CLI, are one (as its own picker has them). The
  /// standard variant comes first.
  Map<String, List<_ModelInfo>> get _models {
    final models = <String, List<_ModelInfo>>{};
    for (final info in _catalog.models) {
      (models[_baseOf(info.value)] ??= []).add(info);
    }
    for (final variants in models.values) {
      variants.sort((a, b) => (a.long ? 1 : 0) - (b.long ? 1 : 0));
    }
    return models;
  }

  /// [model]'s variant with the context now in effect, if it has one.
  _ModelInfo? _variantOf(String model) {
    final variants = _models[model];
    if (variants == null) return null;
    final long = _currentModel?.long ?? false;
    return variants.where((v) => v.long == long).firstOrNull ?? variants.first;
  }

  /// A request to switch the CLI to [model], a value it listed: none if
  /// it is the one in use.
  _Request? _modelChange(String? model) {
    if (model == null || model == _currentModel?.value) return null;
    _model = model;
    return ('set_model', {'model': model});
  }

  /// Sends [requests] in turn, each once the one before is done, then
  /// asks what is in effect: the model, effort and window may all differ.
  /// The CLI answers requests as they come, so a question sent right
  /// after a change could be answered from before it.
  void _change(List<_Request> requests) {
    emitInfoChanged();
    if (!_running) return;
    final control = _control!;
    _changes = _changes.then((_) async {
      for (final (subtype, fields) in requests) {
        try {
          await control.request(subtype, fields);
        } on Object {
          // Refused: what is in effect, asked for next, says so.
        }
      }
      if (!identical(control, _control)) return;
      _refreshApplied();
      await _refreshContext();
    });
  }

  Future<void> _changes = Future.value();

  /// Asks the CLI for the model and effort in effect.
  void _refreshApplied() {
    if (!_running) return;
    unawaited(
      _control!
          .request('get_settings')
          .then((response) {
            if (response['applied'] case final Map<Object?, Object?> applied) {
              if (applied['model'] case final String model) {
                _reportedModel = model;
              }
              _appliedEffort = applied['effort'] as String?;
              emitInfoChanged();
            }
          })
          .catchError((_) {}),
    );
  }

  @override
  late final KernelChoiceSource model = _Choice(
    options: () => [
      for (final MapEntry(key: id, value: variants) in _models.entries)
        KernelOption(
          id,
          // "Default (recommended)": the recommending goes without saying.
          variants.first.label.replaceFirst(
            RegExp(r'\s*\(recommended\)$', caseSensitive: false),
            '',
          ),
          Icons.bolt_rounded,
          variants.first.description,
        ),
    ],
    selected: () => switch (_currentModel?.value) {
      final value? => _baseOf(value),
      null => null,
    },
    select: (id) => _change([?_modelChange(_variantOf(id)?.value)]),
  );

  /// The contexts offered, by option id.
  static const _windows = {'200k': 200000, '400k': 400000, _long: 1000000};

  /// The most context [model] (a model as picked) holds: 1M with a 1M
  /// variant, else as reported while in use; 1M while not known.
  int _modelWindowOf(String model) {
    final variants = _models[model] ?? const <_ModelInfo>[];
    if (variants.any((v) => v.long)) return _windows[_long]!;
    for (final variant in variants) {
      if (_modelWindows[variant.resolved ?? variant.value] case final w?) {
        return w;
      }
    }
    return _windows[_long]!;
  }

  /// The context the conversation fills before it is compacted: up to the
  /// model's own window. A model with a 1M variant uses it past 200K.
  @override
  late final ModelSetting contextSize = _ModelSetting(
    optionsFor: (model) {
      final most = _modelWindowOf(model);
      final options = [
        for (final MapEntry(key: id, value: tokens) in _windows.entries)
          if (tokens <= most)
            KernelOption(id, id.toUpperCase(), Icons.notes_rounded, ''),
      ];
      return options.length > 1 ? options : const [];
    },
    selected: () {
      // Shown as picked until the process (re)starts with it.
      final window = _window != _launchedWindow
          ? _window
          : _contextReported
          ? _contextWindow
          : null;
      return _windows.entries
          .where((entry) => entry.value == window)
          .firstOrNull
          ?.key;
    },
    select: (model, id) {
      final window = _windows[id];
      if (window == null) return;
      final long = window > _windows['200k']!;
      final variants = _models[model] ?? const <_ModelInfo>[];
      final variant = variants.length > 1
          ? variants.where((v) => v.long == long).firstOrNull
          : _variantOf(model);
      _window = window;
      final switched = _modelChange(variant?.value);
      // Restarted, it starts on the model.
      if (!_applyWindow()) _change([?switched]);
    },
  );

  static const _works = [
    KernelOption(
      'agent',
      'Agent',
      Icons.all_inclusive_rounded,
      'Plan, edit and run on its own',
    ),
    KernelOption(
      'ask',
      'Ask',
      Icons.chat_bubble_outline_rounded,
      'Discuss and read, no changes',
    ),
    KernelOption(
      'plan',
      'Plan',
      Icons.checklist_rounded,
      'Research and plan, then build',
    ),
  ];

  static const _approvals = [
    KernelOption(
      'default',
      'Ask for approval',
      Icons.front_hand_outlined,
      'Ask before edits and commands',
    ),
    KernelOption(
      'acceptEdits',
      'Accept edits',
      Icons.edit_note_rounded,
      'Edit files freely, ask before commands',
    ),
    KernelOption(
      'auto',
      'Approve for me',
      Icons.shield_outlined,
      'Ask only for what looks risky',
    ),
    KernelOption(
      'dontAsk',
      "Don't ask",
      Icons.do_not_disturb_on_outlined,
      'Deny whatever is not pre-approved',
    ),
    KernelOption(
      'bypassPermissions',
      'Full access',
      Icons.gpp_maybe_outlined,
      'No checks: any file, any command, the internet',
      caution: true,
    ),
  ];

  /// Sent with a message in Ask, so the model knows from the start (the
  /// CLI refuses changes either way). Not shown: a note, not the message.
  static const _askNote =
      '<system-reminder>The user is in Ask mode: discuss and answer only. '
      'Read and search as needed, but do not edit files or run commands '
      'that change anything; suggest changes instead.</system-reminder>';

  static String _pick(String? id, List<KernelOption> options, String or) =>
      options.any((option) => option.id == id) ? id! : or;

  /// The CLI's permission mode for what is picked. Ask runs as `dontAsk`:
  /// reading needs no approval, and whatever would change something is
  /// refused by the CLI itself.
  String get _mode => switch (_work) {
    'plan' => 'plan',
    'ask' => 'dontAsk',
    _ => _approval,
  };

  /// Tells a running CLI what is picked now.
  void _applyMode() {
    emitInfoChanged();
    final mode = _mode;
    if (!_running || mode == _cliMode) return;
    _cliMode = mode;
    unawaited(
      _control!
          .request('set_permission_mode', {'mode': mode})
          .then((response) {
            if (response['mode'] case final String mode) _reported(mode);
          })
          .catchError((_) {}),
    );
  }

  /// The CLI's mode as it reports it. A change it made itself (the model
  /// entered plan mode; a plan was approved) moves the picks along.
  void _reported(String mode) {
    if (mode == _cliMode) return;
    _cliMode = mode;
    if (mode == 'plan') {
      _work = 'plan';
    } else if (!(mode == 'dontAsk' && _work == 'ask')) {
      _work = 'agent';
      _approval = mode;
    }
    emitInfoChanged();
  }

  @override
  late final KernelChoiceSource mode = _Choice(
    options: () => _works,
    selected: () => _work,
    select: (id) {
      _work = id;
      _applyMode();
    },
  );

  @override
  late final KernelChoiceSource permission = _Choice(
    options: () => [
      for (final option in _approvals)
        if (option.id != 'auto' || (_currentModel?.supportsAuto ?? true))
          option,
    ],
    selected: () => _approval,
    select: (id) {
      _approval = id;
      _applyMode();
    },
  );

  @override
  late final ModelSetting effort = _ModelSetting(
    optionsFor: (model) => [
      for (final level in _variantOf(model)?.effortLevels ?? const <String>[])
        KernelOption(
          level,
          level == 'xhigh'
              ? 'X-High'
              : level[0].toUpperCase() + level.substring(1),
          Icons.speed_rounded,
          switch (level) {
            'low' => 'Fastest, least thinking',
            'medium' => 'Balanced',
            'high' => 'Thinks more',
            'xhigh' => 'Thinks a lot more',
            'max' => 'Most thinking, this session only',
            _ => '',
          },
        ),
    ],
    selected: () {
      final levels = _currentModel?.effortLevels ?? const <String>[];
      final effort = _running ? _appliedEffort : _effort;
      return levels.contains(effort) ? effort : null;
    },
    select: (model, id) {
      final switched = _modelChange(_variantOf(model)?.value);
      // Shown as picked until the CLI says otherwise.
      _effort = _appliedEffort = id;
      _change([
        ?switched,
        (
          'apply_flag_settings',
          {
            'settings': {'effortLevel': id},
          },
        ),
      ]);
    },
  );

  @override
  void emitInfoChanged() {
    _commandCache = null;
    super.emitInfoChanged();
  }
}

/// A control request: its subtype and fields.
typedef _Request = (String, Map<String, Object?>);

class _Permission {
  const _Permission(this.input, this.suggestions, this.questions);

  final Map<String, Object?> input;
  final List<Object?> suggestions;

  /// For AskUserQuestion: the questions, to key the answers by.
  final List<String> questions;
}

class _ModelInfo {
  const _ModelInfo({
    required this.value,
    required this.label,
    required this.description,
    this.resolved,
    this.effortLevels = const [],
    this.supportsAuto = false,
  });

  factory _ModelInfo.from(Map<String, Object?> raw) => _ModelInfo(
    value: '${raw['value']}',
    label: '${raw['displayName'] ?? raw['value']}',
    description: '${raw['description'] ?? ''}',
    resolved: raw['resolvedModel'] as String?,
    effortLevels: [
      if (raw['supportsEffort'] == true)
        for (final level in raw['supportedEffortLevels'] as List? ?? const [])
          '$level',
    ],
    supportsAuto: raw['supportsAutoMode'] == true,
  );

  final String value;
  final String label;
  final String description;
  final String? resolved;
  final List<String> effortLevels;
  final bool supportsAuto;

  /// Holds 1M tokens of context.
  bool get long =>
      ClaudeCodeKernel._isLong(value) ||
      ClaudeCodeKernel._isLong(resolved ?? '');
}

class _Catalog {
  const _Catalog({
    this.commands = const [],
    this.models = const [],
    this.terminalOnly = const [],
  });

  final List<KernelCommand> commands;
  final List<_ModelInfo> models;
  final List<String> terminalOnly;

  _Catalog copyWith({
    List<KernelCommand>? commands,
    List<_ModelInfo>? models,
    List<String>? terminalOnly,
  }) => _Catalog(
    commands: commands ?? this.commands,
    models: models ?? this.models,
    terminalOnly: terminalOnly ?? this.terminalOnly,
  );
}

/// A choice over state the kernel holds: options and selection read live.
class _Choice implements KernelChoiceSource {
  _Choice({
    required this._options,
    required this._selected,
    required this._select,
  });

  final List<KernelOption> Function() _options;
  final String? Function() _selected;
  final void Function(String id) _select;
  List<KernelOption> _cache = const [];

  /// The same list while unchanged, so pickers keep their identity.
  @override
  List<KernelOption> get options {
    final fresh = _options();
    if (!listEquals(fresh, _cache)) _cache = fresh;
    return _cache;
  }

  @override
  String? get selected => _selected();

  @override
  void select(String id) {
    if (id != selected) _select(id);
  }
}

/// A setting that goes with the model, read live.
class _ModelSetting implements ModelSetting {
  _ModelSetting({
    required this._optionsFor,
    required this._selected,
    required this._select,
  });

  final List<KernelOption> Function(String model) _optionsFor;
  final String? Function() _selected;
  final void Function(String model, String id) _select;

  @override
  List<KernelOption> optionsFor(String model) => _optionsFor(model);

  @override
  String? get selected => _selected();

  @override
  void select(String model, String id) => _select(model, id);
}
