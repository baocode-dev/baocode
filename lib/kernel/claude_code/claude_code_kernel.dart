import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import '../../models/launch_environment.dart';
import '../../models/model_provider.dart';
import '../../models/model_providers.dart';
import '../../models/model_runtime.dart';
import '../agent_kernel.dart';
import '../commit_attribution.dart';
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

/// The environment of a session on [provider] that asks for [model] (see
/// [providerLaunchEnvironment]).
typedef ProviderEnvironment = Future<Map<String, String>> Function(
  ModelProvider provider,
  String model,
);

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
        ManagesMcpServers,
        ConfirmsModelSwitch {
  ClaudeCodeKernel(
    this.descriptor,
    this._context, {
    required this._start,
    ClaudeHistoryReader? readHistory,
    ClaudeUsageSwitch? usageOffBy,
    ModelProviders? providers,
    ProviderEnvironment? providerEnvironment,
  }) : _usageOffBy = usageOffBy ?? _usageOn,
       _providers = providers ?? ModelProviders.current,
       _providerEnvironment = providerEnvironment ?? providerLaunchEnvironment {
    _translator = ClaudeTranslator(emit: emit, nextSeq: () => nextSeq);
    _providers.addListener(_providersChanged);
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
    _window = switch (parseTokens(
      settings[KernelChoiceKind.context.name] ?? '',
    )) {
      final tokens? when tokens > 0 => tokens,
      _ => null,
    };
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

  /// The providers of the user's (Settings → Models), whose models are
  /// offered beside Claude Code's own.
  final ModelProviders _providers;
  final ProviderEnvironment _providerEnvironment;

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

  /// Whether the CLI says it is at work (`session_state_changed`): from a
  /// turn's start until, its `result` sent, nothing it queued follows.
  bool _cliWorking = false;

  /// Out of view, but busy when asked to free the process: freed once the
  /// CLI says it is idle.
  bool _releaseWanted = false;

  String? _turn;

  /// When [_turn] began, to time it if the CLI does not.
  DateTime? _turnStarted;
  final Map<String, KernelTurn> _sent = {};
  final Set<String> _queued = {};

  /// Turns stopped here: the CLI's word that it took one up (sent just
  /// before, it may not have yet) does not start it again.
  final Set<String> _stoppedTurns = {};
  final Map<String, _Permission> _permissions = {};
  String? _pendingTitle;

  // What the CLI offers and has in effect. The catalog of the last session
  // to start stands in until this one's arrives.
  static _Catalog _lastCatalog = const _Catalog();
  _Catalog _catalog = _lastCatalog;

  /// The model asked for, as the CLI names it (e.g. `opus[1m]`), or a
  /// provider's ([modelRef]).
  String? _model;

  /// What the process was started on: [_providerKey] then. A provider
  /// is taken up only at start, so another is by a restart (see
  /// [_applyWindow]).
  String _launchedProvider = '';
  String? _reportedModel;
  // What the agent does (Agent, Ask, Plan) and how its actions are
  // approved, picked apart: the CLI runs the approvals as they are, but in
  // Plan, which is a permission mode of its own (see _cliMode). Ask is only
  // said to the model.
  String _work = 'agent';
  String _approval = 'default';

  /// The last message went out in Ask: the next one, out of it, says so.
  bool _inAsk = false;

  /// The permission mode the CLI was last told, or last reported.
  String _cliMode = 'default';

  /// Whether the CLI was last told to leave Plan's commands to the auto
  /// mode classifier (`useAutoModeDuringPlan`).
  bool? _planReviewed;

  /// The effort asked for, and the one the CLI has in effect (it may
  /// step down one the model does not take).
  String? _effort;
  String? _appliedEffort;

  /// The context the conversation may fill before it is compacted, as
  /// picked (the CLI's `autoCompactWindow`); null to leave the CLI's own.
  int? _window;

  /// The [_window] the process was started with: the CLI takes it only
  /// at start, so another is taken up by a restart (see [_applyWindow]).
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
    return _starting ??= _launch().whenComplete(() => _starting = null);
  }

  Future<void> _launch() async {
    await _history;
    // One process at a time on a session: the last one, if restarted.
    await _stopped;
    _setHealth(const KernelHealth(KernelHealthStatus.starting));
    try {
      // On a provider of the user's: its model as it is asked for, the
      // environment that points Claude Code at it, and compaction within
      // the model's window. A model of one gone falls back to the CLI's.
      final custom = _custom;
      final effort = switch (custom) {
        (_, final info) => _effortFor(info),
        null => _effort,
      };
      final model = switch (custom) {
        (final provider, final info) => requestedModel(
          provider,
          info,
          effort: effort,
        ),
        null when parseModelRef(_model) != null => null,
        null => _model,
      };
      // Through the proxy, the effort goes with the model's name; to
      // Anthropic's API, as Claude Code's own, if it is one of its.
      final direct = custom == null || !custom.$1.protocol.proxied;
      Map<String, String>? env;
      if ((custom, model) case ((final provider, _), final model?)) {
        try {
          env = {
            // The window picked, as the model's own: else the CLI holds
            // the conversation to 200K. The provider's env may say else.
            ClaudeModelVariables.maxContextTokens: '${_autocompact!}',
            ...await _providerEnvironment(provider, model),
          };
        } on Object catch (error) {
          throw ClaudeUnavailable(
            '${provider.name} could not be set up',
            detail: '$error',
          );
        }
      }
      _launchedProvider = _providerKey;
      _launchedWindow = _autocompact;
      final transport = await _start(
        ClaudeLaunch(
          cwd: _cwd,
          resume: _sessionId,
          model: model,
          // Plan is entered once started.
          permissionMode: _cliMode = _approval,
          autoModeDuringPlan: _planReviewed = _reviewsPlan,
          effort: direct && (custom == null || _cliEfforts.contains(effort))
              ? effort
              : null,
          thinking: custom != null && direct && effort == 'none' ? false : null,
          autocompact: _autocompact,
          attribution: CommitAttribution.current(),
          env: env,
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
        if ((window, _custom == null ? _currentModel : null) case (
          final window?,
          final current?,
        ))
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
    _cliWorking = false;
    _releaseWanted = false;
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
    _releaseWanted = false;
    if (_health.status == KernelHealthStatus.failed) return;
    unawaited(_ensureStarted().catchError((_) {}));
  }

  @override
  void restart() {
    _teardown();
    _setHealth(KernelHealth.idle);
    prepare();
  }

  /// Whether stopping the process would cut work short: a turn (or the
  /// CLI's work past one), one to come, or a task in the background whose
  /// notice the agent awaits.
  bool get _busy =>
      _turn != null ||
      _cliWorking ||
      _queued.isNotEmpty ||
      _permissions.isNotEmpty ||
      _starting != null ||
      _translator.workingInBackground;

  /// Frees the process now if idle, else once the CLI says it is (one
  /// that does not say keeps it until asked again).
  @override
  void release() {
    if (_transport == null) return;
    if (_busy) {
      _releaseWanted = true;
      return;
    }
    _teardown();
    _setHealth(KernelHealth.idle);
  }

  /// Stops the process if another [_window] was picked since it started,
  /// for the next message to start it again on the same session: the CLI
  /// compacts where it was told at start, whatever it is told after. Done
  /// only as a message is sent, so a pick leaves the conversation be.
  ///
  /// So is another provider, or one whose setup changed: the session goes
  /// on, resumed, on it.
  void _applyWindow() {
    if (!_running || _busy) return;
    if (_providerKey == _launchedProvider && _autocompact == _launchedWindow) {
      return;
    }
    _teardown();
    _setHealth(KernelHealth.idle);
  }

  @override
  void dispose() {
    _disposed = true;
    _providers.removeListener(_providersChanged);
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
      // A context picked since it started: taken up now, while idle.
      _applyWindow();
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
    // Taken now: the message may wait for the CLI to start.
    final ask = _work == 'ask';
    final askEnded = _inAsk && !ask;
    _inAsk = ask;
    _whenReady(
      (transport) => transport.write({
        'type': 'user',
        'uuid': turn.id,
        'session_id': _sessionId ?? '',
        'parent_tool_use_id': null,
        'message': {
          'role': 'user',
          'content': [
            for (final image in turn.images) ...[
              // Its name, for the model to tell which the text means (and
              // this client, reading it back).
              if (image.number case final number?)
                {'type': 'text', 'text': imageReference(number)},
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': image.mediaType,
                  'data': base64Encode(image.bytes),
                },
              },
            ],
            if (turn.text.isNotEmpty) {'type': 'text', 'text': turn.text},
            if (ask)
              {'type': 'text', 'text': _askNote}
            else if (askEnded)
              {'type': 'text', 'text': _askEndedNote},
          ],
        },
      }),
    );
  }

  void _beginTurn(String id, {bool unprompted = false}) {
    _turn = id;
    _turnStarted = DateTime.now();
    _translator.turnId = id;
    emit(TurnStarted(nextSeq, id, unprompted: unprompted));
    _translator.begin();
  }

  void _endTurn({required bool interrupted, Duration? worked}) {
    final turn = _turn;
    if (turn == null) return;
    _turn = null;
    worked ??= switch (_turnStarted) {
      final started? => DateTime.now().difference(started),
      null => null,
    };
    _translator.settle();
    for (final id in _permissions.keys) {
      emit(InteractionResolved(nextSeq, id));
    }
    _permissions.clear();
    emit(TurnEnded(nextSeq, turn, interrupted: interrupted, worked: worked));
  }

  @override
  void cancel() {
    final turn = _turn;
    if (turn == null) return;
    _stoppedTurns.add(turn);
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
    // Answered here, with nothing shown: in full access no one is waited
    // on for a question while it builds (in Plan and Ask, questions are
    // the point), and in Don't ask nothing that is not pre-approved is
    // asked about (the CLI asks in Plan all the same). A plan is always
    // the user's to approve.
    if (switch ((_approval, tool)) {
          ('bypassPermissions', 'AskUserQuestion') when _work == 'agent' =>
            ClaudeTranslator.unattendedAnswer,
          ('dontAsk', != 'AskUserQuestion' && != 'ExitPlanMode') => _notAsked,
          _ => null,
        }
        case final message?) {
      _control!.respond(requestId, {'behavior': 'deny', 'message': message});
      return;
    }
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
        final approvals = _approvals
            .where((a) => a.id == _approval)
            .firstOrNull;
        interaction = PlanReviewRequest(
          id: requestId,
          title: 'Ready to code?',
          plan: plan ?? '(The plan could not be read.)',
          approvals: approvals,
          approveLabel: switch (approvals) {
            final approvals? => 'Yes, start · ${approvals.label}',
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
        // The model asked with no turn under way here: the CLI took up a
        // prompt of its own (a background task's notice, a scheduled one).
        // It is at work all the same: shown, and stopped, as any turn.
        if (message['status'] == 'requesting' && _turn == null) {
          _beginTurn('${message['uuid'] ?? 'own:$nextSeq'}', unprompted: true);
        }
        _translator.translate(message);
      case 'system' when message['subtype'] == 'session_state_changed':
        _cliWorking = message['state'] != 'idle';
        if (!_cliWorking && _releaseWanted) release();
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
        if (_turn != id &&
            _sent.containsKey(id) &&
            !_stoppedTurns.contains(id)) {
          _beginTurn(id);
        }
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
    _endTurn(
      interrupted: message['subtype'] != 'success',
      worked: switch (message['duration_ms']) {
        final num ms => Duration(milliseconds: ms.round()),
        _ => null,
      },
    );
    unawaited(_refreshContext());
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
    _translator.endTasks();
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
      _translator.endReplay();
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
    // Claude Code's own models are those it lists set up as the user has
    // it: one on a provider lists what the provider's names stand in for.
    final own = _launchedProvider.isEmpty;
    _catalog = _lastCatalog = _catalog.copyWith(
      commands: _commandsFrom(response['commands']),
      models: own
          ? [
              for (final raw in response['models'] as List? ?? const [])
                if (raw is Map) _ModelInfo.from(raw.cast<String, Object?>()),
            ]
          : _lastCatalog.models,
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

  // --- Providers --------------------------------------------------------------------

  /// The provider and model of the user's [_model] picks, if it is one.
  (ModelProvider, ProviderModel)? get _custom => _providers.resolve(_model);

  /// What a session on [model] is started on: '' for Claude Code as the
  /// user set it up, else the provider and its setup.
  String _providerKeyOf(String? model) => switch (_providers.resolve(model)) {
    (final provider, _) => '${provider.id}|${provider.launchFingerprint}',
    null => '',
  };

  String get _providerKey => _providerKeyOf(_model);

  /// Whether the conversation has begun: going on with it on another
  /// provider is a restart.
  bool get _conversationStarted => _sent.isNotEmpty || _context.resume != null;

  void _providersChanged() {
    if (_disposed) return;
    emitInfoChanged();
  }

  /// The heading Claude Code's own models are listed under.
  static const _builtinGroup = KernelOptionGroup(
    builtinProviderId,
    'Claude Code',
  );

  @override
  bool switchRestarts(String model) =>
      _conversationStarted && _providerKeyOf(model) != _providerKey;

  /// Switches to [id], an option of [model]: on the provider in use, as
  /// the CLI is told; on another, by starting again on it (at once, if
  /// the conversation has not begun; else as the next message is sent,
  /// which resumes it there).
  void _selectModel(String id) {
    final target = _providers.resolve(id);
    final sameProvider = _providerKeyOf(id) == _providerKey;
    if (sameProvider && target == null) {
      _change([?_modelChange(_variantOf(id)?.value)]);
      return;
    }
    if (sameProvider) {
      final (provider, info) = target!;
      final effort = _effortFor(info);
      _model = id;
      _change([
        (
          'set_model',
          {'model': requestedModel(provider, info, effort: effort)},
        ),
        if (!provider.protocol.proxied) ?_thinkingSettings(effort),
      ]);
      return;
    }
    _model = target == null ? _variantOf(id)?.value ?? id : id;
    if (_running && !_busy && !_conversationStarted) {
      restart();
      return;
    }
    // Taken up with the next message (see _applyWindow).
    emitInfoChanged();
  }

  /// The efforts Claude Code itself takes (`--effort`, `effortLevel`).
  static const _cliEfforts = {'low', 'medium', 'high', 'xhigh', 'max'};

  /// The effort a provider's model is on: the one picked, if it offers
  /// it, else its own.
  String? _effortFor(ProviderModel info) =>
      info.effortLevels.contains(_effort) ? _effort : info.initialEffort;

  /// The context a provider's model fills before compacting: the one
  /// picked, if it offers it, else its own.
  int _windowFor(ProviderModel info) =>
      info.contextOptions.contains(_window) ? _window! : info.initialContext;

  /// The context the session compacts at: a provider's model's, else as
  /// picked (null for the CLI's own).
  int? get _autocompact => switch (_custom) {
    (_, final info) => _windowFor(info),
    null => _window,
  };

  /// Turns the thinking of a provider's model not behind the proxy to
  /// [effort], as Claude Code's own settings: `none` turns it off.
  _Request? _thinkingSettings(String? effort) => effort == null
      ? null
      : (
          'apply_flag_settings',
          {
            'settings': {
              'effortLevel': ?(_cliEfforts.contains(effort) ? effort : null),
              'alwaysThinkingEnabled': effort != 'none',
            },
          },
        );

  List<String> _effortLevelsOf(String model) {
    if (_providers.resolve(model) case (_, final info)) {
      return info.effortLevels;
    }
    if (parseModelRef(model) != null) return const [];
    return _variantOf(model)?.effortLevels ?? const [];
  }

  @override
  late final KernelChoiceSource model = _Choice(
    options: () {
      final current = _custom;
      final providers = _providers.enabled;
      return [
        // Hidden only with a provider's models to pick instead.
        if (!_providers.builtinHidden || providers.isEmpty || current == null)
          if (_models.isEmpty)
            const KernelOption(
              'default',
              'Default',
              Icons.bolt_rounded,
              '',
              group: _builtinGroup,
            )
          else
            for (final MapEntry(key: id, value: variants) in _models.entries)
              KernelOption(
                id,
                // "Default (recommended)": the recommending goes without
                // saying.
                variants.first.label.replaceFirst(
                  RegExp(r'\s*\(recommended\)$', caseSensitive: false),
                  '',
                ),
                Icons.bolt_rounded,
                variants.first.description,
                group: _builtinGroup,
              ),
        for (final provider in providers)
          for (final info in provider.enabledModels)
            KernelOption(
              modelRef(provider.id, info.id),
              info.displayName,
              Icons.hub_outlined,
              [
                info.id,
                if (info.contextWindow case final tokens?) formatTokens(tokens),
              ].join(' · '),
              group: KernelOptionGroup(
                provider.id,
                provider.name,
                warning: _providers.error(provider.id),
              ),
            ),
      ];
    },
    selected: () {
      if (_custom != null) return _model;
      return switch (_currentModel?.value) {
        final value? => _baseOf(value),
        null => _models.isEmpty ? 'default' : null,
      };
    },
    select: _selectModel,
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
      // A provider's model: what it offers, by the number of tokens.
      if (_providers.resolve(model) case (_, final info)) {
        return [
          for (final tokens in info.contextOptions)
            KernelOption(
              '$tokens',
              formatTokens(tokens),
              Icons.notes_rounded,
              '',
            ),
        ];
      }
      if (parseModelRef(model) != null) return const [];
      final most = _modelWindowOf(model);
      final options = [
        for (final MapEntry(key: id, value: tokens) in _windows.entries)
          if (tokens <= most)
            KernelOption(id, id.toUpperCase(), Icons.notes_rounded, ''),
      ];
      return options.length > 1 ? options : const [];
    },
    selected: () {
      if (_custom case (_, final info)) return '${_windowFor(info)}';
      // Shown as picked until the process restarts with it, as the next
      // message is sent.
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
      if (_providers.resolve(model) != null) {
        final tokens = parseTokens(id);
        if (tokens == null || tokens <= 0) return;
        _window = tokens;
        // Taken up with the next message (see _applyWindow).
        if (model != _model) {
          _selectModel(model);
        } else {
          emitInfoChanged();
        }
        return;
      }
      final window = _windows[id];
      if (window == null) return;
      final long = window > _windows['200k']!;
      final variants = _models[model] ?? const <_ModelInfo>[];
      final variant = variants.length > 1
          ? variants.where((v) => v.long == long).firstOrNull
          : _variantOf(model);
      _window = window;
      // Taken up with the next message (see _applyWindow); the model,
      // now.
      _change([?_modelChange(variant?.value)]);
    },
  );

  static const _works = [
    KernelOption(
      'agent',
      'Agent',
      Icons.all_inclusive_rounded,
      'Plan, edit and run code',
    ),
    KernelOption(
      'ask',
      'Ask',
      Icons.chat_bubble_outline_rounded,
      'Talk it through, suggest changes',
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
      'Run what is safe, block what looks risky',
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
      'No checks, and no questions while it works',
      caution: true,
    ),
  ];

  /// Sent with each message in Ask: all there is to it, the approvals
  /// stay as picked. Not shown: a note, not the message.
  static const _askNote =
      '<system-reminder>The user is in Ask mode: discuss and answer only. '
      'Read and search as needed, but do not edit files or run commands '
      'that change anything; suggest changes instead.</system-reminder>';

  /// Sent with the first message out of Ask, or the model goes on by the
  /// notes before it.
  static const _askEndedNote =
      '<system-reminder>The user has left Ask mode: you may now edit files '
      'and run commands as the task needs.</system-reminder>';

  /// The answer to what would be asked in Don't ask.
  static const _notAsked =
      'The user is not asked in this mode, and this is not pre-approved.';

  static String _pick(String? id, List<KernelOption> options, String or) =>
      options.any((option) => option.id == id) ? id! : or;

  /// The CLI's permission mode for what is picked: the approvals, but in
  /// Plan.
  String get _mode => _work == 'plan' ? 'plan' : _approval;

  /// Plan's commands are left to the classifier with the approvals that
  /// approve for the user; asked about with the others.
  bool get _reviewsPlan =>
      _approval == 'auto' || _approval == 'bypassPermissions';

  /// Tells a running CLI what is picked now.
  void _applyMode() {
    _applyPlanReview();
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
    } else {
      if (_work == 'plan') _work = 'agent';
      _approval = mode;
      _applyPlanReview();
    }
    emitInfoChanged();
  }

  void _applyPlanReview() {
    final reviewed = _reviewsPlan;
    if (!_running || reviewed == _planReviewed) return;
    _planReviewed = reviewed;
    _change([
      (
        'apply_flag_settings',
        {
          'settings': {'useAutoModeDuringPlan': reviewed},
        },
      ),
    ]);
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
        if (option.id != 'auto' ||
            (_custom == null && (_currentModel?.supportsAuto ?? true)))
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
      for (final level in _effortLevelsOf(model))
        KernelOption(
          level,
          effortLabel(level),
          Icons.speed_rounded,
          switch (level) {
            'none' => 'No thinking',
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
      if (_custom case (_, final info)) return _effortFor(info);
      final levels = _currentModel?.effortLevels ?? const <String>[];
      final effort = _running ? _appliedEffort : _effort;
      return levels.contains(effort) ? effort : null;
    },
    select: (model, id) {
      if (_providers.resolve(model) case (final provider, final info)) {
        _effort = _appliedEffort = id;
        if (model != _model || _providerKeyOf(model) != _launchedProvider) {
          _selectModel(model);
          return;
        }
        // Through the proxy, the effort goes with the model's name;
        // to Anthropic's API, as Claude Code's own setting.
        _change([
          if (provider.protocol.proxied)
            ('set_model', {'model': requestedModel(provider, info, effort: id)})
          else
            ?_thinkingSettings(id),
        ]);
        return;
      }
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
