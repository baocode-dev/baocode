import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../kernel/agent_kernel.dart';
import '../kernel/kernel_event.dart';
import '../kernel/kernel_registry.dart';
import '../kernel/kernel_types.dart';
import '../kernel/transcript.dart';
import '../remote/remote_location.dart';
import 'chat_feed.dart';
import 'chat_models.dart';
import 'composer/composer_draft.dart';
import 'mock_conversation.dart';
import 'review/change_review.dart';
import 'review/review_store.dart';

/// Opens the review of a project's changes (see [ChangeReview.open]).
typedef ChangeReviewOpener = Future<ChangeReview?> Function(
  String root, {
  String? session,
});

/// A message submitted from the composer.
class ComposerMessage {
  const ComposerMessage({
    required this.text,
    this.mentions = const [],
    this.images = const [],
  });

  final String text;
  final List<String> mentions;
  final List<ImageAttachment> images;

  bool get isEmpty => text.trim().isEmpty && mentions.isEmpty && images.isEmpty;
}

/// A choice a kernel offers (its model, its mode, the kernel itself): the
/// options, the one in effect, and how to pick another.
class KernelChoice {
  const KernelChoice({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<KernelOption> options;
  final KernelOption selected;
  final ValueChanged<KernelOption> onSelected;
}

/// A setting picked beside a model, e.g. its effort (see [ModelSetting]).
class ModelSettingChoice {
  const ModelSettingChoice({
    required this.kind,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final KernelChoiceKind kind;
  final List<KernelOption> options;

  /// What is in effect, or would stay so with the model picked; null
  /// while not known.
  final KernelOption? selected;

  /// Picks the option, and the model with it.
  final ValueChanged<KernelOption> onSelected;
}

/// One agent conversation, as the UI sees it, over an [AgentKernel].
///
/// It keeps only these things:
/// - the [Transcript], the kernel's conversation as reported;
/// - which kernel runs it, and where ([KernelContext]);
/// - the review of what it changed in the project ([ChangeReview]), where
///   there is one;
/// - UI state the kernel never hears of (changes kept, what is typed and
///   not sent).
///
/// Everything else (the status row, tasks, pending changes, the question
/// waiting, the model in effect) is projected from those or read from the
/// kernel. The UI reaches what the kernel can do through the facets here,
/// null when the kernel does not declare it.
class ChatSession extends ChangeNotifier implements ChatFeed {
  ChatSession({
    KernelDescriptor? kernel,
    List<KernelDescriptor>? kernels,
    this.kernelContext = const KernelContext(),
    int historyCount = MockConversation.itemCount,
    List<FileChange> changes = const [],
    ContextUsage? usage,
    this.quietAfterText = const Duration(seconds: 5),
    ChangeReviewOpener? openReview,
  }) : kernels = kernels ?? KernelRegistry.all,
       _openReview =
           openReview ?? (reviewSupported ? ChangeReview.open : null) {
    _transcript = Transcript(
      historyCount: historyCount,
      history: historyCount > 0 ? MockConversation.itemAt : null,
      changes: changes,
      usage: usage ?? (historyCount > 0 ? MockConversation.usage : null),
    );
    _connect(kernel ?? this.kernels.first);
  }

  /// Kernels this session may switch to before its first message.
  final List<KernelDescriptor> kernels;

  /// Where its kernel works, and the session it continues.
  final KernelContext kernelContext;

  /// How long the status row keeps hidden after the agent's text, with
  /// nothing new: the text is most often followed at once, by a tool or the
  /// turn's end, and the row would only flash.
  final Duration quietAfterText;

  /// What is typed in its composer and not sent, while another
  /// conversation shows.
  final ComposerDraft draft = ComposerDraft();

  @override
  ({int index, ComposerDraft draft})? editing;

  /// The subagents opened in its view, one in the other (their ids,
  /// outermost first): shown again when the view comes back to it.
  List<String> openAgents = const [];

  late AgentKernel _kernel;
  StreamSubscription<KernelEvent>? _subscription;
  late Transcript _transcript;

  /// Changes reported at or below this sequence were kept.
  int _keptSeq = -1;

  /// Changes kept file by file: those to a path reported at or below its
  /// sequence.
  final Map<String, int> _keptPaths = {};

  void _connect(KernelDescriptor descriptor) {
    _kernel = descriptor.create(kernelContext);
    _subscription = _kernel.events.listen(_apply);
  }

  void _apply(KernelEvent event) {
    if (event is KernelInfoChanged || _transcript.apply(event)) {
      _cache.clear();
      _timeQuiet();
      _reviewEvent(event);
      notifyListeners();
    }
  }

  // --- The review of its changes ----------------------------------------------

  final ChangeReviewOpener? _openReview;

  /// The review of the changes, while it opens; null when there is none.
  Future<ChangeReview?>? _reviewOpening;
  ChangeReview? _review;

  /// Messages wait on the snapshot before them, and go in order.
  Future<void> _sending = Future.value();

  /// Gives the edits reported a moment to settle before a look.
  Timer? _lookTimer;

  /// The review, while it holds: null before it opened, or once it failed
  /// (the changes are then those the kernel reported).
  ChangeReview? get _activeReview => switch (_review) {
    final review? when review.failure == null => review,
    _ => null,
  };

  /// Opens the review of the project, the first time; and snapshots it,
  /// so that the first message need not wait.
  void _startReview() {
    if (_reviewOpening != null) return;
    final open = _openReview;
    final root = kernelContext.cwd;
    if (open == null || root == null) return;
    _reviewOpening = open(root, session: kernelContext.resume?.id).then((
      review,
    ) {
      if (review == null) return null;
      if (_disposed) {
        review.dispose();
        return null;
      }
      _review = review
        ..session = sessionId
        ..addListener(_reviewChanged);
      unawaited(review.begin());
      notifyListeners();
      return review;
    }, onError: (Object _) => null);
  }

  void _reviewChanged() {
    if (!_disposed) notifyListeners();
  }

  void _reviewEvent(KernelEvent event) {
    final review = _review;
    if (review == null) return;
    review.session = sessionId;
    switch (event) {
      case TurnStarted():
        review.working = true;
      case TurnEnded():
        review.working = isStreaming;
        _lookTimer?.cancel();
        unawaited(review.observe());
      case FileEdited(:final change):
        review.report(change);
        _lookTimer?.cancel();
        _lookTimer = Timer(
          const Duration(milliseconds: 400),
          () => unawaited(review.observe(full: false)),
        );
      default:
    }
  }

  Timer? _quietTimer;
  bool _quiet = false;

  /// Times the quiet after the agent's text, anew on every change.
  void _timeQuiet() {
    _quietTimer?.cancel();
    _quiet = false;
    if (!isStreaming || _last is! AssistantTextItem) return;
    _quietTimer = Timer(quietAfterText, () {
      _quiet = true;
      notifyListeners();
    });
  }

  ChatItem? get _last => _transcript.length == 0
      ? null
      : _transcript.itemAt(_transcript.length - 1);

  // --- The kernel -------------------------------------------------------------

  KernelDescriptor get kernel => _kernel.descriptor;

  KernelHealth get health => _kernel.health;

  /// The id the kernel keeps this conversation under, once known.
  String? get sessionId => _kernel.sessionId;

  /// Completes once the kernel has stopped, after [dispose].
  Future<void> get stopped => _kernel.stopped;

  /// Tries the kernel again after it failed.
  void restart() => _kernel.restart();

  int _views = 0;

  /// A view shows the conversation: the kernel gets ready.
  void attach() {
    _views++;
    _kernel.prepare();
    _startReview();
  }

  /// A view no longer shows it. With none left, an idle kernel frees what
  /// it holds (a view may come right back, e.g. as the layout changes).
  void detach() {
    _views--;
    scheduleMicrotask(() {
      if (_views == 0 && !_disposed) _kernel.release();
    });
  }

  /// Once the conversation has started, its kernel stays: kernels cannot
  /// read each other's sessions.
  bool get kernelLocked =>
      _transcript.length > 0 || kernelContext.resume != null;

  late final List<KernelOption> _kernelOptions = [
    for (final descriptor in kernels) descriptor.option,
  ];

  /// Null once locked, or with nothing to choose from.
  KernelChoice? get kernelChoice {
    if (kernelLocked || kernels.length < 2) return null;
    return KernelChoice(
      options: _kernelOptions,
      selected: _kernelOptions[kernels.indexOf(kernel)],
      onSelected: (option) =>
          setKernel(kernels.firstWhere((k) => k.id == option.id)),
    );
  }

  void setKernel(KernelDescriptor descriptor) {
    if (kernelLocked || descriptor.id == kernel.id) return;
    unawaited(_subscription?.cancel());
    _kernel.dispose();
    _transcript = Transcript(
      changes: [for (final edit in _transcript.edits) edit.change],
    );
    _connect(descriptor);
    notifyListeners();
  }

  // --- Facets: what the kernel declares ------------------------------------------

  KernelChoice? get models => switch (_kernel) {
    final SelectsModel kernel => _choice(kernel.model),
    _ => null,
  };

  /// Whether picking [model] (one of [models]' options) restarts the
  /// conversation's agent on another upstream: asked first.
  bool switchRestarts(String model) => switch (_kernel) {
    final ConfirmsModelSwitch kernel => kernel.switchRestarts(model),
    _ => false,
  };

  KernelChoice? get modes => switch (_kernel) {
    final SelectsMode kernel => _choice(kernel.mode),
    _ => null,
  };

  KernelChoice? get permissions => switch (_kernel) {
    final SelectsPermission kernel => _choice(kernel.permission),
    _ => null,
  };

  /// The settings that go with [model] (one of [models]' options), in
  /// the order they are picked in: only those with a choice to make.
  List<ModelSettingChoice> modelSettings(String model) => [
    for (final (kind, setting) in _modelSettings)
      if (setting.optionsFor(model) case final options when options.isNotEmpty)
        ModelSettingChoice(
          kind: kind,
          options: options,
          selected: options.where((o) => o.id == setting.selected).firstOrNull,
          onSelected: (option) => setting.select(model, option.id),
        ),
  ];

  List<(KernelChoiceKind, ModelSetting)> get _modelSettings => [
    if (_kernel case final SelectsContextSize kernel)
      (KernelChoiceKind.context, kernel.contextSize),
    if (_kernel case final SelectsEffort kernel)
      (KernelChoiceKind.effort, kernel.effort),
  ];

  /// The choice [kind] as it stands, e.g. for a new agent to start with.
  String? selected(KernelChoiceKind kind) => switch (kind) {
    KernelChoiceKind.model => models?.selected.id,
    KernelChoiceKind.mode => modes?.selected.id,
    KernelChoiceKind.permission => permissions?.selected.id,
    KernelChoiceKind.effort || KernelChoiceKind.context =>
      _modelSettings
          .where((setting) => setting.$1 == kind)
          .firstOrNull
          ?.$2
          .selected,
  };

  KernelChoice? _choice(KernelChoiceSource source) {
    final options = source.options;
    if (options.isEmpty) return null;
    return KernelChoice(
      options: options,
      selected: options.firstWhere(
        (option) => option.id == source.selected,
        orElse: () => options.first,
      ),
      onSelected: (option) => source.select(option.id),
    );
  }

  List<KernelCommand> get commands => switch (_kernel) {
    final ProvidesCommands kernel => kernel.commands,
    _ => const [],
  };

  /// Files matching an `@` query; null when the kernel does not look.
  Future<List<FileSuggestion>> Function(String query)? get suggestFiles =>
      switch (_kernel) {
        final SuggestsFiles kernel => kernel.suggestFiles,
        _ => null,
      };

  ContextUsage? get context => switch (_kernel) {
    final ReportsContext kernel =>
      _transcript.usage ?? ContextUsage(window: kernel.contextWindow, used: 0),
    _ => null,
  };

  /// Cost and account limits; null when the kernel does not report them.
  UsageStats? get stats => switch (_kernel) {
    final ReportsUsage kernel =>
      _transcript.stats ?? UsageStats(limits: kernel.accountLimits),
    _ => null,
  };

  /// Asks for the account's limits now (see [ReportsUsage.refreshUsage]).
  void refreshUsage() {
    if (_kernel case final ReportsUsage kernel) {
      unawaited(kernel.refreshUsage());
    }
  }

  bool get acceptsImages => _kernel is AcceptsImages;

  /// What the user would likely send next: offered while the agent waits
  /// for them.
  String? get promptSuggestion => switch (_kernel) {
    final SuggestsPrompts kernel
        when !isStreaming && pendingInteraction == null =>
      kernel.promptSuggestion,
    _ => null,
  };

  /// The kernel's MCP servers; null when it has none to manage, empty
  /// until first reported.
  List<McpServer>? get mcpServers => switch (_kernel) {
    final ManagesMcpServers kernel => kernel.mcpServers ?? const [],
    _ => null,
  };

  void refreshMcpServers() {
    if (_kernel case final ManagesMcpServers kernel) kernel.refreshMcpServers();
  }

  void setMcpServerEnabled(McpServer server, bool enabled) {
    if (_kernel case final ManagesMcpServers kernel) {
      kernel.setMcpServerEnabled(server.name, enabled);
    }
  }

  void reconnectMcpServer(McpServer server) {
    if (_kernel case final ManagesMcpServers kernel) {
      kernel.reconnectMcpServer(server.name);
    }
  }

  /// Starts signing in to [server]: the page to open for the user, if any.
  Future<Uri?> authenticateMcpServer(McpServer server) async =>
      switch (_kernel) {
        final ManagesMcpServers kernel => kernel.authenticateMcpServer(
          server.name,
        ),
        _ => null,
      };

  @override
  bool get canEditMessages => _kernel is RewindsConversation;

  /// Messages can be sent while the agent works.
  bool get canQueue => _kernel is QueuesMessages;

  bool get canRename => _kernel is RenamesSession;

  /// Whether the conversation can be copied into a new one (see [fork]).
  bool get canFork => switch (_kernel) {
    final ForksConversation kernel => kernel.canFork,
    _ => false,
  };

  /// Copies the conversation into a new session titled [title] (see
  /// [ForksConversation.fork]): up to the end of the turn of the item at
  /// [index], or all of it but a turn under way; null when it could not.
  Future<SessionRecord?> fork({required String title, int? index}) async {
    if (_kernel case final ForksConversation kernel when kernel.canFork) {
      String? before;
      if (index != null) {
        // The next message sent: the turn it began, and all after, stay out.
        for (var i = index + 1; i < _transcript.length; i++) {
          if (_transcript.itemAt(i) case UserMessageItem(queued: false)) {
            before = _transcript.idAt(i);
            break;
          }
        }
      } else if (_transcript.activeTurn case final turn?
          when _transcript.indexOf(turn) != null) {
        before = turn;
      }
      return kernel.fork(before: before, title: title);
    }
    return null;
  }

  // --- Projections ------------------------------------------------------------

  @override
  bool get isStreaming => _transcript.activeTurn != null;

  /// Whether the composer may send now.
  bool get canSend => !isStreaming || canQueue;

  InteractionRequest? get pendingInteraction => _transcript.pendingInteraction;

  /// The plan the agent last wrote this run, and the sequence it was
  /// reported at: higher each time it writes it again.
  ({String path, int seq})? get plan => _transcript.plan;

  /// Sequence of the last turn to end, to tell whether it was seen.
  int get lastTurnEndSeq => _transcript.lastTurnEndSeq;

  /// Whether the last turn to end was stopped rather than done.
  bool get lastTurnInterrupted => _transcript.lastTurnInterrupted;

  /// Whether the last turn to end was one the agent took up on its own,
  /// e.g. about a background subagent's report.
  bool get lastTurnUnprompted => _transcript.lastTurnUnprompted;

  /// The history, and a status row at its end while a turn runs: the agent
  /// is live. Hidden (but there, to come and go smoothly) where something
  /// else says so, or it would only flash.
  @override
  int get itemCount => _transcript.length + (isStreaming ? 1 : 0);

  @override
  ChatItem itemAt(int index) {
    if (index < _transcript.length) return _transcript.itemAt(index);
    // Waiting on its model unless its kernel says otherwise.
    return switch (_transcript.activity?.kind) {
      KernelActivityKind.compacting => LiveStatusItem(
        'Compacting conversation',
        visible: _statusVisible,
      ),
      _ => LiveStatusItem(
        'Planning next move',
        whimsical: true,
        visible: _statusVisible,
      ),
    };
  }

  /// Not while the agent waits on the user; nor after a thought under way,
  /// which says so itself; nor after its text, unless all has been quiet
  /// for [quietAfterText].
  bool get _statusVisible {
    if (pendingInteraction != null) return false;
    return switch (_last) {
      ThinkingItem() => !_transcript.isStreamingAt(_transcript.length - 1),
      AssistantTextItem() => _quiet,
      _ => true,
    };
  }

  /// Tasks running beside the conversation, gone once they end (their
  /// outcome stays on their step); null when the kernel runs none.
  List<KernelTask>? get tasks {
    if (_kernel is! RunsBackgroundTasks) return null;
    return _cached(
      #tasks,
      () => [
        for (final task in _transcript.tasks)
          if (task.background && task.status == CommandStatus.running) task,
      ],
    );
  }

  /// Background commands, including completed ones for their output tabs.
  List<KernelTask> get terminalTasks => _cached(
    #terminalTasks,
    () => [
      for (final task in _transcript.tasks)
        if (task.background && task.kind == KernelTaskKind.command) task,
    ],
  );

  void stopTask(KernelTask task) {
    if (_kernel case final RunsBackgroundTasks kernel) kernel.stopTask(task.id);
  }

  /// Moves what the item at [index] runs (a command, a subagent) to the
  /// background, so the turn goes on; null unless the kernel reports it
  /// running in the foreground.
  @override
  VoidCallback? moveToBackgroundAt(int index) => index < _transcript.length
      ? moveToBackgroundOf(_transcript.idAt(index))
      : null;

  /// As [moveToBackgroundAt], for what the tool call [id] runs, wherever it
  /// shows (e.g. in a subagent).
  VoidCallback? moveToBackgroundOf(String? id) {
    if ((_kernel, _runningTask(id)) case (
      final RunsBackgroundTasks kernel,
      KernelTask(background: false),
    )) {
      return () => kernel.moveToBackground(id!);
    }
    return null;
  }

  /// The subagent the tool call [id] started, in the conversation itself.
  AgentItem? agentOf(String? id) {
    if (id == null) return null;
    for (var index = _transcript.length - 1; index >= 0; index--) {
      if (_transcript.itemAt(index) case final AgentItem agent
          when agent.id == id) {
        return agent;
      }
    }
    return null;
  }

  /// The command the tool call [id] ran, in the conversation itself: what a
  /// background command's task does.
  String? commandOf(String? id) {
    final index = id == null ? null : _transcript.indexOf(id);
    if (index == null) return null;
    return switch (_transcript.itemAt(index)) {
      TerminalItem(:final command) when command.isNotEmpty => command,
      _ => null,
    };
  }

  /// Stops the subagent at [index]; null unless it runs as a task.
  @override
  VoidCallback? stopAt(int index) =>
      index < _transcript.length ? stopOf(_transcript.idAt(index)) : null;

  /// Stops what the tool call [id] runs, e.g. a subagent; null unless it
  /// runs as a task the kernel can stop.
  VoidCallback? stopOf(String? id) => switch (_runningTask(id)) {
    final task? when _kernel is RunsBackgroundTasks => () => stopTask(task),
    _ => null,
  };

  KernelTask? _runningTask(String? toolUseId) => toolUseId == null
      ? null
      : _transcript.tasks
            .where(
              (task) =>
                  task.toolUseId == toolUseId &&
                  task.status == CommandStatus.running,
            )
            .firstOrNull;

  List<TodoEntry> get todos => _transcript.todos;

  /// The goal the agent works toward (`/goal`), if any: just met, it is
  /// still here, met, until [dismissGoal].
  KernelGoal? get goal => switch (_transcript.goal) {
    final goal? when !identical(goal, _dismissedGoal) => goal,
    _ => null,
  };
  KernelGoal? _dismissedGoal;

  /// Hides the [goal] there is; a new one shows again.
  void dismissGoal() {
    if (goal == null) return;
    _dismissedGoal = _transcript.goal;
    notifyListeners();
  }

  /// Sets [condition] as the goal, in place of any there is, and sets the
  /// agent to work toward it. At once: Claude Code takes up `/goal` only
  /// between turns.
  void setGoal(String condition) =>
      send(ComposerMessage(text: '/goal ${condition.trim()}'), now: true);

  /// Clears the goal there is, at once.
  void clearGoal() =>
      send(const ComposerMessage(text: '/goal clear'), now: true);

  /// The project's directory, which [fileChanges]' paths are in (on its
  /// host, for a remote one).
  String? get root =>
      _activeReview?.root ??
      switch (kernelContext.cwd) {
        final cwd? => RemoteLocation.pathOf(cwd),
        null => null,
      };

  /// Files changed and neither kept nor undone, one entry per file, with
  /// absolute paths where the project is known: as the review of the
  /// project has them, else as the kernel reported them.
  List<FileChange> get fileChanges {
    if (_activeReview case final review?) return review.changes;
    return _cached(#fileChanges, () {
      final byPath = <String, FileChange>{};
      for (final (seq: _, :change, turnId: _) in _pendingEdits) {
        final path = _absolute(change.path);
        final before = byPath[path];
        byPath[path] = FileChange(
          path: path,
          added: (before?.added ?? 0) + change.added,
          removed: (before?.removed ?? 0) + change.removed,
        );
      }
      return byPath.values.toList();
    });
  }

  /// The files the agent read or changed, absolute: where a file it names
  /// by a path gone wrong (relative to some other folder) may be.
  List<String> get filesSeen => _cached(
    #filesSeen,
    () => {
      for (var i = 0; i < _transcript.length; i++)
        if (_transcript.itemAt(i) case ToolCallItem(:final path?)
            when path.isNotEmpty)
          _absolute(path),
      for (final edit in _transcript.edits) _absolute(edit.change.path),
    }.toList(),
  );

  /// [path] absolute, on the project's host (a remote project's paths are
  /// its host's).
  String _absolute(String path) {
    final cwd = kernelContext.cwd;
    if (cwd == null) return path;
    final paths = RemoteLocation.pathsOf(cwd);
    return paths.isAbsolute(path)
        ? path
        : paths.join(RemoteLocation.pathOf(cwd), path);
  }

  Iterable<({int seq, FileChange change, String? turnId})> get _pendingEdits {
    final settled = math.max(_keptSeq, _transcript.revertedSeq);
    return _transcript.edits.where(
      (edit) =>
          edit.seq > settled &&
          edit.seq > (_keptPaths[_absolute(edit.change.path)] ?? -1),
    );
  }

  void keepAllChanges() {
    _keptSeq = _transcript.lastSeq;
    _keptPaths.clear();
    if (_activeReview case final review?) unawaited(review.keepAll());
    _cache.clear();
    notifyListeners();
  }

  /// Keeps the changes to [changes]' files: they are no longer listed.
  void keepChanges(List<FileChange> changes) {
    if (_activeReview case final review?) {
      unawaited(review.keep([for (final change in changes) change.path]));
      return;
    }
    for (final change in changes) {
      _keptPaths[change.path] = _transcript.lastSeq;
    }
    _cache.clear();
    notifyListeners();
  }

  /// Puts the pending changes back; null when there is no way to.
  VoidCallback? get undoAllChanges {
    if (_activeReview case final review?) {
      if (!review.changes.any((change) => change.tracked)) return null;
      return () => unawaited(review.undoAll());
    }
    if ((_kernel, _pendingEdits.firstOrNull?.turnId) case (
      final RevertsChanges kernel,
      final since?,
    )) {
      return () => kernel.revertChanges(sinceTurn: since);
    }
    return null;
  }

  /// Puts [changes]' files back; null when files cannot be undone one by
  /// one (no review of the project).
  ValueChanged<List<FileChange>>? get undoChanges => switch (_activeReview) {
    final review? => (changes) => unawaited(
      review.undo([for (final change in changes) change.path]),
    ),
    null => null,
  };

  /// Reads the text of [change]'s file before the agent changed it, for a
  /// diff; null when it is not known.
  Future<String> Function()? originalOf(FileChange change) =>
      _activeReview?.original(change.path);

  final Map<Symbol, Object> _cache = {};
  int _cacheVersion = -1;

  /// The number of the last image in the conversation (0 before any): a
  /// new one is numbered on from it, as Claude Code numbers what is pasted.
  /// Counts what its messages say (`[Image #3]`) too, as Claude Code does.
  int get lastImageNumber => _cached(#lastImageNumber, () {
    var last = 0;
    for (var i = 0; i < _transcript.length; i++) {
      if (_transcript.itemAt(i) case UserMessageItem(
        :final text,
        :final images,
      )) {
        for (final image in images) {
          last = math.max(last, image.number ?? 0);
        }
        for (final match in imageReferencePattern.allMatches(text)) {
          last = math.max(last, int.parse(match[1]!));
        }
      }
    }
    return last;
  });

  T _cached<T extends Object>(Symbol key, T Function() compute) {
    if (_cacheVersion != _transcript.version) {
      _cache.clear();
      _cacheVersion = _transcript.version;
    }
    return _cache.putIfAbsent(key, compute) as T;
  }

  // --- Commands ---------------------------------------------------------------

  /// Sends [message]; [now], taken up at once, the turn running stopped
  /// for it (rather than queued behind it). With a plan shown beside the
  /// chat waiting on the user, it says what should change in it instead.
  void send(ComposerMessage message, {bool now = false}) {
    if (pendingInteraction case PlanReviewRequest(planPath: _?)
        when message.text.trim().isNotEmpty) {
      answer(
        PlanAnswer(PlanDecision.keepPlanning, feedback: message.text.trim()),
      );
      return;
    }
    if (message.isEmpty || !canSend) return;
    final turn = KernelTurn(
      id: newTurnId(),
      text: message.text.trim(),
      mentions: message.mentions,
      images: acceptsImages ? message.images : const [],
      now: now,
    );
    final opening = _reviewOpening;
    if (opening == null) {
      _kernel.send(turn);
      return;
    }
    // A turn about to start, not one queued behind another: the project
    // is snapshotted first, so that what the agent does is told apart.
    final snapshot = !isStreaming;
    _sending = _sending.then((_) async {
      if (snapshot) {
        final review = await opening;
        if (review != null && !_disposed) {
          review.working = true;
          // Taken late, it would count some of the agent's work as what
          // was there: the review gives way to what the kernel reports.
          await review.begin().timeout(
            const Duration(seconds: 30),
            onTimeout: () => review.abandon('The snapshot took too long.'),
          );
        }
      }
      if (!_disposed) _kernel.send(turn);
    });
  }

  static final _random = math.Random.secure();

  /// A random UUID (v4): kernels may use it as the message's id.
  static String newTurnId() {
    String hex(int length) =>
        [for (var i = 0; i < length; i++) _random.nextInt(16).toRadixString(16)]
            .join();
    final variant = (8 + _random.nextInt(4)).toRadixString(16);
    return '${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(12)}';
  }

  /// Takes back the queued message at [index].
  @override
  void cancelQueued(int index) {
    final id = _transcript.idAt(index);
    if (id == null) return;
    if (_kernel case final QueuesMessages kernel) kernel.cancelQueued(id);
  }

  /// Resends the user message at [index] as [message]: everything after it
  /// is discarded and the turn runs again from there.
  @override
  void editMessage(int index, ComposerMessage message) {
    if (_kernel case final RewindsConversation kernel
        when !message.isEmpty && itemAt(index) is UserMessageItem) {
      stop();
      var turns = 0;
      String? lastSeen;
      for (var i = index; i < _transcript.length; i++) {
        if (_transcript.itemAt(i) case UserMessageItem(:final queued)) {
          turns++;
          if (!queued) lastSeen = _transcript.idAt(i) ?? lastSeen;
        }
      }
      // Sent once the agent has gone back: turned down, it would follow
      // all of the conversation.
      unawaited(
        kernel
            .rewind(
              itemId: _transcript.idAt(index) ?? '$index',
              index: index,
              turns: turns,
              lastSeen: lastSeen,
            )
            .then((rewound) {
              if (rewound && !_disposed) send(message);
            }),
      );
    }
  }

  void stop() => _kernel.cancel();

  void answer(InteractionAnswer answer) {
    if (pendingInteraction case final request?) {
      _kernel.answer(request.id, answer);
    }
  }

  void rename(String title) {
    if (_kernel case final RenamesSession kernel) kernel.rename(title);
  }

  /// The conversation is deleted: what its review kept goes too.
  void discardChanges() => unawaited(_review?.discard());

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _quietTimer?.cancel();
    _lookTimer?.cancel();
    _review
      ?..removeListener(_reviewChanged)
      ..dispose();
    unawaited(_subscription?.cancel());
    _kernel.dispose();
    super.dispose();
  }
}
