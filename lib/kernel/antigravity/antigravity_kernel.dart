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
import '../output_meter.dart';
import 'agy_runtime.dart';
import 'antigravity_catalog.dart';
import 'antigravity_translator.dart';
import '../line_diff.dart';

/// Google's Antigravity CLI (`agy acp`) as a kernel, over the Agent Client
/// Protocol: its conversations are its own (kept by agy, shared with the
/// user's terminal), the project and the UI the app's.
///
/// What ACP leaves out of its own background tasks (their ends) is read
/// from what agy keeps of a conversation (see [AgyRecords]).
class AntigravityKernel
    with KernelEventSource
    implements
        AgentKernel,
        SelectsModel,
        SelectsEffort,
        SelectsMode,
        SelectsPermission,
        StartsPlans,
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
    this._replayGap = const Duration(milliseconds: 300),
  }) : _runtime = runtime ?? AgyRuntime.local {
    _restore();
    _models = _lastModels;
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
    _translator = AntigravityTranslator(
      emit: emit,
      nextSeq: () => nextSeq,
      fileText: _runtime.fileText,
    )..onTasksChanged = _tasksChanged;
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

  /// The agy started for the conversation, starting or up; null before
  /// one, and once ended (released, restarted, failed or gone). A start
  /// left behind (its run ended while it waited) finds another here, or
  /// none, and leaves all to it.
  _Run? _run;

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
  Future<bool> _ready() => (_run ?? _launch()).ready;

  _Run _launch() {
    final run = _run = _Run();
    run.ready = _start(run);
    return run;
  }

  /// Starts [run]'s agy and its session: this conversation's, loaded, or a
  /// new one. Whether it is up; false too when [run] was ended meanwhile.
  Future<bool> _start(_Run run) async {
    // Not within its caller's frame: a screen opening on it is building.
    await Future<void>.value();
    if (!identical(_run, run)) return false;
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
    try {
      final transport = await _runtime.start(cwd);
      if (!identical(_run, run)) {
        // Ended before it had the process: nothing else ends it.
        transport.close();
        return false;
      }
      final connection = run.connection = AcpConnection(
        transport,
        onRequest: _agentRequest,
        onNotification: _notification,
      );
      unawaited(connection.exited.then((exit) => _exited(run, exit)));
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
        _translator
          ..replaying = true
          ..planning = _work == 'plan';
        // agy reads it back at once, then answers a fixed ~2 s later: the
        // conversation is shown as the reading goes quiet, not then.
        run.loading = true;
        run.replayed(_replayGap, () => _readBack(run));
        try {
          started = await connection.request('session/load', {
            ...session,
            'sessionId': id,
          });
        } finally {
          run.loading = false;
          _translator.settle();
          if (!_muted) _translator.endPlanRound();
          _translator.replaying = false;
          _muted = false;
        }
        // What ran before ran in another agy, gone with it.
        _translator.tasks.clear();
      } else {
        started = await connection.request('session/new', session);
        _sessionId = started['sessionId'] as String?;
      }
      if (!identical(_run, run)) return false;
      _readBack(run);
      _options(started);
      await _applyPicks();
      if (!identical(_run, run)) return false;
      _setHealth(KernelHealth.ready);
      unawaited(_watchRecords());
      if (!_limitsFresh(const Duration(minutes: 5))) _limitsAfterTurn();
      return true;
    } on Object catch (error) {
      // Ended while it started (released, restarted, disposed): the end
      // was meant, and whatever took its place has the conversation.
      if (!identical(_run, run)) return false;
      _historyRead();
      switch (error) {
        case AgyUnavailable(notInstalled: true):
          _setHealth(
            KernelHealth(
              KernelHealthStatus.failed,
              message: error.message,
              setup: KernelSetup(KernelSetupKind.install, start: _install),
            ),
          );
        case AgyUnavailable():
          _fail(error.message, detail: error.detail);
        case AcpError() when _signInNeeded(error):
          _setHealth(
            KernelHealth(
              KernelHealthStatus.failed,
              message: error.message,
              setup: KernelSetup(KernelSetupKind.login, start: _login),
            ),
          );
        case AcpError(closed: false):
          _fail('Antigravity could not start', detail: error.message);
        case AcpError():
          // Its agy ended as it started: what it said as it did.
          final exit = await run.connection!.exited
              .timeout(const Duration(seconds: 5))
              .catchError((_) => const AcpExit(-1));
          _fail(
            'Antigravity could not start (exit code ${exit.code})',
            detail: exit.stderr.trim().isEmpty ? null : exit.stderr.trim(),
          );
        default:
          _fail('Antigravity could not start', detail: '$error');
      }
    }
    if (identical(_run, run)) _run = null;
    run.end();
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

  /// How long agy's reading back of a conversation is quiet before the
  /// conversation is shown, its answer to `session/load` still to come.
  final Duration _replayGap;

  /// Shows [run]'s conversation, once: as its reading back goes quiet, or
  /// as agy answers, whichever comes first. Shown early, it is ready to
  /// the user; a message waits for the answer ([_prompt]), a pick for
  /// [_applyPicks] after it.
  void _readBack(_Run run) {
    if (!identical(_run, run) || run.shown) return;
    run.shown = true;
    _translator.settle();
    _shown = true;
    _timeHistory();
    _historyRead();
    if (run.loading) _setHealth(KernelHealth.ready);
  }

  /// Ends the run on purpose: no run, till the next start.
  void _end() {
    final run = _run;
    if (run == null) return;
    _run = null;
    run.end();
  }

  /// [run]'s agy is gone. One ended on purpose is no longer [_run] by then
  /// (see [_end]); one still it went by itself.
  void _exited(_Run run, AcpExit exit) {
    if (!identical(run, _run)) return;
    _run = null;
    _failAsks();
    final turn = _turn;
    if (turn != null) {
      _translator.settle(interrupted: true);
      _notice(NoticeKind.error, 'Antigravity stopped');
      _endTurn(turn, interrupted: true);
    }
    _endTasks();
    final stderr = exit.stderr.trim();
    _fail(
      'Antigravity stopped (exit code ${exit.code})',
      detail: stderr.isEmpty ? null : stderr,
    );
  }

  @override
  void restart() {
    _end();
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
    if (_run == null) return;
    _end();
    _setHealth(KernelHealth.idle);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _idle?.cancel();
    _poll?.cancel();
    _failAsks();
    final run = _run;
    _run = null;
    run?.end();
    if (run?.connection case final connection?) {
      unawaited(
        connection.exited
            .timeout(const Duration(seconds: 5))
            .catchError((_) => const AcpExit(-1))
            .whenComplete(() {
              if (!_stopped.isCompleted) _stopped.complete();
            }),
      );
    } else if (!_stopped.isCompleted) {
      _stopped.complete();
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
        if (update['title'] case final String said) {
          final title = AntigravityTranslator.withoutReminders(said);
          if (title.isNotEmpty) emit(SessionRenamed(nextSeq, title));
        }
      default:
        if (_muted) return;
        if (_translator.replaying) {
          _translator.update(update);
          if (_run case final run? when run.loading) {
            run.replayed(_replayGap, () => _readBack(run));
          }
          return;
        }
        // Dropped: what a turn stopped still said.
        if (_draining) return;
        // A command's end, run on past its turn: its task, not a turn.
        if (_turn == null && _translator.backgroundUpdate(update)) {
          _translator.update(update);
          return;
        }
        if (_turn == null) _wake();
        _translator.update(update);
        _meter(update);
        _activity();
    }
  }

  /// What the turn's model writes, guessed from its text as it streams:
  /// agy says how much only as the turn ends ([_finish]).
  final OutputMeter _output = OutputMeter();
  DateTime? _outputReported;
  static const _outputEvery = Duration(milliseconds: 250);

  void _meter(Map<String, Object?> update) {
    switch (update) {
      case {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'text': final String text},
      }:
        _output.streamed(text);
      case {
        'sessionUpdate': 'agent_thought_chunk',
        'content': {'text': final String text},
      }:
        _output.streamed(text, timed: false);
      // A call ends the model's request: its time stops till the next.
      case {
        'sessionUpdate': 'tool_call',
        'rawInput': final Map<Object?, Object?> input,
      }:
        _output
          ..streamed(jsonEncode(input))
          ..endMessage();
      default:
        return;
    }
    final now = DateTime.now();
    if (_outputReported case final at? when now.difference(at) < _outputEvery) {
      return;
    }
    _outputReported = now;
    emit(OutputReported(nextSeq, _output.output));
  }

  void _meterTurn() {
    _output.begin();
    _outputReported = null;
  }

  // --- Turns -----------------------------------------------------------------------------

  /// The turn running, ours or one it took up on its own.
  String? _turn;
  DateTime? _turnStarted;

  /// What the user said for [_turn]; null for one agy took up on its own.
  String? _turnText;

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

  /// Set by [startBuilding]: the next message starts the plan awaiting.
  bool _startsPlan = false;

  @override
  void startBuilding() {
    _startsPlan = true;
    _work = 'agent';
    emitInfoChanged();
    unawaited(_applyMode());
  }

  @override
  void send(KernelTurn sent) {
    if (_disposed || !_sentTurns.add(sent.id)) return;
    var turn = sent;
    if (_startsPlan) {
      _startsPlan = false;
      if (_translator.awaitingPlan case final plan?) {
        // Told with it, so that it builds rather than plans on.
        turn = KernelTurn(
          id: sent.id,
          text: sent.text,
          mentions: sent.mentions,
          images: sent.images,
          now: sent.now,
          notes: [
            ...sent.notes,
            '<system-reminder>The user approved the plan in ${plan.path}. '
                'Carry it out now.</system-reminder>',
          ],
        );
        _translator.resolvePlan(started: true);
      }
    }
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
      _sendNow(turn.id);
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
    _turnText = turn.text.trim();
    _meterTurn();
    _translator
      ..turnId = turn.id
      ..planning = _work == 'plan'
      ..resolvePlan(started: false, feedback: turn.text)
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
    final connection = await _ready() ? _run?.connection : null;
    if (connection == null) {
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
      final result = await connection.request('session/prompt', {
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
      await _finish(
        turn.id,
        interrupted: reason == 'cancelled',
        usage: switch (result['usage']) {
          final Map<Object?, Object?> usage => TurnUsage(
            inputTokens:
                _int(usage['inputTokens']) +
                _int(usage['cachedReadTokens']) +
                _int(usage['cachedWriteTokens']),
            outputTokens: _int(usage['outputTokens']),
            tokensPerSecond: _output.averageSpeed,
          ),
          _ => null,
        },
      );
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
    _turnText = null;
    _meterTurn();
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

  /// Ends [turn] with what it spent, as agy said ([usage]).
  Future<void> _finish(
    String turn, {
    required bool interrupted,
    TurnUsage? usage,
  }) async {
    _translator.settle(interrupted: interrupted);
    if (!interrupted) {
      _translator
        ..background()
        ..endPlanRound();
    }
    if (_turn != turn) return;
    _endTurn(turn, interrupted: interrupted, usage: usage);
    unawaited(_watchRecords());
    _limitsAfterTurn();
  }

  /// Ends [turn]; one [handedOn] to a message sent in it keeps what it
  /// asks the user, and the next queued waits.
  void _endTurn(
    String turn, {
    required bool interrupted,
    TurnUsage? usage,
    bool handedOn = false,
  }) {
    if (_turn != turn) return;
    _idle?.cancel();
    _turn = null;
    _unprompted = false;
    if (!handedOn) _failAsks();
    final started = _turnStarted;
    final worked = started == null ? null : DateTime.now().difference(started);
    emit(
      TurnEnded(
        nextSeq,
        turn,
        interrupted: interrupted,
        worked: worked,
        usage: usage,
      ),
    );
    if ((_sessionId, _turnText, started, worked) case (
      final id?,
      final text?,
      final started?,
      final worked?,
    )) {
      _runtime.timeTurn(id, {
        'text': text,
        'sentAt': started.millisecondsSinceEpoch,
        'workedMs': worked.inMilliseconds,
        if (usage != null) ...{
          'input': usage.inputTokens,
          'output': usage.outputTokens,
        },
      });
    }
    _turnText = null;
    if (handedOn) return;
    _stopBackground();
    unawaited(_next());
  }

  static int _int(Object? value) => value is num ? value.toInt() : 0;

  /// The turns read back, timed as this app timed them when they ran:
  /// when each was sent, how long it took and what it spent. Matched from
  /// the latest by what the user said; one run elsewhere (agy in a
  /// terminal) has no time and is passed over.
  void _timeHistory() {
    final id = _sessionId;
    final messages = _translator.replayed.entries.toList();
    _translator.replayed.clear();
    if (id == null || messages.isEmpty) return;
    final turns = _runtime.turnsTimed(id);
    var t = turns.length - 1;
    for (var m = messages.length - 1; m >= 0 && t >= 0; m--) {
      final MapEntry(key: itemId, value: message) = messages[m];
      final turn = turns[t];
      final text = turn['text'];
      final said = message.text.trim();
      if (text is! String || !(said == text || said.startsWith(text))) {
        continue;
      }
      t--;
      final (sentAt, workedMs) = (turn['sentAt'], turn['workedMs']);
      if (sentAt is! int || workedMs is! int) continue;
      final (input, output) = (turn['input'], turn['output']);
      emit(
        ItemUpserted(
          nextSeq,
          itemId,
          UserMessageItem(
            text: message.text,
            images: message.images,
            sentAt: DateTime.fromMillisecondsSinceEpoch(sentAt),
            worked: Duration(milliseconds: workedMs),
            usage: input is int && output is int
                ? TurnUsage(inputTokens: input, outputTokens: output)
                : null,
          ),
        ),
      );
    }
  }

  @override
  void cancel() {
    final turn = _turn;
    if (turn == null) return;
    if (!_unprompted && _prompting != null) _draining = true;
    if (!_toolsCancelled.isCompleted) _toolsCancelled.complete();
    _run?.connection?.notify('session/cancel', {'sessionId': _sessionId});
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
    _sendNow(turnId);
  }

  /// Sends the queued [turnId] while agy is at work. agy takes a prompt
  /// sent mid-turn as a word in, not a turn after: it answers the one
  /// under way at once (`end_turn`) and goes on, its commands and
  /// subagents still at work, answering both. So the turn under way ends
  /// here, and this one goes on from it.
  void _sendNow(String turnId) {
    final current = _turn;
    final turn = _queue.where((turn) => turn.id == turnId).firstOrNull;
    if (current == null || turn == null) {
      unawaited(_next());
      return;
    }
    _queue.remove(turn);
    _translator.settle();
    _endTurn(current, interrupted: false, handedOn: true);
    _begin(turn);
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
    final connection = _run?.connection;
    if (connection == null || _sessionId == null || mode == _agyMode) return;
    // Picked as the session loads: kept, put in effect once it has.
    if (_run?.loading ?? false) return;
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
  /// Its models, as agy last told them (in any conversation): offered
  /// until it tells this one's, which a cold agy takes seconds to.
  late List<KernelOption> _models;
  static List<KernelOption> _lastModels = const [];

  /// Whether what was kept from the last run ([AgyRuntime.kept]) was read
  /// back: once a run.
  static bool _restored = false;

  /// Forgets what was read back, for a test to start afresh.
  @visibleForTesting
  static void forgetKept() {
    _restored = false;
    _lastModels = const [];
    _limits = const [];
    _limitsAt = null;
  }

  void _restore() {
    if (_restored) return;
    _restored = true;
    final kept = _runtime.kept;
    if (kept == null) return;
    _lastModels = [
      for (final model in kept['models'] as List? ?? const [])
        if (model case {'id': final String id, 'name': final String name})
          KernelOption(
            id,
            name,
            Icons.auto_awesome_outlined,
            model['description'] as String? ?? '',
          ),
    ];
    _limits = [
      for (final limit in kept['limits'] as List? ?? const [])
        if (limit case {
          'label': final String label,
          'utilization': final num used,
        })
          RateLimitWindow(
            label,
            used.toDouble(),
            resetsAt: switch (limit['resetsAt']) {
              final String at => DateTime.tryParse(at),
              _ => null,
            },
          ),
    ];
    _limitsAt = switch (kept['limitsAt']) {
      final String at => DateTime.tryParse(at),
      _ => null,
    };
  }

  /// Keeps the models and limits as last told, for the next run to start
  /// with rather than ask again.
  void _keep() {
    _runtime.kept = {
      'models': [
        for (final model in _lastModels)
          {
            'id': model.id,
            'name': model.label,
            'description': model.description,
          },
      ],
      'limits': [
        for (final limit in _limits)
          {
            'label': limit.label,
            'utilization': limit.utilization,
            if (limit.resetsAt case final at?) 'resetsAt': at.toIso8601String(),
          },
      ],
      if (_limitsAt case final at?) 'limitsAt': at.toIso8601String(),
    };
  }

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
          final told = [
            for (final value in values)
              KernelOption(
                value.id,
                value.name,
                Icons.auto_awesome_outlined,
                value.description,
              ),
          ];
          final changed =
              told.length != _lastModels.length ||
              told.indexed.any(
                (entry) =>
                    entry.$2.id != _lastModels[entry.$1].id ||
                    entry.$2.label != _lastModels[entry.$1].label,
              );
          _models = _lastModels = told;
          if (changed) _keep();
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
    final connection = _run?.connection;
    if (connection == null || _sessionId == null) return;
    // Picked as the session loads: kept, put in effect once it has.
    if (_run?.loading ?? false) return;
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

  /// Asked lately: shown as they are, not asked again.
  static bool _limitsFresh(Duration within) => switch (_limitsAt) {
    final at? => DateTime.now().difference(at) < within,
    null => false,
  };

  @override
  Future<void> refreshUsage() {
    if (_disposed) return Future.value();
    if (_asking == null && _limitsFresh(const Duration(minutes: 1))) {
      emit(StatsReported(nextSeq, UsageStats(limits: _limits)));
      return Future.value();
    }
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
        _keep();
      }
    } on Object {
      state = LimitsState.unavailable;
    }
    if (_disposed) return;
    emit(
      StatsReported(nextSeq, UsageStats(limits: _limits, limitsState: state)),
    );
  }

  /// Asks for the limits in the background (a turn over, agy up),
  /// unless asked lately.
  void _limitsAfterTurn() {
    if (_limitsFresh(const Duration(minutes: 2))) return;
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

  /// Whether [taskId] is one of agy's own (`<session>/task-<n>`), ended in
  /// its inbox; else a command's call, ended by its update.
  static bool _agyTask(String taskId) => taskId.contains('/task-');

  /// Tasks the user stopped watching: not shown again.
  final Set<String> _dropped = {};

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
      ]),
    );
  }

  /// A command in the background is stopped by a cancel once no turn is
  /// open (one would end that turn too): agy then ends every command still
  /// at work, each reported failed. Its other tasks it offers no way to
  /// stop: they are no longer shown, and run on until agy ends.
  @override
  void stopTask(String taskId) {
    if (_translator.tasks[taskId] case final task?
        when task.status == CommandStatus.running && !_agyTask(taskId)) {
      _stopCommands = true;
      if (_turn == null) _stopBackground();
      return;
    }
    if (_dropped.add(taskId)) _reportTasks();
  }

  /// Whether the commands in the background are to stop once the turn
  /// under way is over.
  bool _stopCommands = false;

  void _stopBackground() {
    if (!_stopCommands) return;
    _stopCommands = false;
    if (_runningTasks.any((task) => !_agyTask(task.id))) {
      _run?.connection?.notify('session/cancel', {'sessionId': _sessionId});
    }
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

  /// How often its records are read again while a task of agy's runs.
  final Duration _pollEvery;

  /// Reads what agy keeps of the conversation for what ACP does not tell
  /// (its own tasks' ends), again while any runs.
  Future<void> _watchRecords() async {
    _poll?.cancel();
    final id = _sessionId;
    if (id == null || _disposed || _reading) return;
    _reading = true;
    try {
      final records = _runtime.records(id);
      final inbox = await records.messages();
      _tasksFrom(inbox, records);
    } on Object {
      // Read again next time.
    } finally {
      _reading = false;
    }
    if (_disposed) return;
    if (_runningTasks.any((task) => _agyTask(task.id))) {
      _poll = Timer(_pollEvery, () => unawaited(_watchRecords()));
    }
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
      if (task.outputFile != null || !_agyTask(id)) continue;
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
    if (_disposed || _run == null) return;
    if (_turn != null || _runningTasks.isNotEmpty) return;
    _end();
    unawaited(_ready());
  }

  @override
  Future<Uri?> authenticateMcpServer(String name) async => null;
}

/// One agy started for the conversation: its connection once the process
/// is up, and whether the start came through. It is the kernel's only
/// while [AntigravityKernel._run]; ended, it is let go of there first, so
/// its start, waking after, knows itself ended, and its process's exit
/// says nothing.
class _Run {
  AcpConnection? connection;
  late final Future<bool> ready;

  /// Whether its session is being loaded: agy reading the conversation
  /// back, its answer (the options in effect) still to come.
  bool loading = false;

  /// Whether the conversation was shown ([AntigravityKernel._readBack]).
  bool shown = false;
  Timer? _gap;

  /// Something was read back: [quiet] once nothing more is for [gap].
  void replayed(Duration gap, void Function() quiet) {
    _gap?.cancel();
    _gap = Timer(gap, quiet);
  }

  void end() {
    _gap?.cancel();
    connection?.close();
  }
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
