import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:bao_remote/claude.dart' show ClaudeHistoryPage;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import '../../chat/composer/paste_store.dart';
import '../../chat/composer/remote_drops.dart';
import '../../models/codex/codex_service.dart';
import '../../models/launch_environment.dart';
import '../../models/model_icons.dart';
import '../../models/model_provider.dart';
import '../../models/model_providers.dart';
import '../../models/model_runtime.dart';
import '../../remote/remote_location.dart';
import '../../settings/user_settings.dart';
import '../../workspace/editor_launcher.dart' show openExternal;
import '../agent_kernel.dart';
import '../commit_attribution.dart';
import '../extension_switches.dart';
import '../kernel_event.dart';
import '../kernel_types.dart';
import '../prompt_suggestions.dart';
import '../transcript.dart';
import '../queued_messages.dart';
import 'claude_code_transport.dart';
import 'claude_code_translator.dart';
import 'claude_elicitation.dart';
import 'claude_goal.dart';
import 'claude_numbers.dart';
import 'claude_sdk_tools.dart';
import 'turn_stats.dart';
import 'control_channel.dart';
import 'local_time_zone.dart';
import 'usage_limit.dart';

/// Reads a kept session: its conversation lines, oldest first, along the
/// branch the session ended on.
typedef ClaudeHistoryReader = Future<List<Map<String, Object?>>> Function(
  SessionRecord session,
);

/// Reads some of a kept session: its last [turns], or the [turns] before
/// the line [before].
typedef ClaudeHistoryPager = Future<ClaudeHistoryPage> Function(
  SessionRecord session, {
  required int turns,
  String? before,
});

/// Copies the session [id], run in [cwd], into a new one, [into] (see
/// ClaudeSessions.fork): the new session's file.
typedef ClaudeSessionForker = Future<String> Function(
  String cwd,
  String id,
  String into, {
  String? before,
  String? title,
});

/// The setting Claude Code runs with that keeps it from asking for the
/// plan usage, if one does.
typedef ClaudeUsageSwitch = Future<String?> Function();

/// [executable], run in [cwd], refused an option BaoCode starts Claude
/// Code with: whether another, newer, may be started instead.
typedef ClaudeTooOldHandler = Future<bool> Function(
  String cwd,
  String executable,
);

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
/// permissions and questions come back as control requests of its own and
/// become [InteractionRequest]s; a plan is put to the user without waiting
/// (see [StartsPlans]).
class ClaudeCodeKernel
    with KernelEventSource
    implements
        AgentKernel,
        SelectsModel,
        SelectsMode,
        StartsPlans,
        SelectsPermission,
        SelectsEffort,
        SelectsContextSize,
        SelectsFast,
        ProvidesCommands,
        SuggestsFiles,
        ReportsContext,
        ReportsUsage,
        ReportsUsageLimit,
        RunsBackgroundTasks,
        QueuesMessages,
        RevertsChanges,
        RewindsConversation,
        ForksConversation,
        RenamesSession,
        AcceptsImages,
        SuggestsPrompts,
        ManagesMcpServers,
        ConfirmsModelSwitch,
        LoadsHistory {
  ClaudeCodeKernel(
    this.descriptor,
    this._context, {
    required this._start,
    ClaudeHistoryReader? readHistory,
    ClaudeHistoryPager? readHistoryPage,
    this._readGoal,
    this._forkSession,
    ClaudeUsageSwitch? usageOffBy,
    this._rejectTooOld,
    ModelProviders? providers,
    this._codex,
    ProviderEnvironment? providerEnvironment,
    Future<bool> Function(String url)? openLink,
  }) : _openLink = openLink ?? openExternal,
       _usageOffBy = usageOffBy ?? _usageOn,
       _providers = providers ?? ModelProviders.current,
       _providerEnvironment = providerEnvironment ?? providerLaunchEnvironment {
    _translator = ClaudeTranslator(
      emit: emit,
      nextSeq: () => nextSeq,
      goalSaid: _syncGoal,
    );
    _providers.addListener(_providersChanged);
    ExtensionSwitches.changes?.addListener(_applySwitches);
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
    final efforts = '${KernelChoiceKind.effort.name}@';
    final contexts = '${KernelChoiceKind.context.name}@';
    final speeds = '${KernelChoiceKind.fast.name}@';
    for (final MapEntry(:key, :value) in settings.entries) {
      if (key.startsWith(efforts)) {
        _pickedEfforts[key.substring(efforts.length)] = value;
      } else if (key.startsWith(contexts)) {
        if (parseTokens(value) case final tokens? when tokens > 0) {
          _pickedWindows[key.substring(contexts.length)] = tokens;
        }
      } else if (key.startsWith(speeds)) {
        _pickedFast[key.substring(speeds.length)] = value == 'fast';
      }
    }
    if (_model case final model? when !_pickedFast.containsKey(model)) {
      _pickedFast[model] = settings[KernelChoiceKind.fast.name] == 'fast';
    }
    Future<ClaudeHistoryPage> wholePage(
      SessionRecord session, {
      required int turns,
      String? before,
    }) async => ClaudeHistoryPage.whole(await readHistory!(session));
    final pager = readHistoryPage ?? (readHistory == null ? null : wholePage);
    if ((_context.resume, pager) case (final session?, final read?)) {
      _pager = read;
      _history = _replay(read, session);
    }
  }

  /// How many turns of a long session are read at first, from its end, and
  /// then each time the user asks for the earlier ones.
  static const _firstTurns = 10;
  static const _earlierTurns = 20;

  @override
  final KernelDescriptor descriptor;
  final KernelContext _context;

  /// Opens a link an MCP server asks the user to visit.
  final Future<bool> Function(String url) _openLink;
  final ClaudeTransportFactory _start;
  final ClaudeGoalReader? _readGoal;
  final ClaudeSessionForker? _forkSession;
  final ClaudeUsageSwitch _usageOffBy;

  /// A build that refused an option BaoCode starts it with, run in a
  /// folder: whether another, newer, may be started instead (see
  /// [_launch]). None: the user is told to update it.
  final ClaudeTooOldHandler? _rejectTooOld;
  late final ClaudeTranslator _translator;

  /// The providers of the user's (Settings → Models), whose models are
  /// offered beside Claude Code's own.
  final ModelProviders _providers;

  /// The ChatGPT providers' accounts: the app's when null.
  final CodexService? _codex;
  final ProviderEnvironment _providerEnvironment;

  static Future<String?> _usageOn() async => null;

  ClaudeCodeTransport? _transport;
  ControlChannel? _control;
  StreamSubscription<Map<String, Object?>>? _subscription;
  Future<void>? _starting;

  /// The build that exited too old as it started, and what it printed:
  /// another may be started in its place (see [_launch]).
  (String, String)? _tooOldExit;
  Future<void> _history = Future.value();

  @override
  bool get loadingHistory => _loadingHistory;
  bool _loadingHistory = false;

  @override
  bool get hasEarlierHistory => _earlier != null && !_loadingHistory;

  @override
  bool get loadingEarlier => _earlierLoad != null;
  ClaudeHistoryPager? _pager;

  /// What to read the turns before those read by, if there are some.
  String? _earlier;
  Future<void>? _earlierLoad;

  /// Whether what was read begins within a turn (a long one is cut so):
  /// the turn the page before it ends with goes on past it, so is not
  /// timed.
  bool _readInTurn = false;

  /// Whether [page] begins within a turn: with a message of the agent's,
  /// not the user's prompt.
  static bool _beginsInTurn(ClaudeHistoryPage page) {
    for (final line in page.entries) {
      if (line['type'] != 'attachment') return line['type'] == 'assistant';
    }
    return false;
  }

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

  /// The names sent, until the CLI tells them back: not renames of its
  /// own (see [SessionRenamed]).
  final List<String> _sentTitles = [];

  // What the CLI offers and has in effect. The catalog of the last session
  // to start stands in until this one's arrives; before any has this run,
  // Claude Code's own models as [modelCache] kept them.
  static _Catalog? _last;
  static _Catalog get _lastCatalog => _last ??= _Catalog(models: _keptModels());
  static set _lastCatalog(_Catalog catalog) => _last = catalog;
  _Catalog _catalog = _lastCatalog;

  /// Where Claude Code's own models are kept between runs (main.dart sets
  /// it), so the picker lists them while every session is on a provider's:
  /// as it last listed them, set up as the user has it.
  static GlobalStorage? get modelCache => _modelCache;
  static set modelCache(GlobalStorage? storage) {
    _modelCache = storage;
    _last = null;
  }

  static GlobalStorage? _modelCache;
  static const modelCacheKey = 'claudeCode.models';

  /// Where what each turn took and spent is kept (main.dart sets it), for
  /// its footer to show again when the session is opened later; none
  /// kept when null. This machine's sessions only.
  static TurnStats? turnStats;

  /// [turnStats] for this session's history: none for a remote one's.
  TurnStats? get _turnStats => _remoteHost == null ? turnStats : null;

  /// What the kept session's turns took and spent, by prompt.
  Future<Map<String, TurnRecord>> _keptTurns(SessionRecord session) async {
    try {
      return await _turnStats?.read(session.id) ?? const {};
    } on Object {
      return const {};
    }
  }

  /// The models [modelCache] kept, as the CLI listed them.
  static List<_ModelInfo> _keptModels() => [
    for (final raw
        in _modelCache?.get<List<Object?>>(modelCacheKey) ?? const [])
      if (raw is Map && raw['value'] is String)
        _ModelInfo.from(raw.cast<String, Object?>()),
  ];

  /// Keeps [models] (the CLI's own, as listed) in [modelCache], when they
  /// changed.
  static void _keepModels(List<Map<Object?, Object?>> models) {
    final storage = _modelCache;
    if (storage == null) return;
    final kept = storage.get<List<Object?>>(modelCacheKey);
    if (kept != null && jsonEncode(kept) == jsonEncode(models)) return;
    unawaited(
      storage
          .set(modelCacheKey, models)
          .catchError(
            (Object error) => debugPrint('$modelCacheKey not kept: $error'),
          ),
    );
  }

  /// The model asked for, as the CLI names it (e.g. `opus[1m]`), or a
  /// provider's ([modelRef]). BaoCode's own core has no model of its own:
  /// on it, one of no upstream is the first upstream's model. A provider's
  /// removed since falls back as the picker shows it: to Claude Code's own
  /// if offered there, else to the first upstream's.
  String? get _model {
    final picked = _pickedModel;
    if (_providers.resolve(picked) != null) return picked;
    if (_providers.builtinAvailable &&
        (parseModelRef(picked) == null || _providers.builtinOffered)) {
      return picked;
    }
    return _providers.firstModel ??
        (_providers.builtinAvailable ? picked : null);
  }

  set _model(String? model) => _pickedModel = model;
  String? _pickedModel;

  /// The provider's model the process was started on, which its
  /// environment names for each of Claude Code's own (`ANTHROPIC_MODEL`,
  /// `ANTHROPIC_DEFAULT_OPUS_MODEL`): whatever it was switched to since,
  /// one removed leaves it no use (see [_providersChanged]).
  String? _launchedModel;

  /// What the process was started on: [_providerKey] then. A provider
  /// is taken up only at start, so another is by a restart (see
  /// [_applyWindow]).
  String _launchedProvider = '';
  String? _reportedModel;

  /// When the usage limit the last turn hit resets (see
  /// [ReportsUsageLimit]): the account's own plan's, or every ChatGPT
  /// account of a provider out of quota; another provider's limits are
  /// its own.
  DateTime? _limitResetsAt;

  /// Whose limit [_limitResetsAt] is: '' the plan's, else the provider's
  /// ([_providerKey]) whose accounts are out of quota.
  String _limitOn = '';
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

  /// Each model's last choices, restored when switching back to it.
  final Map<String, String> _pickedEfforts = {};
  final Map<String, int> _pickedWindows = {};
  final Map<String, bool> _pickedFast = {};

  /// The [_window] the process was started with: the CLI takes it only
  /// at start, so another is taken up by a restart (see [_applyWindow]).
  int? _launchedWindow;

  /// Whether the process was started to suggest the next prompt
  /// ([PromptSuggestions]): taken only at start, so a change is taken up by
  /// a restart (see [_applyWindow]).
  bool _launchedSuggestions = true;

  /// What the process was started with, its flag settings' permission
  /// rules sent again with the [ExtensionSwitches] as they change.
  ClaudeLaunch? _launched;

  /// The [ExtensionSwitches] the process has: at start, then each change
  /// sent ([_applySwitches]).
  ExtensionSwitches _appliedSwitches = ExtensionSwitches.none;

  /// The context window, as the CLI reports it: the smaller of the
  /// model's and [_window].
  int _contextWindow = 200000;
  bool _contextReported = false;

  /// The models' own windows, by the model the CLI resolved them to, as
  /// reported while they were in use.
  static final Map<String, int> _modelWindows = {};
  double? _cost;

  /// The conversation's requests to the model, by their message's id, and
  /// how the cache took their input: from the session's file when resumed
  /// (turns in the terminal's CLI too), then as they come.
  final Map<String, CacheTokens> _requests = {};
  String? _lastRequest;

  /// The models whose replies said what the cache took: Claude's always,
  /// a provider's through the proxy only when it does (and then only when
  /// its cache was used). The cache is not shown for the others, as all
  /// uncached would be a guess.
  final Set<String?> _cachingModels = {};
  String? _lastModel;

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

  /// The workspace [_cwd] is the folder of, as it is at this launch.
  KernelWorkspace? get _workspace => _context.workspace?.call();

  /// When the messages sent while it works are taken up: as its workspace
  /// would have them, else as the user set.
  QueuedMessages get _queuedMessages =>
      _workspace?.queuedMessages ?? QueuedMessages.current();

  /// Starts the process, if not yet, and waits until it is ready.
  Future<void> _ensureStarted() {
    if (_disposed) return Future.error(StateError('disposed'));
    if (_running) return Future.value();
    return _starting ??= _launch().whenComplete(() {
      _starting = null;
      // Out of view while it started: freed now, unless a message sent
      // meanwhile has it at work.
      if (_releaseWanted) release();
    });
  }

  /// What a process started now is on: the provider, the model as it is
  /// asked for, and the effort. A model of a provider gone falls back to
  /// the CLI's.
  ({String provider, String? model, String? effort}) get _launchTarget {
    final custom = _custom;
    final effort = switch (custom) {
      (_, final info) => _effortFor(info),
      null => _effort,
    };
    return (
      provider: _providerKey,
      model: switch (custom) {
        (final provider, final info) => requestedModel(
          provider,
          info,
          effort: effort,
          fast: _pickedFast[_model] ?? false,
        ),
        null when parseModelRef(_model) != null => null,
        null => _model,
      },
      effort: effort,
    );
  }

  Future<void> _launch() async {
    await _history;
    // One process at a time on a session: the last one, if restarted.
    await _stopped;
    _setHealth(const KernelHealth(KernelHealthStatus.starting));
    try {
      // On a provider of the user's: its model as it is asked for, the
      // environment that points Claude Code at it, and compaction within
      // the model's window.
      final custom = _custom;
      final target = _launchTarget;
      final (:model, :effort, provider: _) = target;
      // Through the proxy, the effort goes with the model's name; to
      // Anthropic's API, as Claude Code's own, if it is one of its.
      final direct = custom == null || !custom.$1.protocolOf(custom.$2).proxied;
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
      final workspace = _workspace;
      _launchedProvider = target.provider;
      _launchedModel = custom != null ? _model : null;
      _launchedWindow = _autocompact;
      _launchedSuggestions = PromptSuggestions.current();
      _appliedSwitches = ExtensionSwitches.current();
      final sdkServers = ClaudeSdkTools.serversFor(_cwd);
      final transport = await _start(
        _launched = ClaudeLaunch(
          cwd: _cwd,
          sdkServers: sdkServers,
          resume: _sessionId,
          model: model,
          // Plan is entered once started.
          permissionMode: _cliMode = _cliApproval,
          autoModeDuringPlan: _planReviewed = _reviewsPlan,
          effort: direct && (custom == null || _cliEfforts.contains(effort))
              ? effort
              : null,
          thinking: custom != null && direct && effort == 'none' ? false : null,
          autocompact: _autocompact,
          promptSuggestions: _launchedSuggestions,
          switches: _appliedSwitches,
          attribution: CommitAttribution.current(),
          env: env,
          directories: [...?workspace?.folders, ...?workspace?.reaches],
          folderInstructions: workspace?.folders.isNotEmpty ?? false,
          // Long pastes are kept on this machine: only its agent reads them.
          // A remote one's reads the files of this machine's copied there.
          readable: RemoteLocation.isRemote(_cwd)
              ? RemoteDrops.folders
              : [?PasteStore.directory],
          instructions: workspace?.instructions,
          ownPrompt: workspace?.ownPrompt ?? false,
          tools: workspace?.tools,
          allowed: workspace?.allowedTools ?? const [],
          models: switch (custom) {
            (final provider, _) => _requestedModels(provider),
            null => const [],
          },
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
        await control.request('initialize', {
          'promptSuggestions': _launchedSuggestions,
          if (sdkServers.isNotEmpty) 'sdkMcpServers': sdkServers,
        }),
      );
      if (_mode != _cliMode) {
        _cliMode = _mode;
        await control.request('set_permission_mode', {'mode': _mode});
      }
      // Another model picked as it started (back in view, say), which it
      // was not told: nothing was said to it yet, so it starts again on it.
      if (_launchTarget != target) {
        _teardown();
        return await _launch();
      }
      _setHealth(KernelHealth.ready);
      // Switched since it was started.
      _applySwitches();
      _syncGoal();
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
        _sentTitles.add(title);
        // Waited on: a process freed as soon as it is ready (out of view
        // by then) would end before it took the title.
        await control
            .request('rename_session', {'title': title, 'source': 'host'})
            .catchError((_) => const <String, Object?>{});
      }
      unawaited(_refreshContext());
    } on ClaudeUnavailable catch (error) {
      _fail(
        error.message,
        error.detail,
        missingFolder: switch (error) {
          ClaudeFolderGone(:final folder) => folder,
          _ => null,
        },
        noModel: error is ClaudeNoModel,
      );
      rethrow;
    } on ControlError catch (error) {
      // Too old: a newer one, if there is one, started in its place.
      if (_tooOldExit case (final executable, final stderr)?) {
        _tooOldExit = null;
        if (!_disposed && await _rejectTooOld!(_cwd, executable)) {
          return _launch();
        }
        _failExit(stderr, executable);
      }
      // Exited while starting: what it said is kept (see _exited).
      if (_health.status != KernelHealthStatus.failed) {
        _fail('Claude Code did not start', '$error');
      }
      rethrow;
    }
  }

  void _fail(
    String message,
    String? detail, {
    String? missingFolder,
    bool noModel = false,
  }) {
    _teardown();
    _setHealth(
      KernelHealth(
        KernelHealthStatus.failed,
        message: message,
        detail: detail,
        missingFolder: missingFolder,
        noModel: noModel,
      ),
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

  /// Whether stopping the process would cut work short: [_working], or a
  /// task in the background whose notice the agent awaits.
  bool get _busy => _working || _translator.workingInBackground;

  /// A turn (or the CLI's work past one), one to come, or the start.
  bool get _working =>
      _turn != null ||
      _cliWorking ||
      _queued.isNotEmpty ||
      _permissions.isNotEmpty ||
      _starting != null;

  /// Frees the process now if idle, else once it has started or the CLI
  /// says it is idle (one that does not say keeps it until asked again).
  @override
  void release() {
    if (_busy) {
      _releaseWanted = true;
      return;
    }
    _releaseWanted = false;
    if (_transport == null) return;
    _teardown();
    _setHealth(KernelHealth.idle);
  }

  /// Stops the process if another [_window] was picked since it started,
  /// for the next message to start it again on the same session: the CLI
  /// compacts where it was told at start, whatever it is told after. Done
  /// only as a message is sent, so a pick leaves the conversation be.
  ///
  /// So is the prompt suggestions' setting turned on or off since.
  ///
  /// So is another provider, or one whose setup changed: the session goes
  /// on, resumed, on it. That even with tasks at work in the background
  /// (a server it started), which end with the process, or the CLI still
  /// saying it is at work past its turn: the user agreed to the restart,
  /// and the message is not for the provider before.
  void _applyWindow() {
    if (!_running) return;
    final otherProvider = _providerKey != _launchedProvider;
    if (!otherProvider &&
        _autocompact == _launchedWindow &&
        PromptSuggestions.current() == _launchedSuggestions) {
      return;
    }
    if (!otherProvider && _busy) return;
    _teardown();
    _translator.endTasks();
    _setHealth(KernelHealth.idle);
  }

  /// The skills, MCP servers and tools turned on or off since the process
  /// started, given it as flag settings: taken up at once, the next request
  /// to the model without them.
  void _applySwitches() {
    final launch = _launched;
    final switches = ExtensionSwitches.current();
    if (!_running || launch == null || switches == _appliedSwitches) return;
    _appliedSwitches = switches;
    _change([
      (
        'apply_flag_settings',
        {'settings': launch.switchSettings(switches, whole: true)},
      ),
    ]);
  }

  @override
  void dispose() {
    _disposed = true;
    _goalRetry?.cancel();
    _providers.removeListener(_providersChanged);
    ExtensionSwitches.changes?.removeListener(_applySwitches);
    _live.remove(this);
    _cancelSdkCalls();
    _teardown();
    closeEvents();
  }

  // --- The conversation -----------------------------------------------------------

  /// Set by [startBuilding]: the next message starts the plan awaiting.
  bool _startsPlan = false;

  @override
  void startBuilding() {
    _startsPlan = true;
    _work = 'agent';
    _applyMode();
  }

  @override
  void send(KernelTurn sent) {
    if (_sent.containsKey(sent.id)) return;
    var turn = sent;
    if (_startsPlan) {
      _startsPlan = false;
      // Told the model with it, so that it builds rather than plans on;
      // the note marks the plan started (see the translator).
      if (_translator.awaitingPlan case final plan?) {
        turn = KernelTurn(
          id: sent.id,
          text: sent.text,
          mentions: sent.mentions,
          images: sent.images,
          now: sent.now,
          notes: [...sent.notes, ClaudeTranslator.planStartedNote(plan.path)],
        );
      }
    }
    _sent[turn.id] = turn;
    if (_turn != null && _running && _providerKey != _launchedProvider) {
      // Another upstream picked while a turn runs (one retrying a provider
      // out of its usage, say): the message is for it, not for the process
      // on the one before, behind that turn. The turn stops, and the process
      // with it (as the switch's confirmation says it restarts); the
      // messages queued go again after, on the new one.
      final queued = [..._queued];
      cancel();
      _queued.clear();
      _held.clear();
      _teardown();
      _translator.endTasks();
      _setHealth(KernelHealth.idle);
      for (final id in [...queued, turn.id]) {
        if (_sent[id] case final queuedTurn?) _submit(queuedTurn);
      }
      return;
    }
    _submit(turn);
  }

  /// Starts a turn with [turn], or queues it behind the one running.
  void _submit(KernelTurn turn) {
    final busy = _turn != null;
    final hold = busy && _holds;
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
        UserMessageItem(
          text: turn.text,
          queued: busy,
          images: turn.images,
          sentAt: DateTime.now(),
        ),
      ),
    );
    // Taken now, as the message was sent.
    final ask = _work == 'ask';
    if (hold) {
      _held[turn.id] = ask;
    } else {
      _write(turn, ask: ask);
    }
  }

  /// Queued messages not given to the CLI yet, with whether each was sent
  /// to be answered only ([_askNote]). The CLI takes up all it queued as one
  /// turn: one of them waits there at a time (see [_holds]), the rest here.
  final Map<String, bool> _held = {};

  /// Whether a message queued now waits in [_held]: while another waits in
  /// the CLI, unless messages join the turn running (then all wait there,
  /// but for one sent now, to be taken up alone).
  bool get _holds {
    final waiting = _queued.where((id) => !_held.containsKey(id));
    return waiting.any((id) => _sent[id]?.now ?? false) ||
        (waiting.isNotEmpty && _queuedMessages == QueuedMessages.afterTurn);
  }

  /// Gives the CLI the messages held for it, as far as [_holds] lets it: one
  /// waiting there was taken up, or taken back.
  void _release() {
    while (_held.isNotEmpty && !_holds) {
      final MapEntry(key: id, value: ask) = _held.entries.first;
      _held.remove(id);
      if (_sent[id] case final turn?) _write(turn, ask: ask);
    }
  }

  void _write(KernelTurn turn, {required bool ask}) {
    // The message may wait for the CLI to start.
    final askEnded = _inAsk && !ask;
    _inAsk = ask;
    _whenReady((transport) {
      // Queued to go now, with tasks in the background: the CLI's interrupt
      // ends those too, so the CLI stops the turn for it itself, once the
      // call under way is done.
      final spareBackground =
          turn.now &&
          _queued.contains(turn.id) &&
          _translator.workingInBackground;
      transport.write({
        'type': 'user',
        'uuid': turn.id,
        'session_id': _sessionId ?? '',
        'parent_tool_use_id': null,
        // Taken up once the turn before it ends, unless the user would have
        // it folded into the turn running, between its tool calls (the
        // CLI's own default).
        'priority': spareBackground
            ? 'now'
            : switch (_queuedMessages) {
                QueuedMessages.afterTurn => 'later',
                QueuedMessages.duringTurn => 'next',
              },
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
            for (final note in turn.notes) {'type': 'text', 'text': note},
            if (ask)
              {'type': 'text', 'text': _askNote}
            else if (askEnded)
              {'type': 'text', 'text': _askEndedNote},
          ],
        },
      });
      // Queued behind the turn running: stopped once it is sent, so it is
      // taken up next, as when the user stops the turn.
      if (turn.now && _queued.contains(turn.id) && !spareBackground) cancel();
    });
  }

  void _beginTurn(String id, {bool unprompted = false}) {
    _turn = id;
    _limitHit(null);
    _turnStarted = DateTime.now();
    _translator.turnId = id;
    emit(TurnStarted(nextSeq, id, unprompted: unprompted));
    _translator.begin();
  }

  void _endTurn({
    required bool interrupted,
    Duration? worked,
    TurnUsage? usage,
  }) {
    final turn = _turn;
    if (turn == null) return;
    _turn = null;
    if (interrupted) _cancelSdkCalls();
    worked ??= switch (_turnStarted) {
      final started? => DateTime.now().difference(started),
      null => null,
    };
    _translator.settle();
    // As streamed, where it was: the agent's own requests, timed.
    if (_translator.turnUsage case final streamed?) {
      usage = TurnUsage(
        inputTokens: streamed.inputTokens,
        outputTokens: streamed.outputTokens,
        tokensPerSecond: streamed.tokensPerSecond,
        costUsd: usage?.costUsd,
      );
    }
    for (final id in _permissions.keys) {
      emit(InteractionResolved(nextSeq, id));
    }
    _permissions.clear();
    if (!interrupted && worked != null) {
      if ((_turnStats, _sessionId) case (final stats?, final session?)) {
        stats.write(session, turn, (worked: worked, usage: usage));
      }
    }
    emit(
      TurnEnded(
        nextSeq,
        turn,
        interrupted: interrupted,
        worked: worked,
        usage: usage,
      ),
    );
  }

  @override
  void cancel() {
    final turn = _turn;
    if (turn == null) return;
    _stoppedTurns.add(turn);
    _tell('interrupt');
    _endTurn(interrupted: true);
  }

  /// Completes as the turn's calls of the app's own tools are given up
  /// (see [ClaudeSdkCall.cancelled]): a turn stopped, the session ended.
  var _sdkCallsCancelled = Completer<void>();

  void _cancelSdkCalls() {
    final cancelled = _sdkCallsCancelled;
    _sdkCallsCancelled = Completer<void>();
    cancelled.complete();
  }

  @override
  Future<bool> cancelQueued(String turnId) async {
    if (!_queued.contains(turnId)) return false;
    if (_held.remove(turnId) != null) {
      _queued.remove(turnId);
      emit(ItemRemoved(nextSeq, turnId));
      return true;
    }
    if (!_running) return false;
    try {
      final response = await _control!.request('cancel_async_message', {
        'message_uuid': turnId,
      });
      if (response['cancelled'] != true) return false;
    } on Object {
      return false;
    }
    // The CLI tells of it as cancelled before it answers: then already
    // taken out (see _lifecycle).
    if (_queued.remove(turnId)) emit(ItemRemoved(nextSeq, turnId));
    _release();
    return true;
  }

  @override
  void sendQueuedNow(String turnId) {
    if (!_queued.contains(turnId)) return;
    if (!_running) {
      // The queue is shown before the process finishes starting. Keep the
      // request behind its pending writes, then check the queue again.
      _whenReady((_) {
        if (_running) sendQueuedNow(turnId);
      });
      return;
    }
    final others = [
      for (final id in _queued)
        if (id != turnId) id,
    ];
    // The only one in the CLI, the others held: next anyway, only the turn
    // running is in the way. Not with tasks in the background, which an
    // interrupt ends too: it is sent again to be taken up next (see
    // [_write]).
    if (!_translator.workingInBackground &&
        !_held.containsKey(turnId) &&
        others.every(_held.containsKey)) {
      cancel();
      return;
    }
    // The CLI takes up all it queued as one turn, in the order sent: the
    // others are taken back too, and sent again after it, held until it is
    // taken up. Those held first, for none to be given the CLI meanwhile.
    final order = [turnId, ...others];
    unawaited(() async {
      final taken = {
        for (final id in [
          ...order.where(_held.containsKey),
          ...order.where((id) => !_held.containsKey(id)),
        ])
          if (await cancelQueued(id)) id,
      };
      for (final id in order.where(taken.contains)) {
        final turn = _sent[id]!;
        send(
          KernelTurn(
            id: _newSessionId(),
            text: turn.text,
            mentions: turn.mentions,
            images: turn.images,
            notes: turn.notes,
            now: id == turnId,
          ),
        );
      }
    }());
  }

  /// Dropped here only once the CLI has: turned down, it goes on with all
  /// of the conversation, and so does what is shown.
  @override
  Future<bool> rewind({
    required String itemId,
    required int index,
    required int turns,
    String? lastSeen,
  }) {
    final rewound = Completer<bool>();
    _writes = _writes
        .then(
          (_) => _request('rewind_conversation', {
            'target_message_uuid': itemId,
            // The turn stopped may not have stopped yet: the CLI turns a
            // rewind down while one runs, unless it is to stop it.
            'interrupt_if_running': true,
            // Unsaid, a later message counts as unseen: turned down too.
            'last_seen_user_message_uuid': ?lastSeen,
          }),
        )
        .then((response) {
          // Turned down, it answers all the same.
          if (response['rewound'] == false) {
            throw ControlError(
              'rewind_conversation',
              '${response['error'] ?? response['reason'] ?? 'turned down'}',
            );
          }
          emit(Rewound(nextSeq, itemId: itemId, index: index));
          rewound.complete(true);
        })
        .catchError((Object error) {
          emit(
            ItemUpserted(
              nextSeq,
              'rewind:$itemId',
              NoticeItem(NoticeKind.error, 'Could not rewind: $error'),
            ),
          );
          rewound.complete(false);
        });
    return rewound.future;
  }

  @override
  bool get canFork => _forkSession != null && _sessionId != null;

  /// Copied where the session is kept, as Claude Code wrote it so far: a
  /// turn running goes on here alone.
  @override
  Future<SessionRecord?> fork({String? before, required String title}) async {
    final (forkSession, id) = (_forkSession, _sessionId);
    if (forkSession == null || id == null) return null;
    final into = _newSessionId();
    try {
      final path = await forkSession(
        _cwd,
        id,
        into,
        before: before,
        title: title,
      );
      return SessionRecord(
        id: into,
        title: title,
        updatedAt: DateTime.now(),
        cwd: _cwd,
        path: path,
      );
    } on Object catch (error) {
      emit(
        ItemUpserted(
          nextSeq,
          'fork:${before ?? id}',
          NoticeItem(NoticeKind.error, 'Could not fork: $error'),
        ),
      );
      return null;
    }
  }

  static final _random = math.Random.secure();

  /// A random UUID (v4), as Claude Code names its sessions.
  static String _newSessionId() {
    String hex(int length) =>
        [for (var i = 0; i < length; i++) _random.nextInt(16).toRadixString(16)]
            .join();
    final variant = (8 + _random.nextInt(4)).toRadixString(16);
    return '${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(12)}';
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
    _sentTitles.add(title);
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
    if (permission.elicitation case (:final fields, :final url)?) {
      control.respond(requestId, switch (answer) {
        QuestionAnswer() => elicitationResult(fields, answer),
        ApprovalAnswer(decision: ApprovalDecision.deny) => {
          'action': 'decline',
        },
        ApprovalAnswer() => () {
          if (url != null && url.isNotEmpty) unawaited(_openLink(url));
          return {'action': 'accept'};
        }(),
      });
      return;
    }
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

  Future<void> _permission(
    String requestId,
    Map<String, Object?> request,
  ) async {
    final tool = request['tool_name'] as String? ?? 'Tool';
    final input = (request['input'] as Map?)?.cast<String, Object?>() ?? {};
    final suggestions = request['permission_suggestions'] as List? ?? const [];
    // The plan is put to the user without waiting on them: its card
    // awaits, the turn ends, and their next message starts it (see
    // startBuilding) or says what should change. The CLI stays in Plan.
    if (tool == 'ExitPlanMode') {
      _control!.respond(requestId, {
        'behavior': 'deny',
        'message': ClaudeTranslator.planPresented,
      });
      return;
    }
    // Answered here, with nothing shown: in Don't ask nothing that is not
    // pre-approved is asked about (the CLI asks in Plan all the same). A
    // question is always the user's to answer, in any mode: the approvals
    // are about what the agent does, not what it asks.
    if (_approval == 'dontAsk' && tool != 'AskUserQuestion') {
      _control!.respond(requestId, {'behavior': 'deny', 'message': _notAsked});
      return;
    }
    // Full access is approved here (see _cliApproval), but for what the
    // CLI's own would ask all the same: that too where no one is there to
    // ask (a bot's, KernelWorkspace.approvesAll). In Plan it leaves to the
    // classifier what the CLI cannot tell is read-only; with no
    // classifier (another provider's model), that is approved here too,
    // as it would be by the classifier.
    if (_approval == 'bypassPermissions' &&
        (_work != 'plan' || !_classifies) &&
        tool != 'AskUserQuestion' &&
        ((_workspace?.approvesAll ?? false) || !_askedInFullAccess(request))) {
      _control!.respond(requestId, {
        'behavior': 'allow',
        'updatedInput': input,
      });
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
          executable: message['executable'] as String?,
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
      case 'system' when message['subtype'] == 'compact_boundary':
        _translator.translate(message);
        _compacted(message);
      case 'system' when message['subtype'] == 'session_state_changed':
        _cliWorking = message['state'] != 'idle';
        // A turn's checks of the goal are all kept by now.
        if (!_cliWorking) _syncGoal();
        if (!_cliWorking && _releaseWanted) release();
      // Its name as it stands, at start and on each change. The host's own
      // come back too, in the order sent: not told. Nor the old name, told
      // at start while the host's waits to be sent.
      case 'system' when message['subtype'] == 'session_title_changed':
        if (message['title'] case final String named
            when named.trim().isNotEmpty) {
          final title = named.trim();
          final sent = _sentTitles.indexOf(title);
          if (sent >= 0) {
            _sentTitles.removeRange(0, sent + 1);
          } else if (_pendingTitle == null) {
            emit(SessionRenamed(nextSeq, title));
          }
        }
      case 'system' when message['subtype'] == 'commands_changed':
        _catalog = _catalog.copyWith(
          commands: _commandsFrom(message['commands']),
        );
        emitInfoChanged();
      case 'assistant':
        if (_countRequest(message)) _reportStats();
        if (message['error'] == 'rate_limit') {
          _limitSaid(message['message']);
          _accountsLimited();
        }
        _translator.translate(message);
      case 'result':
        _result(message);
      case 'rate_limit_event':
        _rateLimits(message['rate_limit_info']);
      case 'command_lifecycle':
        _lifecycle(message);
      case 'prompt_suggestion':
        final suggestion = (message['suggestion'] as String?)?.trim();
        // One turned off since the process started is not offered.
        if (_turn == null &&
            _queued.isEmpty &&
            suggestion != _suggestion &&
            PromptSuggestions.current()) {
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
        _elicitation(id, request);
      case 'mcp_message':
        unawaited(_mcpMessage(id, request));
      default:
        control.refuse(id, 'Not supported by this client');
    }
  }

  /// What the agent says to one of the app's own MCP servers (see
  /// claude_sdk_tools.dart), answered.
  Future<void> _mcpMessage(String id, Map<String, Object?> request) async {
    final message = (request['message'] as Map?)?.cast<String, Object?>();
    if (request['server_name'] != ClaudeSdkTools.server || message == null) {
      _control?.refuse(id, 'No such server');
      return;
    }
    final response = await ClaudeSdkTools.handle(
      message,
      ClaudeSdkCall(
        cwd: _cwd,
        sessionId: _sessionId,
        cancelled: _sdkCallsCancelled.future,
      ),
    );
    _control?.respond(id, {'mcp_response': response});
  }

  /// An MCP server asks the user for input: its form as questions, or a
  /// link to visit as leave to open it. Asked in any mode, as a question
  /// of the agent's is: it is not an action the approvals cover.
  void _elicitation(String requestId, Map<String, Object?> request) {
    final server =
        request['display_name'] as String? ??
        request['mcp_server_name'] as String? ??
        'MCP';
    final message = _clean(request['message'] as String?) ?? '';
    final InteractionRequest interaction;
    var fields = const <ElicitationField>[];
    if (request['mode'] == 'url') {
      final url = request['url'] as String? ?? '';
      interaction = ApprovalRequest(
        id: requestId,
        title:
            request['title'] as String? ?? '$server wants you to open a link',
        toolName: 'mcp__$server',
        reason: message.isEmpty ? null : message,
        preview: TextPreview(url),
      );
    } else {
      fields = elicitationFields(request['requested_schema']);
      interaction = QuestionRequest(
        id: requestId,
        title: request['title'] as String? ?? '$server asks for input',
        questions: elicitationQuestions(message, fields),
      );
    }
    _permissions[requestId] = _Permission(
      const {},
      const [],
      const [],
      elicitation: (fields: fields, url: request['url'] as String?),
    );
    emit(InteractionRequested(nextSeq, interaction));
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
                sentAt: DateTime.now(),
              ),
            ),
          );
        }
        if (_turn != id &&
            _sent.containsKey(id) &&
            !_stoppedTurns.contains(id)) {
          _beginTurn(id);
        }
        _release();
      case 'cancelled':
        if (_queued.remove(id)) emit(ItemRemoved(nextSeq, id));
        _release();
    }
  }

  void _result(Map<String, Object?> message) {
    // The session's cost so far: the turn's is what it grew by (all of it
    // when it fell, the CLI having started over).
    double? turnCost;
    if (message['total_cost_usd'] case final num cost) {
      final before = _cost ?? 0;
      _cost = cost.toDouble();
      turnCost = _cost! >= before ? _cost! - before : _cost;
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
      if (_limitResetsAt == null) _limitSaid(error);
      _accountsLimited();
      if (error.isNotEmpty) {
        final host = _remoteHost;
        emit(
          ItemUpserted(
            nextSeq,
            'error:${message['uuid'] ?? _turn}',
            NoticeItem(
              NoticeKind.error,
              // On a host over SSH: what may be why, and what to do.
              host != null && _notLoggedIn(error)
                  ? '$error\n\n${remoteLoginHint(host)}'
                  : error,
            ),
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
      // Its tokens as the result counts them, for when none streamed (its
      // API time is the session's, too coarse for a speed).
      usage: switch (message['usage']) {
        final Map<Object?, Object?> usage => TurnUsage(
          inputTokens: [
            'input_tokens',
            'cache_creation_input_tokens',
            'cache_read_input_tokens',
          ].fold<int>(0, (sum, key) => sum + (claudeInt(usage[key]) ?? 0)),
          outputTokens: claudeInt(usage['output_tokens']),
          costUsd: turnCost,
        ),
        _ => TurnUsage(costUsd: turnCost),
      },
    );
    unawaited(_refreshContext());
  }

  // --- Goal ------------------------------------------------------------------------

  /// A reading of the goal under way, and whether another is wanted once
  /// it is done.
  Future<void>? _goalReading;
  bool _goalAgain = false;

  /// The goal records there were at the first reading: a goal met or given
  /// up on before is not shown as just met.
  int? _goalSeen;

  /// The hooks and the records disagreed at the last reading: read again a
  /// moment later, once.
  Timer? _goalRetry;
  bool _goalRetried = false;

  /// Has the goal as Claude Code now has it (see claude_goal.dart): one
  /// reading at a time, the last asked for done after it.
  void _syncGoal() {
    if (_disposed) return;
    if (_goalReading != null) {
      _goalAgain = true;
      return;
    }
    _goalReading = _readGoalNow().whenComplete(() {
      _goalReading = null;
      if (_goalAgain) {
        _goalAgain = false;
        _syncGoal();
      }
    });
  }

  Future<void> _readGoalNow() async {
    final id = _sessionId;
    if (id == null) return;
    final control = _control;
    // Asked of both at once; either may not answer (an older CLI, a host
    // gone).
    final (hooks, records) = await (
      _orNull(
        control?.request('get_hooks_listing', {}, const Duration(seconds: 10)),
      ),
      _orNull(_readGoal?.call(_cwd, id)),
    ).wait;
    if (_disposed || (hooks == null && records == null)) return;
    if (records != null) {
      _goalSeen ??= _context.resume == null ? 0 : records.length;
    }
    final kept = keptGoal(records ?? const [], seen: _goalSeen ?? 0);
    final goal = hooks == null ? kept : goalInEffect(kept, hookedGoal(hooks));
    _translator.reportGoal(goal);
    // The file is written a moment after the hooks change.
    if (hooks != null && records != null && goal != kept) {
      if (!_goalRetried) {
        _goalRetried = true;
        _goalRetry?.cancel();
        _goalRetry = Timer(const Duration(seconds: 1), _syncGoal);
      }
    } else {
      _goalRetried = false;
    }
  }

  /// What [future] comes to; null when it fails, or there is none.
  static Future<T?> _orNull<T>(Future<T>? future) async {
    try {
      return await future;
    } on Object {
      return null;
    }
  }

  static String _limitLabel(Object? type) => switch (type) {
    'five_hour' => '5-hour limit',
    'seven_day' => 'Weekly limit',
    'seven_day_opus' => 'Weekly Opus limit',
    'seven_day_sonnet' => 'Weekly Sonnet limit',
    'seven_day_overage_included' => 'Weekly with extra usage',
    _ => '$type',
  };

  @override
  DateTime? get usageLimitResetsAt => usageLimitApplies ? _limitResetsAt : null;

  /// Another provider's model picked: the next message goes there, the
  /// limit hit no bar to it. None hit, whether the one picked has a limit
  /// known here.
  @override
  bool get usageLimitApplies =>
      _limitResetsAt == null ? _hasLimit(_model) : _limitOn == _providerKey;

  @override
  bool usageLimitAppliesTo(String model) => _hasLimit(model);

  /// Whether [model] is held to a limit known here: the plan's, or its
  /// ChatGPT accounts' quota; not another provider's.
  bool _hasLimit(String? model) => switch (_providers.resolve(model)) {
    (final provider, _) => provider.protocol.usesAccounts,
    null => true,
  };

  /// The usage limit is hit, to reset [at]; null, it no longer holds.
  /// [on] is whose: '' the plan's, else the provider's of [_accountsLimited].
  void _limitHit(DateTime? at, {String on = ''}) {
    // A provider's limits are its own, and so is what it says of them:
    // its accounts' quota is learned of them, not of the CLI.
    if (at != null && on != _launchedProvider) return;
    if (at == _limitResetsAt && on == _limitOn) return;
    _limitResetsAt = at;
    _limitOn = on;
    emitInfoChanged();
  }

  /// A turn failed on a provider of ChatGPT accounts: if each one is out
  /// of quota, its limit is hit, to reset as the first is back.
  void _accountsLimited() {
    if (_launchedProvider.isEmpty) return;
    if (_custom case (final provider, _) when provider.protocol.usesAccounts) {
      if ((_codex ?? codexService).backAt(provider) case final at?) {
        _limitHit(at, on: _launchedProvider);
      }
    }
  }

  /// When the limit hit resets, as [said] (an error's text, or the
  /// message it is in) says it; nothing where it does not.
  void _limitSaid(Object? said) {
    final text = switch (said) {
      final String text => text,
      {'content': final List<Object?> content} => [
        for (final block in content)
          if (block case {'type': 'text', 'text': final String text}) text,
      ].join('\n'),
      _ => '',
    };
    if (_limitResetsAt != null || text.isEmpty) return;
    // A remote project's agent says the time in its host's zone.
    final at = parseUsageLimitReset(
      text,
      now: DateTime.now(),
      localZone: _remoteHost == null ? localTimeZone() : null,
    );
    if (at != null && (_remoteHost == null || _zoneSaid(text) == null)) {
      _limitHit(at);
    }
  }

  /// The zone a reset time is said in, if it says one.
  static String? _zoneSaid(String text) =>
      RegExp(r'resets [^(\n]*\(([^)]+)\)').firstMatch(text)?[1];

  /// From a `rate_limit_event`, sent as a reply changes the usage: the
  /// windows, or near a limit just that one. Rejected, the limit is hit:
  /// it says when it resets.
  void _rateLimits(Object? info) {
    if (info is! Map) return;
    if (info['status'] == 'rejected') {
      final resets = [
        if (info['resetsAt'] case final int at) at,
        if (info['unifiedWindows'] case final Map<Object?, Object?> windows)
          for (final window in windows.values)
            // The windows used up: those that hold it back.
            if (window case {'resetsAt': final int at} && final Map used
                when used['status'] == 'rejected' ||
                    switch (used['utilization']) {
                      final num utilization => utilization >= 1,
                      _ => false,
                    })
              at,
      ];
      if (resets.isNotEmpty) {
        _limitResetsAt = null;
        _limitHit(
          DateTime.fromMillisecondsSinceEpoch(resets.reduce(math.max) * 1000),
        );
      }
    }
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
        cache: switch (_requests[_lastRequest]) {
          final last? when _cachingModels.contains(_lastModel) => PromptCache(
            last: last,
            conversation: _requests.values.reduce((a, b) => a + b),
          ),
          _ => null,
        },
      ),
    ),
  );

  /// Counts the request to the model [message] answers, if it is the
  /// conversation's: once, as a message comes a content block at a time,
  /// each with its request's usage. A subagent's is left out, as its
  /// transcript is apart. Whether it was not counted yet.
  bool _countRequest(Map<String, Object?> message) {
    if (message['parent_tool_use_id'] != null ||
        message['isSidechain'] == true) {
      return false;
    }
    final body = message['message'];
    final (id, usage) = switch (body) {
      {'id': final String id, 'usage': final Map<Object?, Object?> usage} => (
        id,
        usage,
      ),
      _ => (null, null),
    };
    if (id == null || usage == null) return false;
    final model = (body as Map)['model'] as String?;
    int count(String key) => claudeInt(usage[key]) ?? 0;
    final tokens = CacheTokens(
      read: count('cache_read_input_tokens'),
      written: count('cache_creation_input_tokens'),
      uncached: count('input_tokens'),
    );
    // None at all: one of the CLI's own (an API error), not the model's.
    if (tokens.total == 0) return false;
    _lastRequest = id;
    _lastModel = model;
    if (usage.containsKey('cache_read_input_tokens') ||
        usage.containsKey('cache_creation_input_tokens')) {
      _cachingModels.add(model);
    }
    if (_requests.containsKey(id)) return false;
    _requests[id] = tokens;
    return true;
  }

  /// The conversation was compacted, maybe mid-turn: the context shown
  /// drops to what is left at once, then to what the CLI counts.
  void _compacted(Map<String, Object?> message) {
    final meta = message['compact_metadata'];
    if (meta is Map && meta['post_tokens'] is int) {
      emit(
        UsageReported(
          nextSeq,
          ContextUsage(
            window: _contextWindow,
            used: meta['post_tokens'] as int,
          ),
        ),
      );
    }
    unawaited(_refreshContext());
  }

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

  void _exited(int code, String stderr, {String? executable}) {
    final wasReady = _health.status == KernelHealthStatus.ready;
    _teardown();
    if (!wasReady &&
        _starting != null &&
        _rejectTooOld != null &&
        executable != null &&
        _tooOld(stderr)) {
      // The launch under way starts a newer one, if there is one, the
      // turn going on there; else it says this and ends the turn.
      _tooOldExit = (executable, stderr);
      return;
    }
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
    _held.clear();
    _translator.endTasks();
    if (_disposed) return;
    if (code == 0 && wasReady) {
      _setHealth(KernelHealth.idle);
    } else {
      _failExit(stderr, executable);
    }
  }

  void _failExit(String stderr, String? executable) {
    final lines = stderr.trim().split('\n');
    final printed = lines
        .skip(lines.length > 12 ? lines.length - 12 : 0)
        .join('\n');
    _setHealth(
      KernelHealth(
        KernelHealthStatus.failed,
        message: _failureMessage(stderr, remote: _remoteHost),
        // Which one, when it is too old: another, newer, may be the
        // terminal's.
        detail: _tooOld(stderr) && executable != null
            ? '$printed\n\nThe one run: $executable'
            : printed,
      ),
    );
  }

  /// Whether the CLI refused an option BaoCode starts it with: one from
  /// before the option was.
  static bool _tooOld(String stderr) => stderr.contains("unknown option '--");

  /// The SSH host the agent runs on; null for this machine.
  String? get _remoteHost => RemoteLocation.hostOf(_cwd);

  /// Whether [text] says Claude Code is not logged in.
  static bool _notLoggedIn(String text) {
    final lower = text.toLowerCase();
    return lower.contains('login') ||
        lower.contains('api key') ||
        lower.contains('authenticat');
  }

  /// Why Claude Code on [host] may say it is not logged in when it is: on a
  /// Mac, its credentials are in the login keychain, which stays locked for
  /// a session over SSH; and what to do.
  static String remoteLoginHint(String host) =>
      'Claude Code on $host is not logged in for this SSH session. If '
      'it is logged in there, and $host is a Mac, its login keychain is '
      'locked over SSH: unlock it in a terminal of the project '
      '(`security unlock-keychain ~/Library/Keychains/login.keychain-db`), '
      'or run `claude setup-token` there and set the token it gives as '
      '`CLAUDE_CODE_OAUTH_TOKEN`. Otherwise, run `claude` there and log in.';

  static String _failureMessage(String stderr, {String? remote}) {
    if (_tooOld(stderr)) {
      return 'Claude Code is older than BaoCode needs. Update it '
          '(`claude update`) and try again.';
    }
    final lower = stderr.toLowerCase();
    if (_notLoggedIn(stderr)) {
      if (remote != null) return remoteLoginHint(remote);
      return 'Claude Code is not logged in. Run `claude` in a terminal and '
          'log in.';
    }
    if (lower.contains('no conversation found')) {
      return 'This session can no longer be resumed';
    }
    return 'Claude Code stopped';
  }

  // --- History ------------------------------------------------------------------------

  Future<void> _replay(ClaudeHistoryPager read, SessionRecord session) async {
    // Read in the constructor, before anyone listens: seen when asked.
    _loadingHistory = true;
    try {
      // Read alongside; never fails.
      final keptTurns = _keptTurns(session);
      final page = await read(session, turns: _firstTurns);
      final kept = await keptTurns;
      _earlier = page.earlier;
      _readInTurn = _beginsInTurn(page);
      _translator
        ..replaying = true
        ..keptTurns = kept;
      var counted = false;
      for (final line in page.entries) {
        if (line['type'] == 'assistant') counted |= _countRequest(line);
        _translator.translate(line);
      }
      _translator.endReplay();
      if (counted) _reportStats();
    } on Object catch (error) {
      emit(
        ItemUpserted(
          nextSeq,
          'history-error',
          NoticeItem(NoticeKind.error, 'Could not read this session: $error'),
        ),
      );
    } finally {
      _translator
        ..replaying = false
        ..keptTurns = const {};
      _loadingHistory = false;
      if (!_disposed) emitInfoChanged();
    }
  }

  @override
  Future<void> loadEarlier() {
    if (_earlier == null || _disposed) return Future.value();
    return _earlierLoad ??= _readEarlier().whenComplete(() {
      _earlierLoad = null;
      if (!_disposed) emitInfoChanged();
    });
  }

  Future<void> _readEarlier() async {
    emitInfoChanged();
    try {
      final keptTurns = _keptTurns(_context.resume!);
      final page = await _pager!(
        _context.resume!,
        turns: _earlierTurns,
        before: _earlier,
      );
      final kept = await keptTurns;
      if (_disposed) return;
      // Told apart from the live one: it only gathers the items, and its
      // events never reach the stream.
      var seq = 0;
      final items = Transcript();
      final translator =
          ClaudeTranslator(emit: items.apply, nextSeq: () => ++seq)
            ..replaying = true
            ..keptTurns = kept;
      var counted = false;
      for (final line in page.entries) {
        if (line['type'] == 'assistant') counted |= _countRequest(line);
        translator.translate(line);
      }
      if (!_readInTurn) translator.endPage();
      if (counted) _reportStats();
      _earlier = page.earlier;
      _readInTurn = _beginsInTurn(page);
      emit(HistoryPrepended(nextSeq, [...items.liveItems]));
    } on Object catch (error) {
      if (_disposed) return;
      emit(
        ItemUpserted(
          nextSeq,
          'history-error',
          NoticeItem(NoticeKind.error, 'Could not read earlier: $error'),
        ),
      );
    }
  }

  // --- Options ------------------------------------------------------------------------

  void _applyInitialize(Map<String, Object?> response) {
    // Claude Code's own models are those it lists set up as the user has
    // it: one on a provider lists what the provider's names stand in for.
    final own = _launchedProvider.isEmpty;
    final listed = [
      for (final raw in response['models'] as List? ?? const [])
        if (raw is Map) raw.cast<Object?, Object?>(),
    ];
    if (own) _keepModels(listed);
    _catalog = _lastCatalog = _catalog.copyWith(
      commands: _commandsFrom(response['commands']),
      models: own
          ? [
              for (final raw in listed)
                _ModelInfo.from(raw.cast<String, Object?>()),
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

  /// What the conversation is on now: the process's provider while one
  /// runs, whatever is picked since (a model of one removed, say), else
  /// the one picked. A model of another is not told that process: one on
  /// a provider takes Claude Code's names ("opus") for the provider's
  /// model (`ANTHROPIC_DEFAULT_OPUS_MODEL`).
  String get _onProvider =>
      _transport != null ? _launchedProvider : _providerKey;

  /// Whether the conversation has begun: going on with it on another
  /// provider is a restart.
  bool get _conversationStarted => _sent.isNotEmpty || _context.resume != null;

  void _providersChanged() {
    if (_disposed) return;
    emitInfoChanged();
    // Failed for want of a model, it starts on the first one added.
    if (_health.noModel && _model != null) restart();
    // Started on a model removed since: let go (once idle), for the next
    // message to start one on the model now picked.
    if (_transport != null &&
        _launchedModel != null &&
        _providers.resolve(_launchedModel) == null) {
      _launchedModel = null;
      release();
    }
  }

  /// The heading Claude Code's own models are listed under.
  static final _builtinGroup = KernelOptionGroup(
    builtinProviderId,
    'Claude Code',
    iconBuilder: _providerIcon(builtinProviderId),
  );

  /// Provider [id]'s icon, as its models' heading shows it.
  static Widget Function(double, Color) _providerIcon(String id) =>
      (size, color) => ProviderIcon(id, size: size, color: color);

  /// [model]'s of [provider], as its option shows it.
  static Widget Function(double, Color) _modelIcon(
    String provider,
    String model,
  ) =>
      (size, color) =>
          ModelIcon(provider: provider, model: model, size: size, color: color);

  @override
  bool switchRestarts(String model) =>
      _conversationStarted && _providerKeyOf(model) != _onProvider;

  /// Switches to [id], an option of [model], on the effort and context it
  /// was last on (those of the model in use noted first, unless [keep] is
  /// false: a setting picked with it already was): on the provider in use, as
  /// the CLI is told; on another, by starting again on it (at once, if
  /// the conversation has not begun; else as the next message is sent,
  /// which resumes it there).
  void _selectModel(String id, {bool keep = true}) {
    if (keep) _keepModelSettings();
    final target = _providers.resolve(id);
    final sameProvider = _providerKeyOf(id) == _onProvider;
    // Its own effort and context, if it had them: not the one before's.
    if (_pickedWindows[id] case final window?) _window = window;
    final recalled = _pickedEfforts[id];
    if (recalled != null) _effort = recalled;
    final variant = target != null
        ? null
        : _pickedWindows[id] == null
        ? _variantOf(id)
        : _variantFor(id, long: _window! > _windows['200k']!);
    if (sameProvider && target == null) {
      final effort =
          recalled != null &&
              recalled != _appliedEffort &&
              _effortLevelsOf(id).contains(recalled)
          ? recalled
          : null;
      if (effort != null) _appliedEffort = effort;
      _change([
        ?_modelChange(variant?.value),
        if (effort != null)
          (
            'apply_flag_settings',
            {
              'settings': {'effortLevel': effort},
            },
          ),
      ]);
      return;
    }
    if (sameProvider) {
      final (provider, info) = target!;
      final effort = _effortFor(info);
      _model = id;
      _change([
        (
          'set_model',
          {
            'model': requestedModel(
              provider,
              info,
              effort: effort,
              fast: _pickedFast[id] ?? false,
            ),
          },
        ),
        if (!provider.protocolOf(info).proxied) ?_thinkingSettings(effort),
      ]);
      return;
    }
    _model = variant?.value ?? id;
    if (_running && !_busy && !_conversationStarted) {
      restart();
      return;
    }
    // Taken up with the next message (see _applyWindow).
    emitInfoChanged();
  }

  /// Notes the effort and context of the model in use, to go back to.
  void _keepModelSettings() {
    final current = model.selected;
    if (current == null) return;
    if (effort.selected case final level?) _pickedEfforts[current] = level;
    final window = switch (_custom) {
      (_, final info) => _windowFor(info),
      null => _windows[contextSize.selected],
    };
    if (window != null) _pickedWindows[current] = window;
  }

  /// [model]'s variant with the long context or without, as there is one.
  _ModelInfo? _variantFor(String model, {required bool long}) {
    final variants = _models[model];
    if (variants == null) return null;
    return variants.where((v) => v.long == long).firstOrNull ?? variants.first;
  }

  /// Each name [provider]'s models are asked for by, with each effort
  /// through the proxy.
  static List<String> _requestedModels(ModelProvider provider) => {
    for (final info in provider.enabledModels) ...[
      requestedModel(provider, info),
      if (provider.protocolOf(info).proxied)
        for (final effort in info.effortLevels)
          requestedModel(provider, info, effort: effort),
      if (provider.protocolOf(info)
          case ProviderProtocol.openaiResponses || ProviderProtocol.codex) ...[
        requestedModel(provider, info, fast: true),
        for (final effort in info.effortLevels)
          requestedModel(provider, info, effort: effort, fast: true),
      ],
    ],
  }.toList();

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
      final providers = _providers.enabled;
      return [
        // Shown unless turned off in Settings → Models; never on BaoCode's
        // own core, which runs on the upstreams alone.
        if (_providers.builtinOffered)
          if (_models.isEmpty)
            // Its models not known (it is not logged in, or no session has
            // started on it yet): picking this starts one, which lists them.
            KernelOption(
              'default',
              'Default',
              Icons.bolt_rounded,
              '',
              group: _builtinGroup,
              iconBuilder: _modelIcon(builtinProviderId, 'default'),
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
                iconBuilder: _modelIcon(builtinProviderId, id),
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
                iconBuilder: _providerIcon(provider.id),
              ),
              iconBuilder: _modelIcon(provider.id, info.id),
            ),
      ];
    },
    selected: () {
      if (_custom != null) return _model;
      // BaoCode's own core with no upstream: none to run on.
      if (!_providers.builtinAvailable) return null;
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
    selectedFor: (model) {
      if (model == this.model.selected) return contextSize.selected;
      final window = _pickedWindows[model] ?? _window;
      if (_providers.resolve(model) case (_, final info)) {
        return '${info.contextOptions.contains(window) ? window : info.initialContext}';
      }
      return _windows.entries
          .where((entry) => entry.value == window)
          .firstOrNull
          ?.key;
    },
    select: (model, id) {
      final switching = model != this.model.selected;
      if (switching) _keepModelSettings();
      if (_providers.resolve(model) != null) {
        final tokens = parseTokens(id);
        if (tokens == null || tokens <= 0) return;
        _window = _pickedWindows[model] = tokens;
        // Taken up with the next message (see _applyWindow).
        if (model != _model) {
          _selectModel(model, keep: false);
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
      _window = _pickedWindows[model] = window;
      // Claude Code's model, picked on another provider's: switched to as
      // that is (see _selectModel).
      if (_providerKeyOf(model) != _onProvider) {
        _selectModel(model, keep: false);
        return;
      }
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
      'No checks: edits and commands run without asking',
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
  String get _mode => _work == 'plan' ? 'plan' : _cliApproval;

  /// The CLI's mode for the approvals picked. Full access is not the
  /// CLI's bypassPermissions, which it refuses as root and cannot switch
  /// to unless started allowing it: it accepts edits, and what it asks
  /// about otherwise is approved in [_permission].
  String get _cliApproval =>
      _approval == 'bypassPermissions' ? 'acceptEdits' : _approval;

  /// What the CLI would still ask in full access: safety checks requiring
  /// manual approval (also inside compound commands), explicit ask rules,
  /// and tools that require user interaction. Protected-path checks that
  /// the classifier may approve do not require a prompt in full access.
  static bool _askedInFullAccess(Map<String, Object?> request) =>
      request['classifier_approvable'] == false ||
      (request['decision_reason_type'] == 'safetyCheck' &&
          request['classifier_approvable'] != true) ||
      request['matched_ask_rule'] != null ||
      request['requires_user_interaction'] == true ||
      request['decision_reason_code'] != null;

  /// Plan's commands are left to the classifier with the approvals that
  /// approve for the user; asked about with the others.
  bool get _reviewsPlan =>
      _approval == 'auto' || _approval == 'bypassPermissions';

  /// Whether the auto mode classifier runs on the model: not on another
  /// provider's.
  bool get _classifies =>
      _custom == null && (_currentModel?.supportsAuto ?? true);

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
        if (option.id != 'auto' || _classifies) option,
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
    selectedFor: (model) {
      if (model == this.model.selected) return effort.selected;
      final level = _pickedEfforts[model] ?? _effort;
      if (_providers.resolve(model) case (_, final info)) {
        return info.effortLevels.contains(level) ? level : info.initialEffort;
      }
      return _effortLevelsOf(model).contains(level) ? level : null;
    },
    select: (model, id) {
      if (model != this.model.selected) _keepModelSettings();
      _pickedEfforts[model] = id;
      if (_providers.resolve(model) case (final provider, final info)) {
        _effort = _appliedEffort = id;
        if (model != _model || _providerKeyOf(model) != _launchedProvider) {
          _selectModel(model, keep: false);
          return;
        }
        // Through the proxy, the effort goes with the model's name;
        // to Anthropic's API, as Claude Code's own setting.
        _change([
          if (provider.protocolOf(info).proxied)
            (
              'set_model',
              {
                'model': requestedModel(
                  provider,
                  info,
                  effort: id,
                  fast: _pickedFast[model] ?? false,
                ),
              },
            )
          else
            ?_thinkingSettings(id),
        ]);
        return;
      }
      // Claude Code's model, picked on another provider's: switched to as
      // that is (see _selectModel).
      if (_providerKeyOf(model) != _onProvider) {
        _effort = _appliedEffort = id;
        _selectModel(model, keep: false);
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
  late final ModelSetting fast = _ModelSetting(
    toggle: true,
    optionsFor: (model) => switch (_providers.resolve(model)) {
      (final provider, final info)
          when provider.protocolOf(info) == ProviderProtocol.openaiResponses ||
              provider.protocolOf(info) == ProviderProtocol.codex =>
        const [KernelOption('fast', 'Fast', Icons.bolt_rounded, '')],
      _ => const [],
    },
    selected: () => _pickedFast[_model] == true ? 'fast' : 'standard',
    selectedFor: (model) => _pickedFast[model] == true ? 'fast' : 'standard',
    select: (model, id) {
      if (id != 'fast' || fast.optionsFor(model).isEmpty) return;
      if (model != this.model.selected) _keepModelSettings();
      _pickedFast[model] = _pickedFast[model] != true;
      if (_providers.resolve(model) case (final provider, final info)) {
        if (model != _model || _providerKeyOf(model) != _launchedProvider) {
          _selectModel(model, keep: false);
        } else {
          _change([
            (
              'set_model',
              {
                'model': requestedModel(
                  provider,
                  info,
                  effort: _effortFor(info),
                  fast: _pickedFast[model]!,
                ),
              },
            ),
          ]);
        }
      }
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
  const _Permission(
    this.input,
    this.suggestions,
    this.questions, {
    this.elicitation,
  });

  /// For an MCP server's elicitation: its form's fields, or the link it
  /// asks to open.
  final ({List<ElicitationField> fields, String? url})? elicitation;

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
    required this._selectedFor,
    required this._select,
    this.toggle = false,
  });

  final List<KernelOption> Function(String model) _optionsFor;
  final String? Function() _selected;
  final String? Function(String model) _selectedFor;
  final void Function(String model, String id) _select;

  @override
  final bool toggle;

  @override
  List<KernelOption> optionsFor(String model) => _optionsFor(model);

  @override
  String? get selected => _selected();

  @override
  String? selectedFor(String model) => _selectedFor(model);

  @override
  void select(String model, String id) => _select(model, id);
}
