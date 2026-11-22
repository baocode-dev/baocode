import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import '../../remote/remote_location.dart';
import '../acp/mcp_endpoint.dart';
import '../agent_kernel.dart';
import '../claude_code/claude_sdk_tools.dart';
import '../kernel_event.dart';
import '../kernel_types.dart';
import '../output_meter.dart';
import 'agy_runtime.dart';
import 'antigravity_catalog.dart';
import 'antigravity_translator.dart';

/// Google's Antigravity CLI (`agy`) as a kernel, through the language
/// server of the one agy the app keeps running ([AgyRuntime.server]): the
/// conversation is a cascade of its, started here or elsewhere (the user's
/// terminal), watched as it runs (`StreamAgentStateUpdates`) and prompted
/// (`SendUserCascadeMessage`). Its conversations are its own, the project
/// and the UI the app's.
class AntigravityKernel
    with KernelEventSource
    implements
        AgentKernel,
        SelectsModel,
        SelectsEffort,
        SelectsMode,
        SelectsPermission,
        StartsPlans,
        LoadsHistory,
        AcceptsImages,
        QueuesMessages,
        RunsBackgroundTasks,
        ManagesMcpServers,
        RenamesSession,
        ReportsUsage,
        ReportsContext {
  AntigravityKernel(
    this.descriptor,
    this._context, {
    AgyRuntime? runtime,
    this._retryAfter = const Duration(seconds: 2),
    this._takenWithin = const Duration(seconds: 90),
  }) : _runtime = runtime ?? AgyRuntime.local {
    _restore();
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
    _translator =
        AntigravityTranslator(
            emit: emit,
            nextSeq: () => nextSeq,
            ownsMessage: _sentTurns.contains,
            originalOf: _originalOf,
          )
          ..onTasksChanged = _tasksChanged
          ..onWaiting = _waiting
          ..onWaitingOver = _waitingOver
          ..onDelta = _streamed;
    if (_context.resume case final resume?) {
      _sessionId = resume.id;
      _loadingHistory = true;
      _initial = true;
      unawaited(_subscribe());
    }
  }

  @override
  final KernelDescriptor descriptor;
  final KernelContext _context;
  final AgyRuntime _runtime;
  late final AntigravityTranslator _translator;

  /// How long after the watch ends (agy gone, say) it is taken up again.
  final Duration _retryAfter;

  /// How long a message sent is given to be taken up before it is given
  /// up on.
  final Duration _takenWithin;

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

  String? _sessionId;

  /// Whether the conversation has had a message: agy keeps it from then on.
  bool get _prompted => _sessionId != null;

  @override
  String? get sessionId => _sessionId;

  bool get _remote => switch (_cwd) {
    final cwd? => RemoteLocation.hostOf(cwd) != null,
    null => false,
  };

  void _localOnly() {
    _setHealth(
      const KernelHealth(
        KernelHealthStatus.failed,
        setup: KernelSetup(KernelSetupKind.localOnly),
      ),
    );
    _historyRead();
  }

  /// A view shows the conversation: agy is checked (installed, signed in,
  /// up), its models asked for, the account's limits if old.
  @override
  void prepare() {
    if (_remote) {
      _localOnly();
      return;
    }
    if (_health.status == KernelHealthStatus.idle) {
      _setHealth(KernelHealth.ready);
    }
    unawaited(_check());
    _limitsAfterTurn();
  }

  Future<void>? _checking;

  /// Whether agy can be used: installed, signed in, its language server
  /// up (booted now if not, seconds). Told as setup to do where not.
  Future<void> _check() => _checking ??= _checkOnce().whenComplete(() {
    _checking = null;
  });

  Future<void> _checkOnce() async {
    if (await _runtime.locate() == null) {
      if (_disposed) return;
      _setHealth(
        KernelHealth(
          KernelHealthStatus.failed,
          message: 'Antigravity is not installed',
          setup: KernelSetup(KernelSetupKind.install, start: _install),
        ),
      );
      _historyRead();
      return;
    }
    try {
      final server = await _runtime.server();
      if (_disposed) return;
      final auth = await server.call('GetAuthStatus');
      if (_disposed) return;
      if (auth case {'authResult': {'hasValidAuth': true}}) {
        if (_health.status == KernelHealthStatus.failed) {
          _setHealth(KernelHealth.ready);
        }
        unawaited(_loadModels(server));
      } else {
        _setHealth(
          KernelHealth(
            KernelHealthStatus.failed,
            message: 'Antigravity is not signed in',
            setup: KernelSetup(KernelSetupKind.login, start: _login),
          ),
        );
      }
    } on AgyUnavailable catch (error) {
      if (_disposed) return;
      _unavailable(error);
    } on AgyError catch (error) {
      if (_disposed) return;
      _fail('Antigravity is not answering', detail: error.message);
    }
  }

  void _unavailable(AgyUnavailable error) {
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
  }

  void _fail(String message, {String? detail}) => _setHealth(
    KernelHealth(KernelHealthStatus.failed, message: message, detail: detail),
  );

  @override
  void restart() {
    _setHealth(KernelHealth.ready);
    unawaited(_check());
    if (_prompted && _watch == null) unawaited(_subscribe());
  }

  /// Nothing held while out of view: the watch on the conversation goes
  /// on (a task of its may end), on the one agy shared by all.
  @override
  void release() {}

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retry?.cancel();
    _taken?.cancel();
    _failAsks();
    unawaited(_watch?.cancel());
    _watch = null;
    unawaited(_tools?.close());
    _tools = null;
    closeEvents();
    if (!_stopped.isCompleted) _stopped.complete();
  }

  // --- Setting it up -------------------------------------------------------------------

  /// Installs agy for the app, then checks again.
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
  /// Google shows there taken back; then checks again.
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

  // --- Watching the conversation ---------------------------------------------------------

  /// The watch on the conversation (`StreamAgentStateUpdates`): its steps
  /// as they come, all of them first.
  StreamSubscription<Map<String, Object?>>? _watch;
  bool _subscribing = false;

  /// Whether the first frame of a conversation continued is still to
  /// come: it read back whole, nothing of it reviewed. One started here
  /// is new from its first step.
  bool _initial = false;

  /// The first frame of the watch under way, which tells of all steps.
  bool _first = true;

  Timer? _retry;
  int _retries = 0;

  /// The watch's own name to agy.
  static final _subscriber = 'baocode-${Random().nextInt(1 << 30)}';

  Future<void> _subscribe() async {
    final id = _sessionId;
    if (_disposed || id == null || _subscribing || _watch != null) return;
    if (_remote) {
      _localOnly();
      return;
    }
    _subscribing = true;
    final AgyLanguageServer server;
    try {
      server = await _runtime.server();
    } on AgyUnavailable catch (error) {
      _subscribing = false;
      if (_disposed) return;
      _unavailable(error);
      _historyRead();
      return;
    } on Object catch (error) {
      _subscribing = false;
      if (_disposed) return;
      _fail('Antigravity could not start', detail: '$error');
      _historyRead();
      return;
    }
    _subscribing = false;
    if (_disposed) return;
    _first = true;
    unawaited(_serveTools());
    _watch = server
        .stream('StreamAgentStateUpdates', {
          'conversationId': id,
          'subscriberId': _subscriber,
          'trajectoryVerbosity': 'CLIENT_TRAJECTORY_VERBOSITY_PROD_UI',
        })
        .listen(
          _frame,
          onError: (Object error) => _watchEnded(error),
          onDone: () => _watchEnded(null),
        );
  }

  /// The watch ended without being asked to: agy gone, or the stream
  /// dropped. What ran is lost to view; watched again after a while.
  void _watchEnded(Object? error) {
    _watch = null;
    if (_disposed) return;
    final turn = _turn;
    if (turn != null) {
      _translator.settle(interrupted: true);
      _notice(NoticeKind.error, switch (error) {
        AgyError(gone: true) => 'Antigravity stopped',
        AgyError(:final message) => message,
        _ => 'Antigravity stopped',
      });
      _endTurn(turn, interrupted: true);
    }
    _failAsks();
    _endTasks();
    if (_loadingHistory) {
      _historyRead();
      if (error case AgyError(:final message)) {
        _fail('Antigravity could not read the conversation', detail: message);
      }
    }
    _retry?.cancel();
    _retry = Timer(_retryAfter * min(1 + _retries++, 10), () {
      if (!_disposed) unawaited(_subscribe());
    });
  }

  /// One frame of the watch: agy's state of the conversation, and the
  /// steps that changed.
  void _frame(Map<String, Object?> frame) {
    final update = _map(frame['update']);
    if (update.isEmpty) return;
    _retries = 0;
    final status = update['status'];
    final running =
        status == 'CASCADE_RUN_STATUS_RUNNING' ||
        status == 'CASCADE_RUN_STATUS_CANCELING';
    if (running && _turn == null && !_cancelling) _wake();
    if (running && _turn != null) {
      _turnRunning = true;
      _taken?.cancel();
    }
    final main = _map(update['mainTrajectoryUpdate']);
    if (_map(main['stepsUpdate']) case {
      'indices': final List indices,
      'steps': final List steps,
    }) {
      _translator.steps(
        [for (final index in indices) _int(index)],
        [for (final step in steps) _map(step)],
        history: _initial,
      );
    }
    if (update['contextWindowUsage'] case final Map usage) {
      _usage(usage.cast<String, Object?>());
    }
    if (update.containsKey('backgroundTasksUpdate')) {
      _translator.backgroundTasks([
        for (final task
            in _map(update['backgroundTasksUpdate'])['backgroundTasks']
                    as List? ??
                const [])
          _map(task),
      ]);
    }
    if (_first) {
      _first = false;
      _initial = false;
      _translator.timeTurns(running: running);
      if (!running) _translator.endPlanRound();
      _historyRead();
      if (_health.status == KernelHealthStatus.failed &&
          _health.setup == null) {
        _setHealth(KernelHealth.ready);
      }
    }
    if (status == 'CASCADE_RUN_STATUS_IDLE') {
      _cancelling = false;
      final turn = _turn;
      if (turn != null && (_turnRunning || _unprompted)) {
        _finish(turn);
      } else {
        _translator.timeTurns();
      }
    }
  }

  void _historyRead() {
    if (!_loadingHistory) return;
    _loadingHistory = false;
    if (!_disposed) emitInfoChanged();
  }

  // --- Starting the conversation ---------------------------------------------------------

  /// The app's own tools, served to the conversation at a key of its own
  /// (kept with it: the address is told agy once, as it starts).
  McpEndpoint? _tools;
  String? _toolKey;
  Future<void>? _servingTools;

  /// Serves the app's tools, where the project has any: at the key the
  /// conversation was started with, else (a new one) a new key.
  Future<void> _serveTools() => _servingTools ??= () async {
    final cwd = _cwd;
    if (cwd == null || _tools != null || _disposed) return;
    if (ClaudeSdkTools.serversFor(cwd).isEmpty) return;
    final key = switch (_sessionId) {
      final id? => _runtime.toolKey(id),
      null => _toolKey ??= McpToolKey.make(),
    };
    if (key == null) return;
    _toolKey = key;
    try {
      _tools = await _runtime.serveTools(_toolMessage, key: key);
    } on Object {
      // Without them then.
    }
  }();

  /// Starts the conversation in agy (`StartCascade`): told the project,
  /// the app's tools and the workspace's instructions. Not before the
  /// first message: one started is kept, even empty.
  Future<void> _start(AgyLanguageServer server) async {
    final cwd = _cwd!;
    await _serveTools();
    final instructions = _workspace?.instructions ?? '';
    final started = await server.call('StartCascade', {
      'source': 'CORTEX_TRAJECTORY_SOURCE_CLI',
      'trajectoryType': 'CORTEX_TRAJECTORY_TYPE_CASCADE',
      'workspaceUris': _workspaceUris,
      'interactionMode': 'INTERACTION_MODE_INTERACTIVE',
      'agentScriptItem': {
        'config': {
          'builtinAgent': {
            'defaultAgent': {'isGoogle': false, 'surface': 'AGENT_SURFACE_CLI'},
          },
          'cascadeConfig': {
            'plannerConfig': {
              if (_tools case final tools?)
                'customizationDiscoveryConfig': {
                  'mcp': {
                    'servers': [
                      {
                        'serverName': ClaudeSdkTools.server,
                        'serverUrl': '${tools.url}',
                        'headers': tools.headers,
                        'forceAllToolsEager': true,
                        'disableStandaloneSse': true,
                      },
                    ],
                  },
                },
              if (instructions.isNotEmpty)
                'promptSectionCustomizationConfig': {
                  'appendPromptSections': [
                    {'title': 'baocode', 'content': instructions},
                  ],
                },
            },
          },
        },
      },
    });
    final id = started['cascadeId'];
    if (id is! String || id.isEmpty) {
      throw const AgyError('Antigravity started no conversation');
    }
    _sessionId = id;
    if (_toolKey case final key? when _tools != null) {
      _runtime.keepToolKey(id, key);
    }
    AntigravityCatalog.forget();
    if (!_disposed) emitInfoChanged();
    unawaited(_subscribe());
    assert(cwd == _cwd);
  }

  /// The project's folders as agy names them: `file://` URIs.
  List<String> get _workspaceUris => [
    for (final folder in _folders) Uri.file(folder).toString(),
  ];

  /// The folders it works in: the project's, the workspace's others, and
  /// those it reaches into.
  List<String> get _folders {
    final cwd = _cwd;
    final workspace = _workspace;
    return [
      ?cwd,
      if (workspace != null)
        for (final folder in {...workspace.folders, ...workspace.reaches})
          if (folder != cwd) folder,
    ];
  }

  // --- Turns -----------------------------------------------------------------------------

  /// The turn running, ours or one agy took up on its own.
  String? _turn;
  DateTime? _turnStarted;

  /// Whether agy has been seen running the turn: it ends once idle again.
  bool _turnRunning = false;

  /// Whether [_turn] was taken up by agy on its own (a task's end, a
  /// subagent's report).
  bool _unprompted = false;
  int _wakes = 0;

  /// Where the turn of agy's own began, to tell what it spent.
  int _wakeFrom = 0;

  /// Whether a turn stopped is still being wound down by agy: it running
  /// meanwhile is not a turn of its own.
  bool _cancelling = false;

  /// Gives up on a message agy has not taken up.
  Timer? _taken;

  final Set<String> _sentTurns = {};
  final List<KernelTurn> _queue = [];

  /// Set by [startBuilding]: the next message starts the plan awaiting.
  bool _startsPlan = false;

  @override
  void startBuilding() {
    _startsPlan = true;
    _work = 'agent';
    emitInfoChanged();
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
    if (_turn == null && _queue.isEmpty) {
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
    _next();
  }

  void _begin(KernelTurn turn) {
    _turn = turn.id;
    _unprompted = false;
    _turnRunning = false;
    _turnStarted = DateTime.now();
    _meterTurn();
    _translator
      ..turnId = turn.id
      ..planning = _work == 'plan'
      ..resolvePlan(started: false, feedback: turn.text);
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
    unawaited(_prompt(turn));
  }

  /// Sends [turn] to agy, starting the conversation first if it is new.
  Future<void> _prompt(KernelTurn turn) async {
    if (_cwd == null) {
      _notice(NoticeKind.error, 'Antigravity needs a project folder');
      _endTurn(turn.id, interrupted: true);
      return;
    }
    if (_remote) {
      _localOnly();
      _endTurn(turn.id, interrupted: true);
      return;
    }
    try {
      if (_health.status != KernelHealthStatus.ready) {
        _setHealth(const KernelHealth(KernelHealthStatus.starting));
      }
      final server = await _runtime.server();
      if (_turn != turn.id) return;
      if (!_prompted) await _start(server);
      if (_turn != turn.id) return;
      await _loadModels(server);
      if (_turn != turn.id) return;
      if (_health.status != KernelHealthStatus.ready) {
        _setHealth(KernelHealth.ready);
      }
      await server.call('SendUserCascadeMessage', _message(turn));
      if (_turn != turn.id) return;
      _taken = Timer(_takenWithin, () {
        if (_turn != turn.id || _turnRunning) return;
        _notice(NoticeKind.error, 'Antigravity did not take the message');
        _endTurn(turn.id, interrupted: true);
      });
    } on AgyUnavailable catch (error) {
      if (_disposed || _turn != turn.id) return;
      _unavailable(error);
      _notice(NoticeKind.error, error.message);
      _endTurn(turn.id, interrupted: true);
    } on AgyError catch (error) {
      if (_disposed || _turn != turn.id) return;
      _notice(NoticeKind.error, error.message);
      if (error.message.toLowerCase().contains('auth') ||
          error.code == 'unauthenticated') {
        _setHealth(
          KernelHealth(
            KernelHealthStatus.failed,
            message: 'Antigravity is not signed in',
            setup: KernelSetup(KernelSetupKind.login, start: _login),
          ),
        );
      } else if (error.gone) {
        _fail('Antigravity stopped', detail: error.message);
      } else if (_health.status == KernelHealthStatus.starting) {
        _setHealth(KernelHealth.ready);
      }
      _endTurn(turn.id, interrupted: true);
    }
  }

  /// The message as agy takes it, with the settings it runs under: the
  /// model and its thinking, the approvals, the app's tools eager, the
  /// workspace's instructions; `/plan` as a command before the text.
  Map<String, Object?> _message(KernelTurn turn) {
    final folders = _folders;
    final edits = switch (_approval) {
      'acceptEdits' || 'auto' || 'bypassPermissions' => true,
      _ => false,
    };
    final instructions = _workspace?.instructions ?? '';
    return {
      'cascadeId': _sessionId,
      'clientMessageId': turn.id,
      'items': [
        if (_work == 'plan')
          {
            'item': {
              'slashCommand': {
                'info': {
                  'name': 'plan',
                  'modelFacingText': planPrompt,
                  'type': 'SLASH_COMMAND_TYPE_SYSTEM',
                },
              },
            },
          },
        if (turn.text.isNotEmpty) {'text': turn.text},
        for (final note in turn.notes) {'text': note},
      ],
      if (turn.images.isNotEmpty)
        'images': [
          for (final image in turn.images)
            {
              'base64Data': base64Encode(image.bytes),
              'mimeType': image.mediaType,
            },
        ],
      'cascadeConfig': {
        'plannerConfig': {
          'planModel': _planModel,
          'toolConfig': {
            'mcp': {'enableLazyLoad': false},
            'antigravityBrowser': {'enableBrowserSubagentWebview': false},
            'runCommand': {
              'autoCommandConfig': {
                'autoExecutionPolicy': switch (_approval) {
                  'auto' => 'CASCADE_COMMANDS_AUTO_EXECUTION_AUTO',
                  'bypassPermissions' =>
                    'CASCADE_COMMANDS_AUTO_EXECUTION_EAGER',
                  _ => 'CASCADE_COMMANDS_AUTO_EXECUTION_OFF',
                },
              },
            },
          },
          'permissionConfig': {
            'defaultGrants': {
              'ask': ['write_file(/)'],
            },
            'effectiveGrants': {
              'allow': [
                for (final folder in folders) 'read_file($folder)',
                if (edits)
                  for (final folder in folders) 'write_file($folder)',
              ],
            },
          },
          if (instructions.isNotEmpty)
            'promptSectionCustomizationConfig': {
              'appendPromptSections': [
                {'title': 'baocode', 'content': instructions},
              ],
            },
        },
        'dynamicWorkspaceUris': _workspaceUris,
      },
      'customAgentSpec': {
        'builtinAgent': {
          'defaultAgent': {
            'isGoogle': false,
            'isInteractive': true,
            'surface': 'AGENT_SURFACE_CLI',
          },
        },
      },
    };
  }

  /// What `/plan` tells the model: research, then a plan as an artifact
  /// for the user to approve, no changes before. The plan card shows the
  /// artifact (a markdown file in agy's own folder).
  @visibleForTesting
  static const planPrompt =
      '<PLAN>The user wants a plan before any change is made. '
      'First research the task in the codebase: read, search and list; run '
      'only commands that change nothing. Clarify what is ambiguous with the '
      'user. Then write the plan as an artifact: a markdown file in your '
      'artifact directory named for the task (not walkthrough.md), with '
      'user_facing = true and request_feedback = true in its ArtifactMetadata. '
      'Cover the goal, what will change and where (files, with snippets where '
      'they help), open questions, and how the result will be verified. The '
      'user sees the artifact as you write it, so do not repeat it in your '
      'reply. Then stop and wait for their approval: make no code changes and '
      'run no modifying commands until they approve.</PLAN>';

  /// Takes up the next message queued, once agy is free.
  void _next() {
    if (_turn != null || _queue.isEmpty) return;
    _begin(_queue.removeAt(0));
  }

  /// agy took up something on its own (a task's end, a subagent's report):
  /// a turn of its own, until it is idle.
  void _wake() {
    final id = 'agy-wake-${++_wakes}';
    _turn = id;
    _unprompted = true;
    _turnRunning = true;
    _turnStarted = DateTime.now();
    _wakeFrom = _translator.stepCount;
    _meterTurn();
    _translator.turnId = id;
    emit(TurnStarted(nextSeq, id, unprompted: true));
  }

  /// agy is idle: [turn] is over, with what it spent as its steps say.
  void _finish(String turn) {
    _translator
      ..settle()
      ..endPlanRound();
    final from = _unprompted ? _wakeFrom : _translator.indexOf(turn);
    final usage = from == null ? null : _translator.usageFrom(from);
    _endTurn(
      turn,
      interrupted: false,
      usage: usage == null
          ? null
          : TurnUsage(
              inputTokens: usage.inputTokens,
              outputTokens: usage.outputTokens,
              tokensPerSecond: _output.averageSpeed,
            ),
    );
    _translator.timeTurns();
    _limitsAfterTurn();
  }

  void _endTurn(String turn, {required bool interrupted, TurnUsage? usage}) {
    if (_turn != turn) return;
    _taken?.cancel();
    _turn = null;
    _unprompted = false;
    _turnRunning = false;
    _failAsks();
    final started = _turnStarted;
    emit(
      TurnEnded(
        nextSeq,
        turn,
        interrupted: interrupted,
        worked: started == null ? null : DateTime.now().difference(started),
        usage: usage,
      ),
    );
    _next();
  }

  @override
  void cancel() {
    final turn = _turn;
    if (turn == null) return;
    _cancelling = true;
    if (!_toolsCancelled.isCompleted) _toolsCancelled.complete();
    if (_sessionId case final id?) {
      unawaited(
        _runtime
            .server()
            .then(
              (server) =>
                  server.call('CancelCascadeInvocation', {'cascadeId': id}),
            )
            .catchError((_) => const <String, Object?>{}),
      );
    }
    _translator.settle(interrupted: true);
    _endTurn(turn, interrupted: true);
  }

  void _notice(NoticeKind kind, String text) {
    emit(
      ItemUpserted(nextSeq, 'agy-notice-${++_notices}', NoticeItem(kind, text)),
    );
  }

  int _notices = 0;

  // --- The model's pace -----------------------------------------------------------------

  /// What the turn's model writes, as its text streams.
  final OutputMeter _output = OutputMeter();
  DateTime? _outputReported;
  static const _outputEvery = Duration(milliseconds: 250);

  void _streamed(String text, {required bool thought}) {
    if (_turn == null) return;
    _output.streamed(text, timed: !thought);
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

  /// Sends the queued [turnId] at once: the turn under way is stopped for
  /// it (sent to agy while it runs, a message waits its turn there).
  void _sendNow(String turnId) {
    if (_turn != null) cancel();
    _next();
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

  /// Step [index] waits on the user: a permission, answered here as the
  /// approvals picked say, else put to them; or a question.
  void _waiting(int index, Map<String, Object?> step) {
    final request = _map(step['requestedInteraction']);
    final trajectory =
        _map(_map(step['metadata'])['sourceTrajectoryStepInfo'])['trajectoryId']
            as String?;
    for (final MapEntry(key: id, value: ask) in [..._asks.entries]) {
      if (ask.index == index) {
        _asks.remove(id);
        emit(InteractionResolved(nextSeq, id));
      }
    }
    if (request['permission'] case final Map permission) {
      final spec = permission.cast<String, Object?>();
      final resource = _map(spec['resource']);
      final action = resource['action'] as String? ?? '';
      final target = resource['target'] as String? ?? '';
      if (_allowed(action, target)) {
        unawaited(
          _interact(index, trajectory, {
            'permission': {'allow': true, 'scope': 'PERMISSION_SCOPE_ONCE'},
          }),
        );
        return;
      }
      final description = spec['actionDescription'] as String?;
      final pattern = spec['suggestedPersistPattern'] as String?;
      final id = 'agy-ask-${++_askCount}';
      _asks[id] = _Ask(index: index, trajectory: trajectory);
      emit(
        InteractionRequested(
          nextSeq,
          ApprovalRequest(
            id: id,
            title: switch (action) {
              'command' => description ?? 'Run a command',
              'write_file' => description ?? 'Edit ${_base(target)}',
              'read_file' => description ?? 'Read ${_base(target)}',
              'mcp' => description ?? 'Use $target',
              _ => description ?? 'Use a tool',
            },
            toolName: switch (action) {
              'command' => 'run_command',
              'write_file' => 'write_file',
              'read_file' => 'read_file',
              'mcp' => target,
              _ => action,
            },
            reason: spec['reason'] as String?,
            preview: switch (action) {
              'command' => CommandPreview(target, description: description),
              _ => TextPreview(target),
            },
            alwaysAllowLabel: pattern == null || pattern.isEmpty
                ? null
                : 'Always allow `$pattern` in this conversation',
          ),
        ),
      );
      return;
    }
    if (request['askQuestion'] case final Map asked) {
      final questions = [
        for (final question in asked['questions'] as List? ?? const [])
          if (question is Map) question.cast<String, Object?>(),
      ];
      if (questions.isEmpty) return;
      final id = 'agy-ask-${++_askCount}';
      _asks[id] = _Ask(
        index: index,
        trajectory: trajectory,
        questions: questions,
      );
      emit(
        InteractionRequested(
          nextSeq,
          QuestionRequest(
            id: id,
            title: questions.first['question'] as String? ?? 'A question',
            questions: [
              for (final question in questions)
                Question(
                  prompt: question['question'] as String? ?? '',
                  allowMultiple: question['isMultiSelect'] == true,
                  options: [
                    for (final option
                        in question['options'] as List? ?? const [])
                      if (option case {'text': final String text})
                        QuestionOption(text),
                  ],
                ),
            ],
          ),
        ),
      );
    }
  }

  /// Step [index] no longer waits (answered elsewhere, or given up).
  void _waitingOver(int index) {
    for (final MapEntry(key: id, value: ask) in [..._asks.entries]) {
      if (ask.index == index && ask.sdk == null) {
        _asks.remove(id);
        emit(InteractionResolved(nextSeq, id));
      }
    }
  }

  /// Whether [action] on [target] is allowed without asking, as the
  /// approvals picked say: full access allows all; reads in the project
  /// are free; edits in it with "accept edits" on; the app's own tools
  /// ask for themselves where they must.
  bool _allowed(String action, String target) {
    if (_approval == 'bypassPermissions' ||
        (_workspace?.approvesAll ?? false)) {
      return true;
    }
    switch (action) {
      case 'read_file':
        return _inProject(target);
      case 'write_file':
        return (_approval == 'acceptEdits' || _approval == 'auto') &&
            _inProject(target);
      case 'mcp':
        return target.startsWith('${ClaudeSdkTools.server}/') ||
            _approval == 'auto';
      default:
        return false;
    }
  }

  bool _inProject(String path) {
    final folders = _folders;
    if (folders.isEmpty) return false;
    final real = path.replaceFirst(RegExp(r'^/private/'), '/');
    return folders.any(
      (folder) =>
          path == folder ||
          path.startsWith('$folder/') ||
          real == folder ||
          real.startsWith('$folder/'),
    );
  }

  Future<void> _interact(
    int index,
    String? trajectory,
    Map<String, Object?> interaction,
  ) async {
    final id = _sessionId;
    if (id == null) return;
    try {
      final server = await _runtime.server();
      await server.call('HandleCascadeUserInteraction', {
        'cascadeId': id,
        'interaction': {
          'trajectoryId': ?trajectory,
          'stepIndex': index,
          ...interaction,
        },
      });
    } on AgyError catch (error) {
      if (!_disposed) _notice(NoticeKind.error, error.message);
    } on AgyUnavailable catch (error) {
      if (!_disposed) _notice(NoticeKind.error, error.message);
    }
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
    final index = ask.index!;
    switch (answer) {
      case ApprovalAnswer(:final decision, :final message):
        unawaited(
          _interact(index, ask.trajectory, {
            'permission': {
              'allow': decision != ApprovalDecision.deny,
              'scope': decision == ApprovalDecision.allowAlways
                  ? 'PERMISSION_SCOPE_CONVERSATION'
                  : 'PERMISSION_SCOPE_ONCE',
              if (decision == ApprovalDecision.deny &&
                  message != null &&
                  message.trim().isNotEmpty)
                'userDenyInstruction': message.trim(),
            },
          }),
        );
      case QuestionAnswer(:final picks, :final skipped):
        final questions = ask.questions ?? const [];
        unawaited(
          _interact(index, ask.trajectory, {
            'askQuestion': {
              'responses': [
                for (var q = 0; q < questions.length; q++)
                  _response(
                    questions[q],
                    skipped
                        ? const []
                        : (q < picks.length ? picks[q] : const []),
                    skipped: skipped,
                  ),
              ],
            },
          }),
        );
    }
  }

  /// The user's answer to [question]: the options picked by their ids,
  /// what they wrote in words.
  static Map<String, Object?> _response(
    Map<String, Object?> question,
    List<String> picks, {
    required bool skipped,
  }) {
    final options = [
      for (final option in question['options'] as List? ?? const [])
        if (option case {'id': final id, 'text': final String text})
          (id: '$id', text: text),
    ];
    final ids = <String>[];
    final written = <String>[];
    for (final pick in picks) {
      final option = options.where((option) => option.text == pick).firstOrNull;
      if (option != null) {
        ids.add(option.id);
      } else if (pick.isNotEmpty) {
        written.add(pick);
      }
    }
    return {
      'question': question['question'],
      'selectedOptionIds': ids,
      if (written.isNotEmpty) 'writeInResponse': written.join('\n'),
      if (skipped) 'skipped': true,
    };
  }

  /// Gives up what is asked: the turn ended, or agy did.
  void _failAsks() {
    for (final MapEntry(key: id, value: ask) in [..._asks.entries]) {
      _asks.remove(id);
      if (!_disposed) emit(InteractionResolved(nextSeq, id));
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
    _asks[id] = _Ask(sdk: answered);
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

  /// What [path] was before the conversation changed it, as agy keeps it
  /// (`GetTrajectoryFileDiffs`); null when it does not say.
  Future<String?> _originalOf(String path) async {
    final id = _sessionId;
    if (id == null) return null;
    final uri = Uri.file(path).toString();
    final server = await _runtime.server();
    final diffs = await server.call('GetTrajectoryFileDiffs', {
      'conversationId': id,
      'fileUris': [uri],
    });
    for (final diff in diffs['diffs'] as List? ?? const []) {
      if (diff case {'uri': final String at} when at == uri) {
        return diff['originalContent'] as String?;
      }
    }
    return null;
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
  /// names).
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
      'Approve edits and safe commands, ask before risky ones',
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

  @override
  late final KernelChoiceSource mode = _Choice(
    options: () => _works,
    selected: () => _work,
    select: (id) {
      _work = id;
      emitInfoChanged();
    },
  );

  @override
  late final KernelChoiceSource permission = _Choice(
    options: () => _approvals,
    selected: () => _approval,
    select: (id) {
      _approval = id;
      emitInfoChanged();
    },
  );

  // --- Models ----------------------------------------------------------------------------

  /// agy's models, as last told (`GetCascadeModelConfigData`): each a
  /// family with its thinking levels, or one on its own.
  static List<_Family> _families = const [];
  static DateTime? _familiesAt;
  static Future<void>? _loadingModels;
  static const _modelsFresh = Duration(minutes: 10);

  /// Whether what was kept from the last run ([AgyRuntime.kept]) was read
  /// back: once a run.
  static bool _restored = false;

  /// Forgets what was read back, for a test to start afresh.
  @visibleForTesting
  static void forgetKept() {
    _restored = false;
    _families = const [];
    _familiesAt = null;
    _limits = const [];
    _limitsAt = null;
  }

  void _restore() {
    if (_restored) return;
    _restored = true;
    final kept = _runtime.kept;
    if (kept == null) return;
    if (kept['models'] case final Map<String, Object?> models) {
      _families = _familiesOf(models);
    }
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
      'models': _modelsKept,
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

  static Map<String, Object?> _modelsKept = const {};

  /// Asks agy for its models, unless told lately.
  Future<void> _loadModels(AgyLanguageServer server) {
    if (_familiesAt case final at?
        when DateTime.now().difference(at) < _modelsFresh &&
            _families.isNotEmpty) {
      return Future.value();
    }
    return _loadingModels ??= () async {
      try {
        final data = await server.call('GetCascadeModelConfigData');
        final families = _familiesOf(data);
        if (families.isEmpty) return;
        _modelsKept = {
          'clientModelConfigs': [
            for (final config
                in data['clientModelConfigs'] as List? ?? const [])
              if (config is Map)
                {
                  for (final key in const [
                    'label',
                    'modelId',
                    'modelOrAlias',
                    'disabled',
                    'supportsImages',
                  ])
                    if (config[key] != null) key: config[key],
                },
          ],
          'groupedModels': data['groupedModels'],
        };
        _families = families;
        _familiesAt = DateTime.now();
        _keep();
        if (!_disposed) emitInfoChanged();
      } on AgyError {
        // Offered as last known, if at all.
      } finally {
        _loadingModels = null;
      }
    }();
  }

  /// The families of [data] (`CascadeModelConfigData`): its grouped
  /// models each with their levels, then the ones on their own; the
  /// disabled left out.
  static List<_Family> _familiesOf(Map<String, Object?> data) {
    final configs = [
      for (final config in data['clientModelConfigs'] as List? ?? const [])
        if (config case {'modelId': final String id}
            when config['disabled'] != true)
          (
            id: id,
            label: config['label'] as String? ?? id,
            model: _map(config['modelOrAlias'])['model'] as String?,
            images: config['supportsImages'] == true,
          ),
    ];
    final grouped = _map(data['groupedModels']);
    final families = <_Family>[];
    final taken = <String>{};
    for (final MapEntry(key: family, value: group) in grouped.entries) {
      final info = _map(group);
      final levels = <_Level>[];
      for (final level
          in info['supportedThinkingLevels'] as List? ?? const []) {
        if (level case {'thinkingSuffix': final String suffix}) {
          final config = configs
              .where((config) => config.id == '$family-$suffix')
              .firstOrNull;
          if (config?.model == null) continue;
          taken.add(config!.id);
          levels.add(
            _Level(
              suffix,
              level['thinkingDisplayName'] as String? ?? suffix,
              config.model!,
            ),
          );
        }
      }
      if (levels.isEmpty) continue;
      families.add(
        _Family(
          family,
          info['displayName'] as String? ?? family,
          levels,
          defaultLevel: info['defaultThinkingSuffix'] as String?,
        ),
      );
    }
    for (final config in configs) {
      if (taken.contains(config.id) || config.model == null) continue;
      families.add(
        _Family(config.id, config.label, [_Level('', '', config.model!)]),
      );
    }
    // As agy lists them, the grouped ones at their first member's place.
    final order = [for (final config in configs) config.id];
    int placeOf(_Family family) {
      final first = order.indexWhere(
        (id) => id == family.id || id.startsWith('${family.id}-'),
      );
      return first < 0 ? order.length : first;
    }

    families.sort((a, b) => placeOf(a).compareTo(placeOf(b)));
    return families;
  }

  String? _model;
  String? _effort;
  final Map<String, String> _pickedEfforts = {};

  _Family? get _family =>
      _families.where((family) => family.id == _model).firstOrNull ??
      _families.firstOrNull;

  /// The model in use, by family.
  String? get _currentModel => _family?.id;

  /// The level the model in use thinks at: as picked for it, else its own
  /// default.
  String? _levelOf(_Family family) {
    final picked = _pickedEfforts[family.id] ?? _effort;
    if (family.levels.any((level) => level.id == picked)) return picked;
    if (family.levels.any((level) => level.id == family.defaultLevel)) {
      return family.defaultLevel;
    }
    return family.levels.lastOrNull?.id;
  }

  /// What the message is run on: the model at its level, as agy names
  /// it (its `planModel`).
  String? get _planModel {
    final family = _family;
    if (family == null) return null;
    final level = _levelOf(family);
    return family.levels
            .where((candidate) => candidate.id == level)
            .firstOrNull
            ?.model ??
        family.levels.first.model;
  }

  @override
  late final KernelChoiceSource model = _Choice(
    options: () => [
      for (final family in _families)
        KernelOption(family.id, family.label, Icons.auto_awesome_outlined, ''),
    ],
    selected: () => _currentModel,
    select: (id) {
      _model = id;
      emitInfoChanged();
    },
  );

  List<KernelOption> _effortsOf(String model) {
    final family = _families.where((family) => family.id == model).firstOrNull;
    if (family == null || family.levels.length < 2) return const [];
    return [
      for (final level in family.levels)
        KernelOption(
          level.id,
          level.label,
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
    selected: () => switch (_family) {
      final family? => _levelOf(family),
      null => null,
    },
    selectedFor: (model) =>
        switch (_families.where((family) => family.id == model).firstOrNull) {
          final family? => _levelOf(family),
          null => null,
        },
    select: (model, id) {
      _pickedEfforts[model] = id;
      _effort = id;
      if (model != _currentModel) _model = model;
      emitInfoChanged();
    },
  );

  // --- Renaming ---------------------------------------------------------------------------

  /// Named in agy (`UpdateConversationAnnotations`): what its list shows.
  @override
  void rename(String title) {
    final id = _sessionId;
    if (id == null) return;
    unawaited(
      _runtime
          .server()
          .then(
            (server) => server.call('UpdateConversationAnnotations', {
              'cascadeId': id,
              'annotations': {'title': title},
              'mergeAnnotations': true,
            }),
          )
          .then((_) => AntigravityCatalog.forget())
          .catchError((_) {}),
    );
  }

  // --- Context and usage -----------------------------------------------------------------

  @override
  int get contextWindow => _window;
  int _window = 1048576;

  void _usage(Map<String, Object?> usage) {
    final size = _int(usage['maxContextTokens']);
    if (size > 0) _window = size;
    emit(
      UsageReported(
        nextSeq,
        ContextUsage(window: _window, used: _int(usage['estimatedTokensUsed'])),
      ),
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

  /// The account's limits as Google tells agy (`RetrieveUserQuotaSummary`):
  /// each group of models' windows.
  Future<void> _askLimits() async {
    emit(
      StatsReported(
        nextSeq,
        UsageStats(limits: _limits, limitsState: LimitsState.checking),
      ),
    );
    var state = LimitsState.idle;
    try {
      if (await _runtime.locate() == null) {
        state = LimitsState.unavailable;
      } else {
        final server = await _runtime.server();
        final summary = await server.call('RetrieveUserQuotaSummary');
        _limits = limitsOf(summary);
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

  @visibleForTesting
  static List<RateLimitWindow> limitsOf(Map<String, Object?> summary) => [
    for (final group
        in _map(summary['response'])['groups'] as List? ?? const [])
      if (group is Map)
        for (final bucket in group['buckets'] as List? ?? const [])
          if (bucket is Map)
            RateLimitWindow(
              switch (bucket['window']) {
                'weekly' => 'Weekly ${group['displayName'] ?? ''} limit',
                'daily' => 'Daily ${group['displayName'] ?? ''} limit',
                _ =>
                  '${group['displayName'] ?? ''} ${bucket['displayName'] ?? 'limit'}',
              }.replaceAll(RegExp(r'\s+'), ' ').trim(),
              switch (bucket['remainingFraction']) {
                final num remaining => (1 - remaining.toDouble()).clamp(0, 1),
                _ => 0,
              },
              resetsAt: switch (bucket['resetTime']) {
                final String at => DateTime.tryParse(at)?.toLocal(),
                _ => null,
              },
            ),
  ];

  /// Asks for the limits in the background (a turn over), unless asked
  /// lately.
  void _limitsAfterTurn() {
    if (_limitsFresh(const Duration(minutes: 2))) return;
    unawaited(refreshUsage());
  }

  // --- History ---------------------------------------------------------------------------

  bool _loadingHistory = false;

  @override
  bool get loadingHistory => _loadingHistory;

  /// agy tells a conversation whole.
  @override
  bool get hasEarlierHistory => false;

  @override
  bool get loadingEarlier => false;

  @override
  Future<void> loadEarlier() => Future.value();

  // --- Background tasks ------------------------------------------------------------------

  /// Tasks the user stopped watching: not shown again.
  final Set<String> _dropped = {};

  void _tasksChanged() => _reportTasks();

  void _reportTasks() {
    if (_disposed) return;
    emit(
      TasksReported(nextSeq, [
        for (final task in _translator.tasks.values)
          if (!_dropped.contains(task.id)) task,
      ]),
    );
  }

  /// agy offers no way to stop one of its background tasks short of the
  /// conversation: it is no longer shown, and runs on.
  @override
  void stopTask(String taskId) {
    if (_dropped.add(taskId)) _reportTasks();
  }

  /// Its commands go on in the background on their own, never moved.
  @override
  void moveToBackground(String toolUseId) {}

  /// Tasks still running as the watch ends: not followed any more.
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

  // --- MCP servers -----------------------------------------------------------------------

  @override
  List<McpServer>? mcpServers;

  @override
  void refreshMcpServers() => unawaited(_readMcpServers());

  Future<void> _readMcpServers() async {
    final configured = await _runtime.mcpServers();
    if (_disposed) return;
    mcpServers = [
      if (_tools != null || ClaudeSdkTools.serversFor(_cwd ?? '').isNotEmpty)
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
      _runtime
          .setMcpServerEnabled(name, enabled)
          .then((_) => _readMcpServers()),
    );
  }

  /// agy connects its servers as a conversation starts: a later change
  /// shows in the next conversation.
  @override
  void reconnectMcpServer(String name) {}

  @override
  Future<Uri?> authenticateMcpServer(String name) async => null;

  // --- Helpers ---------------------------------------------------------------------------

  static Map<String, Object?> _map(Object? value) => switch (value) {
    final Map<String, Object?> map => map,
    final Map map => map.cast<String, Object?>(),
    _ => const {},
  };

  static int _int(Object? value) => switch (value) {
    final int n => n,
    final num n => n.toInt(),
    final String s => int.tryParse(s) ?? 0,
    _ => 0,
  };

  static String _base(String path) => path.split(RegExp(r'[/\\]')).last;
}

/// A key the app's tools are served at for one conversation.
abstract final class McpToolKey {
  static String make() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 12; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}

/// A model family as agy offers it: its thinking levels, each a model of
/// its own to agy.
class _Family {
  const _Family(this.id, this.label, this.levels, {this.defaultLevel});

  final String id;
  final String label;
  final List<_Level> levels;
  final String? defaultLevel;
}

class _Level {
  const _Level(this.id, this.label, this.model);

  final String id;
  final String label;

  /// agy's name for the model at this level (`MODEL_PLACEHOLDER_M318`).
  final String model;
}

/// Something agy waits on the user for: a step's permission or question,
/// or one of the app's tools'.
class _Ask {
  _Ask({this.index, this.trajectory, this.questions, this.sdk});

  final int? index;
  final String? trajectory;
  final List<Map<String, Object?>>? questions;
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
