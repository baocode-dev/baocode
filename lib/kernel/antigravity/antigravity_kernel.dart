import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import '../../models/model_provider.dart' show effortLabel;
import '../../remote/remote_location.dart';
import '../acp/acp_connection.dart';
import '../acp/mcp_endpoint.dart';
import '../agent_kernel.dart';
import '../claude_code/claude_sdk_tools.dart';
import '../kernel_event.dart';
import '../kernel_types.dart';
import 'agy_runtime.dart';
import 'antigravity_catalog.dart';
import 'antigravity_translator.dart';
import '../line_diff.dart';

/// Google's Antigravity CLI (`agy acp`) as a kernel, over the Agent Client
/// Protocol: its conversations are its own (kept by agy, shared with the
/// user's terminal), the project and the UI the app's.
///
/// What ACP leaves out is read from what agy keeps of a conversation (see
/// [AgyRecords]): its background tasks' ends, its subagents' work, what a
/// turn spent.
class AntigravityKernel
    with KernelEventSource
    implements
        AgentKernel,
        SelectsModel,
        SelectsEffort,
        SelectsMode,
        SelectsPermission,
        ProvidesCommands,
        LoadsHistory,
        AcceptsImages,
        QueuesMessages,
        RunsBackgroundTasks,
        ManagesMcpServers,
        ReportsUsage,
        ReportsContext {
  AntigravityKernel(
    this.descriptor,
    this._context, {
    AgyRuntime? runtime,
    this._quiet = const Duration(seconds: 4),
    this._pollEvery = const Duration(seconds: 3),
  }) : _runtime = runtime ?? AgyRuntime.local {
    final settings = _context.settings;
    _work = _pick(settings[KernelChoiceKind.mode.name], _works, 'agent');
    _approval = _pick(
      _approvalOf(settings[KernelChoiceKind.permission.name]),
      _approvals,
      'default',
    );
    _model = settings[KernelChoiceKind.model.name];
    _effort = settings[KernelChoiceKind.effort.name];
    final efforts = '${KernelChoiceKind.effort.name}@';
    for (final MapEntry(:key, :value) in settings.entries) {
      if (key.startsWith(efforts)) {
        _pickedEfforts[key.substring(efforts.length)] = value;
      }
    }
    _translator = AntigravityTranslator(emit: emit, nextSeq: () => nextSeq)
      ..onTasksChanged = _tasksChanged;
    if (_context.resume case final resume?) {
      _sessionId = resume.id;
      _prompted = true;
      _loadingHistory = true;
      unawaited(_ready());
    }
  }

  @override
  final KernelDescriptor descriptor;
  final KernelContext _context;
  final AgyRuntime _runtime;
  late final AntigravityTranslator _translator;

  String? get _cwd => _context.cwd;
  KernelWorkspace? get _workspace => _context.workspace?.call();

  // --- Health ------------------------------------------------------------------------

  @override
  KernelHealth get health => _health;
  KernelHealth _health = KernelHealth.idle;

  void _setHealth(KernelHealth health) {
    _health = health;
    if (!_disposed) emitInfoChanged();
  }

  bool _disposed = false;
  final Completer<void> _stopped = Completer();

  @override
  Future<void> get stopped => _stopped.future;

  // --- The connection ----------------------------------------------------------------

  AcpConnection? _connection;

  /// Starting [_connection] and its session; null once failed, to try
  /// again.
  Future<bool>? _starting;

  /// Whether the connection was ended on purpose (released, reconnected):
  /// not a failure.
  bool _ending = false;

  /// The app's own tools, served to it.
  McpEndpoint? _tools;

  String? _sessionId;

  /// Whether the conversation has had a message: agy keeps it from then on.
  bool _prompted = false;

  /// Whether the conversation was shown: loaded again (a restart), it is
  /// not read back twice.
  bool _shown = false;

  /// Whether updates are dropped: the conversation being read back again.
  bool _muted = false;

  @override
  String? get sessionId => _prompted ? _sessionId : null;

  @override
  void prepare() => unawaited(_ready());

  /// Starts agy and its session, unless done; whether it is up.
  Future<bool> _ready() => _starting ??= _start();

  Future<bool> _start() async {
    if (_disposed) return false;
    final cwd = _cwd;
    if (cwd == null) {
      _fail('Antigravity needs a project folder');
      return false;
    }
    if (RemoteLocation.hostOf(cwd) != null) {
      _setHealth(
        const KernelHealth(
          KernelHealthStatus.failed,
          setup: KernelSetup(KernelSetupKind.localOnly),
        ),
      );
      _historyRead();
      return false;
    }
    _setHealth(const KernelHealth(KernelHealthStatus.starting));
    AcpConnection? launched;
    try {
      final transport = await _runtime.start(cwd);
      if (_disposed) {
        transport.close();
        return false;
      }
      final connection = launched = _connection = AcpConnection(
        transport,
        onRequest: _agentRequest,
        onNotification: _notification,
      );
      _ending = false;
      unawaited(connection.exited.then((exit) => _exited(connection, exit)));
      final init = await connection.request('initialize', {
        'protocolVersion': 1,
        'clientCapabilities': {
          'fs': {'readTextFile': false, 'writeTextFile': false},
          'terminal': false,
        },
        'clientInfo': {'name': 'baocode', 'title': 'BaoCode', 'version': '1'},
      });
      final capabilities = init['agentCapabilities'];
      final loads = capabilities is Map && capabilities['loadSession'] == true;
      if (ClaudeSdkTools.serversFor(cwd).isNotEmpty) {
        _tools ??= await _runtime.serveTools(_toolMessage);
      }
      final session = <String, Object?>{
        'cwd': cwd,
        'mcpServers': [
          if (_tools case final tools?)
            {
              'type': 'http',
              'name': ClaudeSdkTools.server,
              'url': '${tools.url}',
              'headers': [
                for (final MapEntry(:key, :value) in tools.headers.entries)
                  {'name': key, 'value': value},
              ],
            },
        ],
        if (_directories case final folders when folders.isNotEmpty)
          'additionalDirectories': folders,
        if (_workspace?.instructions case final text? when text.isNotEmpty)
          '_meta': {
            'antigravity': {
              'systemPrompt': {'append': text},
            },
          },
      };
      final Map<String, Object?> started;
      if (_sessionId case final id? when _prompted) {
        if (!loads) throw const AgyUnavailable('This agy cannot resume');
        // Read back as it was the first time; dropped after.
        _muted = _shown;
        _translator.replaying = true;
        try {
          started = await connection.request('session/load', {
            ...session,
            'sessionId': id,
          });
        } finally {
          _translator.settle();
          _translator.replaying = false;
          _muted = false;
        }
        // What ran before ran in another agy, gone with it.
        _replayedAgents.addAll(_translator.agents.keys);
        _translator.tasks.clear();
      } else {
        started = await connection.request('session/new', session);
        _sessionId = started['sessionId'] as String?;
      }
      _shown = true;
      _historyRead();
      _options(started);
      await _applyPicks();
      _setHealth(KernelHealth.ready);
      unawaited(_watchRecords());
      return true;
    } on AgyUnavailable catch (error) {
      _historyRead();
      if (error.notInstalled) {
        _setHealth(
          KernelHealth(
            KernelHealthStatus.failed,
            message: error.message,
            setup: KernelSetup(KernelSetupKind.install, start: _install),
          ),
        );
      } else {
        _fail(error.message, detail: error.detail);
      }
    } on AcpError catch (error) {
      _historyRead();
      if (_signInNeeded(error)) {
        _setHealth(
          KernelHealth(
            KernelHealthStatus.failed,
            message: error.message,
            setup: KernelSetup(KernelSetupKind.login, start: _login),
          ),
        );
      } else if (!error.closed) {
        _fail('Antigravity could not start', detail: error.message);
      } else if (!_ending && launched != null) {
        // It ended as it started: what it said as it did.
        final exit = await launched.exited
            .timeout(const Duration(seconds: 5))
            .catchError((_) => const AcpExit(-1));
        _fail(
          'Antigravity could not start (exit code ${exit.code})',
          detail: exit.stderr.trim().isEmpty ? null : exit.stderr.trim(),
        );
      }
    } on Object catch (error) {
      _historyRead();
      _fail('Antigravity could not start', detail: '$error');
    }
    _starting = null;
    _end();
    return false;
  }

  /// The folders it works in besides [_cwd]: the workspace's others, and
  /// those it reaches into.
  List<String> get _directories {
    final workspace = _workspace;
    if (workspace == null) return const [];
    return [
      for (final folder in {...workspace.folders, ...workspace.reaches})
        if (folder != _cwd) folder,
    ];
  }

  static bool _signInNeeded(AcpError error) =>
      error.code == -32000 ||
      error.message.toLowerCase().contains('authentication required');

  void _fail(String message, {String? detail}) => _setHealth(
    KernelHealth(KernelHealthStatus.failed, message: message, detail: detail),
  );

  void _historyRead() {
    if (!_loadingHistory) return;
    _loadingHistory = false;
    if (!_disposed) emitInfoChanged();
  }

  /// Ends the connection on purpose.
  void _end() {
    final connection = _connection;
    if (connection == null) return;
    _connection = null;
    _ending = true;
    connection.close();
  }

  void _exited(AcpConnection connection, AcpExit exit) {
    if (!identical(connection, _connection) && !_disposed) {
      return;
    }
    if (_disposed) {
      if (!_stopped.isCompleted) _stopped.complete();
      return;
    }
    _connection = null;
    _starting = null;
    _failAsks();
    final turn = _turn;
    if (turn != null) {
      _translator.settle(interrupted: true);
      _notice(NoticeKind.error, 'Antigravity stopped');
      _endTurn(turn, interrupted: true);
    }
    _endTasks();
    if (_ending) {
      _setHealth(KernelHealth.idle);
      return;
    }
    final stderr = exit.stderr.trim();
    _fail(
      'Antigravity stopped (exit code ${exit.code})',
      detail: stderr.isEmpty ? null : stderr,
    );
  }

  @override
  void restart() {
    _end();
    _starting = null;
    _setHealth(KernelHealth.idle);
    unawaited(_ready());
  }

  /// Ends agy while idle, out of view: started again (its conversation
  /// loaded) when next used. Not while it works, nor while a task of its
  /// runs: they would end with it.
  @override
  void release() {
    if (_turn != null || _queue.isNotEmpty || _asks.isNotEmpty) return;
    if (_runningTasks.isNotEmpty) return;
    if (_connection == null) return;
    _end();
    _starting = null;
    _setHealth(KernelHealth.idle);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _idle?.cancel();
    _poll?.cancel();
    _failAsks();
    final connection = _connection;
    _connection = null;
    if (connection == null) {
      if (!_stopped.isCompleted) _stopped.complete();
    } else {
      connection.close();
      unawaited(
        connection.exited
            .timeout(const Duration(seconds: 5))
            .catchError((_) => const AcpExit(-1))
            .whenComplete(() {
              if (!_stopped.isCompleted) _stopped.complete();
            }),
      );
    }
    unawaited(_tools?.close());
    _tools = null;
    closeEvents();
  }

  // --- Setting it up -------------------------------------------------------------------

  /// Installs agy for the app, then starts it.
  void _install() {
    var shown = -1;
    _setHealth(
      const KernelHealth(
        KernelHealthStatus.failed,
        setup: KernelSetup(KernelSetupKind.install, progress: 0),
      ),
    );
    unawaited(
      _runtime
          .install(
            onProgress: (progress) {
              final percent = (progress * 100).floor();
              if (percent == shown || _disposed) return;
              shown = percent;
              _setHealth(
                KernelHealth(
                  KernelHealthStatus.failed,
                  setup: KernelSetup(
                    KernelSetupKind.install,
                    progress: progress,
                  ),
                ),
              );
            },
          )
          .then((_) => restart())
          .catchError((Object error) {
            if (_disposed) return;
            _setHealth(
              KernelHealth(
                KernelHealthStatus.failed,
                setup: KernelSetup(
                  KernelSetupKind.install,
                  start: _install,
                  error: '$error',
                ),
              ),
            );
          }),
    );
  }

  /// Signs agy in: the page to do it at given the user, and the code
  /// Google shows there taken back; then starts it.
  void _login() {
    final code = Completer<String?>();
    void waiting({Uri? link}) => _setHealth(
      KernelHealth(
        KernelHealthStatus.failed,
        setup: KernelSetup(
          KernelSetupKind.login,
          link: link,
          signingIn: true,
          submitCode: link == null
              ? null
              : (text) {
                  if (!code.isCompleted) code.complete(text.trim());
                },
          cancel: () {
            if (!code.isCompleted) code.complete(null);
          },
        ),
      ),
    );
    waiting();
    unawaited(
      _runtime
          .login(
            link: (uri) => waiting(link: uri),
            code: () => code.future,
          )
          .then((_) {
            if (!_disposed) restart();
          })
          .catchError((Object error) {
            if (_disposed) return;
            _setHealth(
              KernelHealth(
                KernelHealthStatus.failed,
                setup: KernelSetup(
                  KernelSetupKind.login,
                  start: _login,
                  error: code.isCompleted ? '$error' : null,
                ),
              ),
            );
          }),
    );
  }

  // --- What it reports -----------------------------------------------------------------

  void _notification(String method, Map<String, Object?> params) {
    if (_disposed || method != 'session/update') return;
    if (params['sessionId'] != _sessionId && _sessionId != null) return;
    final update = switch (params['update']) {
      final Map<Object?, Object?> update => update.cast<String, Object?>(),
      _ => null,
    };
    if (update == null) return;
    switch (update['sessionUpdate']) {
      case 'available_commands_update':
        _commandsFrom(update['availableCommands']);
      case 'current_mode_update':
        if (update['currentModeId'] case final String mode) _modeReported(mode);
      case 'config_option_update':
        _options(update);
      case 'usage_update':
        _usage(update);
      case 'session_info_update':
        if (_muted) return;
        if (update['title'] case final String title when title.isNotEmpty) {
          emit(SessionRenamed(nextSeq, title));
        }
      default:
        if (_muted) return;
        if (_translator.replaying) {
          _translator.update(update);
          return;
        }
        // Dropped: what a turn stopped still said.
        if (_draining) return;
        if (_turn == null) _wake();
        _translator.update(update);
        _activity();
    }
  }

  // --- Turns -----------------------------------------------------------------------------

  /// The turn running, ours or one it took up on its own.
  String? _turn;
  DateTime? _turnStarted;

  /// Whether [_turn] was taken up by agy on its own: it ends once agy is
  /// quiet a while.
  bool _unprompted = false;
  int _wakes = 0;
  Timer? _idle;

  /// The prompt agy is answering, until it does: the next is sent after.
  Future<void>? _prompting;

  /// Whether a turn stopped is still being answered: what comes of it is
  /// dropped.
  bool _draining = false;

  final Set<String> _sentTurns = {};
  final List<KernelTurn> _queue = [];

  @override
  void send(KernelTurn turn) {
    if (_disposed || !_sentTurns.add(turn.id)) return;
    if (_turn == null && _queue.isEmpty && _prompting == null) {
      _begin(turn);
      return;
    }
    emit(
      ItemUpserted(
        nextSeq,
        turn.id,
        UserMessageItem(
          text: turn.text,
          images: turn.images,
          queued: true,
          sentAt: DateTime.now(),
        ),
      ),
    );
    if (turn.now) {
      _queue.insert(0, turn);
      emit(QueueReordered(nextSeq, [for (final queued in _queue) queued.id]));
      cancel();
    } else {
      _queue.add(turn);
    }
    unawaited(_next());
  }

  void _begin(KernelTurn turn) {
    _idle?.cancel();
    _turn = turn.id;
    _unprompted = false;
    _turnStarted = DateTime.now();
    _translator
      ..turnId = turn.id
      ..begin();
    emit(TurnStarted(nextSeq, turn.id));
    emit(
      ItemUpserted(
        nextSeq,
        turn.id,
        UserMessageItem(
          text: turn.text,
          images: turn.images,
          sentAt: _turnStarted,
        ),
      ),
    );
    final prompting = _prompt(turn);
    _prompting = prompting;
    unawaited(
      prompting.whenComplete(() {
        if (identical(_prompting, prompting)) _prompting = null;
        _draining = false;
        unawaited(_next());
      }),
    );
  }

  Future<void> _prompt(KernelTurn turn) async {
    if (!await _ready() || _connection == null) {
      if (_turn == turn.id) {
        _notice(
          NoticeKind.error,
          _health.message ?? 'Antigravity is not ready',
        );
        _endTurn(turn.id, interrupted: true);
      }
      return;
    }
    if (_turn != turn.id) return;
    if (!_prompted) {
      _prompted = true;
      AntigravityCatalog.forget();
      emitInfoChanged();
    }
    try {
      final result = await _connection!.request('session/prompt', {
        'sessionId': _sessionId,
        'prompt': [
          if (turn.text.isNotEmpty) {'type': 'text', 'text': turn.text},
          for (final image in turn.images)
            {
              'type': 'image',
              'mimeType': image.mediaType,
              'data': base64Encode(image.bytes),
            },
          for (final note in turn.notes) {'type': 'text', 'text': note},
        ],
      });
      if (_turn != turn.id) return;
      final reason = result['stopReason'];
      if (reason == 'refusal') {
        _notice(NoticeKind.error, 'The model refused to go on');
      } else if (reason == 'max_tokens') {
        _notice(NoticeKind.warning, 'The reply hit the model\'s output limit');
      }
      await _finish(turn.id, interrupted: reason == 'cancelled');
    } on AcpError catch (error) {
      if (_turn != turn.id) return;
      if (!error.closed) {
        _notice(NoticeKind.error, error.message);
        if (_signInNeeded(error)) {
          _setHealth(
            KernelHealth(
              KernelHealthStatus.failed,
              message: error.message,
              setup: KernelSetup(KernelSetupKind.login, start: _login),
            ),
          );
        }
      }
      _translator.settle(interrupted: true);
      _endTurn(turn.id, interrupted: true);
    }
  }

  /// Takes up the next message queued, once agy is free.
  Future<void> _next() async {
    if (_turn != null || _queue.isEmpty) return;
    final prompting = _prompting;
    if (prompting != null) return;
    final turn = _queue.removeAt(0);
    _begin(turn);
  }

  /// agy took up something on its own (a task's end, a subagent's report):
  /// a turn of its own, until it is quiet.
  void _wake() {
    final id = 'agy-wake-${++_wakes}';
    _turn = id;
    _unprompted = true;
    _turnStarted = DateTime.now();
    _translator
      ..turnId = id
      ..begin();
    emit(TurnStarted(nextSeq, id, unprompted: true));
  }

  /// How long agy is quiet before a turn of its own is over.
  final Duration _quiet;

  /// Something came of the turn: one of its own ends once nothing more
  /// does for a while (no call under way).
  void _activity() {
    if (!_unprompted) return;
    _idle?.cancel();
    _idle = Timer(_quiet, () {
      final turn = _turn;
      if (!_unprompted || turn == null) return;
      if (_translator.calling || _asks.isNotEmpty) {
        _activity();
        return;
      }
      unawaited(_finish(turn, interrupted: false));
    });
  }

  /// Ends [turn] with what it spent, as agy kept it.
  Future<void> _finish(String turn, {required bool interrupted}) async {
    _translator.settle(interrupted: interrupted);
    TurnUsage? usage;
    if (!interrupted) {
      try {
        usage = await _turnUsage().timeout(const Duration(seconds: 2));
      } on Object {
        // Without it.
      }
    }
    if (_turn != turn) return;
    _endTurn(turn, interrupted: interrupted, usage: usage);
    unawaited(_watchRecords());
    _limitsAfterTurn();
  }

  void _endTurn(String turn, {required bool interrupted, TurnUsage? usage}) {
    if (_turn != turn) return;
    _idle?.cancel();
    _turn = null;
    _unprompted = false;
    _failAsks();
    emit(
      TurnEnded(
        nextSeq,
        turn,
        interrupted: interrupted,
        worked: switch (_turnStarted) {
          final started? => DateTime.now().difference(started),
          null => null,
        },
        usage: usage,
      ),
    );
    unawaited(_next());
  }

  /// What the last turn spent: its model's requests since the user's
  /// message, as agy logs them.
  Future<TurnUsage?> _turnUsage() async {
    final id = _sessionId;
    if (id == null) return null;
    final steps = await _runtime.records(id).steps();
    var input = 0;
    var output = 0;
    var any = false;
    for (final step in steps.reversed) {
      if (step['type'] == 'USER_INPUT') break;
      if (step['type'] != 'PLANNER_RESPONSE') continue;
      any = true;
      input += _int(step['input_tokens']) + _int(step['cache_read_tokens']);
      output += _int(step['output_tokens']);
    }
    return any ? TurnUsage(inputTokens: input, outputTokens: output) : null;
  }

  static int _int(Object? value) => value is num ? value.toInt() : 0;

  @override
  void cancel() {
    final turn = _turn;
    if (turn == null) return;
    if (!_unprompted && _prompting != null) _draining = true;
    if (!_toolsCancelled.isCompleted) _toolsCancelled.complete();
    _connection?.notify('session/cancel', {'sessionId': _sessionId});
    _translator.settle(interrupted: true);
    _endTurn(turn, interrupted: true);
  }

  void _notice(NoticeKind kind, String text) {
    emit(
      ItemUpserted(nextSeq, 'agy-notice-${++_notices}', NoticeItem(kind, text)),
    );
  }

  int _notices = 0;

  // --- Queued messages -------------------------------------------------------------------

  @override
  Future<bool> cancelQueued(String turnId) async {
    final index = _queue.indexWhere((turn) => turn.id == turnId);
    if (index < 0) return false;
    _queue.removeAt(index);
    emit(ItemRemoved(nextSeq, turnId));
    return true;
  }

  @override
  void sendQueuedNow(String turnId) {
    final index = _queue.indexWhere((turn) => turn.id == turnId);
    if (index < 0) return;
    _queue.insert(0, _queue.removeAt(index));
    emit(QueueReordered(nextSeq, [for (final turn in _queue) turn.id]));
    if (_turn != null) {
      cancel();
    } else {
      unawaited(_next());
    }
  }

  @override
  void moveQueued(String turnId, int index) {
    final at = _queue.indexWhere((turn) => turn.id == turnId);
    if (at < 0) return;
    final turn = _queue.removeAt(at);
    _queue.insert(index.clamp(0, _queue.length), turn);
    emit(QueueReordered(nextSeq, [for (final turn in _queue) turn.id]));
  }

  // --- What it asks ----------------------------------------------------------------------

  final Map<String, _Ask> _asks = {};
  int _askCount = 0;

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
    Map<String, Object?> selected(String id) => {
      'outcome': {'outcome': 'selected', 'optionId': id},
    };
    // Full access: nothing asked; nor with no one there to ask.
    if (allow != null &&
        (_approval == 'bypassPermissions' ||
            (_workspace?.approvesAll ?? false))) {
      return selected(allow);
    }
    final call = switch (params['toolCall']) {
      final Map<Object?, Object?> call => call.cast<String, Object?>(),
      _ => const <String, Object?>{},
    };
    final title = switch (call['title']) {
      final String title when title.trim().isNotEmpty => title.trim(),
      _ => 'Use a tool',
    };
    final id = 'agy-ask-${++_askCount}';
    final standard = options.any(
      (option) => '${option['kind']}'.startsWith(RegExp('allow_|reject_')),
    );
    final InteractionRequest request;
    if (standard) {
      final always = options
          .where((option) => option['kind'] == 'allow_always')
          .firstOrNull;
      request = ApprovalRequest(
        id: id,
        title: title,
        toolName: '${call['name'] ?? call['kind'] ?? 'tool'}',
        preview: _previewOf(call),
        alwaysAllowLabel: always?['name'] as String?,
      );
    } else {
      request = QuestionRequest(
        id: id,
        title: title,
        questions: [
          Question(
            prompt: title,
            allowOther: false,
            options: [
              for (final option in options)
                QuestionOption('${option['name'] ?? option['optionId']}'),
            ],
          ),
        ],
      );
    }
    final answered = Completer<Map<String, Object?>>();
    _asks[id] = _Ask(options: options, acp: answered);
    emit(InteractionRequested(nextSeq, request));
    return answered.future;
  }

  /// What an approval is for, from the call agy asks about.
  static ApprovalPreview? _previewOf(Map<String, Object?> call) {
    final input = switch (call['rawInput']) {
      final Map<Object?, Object?> input => input,
      _ => const {},
    };
    if (input['CommandLine'] case final String command) {
      return CommandPreview(
        command,
        description: input['toolSummary'] as String?,
      );
    }
    for (final block in call['content'] as List? ?? const []) {
      if (block case {
        'type': 'diff',
        'path': final String path,
        'newText': final String after,
      }) {
        final before = block['oldText'] as String? ?? '';
        return DiffPreview(path, lineDiff(before, after));
      }
    }
    return null;
  }

  @override
  void answer(String requestId, InteractionAnswer answer) {
    final ask = _asks.remove(requestId);
    if (ask == null) return;
    emit(InteractionResolved(nextSeq, requestId));
    if (ask.sdk case final sdk?) {
      sdk.complete(switch (answer) {
        ApprovalAnswer(:final decision) => decision,
        _ => null,
      });
      return;
    }
    String? optionOf(String kind) => ask.options
        .where((option) => option['kind'] == kind)
        .map((option) => option['optionId'] as String?)
        .firstOrNull;
    final optionId = switch (answer) {
      ApprovalAnswer(decision: ApprovalDecision.allowOnce) =>
        optionOf('allow_once') ?? optionOf('allow_always'),
      ApprovalAnswer(decision: ApprovalDecision.allowAlways) =>
        optionOf('allow_always') ?? optionOf('allow_once'),
      ApprovalAnswer(decision: ApprovalDecision.deny) =>
        optionOf('reject_once') ?? optionOf('reject_always'),
      QuestionAnswer(:final picks, skipped: false) =>
        ask.options
            .where(
              (option) =>
                  picks.firstOrNull?.firstOrNull ==
                  '${option['name'] ?? option['optionId']}',
            )
            .map((option) => option['optionId'] as String?)
            .firstOrNull,
      QuestionAnswer() => null,
    };
    ask.acp?.complete(
      optionId == null
          ? {
              'outcome': {'outcome': 'cancelled'},
            }
          : {
              'outcome': {'outcome': 'selected', 'optionId': optionId},
            },
    );
    // What to do instead: said in the next message.
    if (answer
        case ApprovalAnswer(decision: ApprovalDecision.deny, :final message?)
        when message.trim().isNotEmpty) {
      send(KernelTurn(id: '$requestId-instead', text: message.trim()));
    }
  }

  /// Gives up what is asked: the turn ended, or agy did.
  void _failAsks() {
    for (final MapEntry(key: id, value: ask) in [..._asks.entries]) {
      _asks.remove(id);
      if (!_disposed) emit(InteractionResolved(nextSeq, id));
      ask.acp?.complete({
        'outcome': {'outcome': 'cancelled'},
      });
      ask.sdk?.complete(null);
    }
  }

  // --- The app's own tools ---------------------------------------------------------------

  Completer<void> _toolsCancelled = Completer();

  Future<Map<String, Object?>?> _toolMessage(
    Map<String, Object?> message,
  ) async {
    final cwd = _cwd;
    if (cwd == null || _disposed) return null;
    // Asked first by agy, before `initialize`: not MCP's.
    if (message['method'] == 'server/discover') {
      return {
        'jsonrpc': '2.0',
        'id': message['id'] ?? 0,
        'error': {'code': -32601, 'message': 'Method not found'},
      };
    }
    if (_toolsCancelled.isCompleted) _toolsCancelled = Completer();
    return ClaudeSdkTools.handle(
      message,
      ClaudeSdkCall(
        cwd: cwd,
        sessionId: _sessionId,
        cancelled: _toolsCancelled.future,
        ask: _toolAsk,
      ),
    );
  }

  /// One of the app's own tools asks the user, on the conversation; in
  /// full access allowed without asking.
  Future<ApprovalDecision?> _toolAsk(ApprovalRequest request) {
    if (_approval == 'bypassPermissions') {
      return Future.value(ApprovalDecision.allowOnce);
    }
    if (_workspace?.approvesAll ?? false) return Future.value();
    final id = 'agy-tool-${++_askCount}';
    final answered = Completer<ApprovalDecision?>();
    _asks[id] = _Ask(options: const [], sdk: answered);
    emit(
      InteractionRequested(
        nextSeq,
        ApprovalRequest(
          id: id,
          title: request.title,
          toolName: request.toolName,
          reason: request.reason,
          preview: request.preview,
          alwaysAllowLabel: request.alwaysAllowLabel,
        ),
      ),
    );
    return answered.future;
  }

  // --- Choices ---------------------------------------------------------------------------

  static const _works = [
    KernelOption(
      'agent',
      'Agent',
      Icons.all_inclusive_rounded,
      'Plan, edit and run code',
    ),
    KernelOption(
      'plan',
      'Plan',
      Icons.checklist_rounded,
      'Research and plan, then build',
    ),
  ];

  /// As Claude Code's are named (the user's picks are kept by these
  /// names), each one of agy's modes but full access.
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
      'Approve edits and safe commands, ask before irreversible ones',
    ),
    KernelOption(
      'bypassPermissions',
      'Full access',
      Icons.gpp_maybe_outlined,
      'No checks: edits and commands run without asking',
      caution: true,
    ),
  ];

  /// A pick of Claude Code's approvals as one of these.
  static String? _approvalOf(String? id) => switch (id) {
    'dontAsk' => 'default',
    'accept-edits' => 'acceptEdits',
    _ => id,
  };

  static String _pick(String? id, List<KernelOption> options, String or) =>
      options.any((option) => option.id == id) ? id! : or;

  late String _work;
  late String _approval;

  /// agy's mode, as it last said.
  String? _agyMode;

  /// agy's mode for what is picked: Plan, else the approvals. Full access
  /// is its auto, what it still asks approved here.
  String get _wantedMode => _work == 'plan'
      ? 'plan'
      : switch (_approval) {
          'acceptEdits' => 'accept-edits',
          'auto' || 'bypassPermissions' => 'auto',
          _ => 'default',
        };

  void _modeReported(String mode) {
    _agyMode = mode;
    if (mode == 'plan') {
      _work = 'plan';
    } else {
      if (_work == 'plan') _work = 'agent';
      final approval = switch (mode) {
        'accept-edits' => 'acceptEdits',
        'auto' => _approval == 'bypassPermissions' ? _approval : 'auto',
        _ => 'default',
      };
      _approval = approval;
    }
    if (!_disposed) emitInfoChanged();
  }

  Future<void> _applyMode() async {
    final mode = _wantedMode;
    final connection = _connection;
    if (connection == null || _sessionId == null || mode == _agyMode) return;
    _agyMode = mode;
    try {
      await connection.request('session/set_mode', {
        'sessionId': _sessionId,
        'modeId': mode,
      });
    } on AcpError catch (error) {
      if (!error.closed) _notice(NoticeKind.error, error.message);
    }
  }

  @override
  late final KernelChoiceSource mode = _Choice(
    options: () => _works,
    selected: () => _work,
    select: (id) {
      _work = id;
      emitInfoChanged();
      unawaited(_applyMode());
    },
  );

  @override
  late final KernelChoiceSource permission = _Choice(
    options: () => _approvals,
    selected: () => _approval,
    select: (id) {
      _approval = id;
      emitInfoChanged();
      unawaited(_applyMode());
    },
  );

  /// Its models (families, their thinking apart), as it lists them.
  List<KernelOption> _models = const [];

  /// Its model ids, each a family's at a thinking level
  /// (`gemini-3.8-flash-low`): what levels each family has.
  List<String> _variants = const [];

  /// The thinking levels of the model in use, as it lists them.
  List<({String id, String name})> _levels = const [];

  String? _model;
  String? _effort;

  /// The model and level in effect, as it last said.
  String? _currentModel;
  String? _currentEffort;
  final Map<String, String> _pickedEfforts = {};

  /// What `session/new` or `config_option_update` says of its options.
  void _options(Map<String, Object?> result) {
    if (result['models'] case {'availableModels': final List models}) {
      _variants = [
        for (final model in models)
          if (model case {'modelId': final String id}) id,
      ];
    }
    if (result['modes'] case {'currentModeId': final String mode}) {
      _agyMode = mode;
    }
    for (final option in result['configOptions'] as List? ?? const []) {
      if (option is! Map) continue;
      final values = [
        for (final value in option['options'] as List? ?? const [])
          if (value case {'value': final String id})
            (
              id: id,
              name: value['name'] as String? ?? id,
              description: value['description'] as String? ?? '',
            ),
      ];
      final current = option['currentValue'] as String?;
      switch (option['id']) {
        case 'model':
          _models = [
            for (final value in values)
              KernelOption(
                value.id,
                value.name,
                Icons.auto_awesome_outlined,
                value.description,
              ),
          ];
          _currentModel = current;
        case 'thought_level':
          _levels = [
            for (final value in values) (id: value.id, name: value.name),
          ];
          _currentEffort = current;
        case 'mode':
          if (current != null) _agyMode = current;
      }
    }
    if (!_disposed) emitInfoChanged();
  }

  /// Puts what the user picked in effect in a session just started.
  Future<void> _applyPicks() async {
    final model = _model;
    if (model != null &&
        model != _currentModel &&
        _models.any((option) => option.id == model)) {
      await _setOption('model', model);
    }
    final effort = _pickedEfforts[_currentModel] ?? _effort;
    if (effort != null &&
        effort != _currentEffort &&
        _levels.any((level) => level.id == effort)) {
      await _setOption('thought_level', effort);
    }
    await _applyMode();
  }

  Future<void> _setOption(String id, String value) async {
    final connection = _connection;
    if (connection == null || _sessionId == null) return;
    try {
      final result = await connection.request('session/set_config_option', {
        'sessionId': _sessionId,
        'configId': id,
        'value': value,
      });
      _options(result);
    } on AcpError catch (error) {
      if (!error.closed) _notice(NoticeKind.error, error.message);
    }
  }

  @override
  late final KernelChoiceSource model = _Choice(
    options: () => _models,
    selected: () => _currentModel ?? _model,
    select: (id) {
      _model = id;
      _currentModel = id;
      emitInfoChanged();
      unawaited(
        _setOption('model', id).then((_) async {
          final effort = _pickedEfforts[id];
          if (effort != null &&
              effort != _currentEffort &&
              _levels.any((level) => level.id == effort)) {
            await _setOption('thought_level', effort);
          }
        }),
      );
    },
  );

  static const _levelWords = {
    'minimal',
    'none',
    'low',
    'medium',
    'high',
    'xhigh',
    'max',
  };

  /// The levels [model] thinks at: as it lists them for the one in use,
  /// else as its model ids tell.
  List<KernelOption> _effortsOf(String model) {
    final levels = model == _currentModel
        ? _levels
        : [
            for (final id in _variants)
              if (id.startsWith('$model-') &&
                  _levelWords.contains(id.substring(model.length + 1)))
                (
                  id: id.substring(model.length + 1),
                  name: effortLabel(id.substring(model.length + 1)),
                ),
          ];
    return [
      for (final level in levels)
        KernelOption(
          level.id,
          effortLabel(level.id),
          Icons.speed_rounded,
          switch (level.id) {
            'low' => 'Fastest, least thinking',
            'medium' => 'Balanced',
            'high' => 'Thinks more',
            'xhigh' => 'Thinks a lot more',
            _ => '',
          },
        ),
    ];
  }

  @override
  late final ModelSetting effort = _ModelSetting(
    optionsFor: _effortsOf,
    selected: () => _currentEffort,
    selectedFor: (model) {
      if (model == _currentModel) return _currentEffort;
      final options = _effortsOf(model);
      final picked = _pickedEfforts[model] ?? _effort;
      return options.any((option) => option.id == picked)
          ? picked
          : options.lastOrNull?.id;
    },
    select: (model, id) {
      _pickedEfforts[model] = id;
      _effort = id;
      if (model != _currentModel) {
        this.model.select(model);
        return;
      }
      _currentEffort = id;
      emitInfoChanged();
      unawaited(_setOption('thought_level', id));
    },
  );

  // --- Commands --------------------------------------------------------------------------

  @override
  List<KernelCommand> commands = const [];

  void _commandsFrom(Object? raw) {
    commands = [
      for (final command in raw is List ? raw : const [])
        if (command case {'name': final String name})
          KernelCommand(
            name,
            command['description'] as String? ?? '',
            Icons.terminal_rounded,
            argumentHint: switch (command['input']) {
              {'hint': final String hint} => hint,
              _ => '',
            },
          ),
    ];
    if (!_disposed) emitInfoChanged();
  }

  // --- Context and usage -----------------------------------------------------------------

  @override
  int get contextWindow => _window;
  int _window = 1048576;

  void _usage(Map<String, Object?> update) {
    final size = update['size'];
    final used = update['used'];
    if (size is num && size > 0) _window = size.toInt();
    if (used is! num) return;
    emit(
      UsageReported(nextSeq, ContextUsage(window: _window, used: used.toInt())),
    );
  }

  /// The account's limits as last asked, any session's.
  static List<RateLimitWindow> _limits = const [];
  static DateTime? _limitsAt;
  static Future<void>? _asking;

  @override
  List<RateLimitWindow> get accountLimits => _limits;

  @override
  Future<void> refreshUsage() {
    if (_disposed) return Future.value();
    return _asking ??= _askLimits().whenComplete(() => _asking = null);
  }

  Future<void> _askLimits() async {
    emit(
      StatsReported(
        nextSeq,
        UsageStats(limits: _limits, limitsState: LimitsState.checking),
      ),
    );
    var state = LimitsState.idle;
    try {
      final limits = await _runtime.quota();
      if (limits == null) {
        state = LimitsState.unavailable;
      } else {
        _limits = limits;
        _limitsAt = DateTime.now();
      }
    } on Object {
      state = LimitsState.unavailable;
    }
    if (_disposed) return;
    emit(
      StatsReported(nextSeq, UsageStats(limits: _limits, limitsState: state)),
    );
  }

  /// Asks for the limits once a turn ends, unless asked lately.
  void _limitsAfterTurn() {
    final at = _limitsAt;
    if (at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 2)) {
      return;
    }
    unawaited(refreshUsage());
  }

  // --- History ---------------------------------------------------------------------------

  bool _loadingHistory = false;

  @override
  bool get loadingHistory => _loadingHistory;

  /// agy reads a conversation back whole.
  @override
  bool get hasEarlierHistory => false;

  @override
  bool get loadingEarlier => false;

  @override
  Future<void> loadEarlier() => Future.value();

  // --- Background tasks and subagents ----------------------------------------------------

  Iterable<KernelTask> get _runningTasks => _translator.tasks.values.where(
    (task) => task.status == CommandStatus.running,
  );

  /// Tasks the user stopped watching: not shown again.
  final Set<String> _dropped = {};

  /// The subagents of the conversation as read back: they ran in an agy
  /// gone since, done one way or another.
  final Set<String> _replayedAgents = {};

  void _tasksChanged() {
    _reportTasks();
    unawaited(_watchRecords());
  }

  void _reportTasks() {
    if (_disposed) return;
    emit(
      TasksReported(nextSeq, [
        for (final task in _translator.tasks.values)
          if (!_dropped.contains(task.id)) task,
        for (final MapEntry(key: id, value: agent)
            in _translator.agents.entries)
          if (!_replayedAgents.contains(id) && !_dropped.contains(id))
            KernelTask(
              id: id,
              description: agent.description,
              kind: KernelTaskKind.agent,
              status: agent.status,
              startedAt: agent.startedAt ?? DateTime.now(),
              toolUseId: id,
              summary: agent.activity,
            ),
      ]),
    );
  }

  /// agy offers no way to stop one of its tasks over ACP: it is no longer
  /// shown, and runs on until agy ends.
  @override
  void stopTask(String taskId) {
    if (_dropped.add(taskId)) _reportTasks();
  }

  /// Its commands go on in the background on their own, never moved.
  @override
  void moveToBackground(String toolUseId) {}

  /// Tasks still running as agy ends: they end with it.
  void _endTasks() {
    var changed = false;
    for (final MapEntry(key: id, value: task) in [
      ..._translator.tasks.entries,
    ]) {
      if (task.status != CommandStatus.running) continue;
      _translator.tasks[id] = task.copyWith(status: CommandStatus.failed);
      changed = true;
    }
    if (changed) _reportTasks();
  }

  Timer? _poll;
  bool _reading = false;

  /// How often its records are read again while a task or subagent runs.
  final Duration _pollEvery;

  /// Reads what agy keeps of the conversation for what ACP does not tell
  /// (its tasks' ends, its subagents' work), again while any runs.
  Future<void> _watchRecords() async {
    _poll?.cancel();
    final id = _sessionId;
    if (id == null || _disposed || _reading) return;
    _reading = true;
    try {
      final records = _runtime.records(id);
      final inbox = await records.messages();
      _tasksFrom(inbox, records);
      if (_translator.agents.isNotEmpty) {
        await _agentsFrom(records, inbox);
      }
    } on Object {
      // Read again next time.
    } finally {
      _reading = false;
    }
    if (_disposed) return;
    final running =
        _runningTasks.isNotEmpty ||
        _translator.agents.values.any(
          (agent) => agent.status == CommandStatus.running,
        );
    if (running) _poll = Timer(_pollEvery, () => unawaited(_watchRecords()));
  }

  static final _taskEnd = RegExp(
    r'''Task id "?([^"\s]+)"? (finished|failed|was cancelled|was killed)''',
  );

  void _tasksFrom(List<Map<String, Object?>> inbox, AgyRecords records) {
    var changed = false;
    for (final message in inbox) {
      final content = '${message['content'] ?? ''}';
      final match = _taskEnd.firstMatch(content);
      final taskId = match?.group(1) ?? message['sender'] as String?;
      final task = _translator.tasks[taskId];
      if (task == null || task.status != CommandStatus.running) continue;
      final failed =
          match?.group(2) != 'finished' ||
          RegExp(r'exit code:?\s*[1-9]').hasMatch(content);
      _translator.tasks[task.id] = task.copyWith(
        status: failed ? CommandStatus.failed : CommandStatus.succeeded,
        summary: _firstLine(content.substring(match?.end ?? 0)),
        outputFile: records.taskLog(task.id),
      );
      changed = true;
    }
    for (final MapEntry(key: id, value: task) in [
      ..._translator.tasks.entries,
    ]) {
      if (task.outputFile != null) continue;
      _translator.tasks[id] = task.copyWith(outputFile: records.taskLog(id));
      changed = true;
    }
    if (changed) _reportTasks();
  }

  static String? _firstLine(String text) {
    final line = text
        .replaceFirst(RegExp(r'^\s*(with result:?)?\s*'), '')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .firstOrNull;
    if (line == null) return null;
    return line.length > 160 ? '${line.substring(0, 160)}…' : line;
  }

  /// The subagents' work, as agy keeps their conversations: the cards of
  /// [AntigravityTranslator.agents] filled in, in the order they started.
  Future<void> _agentsFrom(
    AgyRecords records,
    List<Map<String, Object?>> inbox,
  ) async {
    final children = await records.subagents();
    children.sort(
      (a, b) => _int(a['spawnStepIndex']).compareTo(_int(b['spawnStepIndex'])),
    );
    final cards = [..._translator.agents.entries];
    var changed = false;
    for (final (index, card) in cards.indexed) {
      if (index >= children.length) break;
      final child = children[index];
      final childId = child['conversationId'] as String?;
      if (childId == null) continue;
      // Read whole once done.
      if (card.value.status != CommandStatus.running &&
          card.value.children.isNotEmpty) {
        continue;
      }
      final steps = await records.child(childId).steps();
      final items = agyChildItems(steps);
      final report = inbox
          .where((message) => message['sender'] == childId)
          .map((message) => '${message['content'] ?? ''}')
          .lastOrNull;
      var tokens = 0;
      String? model;
      for (final step in steps) {
        if (step['type'] != 'PLANNER_RESPONSE') continue;
        tokens += _int(step['output_tokens']);
        model = step['model'] as String? ?? model;
      }
      final calls = items.whereType<ToolCallItem>().toList();
      final agent = card.value;
      // Done once it reports (to the inbox); one that ran in an agy gone
      // since is done all the same, or never will be.
      final status = agent.status == CommandStatus.failed
          ? CommandStatus.failed
          : report != null || _replayedAgents.contains(card.key)
          ? CommandStatus.succeeded
          : _connection == null
          ? CommandStatus.failed
          : CommandStatus.running;
      final updated = agent.copyWith(
        agentType: _string((child['subagentDescriptor'] as Map?)?['typeName']),
        status: status,
        children: items,
        toolUses: calls.length,
        lastTool: calls.lastOrNull?.label,
        activity: status == CommandStatus.running
            ? calls.lastOrNull?.target
            : null,
        tokens: tokens == 0 ? null : tokens,
        model: model,
        result: report,
        duration:
            agent.duration ??
            (status != CommandStatus.running &&
                    !_replayedAgents.contains(card.key) &&
                    agent.startedAt != null
                ? DateTime.now().difference(agent.startedAt!)
                : null),
      );
      _translator.agents[card.key] = updated;
      emit(ItemUpserted(nextSeq, card.key, updated));
      changed = true;
    }
    if (changed) _reportTasks();
  }

  static String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  // --- MCP servers -----------------------------------------------------------------------

  @override
  List<McpServer>? mcpServers;

  @override
  void refreshMcpServers() => unawaited(_readMcpServers());

  Future<void> _readMcpServers() async {
    final configured = await _runtime.mcpServers();
    if (_disposed) return;
    mcpServers = [
      if (_tools != null)
        const McpServer(
          name: ClaudeSdkTools.server,
          status: McpServerStatus.connected,
          scope: 'BaoCode',
        ),
      for (final server in configured)
        McpServer(
          name: server.name,
          status: server.enabled
              ? McpServerStatus.connected
              : McpServerStatus.disabled,
          scope: 'user',
        ),
    ];
    emitInfoChanged();
  }

  @override
  void setMcpServerEnabled(String name, bool enabled) {
    if (name == ClaudeSdkTools.server) return;
    unawaited(
      _runtime.setMcpServerEnabled(name, enabled).then((_) async {
        await _readMcpServers();
        _reconnect();
      }),
    );
  }

  @override
  void reconnectMcpServer(String name) => _reconnect();

  /// Starts agy again on the conversation, to take its servers anew; once
  /// idle, if it works now.
  void _reconnect() {
    if (_disposed || _connection == null) return;
    if (_turn != null || _runningTasks.isNotEmpty) return;
    _end();
    _starting = null;
    unawaited(_ready());
  }

  @override
  Future<Uri?> authenticateMcpServer(String name) async => null;
}

/// A subagent's conversation as items, from its steps (`transcript.jsonl`):
/// what it said, and the tools it called.
@visibleForTesting
List<ChatItem> agyChildItems(List<Map<String, Object?>> steps) {
  final items = <ChatItem>[];
  for (final step in steps) {
    if (step['type'] != 'PLANNER_RESPONSE') continue;
    if (step['content'] case final String text when text.trim().isNotEmpty) {
      items.add(AssistantTextItem(text.trim()));
    }
    for (final call in step['tool_calls'] as List? ?? const []) {
      if (call is! Map) continue;
      final name = '${call['name'] ?? ''}';
      final args = <String, Object?>{
        for (final MapEntry(:key, :value)
            in (call['args'] as Map? ?? const {}).entries)
          '$key': _argument(value),
      };
      String? arg(String key) => switch (args[key]) {
        final String value when value.trim().isNotEmpty => value,
        _ => null,
      };
      final path = arg('Path') ?? arg('AbsolutePath') ?? arg('File');
      final kind = switch (name) {
        'read_file' || 'view_file' || 'list_dir' => ToolKind.read,
        'edit_file' ||
        'write_file' ||
        'replace_file_content' ||
        'multi_replace_file_content' ||
        'write_to_file' => ToolKind.edit,
        'run_command' => ToolKind.command,
        'grep_search' || 'find_by_name' || 'search' => ToolKind.grep,
        'read_url_content' || 'search_web' || 'read_url' => ToolKind.web,
        'invoke_subagent' || 'start_subagent' => ToolKind.agent,
        _ when name.startsWith('mcp_') => ToolKind.mcp,
        _ => ToolKind.other,
      };
      items.add(
        ToolCallItem(
          kind: kind,
          label: name,
          path: path,
          target:
              path?.split(RegExp(r'[/\\]')).last ??
              arg('CommandLine') ??
              arg('Query') ??
              arg('Url') ??
              arg('toolSummary') ??
              '',
          input: args,
        ),
      );
    }
  }
  return items;
}

/// A tool call's argument as agy logs it: a JSON value written as text
/// (`"\"/a/b\""`), read back.
Object? _argument(Object? value) {
  if (value is! String) return value;
  final text = value.trim();
  if (text.isEmpty) return value;
  if (text.startsWith('"') ||
      text.startsWith('{') ||
      text.startsWith('[') ||
      text == 'true' ||
      text == 'false' ||
      num.tryParse(text) != null) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return value;
    }
  }
  return value;
}

/// Something agy waits on the user for: its own request, answered with
/// one of [options]; or one of the app's tools'.
class _Ask {
  _Ask({required this.options, this.acp, this.sdk});

  final List<Map<String, Object?>> options;
  final Completer<Map<String, Object?>>? acp;
  final Completer<ApprovalDecision?>? sdk;
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

class _ModelSetting implements ModelSetting {
  _ModelSetting({
    required this._optionsFor,
    required this._selected,
    required this._selectedFor,
    required this._select,
  });

  final List<KernelOption> Function(String model) _optionsFor;
  final String? Function() _selected;
  final String? Function(String model) _selectedFor;
  final void Function(String model, String id) _select;

  @override
  bool get toggle => false;

  @override
  List<KernelOption> optionsFor(String model) => _optionsFor(model);

  @override
  String? get selected => _selected();

  @override
  String? selectedFor(String model) => _selectedFor(model);

  @override
  void select(String model, String id) => _select(model, id);
}
