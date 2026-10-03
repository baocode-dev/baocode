import 'dart:async';
import 'dart:math' as math;

import 'package:bao_editor/textmate/textmate_syntax.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'chat/chat_keys.dart';
import 'chat/chat_models.dart' show FileChange, FileChangeKind;
import 'chat/chat_screen.dart';
import 'chat/composer/composer_files.dart' show ComposerFile;
import 'chat/composer/file_drop.dart';
import 'chat/panels/interaction_panel.dart';
import 'customize/customization_store.dart';
import 'customize/customizations.dart';
import 'customize/customize_view.dart';
import 'ide/git/git_repository.dart';
import 'ide/ide_chat_title.dart';
import 'ide/ide_commands.dart';
import 'ide/ide_dialog.dart';
import 'ide/ide_modern_ui.dart';
import 'ide/ide_notifications.dart';
import 'ide/file_service.dart';
import 'ide/ide_quick_input.dart';
import 'ide/ide_quick_open.dart';
import 'ide/ide_workbench.dart';
import 'ide/ide_workspace.dart';
import 'ide/lsp/language_features.dart';
import 'ide/lsp/lsp_protocol.dart';
import 'ide/terminal/terminal_instance.dart';
import 'keybindings/chat_keybindings.dart';
import 'keybindings/default_keybindings.dart';
import 'keybindings/key_chord.dart';
import 'keybindings/keybinding_service.dart';
import 'keybindings/window_keybindings.dart';
import 'l10n/command_titles.dart';
import 'l10n/l10n.dart';
import 'notifications/attention_host.dart';
import 'notifications/attention_service.dart';
import 'notifications/attention_settings.dart';
import 'platform/local_paths.dart'
    if (dart.library.io) 'platform/local_paths_io.dart';
import 'platform/open_requests.dart';
import 'platform/shell_command.dart';
import 'search/conversation_search.dart';
import 'search/search_palette.dart';
import 'settings/app_settings.dart';
import 'settings/data_dir_startup.dart';
import 'settings/jsonc_file.dart';
import 'settings/settings_dialog.dart';
import 'settings/shell_command_actions.dart';
import 'sidebar/sidebar.dart';
import 'theme/codicons.dart';
import 'theme/app_theme.dart';
import 'theme/workbench_theme.dart' show WorkbenchThemeService, themeColors;
import 'window/app_windows.dart';
import 'window/code_args.dart';
import 'window/window_settings.dart';
import 'workspace/chat_drag.dart';
import 'workspace/chat_grid_view.dart';
import 'workspace/new_chat_folder_bar.dart';
import 'workspace/open_in_editor_button.dart';
import 'workspace/pin_window_button.dart';
import 'workspace/title_bar_double_click.dart';
import 'workspace/window_controls.dart';
import 'workspace/window_header/window_header.dart';
import 'workspace/workspace.dart';

/// The window: the agents sidebar on the left, the selected agent's chat
/// on the right, and up to three more beside it, dragged there from the
/// sidebar (see [ChatGridView]).
///
/// With [windows] that open windows of their own ([AppWindows.multi]), one
/// is built in each: the chat's window ([AppWindows.chat]) has the chat
/// alone; an IDE window, the IDE of its folder. Without, the IDE shows in
/// this one, as [Workspace.layout] says.
///
/// The sidebar can be dragged wider or narrower and hidden (⌘B or its
/// button). In a narrow window it is hidden by default and opens over the
/// chat as a drawer instead of pushing it aside.
class Workbench extends StatefulWidget {
  const Workbench({
    super.key,
    required this.workspace,
    this.ideEditorBuilder,
    this.languagesFor,
    this.gitFor,
    this.terminalBackend,
    this.settings,
    this.conversations = const NoConversationSearch(),
    this.customizations,
    this.windows,
    this.window,
  });

  final Workspace workspace;

  /// The app's windows; none under test, where the IDE shows in this one.
  final AppWindows? windows;

  /// The one this is built in (the chat's, by default).
  final AppWindow? window;

  /// What the search palette searches the agents' conversations with.
  final ConversationSearch conversations;

  /// Claude Code's customizations, shown by the sidebar's Customize; no
  /// Customize without them.
  final CustomizationStore? customizations;

  /// What the settings dialog shows; without it, only what needs nothing
  /// more (e.g. under test).
  final AppSettings? settings;

  /// The language servers for the project at a root, when the IDE opens it;
  /// none when null.
  final LanguageFeatures Function(String root)? languagesFor;

  /// The Git repository of the project at a root, when the IDE opens it;
  /// none when null.
  final IdeGitRepository Function(String root)? gitFor;

  /// What the IDE's terminals run on (with settings.json's profiles); none
  /// when null.
  final TerminalBackend? terminalBackend;

  @visibleForTesting
  final Widget Function(BuildContext, IdeWorkspace)? ideEditorBuilder;

  /// Below this width the sidebar becomes a drawer.
  static const narrowWidth = 720.0;
  static const minSidebarWidth = 200.0;
  static const maxSidebarWidth = 420.0;

  /// The sidebar leaves at least this much of the window beside it.
  static const sidebarWindowMargin = 20.0;

  @override
  State<Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<Workbench> implements WindowDelegate {
  static const _duration = Duration(milliseconds: 200);

  /// The border between sidebar and chat: a line at the left of a strip
  /// this wide, which takes the resize drag.
  static const _handleWidth = 5.0;

  /// The width set by dragging. Shown as [_shownWidth], which a narrow
  /// window may cap below it for now. A drag sets it without building the
  /// window again: only the columns are laid out anew, the sidebar and the
  /// chat as they were (built again each move, they would lag the pointer).
  final ValueNotifier<double> _width = ValueNotifier(260);

  /// Of the window, from the last layout.
  double _windowWidth = double.infinity;

  /// At most 20 short of the window's width, so the border (and its drag
  /// strip) stays in it.
  double get _maxWidth => math.min(
    Workbench.maxSidebarWidth,
    _windowWidth - Workbench.sidebarWindowMargin,
  );

  double get _shownWidth => _width.value.clamp(
    math.min(Workbench.minSidebarWidth, _maxWidth),
    _maxWidth,
  );
  bool _dragging = false;

  /// Pointer and sidebar width when the resize drag began.
  ({double x, double width})? _dragOrigin;

  /// Shown beside the chat (wide window).
  bool _docked = true;

  /// Shown over the chat (narrow window). A closed drawer is not built,
  /// once it has slid out.
  bool _drawerOpen = false;
  bool _drawerClosing = false;
  bool _narrow = false;

  Workspace get _workspace => widget.workspace;

  /// The IDE's workspaces by folder, each kept once shown; [_noFolder]'s is
  /// its empty window.
  final Map<String, IdeWorkspace> _ideSpaces = {};
  final Map<String, GlobalKey<IdeWorkbenchState>> _ideKeys = {};
  final Map<String, List<IdeCommand>> _ideCommands = {};

  /// The key of the IDE's empty window, with no folder open.
  static const _noFolder = '';

  /// The IDE shown, or to be shown: that of its folder (an IDE window's
  /// own).
  String get _ideFolder => _ideWindow
      ? widget.window!.folder ?? _noFolder
      : _workspace.ideFolder ?? _noFolder;
  IdeWorkbenchState? get _ide => _ideKeys[_ideFolder]?.currentState;

  AppWindows? get _windows => widget.windows;

  /// Whether the IDE has windows of its own.
  bool get _multi => _windows?.multi ?? false;

  /// Whether this is one of them.
  bool get _ideWindow => _multi && !(widget.window?.isChat ?? true);

  /// Whether this is the app's main window, the chat's: what the app does
  /// once (its notifications, the system's requests, the File menu) is
  /// done here.
  bool get _main => !_ideWindow;

  int get _viewId => widget.window?.viewId ?? 0;

  /// Whether the IDE shows: always in its own window; without them, as the
  /// workspace's layout says.
  bool get _showsIde =>
      _ideWindow || (!_multi && _workspace.layout == WorkspaceLayout.ide);

  WindowSettings get _windowSettings =>
      WindowSettings.parse(widget.settings?.files?.settings.values ?? const {});

  /// Whether ⌘ (Ctrl) is held: a folder or file picked then opens in a new
  /// window.
  static bool get _newWindowHeld {
    final keyboard = HardwareKeyboard.instance;
    return defaultTargetPlatform == TargetPlatform.macOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
  }

  /// Whether the keyboard is in this window (each window's workbench sees
  /// every key).
  bool get _hasKeyboard {
    if (!_multi) return true;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null && focus.mounted) {
      final view = focus.findAncestorWidgetOfExactType<View>();
      if (view != null) return view.view.viewId == _viewId;
    }
    return WindowControls.activeViewId == _viewId;
  }

  /// The window is kept above other apps' windows.
  bool _pinned = false;

  /// An agent dragged from the sidebar onto the conversations.
  late final ChatDrag _drag = ChatDrag(onDrop: _drop, onStart: _closeDrawer);

  void _setPinned(bool pinned) {
    setState(() => _pinned = pinned);
    WindowControls.setAlwaysOnTop(pinned, viewId: _viewId);
  }

  /// Back in the app, the list picks up sessions started elsewhere (e.g.
  /// in a terminal) meanwhile.
  AppLifecycleListener? _lifecycle;

  /// Notifies of the agents that want the user, keeps the count on the
  /// app's icon and the tray icon (see lib/notifications/): the main
  /// window's, once for the app. One picked shows in the IDE window it is
  /// a tab of, else here.
  late final AttentionService? _attention = _main
      ? AttentionService(
          workspace: _workspace,
          host: ChannelAttentionHost.instance,
          settings: () => AttentionSettings.parse(
            widget.settings?.files?.settings.values ?? const {},
          ),
          settingsChanges: widget.settings?.files?.settings,
          l10n: () => context.l10n,
          shown: _workspace.isShown,
          onOpen: (thread) => _windows != null
              ? _windows!.showAgent(thread)
              : _openNotifiedAgent(thread),
        )
      : null;

  /// The keybindings the buttons' tooltips show (`New Agent (⌘N)`): they
  /// follow a keymap picked, keybindings.json edited.
  late final KeybindingService _keybindings = KeybindingService.instance;

  void _keybindingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
    _keybindings.addListener(_keybindingsChanged);
    // The window's own channels: its menu bar's commands (the key window's,
    // on macOS), its Edit menu, its buttons, the files dropped on it.
    WindowControls.setMenuCommands(_viewId, _runMenuCommand);
    WindowControls.handleEditCommands(_viewId);
    WindowControls.handleWindowEvents(_viewId);
    FileDrops.listen(_viewId);
    if (_windows?.started ?? false) {
      FileDrops.setUnhandledDrop(_viewId, _dropped);
    }
    widget.window?.attach(this);
    _windows?.addListener(_windowsChanged);
    if (_main) {
      OpenRequests.listen((paths) => unawaited(_openPaths(paths)));
      _workspace.addListener(_syncRecentMenu);
      _syncRecentMenu();
      _lifecycle = AppLifecycleListener(
        onResume: () => unawaited(_workspace.refresh()),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
    }
    widget.settings?.files?.changes.addListener(_settingsFilesChanged);
    _settingsFilesChanged();
  }

  /// The IDE moved to windows of its own (`window.ideWindows`): the main
  /// window's goes, its editors, terminals and language servers with it.
  void _windowsChanged() {
    if (!_multi || _ideWindow || _ideSpaces.isEmpty) return;
    final spaces = _ideSpaces.values.toList();
    setState(() {
      _ideSpaces.clear();
      _ideKeys.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final space in spaces) {
        space.dispose();
      }
    });
  }

  /// Files dropped on the window where nothing in it takes them: opened
  /// as the `code` command opens them.
  bool _dropped(List<ComposerFile> files) =>
      _windows?.dropped(_viewId, files) ?? false;

  bool _attentionStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Once the app's language is in scope; the tray's menu follows it.
    if (_attentionStarted) {
      _attention?.refresh();
    } else {
      _attentionStarted = true;
      _attention?.start();
    }
  }

  /// What the app asks once it shows: whether to remove what a move of
  /// the data folder left behind, then (once ever) whether to import
  /// another editor's keybindings; one after the other.
  Future<void> _afterFirstFrame() async {
    final settings = widget.settings;
    if (settings?.files == null || !mounted) return;
    await offerOldDataDirRemoval(context);
    if (!mounted) return;
    await settings!.offerImport(context);
  }

  @override
  void dispose() {
    _citedCode?.dispose();
    _drag.dispose();
    _width.dispose();
    _lifecycle?.dispose();
    _attention?.dispose();
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _keybindings.removeListener(_keybindingsChanged);
    // The window's channels stay: a folder replaced builds the next
    // workbench before this one goes, and AppWindows stops them with the
    // window.
    if (WindowControls.menuCommandsOf(_viewId) == _runMenuCommand) {
      WindowControls.setMenuCommands(_viewId, null);
    }
    if (FileDrops.unhandledDropOf(_viewId) == _dropped) {
      FileDrops.setUnhandledDrop(_viewId, null);
    }
    widget.window?.detach(this);
    _windows?.removeListener(_windowsChanged);
    _editedTimer?.cancel();
    for (final subscription in _editedSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _chordTimer?.cancel();
    if (_main) {
      OpenRequests.stop();
      _workspace.removeListener(_syncRecentMenu);
    }
    widget.settings?.files?.changes.removeListener(_settingsFilesChanged);
    _notifications.dispose();
    for (final index in _fileIndexes.values) {
      index.dispose();
    }
    for (final ide in _ideSpaces.values) {
      ide.dispose();
    }
    super.dispose();
  }

  // --- Settings files ------------------------------------------------------

  /// The workbench's own notifications, over both layouts: a settings file
  /// that does not parse.
  final IdeNotifications _notifications = IdeNotifications();

  /// The error last told of, per file, whether its notification is still
  /// open or not; and those open.
  final Map<JsoncFile, String> _fileErrorsTold = {};
  final Map<JsoncFile, IdeNotification> _fileErrorNotes = {};

  /// A settings file that stops parsing is told of once per error (what
  /// was last read from it stays in effect); fixed, its notification goes.
  void _settingsFilesChanged() {
    final files = widget.settings?.files;
    if (files == null) return;
    for (final file in files.userFiles) {
      final error = file.error;
      if (error == null) {
        _fileErrorsTold.remove(file);
        if (_fileErrorNotes.remove(file) case final note?) {
          _notifications.close(note);
        }
        continue;
      }
      if (_fileErrorsTold[file] == error) continue;
      _fileErrorsTold[file] = error;
      late final IdeNotification note;
      note = _notifications.notify(
        IdeSeverity.error,
        context.l10n.settingsFileError(p.basename(file.path), error),
        source: file.path,
        sticky: true,
        onClose: () {
          if (identical(_fileErrorNotes[file], note)) {
            _fileErrorNotes.remove(file);
          }
        },
      );
      _fileErrorNotes[file] = note;
    }
  }

  // --- Keybindings ---------------------------------------------------------

  /// The commands the chat layout runs itself, those it can now (the IDE
  /// runs its own, and [_settingsCommands] besides; a chat, its own: see
  /// [ChatKeys]).
  Map<String, VoidCallback> _chatCommands() {
    final current = _workspace.current;
    // One agent alone is the one pane.
    final panes = _workspace.grid.isEmpty ? [?current] : _workspace.grid.panes;
    final agents = _agentsInOrder();
    return {
      'workbench.action.toggleSidebarVisibility': _toggle,
      openSettingsCommandId: () => unawaited(openSettings()),
      openKeybindingsCommandId: () =>
          unawaited(openSettings(SettingsSection.keyboard)),
      // As the sidebar's New Agent button: a folder first, without one.
      if (_workspace.projects.isNotEmpty)
        ChatCommandIds.newChat: _newAgent
      else if (WindowControls.canPickDirectory)
        ChatCommandIds.newChat: () => unawaited(_openFolder()),
      if (current != null && panes.length > 1)
        ChatCommandIds.closePane: () => _workspace.closePane(current),
      if (agents.isNotEmpty) ...{
        ChatCommandIds.nextAgent: () => _openAgentBy(1),
        ChatCommandIds.previousAgent: () => _openAgentBy(-1),
      },
      for (final (index, thread)
          in agents.take(ChatCommandIds.agentIndexes).indexed)
        '${ChatCommandIds.openAgentAtIndex}${index + 1}': () =>
            _openAgent(thread),
      for (final (index, thread) in panes.indexed)
        '${ChatCommandIds.focusPane}${index + 1}': () => _openAgent(thread),
      if (panes.length > 1) ...{
        ChatCommandIds.focusNextPane: () => _focusPaneBy(1),
        ChatCommandIds.focusPreviousPane: () => _focusPaneBy(-1),
      },
      ChatCommandIds.searchAgents: _searchAgents,
      ChatCommandIds.search: () => unawaited(_openPalette()),
      if (widget.customizations != null) _customizeCommand: _showCustomize,
      if (current != null)
        ChatCommandIds.openIde: () => _workspace.openInIde(current),
      ..._windowCommands(),
    };
  }

  /// New Window, Close Window, Switch Window… and Show Chat Window, where
  /// the app has windows (the IDE in the main one: New Window shows its
  /// empty window there, Show Chat Window the chat).
  Map<String, VoidCallback> _windowCommands() {
    final windows = _windows;
    final window = widget.window;
    if (windows == null || window == null || !windows.started) {
      return const {};
    }
    return {
      WindowCommandIds.newWindow: () => unawaited(windows.newWindow()),
      WindowCommandIds.closeWindow: () => unawaited(
        windows.requestClose(
          window,
          // A menu clicked, or a shortcut (its keys still down).
          byKeyboard: HardwareKeyboard.instance.logicalKeysPressed.isNotEmpty,
        ),
      ),
      WindowCommandIds.switchWindow: () => windows.switchWindow(window),
      WindowCommandIds.showChat: () {
        if (windows.multi) return windows.showChat();
        windows.focus(window);
        _workspace.layout = WorkspaceLayout.chat;
      },
    };
  }

  /// Reaches the sidebar, for the agents it lists and its search.
  final SidebarLink _sidebarLink = SidebarLink();

  /// The agents as the sidebar lists them, top to bottom; without it, as it
  /// would by date (pinned ones first, no archived ones).
  List<AgentThread> _agentsInOrder() {
    if (_sidebarLink.visibleThreads case final threads?) return threads;
    final threads = [
      for (final thread in _workspace.threads)
        if (!thread.archived && _workspace.listsInSidebar(thread)) thread,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [
      ...threads.where((thread) => thread.pinned),
      ...threads.where((thread) => !thread.pinned),
    ];
  }

  /// Opens [thread] (in the focused pane, unless it is shown in one) and
  /// focuses its input.
  void _openAgent(AgentThread thread) {
    _closeDrawer();
    _closeCustomize();
    if (!identical(thread, _workspace.current)) _workspace.select(thread);
    _focusChat(thread);
  }

  /// An agent picked in a notification or the tray's menu: in the IDE's
  /// chat while the IDE shows (its folder's IDE, if another shows), else as
  /// the sidebar opens it.
  void _openNotifiedAgent(AgentThread thread) {
    if (_workspace.layout != WorkspaceLayout.ide) return _openAgent(thread);
    final folder = thread.project.path;
    if (folder != _ideFolder) _openIdeFolder(folder);
    _openIdeChat(folder, thread);
    _afterBuild(() => _ide?.showChat());
  }

  /// The agent [step] away from the current one in the sidebar's order,
  /// round from the end.
  void _openAgentBy(int step) {
    final threads = _agentsInOrder();
    if (threads.isEmpty) return;
    final at = threads.indexWhere(
      (thread) => identical(thread, _workspace.current),
    );
    final next = at < 0
        ? (step > 0 ? 0 : threads.length - 1)
        : (at + step) % threads.length;
    _openAgent(threads[next]);
  }

  /// The pane [step] away from the focused one, row by row, round.
  void _focusPaneBy(int step) {
    final panes = _workspace.grid.panes;
    if (panes.length < 2) return;
    final at = panes.indexWhere(
      (thread) => identical(thread, _workspace.current),
    );
    _openAgent(panes[((at < 0 ? 0 : at) + step) % panes.length]);
  }

  void _newAgent() {
    _closeDrawer();
    _closeCustomize();
    _focusChat(_workspace.create());
  }

  /// The search palette, on its agents.
  void _searchAgents() => unawaited(_openPalette(SearchFilter.agents));

  // --- Search and Customize ---------------------------------------------------

  /// Customize's command, for the palette.
  static const _customizeCommand = 'baocode.chat.customize';

  /// Claude Code's customizations show in place of the chat.
  bool _customizing = false;
  CustomizationKind _customizeKind = CustomizationKind.skills;
  final GlobalKey<CustomizeViewState> _customizeKey = GlobalKey();

  void _showCustomize([CustomizationKind? kind]) {
    _closeDrawer();
    if (kind != null) _customizeKey.currentState?.show(kind);
    setState(() {
      _customizing = true;
      if (kind != null) _customizeKind = kind;
    });
  }

  void _closeCustomize() {
    if (_customizing) setState(() => _customizing = false);
  }

  bool _paletteOpen = false;

  /// The ids of the palette's actions last run, the last first.
  final List<String> _recentActions = [];

  /// Each project's files, for the palette: listed again as it opens.
  final Map<String, IdeFileIndex> _fileIndexes = {};

  /// The project the palette's files are of: the current agent's, else the
  /// first listed.
  Project? get _paletteProject =>
      _workspace.current?.project ?? _workspace.sidebarProjects.firstOrNull;

  /// Opens the search palette over the chat layout, on [filter].
  Future<void> _openPalette([SearchFilter filter = SearchFilter.all]) async {
    if (_paletteOpen || !mounted) return;
    _paletteOpen = true;
    try {
      _closeDrawer();
      final project = _paletteProject;
      final files = project == null
          ? null
          : _fileIndexes.putIfAbsent(
              project.path,
              () => IdeFileIndex(IdeFileService(project.path), project.path),
            );
      await showSearchPalette(
        context,
        agents: [
          for (final thread
              in _workspace.threads.toList()
                ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
            if (_workspace.listsInSidebar(thread) && !thread.untouched) thread,
        ],
        conversations: widget.conversations,
        files: files,
        actions: _paletteActions(),
        recentActions: List.of(_recentActions),
        settings: _paletteSettings(),
        filter: filter,
        onOpenAgent: _openAgent,
        onOpenFile: (path) {
          if (_windows case final windows? when _multi) {
            unawaited(
              windows.showFolder(project?.path, files: [CodeTarget(path)]),
            );
            return;
          }
          if (project != null) _openIdeFolder(project.path);
          _openIdeFiles([path]);
        },
        onRunAction: (action) {
          _recentActions
            ..remove(action.id)
            ..insert(0, action.id);
          if (_recentActions.length > 5) _recentActions.removeLast();
          action.run();
        },
      );
    } finally {
      _paletteOpen = false;
    }
  }

  /// The window's commands the palette runs, as they can be now.
  List<PaletteAction> _paletteActions() {
    final l10n = context.l10n;
    final commands = _chatCommands();
    PaletteAction? action(String id, IconData icon, [VoidCallback? run]) {
      final command = run ?? commands[id];
      if (command == null) return null;
      return PaletteAction(
        id: id,
        label: id == _customizeCommand
            ? l10n.sidebarCustomize
            : localizedCommandLabel(l10n, id, commandCatalog[id]?.title ?? id),
        icon: icon,
        keybinding: ChatKeys.keyLabel(id, ChatKeys.chatLayout),
        run: command,
      );
    }

    return [
      ?action(ChatCommandIds.newChat, Codicons.add),
      ?action(_customizeCommand, Codicons.extensions),
      ?action(openSettingsCommandId, Codicons.settingsGear),
      ?action(openKeybindingsCommandId, Codicons.keyboard),
      ?action(
        'workbench.action.toggleSidebarVisibility',
        Codicons.layoutSidebarLeft,
      ),
      ?action(ChatCommandIds.openIde, Codicons.code),
      if (WindowControls.canPickDirectory)
        ?action(
          'workbench.action.files.openFolder',
          Codicons.folderOpened,
          () => unawaited(_openFolder()),
        ),
      ?action(ChatCommandIds.nextAgent, Codicons.arrowDown),
      ?action(ChatCommandIds.previousAgent, Codicons.arrowUp),
      ?action(ChatCommandIds.focusNextPane, Codicons.arrowRight),
      ?action(ChatCommandIds.focusPreviousPane, Codicons.arrowLeft),
      ?action(ChatCommandIds.closePane, Codicons.close),
    ];
  }

  /// The settings' pages, and Customize's, for the palette.
  List<PaletteAction> _paletteSettings() {
    final l10n = context.l10n;
    return [
      for (final section in SettingsSection.values)
        PaletteAction(
          id: 'settings.${section.name}',
          label: SettingsDialogState.label(context, section),
          icon: SettingsDialogState.icon(section),
          run: () => unawaited(openSettings(section)),
        ),
      if (widget.customizations != null)
        for (final kind in CustomizationKind.values)
          PaletteAction(
            id: 'customize.${kind.name}',
            label: '${l10n.sidebarCustomize}: ${kind.label(l10n)}',
            icon: kind.icon,
            run: () => _showCustomize(kind),
          ),
    ];
  }

  /// Focuses [thread]'s input once its chat is built.
  void _focusChat(AgentThread thread) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ChatScreen.focusInput(_chatKey(thread));
    });
  }

  /// The settings' commands, for the IDE's palette and keybindings.
  late final List<IdeCommand> _settingsCommands = [
    IdeCommand(
      id: openSettingsCommandId,
      category: 'Preferences',
      label: 'Open Settings',
      run: () => unawaited(openSettings()),
    ),
    IdeCommand(
      id: openKeybindingsCommandId,
      category: 'Preferences',
      label: 'Open Keyboard Shortcuts',
      run: () => unawaited(openSettings(SettingsSection.keyboard)),
    ),
  ];

  /// The chords of a sequence typed so far (⌘K of ⌘K ⌘S).
  List<KeyChord>? _pendingChords;
  Timer? _chordTimer;

  /// A key in the chat layout, from anywhere, the composer included (which
  /// swallows other shortcuts): a keyboard handler sees every key first.
  /// It runs a window command its keybinding resolves to (see
  /// [KeybindingService]), or a chat's: that of the focus (which runs it
  /// itself, after an open menu has had the key), or the current agent's
  /// where the focus is in none (the sidebar). The IDE resolves its own
  /// keys.
  bool _handleKey(KeyEvent event) {
    if (event is KeyUpEvent ||
        _showsIde ||
        KeyChord.fromEvent(event) == null ||
        !mounted ||
        !_hasKeyboard) {
      return false;
    }
    // A dialog over the window (the settings' key recorder) keeps its keys.
    if (!(ModalRoute.isCurrentOf(context) ?? true)) {
      _leaveChord();
      return false;
    }
    // So does an input method composing text.
    if (ChatKeys.isComposing) return false;
    final focused = ChatKeys.focusedTargets();
    final chat = focused.isNotEmpty
        ? focused
        : switch (_workspace.current) {
            final thread? => ChatKeys.targetsOf(
              _chatKey(thread).currentContext,
            ),
            null => const <ChatKeyTarget>[],
          };
    final window = _chatCommands();
    final chatCommands = ChatKeys.commandsOf(chat);
    final pending = _pendingChords;
    final result = KeybindingService.instance.resolveEvent(
      event,
      pending: pending ?? const [],
      context: ChatKeys.lookupOf(chat, _chatKeyContext),
      canRun: (item) =>
          window.containsKey(item.command) ||
          chatCommands.containsKey(item.command),
    );
    _leaveChord();
    switch (result) {
      case KeybindingFound(:final command):
        if (window[command] case final run?) {
          ChatKeys.markHandled(event);
          run();
          return true;
        }
        // The focused chat's own, after its open menu (see ChatKeys).
        if (focused.isNotEmpty && pending == null) return false;
        ChatKeys.markHandled(event);
        chatCommands[command]!();
        return true;
      case MoreChordsNeeded(:final chords):
        ChatKeys.markHandled(event);
        _pendingChords = chords;
        _chordTimer = Timer(const Duration(seconds: 5), _leaveChord);
        return true;
      case NoKeybinding():
        // Upstream swallows a second key that completes nothing.
        if (pending == null) return false;
        ChatKeys.markHandled(event);
        return true;
    }
  }

  void _leaveChord() {
    _pendingChords = null;
    _chordTimer?.cancel();
    _chordTimer = null;
  }

  /// The context keys of the chat layout.
  Object? _chatKeyContext(String key) {
    final focus = FocusManager.instance.primaryFocus;
    return switch (key) {
      'chatMode' => true,
      'ideMode' => false,
      'inputFocus' || 'textInputFocus' =>
        focus?.context?.findAncestorStateOfType<EditableTextState>() != null,
      _ => null,
    };
  }

  /// Those of the IDE's chat.
  static Object? _ideChatKeyContext(String key) => switch (key) {
    'chatMode' => false,
    'ideMode' => true,
    _ => null,
  };

  /// A command of the system's menu bar: the app menu's Preferences…, and
  /// the File menu's, which are the IDE's (Open Folder… in the chat layout
  /// is its own, a project there). The window's own: New Window, Close
  /// Window.
  void _runMenuCommand(String command) {
    if (command == openSettingsCommandId) {
      unawaited(openSettings());
      return;
    }
    if (_windowCommands()[command] case final run?) {
      run();
      return;
    }
    final chat = !_showsIde;
    if (chat && command == 'workbench.action.files.openFolder') {
      unawaited(_openFolder());
      return;
    }
    if (_ideCommandsFor(_ideFolder).where((c) => c.id == command).firstOrNull
        case final host? when !(chat && _multi && _inIdeWindow(command))) {
      host.run();
      return;
    }
    if (_multi && chat) {
      // The IDE's own, in its window last in front (an empty one, if none).
      final windows = _windows!;
      unawaited(() async {
        final window = await windows.showFolder(null);
        (await window?.ready)?.runCommand(command);
      }());
      return;
    }
    if (_ideWindow) {
      _ide?.runCommand(command);
      return;
    }
    // The IDE's own (New Text File, Save, Save As…): once it shows.
    _workspace.layout = WorkspaceLayout.ide;
    _afterBuild(() => _ide?.runCommand(command));
  }

  /// The host's commands the chat's window has the IDE's window run: those
  /// over the IDE (Open Recent's pick).
  static bool _inIdeWindow(String command) =>
      command == 'workbench.action.openRecent';

  /// Runs [action] once the frame being scheduled is built.
  void _afterBuild(VoidCallback action) {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  // --- The IDE's files and folders --------------------------------------------

  /// The host's commands for the IDE of [folder]: the settings', the files'
  /// and folders', its chat's, the shell command's. The same list each
  /// time, so its keybindings are registered once.
  List<IdeCommand> _ideCommandsFor(String folder) =>
      _ideCommands.putIfAbsent(folder, () {
        IdeCommand command(String id, VoidCallback run, {bool enabled = true}) {
          final info = commandCatalog[id];
          return IdeCommand(
            id: id,
            category: info?.category,
            label: info?.title ?? id,
            enabled: enabled,
            run: run,
          );
        }

        return [
          ..._settingsCommands,
          command(
            'workbench.action.files.openFile',
            () => unawaited(_pickIdeFiles()),
            enabled: WindowControls.canPickFiles,
          ),
          command(
            'workbench.action.files.openFolder',
            () => unawaited(_pickIdeFolder()),
            enabled: WindowControls.canPickDirectory,
          ),
          command('workbench.action.openRecent', _showOpenRecent),
          command(
            'workbench.action.clearRecentlyOpened',
            () => unawaited(_clearRecent()),
          ),
          for (final MapEntry(key: id, value: run) in _windowCommands().entries)
            command(id, run),
          if (folder != _noFolder) ...[
            command('workbench.action.closeFolder', _closeIdeFolder),
            IdeCommand(
              id: ChatCommandIds.newChat,
              label: 'New Chat',
              category: 'Chat',
              run: () => _newIdeChat(folder),
            ),
            IdeCommand(
              id: ChatCommandIds.closeTab,
              label: 'Close Chat',
              category: 'Chat',
              run: () => _closeIdeChat(folder),
            ),
          ],
          if (ShellCommand.supported) ...[
            command(
              installShellCommandId,
              () => unawaited(_shellCommand(installShellCommand)),
            ),
            command(
              uninstallShellCommandId,
              () => unawaited(_shellCommand(uninstallShellCommand)),
            ),
          ],
        ];
      });

  /// Shows [folder] in the IDE. With windows of its own: in this one, in
  /// place of its folder (its unsaved files asked about first), unless
  /// ⌘ (Ctrl) was [held] or `window.openFoldersInNewWindow` says a new
  /// one; from the chat's window, in the folder's (opened, if it is not).
  void _openIdeFolder(String folder, {bool held = false}) {
    if (_multi) {
      final windows = _windows!;
      if (_ideWindow && !_windowSettings.folderInNewWindow(held: held)) {
        unawaited(windows.replaceFolder(widget.window!, folder));
      } else {
        unawaited(windows.showFolder(folder));
      }
      return;
    }
    _workspace.openIdeFolder(folder);
    _workspace.layout = WorkspaceLayout.ide;
  }

  /// Close Folder: an IDE window's, its welcome in its place.
  void _closeIdeFolder() {
    if (_ideWindow) {
      unawaited(_windows!.replaceFolder(widget.window!, null));
      return;
    }
    _workspace.closeIdeFolder();
  }

  Future<void> _pickIdeFolder() async {
    final held = _newWindowHeld;
    final path = await WindowControls.pickDirectory();
    if (path == null || !mounted) return;
    _openIdeFolder(path, held: held);
  }

  /// Opens [paths] in editors of the IDE's folder (or its empty window).
  /// With windows of its own: in this one, unless ⌘ (Ctrl) was [held] or
  /// `window.openFilesInNewWindow` says a new one; from the chat's window,
  /// as the `code` command opens them.
  void _openIdeFiles(List<String> paths, {bool held = false}) {
    if (paths.isEmpty) return;
    if (_multi) {
      final targets = [for (final path in paths) CodeTarget(path)];
      final newWindow = _windowSettings.fileInNewWindow(held: held);
      if (_ideWindow && !newWindow) {
        paths.forEach(_workspace.addRecentFile);
        unawaited(openFiles(targets));
      } else {
        unawaited(_windows!.openFiles(targets, newWindow: newWindow));
      }
      return;
    }
    paths.forEach(_workspace.addRecentFile);
    _workspace.layout = WorkspaceLayout.ide;
    _afterBuild(() async {
      for (final path in paths) {
        await _ide?.openFile(path);
      }
    });
  }

  Future<void> _pickIdeFiles() async {
    final held = _newWindowHeld;
    final paths = await WindowControls.pickOpenFiles(
      directory: _ideFolder == _noFolder ? null : _ideFolder,
    );
    if (!mounted) return;
    _openIdeFiles(paths, held: held);
  }

  /// What the system asks to open (the `code` command, Finder's Open With,
  /// the File menu's Open Recent): folders and files alike in the IDE,
  /// whichever the main window is; the chat is left as it was. With the
  /// app's windows, as they open them (see [AppWindows.openRequested]).
  Future<void> _openPaths(List<String> paths) async {
    if (_windows case final windows?) return windows.openRequested(paths);
    final folders = <String>[];
    final files = <String>[];
    for (final path in paths) {
      (await isDirectory(path) ? folders : files).add(path);
    }
    if (!mounted) return;
    // One window, one folder: the last given.
    if (folders.lastOrNull case final folder?) _openIdeFolder(folder);
    _openIdeFiles(files);
  }

  /// The IDE's Open Recent: the folders and files it opened, to open again.
  void _showOpenRecent() {
    final ide = _ide;
    if (ide == null) return;
    final l10n = context.l10n;
    IdeQuickPickItem item(
      String path,
      IconData icon,
      VoidCallback open, {
      bool opened = false,
    }) => IdeQuickPickItem(
      label: p.basename(path).isEmpty ? path : p.basename(path),
      description: opened
          ? '${p.dirname(path)}  ·  ${l10n.windowOpened}'
          : p.dirname(path),
      icon: Icon(icon),
      onAccept: open,
    );
    // With the IDE's windows, those open are marked; picked, they come
    // in front.
    final windows = _multi ? _windows : null;
    final folders = [
      for (final folder in _workspace.recentFolders)
        if (folder != _ideFolder)
          item(
            folder,
            Codicons.folder,
            () => _openIdeFolder(folder, held: _newWindowHeld),
            opened: windows?.windowFor(folder) != null,
          ),
    ];
    final files = [
      for (final file in _workspace.recentFiles)
        item(
          file,
          Codicons.file,
          () => _openIdeFiles([file], held: _newWindowHeld),
        ),
    ];
    ide.showQuickPick(
      IdeQuickPick(
        items: [
          if (folders.isEmpty && files.isEmpty)
            IdeQuickPickItem(label: l10n.ideNoRecent),
          if (folders.isNotEmpty) ...[
            IdeQuickPickSeparator(l10n.ideRecentFolders),
            ...folders,
          ],
          if (files.isNotEmpty) ...[
            IdeQuickPickSeparator(l10n.ideRecentFiles),
            ...files,
          ],
        ],
        placeholder: l10n.ideOpenRecentPlaceholder,
        matchOnDescription: true,
        sortByLabel: false,
        onDidAccept: (item) => item?.onAccept?.call(),
      ),
    );
  }

  Future<void> _clearRecent() async {
    final l10n = context.l10n;
    final choice = await showIdeDialog(
      context,
      message: l10n.ideClearRecentConfirm,
      detail: l10n.ideClearRecentDetail,
      buttons: [l10n.ideClearRecent],
    );
    if (choice == 0) _workspace.clearRecent();
  }

  /// Installs or removes the shell command, and tells how that went.
  Future<void> _shellCommand(
    Future<ShellCommandOutcome?> Function(BuildContext) action,
  ) async {
    final outcome = await action(context);
    if (outcome == null || !mounted) return;
    final ide = _ide;
    if (ide != null && _showsIde) {
      ide.notify(outcome.severity, outcome.message);
    } else {
      _notifications.notify(outcome.severity, outcome.message);
    }
  }

  /// Asks where to save [doc] of [space] (Save As…, an untitled file's
  /// first save): where it is, or in the folder; noted among the recent.
  Future<String?> _askSavePath(IdeWorkspace space, IdeDocument doc) async {
    final path = await WindowControls.pickSaveFile(
      directory: doc.isUntitled
          ? (space.hasFolder ? space.root : null)
          : p.dirname(doc.path),
      name: doc.isUntitled ? doc.path : p.basename(doc.path),
    );
    if (path != null) _workspace.addRecentFile(path);
    return path;
  }

  /// The macOS File menu's Open Recent, as the IDE's.
  List<String> _recentMenu = const [];
  void _syncRecentMenu() {
    final recent = [
      ..._workspace.recentFolders.take(_recentMenuItems),
      ..._workspace.recentFiles.take(_recentMenuItems),
    ];
    if (listEquals(recent, _recentMenu)) return;
    _recentMenu = recent;
    unawaited(WindowControls.setRecentItems(recent));
  }

  static const _recentMenuItems = 10;

  /// The macOS File menu's titles, in the language they were last set in.
  String? _fileMenuLocale;
  void _syncFileMenu(AppLocalizations l10n) {
    if (_fileMenuLocale == l10n.localeName) return;
    _fileMenuLocale = l10n.localeName;
    unawaited(
      WindowControls.setFileMenuTitles({
        'file': l10n.menuFile,
        'newUntitledFile': l10n.cmdNewUntitledFile,
        'openFile': l10n.cmdOpenFile,
        'openFolder': l10n.cmdOpenFolder,
        'openRecent': l10n.cmdOpenRecent,
        'save': l10n.cmdSave,
        'saveAs': l10n.cmdSaveAs,
        'closeFolder': l10n.cmdCloseFolder,
        'clearRecent': l10n.cmdClearRecentlyOpened,
        'more': l10n.menuMore,
        'newWindow': l10n.cmdNewWindow,
        'closeWindow': l10n.menuCloseWindow,
      }),
    );
  }

  // --- The IDE's chat ----------------------------------------------------------

  void _newIdeChat(String folder) => _focusChat(_workspace.newIdeChat(folder));

  /// Closes [folder]'s chat tab shown; the keyboard goes to the one shown
  /// next, so ⌘W goes on closing them.
  void _closeIdeChat(String folder) {
    final current = _workspace.ideChat(folder);
    if (current == null) return;
    _workspace.closeIdeChat(folder, current);
    if (_workspace.ideChat(folder) case final next?) _focusChat(next);
  }

  void _openIdeChat(String folder, AgentThread thread) {
    _workspace.openIdeChat(folder, thread);
    _focusChat(thread);
  }

  /// The IDE's chat in [folder]: its tabs over the one shown. Without a
  /// folder, a way to open one.
  Widget _buildIdeChat(String folder) {
    if (folder == _noFolder) {
      return _IdeNoFolderChat(
        onOpenFolder: WindowControls.canPickDirectory
            ? () => unawaited(_pickIdeFolder())
            : null,
      );
    }
    final current = _workspace.ideChat(folder);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IdeChatTitle(
          tabs: _workspace.ideChats(folder),
          threads: [
            for (final thread in _workspace.threads)
              if (thread.project.path == folder) thread,
          ],
          current: current,
          onNew: () => _newIdeChat(folder),
          onOpen: (thread) => _openIdeChat(folder, thread),
          onClose: (threads) => _workspace.closeIdeChats(folder, threads),
          onPin: (thread) => _workspace.setPinned(thread, !thread.pinned),
          onMove: (thread, index) =>
              _workspace.moveIdeChat(folder, thread, index),
        ),
        Expanded(
          child: current == null
              ? const SizedBox.shrink()
              : _buildChat(showToggle: false, embedded: true, pane: current),
        ),
      ],
    );
  }

  bool _settingsOpen = false;

  /// Opens the settings dialog on [section].
  Future<void> openSettings([
    SettingsSection section = SettingsSection.general,
  ]) async {
    if (_settingsOpen || !mounted) return;
    _settingsOpen = true;
    _closeDrawer();
    try {
      await showSettingsDialog(
        context,
        section: section,
        pageBuilder: (context, section) =>
            widget.settings?.buildPage(context, section) ??
            const SizedBox.shrink(),
      );
    } finally {
      _settingsOpen = false;
    }
  }

  void _toggle() {
    setState(() {
      if (_narrow) {
        _drawerClosing = _drawerOpen;
        _drawerOpen = !_drawerOpen;
      } else {
        _docked = !_docked;
      }
    });
  }

  void _closeDrawer() {
    if (!_drawerOpen) return;
    setState(() {
      _drawerOpen = false;
      _drawerClosing = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_main) _syncFileMenu(context.l10n);
    return LayoutBuilder(
      builder: (context, constraints) {
        _windowWidth = constraints.maxWidth;
        final narrow = constraints.maxWidth < Workbench.narrowWidth;
        if (narrow != _narrow) {
          _narrow = narrow;
          // Crossing the breakpoint never leaves a drawer over the chat.
          _drawerOpen = false;
          _drawerClosing = false;
        }
        // The text style (and ink) for what is not inside a panel's own:
        // the empty workspace, the dragged agent over the window.
        return Material(
          color: AppColors.windowCanvas,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The header too: it opens the current session's project.
              ListenableBuilder(
                listenable: _workspace,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Windows draws its own header over both columns (see
                    // window_header/); elsewhere the system's is above them.
                    if (WindowControls.drawsHeader) _buildHeader(),
                    Expanded(child: _buildContent(narrow)),
                  ],
                ),
              ),
              ChatDragLayer(drag: _drag),
              // As the IDE's toasts: above its status bar.
              Positioned(
                right: 8,
                bottom: _showsIde ? 36 : 12,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.max(0, constraints.maxWidth - 16),
                  ),
                  child: IdeNotificationToasts(notifications: _notifications),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(bool narrow) {
    final folder = _ideFolder;
    // An IDE window has its folder's alone.
    if (_ideWindow) return _buildIde(folder, _ideSpace(folder), shown: true);
    final ide = _showsIde;
    if (ide) _ideSpace(folder);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final MapEntry(key: path, value: space) in _ideSpaces.entries)
          _buildIde(path, space, shown: ide && path == folder),
        if (!ide) narrow ? _buildNarrow() : _buildWide(),
      ],
    );
  }

  /// The IDE of [path] (see [_ideSpace]), kept built while another shows.
  Widget _buildIde(String path, IdeWorkspace space, {required bool shown}) {
    return Offstage(
      key: ValueKey(path),
      offstage: !shown,
      child: TickerMode(
        enabled: shown,
        child: ExcludeFocus(
          excluding: !shown,
          child: IdeWorkbench(
            key: _ideKeys.putIfAbsent(path, GlobalKey.new),
            workspace: space,
            project: path == _noFolder
                ? Project.at(space.root)
                : _workspace.projectAt(path),
            visible: shown,
            // An IDE window's way back shows the chat's window.
            onBack: _ideWindow
                ? _windows!.showChat
                : () => _workspace.layout = WorkspaceLayout.chat,
            backLabel: _ideWindow ? context.l10n.cmdShowChatWindow : null,
            pinned: _pinned,
            onPinnedChanged: _setPinned,
            editorBuilder: widget.ideEditorBuilder,
            ignoredRecommendations: _workspace.ignoredServerRecommendations,
            onIgnoreRecommendation: _workspace.ignoreServerRecommendation,
            colorThemes: WorkbenchThemeService.instance,
            commands: _ideCommandsFor(path),
            recentFolders: _workspace.recentFolders,
            onOpenRecent: (folder) =>
                _openIdeFolder(folder, held: _newWindowHeld),
            settings: widget.settings?.files?.settings,
            viewState: _workspace.ideView(path),
            onViewState: path == _noFolder
                ? null
                : (state) => _workspace.keepIdeView(path, state),
            terminalBackend:
                widget.terminalBackend ??
                const TerminalBackend(supported: false),
            chat: shown
                ? _conversation(_buildIdeChat(path))
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Widget _buildWide() {
    // Built once for the widths a drag goes through (see [_width]).
    final sidebar = _buildSidebar();
    final panes = _buildPanes(showToggle: !_docked);
    final row = ValueListenableBuilder(
      valueListenable: _width,
      builder: (context, _, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedContainer(
            duration: _dragging ? Duration.zero : _duration,
            curve: Curves.easeOutCubic,
            width: _docked ? _shownWidth : 0,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerRight,
                minWidth: _shownWidth,
                maxWidth: _shownWidth,
                child: sidebar,
              ),
            ),
          ),
          // One backdrop for both: two, meeting at a fractional x (a dragged
          // width), would each half cover the pixel there, and the material
          // would show through the seam.
          Expanded(
            child: _conversation(
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_docked) _buildResizeHandle(),
                  Expanded(child: panes),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [row, if (_dragging) _resizeCursorLayer],
    );
  }

  Widget _buildNarrow() {
    // The same sidebar and border as when docked, at the same width.
    const handleWidth = _WorkbenchState._handleWidth;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: _conversation(_buildPanes(showToggle: true))),
        // Scrim: a click outside closes the drawer.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_drawerOpen,
            child: GestureDetector(
              onTap: _closeDrawer,
              child: AnimatedOpacity(
                opacity: _drawerOpen ? 1 : 0,
                duration: _duration,
                // Black, not the theme's: as upstream's modal backdrops.
                child: const ColoredBox(color: Color(0x66000000)),
              ),
            ),
          ),
        ),
        // Only the slide animates; the width follows the drag or the window
        // at once (animating it too would leave the sidebar overflowing its
        // box while the window grows).
        ValueListenableBuilder(
          valueListenable: _width,
          builder: (context, _, sidebar) => TweenAnimationBuilder<double>(
            tween: Tween(end: _drawerOpen ? 1 : 0),
            duration: _duration,
            curve: Curves.easeOutCubic,
            onEnd: () {
              if (_drawerClosing) setState(() => _drawerClosing = false);
            },
            builder: (context, shown, child) => Positioned(
              top: 0,
              bottom: 0,
              left: -(_shownWidth + handleWidth + 24) * (1 - shown),
              width: _shownWidth + handleWidth,
              child: child!,
            ),
            child: sidebar == null
                ? const SizedBox.shrink()
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: _shownWidth, child: sidebar),
                      _buildResizeHandle(),
                    ],
                  ),
          ),
          // Built once for the widths a drag goes through (see [_width]).
          child: _drawerOpen || _drawerClosing
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: themeColors['widget.shadow'],
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  // Over the chat, not the material: the tint alone would
                  // show the chat through.
                  child: _opaque(_buildSidebar(onOpened: _closeDrawer)),
                )
              : null,
        ),
        if (_dragging) _resizeCursorLayer,
      ],
    );
  }

  /// While resizing, the pointer may be far from the border: the resize
  /// cursor everywhere, and no hover effects under it.
  static const _resizeCursorLayer = MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
  );

  /// On the window's own color: over the system's material (see
  /// [AppColors.windowCanvas]), opaque.
  static Widget _opaque(Widget child) =>
      ColoredBox(color: AppColors.background, child: child);

  /// On the conversation's color: over the material, a tint of it.
  static Widget _conversation(Widget child) =>
      ColoredBox(color: AppColors.conversationSurface, child: child);

  Widget _buildSidebar({VoidCallback? onOpened}) {
    return Sidebar(
      workspace: _workspace,
      link: _sidebarLink,
      onCollapse: _toggle,
      onOpened: () {
        _closeCustomize();
        onOpened?.call();
      },
      onOpenFolder: WindowControls.canPickDirectory ? _openFolder : null,
      onOpenSettings: () => unawaited(openSettings()),
      onSearch: () => unawaited(_openPalette()),
      onCustomize: widget.customizations == null
          ? null
          : () => _customizing ? _closeCustomize() : _showCustomize(),
      customizing: _customizing,
      drag: _drag,
    );
  }

  /// The bar Windows draws itself, over the sidebar and the chat (see
  /// window_header/): the sidebar toggle, the menus, the pin, the editor
  /// button and the window buttons, all of which are in the columns
  /// themselves elsewhere.
  /// The IDE's workspace for [folder], made the first time it is shown
  /// (the header, built first, may be the first to ask). Without a folder
  /// ([_noFolder]), it is in the home folder, with no language servers
  /// or Git.
  IdeWorkspace _ideSpace(String folder) => _ideSpaces.putIfAbsent(folder, () {
    final space = folder == _noFolder
        ? IdeWorkspace(homeDirectory ?? p.current, hasFolder: false)
        : IdeWorkspace(
            folder,
            languages: widget.languagesFor?.call(folder),
            git: widget.gitFor?.call(folder),
          );
    // The parts as the last run left them, before anything shows them.
    if (_workspace.ideView(folder) case final kept?) {
      space.layout
        ..terminals = (widget.terminalBackend?.supported ?? false)
        ..restore(kept);
    }
    if (_ideWindow) _trackEdited(space);
    return space..askSavePath = (doc) => _askSavePath(space, doc);
  });

  // --- Unsaved files -----------------------------------------------------------

  Timer? _editedTimer;
  final Map<Object, StreamSubscription<Object?>> _editedSubscriptions = {};

  /// An IDE window shows whether it has unsaved files (the dot in macOS'
  /// close button): followed as [space]'s files open and close, and as
  /// they are typed in.
  void _trackEdited(IdeWorkspace space) {
    void changed() {
      _editedTimer?.cancel();
      _editedTimer = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _windows?.setEdited(
          widget.window!,
          space.documents.any((doc) => doc.dirty),
        );
      });
    }

    void follow() {
      final models = {for (final doc in space.documents) doc.model};
      _editedSubscriptions.removeWhere((model, subscription) {
        if (models.contains(model)) return false;
        unawaited(subscription.cancel());
        return true;
      });
      for (final model in models) {
        _editedSubscriptions[model] ??= model.changes.listen((_) => changed());
      }
      changed();
    }

    space.addListener(follow);
  }

  Widget _buildHeader() {
    final ide = _showsIde;
    final project = ide
        ? switch (_ideFolder) {
            _noFolder => null,
            final folder => _workspace.projectAt(folder),
          }
        : _workspace.current?.project;
    final windows = _multi ? _windows : null;
    return WindowHeader(
      workspace: _workspace,
      project: project,
      ide: ide,
      hasFolder: _ideFolder != _noFolder,
      onBack: _ideWindow ? windows!.showChat : null,
      backLabel: _ideWindow ? context.l10n.cmdShowChatWindow : null,
      onNewWindow: windows == null
          ? null
          : () => unawaited(windows.newWindow()),
      onCloseWindow: windows == null
          ? null
          : _windowCommands()[WindowCommandIds.closeWindow],
      sidebarShown: _narrow ? _drawerOpen : _docked,
      onToggleSidebar: _toggle,
      ideLayout: ide ? _ideSpace(_ideFolder).layout : null,
      pinned: _pinned,
      onTogglePin: _setPinned,
      onOpenFolder: _openFolder,
      onOpenSettings: () => unawaited(openSettings()),
      onToggleContextPanel: () {
        if (_workspace.current case final thread?) {
          ChatScreen.toggleContextPanel(_chatKey(thread));
        }
      },
      onCommand: (command) => _chatCommands()[command]?.call(),
      onFileCommand: _runMenuCommand,
    );
  }

  /// The chat of [thread]: a state of its own for each (and kept as it
  /// moves between the wide and narrow layouts), reached by the header.
  /// Each window's own: the same agent may show in two.
  GlobalKey _chatKey(AgentThread thread) => _chatKeys[thread] ??= GlobalKey();
  final Expando<GlobalKey> _chatKeys = Expando();

  void _endDrag() {
    setState(() {
      _dragging = false;
      _dragOrigin = null;
    });
  }

  /// The border between sidebar and chat, draggable to resize.
  Widget _buildResizeHandle() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        // Its clicks stay its own (not the drawer's scrim, under it).
        behavior: HitTestBehavior.opaque,
        // From the press, not from where the drag was recognized, so the
        // border stays under the pointer.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (details) => setState(() {
          _dragging = true;
          _dragOrigin = (x: details.globalPosition.dx, width: _shownWidth);
        }),
        // Where the pointer is relative to where it was pressed, not the
        // sum of the moves: past the min or max the border waits there, and
        // follows again only once the pointer is back at it.
        onHorizontalDragUpdate: (details) {
          final origin = _dragOrigin!;
          _width.value = (origin.width + details.globalPosition.dx - origin.x)
              .clamp(math.min(Workbench.minSidebarWidth, _maxWidth), _maxWidth);
        },
        onHorizontalDragEnd: (_) => _endDrag(),
        onHorizontalDragCancel: _endDrag,
        // At rest the border line; dragged, as thick as the IDE's sashes,
        // in their `sash.hoverBorder`.
        child: Container(
          width: _handleWidth,
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: _dragging ? IdeModernUI.gap : 1,
            color: _dragging ? IdeModernUI.sashHover : AppColors.border,
          ),
        ),
      ),
    );
  }

  Future<void> _openFolder() async {
    final path = await WindowControls.pickDirectory();
    if (path == null || !mounted) return;
    await _workspace.openFolder(path);
    _closeDrawer();
  }

  /// The open agents side by side (see [ChatGridView]).
  Widget _buildPanes({required bool showToggle}) {
    if (_customizing) {
      if (widget.customizations case final store?) {
        return _buildCustomize(store, showToggle: showToggle);
      }
    }
    final grid = _workspace.grid;
    if (grid.isEmpty) return _buildChat(showToggle: showToggle);
    return ChatGridView(
      grid: grid,
      drag: _drag,
      onFocus: (thread) {
        if (!identical(thread, _workspace.current)) _workspace.select(thread);
      },
      paneBuilder: (context, thread, place) =>
          _buildChat(showToggle: showToggle, pane: thread, place: place),
      onLinesMoved: _workspace.keepGridLines,
    );
  }

  /// Customize, in place of the conversations: its title bar as a chat's,
  /// the sidebar's toggle by the traffic lights while it is hidden.
  Widget _buildCustomize(CustomizationStore store, {required bool showToggle}) {
    final header = WindowControls.drawsHeader;
    return CustomizeView(
      key: _customizeKey,
      store: store,
      projects: _workspace.sidebarProjects,
      project: _paletteProject,
      kind: _customizeKind,
      onClose: _closeCustomize,
      leading: !header && showToggle
          ? SidebarIconButton(
              icon: Codicons.layoutSidebarLeftOff,
              tooltip: context.l10n.windowShowSidebar,
              command: 'workbench.action.toggleSidebarVisibility',
              onTap: _toggle,
            )
          : null,
      titleBarInset: !header && showToggle
          ? AppMetrics.trafficLightsWidth + 8
          : 12.0,
      onOpenFile: (path) => _openIdeFiles([path]),
    );
  }

  /// An agent dragged from the sidebar, released over the conversations.
  void _drop(ChatDrop drop) {
    final growth = drop.growth;
    if (growth != Size.zero) {
      // Wide enough, the window would dock the sidebar, which would take
      // the room made: it stays out of the way, as it was.
      if (_narrow && _windowWidth + growth.width >= Workbench.narrowWidth) {
        setState(() => _docked = false);
      }
      unawaited(WindowControls.grow(growth));
    }
    if (drop.side case final side?) {
      _workspace.openBeside(drop.thread, drop.target, side);
    } else {
      _workspace.openInPlaceOf(drop.target, drop.thread);
    }
  }

  /// A pane that is the whole of the conversations.
  static const ChatPanePlace _whole = (
    topLeft: true,
    topRight: true,
    top: true,
    alone: true,
  );

  /// The chat of [pane] (by default the current agent), at [place] among
  /// the others.
  Widget _buildChat({
    required bool showToggle,
    bool embedded = false,
    AgentThread? pane,
    ChatPanePlace place = _whole,
  }) {
    final thread = pane ?? _workspace.current;
    // Windows keeps the toggle, the pin and the editor button in its header
    // (see window_header/): all that is left for this row is the session's
    // title, which then sits in the middle of it. Elsewhere the toggle is
    // in the top left pane, by the traffic lights, and the pin and the
    // editor button in the top right one.
    final header = WindowControls.drawsHeader;
    showToggle = showToggle && place.topLeft;
    final leading = !header && showToggle
        ? SidebarIconButton(
            icon: Codicons.layoutSidebarLeftOff,
            tooltip: context.l10n.windowShowSidebar,
            command: 'workbench.action.toggleSidebarVisibility',
            onTap: _toggle,
          )
        : null;
    final titleBarInset = header
        ? 12.0
        : showToggle
        ? AppMetrics.trafficLightsWidth + 8
        : 12.0;
    if (thread == null) {
      return _EmptyWorkspace(
        loading: _workspace.loading,
        leading: leading,
        titleBarInset: titleBarInset,
        onOpenFolder: WindowControls.canPickDirectory ? _openFolder : null,
      );
    }
    final windowTools = !header && !embedded && place.topRight;
    // The window's, in whichever pane is top right: they are the focused
    // agent's (Fast Ide opens it), and a click on them leaves the focus
    // where it is. So does closing another pane.
    final tools = [
      if (windowTools) ...[
        PinWindowButton(pinned: _pinned, onChanged: _setPinned),
        const SizedBox(width: 6),
        OpenInEditorButton(
          workspace: _workspace,
          project: (_workspace.current ?? thread).project,
        ),
      ],
      if (!place.alone) ...[
        if (windowTools) const SizedBox(width: 6),
        // With Close Pane's keys, which close the focused pane: as each of
        // upstream's tabs titles its close button with Close's.
        SidebarIconButton(
          icon: Codicons.close,
          tooltip: context.l10n.workspaceClosePane,
          command: ChatCommandIds.closePane,
          onTap: () => _workspace.closePane(thread),
        ),
      ],
    ];
    // The layout's context keys, for the chat's keybindings (see ChatKeys).
    return ChatKeyScope(
      lookup: embedded ? _ideChatKeyContext : _chatKeyContext,
      child: ChatScreen(
        key: _chatKey(thread),
        embedded: embedded,
        session: thread.session,
        title: thread.localizedTitle(context.l10n),
        autofocus: thread.session.itemCount == 0,
        onRename: (title) => _workspace.rename(thread, title),
        // Beside the sidebar, the traffic lights are over it, not here.
        titleBarInset: titleBarInset,
        leading: leading,
        trailing: tools.isEmpty
            ? null
            : KeepPaneFocus(
                child: Row(mainAxisSize: MainAxisSize.min, children: tools),
              ),
        windowTitleBar: place.top,
        focused: place.alone || identical(thread, _workspace.current),
        onOpenChange: (change, original) =>
            _openChange(thread, change, original),
        onOpenCode: (path, start, end) => _openCode(thread, path, start, end),
        colorizeCode: _colorizeCode,
        // Where a new agent is to work: the IDE's chat works in the IDE's
        // project, and a kept session where it was.
        start: embedded || thread.record != null
            ? null
            : NewChatFolderBar(workspace: _workspace, thread: thread),
      ),
    );
  }

  /// Opens a file [thread]'s agent changed in the IDE: a diff of its text
  /// before the agent changed it ([original]) against the file, the text
  /// alone where the agent deleted it, or the file where that is unknown.
  void _openChange(
    AgentThread thread,
    FileChange change,
    Future<String> Function()? original,
  ) {
    final label = context.l10n.stripChangesDiff;
    _inIdeOf(
      thread,
      (ide) => switch ((original, change.kind)) {
        (null, _) => ide.open(change.path),
        (final read?, FileChangeKind.deleted) => ide.openRevision(
          change.path,
          label: label,
          read: read,
        ),
        (final read?, _) => ide.openDiff(
          change.path,
          label: label,
          original: read,
        ),
      },
    );
  }

  /// Shows [thread] in the IDE (its project's window, with the IDE's
  /// windows), the tab of its chat there, then [open]s in its workspace.
  void _inIdeOf(
    AgentThread thread,
    Future<Object?> Function(IdeWorkspace ide) open,
  ) {
    if (_windows case final windows? when _multi) {
      unawaited(() async {
        final window = await windows.showFolder(
          thread.project.path,
          thread: thread,
        );
        if ((await window?.ready)?.ideSpace case final ide?) await open(ide);
      }());
      return;
    }
    _workspace.openInIde(thread);
    unawaited(open(_ideSpace(thread.project.path)));
  }

  /// Opens a file [thread]'s agent cited in the IDE, lines [start] to
  /// [end] (from 1) selected.
  void _openCode(AgentThread thread, String path, int start, int end) {
    final range = LspRange(
      LspPosition(start - 1, 0),
      // To the end of the line: positions keep to theirs.
      LspPosition(end - 1, 1 << 30),
    );
    _inIdeOf(thread, (ide) => ide.openAt(path, range));
  }

  // --- For AppWindows (WindowDelegate) -------------------------------------------

  @override
  BuildContext? get windowContext => mounted ? context : null;

  @override
  IdeWorkspace? get ideSpace => _showsIde ? _ideSpace(_ideFolder) : null;

  @override
  Future<void> openFiles(List<CodeTarget> files) async {
    if (!_showsIde) _workspace.layout = WorkspaceLayout.ide;
    setState(() {});
    // Once the IDE shows.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final space = _ideSpace(_ideFolder);
    for (final file in files) {
      if (file.line case final line?) {
        final at = LspPosition(
          math.max(0, line - 1),
          math.max(0, (file.column ?? 1) - 1),
        );
        await space.openAt(file.path, LspRange(at, at));
      } else {
        await _ide?.openFile(file.path);
      }
    }
  }

  @override
  void showAgent(AgentThread thread) {
    if (_ideWindow) {
      _openIdeChat(_ideFolder, thread);
      _afterBuild(() => _ide?.showChat());
    } else if (_multi) {
      _openAgent(thread);
    } else {
      _openNotifiedAgent(thread);
    }
  }

  @override
  void showIdeFolder(String? folder) {
    if (folder == null) {
      _workspace.layout = WorkspaceLayout.ide;
    } else {
      _openIdeFolder(folder);
    }
  }

  @override
  Future<List<IdeDocument>> unsavedDocuments() async {
    for (final key in _ideKeys.values) {
      await key.currentState?.flush();
    }
    return [
      for (final space in _ideSpaces.values)
        ...space.documents.where((doc) => doc.dirty),
    ];
  }

  @override
  Future<bool> saveDocuments(List<IdeDocument> documents) async {
    try {
      for (final doc in documents) {
        for (final space in _ideSpaces.values) {
          if (space.documents.contains(doc)) await space.save(doc);
        }
      }
    } catch (error) {
      if (mounted) {
        _notifications.notify(IdeSeverity.error, '$error');
      }
      return false;
    }
    // An untitled one whose Save As was cancelled is still there.
    return !_ideSpaces.values.any(
      (space) =>
          space.documents.any((doc) => doc.dirty && documents.contains(doc)),
    );
  }

  @override
  bool terminalsRunning({required bool childProcesses}) => _ideKeys.values.any(
    (key) =>
        key.currentState?.terminalsRunning(childProcesses: childProcesses) ??
        false,
  );

  @override
  void showQuickPick(IdeQuickPick pick) {
    if (_ide case final ide? when _showsIde) {
      ide.showQuickPick(pick);
      return;
    }
    // The chat's window: over it, as the IDE shows one.
    var closed = false;
    unawaited(
      showGeneralDialog<void>(
        context: context,
        barrierColor: Colors.transparent,
        pageBuilder: (context, _, _) => Padding(
          padding: EdgeInsets.only(
            top: WindowControls.drawsHeader ? 0 : AppMetrics.titleBarHeight,
          ),
          child: IdeQuickInput.pick(
            pick: pick,
            onClose: () {
              if (closed) return;
              closed = true;
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
    );
  }

  @override
  void runCommand(String command) => _runMenuCommand(command);

  /// The code agents cite in the editor's colors, by TextMate: started as
  /// the first is shown.
  TextMateSyntax? _citedCode;

  Future<List<List<TextSpan>>?> _colorizeCode(String path, String code) async {
    final syntax = _citedCode ??= TextMateSyntax(
      themes: WorkbenchThemeService.instance,
    );
    final language = await syntax.languageIdForPath(path);
    return language == null ? null : syntax.colorize(language, code);
  }
}

/// The IDE's chat without a folder: one to open first, as agents work in
/// one.
class _IdeNoFolderChat extends StatelessWidget {
  const _IdeNoFolderChat({this.onOpenFolder});

  final VoidCallback? onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Codicons.commentDiscussion,
              size: 26,
              color: AppColors.textFaint,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.ideChatNoFolder,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            if (onOpenFolder case final open?) ...[
              const SizedBox(height: 16),
              // As wide as its label: a centred column would stretch it.
              IntrinsicWidth(
                child: PanelButton(
                  label: l10n.explorerOpenFolder,
                  primary: true,
                  onTap: open,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// In place of a chat while there is no project: open one, or wait for
/// the kept ones to load. On the web, where agents cannot run, says so.
class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace({
    required this.loading,
    required this.titleBarInset,
    this.leading,
    this.onOpenFolder,
  });

  final bool loading;
  final double titleBarInset;
  final Widget? leading;
  final VoidCallback? onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (title, detail) = loading
        ? (l10n.workspaceLoadingProjects, '')
        : onOpenFolder == null
        ? (l10n.workspaceDesktopOnly, l10n.workspaceDesktopOnlyDetail)
        : (
            l10n.workspaceOpenProjectFolder,
            l10n.workspaceOpenProjectFolderDetail,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Nothing to put in it (Windows keeps the toggle in its header):
        // the empty state starts at the top instead of under an empty row.
        if (leading case final leading?)
          TitleBarDoubleClick(
            child: SizedBox(
              height: AppMetrics.titleBarHeight,
              child: Padding(
                padding: EdgeInsets.only(left: titleBarInset),
                child: Row(children: [leading]),
              ),
            ),
          ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  size: 26,
                  color: AppColors.textFaint,
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                  ),
                ],
                if (onOpenFolder case final open? when !loading) ...[
                  const SizedBox(height: 16),
                  // As wide as its label: a centred column would stretch it.
                  IntrinsicWidth(
                    child: PanelButton(
                      label: l10n.sidebarOpenFolder,
                      primary: true,
                      onTap: open,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
