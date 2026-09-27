import 'package:flutter/foundation.dart';

import '../chat/chat_models.dart';
import '../chat/chat_session.dart';
import '../chat/mock_conversation.dart';
import 'editor_launcher.dart';

/// A repository agents work in.
class Project {
  const Project(this.name, this.path);

  final String name;
  final String path;
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

/// One agent conversation in the sidebar.
class AgentThread {
  AgentThread._({
    required this.project,
    required this.session,
    required this.updatedAt,
    this._title = '',
    this.pinned = false,
    this.unread = false,
  });

  final Project project;
  final ChatSession session;

  /// Empty until the first message names it (or the user does).
  String _title;
  String get title => _title.isEmpty ? 'New Agent' : _title;

  /// Last time it started, stopped, or asked something.
  DateTime updatedAt;
  bool pinned;
  bool archived = false;
  bool unread;

  ThreadStatus get status {
    if (session.pendingQuestion != null) return ThreadStatus.needsInput;
    if (session.isStreaming) return ThreadStatus.running;
    if (unread) return ThreadStatus.unread;
    return ThreadStatus.idle;
  }

  /// Lines added and removed by its pending file changes, if any.
  ({int added, int removed})? get diff {
    final changes = session.fileChanges;
    if (changes.isEmpty) return null;
    return (
      added: changes.fold(0, (sum, change) => sum + change.added),
      removed: changes.fold(0, (sum, change) => sum + change.removed),
    );
  }

  /// What the sidebar shows of it, to tell when that changed.
  _Snapshot get _snapshot => (status: status, title: title, diff: diff);
}

typedef _Snapshot = ({
  ThreadStatus status,
  String title,
  ({int added, int removed})? diff,
});

/// Projects and their agents (in memory only). Any number of agents may
/// run at once; the sidebar shows which need attention.
class Workspace extends ChangeNotifier {
  Workspace({required this.projects});

  /// Sample projects and agents at various ages and states.
  factory Workspace.mock() {
    const monad = Project('monad', '~/code/monad');
    const docs = Project('cursor-docs', '~/code/cursor-docs');
    const gateway = Project('api-gateway', '~/work/api-gateway');
    final workspace = Workspace(projects: const [monad, docs, gateway]);
    final now = DateTime.now();
    void add(
      Project project,
      String title,
      Duration age, {
      int history = 16,
      bool pinned = false,
      bool unread = false,
      List<FileChange> changes = const [],
    }) {
      final session = ChatSession(historyCount: history)
        ..fileChanges.addAll(changes);
      workspace._add(
        AgentThread._(
          project: project,
          session: session,
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
    );
    add(docs, 'Broken anchors in API reference', const Duration(days: 2));
    add(docs, 'Translate rules guide to Chinese', const Duration(days: 12));
    add(gateway, 'Rate limit per API key', const Duration(minutes: 55));
    add(
      gateway,
      'Migrate auth middleware to JWT',
      const Duration(days: 1, hours: 6),
    );
    add(gateway, 'Flaky integration test on CI', const Duration(days: 9));
    workspace._selected = workspace.threads.first;
    return workspace;
  }

  final List<Project> projects;

  List<AgentThread> get threads => List.unmodifiable(_threads);
  final List<AgentThread> _threads = [];

  AgentThread get selected => _selected!;
  AgentThread? _selected;

  /// Where "Open" in the title bar opens a project.
  Editor get preferredEditor => _preferredEditor;
  Editor _preferredEditor = Editor.vscode;
  set preferredEditor(Editor editor) {
    if (editor == _preferredEditor) return;
    _preferredEditor = editor;
    notifyListeners();
  }

  final Map<AgentThread, VoidCallback> _listeners = {};
  final Map<AgentThread, _Snapshot> _snapshots = {};

  /// Starts a couple of background agents, to show running and waiting
  /// states in the sidebar.
  void startDemoRuns() {
    for (final thread in _threads.skip(1).take(2)) {
      thread.session.send(
        const ComposerMessage(text: '把输入框改成随内容自动增高，并支持 @ 提及和 / 命令'),
      );
    }
  }

  void _add(AgentThread thread) {
    _threads.add(thread);
    _snapshots[thread] = thread._snapshot;
    void listener() => _sync(thread);
    _listeners[thread] = listener;
    thread.session.addListener(listener);
  }

  /// Keeps the sidebar current as the agent works: names a new agent after
  /// its first message, flags one that finished out of view, and notifies
  /// only when something shown changed (not on every streamed character).
  void _sync(AgentThread thread) {
    final session = thread.session;
    if (thread._title.isEmpty && session.itemCount > 0) {
      if (session.itemAt(0) case UserMessageItem(:final text)) {
        thread._title = text.trim().split('\n').first;
      }
    }
    final before = _snapshots[thread];
    if (before?.status == ThreadStatus.running &&
        !session.isStreaming &&
        session.pendingQuestion == null &&
        !identical(thread, _selected)) {
      thread.unread = true;
    }
    final snapshot = thread._snapshot;
    if (snapshot == before) return;
    if (before != null && before.status != snapshot.status) {
      thread.updatedAt = DateTime.now();
    }
    _snapshots[thread] = snapshot;
    notifyListeners();
  }

  void select(AgentThread thread) {
    thread.unread = false;
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
    project ??= _selected?.project ?? projects.first;
    for (final thread in _threads) {
      if (thread.project == project &&
          thread._title.isEmpty &&
          thread.session.itemCount == 0 &&
          !thread.archived) {
        select(thread);
        return thread;
      }
    }
    final thread = AgentThread._(
      project: project,
      session: ChatSession(historyCount: 0),
      updatedAt: DateTime.now(),
    );
    _add(thread);
    select(thread);
    return thread;
  }

  void rename(AgentThread thread, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == thread._title) return;
    thread._title = trimmed;
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

  void delete(AgentThread thread) {
    final listener = _listeners.remove(thread);
    if (listener != null) thread.session.removeListener(listener);
    _snapshots.remove(thread);
    _threads.remove(thread);
    if (identical(thread, _selected)) _selectNext(thread);
    // Stop its run and background task so nothing reports to a disposed
    // session.
    thread.session
      ..stop()
      ..tasks.clear()
      ..dispose();
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
      _selected = candidates.first..unread = false;
    }
  }

  @override
  void dispose() {
    for (final MapEntry(key: thread, value: listener) in _listeners.entries) {
      thread.session
        ..removeListener(listener)
        ..stop()
        ..tasks.clear()
        ..dispose();
    }
    super.dispose();
  }
}
