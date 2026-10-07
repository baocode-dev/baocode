import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show TextSelection;
import 'package:flutter_quill/quill_delta.dart';
import 'package:path/path.dart' as p;

import '../chat/chat_models.dart';
import '../chat/chat_session.dart';
import '../chat/composer/composer_draft.dart';
import '../chat/mock_conversation.dart';
import '../icons/emoji_sheet.dart';
import '../icons/icon_library.dart';
import '../icons/project_icon.dart';
import '../kernel/agent_kernel.dart';
import '../kernel/kernel_registry.dart';
import '../kernel/kernel_types.dart';
import '../l10n/l10n.dart';
import '../models/model_providers.dart';
import '../theme/workbench_theme.dart' show ColorThemeStorage;
import '../remote/remote_location.dart';
import '../remote/ssh_host.dart' show SshHostState, SshHosts;
import 'agent_title.dart';
import 'chat_grid.dart';
import 'editor_launcher.dart';
import 'preference_store.dart';

/// The arrangement of the project and its conversation in the window.
enum WorkspaceLayout { chat, ide }

/// A directory agents work in: on this machine, or on a host reached over
/// SSH ([host]), its [path] then a location (see [RemoteLocation]).
class Project {
  const Project(this.name, this.path);

  factory Project.at(String path) {
    if (RemoteLocation.isRemote(path)) {
      return Project(RemoteLocation.nameOf(path), path);
    }
    // The folder's own name, on either separator (Windows paths come with
    // backslashes).
    final name = p.basename(path);
    return Project(name.isEmpty ? path : name, path);
  }

  final String name;

  /// Where it is: its folder's path here, or its location on a remote host.
  final String path;

  /// The remote host it is on; null for this machine.
  String? get host => RemoteLocation.hostOf(path);

  /// Its folder's path on its host.
  String get root => RemoteLocation.pathOf(path);

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
    this.archived = false,
    bool unread = false,
  }) : _seenSeq = unread ? -1 : 0,
       _wantsTitle = record == null && _title.isEmpty;

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

  /// Its session's id: none for a new agent until its first message.
  String? get id => (isOpen ? session.sessionId : null) ?? record?.id;
  String? get _id => id;

  /// A new agent of this run that nothing was sent to, nor named.
  bool get untouched =>
      record == null &&
      _title.isEmpty &&
      isOpen &&
      session.itemCount == 0 &&
      !archived;

  /// Empty until the first message names it (or the user does).
  String _title;
  String get title => _title.isEmpty ? 'New Chat' : _title;

  /// [title] as shown: an untitled agent's in [l10n]'s language.
  String localizedTitle(AppLocalizations l10n) =>
      _title.isEmpty ? l10n.agentUntitled : _title;

  /// A title is still to be generated for it: a new agent's, until one is
  /// asked for or the user names it.
  bool _wantsTitle;

  /// The user named it: a title generated meanwhile is dropped.
  bool _named = false;

  /// Last time it started, stopped, or asked something.
  DateTime updatedAt;
  bool pinned;
  bool archived;

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
class Workspace extends ChangeNotifier implements ColorThemeStorage {
  Workspace({
    List<Project> projects = const [],
    List<KernelDescriptor>? kernels,
    PreferenceStore? preferences,
    PreferenceStore? drafts,
    IconLibrary? icons,
    this.titler,
    AppLocalizations Function()? l10n,
  }) : _projects = [...projects],
       icons = icons ?? IconLibrary(),
       l10n = l10n ?? (() => englishLocalizations),
       kernels = kernels ?? KernelRegistry.all,
       _preferredKernel = (kernels ?? KernelRegistry.all).first,
       _store = preferences,
       _draftStore = drafts {
    this.icons
      ..onRemoved = _forgetIconImage
      ..addListener(notifyListeners);
  }

  /// The kernels new agents may run on.
  final List<KernelDescriptor> kernels;

  /// Titles a new agent after its first message (images alone are titled
  /// after their file, see [agentImageTitle]); without it, the first
  /// message's first line stays its title.
  final AgentTitler? titler;

  /// The strings of the app's language, for the titles given here: they
  /// are kept with the session, so are in the language of when given.
  final AppLocalizations Function() l10n;

  List<Project> get projects => List.unmodifiable(_projects);
  final List<Project> _projects;

  List<AgentThread> get threads => List.unmodifiable(_threads);
  final List<AgentThread> _threads = [];

  /// The open agent, the one focused where several show; null only while
  /// there is no project yet.
  AgentThread? get current => _selected;
  AgentThread get selected => _selected!;
  AgentThread? _selected;

  /// The agents shown side by side, [current] one of them. It changes
  /// through [select], [openBeside], [openInPlaceOf] and [closePane]; only
  /// its lines are the view's to move.
  ChatGrid<AgentThread> get grid => _grid;
  final ChatGrid<AgentThread> _grid = ChatGrid();

  bool _loading = false;
  bool get loading => _loading;

  // --- Loading -------------------------------------------------------------

  /// Lists the projects and sessions the kernels keep, then opens a new
  /// agent in the most recent project.
  Future<void> load() async {
    _loading = true;
    notifyListeners();
    unawaited(icons.load());
    await (_restoring = _restore());
    var complete = true;
    final listed = <String>{};
    for (final kernel in kernels) {
      final catalog = kernel.catalog;
      if (catalog == null) continue;
      List<ProjectRecord> records;
      try {
        records = await catalog.projects();
      } on Object {
        records = const [];
        complete = false;
      }
      for (final record in records) {
        listed.add(record.path);
        final project = _project(record.path);
        for (final session in record.sessions) {
          _addKept(kernel, project, session);
        }
      }
    }
    for (final folder in _folders) {
      if (listed.contains(folder)) continue;
      final project = _project(folder);
      // A remote project's sessions are its host's: no catalog lists them
      // with this machine's, so they are asked for there (not waited for).
      if (RemoteLocation.isRemote(folder)) unawaited(_listKept(project));
    }
    // Only once all were read: what one failed to list is not gone. Nor
    // while remote projects' sessions are still to be listed (or cannot
    // be, their host away): what is kept of those must stay.
    if (complete && !_folders.any(RemoteLocation.isRemote)) {
      _forgetGone(listed);
    }
    _loading = false;
    for (final folder in {?_ideFolder, ..._windowFolders}) {
      _ensureIdeChat(folder);
    }
    _restoreChatView();
    if (_selected == null && _projects.isNotEmpty) {
      create(project: sidebarProjects.firstOrNull ?? _projects.first);
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
  Future<AgentThread> openFolder(String path) async =>
      create(project: _openProject(path));

  /// Has [thread], a new agent nothing was sent to yet, work in [path]
  /// instead: a new agent there (an untouched one reused) takes its pane,
  /// and it goes. [path] is opened as a project if it was not one.
  AgentThread moveNew(AgentThread thread, String path) {
    final project = _openProject(path);
    if (project == thread.project || !_threads.contains(thread)) {
      return thread;
    }
    // Into its pane: the focused one is what [create] shows the new in.
    if (_grid.contains(thread)) _focus(thread);
    final moved = create(project: project);
    if (_isUntouched(thread)) _discard(thread);
    return moved;
  }

  /// [path]'s project, listed first if it was not; the sessions kept there
  /// follow once read (see [_listKept]).
  Project _openProject(String path) {
    // Opened again: listed again.
    _unhide(path);
    final known = _projects.any((project) => project.path == path);
    final project = _project(path);
    if (!known) {
      // Newest first, like the kept projects.
      _projects
        ..remove(project)
        ..insert(0, project);
      // Listed again next run, if no kernel keeps a session there by then.
      if (!_folders.contains(path)) {
        _folders.add(path);
        _save();
      }
      unawaited(_listKept(project));
    }
    return project;
  }

  /// Lists the sessions the kernels keep in [project]. Not waited for: to
  /// find them, Claude Code's are all read, which may take a while.
  Future<void> _listKept(Project project) async {
    final before = _threads.length;
    for (final kernel in kernels) {
      final List<SessionRecord> sessions;
      try {
        sessions = await kernel.catalog?.sessionsIn(project.path) ?? const [];
      } on Object {
        // Its host out of reach: listed once it is reached.
        if (project.host case final host?) _listWhenReached(host, project);
        continue;
      }
      if (_disposed) return;
      for (final session in sessions) {
        _addKept(kernel, project, session);
      }
    }
    if (_threads.length != before) notifyListeners();
  }

  /// The listeners of the hosts that could not be reached to list their
  /// projects' sessions, by project.
  final Map<String, VoidCallback> _unreached = {};

  /// Lists [project]'s sessions once [host] is connected.
  void _listWhenReached(String host, Project project) {
    if (_disposed || _unreached.containsKey(project.path)) return;
    final ssh = SshHosts.instance[host];
    void listener() {
      if (ssh.state != SshHostState.connected) return;
      ssh.removeListener(listener);
      _unreached.remove(project.path);
      if (!_disposed) unawaited(_listKept(project));
    }

    _unreached[project.path] = listener;
    ssh.addListener(listener);
  }

  /// Lists [project], first, kept for the next run (see [_folders]).
  void _listProject(Project project) {
    _unhide(project.path);
    _projects
      ..remove(project)
      ..insert(0, project);
    if (!_folders.contains(project.path)) _folders.add(project.path);
    _save();
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
    final id = session.id;
    // Asked something there since it was taken off the list: back on it.
    if (_hiddenProjects[project.path] case final since?
        when session.updatedAt.isAfter(since)) {
      _unhide(project.path);
    }
    _add(
      AgentThread._(
        project: project,
        kernel: kernel,
        record: session,
        title:
            _names[id] ??
            (session.title.isEmpty ? l10n().agentImageUntitled : session.title),
        updatedAt: session.updatedAt,
        pinned: _pinned.contains(id),
        archived: _archived.contains(id),
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
    const baocode = Project('baocode', '~/code/baocode');
    const docs = Project('cursor-docs', '~/code/cursor-docs');
    const gateway = Project('api-gateway', '~/work/api-gateway');
    final workspace = Workspace(projects: const [baocode, docs, gateway]);
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
      baocode,
      'Optimize virtual list scrolling',
      const Duration(minutes: 2),
      history: MockConversation.itemCount,
    );
    add(
      baocode,
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
      baocode,
      'Fix selection jitter in streaming thoughts',
      const Duration(hours: 3),
      history: 24,
    );
    add(
      baocode,
      'Floating layer for composer popovers',
      const Duration(days: 1, hours: 2),
      pinned: true,
    );
    add(baocode, 'Edit sent messages in history', const Duration(days: 4));
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
    workspace._focus(workspace.threads.first);
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

  // --- IDE -----------------------------------------------------------------

  /// The folder the IDE shows, apart from the chat's: opening one there
  /// neither starts an agent nor lists it as a project (one is listed once
  /// an agent there is sent something). None: the IDE's empty window.
  String? get ideFolder => _ideFolder;
  String? _ideFolder;

  /// Folders and files the IDE opened, the most recent first.
  ///
  /// A project hidden from the sidebar is not a selectable recent project
  /// either. Folders that are not projects yet remain available so opening a
  /// new folder in the IDE still works as before.
  List<String> get recentFolders => List.unmodifiable([
    for (final path in _recentFolders)
      if (!_projects.any((project) => project.path == path) ||
          !_hiddenProjects.containsKey(path))
        path,
  ]);
  List<String> get recentFiles => List.unmodifiable(_recentFiles);
  final List<String> _recentFolders = [], _recentFiles = [];

  /// Recent folders and files kept, each.
  static const _keptRecent = 30;

  /// How the IDE's window was left in [folder] (its widths, parts, view
  /// and editors; see `IdeWorkbench.viewState`), for the next run.
  Map<String, Object?>? ideView(String folder) => _ideViews[folder];
  final Map<String, Map<String, Object?>> _ideViews = {};

  void keepIdeView(String folder, Map<String, Object?> state) {
    _ideViews[folder] = state;
    _save();
  }

  /// [path]'s project: the listed one, or one that is not (yet) listed.
  Project projectAt(String path) {
    for (final project in _projects) {
      if (project.path == path) return project;
    }
    for (final thread in _threads) {
      if (thread.project.path == path) return thread.project;
    }
    return Project.at(path);
  }

  /// Has the IDE show [path], with a chat of its own there.
  void openIdeFolder(String path) {
    _unhide(path);
    if (ideWindows case final route?) {
      noteIdeFolder(path);
      route(path, null);
      return;
    }
    _ideFolder = path;
    _recent(_recentFolders, path);
    _ensureIdeChat(path);
    _save();
    notifyListeners();
  }

  // --- The IDE's windows ------------------------------------------------------

  /// Where the IDE shows once it has windows of its own (see
  /// lib/window/app_windows.dart): asked for [folder]'s window (null: the
  /// one last in front, or an empty one) with [thread] its chat's tab.
  /// Unset, the IDE is this window's [layout], at [ideFolder].
  void Function(String? folder, AgentThread? thread)? ideWindows;

  /// The folders the IDE's windows show, and whether the chat's window
  /// shows: what [isShown] counts.
  Set<String> _windowFolders = const {};
  bool _chatWindowShown = true;

  void showWindows({required Iterable<String> folders, required bool chat}) {
    final shown = folders.toSet();
    final added = shown.difference(_windowFolders);
    _windowFolders = shown;
    _chatWindowShown = chat;
    added.forEach(_ensureIdeChat);
    if (_markShownSeen() || added.isNotEmpty) notifyListeners();
  }

  /// The agents shown each in a window of its own (Explorer's Open with
  /// BaoCode; see AppWindows.openAgent): what [isShown] counts too.
  Set<AgentThread> _windowAgents = const {};

  void showAgentWindows(Iterable<AgentThread> threads) {
    _windowAgents = threads.toSet();
    if (_markShownSeen()) notifyListeners();
  }

  /// A new agent in [path] (opened as a project if it was not), for a
  /// window of its own: not in the chat's panes, nor reused (each window
  /// its own agent).
  AgentThread newWindowAgent(String path) {
    final thread = _newThread(_openProject(path));
    notifyListeners();
    return thread;
  }

  /// [thread]'s window closed: a new agent nothing was sent to is dropped,
  /// unless it shows elsewhere too.
  void closeWindowAgent(AgentThread thread) {
    if (!_threads.contains(thread) || !_isUntouched(thread)) return;
    if (_grid.contains(thread)) return;
    if (_ideChats.values.any((tabs) => tabs.contains(thread))) return;
    _discard(thread);
  }

  /// [path] opened by the IDE's window of its own: among the recent, with a
  /// chat of its own there.
  void noteIdeFolder(String path) {
    _unhide(path);
    _recent(_recentFolders, path);
    _ensureIdeChat(path);
    _save();
    notifyListeners();
  }

  /// The IDE's folder and whether it showed, as a run before the IDE's
  /// windows left them in the one window: taken, for its own window to
  /// open them (the chat shows here from now on).
  ({String? folder, bool shown}) takeSingleWindowIde() {
    final taken = (folder: _ideFolder, shown: _layout == WorkspaceLayout.ide);
    if (taken.folder == null && !taken.shown) return taken;
    _ideFolder = null;
    _layout = WorkspaceLayout.chat;
    _save();
    return taken;
  }

  /// Back to the IDE's empty window.
  void closeIdeFolder() {
    if (_ideFolder == null) return;
    _ideFolder = null;
    _save();
    notifyListeners();
  }

  /// Notes [path] among the files the IDE opened.
  void addRecentFile(String path) {
    if (_recentFiles.firstOrNull == path) return;
    _recent(_recentFiles, path);
    _save();
    notifyListeners();
  }

  /// Forgets the folders and files the IDE opened.
  void clearRecent() {
    if (_recentFolders.isEmpty && _recentFiles.isEmpty) return;
    _recentFolders.clear();
    _recentFiles.clear();
    _save();
    notifyListeners();
  }

  void _recent(List<String> list, String path) {
    list
      ..remove(path)
      ..insert(0, path);
    if (list.length > _keptRecent) list.removeRange(_keptRecent, list.length);
  }

  /// Shows [thread] in the IDE: its folder, with it the chat there.
  void openInIde(AgentThread thread) {
    final folder = thread.project.path;
    _unhide(folder);
    if (ideWindows case final route?) {
      _recent(_recentFolders, folder);
      _addIdeChat(folder, thread);
      _markShownSeen();
      _save();
      notifyListeners();
      route(folder, thread);
      return;
    }
    _ideFolder = folder;
    _recent(_recentFolders, folder);
    _addIdeChat(folder, thread);
    _layout = WorkspaceLayout.ide;
    _save();
    notifyListeners();
  }

  /// The chats the IDE shows as tabs in [folder], in their order: agents,
  /// or (until those are listed) the ids of their sessions.
  final Map<String, List<Object>> _ideChats = {};

  /// The tab shown in each folder, the same way.
  final Map<String, Object> _ideChatShown = {};

  /// New agents in the IDE's tabs, not kept until their session has an id.
  final Set<AgentThread> _ideChatsUnkept = {};

  AgentThread? _threadWithId(String id) {
    for (final thread in _threads) {
      if (thread.id == id) return thread;
    }
    return null;
  }

  /// The chats open as tabs in [folder] (once listed, for those of the last
  /// run).
  List<AgentThread> ideChats(String folder) {
    final tabs = _ideChats[folder];
    if (tabs == null) return const [];
    for (final (i, tab) in tabs.indexed) {
      if (tab is String) tabs[i] = _threadWithId(tab) ?? tab;
    }
    if (_ideChatShown[folder] case final String id) {
      if (_threadWithId(id) case final thread?) _ideChatShown[folder] = thread;
    }
    return [...tabs.whereType<AgentThread>()];
  }

  /// The tab shown in [folder].
  AgentThread? ideChat(String folder) {
    final tabs = ideChats(folder);
    return switch (_ideChatShown[folder]) {
      final AgentThread thread when tabs.contains(thread) => thread,
      _ => tabs.firstOrNull,
    };
  }

  /// Shows [thread] in [folder]'s tabs, as one of them if it was not.
  void openIdeChat(String folder, AgentThread thread) {
    _addIdeChat(folder, thread);
    _markShownSeen();
    _save();
    notifyListeners();
  }

  /// A new chat in [folder]'s tabs, shown: an untouched one there reused.
  AgentThread newIdeChat(String folder) {
    final thread =
        ideChats(folder).where(_isUntouched).firstOrNull ??
        _newThread(projectAt(folder));
    _addIdeChat(folder, thread);
    _save();
    notifyListeners();
    return thread;
  }

  /// Closes [thread]'s tab in [folder]; the agent goes on, in the sidebar
  /// (a new one nothing was sent to is dropped). The last closed, a new
  /// one takes its place.
  void closeIdeChat(String folder, AgentThread thread) =>
      closeIdeChats(folder, [thread]);

  /// Closes the tabs of [threads] in [folder] at once (a tab's Close
  /// Others, Close to the Right, Close All), as [closeIdeChat] each.
  void closeIdeChats(String folder, Iterable<AgentThread> threads) {
    var closed = false;
    for (final thread in [...threads]) {
      closed = _closeIdeChat(folder, thread) || closed;
    }
    if (!closed) return;
    _ensureIdeChat(folder);
    _save();
    notifyListeners();
  }

  bool _closeIdeChat(String folder, AgentThread thread) {
    final tabs = _ideChats[folder];
    if (tabs == null) return false;
    final at = tabs.indexOf(thread);
    if (at < 0) return false;
    tabs.removeAt(at);
    _ideChatsUnkept.remove(thread);
    if (identical(_ideChatShown[folder], thread)) {
      final heirs = tabs.whereType<AgentThread>().toList();
      if (heirs.isEmpty) {
        _ideChatShown.remove(folder);
      } else {
        _ideChatShown[folder] = heirs[(at - 1).clamp(0, heirs.length - 1)];
      }
    }
    if (_isUntouched(thread) && !_grid.contains(thread)) {
      _discard(thread);
    }
    return true;
  }

  /// Moves [thread]'s tab in [folder] to [index] among the tabs (a tab
  /// dragged); those of the last run not listed yet keep their places.
  void moveIdeChat(String folder, AgentThread thread, int index) {
    final shown = ideChats(folder);
    final from = shown.indexOf(thread);
    if (from < 0) return;
    shown.removeAt(from);
    final to = index.clamp(0, shown.length);
    if (to == from) return;
    shown.insert(to, thread);
    final tabs = _ideChats[folder]!;
    var next = 0;
    for (var i = 0; i < tabs.length; i++) {
      if (tabs[i] is AgentThread) tabs[i] = shown[next++];
    }
    _save();
    notifyListeners();
  }

  void _addIdeChat(String folder, AgentThread thread) {
    final tabs = _ideChats.putIfAbsent(folder, () => []);
    ideChats(folder);
    if (!tabs.contains(thread)) {
      final shown = tabs.indexOf(_ideChatShown[folder] ?? thread);
      tabs.insert(shown < 0 ? tabs.length : shown + 1, thread);
    }
    _ideChatShown[folder] = thread;
    if (thread.id == null) _ideChatsUnkept.add(thread);
  }

  /// A chat for [folder]'s panel, where it has none.
  void _ensureIdeChat(String folder) {
    if (ideChats(folder).isNotEmpty) return;
    // Those of the last run are listed once loaded.
    if (_loading || _ideChats[folder]?.isNotEmpty == true) return;
    _addIdeChat(folder, _newThread(projectAt(folder)));
  }

  /// Takes [thread], deleted or dropped, out of the IDE's tabs.
  void _closeIdeChats(AgentThread thread) {
    _ideChatsUnkept.remove(thread);
    for (final folder in [..._ideChats.keys]) {
      if (!_ideChats[folder]!.remove(thread)) continue;
      if (identical(_ideChatShown[folder], thread)) {
        _ideChatShown.remove(folder);
      }
      if (folder == _ideFolder || _windowFolders.contains(folder)) {
        _ensureIdeChat(folder);
      }
      _save();
    }
  }

  // --- Preferences ------------------------------------------------------------

  WorkspaceLayout get layout => _layout;
  WorkspaceLayout _layout = WorkspaceLayout.chat;
  set layout(WorkspaceLayout layout) {
    // The IDE has windows of its own: the one last in front shows.
    if (ideWindows case final route? when layout == WorkspaceLayout.ide) {
      route(null, null);
      return;
    }
    if (_layout == layout) return;
    _layout = layout;
    _markShownSeen();
    _save();
    notifyListeners();
  }

  /// Where "Open" in the title bar opens a project: the Fast Ide until the
  /// user picks another (kept with the rest, so an earlier pick stays).
  Editor get preferredEditor => _preferredEditor;
  Editor _preferredEditor = Editor.fastIde;
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

  /// Language servers the Fast Ide is not to recommend installing again.
  Set<String> get ignoredServerRecommendations =>
      Set.unmodifiable(_ignoredRecommendations);
  final Set<String> _ignoredRecommendations = {};

  /// Don't Show Again for this Language Server: kept between runs.
  void ignoreServerRecommendation(String serverId) {
    if (!_ignoredRecommendations.add(serverId)) return;
    _save();
    notifyListeners();
  }

  /// Each agent's choices, by session: those it opens with again.
  final Map<String, Map<String, String>> _agentSettings = {};

  /// Agents' choices kept, the most recent ones.
  static const _keptAgents = 500;

  // --- Sidebar ------------------------------------------------------------

  /// How the sidebar groups agents, by name; null for its default.
  String? get sidebarGrouping => _sidebarGrouping;
  String? _sidebarGrouping;
  set sidebarGrouping(String? grouping) {
    if (grouping == _sidebarGrouping) return;
    _sidebarGrouping = grouping;
    _save();
    notifyListeners();
  }

  /// Whether the sidebar group [group] (by key) is folded.
  bool isCollapsed(String group) => _collapsedGroups.contains(group);
  final Set<String> _collapsedGroups = {};

  void toggleCollapsed(String group) {
    if (!_collapsedGroups.remove(group)) _collapsedGroups.add(group);
    _save();
    notifyListeners();
  }

  /// Whether the sidebar lists archived agents.
  bool get showArchived => _showArchived;
  bool _showArchived = false;
  set showArchived(bool show) {
    if (show == _showArchived) return;
    _showArchived = show;
    _save();
    notifyListeners();
  }

  /// Whether the sidebar group [group] (by key) shows all its agents,
  /// not only the most recent ones.
  bool isExpanded(String group) => _expandedGroups.contains(group);
  final Set<String> _expandedGroups = {};

  void toggleExpanded(String group) {
    if (!_expandedGroups.remove(group)) _expandedGroups.add(group);
    _save();
    notifyListeners();
  }

  /// Whether the sidebar lists [thread]: not a new agent nothing was sent
  /// to (but the one shown), nor one of a project not listed (the IDE's
  /// folder's, until it is sent something).
  bool listsInSidebar(AgentThread thread) =>
      _projects.contains(thread.project) &&
      (!_isUntouched(thread) || _grid.contains(thread));

  /// The sidebar's key for the group of [path]'s project.
  static String projectGroup(String path) => 'project:$path';

  /// Sessions pinned, by id, in the order the sidebar lists them; and
  /// archived. Claude Code keeps neither.
  final Set<String> _pinned = {}, _archived = {};

  void _setPinnedIds(Iterable<String> ids) {
    final ordered = {...ids};
    _pinned
      ..clear()
      ..addAll(ordered);
  }

  /// [threads] (pinned ones) as the user ordered them: the last pinned on
  /// top, those not yet with an id above all.
  List<AgentThread> inPinnedOrder(Iterable<AgentThread> threads) {
    final rank = {for (final (i, id) in _pinned.indexed) id: i};
    final ranked = [
      for (final thread in threads)
        if (rank[thread.id] != null) thread,
    ]..sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
    return [
      for (final thread in threads)
        if (rank[thread.id] == null) thread,
      ...ranked,
    ];
  }

  /// Pins what of [ordered] is not, and has them listed in that order.
  void reorderPinned(List<AgentThread> ordered) {
    for (final thread in ordered) {
      thread.pinned = true;
      _keepMarks(thread);
    }
    final ids = [for (final thread in ordered) ?thread.id];
    // Those not listed (e.g. of a project taken off the list) after.
    _setPinnedIds([...ids, ..._pinned]);
    _save();
    notifyListeners();
  }

  /// The order the user dragged each project's agents in, by path: ids,
  /// top first. A project not here lists them newest first.
  final Map<String, List<String>> _order = {};

  /// Whether [project]'s agents are in the order the user dragged them in,
  /// rather than newest first.
  bool isManuallyOrdered(Project project) => _order.containsKey(project.path);

  /// [threads] (of [project], newest first) as the user ordered them:
  /// those not ordered yet (e.g. new) on top, newest first.
  List<AgentThread> inProjectOrder(Project project, List<AgentThread> threads) {
    final order = _order[project.path];
    if (order == null) return threads;
    final rank = {for (final (i, id) in order.indexed) id: i};
    final ranked = [
      for (final thread in threads)
        if (rank[thread.id] != null) thread,
    ]..sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
    return [
      for (final thread in threads)
        if (rank[thread.id] == null) thread,
      ...ranked,
    ];
  }

  /// Lists [project]'s agents in the order of [ordered] from now on.
  void reorder(Project project, List<AgentThread> ordered) {
    final ids = [for (final thread in ordered) ?thread.id];
    _order[project.path] = [
      ...ids,
      // Those not listed now (e.g. archived) keep their place after.
      for (final id in _order[project.path] ?? const <String>[])
        if (!ids.contains(id)) id,
    ];
    _save();
    notifyListeners();
  }

  /// Lists [project]'s agents newest first again.
  void sortByTime(Project project) {
    if (_order.remove(project.path) == null) return;
    _save();
    notifyListeners();
  }

  /// Projects the user took off the sidebar, by path, and when: listed
  /// again once opened, or asked something since (see [_unhide]).
  final Map<String, DateTime> _hiddenProjects = {};

  bool isHidden(Project project) => _hiddenProjects.containsKey(project.path);

  /// Takes [project] off the sidebar; nothing of it is deleted.
  void hideProject(Project project) {
    _hiddenProjects[project.path] = DateTime.now();
    _save();
    notifyListeners();
  }

  void _unhide(String path) {
    if (_hiddenProjects.remove(path) != null) _save();
  }

  /// The order the user dragged projects in, by path.
  final List<String> _projectOrder = [];

  /// The projects the sidebar lists, in its order: those not dragged yet
  /// (e.g. new) on top, most recent first; then as the user ordered them.
  List<Project> get sidebarProjects {
    final shown = [
      for (final project in _projects)
        if (!isHidden(project)) project,
    ];
    final rank = {for (final (i, path) in _projectOrder.indexed) path: i};
    final ranked = [
      for (final project in shown)
        if (rank[project.path] != null) project,
    ]..sort((a, b) => rank[a.path]!.compareTo(rank[b.path]!));
    return [
      for (final project in shown)
        if (rank[project.path] == null) project,
      ...ranked,
    ];
  }

  /// Moves [project] to [index] of [sidebarProjects]: all listed are in
  /// the user's order from then on.
  void moveProject(Project project, int index) {
    final order = sidebarProjects..remove(project);
    order.insert(index.clamp(0, order.length), project);
    final paths = [for (final project in order) project.path];
    final rest = [
      for (final path in _projectOrder)
        if (!paths.contains(path)) path,
    ];
    _projectOrder
      ..clear()
      ..addAll([...paths, ...rest]);
    _save();
    notifyListeners();
  }

  /// Archives [project]'s agents (not a new one nothing was sent to).
  void archiveAll(Project project) {
    for (final thread in [..._threads]) {
      if (thread.project != project || thread.archived || thread.untouched) {
        continue;
      }
      thread
        ..archived = true
        ..pinned = false;
      _keepMarks(thread);
      _leave(thread);
    }
    notifyListeners();
  }

  // --- Project icons --------------------------------------------------------

  /// The pictures uploaded as icons, shared by the projects.
  final IconLibrary icons;

  /// What each project shows in place of its folder, by path.
  final Map<String, ProjectIcon> _projectIcons = {};

  /// The icons last picked, the last first.
  List<ProjectIcon> get recentIcons => List.unmodifiable(_recentIcons);
  final List<ProjectIcon> _recentIcons = [];
  static const _keptRecentIcons = 16;

  /// [project]'s icon; null for its folder.
  ProjectIcon? iconOf(Project project) => _projectIcons[project.path];

  /// Gives [project] [icon], or its folder back when null; [remember]
  /// notes it among the [recentIcons].
  void setIcon(Project project, ProjectIcon? icon, {bool remember = true}) {
    if (icon == null) {
      _projectIcons.remove(project.path);
    } else {
      _projectIcons[project.path] = icon;
      if (remember) {
        _recentIcons
          ..remove(icon)
          ..insert(0, icon);
        if (_recentIcons.length > _keptRecentIcons) {
          _recentIcons.removeRange(_keptRecentIcons, _recentIcons.length);
        }
      }
    }
    _save();
    notifyListeners();
  }

  /// Whose pictures the emoji are drawn from ([EmojiSheet.style]); null
  /// until the user picks, for the system's own.
  EmojiStyle? _emojiStyle;

  void setEmojiStyle(EmojiStyle style) {
    if (style == _emojiStyle) return;
    _emojiStyle = style;
    EmojiSheet.style.value = style;
    _save();
    notifyListeners();
  }

  /// A picture deleted from the library: the projects that showed it show
  /// their folder again.
  void _forgetIconImage(String id) {
    final icon = LibraryIcon(id);
    final count = _projectIcons.length + _recentIcons.length;
    _projectIcons.removeWhere((_, value) => value == icon);
    _recentIcons.remove(icon);
    if (_projectIcons.length + _recentIcons.length == count) return;
    _save();
    notifyListeners();
  }

  /// Names the user gave sessions whose CLI was not running, by id: it
  /// takes them once it is, until then the catalog lists the old title.
  final Map<String, String> _names = {};

  /// Folders opened where no kernel keeps a session yet.
  final List<String> _folders = [];

  /// Forgets what was kept for sessions and folders the catalogs no longer
  /// list as such ([listed]: the project paths they do).
  void _forgetGone(Set<String> listed) {
    final titles = {
      for (final thread in _threads)
        if (thread.record case final record?) record.id: record.title,
    };
    final count = _pinned.length + _archived.length + _folders.length;
    final names = _names.length;
    _pinned.retainAll(titles.keys);
    _archived.retainAll(titles.keys);
    // A name the catalog lists is the CLI's now.
    _names.removeWhere((id, name) => titles[id] == null || titles[id] == name);
    _folders.removeWhere(listed.contains);
    final paths = {for (final project in _projects) project.path};
    bool gone(String group) =>
        group.startsWith(projectGroup('')) &&
        !paths.contains(group.substring(projectGroup('').length));
    int size() => Object.hashAll([
      _collapsedGroups.length,
      _expandedGroups.length,
      _projectOrder.length,
      _hiddenProjects.length,
      _order.length,
      _projectIcons.length,
      for (final order in _order.values) order.length,
    ]);
    final before = size();
    _collapsedGroups.removeWhere(gone);
    _expandedGroups.removeWhere(gone);
    _projectOrder.retainWhere(paths.contains);
    _hiddenProjects.removeWhere((path, _) => !paths.contains(path));
    _order.removeWhere((path, _) => !paths.contains(path));
    _projectIcons.removeWhere((path, _) => !paths.contains(path));
    for (final order in _order.values) {
      order.retainWhere(titles.containsKey);
    }
    final ids = {...titles.keys, for (final thread in _threads) ?thread.id};
    final drafts = _drafts.length;
    _drafts.removeWhere(
      (key, _) => key.startsWith(_newDraft)
          ? !paths.contains(key.substring(_newDraft.length))
          : !ids.contains(key),
    );
    if (_drafts.length != drafts) _saveDrafts();
    for (final tabs in _ideChats.values) {
      tabs.removeWhere((tab) => tab is String && !titles.containsKey(tab));
    }
    _ideChatShown.removeWhere(
      (_, tab) => tab is String && !titles.containsKey(tab),
    );
    if (_pinned.length + _archived.length + _folders.length != count ||
        _names.length != names ||
        size() != before) {
      _save();
    }
  }

  // --- Drafts ---------------------------------------------------------------

  /// What is typed and not sent in each agent's composer, kept between
  /// runs apart from [_store] (written as it is typed): by session id, or
  /// [_newDraft] and the project's path for a new agent's.
  final PreferenceStore? _draftStore;
  final Map<String, Map<String, Object?>> _drafts = {};
  static const _newDraft = 'new:';

  /// Projects whose new agent's draft no agent of this run has taken yet:
  /// the first new agent there does.
  final Set<String> _newDrafts = {};

  /// The key each agent's draft was last kept under: a new agent's moves
  /// to its session's.
  final Map<AgentThread, String> _draftKeys = {};
  Timer? _draftTimer;

  Future<void> _restoreDrafts() async {
    final kept = await _draftStore?.read() ?? const {};
    for (final MapEntry(:key, :value) in kept.entries) {
      if (value is Map<String, Object?>) _drafts[key] = value;
      if (key.startsWith(_newDraft)) {
        _newDrafts.add(key.substring(_newDraft.length));
      }
    }
  }

  /// Puts back [thread]'s draft from the last run, and keeps it as it
  /// changes.
  void _followDraft(AgentThread thread) {
    final draft = thread.session.draft;
    final id = thread.id;
    final key = id ?? '$_newDraft${thread.project.path}';
    if (id != null || _newDrafts.remove(thread.project.path)) {
      if (_drafts[key] case final kept?) _decodeDraft(kept, draft);
    }
    draft.onSaved = () => _draftChanged(thread);
  }

  void _draftChanged(AgentThread thread) {
    final draft = thread.session.draft;
    final key = thread.id ?? '$_newDraft${thread.project.path}';
    if (_draftKeys[thread] case final was? when was != key) {
      _drafts.remove(was);
    }
    _draftKeys[thread] = key;
    final empty = draft.content!.toList().every(
      (op) => op.data is String && (op.data! as String).trim().isEmpty,
    );
    if (empty) {
      if (_drafts.remove(key) == null) return;
    } else {
      _drafts[key] = _encodeDraft(draft);
    }
    _saveDrafts();
  }

  void _forgetDraft(String id) {
    if (_drafts.remove(id) != null) _saveDrafts();
  }

  /// Written a moment after typing stops, not on every key.
  void _saveDrafts() {
    if (_draftStore == null) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 500), _writeDrafts);
  }

  void _writeDrafts() => unawaited(_draftStore?.write({..._drafts}));

  static Map<String, Object?> _encodeDraft(ComposerDraft draft) => {
    'content': draft.content!.toJson(),
    'base': draft.selection.baseOffset,
    'extent': draft.selection.extentOffset,
    'images': [
      for (final image in draft.images)
        {
          'bytes': base64Encode(image.bytes),
          'mediaType': image.mediaType,
          'name': ?image.name,
          'number': ?image.number,
        },
    ],
  };

  /// Into [draft]; nothing of one that cannot be read.
  static void _decodeDraft(Map<String, Object?> kept, ComposerDraft draft) {
    try {
      final images = [
        for (final image in kept['images']! as List<Object?>)
          if (image case {
            'bytes': final String bytes,
            'mediaType': final String mediaType,
          })
            ImageAttachment(
              bytes: base64Decode(bytes),
              mediaType: mediaType,
              name: image['name'] as String?,
              number: image['number'] as int?,
            ),
      ];
      final content = Delta.fromJson(kept['content']! as List<Object?>);
      final selection = TextSelection(
        baseOffset: kept['base']! as int,
        extentOffset: kept['extent']! as int,
      );
      draft
        ..content = content
        ..selection = selection
        ..images = images;
    } on Object {
      // Kept by another version, or broken: not put back.
    }
  }

  // --- Color theme --------------------------------------------------------

  /// The `workbench.colorTheme` setting.
  @override
  String? get colorThemeSetting => _colorTheme;
  String? _colorTheme;

  /// The current theme as `ColorThemeData.toStorage` keeps it.
  @override
  String? get colorThemeData => _colorThemeData;
  String? _colorThemeData;
  bool _colorThemeStored = false;

  @override
  void storeColorTheme({required String setting, String? data}) {
    _colorTheme = setting;
    _colorThemeData = data;
    _colorThemeStored = true;
    // Not before what was kept is read: that would be written over.
    unawaited(_restoring.then((_) => _save()));
  }

  /// What was kept, read once [load] has read it.
  Future<void> get restored => _restoring;
  Future<void> _restoring = Future.value();

  final PreferenceStore? _store;

  Future<void> _restore() async {
    await _restoreDrafts();
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
    // The file manager was kept as `finder` before it was `folder`.
    final editor = kept['editor'] == 'finder'
        ? Editor.folder.name
        : kept['editor'];
    if (Editor.availableEditors.where((e) => e.name == editor).firstOrNull
        case final editor?) {
      _preferredEditor = editor;
    }
    if (kept['layout'] == WorkspaceLayout.ide.name) {
      _layout = WorkspaceLayout.ide;
    }
    _settings.addAll(strings(kept['settings']));
    if (kept['ignoredRecommendations'] case final List<Object?> ignored) {
      _ignoredRecommendations.addAll(ignored.whereType<String>());
    }
    if (kept['agents'] case final Map<Object?, Object?> agents) {
      for (final MapEntry(:key, :value) in agents.entries) {
        if (key is String) _agentSettings[key] = strings(value);
      }
    }
    if (kept['sidebar'] case final Map<Object?, Object?> sidebar) {
      Iterable<String> list(String key) => switch (sidebar[key]) {
        final List<Object?> list => list.whereType<String>(),
        _ => const [],
      };
      if (sidebar['grouping'] case final String grouping) {
        _sidebarGrouping = grouping;
      }
      _collapsedGroups.addAll(list('collapsed'));
      _showArchived = sidebar['showArchived'] == true;
      _pinned.addAll(list('pinned'));
      _archived.addAll(list('archived'));
      _names.addAll(strings(sidebar['names']));
      _folders.addAll(list('folders'));
      _expandedGroups.addAll(list('expanded'));
      _projectOrder.addAll(list('projectOrder'));
      for (final MapEntry(:key, :value) in strings(
        sidebar['hiddenProjects'],
      ).entries) {
        if (DateTime.tryParse(value) case final since?) {
          _hiddenProjects[key] = since;
        }
      }
      if (sidebar['order'] case final Map<Object?, Object?> order) {
        for (final MapEntry(:key, :value) in order.entries) {
          if ((key, value) case (final String path, final List<Object?> ids)) {
            _order[path] = ids.whereType<String>().toList();
          }
        }
      }
    }
    if (kept['projectIcons'] case final Map<Object?, Object?> icons) {
      for (final MapEntry(:key, :value) in icons.entries) {
        if ((key, ProjectIcon.fromJson(value)) case (
          final String path,
          final icon?,
        )) {
          _projectIcons[path] = icon;
        }
      }
    }
    if (kept['recentIcons'] case final List<Object?> recent) {
      _recentIcons.addAll(recent.map(ProjectIcon.fromJson).nonNulls);
    }
    if (EmojiStyle.values.asNameMap()[kept['emojiStyle']] case final style?) {
      _emojiStyle = style;
      EmojiSheet.style.value = style;
    }
    if (kept['chat'] case final Map<Object?, Object?> chat) {
      _keptChatView = chat;
    }
    if (kept['ide'] case final Map<Object?, Object?> ide) {
      Iterable<String> list(Object? raw) => switch (raw) {
        final List<Object?> list => list.whereType<String>(),
        _ => const [],
      };
      if (ide['folder'] case final String folder) _ideFolder = folder;
      _recentFolders.addAll(list(ide['recentFolders']));
      _recentFiles.addAll(list(ide['recentFiles']));
      if (ide['views'] case final Map<Object?, Object?> views) {
        for (final MapEntry(:key, :value) in views.entries) {
          if ((key, value) case (final String folder, final Map view)) {
            _ideViews[folder] = view.cast<String, Object?>();
          }
        }
      }
      if (ide['chats'] case final Map<Object?, Object?> chats) {
        for (final MapEntry(:key, :value) in chats.entries) {
          if ((key, value) case (
            final String folder,
            final Map<Object?, Object?> chat,
          )) {
            _ideChats[folder] = [...list(chat['tabs'])];
            if (chat['shown'] case final String id) _ideChatShown[folder] = id;
          }
        }
      }
    }
    if (!_colorThemeStored) {
      if (kept['colorTheme'] case final String setting) _colorTheme = setting;
      if (kept['colorThemeData'] case final String data) {
        _colorThemeData = data;
      }
    }
  }

  void _save() => unawaited(
    _store?.write({
      'kernel': _preferredKernel.id,
      'editor': _preferredEditor.name,
      'layout': _layout.name,
      'settings': _settings,
      'agents': _agentSettings,
      'ignoredRecommendations': [..._ignoredRecommendations],
      'sidebar': {
        'grouping': ?_sidebarGrouping,
        'collapsed': [..._collapsedGroups],
        'showArchived': _showArchived,
        'pinned': [..._pinned],
        'archived': [..._archived],
        'names': {..._names},
        'folders': [..._folders],
        'expanded': [..._expandedGroups],
        'projectOrder': [..._projectOrder],
        'hiddenProjects': {
          for (final MapEntry(:key, :value) in _hiddenProjects.entries)
            key: value.toIso8601String(),
        },
        'order': {
          for (final MapEntry(:key, :value) in _order.entries) key: [...value],
        },
      },
      'ide': {
        'folder': ?_ideFolder,
        'recentFolders': [..._recentFolders],
        'recentFiles': [..._recentFiles],
        // Those of the folders still recent.
        'views': {
          for (final MapEntry(key: folder, :value) in _ideViews.entries)
            if (folder == _ideFolder || _recentFolders.contains(folder))
              folder: value,
        },
        'chats': {
          for (final MapEntry(key: folder, value: tabs) in _ideChats.entries)
            if (_keptTabs(tabs) case final ids when ids.isNotEmpty)
              folder: {'tabs': ids, 'shown': ?_keptTab(_ideChatShown[folder])},
        },
      },
      'projectIcons': {
        for (final MapEntry(:key, :value) in _projectIcons.entries)
          key: value.toJson(),
      },
      'recentIcons': [for (final icon in _recentIcons) icon.toJson()],
      'emojiStyle': ?_emojiStyle?.name,
      'chat': ?_chatViewToSave(),
      'colorTheme': ?_colorTheme,
      'colorThemeData': ?_colorThemeData,
    }),
  );

  /// The panes to save: as kept, until [load] has shown them again.
  Object? _chatViewToSave() {
    if (!_chatViewRestored) return _keptChatView;
    final view = _chatView;
    _chatViewSaved = jsonEncode(view);
    return view;
  }

  /// An IDE tab as kept: its session's id, none for a new agent's.
  static String? _keptTab(Object? tab) => switch (tab) {
    final String id => id,
    final AgentThread thread => thread.id,
    _ => null,
  };

  static List<String> _keptTabs(List<Object> tabs) => [
    for (final tab in tabs) ?_keptTab(tab),
  ];

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
    // Named while closed: its CLI keeps the name once running.
    if (_names[thread.record?.id] case final name?) thread.session.rename(name);
    _followDraft(thread);
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
    if (thread._wantsTitle) _askTitle(thread);
    // Sent something: its folder is a project now, if it was not.
    if (!_isUntouched(thread) && !_projects.contains(thread.project)) {
      _listProject(thread.project);
    }
    if (_ideChatsUnkept.contains(thread) && thread.id != null) {
      _ideChatsUnkept.remove(thread);
      _save();
    }
    // What ends in view is seen, while the window is in front.
    if (_windowActive && isShown(thread)) thread._markSeen();
    // Pinned or archived before its first message gave it an id.
    if (thread.pinned || thread.archived) _keepMarks(thread);
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

  /// Whether the window is in front: what ends in view while it is not
  /// is unread until it is again.
  bool get windowActive => _windowActive;
  bool _windowActive = true;
  set windowActive(bool active) {
    if (active == _windowActive) return;
    _windowActive = active;
    if (active && _markShownSeen()) notifyListeners();
  }

  /// Whether [thread] shows in the window: in one of the chat's panes, or,
  /// while the IDE shows, as its folder's chat. With the IDE's windows,
  /// in the chat's panes while its window shows, or as the chat of one of
  /// theirs. Either way, in a window of its own.
  bool isShown(AgentThread thread) =>
      _windowAgents.contains(thread) ||
      (ideWindows != null
          ? (_chatWindowShown && _grid.contains(thread)) ||
                _windowFolders.any(
                  (folder) => identical(ideChat(folder), thread),
                )
          : switch (_layout) {
              WorkspaceLayout.chat => _grid.contains(thread),
              WorkspaceLayout.ide => switch (_ideFolder) {
                final folder? => identical(ideChat(folder), thread),
                null => false,
              },
            });

  /// Marks what shows as seen, while the window is in front; whether any
  /// was unread.
  bool _markShownSeen() {
    if (!_windowActive) return false;
    var changed = false;
    for (final thread in _threads) {
      if (!thread.unread || !isShown(thread)) continue;
      thread._markSeen();
      _snapshots[thread] = thread._snapshot;
      changed = true;
    }
    return changed;
  }

  // --- The chat's panes, kept between runs ----------------------------------

  /// The panes as the last run left them, until [load] shows them again.
  Map<Object?, Object?>? _keptChatView;
  bool _chatViewRestored = false;

  /// What [_chatView] was last saved as.
  String? _chatViewSaved;

  /// The agents shown side by side, the grid's cells, the one focused and
  /// where the lines are; an agent by its session's id, a new one by its
  /// folder.
  Map<String, Object?>? get _chatView {
    if (_grid.isEmpty) return null;
    final panes = _grid.panes;
    final focused = _selected;
    return {
      'panes': [
        for (final thread in panes) thread.id ?? {'new': thread.project.path},
      ],
      'cells': [for (final pane in _grid.cells) panes.indexOf(pane)],
      if (focused != null && panes.contains(focused))
        'focused': panes.indexOf(focused),
      'columnRatio': _grid.columnRatio,
      'rowRatio': _grid.rowRatio,
    };
  }

  /// The panes as [_chatView] kept them, those whose agent is gone left
  /// out; the agent focused focused. Nothing with none left.
  void _restoreChatView() {
    final kept = _keptChatView;
    _keptChatView = null;
    _chatViewRestored = true;
    if (kept == null || _selected != null) return;
    final panes = switch (kept['panes']) {
      final List<Object?> panes => panes,
      _ => const <Object?>[],
    };
    final cells = ChatGrid<int>();
    if (kept['cells'] case final List<Object?> kept) {
      cells.restore(kept.whereType<int>().toList());
    }
    final shown = <int, AgentThread>{};
    for (final pane in cells.panes) {
      final thread = switch (panes.elementAtOrNull(pane)) {
        final String id =>
          _threads.where((t) => t.id == id && !t.archived).firstOrNull,
        {'new': final String path} => switch (_projects
            .where((project) => project.path == path)
            .firstOrNull) {
          final project? =>
            _threads
                    .where(
                      (t) =>
                          t.project == project &&
                          _isUntouched(t) &&
                          !shown.containsValue(t),
                    )
                    .firstOrNull ??
                _newThread(project),
          null => null,
        },
        _ => null,
      };
      if (thread != null && !shown.containsValue(thread)) {
        shown[pane] = thread;
      }
    }
    for (final pane in cells.panes) {
      if (!shown.containsKey(pane)) cells.remove(pane);
    }
    if (cells.isEmpty) return;
    _grid.restore([for (final cell in cells.cells) shown[cell]!]);
    if (kept['columnRatio'] case final num ratio when ratio > 0 && ratio < 1) {
      _grid.columnRatio = ratio.toDouble();
    }
    if (kept['rowRatio'] case final num ratio when ratio > 0 && ratio < 1) {
      _grid.rowRatio = ratio.toDouble();
    }
    final focused = switch (kept['focused']) {
      final int pane => shown[pane],
      _ => null,
    };
    _focus(focused ?? _grid.at(0)!);
  }

  /// A line between the panes moved: kept where it is now.
  void keepGridLines() => _save();

  /// Saves the panes whenever they change: an agent opened, split off,
  /// closed or given its id.
  @override
  void notifyListeners() {
    if (_chatViewRestored && jsonEncode(_chatView) != _chatViewSaved) {
      _save();
    }
    super.notifyListeners();
  }

  /// Shows [thread] and focuses it: in its pane if it has one, else in
  /// place of the focused one.
  void select(AgentThread thread) {
    _focus(thread);
    notifyListeners();
  }

  void _focus(AgentThread thread) {
    thread._markSeen();
    _snapshots[thread] = thread._snapshot;
    if (!_grid.contains(thread)) {
      final focused = _selected;
      if (focused != null && _grid.contains(focused)) {
        _grid.replace(focused, thread);
      } else {
        _grid.show(thread);
      }
    }
    _selected = thread;
  }

  /// Shows [thread] in the half of [target]'s pane on its [side], and
  /// focuses it; where it shows already, only focuses it. Nothing where
  /// [target]'s pane cannot be split that way (see [ChatGrid.canSplit]).
  void openBeside(AgentThread thread, AgentThread target, PaneSide side) {
    if (!_grid.contains(thread)) {
      if (!_grid.canSplit(target, side)) return;
      _grid.split(target, side, thread);
    }
    select(thread);
  }

  /// Shows [thread] in [target]'s pane, and focuses it; where it shows
  /// already, only focuses it.
  void openInPlaceOf(AgentThread target, AgentThread thread) {
    if (!_grid.contains(target)) return;
    if (!_grid.contains(thread)) _grid.replace(target, thread);
    select(thread);
  }

  /// Closes [thread]'s pane, the one beside it taking its place; the last
  /// one stays. The agent goes on, in the sidebar.
  void closePane(AgentThread thread) {
    if (_grid.length < 2 || !_grid.contains(thread)) return;
    final heir = _grid.remove(thread)!;
    if (identical(thread, _selected)) _focus(heir);
    notifyListeners();
  }

  /// Opens a new, empty agent in [project] (by default the current one's).
  /// An untouched new agent there is reused rather than piling up.
  AgentThread create({Project? project}) {
    project ??= switch (_selected?.project) {
      final current? when !isHidden(current) => current,
      _ => sidebarProjects.firstOrNull ?? _projects.firstOrNull,
    };
    if (project == null) {
      throw StateError('No project to create an agent in');
    }
    for (final thread in _threads) {
      if (thread.project == project && _isUntouched(thread)) {
        select(thread);
        return thread;
      }
    }
    final thread = _newThread(project);
    select(thread);
    return thread;
  }

  /// A new, empty agent in [project], listed here but not shown.
  AgentThread _newThread(Project project) {
    final kernel = _preferredKernel;
    final settings = {
      ..._preferredSettings,
      // Settings → Models' pick, if any, over the last one.
      KernelChoiceKind.model.name: ?ModelProviders.current.defaultModel,
    };
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
    return thread;
  }

  static bool _isUntouched(AgentThread thread) => thread.untouched;

  /// Takes the untouched [thread] off the list: nothing of it was kept, so
  /// unlike [delete] there is no session to delete.
  void _discard(AgentThread thread) {
    final listener = _listeners.remove(thread);
    if (listener != null) thread.session.removeListener(listener);
    _snapshots.remove(thread);
    if (_draftKeys.remove(thread) case final key?) _forgetDraft(key);
    _threads.remove(thread);
    _leave(thread);
    _closeIdeChats(thread);
    thread.session
      ..stop()
      ..dispose();
    notifyListeners();
  }

  /// Titles [thread] after its first message: images alone after their
  /// file; anything else by [titler], if its kernel keeps the title
  /// (Claude Code's: the message goes to Claude).
  void _askTitle(AgentThread thread) {
    final session = thread.session;
    // Not only added at the end: a message goes before the live status.
    for (var i = 0; i < session.itemCount; i++) {
      if (session.itemAt(i) case UserMessageItem(:final text, :final images)) {
        thread._wantsTitle = false;
        // A new session there: its project is listed again.
        _unhide(thread.project.path);
        // Within [_sync], which tells the change.
        if (agentImageTitle(text, images, l10n()) case final title?) {
          thread._title = title;
          session.rename(title);
          return;
        }
        if (titler == null || !session.canRename) return;
        unawaited(
          titler!(
            text,
            model: session.selected(KernelChoiceKind.model),
            location: thread.project.path,
          ).then((title) {
            if (title == null || thread._named) return;
            if (_disposed || !_threads.contains(thread)) return;
            _retitle(thread, title);
          }),
        );
        return;
      }
    }
  }

  void rename(AgentThread thread, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == thread._title) return;
    thread
      .._named = true
      .._wantsTitle = false;
    // Kept here too: its CLI takes the name only once running.
    if (thread._id case final id?) {
      _names[id] = trimmed;
      _save();
    }
    _retitle(thread, trimmed);
  }

  void _retitle(AgentThread thread, String title) {
    thread._title = title;
    if (thread.isOpen) thread.session.rename(title);
    _snapshots[thread] = thread._snapshot;
    notifyListeners();
  }

  void setPinned(AgentThread thread, bool pinned) {
    thread.pinned = pinned;
    _keepMarks(thread);
    notifyListeners();
  }

  void setArchived(AgentThread thread, bool archived) {
    thread.archived = archived;
    if (archived) thread.pinned = false;
    _keepMarks(thread);
    if (archived) _leave(thread);
    notifyListeners();
  }

  /// Keeps whether [thread] is pinned and archived for the next run, once
  /// its session has an id (see [_sync] for a new agent's).
  void _keepMarks(AgentThread thread) {
    final id = thread._id;
    if (id == null) return;
    bool mark(Set<String> ids, bool on) => on ? ids.add(id) : ids.remove(id);
    // Both, not only the first that changed.
    final pinned = mark(_pinned, thread.pinned);
    final archived = mark(_archived, thread.archived);
    // Pinned last, it is on top (see [inPinnedOrder]).
    if (pinned && thread.pinned) _setPinnedIds([id, ..._pinned]);
    if (pinned || archived) _save();
  }

  /// Deletes [thread]: stops its agent, and once it has stopped, deletes
  /// the session its kernel kept (deleting it again does nothing).
  void delete(AgentThread thread) {
    final id =
        thread.record?.id ?? (thread.isOpen ? thread.session.sessionId : null);
    if (id != null) {
      _removed.add(id);
      _forgetDraft(id);
      final kept = [_pinned.remove(id), _archived.remove(id)];
      if (_names.remove(id) != null || kept.contains(true)) _save();
    }
    final catalog = thread.kernel.catalog;
    final listener = _listeners.remove(thread);
    if (listener != null) thread.session.removeListener(listener);
    _snapshots.remove(thread);
    if (_draftKeys.remove(thread) case final key?) _forgetDraft(key);
    _threads.remove(thread);
    _leave(thread);
    _closeIdeChats(thread);
    var stopped = Future<void>.value();
    if (thread.isOpen) {
      thread.session
        ..stop()
        ..discardChanges()
        ..dispose();
      stopped = thread.session.stopped;
    }
    if ((catalog, id) case (final catalog?, final id?)) {
      unawaited(stopped.then((_) => catalog.delete(id)).catchError((_) {}));
    }
    notifyListeners();
  }

  /// After [gone] is archived or deleted: its pane closes, the one beside
  /// it taking its place; the last one shows the most recent remaining
  /// agent instead, or a new one.
  void _leave(AgentThread gone) {
    if (!_grid.contains(gone)) return;
    if (_grid.length > 1) {
      final heir = _grid.remove(gone)!;
      if (identical(gone, _selected)) _focus(heir);
      return;
    }
    final candidates = [
      for (final thread in _threads)
        if (!thread.archived &&
            !identical(thread, gone) &&
            _projects.contains(thread.project))
          thread,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _grid.clear();
    _selected = null;
    if (candidates.isEmpty) {
      create(project: gone.project);
    } else {
      _focus(candidates.first);
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    icons.removeListener(notifyListeners);
    for (final MapEntry(key: path, value: listener) in _unreached.entries) {
      SshHosts.instance[RemoteLocation.hostOf(path)!].removeListener(listener);
    }
    if (_draftTimer?.isActive ?? false) {
      _draftTimer!.cancel();
      _writeDrafts();
    }
    for (final MapEntry(key: thread, value: listener) in _listeners.entries) {
      thread.session
        ..removeListener(listener)
        ..stop()
        ..dispose();
    }
    super.dispose();
  }
}
