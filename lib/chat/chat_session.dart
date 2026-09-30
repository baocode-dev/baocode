import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../kernel/agent_kernel.dart';
import '../kernel/kernel_event.dart';
import '../kernel/kernel_registry.dart';
import '../kernel/kernel_types.dart';
import '../kernel/transcript.dart';
import 'chat_feed.dart';
import 'chat_models.dart';
import 'composer/composer_draft.dart';
import 'mock_conversation.dart';

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
/// It keeps only three things:
/// - the [Transcript], the kernel's conversation as reported;
/// - which kernel runs it, and where ([KernelContext]);
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
  }) : kernels = kernels ?? KernelRegistry.all {
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

  void _connect(KernelDescriptor descriptor) {
    _kernel = descriptor.create(kernelContext);
    _subscription = _kernel.events.listen(_apply);
  }

  void _apply(KernelEvent event) {
    if (event is KernelInfoChanged || _transcript.apply(event)) {
      _cache.clear();
      _timeQuiet();
      notifyListeners();
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

  // --- Projections ------------------------------------------------------------

  @override
  bool get isStreaming => _transcript.activeTurn != null;

  /// Whether the composer may send now.
  bool get canSend => !isStreaming || canQueue;

  InteractionRequest? get pendingInteraction => _transcript.pendingInteraction;

  /// Sequence of the last turn to end, to tell whether it was seen.
  int get lastTurnEndSeq => _transcript.lastTurnEndSeq;

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

  /// Files changed and neither kept nor reverted, one entry per file.
  List<FileChange> get fileChanges => _cached(#fileChanges, () {
    final byPath = <String, FileChange>{};
    for (final (seq: _, :change, turnId: _) in _pendingEdits) {
      final before = byPath[change.path];
      byPath[change.path] = before == null
          ? change
          : FileChange(
              path: change.path,
              added: before.added + change.added,
              removed: before.removed + change.removed,
            );
    }
    return byPath.values.toList();
  });

  Iterable<({int seq, FileChange change, String? turnId})> get _pendingEdits {
    final settled = math.max(_keptSeq, _transcript.revertedSeq);
    return _transcript.edits.where((edit) => edit.seq > settled);
  }

  void keepAllChanges() {
    _keptSeq = _transcript.lastSeq;
    _cache.clear();
    notifyListeners();
  }

  /// Puts the pending changes back; null when the kernel cannot, or does
  /// not know the turn they began in.
  VoidCallback? get undoAllChanges {
    if ((_kernel, _pendingEdits.firstOrNull?.turnId) case (
      final RevertsChanges kernel,
      final since?,
    )) {
      return () => kernel.revertChanges(sinceTurn: since);
    }
    return null;
  }

  final Map<Symbol, Object> _cache = {};
  int _cacheVersion = -1;

  T _cached<T extends Object>(Symbol key, T Function() compute) {
    if (_cacheVersion != _transcript.version) {
      _cache.clear();
      _cacheVersion = _transcript.version;
    }
    return _cache.putIfAbsent(key, compute) as T;
  }

  // --- Commands ---------------------------------------------------------------

  void send(ComposerMessage message) {
    if (message.isEmpty || !canSend) return;
    _kernel.send(
      KernelTurn(
        id: newTurnId(),
        text: message.text.trim(),
        mentions: message.mentions,
        images: acceptsImages ? message.images : const [],
      ),
    );
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
      for (var i = index; i < _transcript.length; i++) {
        if (_transcript.itemAt(i) is UserMessageItem) turns++;
      }
      kernel.rewind(
        itemId: _transcript.idAt(index) ?? '$index',
        index: index,
        turns: turns,
      );
      send(message);
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

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _quietTimer?.cancel();
    unawaited(_subscription?.cancel());
    _kernel.dispose();
    super.dispose();
  }
}
