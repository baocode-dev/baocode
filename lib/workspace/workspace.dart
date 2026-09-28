import 'dart:async';

import 'package:flutter/foundation.dart';

import '../chat/chat_models.dart';
import '../chat/chat_session.dart';
import '../chat/mock_conversation.dart';
import '../kernel/agent_kernel.dart';
import '../kernel/kernel_registry.dart';
import 'package:path/path.dart' as p;

import '../kernel/kernel_types.dart';
import 'editor_launcher.dart';
import 'preference_store.dart';

/// A directory agents work in.
class Project {
  const Project(this.name, this.path);

  factory Project.at(String path) {
    // The folder's own name, on either separator (Windows paths come with
    // backslashes).
    final name = p.basename(path);
    return Project(name.isEmpty ? path : name, path);
  }

  final String name;
  final String path;

  @override
  bool operator ==(Object other) => other is Project && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// What an agent needs from the user, most urgent first.
enum ThreadStatus {
  /// Stopped on a question only the user can answer.
  needsInput,
  running,

  /// Finished while the user was looking at another agent.
  unread,
  idle,
}

/// One agent conversation in the sidebar. A kept session's conversation
/// is only read, and its kernel only started, once it is opened.
class AgentThread {
  AgentThread._({
    required this.project,
    required this._kernel,
    required this._open,
    required this.updatedAt,
    this.record,
    this._title = '',
    this.pinned = false,
    bool unread = false,
  }) : _seenSeq = unread ? -1 : 0;

  final Project project;

  /// The kept session it continues, if any.
  final SessionRecord? record;

  final KernelDescriptor _kernel;
  final ChatSession Function() _open;
  ChatSession? _session;
  void Function(AgentThread thread)? _onOpened;

  /// The conversation, opened (and its history read) on first use.
  ChatSession get session {
    final session = _session;
    if (session != null) return session;
    final opened = _session = _open();
    _onOpened?.call(this);
    return opened;
  }

  bool get isOpen => _session != null;

  /// Empty until the first message names it (or the user does).
  String _title;
  String get title => _title.isEmpty ? 'New Agent' : _title;

  /// Last time it started, stopped, or asked something.
  DateTime updatedAt;
  bool pinned;
  bool archived = false;

  /// The last turn end the user has seen (see [ChatSession.lastTurnEndSeq]).
  int _seenSeq;

  /// A turn ended since the user last looked.
  bool get unread => (_session?.lastTurnEndSeq ?? 0) > _seenSeq;

  void _markSeen() => _seenSeq = _session?.lastTurnEndSeq ?? 0;

  KernelDescriptor get kernel => _session?.kernel ?? _kernel;

  ThreadStatus get status {
    final session = _session;
    if (session?.pendingInteraction != null) return ThreadStatus.needsInput;
    if (session?.isStreaming ?? false) return ThreadStatus.running;
    if (unread) return ThreadStatus.unread;
    return ThreadStatus.idle;
  }

  /// Lines added and removed by its pending file changes, if any.
  ({int added, int removed})? get diff {
    final changes = _session?.fileChanges ?? const [];
    if (changes.isEmpty) return null;
    return (
      added: changes.fold(0, (sum, change) => sum + change.added),
      removed: changes.fold(0, (sum, change) => sum + change.removed),
    );
  }

  /// What the sidebar shows of it, to tell when that changed.
  _Snapshot get _snapshot => (
    status: status,
    title: title,
    diff: diff,
    kernel: kernel.id,
    mode: _session?.selected(KernelChoiceKind.mode),
    permission: _session?.selected(KernelChoiceKind.permission),
    model: _session?.selected(KernelChoiceKind.model),
    effort: _session?.selected(KernelChoiceKind.effort),
    context: _session?.selected(KernelChoiceKind.context),
  );
}

typedef _Snapshot = ({
  ThreadStatus status,
  String title,
  ({int added, int removed})? diff,
  String kernel,
  String? mode,
  String? permission,
  String? model,
  String? effort,
  String? context,
});

/// Projects and their agents. Any number of agents may run at once; the
/// sidebar shows which need attention.
///
/// The projects and past sessions are the ones the kernels keep
/// ([SessionCatalog]), plus folders opened this run. Only what the user
/// picks is kept here, in [preferences]: the kernel, mode, model and so
/// on new agents start with, and those of each agent.
class Workspace extends ChangeNotifier {
  Workspace({
    List<Project> projects = const [],
    List<KernelDescriptor>? kernels,
    PreferenceStore? preferences,
  }) : _projects = [...projects],
       kernels = kernels ?? KernelRegistry.all,
       _preferredKernel = (kernels ?? KernelRegistry.all).first,
       _store = preferences;

  /// The kernels new agents may run on.
  final List<KernelDescriptor> kernels;

  List<Project> get projects => List.unmodifiable(_projects);
  final List<Project> _projects;

  List<AgentThread> get threads => List.unmodifiable(_threads);
  final List<AgentThread> _threads = [];

  /// The open agent; null only while there is no project yet.
  AgentThread? get current => _selected;
  AgentThread get selected => _selected!;
  AgentThread? _selected;

  bool _loading = false;
  bool get loading => _loading;

  // --- Loading -------------------------------------------------------------

  /// Lists the projects and sessions the kernels keep, then opens a new
  /// agent in the most recent project.
  Future<void> load() async {
    _loading = true;
    notifyListeners();
    await _restore();
    for (final kernel in kernels) {
      final catalog = kernel.catalog;
      if (catalog == null) continue;
      List<ProjectRecord> records;
      try {
        records = await catalog.projects();
      } on Object {
        records = const [];
      }
      for (final record in records) {
        final project = _project(record.path);
        for (final session in record.sessions) {
          _addKept(kernel, project, session);
        }
      }
    }
    _loading = false;
    if (_selected == null && _projects.isNotEmpty) {
      create(project: _projects.first);
    } else {
      notifyListeners();
    }
  }

  Future<void>? _refreshing;

  /// Picks up sessions the kernels kept since [load] (e.g. ones started in
  /// a terminal). What is listed stays as it is.
  Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    if (_loading) return;
    final before = _threads.length;
    for (final kernel in kernels) {
      final List<ProjectRecord> records;
      try {
        records = await kernel.catalog?.projects() ?? const [];
      } on Object {
        continue;
      }
      for (final record in records) {
        final known = _projects.any((project) => project.path == record.path);
        final project = _project(record.path);
        if (!known) {
          // Newest first, like the kept projects.
          _projects
            ..remove(project)
            ..insert(0, project);
        }
        for (final session in record.sessions) {
          _addKept(kernel, project, session);
        }
      }
    }
    if (_threads.length != before) notifyListeners();
  }

  /// Opens [path] as a project (if not yet) and a new agent in it.
  Future<AgentThread> openFolder(String path) async {
    final known = _projects.any((project) => project.path == path);
    final project = _project(path);
    if (!known) {
      for (final kernel in kernels) {
        final sessions = await kernel.catalog?.sessionsIn(path);
        for (final session in sessions ?? const <SessionRecord>[]) {
          _addKept(kernel, project, session);
        }
      }
      // Newest first, like the kept projects.
      _projects
        ..remove(project)
        ..insert(0, project);
    }
    return create(project: project);
  }

  Project _project(String path) {
    for (final project in _projects) {
      if (project.path == path) return project;
    }
    final project = Project.at(path);
    _projects.add(project);
    return project;
  }

  void _addKept(
    KernelDescriptor kernel,
    Project project,
    SessionRecord session,
  ) {
    if (_removed.contains(session.id)) return;
    // Listed already, or it is an agent of this run.
    if (_threads.any(
      (thread) =>
          thread.record?.id == session.id ||
          (thread.isOpen && thread.session.sessionId == session.id),
    )) {
      return;
    }
    _add(
      AgentThread._(
        project: project,
        kernel: kernel,
        record: session,
        title: session.title,
        updatedAt: session.updatedAt,
        open: () => ChatSession(
          kernel: kernel,
          kernels: kernels,
          kernelContext: KernelContext(
            cwd: session.cwd,
            resume: session,
            // As it was left, or as a new agent starts.
            settings: {..._preferredSettings, ...?_agentSettings[session.id]},
          ),
          historyCount: 0,
        ),
      ),
    );
  }

  // --- Mock ------------------------------------------------------------------

  /// Sample projects and agents at various ages and states, on the
  /// registered kernels (mock ones under test).
  factory Workspace.mock() {
    const monad = Project('monad', '~/code/monad');
    const docs = Project('cursor-docs', '~/code/cursor-docs');
    const gateway = Project('api-gateway', '~/work/api-gateway');
    final workspace = Workspace(projects: const [monad, docs, gateway]);
    final claude = workspace.kernels.first;
    final codex = workspace.kernels.lastOrNull ?? claude;
    final now = DateTime.now();
    void add(
      Project project,
      String title,
      Duration age, {
      int history = 16,
      bool pinned = false,
      bool unread = false,
      List<FileChange> changes = const [],
      KernelDescriptor? kernel,
    }) {
      final descriptor = kernel ?? claude;
      final isCodex = descriptor == codex && codex != claude;
      final session = ChatSession(
        kernel: descriptor,
        kernels: workspace.kernels,
        kernelContext: KernelContext(cwd: project.path),
        historyCount: history,
        changes: changes,
        usage: isCodex
            ? const ContextUsage(window: 272000, used: 52400)
            : history > 0
            ? MockConversation.usage
            : null,
      );
      workspace._add(
        AgentThread._(
          project: project,
          kernel: descriptor,
          open: () => session,
          title: title,
          updatedAt: now.subtract(age),
          pinned: pinned,
          unread: unread,
        ),
      );
    }

    add(
      monad,
      'Optimize virtual list scrolling',
      const Duration(minutes: 2),
      history: MockConversation.itemCount,
    );
    add(
      monad,
      'Sticky user message on scroll',
      const Duration(minutes: 38),
      unread: true,
      changes: const [
        FileChange(
          path: 'lib/chat/chat_history_view.dart',
          added: 186,
          removed: 4,
        ),
        FileChange(path: 'test/composer_test.dart', added: 64, removed: 9),
      ],
    );
    add(
      monad,
      'Fix selection jitter in streaming thoughts',
      const Duration(hours: 3),
      history: 24,
    );
    add(
      monad,
      'Floating layer for composer popovers',
      const Duration(days: 1, hours: 2),
      pinned: true,
    );
    add(monad, 'Edit sent messages in history', const Duration(days: 4));
    add(
      docs,
      'Rewrite the agents quickstart',
      const Duration(hours: 1),
      changes: const [
        FileChange(path: 'docs/agents/quickstart.mdx', added: 42, removed: 7),
      ],
      kernel: codex,
    );
    add(
      docs,
      'Broken anchors in API reference',
      const Duration(days: 2),
      kernel: codex,
    );
    add(
      docs,
      'Translate rules guide to Chinese',
      const Duration(days: 12),
      kernel: codex,
    );
    add(gateway, 'Rate limit per API key', const Duration(minutes: 55));
    add(
      gateway,
      'Migrate auth middleware to JWT',
      const Duration(days: 1, hours: 6),
      kernel: codex,
    );
    add(gateway, 'Flaky integration test on CI', const Duration(days: 9));
    workspace._selected = workspace.threads.first;
    return workspace;
  }

  /// Starts a few background agents, on each kernel, to show running and
  /// waiting states in the sidebar.
  void startDemoRuns() {
    final others = _threads.where((thread) => thread.kernel != kernels.first);
    for (final thread in [..._threads.skip(1).take(2), ...others.take(1)]) {
      thread.session.send(
        const ComposerMessage(text: '把输入框改成随内容自动增高，并支持 @ 提及和 / 命令'),
      );
    }
  }

  // --- Preferences ------------------------------------------------------------

  /// Where "Open" in the title bar opens a project.
  Editor get preferredEditor => _preferredEditor;
  Editor _preferredEditor = Editor.vscode;
  set preferredEditor(Editor editor) {
    if (editor == _preferredEditor) return;
    _preferredEditor = editor;
    _save();
    notifyListeners();
  }

  /// The kernel a new agent starts with: the last one picked.
  KernelDescriptor get preferredKernel => _preferredKernel;
  KernelDescriptor _preferredKernel;

  /// The mode, model, context and effort a new agent starts with: the
  /// last ones picked.
  Map<String, String> get _preferredSettings => Map.unmodifiable(_settings);
  final Map<String, String> _settings = {};

  /// Each agent's choices, by session: those it opens with again.
  final Map<String, Map<String, String>> _agentSettings = {};

  /// Agents' choices kept, the most recent ones.
  static const _keptAgents = 500;

  final PreferenceStore? _store;

  Future<void> _restore() async {
    final store = _store;
    if (store == null) return;
    final kept = await store.read();
    Map<String, String> strings(Object? raw) => {
      if (raw is Map)
        for (final MapEntry(:key, :value) in raw.entries)
          if ((key, value) case (final String key, final String value))
            key: value,
    };
    if (kernels.where((k) => k.id == kept['kernel']).firstOrNull
        case final kernel?) {
      _preferredKernel = kernel;
    }
    if (Editor.availableEditors
        .where((e) => e.name == kept['editor'])
        .firstOrNull
        case final editor?) {
      _preferredEditor = editor;
    }
    _settings.addAll(strings(kept['settings']));
    if (kept['agents'] case final Map<Object?, Object?> agents) {
      for (final MapEntry(:key, :value) in agents.entries) {
        if (key is String) _agentSettings[key] = strings(value);
      }
    }
  }

  void _save() => unawaited(
    _store?.write({
      'kernel': _preferredKernel.id,
      'editor': _preferredEditor.name,
      'settings': _settings,
      'agents': _agentSettings,
    }),
  );

  /// Keeps [thread]'s choices for when it is opened again, e.g. after a
  /// restart. True if they changed.
  bool _keepChoices(AgentThread thread, _Snapshot snapshot) {
    final id = thread.isOpen ? thread.session.sessionId : thread.record?.id;
    if (id == null) return false;
    final choices = {
      for (final (kind, value) in [
        (KernelChoiceKind.mode, snapshot.mode),
        (KernelChoiceKind.permission, snapshot.permission),
        (KernelChoiceKind.model, snapshot.model),
        (KernelChoiceKind.effort, snapshot.effort),
        (KernelChoiceKind.context, snapshot.context),
      ])
        kind.name: ?value,
    };
    if (choices.isEmpty || mapEquals(choices, _agentSettings[id])) {
      return false;
    }
    // The most recent last, the oldest dropped.
    _agentSettings
      ..remove(id)
      ..[id] = choices;
    while (_agentSettings.length > _keptAgents) {
      _agentSettings.remove(_agentSettings.keys.first);
    }
    return true;
  }

  // --- Threads -------------------------------------------------------------------

  /// Sessions taken off the list this run: a refresh does not bring them
  /// back.
  final Set<String> _removed = {};

  final Map<AgentThread, VoidCallback> _listeners = {};
  final Map<AgentThread, _Snapshot> _snapshots = {};

  void _add(AgentThread thread) {
    _threads.add(thread);
    thread._onOpened = _listen;
    if (thread.isOpen) _listen(thread);
    _snapshots[thread] = thread._snapshot;
  }

  void _listen(AgentThread thread) {
    if (_listeners.containsKey(thread)) return;
    void listener() => _sync(thread);
    _listeners[thread] = listener;
    thread.session.addListener(listener);
  }

  /// Keeps the sidebar current as the agent works: names a new agent after
  /// its first message, notes what was seen, and notifies only when
  /// something shown changed (not on every streamed character).
  void _sync(AgentThread thread) {
    final session = thread.session;
    if (thread._title.isEmpty && session.itemCount > 0) {
      if (session.itemAt(0) case UserMessageItem(:final text)) {
        thread._title = text.trim().split('\n').first;
      }
    }
    // What ends in view is seen.
    if (identical(thread, _selected)) thread._markSeen();
    final before = _snapshots[thread];
    final snapshot = thread._snapshot;
    if (snapshot == before) return;
    var changed = _keepChoices(thread, snapshot);
    if (before != null) {
      // Picked for this agent: the next new one starts with it too.
      if (before.kernel != snapshot.kernel) {
        _preferredKernel = thread.kernel;
        changed = true;
      }
      void remember(KernelChoiceKind kind, String? was, String? now) {
        if (now != null && was != null && now != was) {
          _settings[kind.name] = now;
          changed = true;
        }
      }

      remember(KernelChoiceKind.mode, before.mode, snapshot.mode);
      remember(
        KernelChoiceKind.permission,
        before.permission,
        snapshot.permission,
      );
      remember(KernelChoiceKind.model, before.model, snapshot.model);
      remember(KernelChoiceKind.effort, before.effort, snapshot.effort);
      remember(KernelChoiceKind.context, before.context, snapshot.context);
      if (before.status != snapshot.status) thread.updatedAt = DateTime.now();
    }
    if (changed) _save();
    _snapshots[thread] = snapshot;
    notifyListeners();
  }

  void select(AgentThread thread) {
    thread._markSeen();
    _snapshots[thread] = thread._snapshot;
    if (identical(thread, _selected)) {
      notifyListeners();
      return;
    }
    _selected = thread;
    notifyListeners();
  }

  /// Opens a new, empty agent in [project] (by default the current one's).
  /// An untouched new agent there is reused rather than piling up.
  AgentThread create({Project? project}) {
    project ??= _selected?.project ?? _projects.firstOrNull;
    if (project == null) {
      throw StateError('No project to create an agent in');
    }
    for (final thread in _threads) {
      if (thread.project == project &&
          thread.record == null &&
          thread._title.isEmpty &&
          thread.isOpen &&
          thread.session.itemCount == 0 &&
          !thread.archived) {
        select(thread);
        return thread;
      }
    }
    final kernel = _preferredKernel;
    final settings = _preferredSettings;
    final cwd = project.path;
    final thread = AgentThread._(
      project: project,
      kernel: kernel,
      updatedAt: DateTime.now(),
      open: () => ChatSession(
        kernel: kernel,
        kernels: kernels,
        kernelContext: KernelContext(cwd: cwd, settings: settings),
        historyCount: 0,
      ),
    );
    _add(thread);
    _listen(thread); // Opens it.
    select(thread);
    return thread;
  }

  void rename(AgentThread thread, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == thread._title) return;
    thread._title = trimmed;
    if (thread.isOpen) thread.session.rename(trimmed);
    _snapshots[thread] = thread._snapshot;
    notifyListeners();
  }

  void setPinned(AgentThread thread, bool pinned) {
    thread.pinned = pinned;
    notifyListeners();
  }

  void setArchived(AgentThread thread, bool archived) {
    thread.archived = archived;
    if (archived) thread.pinned = false;
    if (archived && identical(thread, _selected)) _selectNext(thread);
    notifyListeners();
  }

  /// Deletes [thread]: stops its agent, and once it has stopped, deletes
  /// the session its kernel kept (deleting it again does nothing).
  void delete(AgentThread thread) {
    final id =
        thread.record?.id ?? (thread.isOpen ? thread.session.sessionId : null);
    if (id != null) _removed.add(id);
    final catalog = thread.kernel.catalog;
    final listener = _listeners.remove(thread);
    if (listener != null) thread.session.removeListener(listener);
    _snapshots.remove(thread);
    _threads.remove(thread);
    if (identical(thread, _selected)) _selectNext(thread);
    var stopped = Future<void>.value();
    if (thread.isOpen) {
      thread.session
        ..stop()
        ..dispose();
      stopped = thread.session.stopped;
    }
    if ((catalog, id) case (final catalog?, final id?)) {
      unawaited(stopped.then((_) => catalog.delete(id)).catchError((_) {}));
    }
    notifyListeners();
  }

  /// After [gone] is archived or deleted: the most recent remaining agent,
  /// or a new one.
  void _selectNext(AgentThread gone) {
    final candidates = [
      for (final thread in _threads)
        if (!thread.archived && !identical(thread, gone)) thread,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (candidates.isEmpty) {
      _selected = null;
      create(project: gone.project);
    } else {
      _selected = candidates.first.._markSeen();
    }
  }

  @override
  void dispose() {
    for (final MapEntry(key: thread, value: listener) in _listeners.entries) {
      thread.session
        ..removeListener(listener)
        ..stop()
        ..dispose();
    }
    super.dispose();
  }
}
