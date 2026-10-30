import 'dart:async';
import 'dart:math' as math;

import 'package:bao_editor/textmate/textmate_syntax.dart';
import 'package:bao_remote/client.dart' show SshPrompt;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'browser/browser_bridge.dart';
import 'browser/browser_tools.dart';
import 'browser/browser_welcome.dart';
import 'images/image_tools.dart';
import 'channel/channel_setup.dart';
import 'channel/channel_gate.dart';
import 'channel/channel_setup_welcome.dart';
import 'chat/chat_keys.dart';
import 'chat/chat_models.dart' show FileChange, FileChangeKind;
import 'chat/chat_screen.dart';
import 'chat/chat_session.dart' show ChatSession;
import 'chat/composer/composer_files.dart' show CodeReference, ComposerFile;
import 'chat/composer/composer_mock_data.dart' show Suggestion;
import 'chat/composer/file_drop.dart';
import 'chat/composer/file_mentions.dart';
import 'chat/open_editor.dart';
import 'chat/panels/interaction_panel.dart';
import 'chat/side_panel/file_open.dart';
import 'chat/side_panel/file_preview.dart' show FilePreview;
import 'chat/side_panel/side_panel_controller.dart';
import 'chat/side_panel/side_panel_view.dart';
import 'chat/side_panel/web_page_opener.dart';
import 'customize/customization_store.dart';
import 'customize/customizations.dart';
import 'customize/customize_view.dart';
import 'extensions/theme_extensions.dart';
import 'ide/editor_word_wrap.dart';
import 'ide/git/git_model.dart' show ideWorktreeOf;
import 'ide/git/git_repository.dart';
import 'ide/git/ide_git_clone_dialog.dart';
import 'ide/git/ide_git_log_view.dart' show IdeGitWorktreeChoice;
import 'ide/git/repository_scan.dart';
import 'ide/file_views.dart';
import 'ide/file_service.dart'
    show
        IdeFileService,
        byteSizeThrough,
        IdeHostFiles,
        ideIsImagePath,
        readBytesThrough,
        readFileBytes;
import 'ide/ide_agent_edits.dart';
import 'ide/ide_chat_history.dart';
import 'ide/ide_chat_title.dart';
import 'ide/ide_color_theme_picker.dart';
import 'ide/ide_commands.dart';
import 'ide/ide_dialog.dart';
import 'ide/ide_menu.dart';
import 'models/model_welcome.dart';
import 'models/upstream_import.dart';
import 'ide/ide_modern_ui.dart';
import 'ide/ide_notifications.dart';
import 'ide/git/commit_message.dart';
import 'ide/ide_quick_input.dart';
import 'ide/ide_quick_open.dart';
import 'ide/ide_welcome.dart' show IdeRecentWorkspace;
import 'ide/ide_workbench.dart';
import 'ide/search/text_search.dart' show ideSearchText;
import 'ide/ide_workspace.dart';
import 'ide/lsp/language_features.dart';
import 'ide/lsp/lsp_protocol.dart';
import 'ide/lsp/packs/lsp_settings_template.dart';
import 'ide/terminal/links/terminal_links.dart';
import 'ide/terminal/terminal_instance.dart';
import 'ide/terminal/terminal_panel.dart' show terminalCommandsToSkipShell;
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
import 'platform/data_dir.dart' show DataDirectory;
import 'platform/event_log.dart' show appEvent;
import 'platform/local_paths.dart'
    if (dart.library.io) 'platform/local_paths_io.dart';
import 'platform/open_requests.dart';
import 'platform/shell_command.dart';
import 'search/conversation_search.dart';
import 'search/search_palette.dart';
import 'settings/app_settings.dart';
import 'settings/data_dir_startup.dart';
import 'settings/jsonc_file.dart';
import 'settings/pages/diagnostics_dialog.dart';
import 'settings/pages/models_page.dart';
import 'settings/pages/upstream_import_dialog.dart';
import 'settings/settings_dialog.dart';
import 'settings/shell_command_actions.dart';
import 'sidebar/sidebar.dart';
import 'theme/code_font.dart';
import 'theme/codicons.dart';
import 'icons/project_icon_view.dart';
import 'theme/app_theme.dart';
import 'theme/workbench_theme.dart' show WorkbenchThemeService, themeColors;
import 'tips/feature_tip.dart';
import 'tips/feature_tips_controller.dart';
import 'tips/feature_tips_view.dart';
import 'tips/star_prompt.dart';
import 'window/app_windows.dart';
import 'window/code_args.dart';
import 'window/window_settings.dart';
import 'remote/open_remote.dart';
import 'remote/project_host.dart';
import 'remote/remote_customization_disk.dart';
import 'remote/remote_files.dart';
import 'remote/remote_location.dart';
import 'remote/remote_status.dart';
import 'remote/ssh_host.dart';
import 'remote/ssh_password_dialog.dart';
import 'remote/ssh_passwords.dart';
import 'stash/stash_controller.dart';
import 'stash/stash_thread_view.dart' show sidebarStashes;
import 'stash/stash_view.dart';
import 'stash/stash_welcome.dart' show showStashWelcome;
import 'workspace/agent_work_path.dart';
import 'workspace/chat_branch_bar.dart';
import 'workspace/chat_quota_bar.dart';
import 'workspace/chat_drag.dart';
import 'workspace/chat_grid_view.dart';
import 'workspace/chat_terminal.dart';
import 'workspace/terminal_deck.dart';
import 'workspace/editor_launcher.dart' show openExternal;
import 'workspace/ssh_server_edit.dart';
import 'workspace/new_chat_folder_bar.dart';
import 'workspace/open_in_editor_button.dart';
import 'workspace/pin_window_button.dart';
import 'workspace/project_workspace.dart' show ProjectWorkspace;
import 'workspace/title_bar_double_click.dart';
import 'workspace/window_controls.dart';
import 'workspace/window_header/window_header.dart';
import 'workspace/workspace.dart';
import 'workspace/workspace_dialog.dart';

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

/// This machine's files, for what is shown as a file in the IDE (see
/// FileOpenScope.showLocal).
final IdeFileService _localFiles = IdeFileService(p.current);

class Workbench extends StatefulWidget {
  const Workbench({
    super.key,
    required this.workspace,
    this.ideEditorBuilder,
    this.languagesFor,
    this.themeExtensions,
    this.gitFor,
    this.repositoriesIn,
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

  /// The installed theme extensions, which the IDE's Extensions view lists
  /// and installs; no Extensions view when null.
  final ThemeExtensions? themeExtensions;

  /// The Git repository of the project at a root, when the IDE opens it;
  /// none when null.
  final IdeGitRepository Function(String root)? gitFor;

  /// The repositories in a folder's subfolders, by path on its host,
  /// for the IDE's Source Control (`git.autoRepositoryDetection`); none
  /// looked for when null.
  final Future<List<String>> Function(String folder, IdeRepositoryScan scan)?
  repositoriesIn;

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
  /// strip) stays in it; with the side panel beside it, short of what the
  /// conversations and the panel take at their least.
  double get _maxWidth => math.min(
    Workbench.maxSidebarWidth,
    _windowWidth -
        (_bothSides ? _sidePanelRoom : Workbench.sidebarWindowMargin),
  );

  double get _shownWidth => _width.value.clamp(
    math.min(Workbench.minSidebarWidth, _maxWidth),
    _maxWidth,
  );
  bool _dragging = false;

  /// Pointer and sidebar width when the resize drag began.
  ({double x, double width})? _dragOrigin;

  /// Shown beside the chat (wide window), as asked; see [_sidebarDocked].
  bool _docked = true;

  /// The least the conversations and the side panel take at the sidebar's
  /// right: its border, theirs and their minimums.
  static const _sidePanelRoom =
      _handleWidth +
      AgentSidePanelArea.minChat +
      AgentSidePanelArea.sashWidth +
      AgentSidePanel.minWidth;

  /// Whether the side panel was asked for after the docked sidebar: where
  /// the window has not the room for both, the one asked for last stays and
  /// the other gives way, as the IDE's side bar and chat do (see
  /// [IdeLayout]); the panel at first, as the IDE's chat. One that gave
  /// way to the other asked for stays hidden until asked for again; one
  /// that gave way to a narrow window is back as it widens.
  bool _sidePanelLast = true;

  /// [AgentSidePanel.asks] as last seen.
  int _sidePanelAsks = 0;

  /// The side panel shown for a conversation, beside the docked sidebar:
  /// the window's, or (agents side by side) the focused pane's.
  bool get _sidePanelWanted =>
      _sidePanel.isShown && (_agentThread ?? _workspace.current) != null;

  /// Whether the window has the docked sidebar, at its least, beside the
  /// conversations and the side panel, at theirs.
  bool get _roomForSides =>
      _windowWidth - _sidePanelRoom >= Workbench.minSidebarWidth;

  /// Both asked for in a wide window too narrow for the two.
  bool get _sidesClash =>
      !_narrow && _docked && _sidePanelWanted && !_roomForSides;

  /// Whether the sidebar is docked, not having given way to the side panel.
  bool get _sidebarDocked => _docked && !(_sidesClash && _sidePanelLast);

  /// Whether the side panel gave way to the docked sidebar.
  bool get _sidePanelHidden => _sidesClash && !_sidePanelLast;

  /// Whether the side panel and the docked sidebar both show.
  bool get _bothSides =>
      !_narrow && _docked && _sidePanelWanted && !_sidesClash;

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

  /// Each hidden IDE as last built: built again only once shown. A hidden
  /// one is still laid out, and the window rebuilds with every change to
  /// the workspace (an agent's status, its title, its diff).
  final Map<String, ({IdeWorkspace space, Widget ide})> _hiddenIdes = {};

  /// The agents' changes each folder's IDE shows in its files.
  final Map<String, IdeAgentEdits> _ideAgentEdits = {};
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
  bool get _ideWindow => _multi && (widget.window?.isIde ?? false);

  /// Whether this is an agent's window (Explorer's Open with BaoCode): its
  /// conversation alone, [_agentThread]'s.
  bool get _agentWindow => widget.window?.isAgent ?? false;
  AgentThread? get _agentThread => _agentWindow ? widget.window!.thread : null;

  /// Whether this is the app's main window, the chat's: what the app does
  /// once (its notifications, the system's requests, the File menu) is
  /// done here.
  bool get _main => !_ideWindow && !_agentWindow;

  int get _viewId => widget.window?.viewId ?? 0;

  /// Whether the IDE shows: always in its own window; without them, as the
  /// workspace's layout says.
  bool get _showsIde =>
      _ideWindow ||
      (!_multi && !_agentWindow && _workspace.layout == WorkspaceLayout.ide);

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

  /// The terminals under the conversations, in the focused agent's
  /// project (see [ChatTerminals]); none where they cannot run, nor in an
  /// IDE window (the IDE has its own).
  late final ChatTerminals? _terminals = switch (widget.terminalBackend) {
    final backend? when backend.supported && !_ideWindow => ChatTerminals(
      backend,
      rootOf: () => (_agentThread ?? _workspace.current)?.project.path,
      // A remote project's on its host.
      backendFor: (location) => ProjectHost.of(location).terminals(backend),
      // A workspace's in its first folder (its own is only its settings).
      pathOf: (location) => switch (_workspace.workspaceAt(location)) {
        final multi? => multi.folders.firstOrNull ?? location,
        null => RemoteLocation.pathOf(location),
      },
    )..onLastClosed = _focusCurrentChat,
    _ => null,
  }?..addListener(_terminalsChanged);

  /// The title bars' toggles and the window's commands follow them.
  void _terminalsChanged() {
    if (!_terminalTipRaised && (_terminals?.shown ?? false)) {
      _terminalTipRaised = true;
      if (_tips case final tips?) {
        unawaited(tips.scenario(TipScenarios.openedTerminal));
      }
    }
    if (mounted) setState(() {});
  }

  /// The panel at the right of the conversations: the focused agent's
  /// changes and the files opened from its conversation (see
  /// [AgentSidePanel]), shown and as wide as the last run left it.
  late final AgentSidePanel _sidePanel =
      AgentSidePanel(
          state: _workspace.sidePanelView,
          onSave: () => _workspace.keepSidePanelView(_sidePanel.toJson()),
          settings: widget.settings?.files?.settings,
        )
        ..pane = (() => _panesSidePanels ? _workspace.current?.session : null)
        ..addListener(_sidePanelChanged);

  /// Whether agents side by side each have a side panel of their own,
  /// beside their pane (see [AgentSidePanel.pane]): not one window's
  /// beside them all.
  bool get _panesSidePanels =>
      _agentThread == null && !_replacingChat && _workspace.grid.length > 1;
  bool _sidePanelShown = false;
  late bool _sidePanelAtLeft = _sidePanel.atLeft;

  /// Whether the side panel shows at the conversations' left: at the
  /// window's, the sidebar's toggle by the traffic lights is its.
  bool get _sidePanelAtWindowLeft =>
      _sidePanelShown &&
      !_sidePanelHidden &&
      !_replacingChat &&
      _sidePanelAtLeft;

  /// The title bars' toggles follow it (not its width, as it is dragged).
  /// Asked for where it had given way, or with no room for it and the
  /// docked sidebar, it stays and the sidebar gives way (see
  /// [_sidePanelLast]).
  void _sidePanelChanged() {
    final asked = _sidePanel.asks != _sidePanelAsks;
    if (_sidePanel.isShown == _sidePanelShown &&
        _sidePanel.atLeft == _sidePanelAtLeft &&
        !asked) {
      // Each pane's own, shown or hidden: their panes built anew.
      if (_panesSidePanels && mounted) setState(() {});
      return;
    }
    _sidePanelAtLeft = _sidePanel.atLeft;
    if (asked) {
      _sidePanelAsks = _sidePanel.asks;
      // Showing already, the sidebar gives way only to a narrower window.
      final shown = _sidePanelShown && !_sidePanelHidden;
      _sidePanelLast = true;
      if (!shown && _sidesClash) _docked = false;
    }
    _sidePanelShown = _sidePanel.isShown;
    if (mounted) setState(() {});
  }

  /// Toggle Side Panel, as the title bars' toggles show it: shown where it
  /// gave way, it is asked for again. Of agents side by side, the focused
  /// one's.
  void _toggleSidePanel() => _sidePanel.isShown && !_sidePanelHidden
      ? _sidePanel.hide()
      : _sidePanel.show();

  /// Whether the side panel shows for [thread]: of agents side by side, its
  /// pane's own; else the window's, the focused agent's.
  bool _sidePanelShownFor(AgentThread thread) => _panesSidePanels
      ? _sidePanel.shownIn(thread.session) && !_sidePanelHidden
      : _sidePanelShown &&
            !_sidePanelHidden &&
            (_agentThread != null || identical(thread, _workspace.current));

  /// [thread]'s pane's side panel: hidden where it is its agent's already,
  /// else shown for it, focused first.
  void _toggleSidePanelOf(AgentThread thread) {
    if (_agentThread == null && !identical(thread, _workspace.current)) {
      _workspace.select(thread);
    }
    if (_panesSidePanels) {
      return _sidePanel.setShownIn(thread.session, !_sidePanelShownFor(thread));
    }
    _sidePanelShownFor(thread) ? _sidePanel.hide() : _sidePanel.show();
  }

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
    // What signing in to a host asks, asked here.
    SshHosts.instance.passwords.ask = _askSshPassword;
    // The servers saved with the host picker's form.
    SshHosts.instance.savedServers = () => _workspace.sshServers;
    unawaited(_loadSshConfigHosts());
    FileDrops.listen(_viewId);
    if (_windows?.started ?? false) {
      FileDrops.setUnhandledDrop(_viewId, _dropped);
    }
    widget.window?.attach(this);
    _windows?.addListener(_windowsChanged);
    if (_main) {
      // A link to a stash (#12 references) shows it here.
      StashController.current?.showPage = _showStash;
      // A stash's file opens as the Stash page shows it.
      if (StashController.current case final stash?) {
        FileViews.register(stashFileView(stash, onOpenAgent: _openAgent));
      }
      // A web page a chat links to opens in the browser.
      FileViews.registerOpener(webPageOpener);
      // The user's browsers, for agents (see browser_bridge.dart).
      unawaited(BrowserTools.start());
      // Pictures, for agents, while an image model is turned on.
      ImageTools.start();
      OpenRequests.listen((paths) => unawaited(_openPaths(paths)));
      _workspace.addListener(_syncRecentMenu);
      _syncRecentMenu();
      _lifecycle = AppLifecycleListener(
        onResume: () => unawaited(_workspace.refresh()),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
      _stopUpdateOffers = widget.settings?.updates?.listen(
        _notifications,
        () => context.l10n,
      );
    } else if (ChannelGate.current case final gate? when !gate.ready) {
      // Opened before the main window's was done: here as well.
      WidgetsBinding.instance.addPostFrameCallback((_) => _setUpChannel());
    }
    // Signed out (Settings → Account, or by the site): the welcome again.
    ChannelGate.current?.addListener(_channelGateChanged);
    widget.settings?.files?.changes.addListener(_settingsFilesChanged);
    _settingsFilesChanged();
    _sidePanelShown = _sidePanel.isShown;
    _sidePanelAsks = _sidePanel.asks;
    _workspace.addListener(_restoreSidePanel);
    _restoreSidePanel();
    _workspace.addListener(_syncWorkspaceFolders);
  }

  /// The IDE and side panel of a multi-folder workspace show the folders
  /// it has now.
  void _syncWorkspaceFolders() {
    for (final MapEntry(key: folder, value: space) in _ideSpaces.entries) {
      if (_workspace.workspaceAt(folder) case final multi?) {
        space.roots = multi.folders;
      }
    }
    for (final multi in _workspace.workspaces) {
      _sidePanel.setRoots(multi.path, multi.folders);
    }
  }

  /// Create Workspace...: asks for its name and folders, then opens it in
  /// the IDE ([inIde]) or has a new agent work in it.
  Future<void> _createWorkspace({bool inIde = false}) async {
    final made = await showWorkspaceDialog(context, workspace: _workspace);
    if (made == null || !mounted) return;
    if (inIde) {
      _openIdeFolder(made.path);
    } else {
      unawaited(_workspace.openFolder(made.path));
    }
  }

  /// Add Folder to Workspace...: one picked in the file manager.
  Future<void> _addWorkspaceFolder(String location) async {
    final path = await WindowControls.pickDirectory();
    if (path == null || !mounted) return;
    if (_workspace.workspaceAt(location) case final multi?) {
      _workspace.addWorkspaceFolder(multi, path);
    }
  }

  IdeRecentWorkspace? _recentWorkspace(String path) =>
      switch (_workspace.workspaceAt(path)) {
        final multi? => (name: multi.name, folders: multi.folders),
        null => null,
      };

  /// The side panel as the last run left it, once the workspace has read
  /// that (after this is built).
  void _restoreSidePanel() {
    if (_workspace.sidePanelView case final view?) {
      _workspace.removeListener(_restoreSidePanel);
      _sidePanel.restore(view);
    }
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
  bool _dropped(List<ComposerFile> files) {
    // Theme extensions (.vsix) dropped on the IDE install there.
    if (_showsIde &&
        (_ide?.dropExtensions([for (final file in files) file.path]) ??
            false)) {
      return true;
    }
    final opened = _windows?.dropped(_viewId, files) ?? false;
    // Opened as a project in the IDE: no agent's answer to wait for.
    if (opened && files.any((file) => file.directory)) {
      if (_tips case final tips?) {
        unawaited(tips.scenario(TipScenarios.openedFolder));
      }
    }
    return opened;
  }

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
  /// the data folder left behind; then the feature tips start (importing
  /// another editor's keybindings among the checklist's).
  Future<void> _afterFirstFrame() async {
    final settings = widget.settings;
    if (settings?.files == null || !mounted) return;
    await _setUpChannel();
    if (!mounted) return;
    await offerOldDataDirRemoval(context);
    if (!mounted) return;
    await _startTips();
  }

  bool _channelWelcomeShown = false;

  void _channelGateChanged() {
    final gate = ChannelGate.current;
    if (gate == null || gate.ready || _channelWelcomeShown) return;
    // Its account read meanwhile: signed in, likely.
    if (gate.stage == ChannelStage.finding) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _setUpChannel());
  }

  /// The channel build's way in (lib/channel/): its welcome, which stays
  /// till it is set up and the user signed in to the channel's account
  /// site, before anything else; in each window open meanwhile, done in
  /// any; and again once signed out.
  Future<void> _setUpChannel() async {
    final gate = ChannelGate.current;
    if (gate == null || _channelWelcomeShown || !mounted) return;
    _channelWelcomeShown = true;
    try {
      if (gate.stage != ChannelStage.setup && gate.channel == null) {
        final language = Localizations.localeOf(context).languageCode;
        await gate.find(language == 'zh' ? 'zh' : 'en');
      }
      if (gate.ready || !mounted) return;
      final diagnostics = widget.settings?.diagnostics;
      await showChannelSetupWelcome(
        context,
        gate: gate,
        trouble: diagnostics == null
            ? null
            : (context) =>
                  unawaited(showDiagnosticsDialog(context, diagnostics)),
      );
    } finally {
      _channelWelcomeShown = false;
    }
  }

  /// The setup page's `baocode://activate` link, opened: what it says,
  /// unless it was set up already; one not this install's, said so.
  Future<void> _acceptChannelLink(String link) async {
    final setup = ChannelSetup.current;
    if (setup == null || setup.done) return;
    _windows?.showChat();
    final l10n = context.l10n;
    final message = switch (setup.acceptLink(link)) {
      ChannelLinkResult.accepted => null,
      ChannelLinkResult.invalid => l10n.channelSetupLinkInvalid,
      ChannelLinkResult.otherInstall => l10n.channelSetupLinkOther,
    };
    if (message == null) return;
    await showIdeDialog(
      context,
      message: message,
      buttons: [l10n.commonOk],
      cancel: null,
      type: IdeDialogType.error,
    );
  }

  Future<SshPasswordAnswer?> _askSshPassword(
    SshPrompt prompt, {
    required bool keepable,
  }) async => mounted
      ? showSshPasswordDialog(context, prompt, keepable: keepable)
      : null;

  @override
  void dispose() {
    ChannelGate.current?.removeListener(_channelGateChanged);
    for (final edits in _ideAgentEdits.values) {
      edits.dispose();
    }
    if (SshHosts.instance.passwords.ask == _askSshPassword) {
      SshHosts.instance.passwords.ask = null;
    }
    if (StashController.current case final stash?
        when stash.showPage == _showStash) {
      stash.showPage = null;
      FileViews.unregister('stash');
    }
    _terminals
      ?..removeListener(_terminalsChanged)
      ..dispose();
    _chatCode?.dispose();
    _workspace.removeListener(_restoreSidePanel);
    _workspace.removeListener(_syncWorkspaceFolders);
    _sidePanel
      ..removeListener(_sidePanelChanged)
      ..dispose();
    for (final git in _sidePanelGits.values) {
      git.dispose();
    }
    _drag.dispose();
    _width.dispose();
    _looseChatFolder.dispose();
    _ideHistory.dispose();
    _lifecycle?.dispose();
    _attention?.dispose();
    _starPrompt?.dispose();
    _stopUpdateOffers?.call();
    if (_tipsPresenter case final presenter?) {
      _tips
        ?..detach(presenter)
        ..removeListener(_tipsChanged);
    }
    _typingTimer?.cancel();
    for (final MapEntry(key: session, value: listener)
        in _turnWatches.entries) {
      session.removeListener(listener);
    }
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
    _syncAutoSave();
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
    // An agent's window has its agent alone (and the sidebar to pick
    // another: see _buildContent), and the search palette for the window's
    // commands.
    if (_agentWindow) {
      return {
        'workbench.action.toggleSidebarVisibility': _toggle,
        openSettingsCommandId: () => unawaited(openSettings()),
        openKeybindingsCommandId: () =>
            unawaited(openSettings(SettingsSection.keyboard)),
        ideSelectColorThemeCommandId: _selectColorTheme,
        checkForUpdatesCommandId: _checkForUpdates,
        if (_tipsEnabled) showSetupGuideCommandId: _showSetupGuide,
        if (_tipsEnabled) resetFeatureTipsCommandId: _resetTips,
        starOnGitHubCommandId: _starOnGitHub,
        if (BrowserBridge.instance.supported)
          browserWelcomeCommandId: _showBrowserWelcome,
        modelWelcomeCommandId: _showModelWelcome,
        ChatCommandIds.search: () => unawaited(_openPalette()),
        ..._sidePanelCommands(),
        ..._terminalCommands(),
        ..._windowCommands(),
      };
    }
    final current = _workspace.current;
    // One agent alone is the one pane.
    final panes = _workspace.grid.isEmpty ? [?current] : _workspace.grid.panes;
    final agents = _agentsInOrder();
    return {
      'workbench.action.toggleSidebarVisibility': _toggle,
      openSettingsCommandId: () => unawaited(openSettings()),
      openKeybindingsCommandId: () =>
          unawaited(openSettings(SettingsSection.keyboard)),
      ideSelectColorThemeCommandId: _selectColorTheme,
      checkForUpdatesCommandId: _checkForUpdates,
      if (_tipsEnabled) showSetupGuideCommandId: _showSetupGuide,
      if (_tipsEnabled) resetFeatureTipsCommandId: _resetTips,
      starOnGitHubCommandId: _starOnGitHub,
      if (BrowserBridge.instance.supported)
        browserWelcomeCommandId: _showBrowserWelcome,
      if (StashController.current != null)
        stashWelcomeCommandId: _showStashWelcome,
      modelWelcomeCommandId: _showModelWelcome,
      // As the sidebar's New Agent button: a folder first, without one.
      if (_workspace.sidebarProjects.isNotEmpty)
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
      if (StashController.current != null) _stashCommand: _showStash,
      if (current != null) ...{
        ChatCommandIds.openIde: () => _workspace.openInIde(current),
        ..._sidePanelCommands(),
      },
      ..._terminalCommands(),
      ..._windowCommands(),
    };
  }

  /// The terminal panel's: Toggle Terminal (and Toggle Panel Visibility,
  /// which the IDE's panel button shows first) and Create New Terminal
  /// where there is an agent's project for them; those on the terminal
  /// shown.
  Map<String, VoidCallback> _terminalCommands() {
    final terminals = _terminals;
    if (terminals == null || terminals.root == null) return const {};
    final current = terminals.shown ? terminals.current : null;
    return {
      toggleTerminalCommand: _toggleTerminal,
      togglePanelCommand: _toggleTerminal,
      newTerminalCommand: terminals.create,
      if (current?.active != null)
        'workbench.action.terminal.kill': terminals.kill,
      if ((current?.instances.length ?? 0) > 1) ...{
        'workbench.action.terminal.focusNext': () =>
            terminals.cycle(next: true),
        'workbench.action.terminal.focusPrevious': () =>
            terminals.cycle(next: false),
      },
    };
  }

  /// Preferences: Color Theme (see [ideColorThemePick]), over the chat as
  /// the IDE shows it over its editor.
  void _selectColorTheme() => showQuickPick(
    ideColorThemePick(
      WorkbenchThemeService.instance,
      onError: (error) {
        if (mounted) _notifications.notify(IdeSeverity.error, '$error');
      },
      l10n: context.l10n,
    ),
  );

  /// Toggle Terminal (⌃`): the focused agent's panel, its terminal
  /// focused; or hidden, the keyboard back in the chat if the terminal had
  /// it.
  void _toggleTerminal() {
    if (_agentThread ?? _workspace.current case final thread?) {
      _toggleTerminalOf(thread);
    }
  }

  /// [thread]'s project's panel: shown, its terminal focused; or hidden,
  /// the keyboard back in the chat if the terminal had it.
  void _toggleTerminalOf(AgentThread thread) {
    final terminals = _terminals;
    if (terminals == null) return;
    final root = thread.project.path;
    if (!terminals.shownFor(root)) return terminals.show(root: root);
    if (terminals.hide(root: root)) _focusCurrentChat();
  }

  /// The focused agent's input, once its chat is built.
  void _focusCurrentChat() {
    if (_agentThread ?? _workspace.current case final thread?) {
      _focusChat(thread);
    }
  }

  /// Opens a link from a terminal: a URL in the browser, a file in the IDE
  /// at its line and column, a folder in the system's file manager.
  void _openTerminalLink(TerminalLink link) {
    final thread = _agentThread ?? _workspace.current;
    switch (link.type) {
      case TerminalLinkType.url:
        unawaited(openExternal(link.text));
      case TerminalLinkType.localFile when thread != null:
        final at = LspPosition(
          math.max(0, (link.line ?? 1) - 1),
          math.max(0, (link.column ?? 1) - 1),
        );
        _inIdeOf(thread, (ide) => ide.openAt(link.path!, LspRange(at, at)));
      case TerminalLinkType.localFolder:
        unawaited(openExternal(link.path!));
      case TerminalLinkType.localFile || TerminalLinkType.search:
        break;
    }
  }

  /// New Window, Close Window, Switch Window… and Show Chat Window, where
  /// the app has windows (the IDE in the main one: New Window shows its
  /// empty window there, Show Chat Window the chat); full screen and zoom
  /// in any.
  Map<String, VoidCallback> _windowCommands() {
    final windows = _windows;
    final window = widget.window;
    final anyWindow = {
      if (WindowControls.canFullScreen)
        WindowCommandIds.toggleFullScreen: () =>
            unawaited(WindowControls.toggleFullScreen(viewId: _viewId)),
      WindowCommandIds.zoomIn: () => _zoom(1),
      WindowCommandIds.zoomOut: () => _zoom(-1),
      WindowCommandIds.zoomReset: () => _zoom(null),
    };
    if (windows == null || window == null || !windows.started) {
      return anyWindow;
    }
    return {
      ...anyWindow,
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
        if (windows.multi || window.isAgent) return windows.showChat();
        windows.focus(window);
        _workspace.layout = WorkspaceLayout.chat;
      },
    };
  }

  /// The window's scale [steps] of [CodeFont.uiScaleStep] on (null: back
  /// to the system's), kept in settings.json as Interface Size has it.
  void _zoom(int? steps) {
    final now = CodeFont.uiScale.value;
    final percent = steps == null
        ? CodeFont.defaultUiScale
        : CodeFont.zoomedUiScale(now, steps);
    if (percent == now) return;
    appEvent(
      'zoom',
      'Zoom ${switch (steps) {
        null => 'Reset',
        > 0 => 'In',
        _ => 'Out',
      }}, keys down: ${HardwareKeyboard.instance.logicalKeysPressed.map((key) => key.keyLabel).join('+')}',
    );
    CodeFont.uiScale.value = percent;
    final settings = widget.settings?.files?.settings;
    if (settings == null) return;
    unawaited(
      settings
          .update(CodeFont.uiScaleSettingKey, CodeFont.uiScaleSetting(percent))
          .catchError((Object error) {
            // A settings file that does not parse is left as it is; its
            // error is shown.
            debugPrint('${CodeFont.uiScaleSettingKey} not kept: $error');
          }),
    );
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

  /// The customizations of each remote host the sidebar has been on.
  final Map<String, CustomizationStore> _hostCustomizations = {};

  void _showCustomize([CustomizationKind? kind]) {
    _closeDrawer();
    if (kind != null) _customizeKey.currentState?.show(kind);
    setState(() {
      _customizing = true;
      _stashing = false;
      if (kind != null) _customizeKind = kind;
    });
  }

  /// The conversations show again, in place of Customize or the stashes.
  void _closeCustomize() {
    if (_customizing || _stashing) {
      setState(() => _customizing = _stashing = false);
    }
  }

  // --- The stashes ------------------------------------------------------------

  /// The stashes' page's command, for the palette and the keys.
  static const _stashCommand = 'baocode.stash.show';

  /// The stashes (docs/stash.md) show in place of the chat.
  bool _stashing = false;
  int? _stashShown;
  final GlobalKey<StashViewState> _stashKey = GlobalKey();

  /// Something shows in place of the conversations.
  bool get _replacingChat => _customizing || _stashing;

  /// Shows the stashes, [id]'s if given.
  void _showStash([int? id]) {
    if (StashController.current == null) return;
    _closeDrawer();
    if (id != null) _stashKey.currentState?.show(id);
    setState(() {
      _stashing = true;
      _customizing = false;
      _stashShown = id;
    });
  }

  bool _paletteOpen = false;

  /// The ids of the palette's actions last run, the last first.
  final List<String> _recentActions = [];

  /// Each project's files, for the palette: listed again as it opens.
  final Map<String, IdeFileIndex> _fileIndexes = {};

  /// [project]'s files, for the palette and `@` alike: listed once, then
  /// again as either opens.
  IdeFileIndex _fileIndexOf(Project project) => _fileIndexes.putIfAbsent(
    project.path,
    () => IdeFileIndex(
      ProjectHost.of(project.path).files(project.root),
      project.root,
      pathContext: ProjectHost.of(project.path).paths,
    ),
  )..roots = _workspace.workspaceOf(project)?.folders;

  final Map<String, FileMentions> _fileMentions = {};

  /// Where `@` in [project]'s conversations looks files up.
  FileMentions _fileMentionsOf(Project project) {
    final index = _fileIndexOf(project);
    final mentions = _fileMentions[project.path];
    if (mentions != null && identical(mentions.index, index)) return mentions;
    final location = project.path;
    final host = ProjectHost.of(location);
    return _fileMentions[location] = FileMentions(
      files: _projectFileServices[location] ??= host.files(
        host.pathOf(location),
      ),
      paths: host.paths,
      index: index,
      home: project.host == null ? homeDirectory : null,
    );
  }

  /// The project the palette's files are of: the window's agent's, or the
  /// current agent's, else the first listed.
  Project? get _paletteProject =>
      (_agentThread ?? _workspace.current)?.project ??
      _workspace.sidebarProjects.firstOrNull;

  /// Opens the search palette over the chat layout, on [filter]; in an
  /// agent's window, an agent picked shows in its place, and a file opens
  /// in the IDE's window.
  Future<void> _openPalette([SearchFilter filter = SearchFilter.all]) async {
    if (_paletteOpen || !mounted) return;
    _paletteOpen = true;
    try {
      _closeDrawer();
      final project = _paletteProject;
      final files = project == null ? null : _fileIndexOf(project);
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
        onOpenAgent: _agentWindow ? _showInWindow : _openAgent,
        // A hit in what was said: found in the conversation, once shown.
        onFindInAgent: (thread, query) {
          _agentWindow ? _showInWindow(thread) : _openAgent(thread);
          _findInChat(thread, query);
        },
        onOpenFile: (path) {
          if (_windows case final windows? when _multi || _agentWindow) {
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
      ?action(_customizeCommand, Codicons.plug),
      ?action(openSettingsCommandId, Codicons.settingsGear),
      ?action(openKeybindingsCommandId, Codicons.keyboard),
      ?action(ideSelectColorThemeCommandId, Codicons.symbolColor),
      ?action(checkForUpdatesCommandId, Codicons.cloudDownload),
      ?action(showSetupGuideCommandId, Codicons.rocket),
      ?action(resetFeatureTipsCommandId, Codicons.discard),
      ?action(starOnGitHubCommandId, Codicons.star),
      ?action(browserWelcomeCommandId, Codicons.globe),
      ?action(stashWelcomeCommandId, Codicons.note),
      ?action(modelWelcomeCommandId, Codicons.sparkle),
      ?action(
        'workbench.action.toggleSidebarVisibility',
        Codicons.layoutSidebarLeft,
      ),
      ?action(ChatCommandIds.openIde, Codicons.code),
      ?action(ChatCommandIds.toggleSidePanel, Codicons.layoutSidebarRight),
      ?action(ChatCommandIds.toggleSidePanelPosition, Codicons.arrowSwap),
      for (final section in alwaysShownSections)
        ?action(section.command!, section.icon),
      ?action(toggleTerminalCommand, Codicons.terminal),
      ?action(newTerminalCommand, Codicons.add),
      if (WindowControls.canPickDirectory)
        ?action(
          'workbench.action.files.openFolder',
          Codicons.folderOpened,
          () => unawaited(_openFolder()),
        ),
      ?action(openRemoteFolderCommandId, Codicons.remote, _openRemoteProject),
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
            label: '${l10n.customizeTitle}: ${kind.label(l10n)}',
            icon: kind.icon,
            run: () => _showCustomize(kind),
          ),
    ];
  }

  /// Finds [query] in [thread]'s chat once it is built: a frame or a few
  /// after it is opened, as its layout settles.
  void _findInChat(AgentThread thread, String query, [int frames = 30]) {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted || ChatScreen.find(_chatKey(thread), query)) return;
        if (frames > 1) _findInChat(thread, query, frames - 1);
      })
      ..ensureVisualUpdate();
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
    IdeCommand(
      id: openLspSettingsCommandId,
      category: 'Preferences',
      label: commandCatalog[openLspSettingsCommandId]!.title,
      run: () => unawaited(_openLspSettings()),
    ),
    IdeCommand(
      id: checkForUpdatesCommandId,
      label: commandCatalog[checkForUpdatesCommandId]!.title,
      run: _checkForUpdates,
    ),
    IdeCommand(
      id: showSetupGuideCommandId,
      category: 'Help',
      label: commandCatalog[showSetupGuideCommandId]!.title,
      run: _showSetupGuide,
    ),
    IdeCommand(
      id: resetFeatureTipsCommandId,
      category: 'Help',
      label: commandCatalog[resetFeatureTipsCommandId]!.title,
      run: _resetTips,
    ),
    IdeCommand(
      id: starOnGitHubCommandId,
      category: 'Help',
      label: commandCatalog[starOnGitHubCommandId]!.title,
      run: _starOnGitHub,
    ),
    if (BrowserBridge.instance.supported)
      IdeCommand(
        id: browserWelcomeCommandId,
        category: 'Help',
        label: commandCatalog[browserWelcomeCommandId]!.title,
        run: _showBrowserWelcome,
      ),
    if (StashController.current != null)
      IdeCommand(
        id: stashWelcomeCommandId,
        category: 'Help',
        label: commandCatalog[stashWelcomeCommandId]!.title,
        run: _showStashWelcome,
      ),
    IdeCommand(
      id: modelWelcomeCommandId,
      category: 'Help',
      label: commandCatalog[modelWelcomeCommandId]!.title,
      run: _showModelWelcome,
    ),
  ];

  // --- Feature tips ----------------------------------------------------------

  /// The app's feature tips (see FeatureTipsController); none without
  /// settings files.
  FeatureTipsController? get _tips => widget.settings?.tips;

  bool get _tipsEnabled => _tips?.enabled ?? false;

  /// Where the tips that come up by themselves show: the main window's
  /// notifications.
  TipsPresenter? _tipsPresenter;

  /// Whether a key went down lately: a tip waits until the user stops
  /// typing.
  bool _typing = false;
  Timer? _typingTimer;

  void _noteTyping() {
    _typing = true;
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () => _typing = false);
  }

  /// Whether a tip now would interrupt: an agent answering, or typing.
  bool _busyForTips() =>
      _typing || _workspace.threads.any((thread) => thread.session.isStreaming);

  /// The tips start once the window shows: the checklist, the update's
  /// notice, then those of what happens.
  Future<void> _startTips() async {
    final tips = _tips;
    if (tips == null) return;
    await tips.start();
    if (!mounted) return;
    final presenter = _tipsPresenter = TipsPresenter(
      notifications: _notifications,
      l10n: () => context.l10n,
      context: () => mounted
          ? TipContext(
              context,
              openSettings: (section) => unawaited(openSettings(section)),
            )
          : null,
      busy: _busyForTips,
    );
    tips.attach(presenter);
    _restores = tips.restores;
    tips.addListener(_tipsChanged);
    if (_main) _welcomeBrowserAfterUpdate(tips);
    if (_main) {
      _starPrompt = StarPrompt(
        workspace: _workspace,
        storage: tips.storage,
        enabled: () => tips.enabled,
        busy: () => _busyForTips() || !_inFront(),
        ask: _showStarDialog,
      )..start();
    }
  }

  // --- The browser's welcome -------------------------------------------------

  /// Kept once the browser's welcome has shown by itself.
  static const _browserWelcomedKey = 'browser.welcomed';

  /// After an update, the browser's welcome, once: to a user who has not
  /// connected one, with the tips on, when not busy.
  void _welcomeBrowserAfterUpdate(FeatureTipsController tips) {
    final bridge = BrowserBridge.instance;
    if (tips.updatedFrom == null ||
        !tips.enabled ||
        !bridge.supported ||
        !bridge.enabled ||
        bridge.connectedBefore ||
        tips.storage.get(_browserWelcomedKey) == true) {
      return;
    }
    void attempt() {
      if (!mounted) return;
      if (_busyForTips() || !_inFront()) {
        Timer(const Duration(seconds: 10), attempt);
        return;
      }
      unawaited(tips.storage.set(_browserWelcomedKey, true));
      _showBrowserWelcome();
    }

    // The update's notice first, the window settled.
    Timer(const Duration(seconds: 3), attempt);
  }

  /// Connect Your Browser…, the command: the welcome, now.
  void _showBrowserWelcome() {
    if (!mounted) return;
    unawaited(
      showBrowserWelcome(
        context,
        openSettings: () => unawaited(openSettings(SettingsSection.browser)),
      ),
    );
  }

  /// Meet Stash…, the command: Stash's welcome, now.
  void _showStashWelcome() {
    final stash = StashController.current;
    if (!mounted || stash == null) return;
    stash.welcomed = true;
    unawaited(showStashWelcome(context, controller: stash));
  }

  /// Set Up a Model…, the command: what an upstream is, and adding one.
  void _showModelWelcome() {
    if (!mounted) return;
    unawaited(
      showModelWelcome(
        context,
        openSettings: (section) => unawaited(openSettings(section)),
      ),
    );
  }

  // --- Asking for a star -----------------------------------------------------

  /// Asks for a star on GitHub after the first conversations (see
  /// StarPrompt): the main window's, once for the app.
  StarPrompt? _starPrompt;

  /// Whether the app is in front: the ask waits for the user to be back.
  static bool _inFront() => switch (WidgetsBinding.instance.lifecycleState) {
    null || AppLifecycleState.resumed => true,
    _ => false,
  };

  Future<void> _showStarDialog() async {
    if (!mounted) return;
    await showStarDialog(
      context,
      openUrl: (url) async => unawaited(openExternal('$url')),
    );
  }

  /// Star BaoCode on GitHub, the command: the ask, now.
  void _starOnGitHub() => unawaited(_starPrompt?.show() ?? _showStarDialog());

  /// The restores of the card seen (see [_tipsChanged]).
  int _restores = 0;

  /// The card brought back (Show Setup Guide, from any window, or the
  /// sidebar's entry): a new agent, where it shows, unless one shows.
  void _tipsChanged() {
    final tips = _tips;
    if (tips == null || tips.restores == _restores) return;
    _restores = tips.restores;
    final current = _workspace.current;
    if (current == null || _workspace.sidebarProjects.isEmpty) return;
    if (current.record == null && current.session.itemCount == 0) return;
    _newAgent();
  }

  /// Show Setup Guide: the checklist back, in the chat where it shows.
  void _showSetupGuide() {
    final tips = _tips;
    if (tips == null) return;
    unawaited(tips.restore());
    _showTipsChat();
  }

  /// Reset Feature Tips: the tips as at a first launch, the checklist shown.
  void _resetTips() {
    final tips = _tips;
    if (tips == null) return;
    unawaited(tips.reset());
    _showTipsChat();
  }

  /// The chat the checklist is in, in front.
  void _showTipsChat() {
    if (_windows case final windows? when _multi || _agentWindow) {
      if (_ideWindow || _agentWindow) windows.showChat();
    } else if (_workspace.layout == WorkspaceLayout.ide) {
      _workspace.layout = WorkspaceLayout.chat;
    }
  }

  /// The sessions watched for the end of their first answer (see
  /// [_watchFirstTurn]), to stop watching with the window.
  final Map<ChatSession, VoidCallback> _turnWatches = {};

  /// A project opened from its folder: the context menu's tip, once its
  /// agent has answered (started a turn and ended it).
  void _watchFirstTurn(AgentThread thread) {
    final tips = _tips;
    if (tips == null || !tips.enabled) return;
    final session = thread.session;
    if (_turnWatches.containsKey(session)) return;
    var started = false;
    void listener() {
      if (session.isStreaming) {
        started = true;
        return;
      }
      if (!started) return;
      session.removeListener(listener);
      _turnWatches.remove(session);
      unawaited(tips.scenario(TipScenarios.openedFolder));
    }

    _turnWatches[session] = listener;
    session.addListener(listener);
  }

  /// Whether the terminal panel's tip was raised this launch.
  bool _terminalTipRaised = false;

  // --- Updates -------------------------------------------------------------

  /// What the app's updates found by themselves, told of here: the main
  /// window's.
  VoidCallback? _stopUpdateOffers;

  /// The sidebar's Update: Restart to Update, as the offer's button.
  void _restartToUpdate() {
    if (widget.settings?.updates case final updates?) {
      unawaited(updates.restart(_notifications, context.l10n));
    }
  }

  /// Check for Updates...: what it finds told of in this window.
  void _checkForUpdates() {
    final updates = widget.settings?.updates;
    if (updates == null) {
      _notifications.notify(IdeSeverity.info, context.l10n.updateUnsupported);
      return;
    }
    unawaited(updates.checkNow(_notifications, context.l10n));
  }

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
    if (event is KeyDownEvent) _noteTyping();
    if (event is KeyUpEvent ||
        _showsIde ||
        KeyChord.fromEvent(event) == null ||
        !mounted ||
        !_hasKeyboard) {
      return false;
    }
    // The quick pick over the window has its own.
    if (_quickInputKey?.currentState case final quick?) {
      _leaveChord();
      return !ChatKeys.isComposing && _handleQuickInputKey(quick, event);
    }
    // A dialog over the window (the settings' key recorder) keeps its keys.
    if (!(ModalRoute.isCurrentOf(context) ?? true)) {
      _leaveChord();
      return false;
    }
    // So does an input method composing text.
    if (ChatKeys.isComposing) return false;
    // In a terminal, the keys are the shell's but for the window's that
    // skip it, as VS Code's (`terminal.integrated.commandsToSkipShell`, and
    // ⌘ on macOS); none are the chat's.
    final inTerminal = _terminals?.focused ?? false;
    final focused = inTerminal
        ? const <ChatKeyTarget>[]
        : ChatKeys.focusedTargets();
    final chat = focused.isNotEmpty || inTerminal
        ? focused
        : switch (_agentThread ?? _workspace.current) {
            final thread? => ChatKeys.targetsOf(
              _chatKey(thread).currentContext,
            ),
            null => const <ChatKeyTarget>[],
          };
    final window = _chatCommands();
    final chatCommands = ChatKeys.commandsOf(chat);
    final pending = _pendingChords;
    KeybindingResolution resolve(bool Function(String command) canRun) =>
        KeybindingService.instance.resolveEvent(
          event,
          pending: pending ?? const [],
          context: ChatKeys.lookupOf(chat, _chatKeyContext),
          canRun: (item) => canRun(item.command),
        );
    bool skipsShell(String command) =>
        HardwareKeyboard.instance.isMetaPressed ||
        terminalCommandsToSkipShell.contains(command);
    var result = inTerminal
        // The terminal's own first (⇧⌘] is its next terminal there, the
        // next agent elsewhere).
        ? resolve(
            (command) =>
                command.startsWith('workbench.action.terminal.') &&
                window.containsKey(command) &&
                skipsShell(command),
          )
        : const NoKeybinding();
    if (result is NoKeybinding) {
      result = resolve(
        (command) =>
            (window.containsKey(command) &&
                (!inTerminal || skipsShell(command))) ||
            chatCommands.containsKey(command),
      );
    }
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
      'terminalFocus' || 'terminalFocusInAny' => _terminals?.focused ?? false,
      ChatContextKeys.sidePanelFocus => _sidePanel.hasFocus,
      'terminalProcessSupported' => _terminals != null,
      'terminalIsOpen' || 'terminalHasBeenCreated' =>
        _terminals?.current?.instances.isNotEmpty ?? false,
      'terminalCount' => _terminals?.current?.instances.length ?? 0,
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
            // A remote project's Open File… browses its host's folders,
            // not this machine's (VS Code's remote Open File…).
            RemoteLocation.isRemote(folder)
                ? _openRemoteFile
                : () => unawaited(_pickIdeFiles()),
            enabled: WindowControls.canPickFiles,
          ),
          command(
            'workbench.action.files.openFolder',
            () => unawaited(_pickIdeFolder()),
            enabled: WindowControls.canPickDirectory,
          ),
          IdeCommand(
            id: 'git.clone',
            category: 'Git',
            label: 'Clone',
            enabled: !kIsWeb,
            run: () => unawaited(_cloneRepository()),
          ),
          IdeCommand(
            id: openRemoteFolderCommandId,
            category: 'Remote-SSH',
            label: 'Open Remote Project...',
            run: () => _openRemoteProject(inIde: true),
          ),
          IdeCommand(
            id: openRemoteFileCommandId,
            category: 'Remote-SSH',
            label: 'Open Remote File...',
            run: () => _openRemoteFile(),
          ),
          if (_workspace.workspaceDirectories.root != null)
            IdeCommand(
              id: IdeWorkbench.createWorkspaceCommandId,
              category: 'Workspaces',
              label: 'Create Workspace...',
              run: () => unawaited(_createWorkspace(inIde: true)),
            ),
          command('workbench.action.openRecent', _showOpenRecent),
          command(
            'workbench.action.clearRecentlyOpened',
            () => unawaited(_clearRecent()),
          ),
          command(toggleAutoSaveCommandId, _toggleAutoSave),
          command(EditorWordWrap.commandId, EditorWordWrap.toggle),
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

  /// Where the last clone went: the next one's folder at first.
  String? _cloneParent;

  /// Git: Clone (JetBrains' Get from Version Control): a repository
  /// cloned, then opened as a folder is.
  Future<void> _cloneRepository() async {
    final held = _newWindowHeld;
    final folder = await showIdeGitCloneDialog(
      context,
      parent: _cloneParent ?? homeDirectory ?? p.current,
      pickDirectory: WindowControls.canPickDirectory
          ? WindowControls.pickDirectory
          : null,
    );
    if (folder == null || !mounted) return;
    _cloneParent = p.dirname(folder);
    _openIdeFolder(folder, held: held);
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

  /// The user's `lsp.json`, in an editor: made first, with its examples,
  /// where there is none (#304).
  Future<void> _openLspSettings() async {
    final path = DataDirectory.current.lspSettingsFile;
    await ensureLspSettingsFile(path);
    if (mounted) _openIdeFiles([path]);
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
    if (paths.firstOrNull == CodeArgs.importRequestMarker) {
      for (final link in paths.skip(1)) {
        if (ChannelSetup.isLink(link)) {
          await _acceptChannelLink(link);
        } else {
          await _importUpstream(link);
        }
      }
      return;
    }
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
    // A remote project's folders are not this machine's, where the panel is.
    final local = space.files is! IdeHostFiles;
    final path = await WindowControls.pickSaveFile(
      directory: !local
          ? null
          : doc.isUntitled
          ? (space.hasFolder ? space.root : null)
          : p.dirname(doc.path),
      name: doc.isUntitled
          ? doc.path
          : local
          ? p.basename(doc.path)
          : p.posix.basename(doc.path),
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

  /// Whether `files.autoSave` is on, in any of its modes: the File menu's
  /// Auto Save ticked.
  bool get _autoSaveOn =>
      switch (widget.settings?.files?.settings['files.autoSave']) {
        final String mode => mode != 'off',
        _ => false,
      };

  /// [_autoSaveOn] as the File menus last showed it.
  bool? _autoSaveShown;
  void _syncAutoSave() {
    final on = _autoSaveOn;
    if (on == _autoSaveShown) return;
    final first = _autoSaveShown == null;
    _autoSaveShown = on;
    if (_main) unawaited(WindowControls.setFileMenuChecked({'autoSave': on}));
    if (!first && mounted) setState(() {});
  }

  /// Toggle Auto Save, as VS Code's: `afterDelay` when off, else off (the
  /// setting removed, off being its default).
  void _toggleAutoSave() {
    final settings = widget.settings?.files?.settings;
    if (settings == null) return;
    unawaited(
      settings
          .update('files.autoSave', _autoSaveOn ? null : 'afterDelay')
          .catchError((Object error) {
            // A settings file that does not parse is left as it is; its
            // error is shown.
            debugPrint('files.autoSave not kept: $error');
          }),
    );
  }

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
        'autoSave': l10n.menuAutoSave,
        'closeFolder': l10n.cmdCloseFolder,
        'clearRecent': l10n.cmdClearRecentlyOpened,
        'more': l10n.menuMore,
        'newWindow': l10n.cmdNewWindow,
        'closeWindow': l10n.menuCloseWindow,
        // The app menu's, under About.
        'checkForUpdates': l10n.cmdCheckForUpdates.replaceAll('...', '…'),
      }),
    );
  }

  // --- The IDE's chat ----------------------------------------------------------

  void _newIdeChat(String folder) => _focusChat(_workspace.newIdeChat(folder));

  /// [code] after what is typed in [folder]'s chat (a new one, if it has
  /// none), the keyboard there: the IDE's Add Selection to Chat. Without a
  /// folder, the chat of the file's in front, if one shows.
  void _addCodeToIdeChat(String folder, List<CodeReference> code) {
    final chatFolder = folder == _noFolder ? _looseChatFolder.value : folder;
    if (chatFolder == null) return;
    if (_ideHistory.value == chatFolder) _ideHistory.value = null;
    final thread =
        _workspace.ideChat(chatFolder) ?? _workspace.newIdeChat(chatFolder);
    thread.session.draft.insertCode(code);
    _focusChat(thread);
  }

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

  /// Copies [thread]'s conversation into a new agent, opened as a tab in
  /// [folder], as the sidebar's Fork does.
  Future<void> _forkIdeChat(String folder, AgentThread thread) async {
    final forked = await _workspace.fork(thread);
    if (forked == null || !mounted) return;
    _openIdeChat(folder, forked);
  }

  /// Deletes [thread]'s conversation once confirmed, as the sidebar's
  /// Delete asks.
  Future<void> _confirmDeleteThread(AgentThread thread) async {
    final l10n = context.l10n;
    final title = thread.localizedTitle(l10n);
    final choice = await showIdeDialog(
      context,
      message: l10n.sidebarDeleteAgentTitle,
      detail: thread.kernel.catalog == null
          ? l10n.sidebarDeleteAgentMessage(title)
          : l10n.sidebarDeleteAgentMessageKernel(title, thread.kernel.label),
      buttons: [l10n.commonDelete],
      type: IdeDialogType.warning,
    );
    if (choice != 0) return;
    _workspace.delete(thread);
  }

  /// The IDE's chat in [folder]: its tabs over the one shown, the agent
  /// told of the file open in its editor. Without a folder, in that of the
  /// file in front (see [_looseChatFolder]); a way to open one until there
  /// is one.
  Widget _buildIdeChat(String folder) {
    OpenEditor? openEditor() => _ideKeys[folder]?.currentState?.openEditor;
    if (folder == _noFolder) {
      return ValueListenableBuilder(
        valueListenable: _looseChatFolder,
        builder: (context, loose, _) => loose == null
            ? _IdeNoFolderChat(
                onOpenFolder: WindowControls.canPickDirectory
                    ? () => unawaited(_pickIdeFolder())
                    : null,
              )
            : _ideChatIn(loose, openEditor),
      );
    }
    return _ideChatIn(folder, openEditor);
  }

  /// The folder whose IDE chat shows its agents' history floating over it.
  final ValueNotifier<String?> _ideHistory = ValueNotifier(null);

  /// Back from [folder]'s history to its chat, the keyboard there.
  void _closeIdeHistory(String folder) {
    if (_ideHistory.value != folder) return;
    _ideHistory.value = null;
    if (_workspace.ideChat(folder) case final current?) _focusChat(current);
  }

  /// The IDE's chat tabs in [folder] over the one shown, its agents'
  /// history floating over that while it shows.
  Widget _ideChatIn(String folder, OpenEditor? Function() openEditor) {
    final current = _workspace.ideChat(folder);
    final threads = [
      for (final thread in _workspace.threads)
        if (thread.project.path == folder) thread,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder(
          valueListenable: _ideHistory,
          builder: (context, historyFolder, _) => IdeChatTitle(
            tabs: _workspace.ideChats(folder),
            current: current,
            onNew: () {
              _ideHistory.value = null;
              _newIdeChat(folder);
            },
            onOpen: (thread) {
              _ideHistory.value = null;
              _openIdeChat(folder, thread);
            },
            onClose: (threads) => _workspace.closeIdeChats(folder, threads),
            onPin: (thread) => _workspace.setPinned(thread, !thread.pinned),
            onMove: (thread, index) =>
                _workspace.moveIdeChat(folder, thread, index),
            onRename: _workspace.rename,
            onFork: (thread) => unawaited(_forkIdeChat(folder, thread)),
            onArchive: (thread) =>
                _workspace.setArchived(thread, !thread.archived),
            onDelete: (thread) => unawaited(_confirmDeleteThread(thread)),
            historyOpen: historyFolder == folder,
            onHistory: () => historyFolder == folder
                ? _closeIdeHistory(folder)
                : _ideHistory.value = folder,
          ),
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (current == null)
                const SizedBox.shrink()
              else
                for (final thread in _keepIdeChats(folder, current))
                  _keptIdeChat(
                    thread,
                    shown: identical(thread, current),
                    openEditor: openEditor,
                  ),
              // Over the chat, which keeps what it was at underneath.
              ValueListenableBuilder(
                valueListenable: _ideHistory,
                builder: (context, historyFolder, _) => historyFolder != folder
                    ? const SizedBox.shrink()
                    : IdeChatHistory(
                        threads: threads,
                        current: current,
                        onOpen: (thread) {
                          _ideHistory.value = null;
                          _openIdeChat(folder, thread);
                        },
                        onPin: (thread) =>
                            _workspace.setPinned(thread, !thread.pinned),
                        onArchive: (thread) =>
                            _workspace.setArchived(thread, !thread.archived),
                        onFork: (thread) {
                          _ideHistory.value = null;
                          unawaited(_forkIdeChat(folder, thread));
                        },
                        onDelete: (thread) =>
                            unawaited(_confirmDeleteThread(thread)),
                        onDismiss: () => _closeIdeHistory(folder),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The IDE chat tabs shown last in each folder, the one shown first,
  /// kept built ([_keptIdeChat]): a long conversation takes a while to
  /// build, which a tab shown again went through each time.
  final Map<String, List<AgentThread>> _ideChatsKept = {};

  /// Each kept chat as last built while shown.
  final Map<AgentThread, Widget> _ideChatWidgets = {};

  static const _ideChatsKeptCount = 5;

  /// [folder]'s kept chats, [current] first, those whose tabs are open.
  List<AgentThread> _keepIdeChats(String folder, AgentThread current) {
    final open = _workspace.ideChats(folder);
    final kept = _ideChatsKept[folder] = [
      current,
      for (final thread in _ideChatsKept[folder] ?? const <AgentThread>[])
        if (!identical(thread, current) && open.contains(thread)) thread,
    ].take(_ideChatsKeptCount).toList();
    final all = {for (final chats in _ideChatsKept.values) ...chats};
    _ideChatWidgets.removeWhere((thread, _) => !all.contains(thread));
    return kept;
  }

  /// [thread]'s chat in the IDE, kept built while another tab shows: as it
  /// was last built then, rebuilt as the window is only while shown.
  Widget _keptIdeChat(
    AgentThread thread, {
    required bool shown,
    required OpenEditor? Function() openEditor,
  }) {
    Widget build() => _buildChat(
      showToggle: false,
      embedded: true,
      pane: thread,
      openEditor: openEditor,
    );
    final chat = shown
        ? _ideChatWidgets[thread] = build()
        : _ideChatWidgets[thread] ??= build();
    return Offstage(
      key: ObjectKey(thread),
      offstage: !shown,
      child: TickerMode(
        enabled: shown,
        child: ExcludeFocus(excluding: !shown, child: chat),
      ),
    );
  }

  /// A site's one-click import of an upstream ([UpstreamImport]): asked
  /// about in this window, brought in front; once added, its page in
  /// Settings → Models.
  Future<void> _importUpstream(String link) async {
    // The channel build's only upstream is its account's.
    if (ChannelSetup.channelBuild) return;
    _windows?.showChat();
    final l10n = context.l10n;
    final import = UpstreamImport.parse(link);
    if (import == null) {
      await showIdeDialog(
        context,
        message: l10n.modelsImportInvalid,
        detail: l10n.modelsImportInvalidDetail,
        buttons: [l10n.commonOk],
        cancel: null,
        type: IdeDialogType.error,
      );
      return;
    }
    final id = await showUpstreamImportDialog(context, import);
    if (id == null || !mounted) return;
    ModelsSettingsPage.reveal.value = id;
    await openSettings(SettingsSection.models);
  }

  bool _settingsOpen = false;

  /// Opens the settings dialog on [section].
  Future<void> openSettings([
    SettingsSection section = SettingsSection.general,
  ]) async {
    if (_settingsOpen || !mounted) return;
    // Built with: Windows' header gives the dialog its left.
    setState(() => _settingsOpen = true);
    _closeDrawer();
    try {
      await showSettingsDialog(
        context,
        section: section,
        pageBuilder: (context, section) =>
            widget.settings?.buildPage(context, section) ??
            const SizedBox.shrink(),
        noticeBuilder: widget.settings?.buildNotice,
      );
    } finally {
      if (mounted) {
        setState(() => _settingsOpen = false);
      } else {
        _settingsOpen = false;
      }
    }
  }

  /// Toggle Sidebar. Docked where it had given way to the side panel, or
  /// with no room for the two, it stays and the panel gives way (see
  /// [_sidePanelLast]).
  void _toggle() {
    setState(() {
      if (_narrow) {
        _drawerClosing = _drawerOpen;
        _drawerOpen = !_drawerOpen;
      } else if (_sidebarDocked) {
        _docked = false;
      } else {
        _docked = true;
        _sidePanelLast = false;
        if (_sidesClash) _sidePanel.hide();
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
        final content = Material(
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
        // The model picker's Manage Models… opens the settings.
        return SettingsOpener(
          open: (section) => unawaited(openSettings(section)),
          // The side panel explorer's uploads and downloads show their
          // progress in the window's toasts.
          child: IdeNotificationsScope(
            notifications: _notifications,
            child: content,
          ),
        );
      },
    );
  }

  Widget _buildContent(bool narrow) {
    if (_agentThread case final thread?) {
      // Gone (deleted), its window goes with it.
      if (!_workspace.threads.contains(thread)) return const SizedBox.shrink();
      // With the sidebar, as the chat's window has it: over the
      // conversation while narrow, beside it once wide. Its toggle is the
      // header's on Windows, else by the traffic lights while it is hidden.
      final showToggle = narrow || !_sidebarDocked;
      final chat = _withSidePanel(
        _withTerminal(
          _buildChat(
            showToggle: showToggle,
            pane: thread,
            showsTerminals: _terminals != null,
          ),
          thread,
        ),
        showToggle: showToggle,
      );
      return narrow ? _buildNarrow(body: chat) : _buildWide(body: chat);
    }
    final folder = _ideFolder;
    // An IDE window has its folder's alone.
    if (_ideWindow) return _buildIde(folder, _ideSpace(folder), shown: true);
    final ide = _showsIde;
    if (ide) _ideSpace(folder);
    _hiddenIdes.removeWhere((path, _) => !_ideSpaces.containsKey(path));
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
    if (shown) {
      _hiddenIdes.remove(path);
    } else if (_hiddenIdes[path] case final kept? when kept.space == space) {
      return kept.ide;
    }
    final built = _ideOf(path, space, shown: shown);
    if (!shown) _hiddenIdes[path] = (space: space, ide: built);
    return built;
  }

  Widget _ideOf(String path, IdeWorkspace space, {required bool shown}) {
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
            themeExtensions: widget.themeExtensions,
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
            recentWorkspaceOf: _recentWorkspace,
            onAddFolder: _workspace.workspaceAt(path) == null
                ? null
                : () => unawaited(_addWorkspaceFolder(path)),
            onRemoveFolder: switch (_workspace.workspaceAt(path)) {
              final multi? => (folder) => _workspace.removeWorkspaceFolder(
                multi,
                folder,
              ),
              null => null,
            },
            onOpenRecent: (folder) =>
                _openIdeFolder(folder, held: _newWindowHeld),
            settings: widget.settings?.files?.settings,
            viewState: _workspace.ideView(path),
            onViewState: path == _noFolder
                ? null
                : (state) => _workspace.keepIdeView(path, state),
            terminalBackend: ProjectHost.of(path).terminals(
              widget.terminalBackend ?? const TerminalBackend(supported: false),
            ),
            // Its chat's background commands, with its terminals.
            terminalTasks: switch (_workspace.ideChat(path)) {
              final thread? => SessionTerminalTasks(thread.session),
              null => null,
            },
            // The project's terminals, the chat's: the same in both.
            terminals: path == _noFolder
                ? null
                : _terminals?.terminalsOf(path),
            terminalHosts: _terminals?.hosts,
            remote: switch (ProjectHost.of(path)) {
              final SshHost host => SshStatusIndicator(
                host,
                // The remote menu: switch host, reconnect, open a folder
                // or a file there.
                onChoose: (rect) {
                  if (!mounted) return;
                  _statusAnchor = rect;
                  unawaited(_showRemoteMenu(host.host));
                },
              ),
              _ => null,
            },
            // Claude Haiku where the project is.
            commitMessage: (prompt, {cancel}) =>
                ideClaudeCommitMessage(prompt, cancel: cancel, location: path),
            agentEdits: _ideAgentEdits.putIfAbsent(path, IdeAgentEdits.new)
              ..sessions = _agentSessionsIn(path),
            chat: shown
                ? _ideConversation(_buildIdeChat(path))
                : const SizedBox.shrink(),
            onAddToChat: _workspace.ideChat(path) == null
                ? null
                : (files) => _workspace
                      .ideChat(path)
                      ?.session
                      .draft
                      .insertFiles(files),
            onAddCodeToChat: (code) => _addCodeToIdeChat(path, code),
            onAskInChat: _workspace.ideChat(path) == null
                ? null
                : (text) => _workspace
                      .ideChat(path)
                      ?.session
                      .draft
                      .restore(text, const []),
          ),
        ),
      ),
    );
  }

  /// The conversations whose changes [path]'s IDE shows in its files: its
  /// chat's first, then the others open in the project.
  List<ChatSession> _agentSessionsIn(String path) {
    final chat = _workspace.ideChat(path);
    return [
      if (chat != null && chat.isOpen) chat.session,
      for (final thread in _workspace.threads)
        if (thread.isOpen &&
            thread.project.path == path &&
            !identical(thread, chat))
          thread.session,
    ];
  }

  /// The sidebar docked beside [body] (by default the chat's panes).
  Widget _buildWide({Widget? body}) {
    // Built once for the widths a drag goes through (see [_width]).
    final sidebar = _buildSidebar();
    final panes = body ?? _buildPanes(showToggle: !_sidebarDocked);
    final row = ValueListenableBuilder(
      valueListenable: _width,
      builder: (context, _, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedContainer(
            duration: _dragging ? Duration.zero : _duration,
            curve: Curves.easeOutCubic,
            width: _sidebarDocked ? _shownWidth : 0,
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
            // The handle over the conversations' edge, its line alone
            // beside them: nothing between a pane's color and the line.
            child: _conversation(
              Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(left: _sidebarDocked ? 1 : 0, child: panes),
                  if (_sidebarDocked)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: _buildResizeHandle(),
                    ),
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

  /// The sidebar as a drawer over [body] (by default the chat's panes).
  Widget _buildNarrow({Widget? body}) {
    // The same sidebar and border as when docked, at the same width.
    const handleWidth = _WorkbenchState._handleWidth;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: _conversation(body ?? _buildPanes(showToggle: true)),
        ),
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
  /// [thread] in this agent's window, in place of its agent.
  void _showInWindow(AgentThread thread) {
    final window = widget.window;
    if (window == null) return;
    _windows?.showInWindow(window, thread);
    setState(() {});
  }

  static Widget _conversation(Widget child) =>
      ColoredBox(color: AppColors.conversationSurface, child: child);

  /// The IDE's chat: the editor's color, opaque, as the editor beside it.
  static Widget _ideConversation(Widget child) =>
      ColoredBox(color: AppColors.code, child: child);

  Widget _buildSidebar({VoidCallback? onOpened}) {
    // An agent's window shows what is picked or made here in its place;
    // the chat's window and Customize are not its.
    final agent = _agentThread;
    return Sidebar(
      workspace: _workspace,
      current: agent,
      onSelect: agent == null ? null : _showInWindow,
      onNewAgent: agent == null
          ? null
          : (project) => _showInWindow(
              _workspace.newWindowAgent((project ?? agent.project).path),
            ),
      link: _sidebarLink,
      onCollapse: _toggle,
      onOpened: () {
        _closeCustomize();
        onOpened?.call();
      },
      onOpenFolder: WindowControls.canPickDirectory ? _openFolder : null,
      onAddSshHost: WindowControls.canPickDirectory
          ? () => _openRemoteProject(switchTo: true)
          : null,
      onOpenFolderOn: WindowControls.canPickDirectory
          ? (host) => _openRemoteProject(host: host)
          : null,
      editSshHost: (host) => _sshConfigHosts.contains(host)
          ? null
          : () => unawaited(_editSshServer(host: host)),
      onOpenSettings: () => unawaited(openSettings()),
      updates: widget.settings?.updates?.service,
      onUpdate: _restartToUpdate,
      onSearch: () => unawaited(_openPalette()),
      setup: switch (_tips) {
        final tips? when _main => FeatureTipsEntry(controller: tips),
        _ => null,
      },
      onCustomize: agent != null || widget.customizations == null
          ? null
          : () => _customizing ? _closeCustomize() : _showCustomize(),
      customizing: _customizing,
      onStash: agent != null || StashController.current == null
          ? null
          : () => _stashing ? _closeCustomize() : _showStash(),
      stashing: _stashing,
      // Opened on the Stash page, which an agent's window has not.
      stashes: switch (StashController.current) {
        final stash? when agent == null => sidebarStashes(stash, _showStash),
        _ => null,
      },
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
  ///
  /// A remote folder's is in its path on its host, its files, Git,
  /// language servers and terminals there.
  IdeWorkspace _ideSpace(String folder) => _ideSpaces.putIfAbsent(folder, () {
    final host = ProjectHost.of(folder);
    final root = host.pathOf(folder);
    final multi = _workspace.workspaceAt(folder);
    final space = folder == _noFolder
        ? IdeWorkspace(homeDirectory ?? p.current, hasFolder: false)
        : multi != null
        // A workspace's folders, each a root with its own repository; the
        // language servers its first folder's.
        ? IdeWorkspace(
            root,
            files: host.files(root),
            languages: switch (multi.folders.firstOrNull) {
              final first? => widget.languagesFor?.call(first),
              null => null,
            },
            roots: multi.folders,
            gitOf: (folder) => widget.gitFor?.call(folder),
            repositoryDetection: _repositoryDetection(host),
            openWorktree: (path) =>
                widget.gitFor?.call(RemoteLocation.of(host.name, path)),
            paths: host.name == null ? null : host.paths,
          )
        : IdeWorkspace(
            root,
            files: host.files(root),
            languages: widget.languagesFor?.call(folder),
            git: widget.gitFor?.call(folder),
            repositoryDetection: _repositoryDetection(host),
            openWorktree: (path) =>
                widget.gitFor?.call(RemoteLocation.of(host.name, path)),
            paths: host.name == null ? null : host.paths,
          );
    // The parts as the last run left them, before anything shows them.
    if (_workspace.ideView(folder) case final kept?) {
      space.layout
        ..terminals = (widget.terminalBackend?.supported ?? false)
        ..restore(kept);
    }
    if (_ideWindow) _trackEdited(space);
    if (folder == _noFolder) space.addListener(() => _followLooseFile(space));
    return space..askSavePath = (doc) => _askSavePath(space, doc);
  });

  /// Where the IDE's chat is without a folder open: in that of the file in
  /// front in the editor, once there is one; kept as its files close.
  final ValueNotifier<String?> _looseChatFolder = ValueNotifier(null);

  void _followLooseFile(IdeWorkspace space) {
    if (!mounted) return;
    // Told while building: once built.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      return WidgetsBinding.instance.addPostFrameCallback(
        (_) => _followLooseFile(space),
      );
    }
    final doc = space.active;
    if (doc == null || doc.isUntitled || doc.openError != null) return;
    final folder = p.dirname(doc.path);
    if (folder == _looseChatFolder.value) return;
    _workspace.ensureIdeChat(folder);
    _looseChatFolder.value = folder;
  }

  /// Finds the repositories of an IDE's folders' subfolders on [host], as
  /// settings.json's `git.autoRepositoryDetection` says when it opens.
  IdeRepositoryDetection? _repositoryDetection(ProjectHost host) {
    final gitFor = widget.gitFor;
    final repositoriesIn = widget.repositoriesIn;
    if (gitFor == null || repositoriesIn == null) return null;
    return IdeRepositoryDetection(
      find: (folder) => repositoriesIn(
        RemoteLocation.of(host.name, folder),
        IdeRepositoryScan.parse(
          widget.settings?.files?.settings.values ?? const {},
        ),
      ),
      open: (path) => gitFor(RemoteLocation.of(host.name, path)),
    );
  }

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
        : (_agentThread ?? _workspace.current)?.project;
    final windows = _multi ? _windows : null;
    final agent = _agentThread;
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
      sidebarShown: _narrow ? _drawerOpen : _sidebarDocked,
      onToggleSidebar: _toggle,
      ideLayout: ide ? _ideSpace(_ideFolder).layout : null,
      pinned: _pinned,
      onTogglePin: _setPinned,
      terminalShown: _terminals?.shown ?? false,
      onToggleTerminal: ide || _terminals?.root == null
          ? null
          : _toggleTerminal,
      sidePanelShown: _sidePanel.isShown && !_sidePanelHidden,
      onToggleSidePanel: ide || (agent ?? _workspace.current) == null
          ? null
          : _toggleSidePanel,
      chatTools: ide || !_toolsInPanes,
      onOpenFolder: _openFolder,
      onOpenSettings: () => unawaited(openSettings()),
      onToggleContextPanel: () {
        if (agent ?? _workspace.current case final thread?) {
          ChatScreen.toggleContextPanel(_chatKey(thread));
        }
      },
      onCommand: agent == null
          ? (command) => _chatCommands()[command]?.call()
          : null,
      onFileCommand: _runMenuCommand,
      autoSave: _autoSaveOn,
      compact: _narrow,
      settingsShown: _settingsOpen,
      title: _titleInHeader
          ? (agent ?? _workspace.current)?.localizedTitle(context.l10n)
          : null,
    );
  }

  /// Whether the conversations are side by side, each pane's title bar with
  /// its own agent's terminal, side panel and editor buttons (see
  /// [_buildChat]), as macOS has them: Windows' header then has only the
  /// window's, the pin.
  bool get _toolsInPanes =>
      !_agentWindow && !_replacingChat && _workspace.grid.length >= 2;

  /// Whether the session's title is in Windows' header (see
  /// [WindowHeader.title]), not a row of the chat's own: the narrow
  /// window's, with one conversation in it, as macOS's title bar has it.
  bool get _titleInHeader =>
      WindowControls.drawsHeader &&
      _narrow &&
      !_showsIde &&
      !_replacingChat &&
      // An agent's window has its one conversation.
      (_agentWindow ||
          (_workspace.grid.length <= 1 && _workspace.current != null));

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
            color: _dragging ? IdeModernUI.sashHover : AppColors.partBorder,
          ),
        ),
      ),
    );
  }

  /// Open Remote Project…: a folder of a host reached over SSH, opened as
  /// a project (in the IDE when asked [inIde]), or given to [onOpen]. The
  /// host is kept among the sidebar's once connected, and switched to when
  /// asked [switchTo]; [host] one known, not asked for.
  void _openRemoteProject({
    bool inIde = false,
    ValueChanged<String>? onOpen,
    String? host,
    bool switchTo = false,
  }) {
    final held = _newWindowHeld;
    late final OpenRemoteFlow flow;
    flow = OpenRemoteFlow(
      show: showQuickPick,
      l10n: context.l10n,
      added: _workspace.sshHosts,
      labelOf: _workspace.hostLabel,
      addressOf: (host) =>
          _workspace.sshServers[host]?.address ?? RemoteLocation.hostName(host),
      iconOf: _hostIcon,
      onAdd: (address) =>
          unawaited(_editSshServer(flow: flow, address: address)),
      onEdit: (host) => unawaited(_editSshServer(flow: flow, host: host)),
      onForgetHostKey: _forgetHostKey,
      onConnected: (host) {
        if (!mounted) return;
        _workspace.addSshHost(host);
        if (switchTo) _workspace.sidebarHost = host;
      },
      onOpen: (location) {
        if (!mounted) return;
        if (onOpen != null) {
          onOpen(location);
        } else if (inIde) {
          _openIdeFolder(location, held: held);
        } else {
          unawaited(_workspace.openFolder(location));
        }
      },
    );
    if (host != null) {
      flow.startAt(host);
    } else {
      unawaited(flow.start());
    }
  }

  /// The hosts of `~/.ssh/config`, as last read: edited there, not with
  /// the form (see the sidebar's host menu).
  List<String> _sshConfigHosts = const [];

  Future<List<String>> _loadSshConfigHosts() async {
    final hosts = await defaultRemoteConfigHosts().catchError(
      (Object _) => const <String>[],
    );
    return _sshConfigHosts = hosts;
  }

  /// The form of a server: adding one (at [address], when typed), or
  /// editing [host], from [flow]'s host picker or the sidebar's host menu
  /// (no [flow]). Saved, it is connected to when asked; from the picker,
  /// else the picker shows again, as it does when cancelled.
  Future<void> _editSshServer({
    OpenRemoteFlow? flow,
    String? host,
    String? address,
  }) async {
    final config = await _loadSshConfigHosts();
    if (!mounted) return;
    final result = await editSshServer(
      context,
      _workspace,
      host: host,
      address: address,
      configHosts: config,
      onWarning: (message) =>
          _notifications.notify(IdeSeverity.warning, message),
    );
    if (!mounted) return;
    if (result == null) {
      if (flow != null) unawaited(flow.start());
      return;
    }
    if (flow == null) {
      // Connected already: the new settings are for the next connection.
      final ssh = SshHosts.instance[result.host];
      if (result.connect && ssh.state != SshHostState.connected) {
        ssh.reconnect().ignore();
      }
    } else if (result.connect) {
      flow.startAt(result.host);
    } else {
      unawaited(flow.start());
    }
  }

  /// Asks whether to forget the host key known for [host], changed, and
  /// does: whether it did.
  Future<bool> _forgetHostKey(String host) async {
    final l10n = context.l10n;
    final choice = await showIdeDialog(
      context,
      message: l10n.remoteForgetHostKeyTitle(_workspace.hostLabel(host)),
      detail: l10n.remoteForgetHostKeyDetail,
      buttons: [l10n.remoteForgetHostKeyButton],
    );
    if (choice != 0 || !mounted) return false;
    try {
      await SshHosts.instance.forgetHostKey(host);
    } on Object catch (error) {
      if (mounted) {
        _notifications.notify(
          IdeSeverity.error,
          sshErrorText(error, l10n).$1 ?? '$error',
        );
      }
      return false;
    }
    return true;
  }

  /// A host's icon, as the workspace kept it (the host switcher's).
  Widget? _hostIcon(String host) =>
      switch (_workspace.iconOf(_workspace.hostIconProject(host))) {
        null => null,
        final icon => ProjectIconView(
          icon: icon,
          library: _workspace.icons,
          size: 16,
          color: AppColors.textMuted,
        ),
      };

  /// Open File… in a remote project (VS Code's, in a remote window): the
  /// current project's host, its folders browsed, the file picked opened
  /// where the IDE's files are (that host), by its path there. Nothing
  /// without a remote project (a local Open File… is this machine's).
  void _openRemoteFile() {
    final folder = _ideFolder;
    final host = RemoteLocation.hostOf(folder);
    if (host == null || host.isEmpty) return;
    final flow = OpenRemoteFileFlow(
      show: showQuickPick,
      l10n: context.l10n,
      hosts: SshHosts.instance,
      onOpen: (location) {
        if (!mounted) return;
        if (RemoteLocation.hostOf(location) != host) return;
        // This IDE's files are that host's: it opens the path there
        // (whatever folder it is in); the editor keeps it among its own
        // recently used.
        final path = RemoteLocation.pathOf(location);
        _afterBuild(() => _ide?.openFile(path));
      },
    );
    unawaited(flow.open(host, directory: RemoteLocation.pathOf(folder)));
  }

  /// The remote menu (the status bar's `SSH: <host>`, VS Code's remote
  /// indicator): the SSH hosts to switch to (opening a folder on one), the
  /// current host's connection, opening a folder or a file there, and
  /// adding a host. In the IDE, so its folder opens here ([inIde]).
  Future<void> _showRemoteMenu(String host) async {
    final l10n = context.l10n;
    final hosts = SshHosts.instance;
    final ssh = hosts[host];
    final others = [
      for (final name in _workspace.sshHosts)
        if (name != host) name,
    ];
    await showIdeMenu(
      context,
      anchor: _statusAnchor,
      alignRight: false,
      entries: [
        if (others.isNotEmpty) ...[
          for (final name in others)
            IdeMenuAction(
              _workspace.hostLabel(name),
              icon: _hostIcon(name) ?? const SizedBox.shrink(),
              onSelected: () =>
                  _openRemoteProject(host: name, switchTo: true, inIde: true),
            ),
          const IdeMenuSeparator(),
        ],
        if (ssh.state == SshHostState.connected)
          IdeMenuAction(
            l10n.sidebarDisconnectHost,
            icon: const Icon(Codicons.debugDisconnect),
            onSelected: () => unawaited(ssh.close()),
          )
        else
          IdeMenuAction(
            l10n.remoteReconnect,
            icon: const Icon(Codicons.refresh),
            onSelected: () => ssh.reconnect().ignore(),
          ),
        const IdeMenuSeparator(),
        IdeMenuAction(
          l10n.sidebarOpenFolderOn(RemoteLocation.hostName(host)),
          icon: const Icon(Codicons.folderOpened),
          onSelected: () =>
              _openRemoteProject(host: host, switchTo: true, inIde: true),
        ),
        IdeMenuAction(
          l10n.remoteOpenFileOn(RemoteLocation.hostName(host)),
          icon: const Icon(Codicons.file),
          onSelected: () => _openRemoteFile(),
        ),
        const IdeMenuSeparator(),
        IdeMenuAction(
          l10n.sidebarAddSshHost,
          icon: const Icon(Codicons.add),
          onSelected: () => _openRemoteProject(switchTo: true, inIde: true),
        ),
      ],
    );
  }

  /// Where the status bar's remote entry is, for the menu to drop from
  /// (set as the item is built).
  Rect _statusAnchor = Rect.zero;

  Future<void> _openFolder() async {
    final path = await WindowControls.pickDirectory();
    if (path == null || !mounted) return;
    final thread = await _workspace.openFolder(path);
    _closeDrawer();
    if (mounted) _watchFirstTurn(thread);
  }

  /// The open agents side by side (see [ChatGridView]), each with its
  /// project's terminal panel under it (see [_withTerminal]); of several,
  /// each with a side panel of its own (see [_paneSidePanel]), else the
  /// side panel at their right.
  Widget _buildPanes({required bool showToggle}) => _workspace.grid.length > 1
      ? _buildGrid(showToggle: showToggle)
      : _withSidePanel(
          _buildGrid(showToggle: showToggle),
          showToggle: showToggle,
        );

  void _showSidePanelSection(SidePanelSection section) {
    final thread = _agentThread ?? _workspace.current;
    if (thread != null) _sidePanel.showSection(thread.session, section);
  }

  Map<String, VoidCallback> _sidePanelCommands() => {
    ChatCommandIds.toggleSidePanel: _toggleSidePanel,
    ChatCommandIds.toggleSidePanelPosition: () =>
        _sidePanel.atLeft = !_sidePanel.atLeft,
    if (_sidePanel.hasFocus) ...{
      ChatCommandIds.sidePanelCloseTab: _closeSidePanelTab,
      ChatCommandIds.attachSelection: _addSidePanelSelectionToChat,
    },
    for (final section in alwaysShownSections)
      section.command!: () => _showSidePanelSection(section),
  };

  /// The focus of the focused agent's side panel: its pane's, of agents
  /// side by side, else the window's.
  FocusNode _sidePanelFocusOf(AgentThread thread) => _panesSidePanels
      ? _sidePanel.focusNodeOf(thread.session)
      : _sidePanel.focusNode;

  /// Add Selection to Chat, from the side panel: the lines selected in its
  /// file shown after what is typed in the agent's input, the keyboard
  /// there; with none, only the keyboard (Focus Chat Input).
  void _addSidePanelSelectionToChat() {
    final thread = _agentThread ?? _workspace.current;
    if (thread == null) return;
    thread.session.draft.insertCode(
      FilePreview.selectedAt(FocusManager.instance.primaryFocus?.context),
    );
    _focusChat(thread);
  }

  /// Close Tab, from the side panel; the focus stays there, for the next.
  void _closeSidePanelTab() {
    final thread = _agentThread ?? _workspace.current;
    if (thread == null) return;
    final focus = _sidePanelFocusOf(thread);
    // One with unsaved changes asks first whether to save them.
    if (_sidePanel.tabsOf(thread.session).current case final tab?
        when tab.dirty) {
      unawaited(
        closeSidePanelTabs(context, _sidePanel, thread.session, [tab]).then((
          _,
        ) {
          if (mounted && _sidePanelShownFor(thread)) focus.requestFocus();
        }),
      );
      return;
    }
    _sidePanel.closeCurrent(thread.session);
    if (_sidePanelShownFor(thread)) focus.requestFocus();
  }

  /// [showToggle]: the window's sidebar hidden, the panel at the
  /// conversations' left is at the window's, under the traffic lights.
  Widget _withSidePanel(
    Widget child, {
    required bool showToggle,
  }) => AgentSidePanelArea(
    panel: _sidePanel,
    // Customize, in place of the conversations, isn't one of theirs.
    hidden: _sidePanelHidden || _replacingChat,
    // Just under the conversation's title bar, whose right has the
    // window's buttons on macOS; at the top under Windows' header, already
    // a bar of its own (the title row's right is empty, the rail beside
    // its column).
    railTop: WindowControls.drawsHeader ? 12 : AppMetrics.titleBarHeight + 4,
    // Not in a narrow window, where the conversation has no room to spare
    // (the title bar's toggle shows the panel). Agents side by side have
    // one each, over their own pane (see [_paneRail]).
    rail: switch (_agentThread ?? _workspace.current) {
      final thread? when _agentThread != null || _workspace.grid.length < 2 =>
        _railFor(thread),
      _ => null,
    },
    builder: (context) => switch (_agentThread ?? _workspace.current) {
      final thread?
          when showToggle && _sidePanel.atLeft && !WindowControls.drawsHeader =>
        _buildSidePanel(
          thread,
          titleBarInset: AppMetrics.trafficLightsWidth,
          leading: SidebarIconButton(
            icon: Codicons.layoutSidebarLeftOff,
            tooltip: context.l10n.windowShowSidebar,
            command: 'workbench.action.toggleSidebarVisibility',
            onTap: _toggle,
          ),
        ),
      final thread? => _buildSidePanel(thread),
      null => const SizedBox.shrink(),
    },
    child: child,
  );

  /// [_sidePanelRail] for [thread], where it has one: not in a narrow
  /// window, in place of the conversations, nor for an agent not begun.
  Widget? _railFor(AgentThread thread) =>
      !_narrow && !_replacingChat && !thread.untouched
      ? _sidePanelRail(thread)
      : null;

  /// The side panel's quick entries for [thread]'s conversation, counting
  /// what its pages' bar counts: the changes of its repositories, its
  /// background commands running. A section picked shows for [thread],
  /// focused first.
  Widget _sidePanelRail(AgentThread thread) => ListenableBuilder(
    listenable: _worktreeSignals(thread),
    builder: (context, _) => _sidePanelRailOf(thread),
  );

  Widget _sidePanelRailOf(AgentThread thread) {
    final multi = _workspace.workspaceAt(thread.project.path);
    return SidePanelRail(
      onSelect: (section) {
        if (_agentThread == null && !identical(thread, _workspace.current)) {
          _workspace.select(thread);
        }
        _showSidePanelSection(section);
      },
      session: thread.session,
      gits: switch (_shownRepositories(
        thread,
        multi == null
            ? _sidePanelFolderRepositories(thread)
            : _sidePanelRepositories(multi),
      )) {
        [] => [?_shownGit(thread)],
        final repositories => [for (final (_, git) in repositories) git],
      },
    );
  }

  Widget _buildSidePanel(
    AgentThread thread, {
    double titleBarInset = 0,
    Widget? leading,
    bool windowTitleBar = true,
  }) {
    final location = thread.project.path;
    final multi = _workspace.workspaceAt(location);
    // Its IDE's repositories, found in the folders' subfolders as they are
    // looked for.
    if (_ideSpaces[multi?.path ?? location] case final space?) {
      return ListenableBuilder(
        listenable: space,
        builder: (context, _) => _sidePanelView(
          thread,
          titleBarInset: titleBarInset,
          leading: leading,
          windowTitleBar: windowTitleBar,
        ),
      );
    }
    return _sidePanelView(
      thread,
      titleBarInset: titleBarInset,
      leading: leading,
      windowTitleBar: windowTitleBar,
    );
  }

  Widget _sidePanelView(
    AgentThread thread, {
    double titleBarInset = 0,
    Widget? leading,
    bool windowTitleBar = true,
  }) => ListenableBuilder(
    listenable: _worktreeSignals(thread),
    builder: (context, _) => _sidePanelViewOf(
      thread,
      titleBarInset: titleBarInset,
      leading: leading,
      windowTitleBar: windowTitleBar,
    ),
  );

  Widget _sidePanelViewOf(
    AgentThread thread, {
    double titleBarInset = 0,
    Widget? leading,
    bool windowTitleBar = true,
  }) {
    final (:files, :paths) = _projectFiles(thread);
    final location = thread.project.path;
    final multi = _workspace.workspaceAt(location);
    return AgentSidePanelView(
      panel: _sidePanel,
      session: thread.session,
      files: files,
      readBytes: files is IdeHostFiles ? files.readBytes : readFileBytes,
      paths: paths,
      colorize: _colorizeCode,
      // The files page's search runs where the IDE's does: a workspace's
      // folders each, a remote project's there, a local one here.
      searchEngine: (root, query) => switch (files) {
        final IdeHostFiles host => host.searchText(root, query),
        _ when multi != null => IdeWorkbench.searchRoots(
          multi.folders,
          query,
          ideSearchText,
        ),
        _ => ideSearchText(root, query),
      },
      onOpenInIde: (request) => _openRequestInIde(thread, request),
      // With its IDE's language servers.
      formatter:
          (path, text, {range, required tabSize, required insertSpaces}) =>
              _ideSpace(multi?.path ?? location).formatOutside(
                path,
                text,
                range: range,
                tabSize: tabSize,
                insertSpaces: insertSpaces,
              ),
      git: _shownGit(thread),
      terminals: _terminals?.terminalsOf(thread.project.path),
      terminalHosts: _terminals?.hosts,
      terminalSkipShell: chatTerminalSkipShell,
      onOpenTerminalLink: _openTerminalLink,
      // Claude Haiku where the project is, as the IDE's Source Control.
      commitMessage: (prompt, {cancel}) =>
          ideClaudeCommitMessage(prompt, cancel: cancel, location: location),
      notifications: _notifications,
      workspaceName: multi?.name,
      roots: multi?.folders ?? const [],
      repositories: _shownRepositories(
        thread,
        multi == null
            ? _sidePanelFolderRepositories(thread)
            : _sidePanelRepositories(multi),
      ),
      worktreesOf: (git) {
        final folder = _shownFolders[git] ?? location;
        return IdeGitWorktreeChoice(
          agentPath: _agentWorkPathOf(thread).path,
          following: _sidePanel.worktreeOf(thread.session, folder) == null,
          onSelect: (path) =>
              _sidePanel.chooseWorktree(thread.session, folder, path),
        );
      },
      onAddFolder: multi == null
          ? null
          : () => unawaited(_addWorkspaceFolder(location)),
      onRemoveFolder: multi == null
          ? null
          : (folder) => _workspace.removeWorkspaceFolder(multi, folder),
      titleBarInset: titleBarInset,
      leading: leading,
      windowTitleBar: windowTitleBar,
    );
  }

  /// The repositories of [multi]'s folders the side panel lists: its
  /// IDE's, once open, else the panel's own.
  List<(String, IdeGitRepository)> _sidePanelRepositories(
    ProjectWorkspace multi,
  ) {
    if (_ideSpaces[multi.path] case final space?) return space.repositories;
    final gitFor = widget.gitFor;
    if (gitFor == null) return const [];
    return [
      for (final folder in multi.folders)
        (folder, _sidePanelGits[folder] ??= gitFor(folder)),
    ];
  }

  /// The repositories of [thread]'s folder and its subfolders the side
  /// panel lists, as Source Control does (`git.autoRepositoryDetection`):
  /// its IDE's, once open, else the panel's own, looked for once; none
  /// until some are found in the subfolders ([AgentSidePanelView.git] its
  /// one).
  List<(String, IdeGitRepository)> _sidePanelFolderRepositories(
    AgentThread thread,
  ) {
    final location = thread.project.path;
    if (_ideSpaces[location] case final space?) return space.repositories;
    final gitFor = widget.gitFor;
    final repositoriesIn = widget.repositoriesIn;
    if (gitFor == null || repositoriesIn == null) return const [];
    final found = _sidePanelFound[location];
    if (found == null) {
      _sidePanelFound[location] = const [];
      final host = ProjectHost.of(location);
      unawaited(() async {
        final List<String> paths;
        try {
          paths = await repositoriesIn(
            location,
            IdeRepositoryScan.parse(
              widget.settings?.files?.settings.values ?? const {},
            ),
          );
        } catch (_) {
          return;
        }
        if (!mounted || paths.isEmpty) return;
        setState(() {
          _sidePanelFound[location] = [
            for (final path in paths)
              (
                path,
                _sidePanelGits[RemoteLocation.of(host.name, path)] ??= gitFor(
                  RemoteLocation.of(host.name, path),
                ),
              ),
          ];
        });
      }());
      return const [];
    }
    if (found.isEmpty) return const [];
    return ideFolderRepositories(
      ProjectHost.of(location).pathOf(location),
      _sidePanelGit(thread),
      found,
    );
  }

  /// The repositories found in a project's subfolders for its side panel,
  /// by project; empty while being looked for.
  final Map<String, List<(String, IdeGitRepository)>> _sidePanelFound = {};

  /// The files of [thread]'s project, on its host, and how it spells
  /// their paths.
  ({IdeFileService files, p.Context paths}) _projectFiles(AgentThread thread) {
    final location = thread.project.path;
    final host = ProjectHost.of(location);
    return (
      files: _projectFileServices[location] ??= host.files(
        host.pathOf(location),
      ),
      paths: host.paths,
    );
  }

  final Map<String, IdeFileService> _projectFileServices = {};

  /// The repository whose changes the side panel lists for [thread]'s
  /// project: its IDE's, once open, else one of the panel's own (on the
  /// project's host); none without Git.
  IdeGitRepository? _sidePanelGit(AgentThread thread) {
    final location = thread.project.path;
    if (_ideSpaces[location]?.git case final git?) return git;
    final gitFor = widget.gitFor;
    if (gitFor == null) return null;
    return _sidePanelGits[location] ??= gitFor(location);
  }

  final Map<String, IdeGitRepository> _sidePanelGits = {};

  /// Under [thread]'s composer: the branch of its project, or its
  /// workspace's name and its folders' branches, with the side panel's
  /// repositories.
  Widget _branchBar(AgentThread thread) => ListenableBuilder(
    listenable: _worktreeSignals(thread),
    builder: (context, _) {
      final project = thread.project;
      final multi = _workspace.workspaceOf(project);
      final git = multi == null ? _shownGit(thread) : null;
      return ChatQuotaBar(
        session: thread.session,
        branch: ChatBranchBar(
          session: thread.session,
          name: multi?.name ?? project.name,
          workspace: multi != null,
          repositories: multi != null
              ? _shownRepositories(thread, _sidePanelRepositories(multi))
              : [if (git != null) (project.path, git)],
          onSwitchWorktree: widget.gitFor == null
              ? null
              : (folder, path) =>
                    _sidePanel.chooseWorktree(thread.session, folder, path),
        ),
      );
    },
  );

  // --- Where the agent works ---------------------------------------------------

  /// Where each conversation's agent works, told as it moves.
  final Map<ChatSession, AgentWorkPath> _agentWorkPaths = Map.identity();

  AgentWorkPath _agentWorkPathOf(AgentThread thread) =>
      _agentWorkPaths[thread.session] ??= AgentWorkPath(thread.session);

  /// What changes which worktree [thread]'s repositories show: where its
  /// agent works, the worktree picked, and the worktrees read.
  Listenable _worktreeSignals(AgentThread thread) {
    final multi = _workspace.workspaceAt(thread.project.path);
    return Listenable.merge([
      _agentWorkPathOf(thread),
      _sidePanel,
      ?_sidePanelGit(thread),
      if (multi != null)
        for (final (_, git) in _sidePanelRepositories(multi)) git,
    ]);
  }

  /// The folder of each repository the side panel shows, by it: a
  /// worktree's, the folder whose repository it is of.
  final Map<IdeGitRepository, String> _shownFolders = Map.identity();

  /// The worktrees read again for where the agent moved, by repository:
  /// once for each place.
  final Map<IdeGitRepository, String> _worktreesReadFor = Map.identity();

  /// [thread]'s project's repository as its side panel and branch show it
  /// (see [_worktreeGit]).
  IdeGitRepository? _shownGit(AgentThread thread) {
    final git = _sidePanelGit(thread);
    return git == null ? null : _worktreeGit(thread, thread.project.path, git);
  }

  List<(String, IdeGitRepository)> _shownRepositories(
    AgentThread thread,
    List<(String, IdeGitRepository)> repositories,
  ) => [
    for (final (folder, git) in repositories)
      (folder, _worktreeGit(thread, folder, git)),
  ];

  /// [git], [folder]'s repository, as [thread]'s conversation shows it: the
  /// worktree picked on its changes page, else the one its agent works in
  /// (the files it edits are there), else [git] itself.
  IdeGitRepository _worktreeGit(
    AgentThread thread,
    String folder,
    IdeGitRepository git,
  ) {
    _shownFolders[git] = folder;
    final gitFor = widget.gitFor;
    if (gitFor == null || !git.isRepository) return git;
    final paths = git.service.pathContext;
    final chosen = _sidePanel.worktreeOf(thread.session, folder);
    final agent = _agentWorkPathOf(thread).path;
    final worktrees = git.worktrees;
    if (chosen == null &&
        agent != null &&
        ideWorktreeOf(agent, worktrees, paths) == null &&
        _worktreesReadFor[git] != agent) {
      // Perhaps one made since they were read.
      _worktreesReadFor[git] = agent;
      unawaited(git.reloadWorktrees());
    }
    final target = agentShownWorktree(
      root: git.service.root,
      worktrees: worktrees,
      paths: paths,
      chosen: chosen,
      agentPath: agent,
    );
    if (target == null) return git;
    final location = RemoteLocation.of(
      RemoteLocation.hostOf(thread.project.path),
      target,
    );
    final worktree = _sidePanelGits[location] ??= gitFor(location);
    _shownFolders[worktree] = folder;
    return worktree;
  }

  final Map<String, Future<bool> Function(String)> _projectFileChecks = {};
  final Map<String, Future<Uint8List> Function(String)> _projectByteReaders =
      {};

  /// Where the files [thread]'s conversation names open: the side panel,
  /// or the IDE for its chat ([embedded]).
  /// The file of [thread]'s `/command` [name] (see [ChatScreen.commandFile]),
  /// on the machine it works on.
  Future<String?> _commandFileOf(AgentThread thread, String name) {
    final location = thread.session.kernelContext.cwd ?? thread.project.path;
    final host = RemoteLocation.hostOf(location);
    final store = host == null
        ? widget.customizations
        : _hostCustomizations[host] ??= CustomizationStore(
            disk: RemoteCustomizationDisk(SshHosts.instance[host]),
          );
    if (store == null) return Future.value();
    return store.commandFile(name, project: RemoteLocation.pathOf(location));
  }

  FileLinkTarget _fileLinks(AgentThread thread, {required bool embedded}) {
    final (:files, :paths) = _projectFiles(thread);
    return FileLinkTarget(
      open: embedded
          ? (request) => _openRequestInIde(thread, request)
          // From the conversation: the file alone, its list out of the way.
          : (request) => _sidePanel.open(
              thread.session,
              _agentChangeIn(thread.session, request),
              listAway: true,
            ),
      inPanel: !embedded,
      openInIde: embedded
          ? null
          : (request) => _openRequestInIde(thread, request),
      showBrowserTab: embedded
          ? null
          : (tabId) {
              BrowserTools.show(tabId);
              _sidePanel.showSection(thread.session, SidePanelSection.browser);
            },
      openFolder: embedded
          ? null
          : (path) => _sidePanel.openFolder(thread.session, path),
      exists: _projectFileChecks[thread.project.path] ??= fileExistsIn(
        files,
        paths: paths,
      ),
      // The same each build: the chat's images are kept by it.
      readBytes: _projectByteReaders[thread.project.path] ??= (path) =>
          readBytesThrough(files, path),
      sizeOf: (path) async => await byteSizeThrough(files, path) ?? 0,
      paths: paths,
      roots: () =>
          _workspace.workspaceAt(thread.project.path)?.folders ?? const [],
    );
  }

  /// [request] for a file's changes as the file itself where [session]'s
  /// change to it is pending: shown in its text, each part to keep or
  /// undo, as the IDE shows it.
  FileOpenRequest _agentChangeIn(ChatSession session, FileOpenRequest request) {
    if (!request.diff ||
        request.local ||
        request.change?.kind == FileChangeKind.deleted ||
        session.changeReview?.baseOf(request.path) == null) {
      return request;
    }
    return FileOpenRequest(
      request.path,
      range: request.range,
      change: request.change,
      agentChange: true,
    );
  }

  /// The first part of [thread]'s change pending in [path] scrolled to, once
  /// the IDE's editor shows the file.
  void _revealAgentChange(AgentThread thread, String path) {
    if (thread.session.changeReview?.baseOf(path) == null) return;
    _ideAgentEdits
        .putIfAbsent(thread.project.path, IdeAgentEdits.new)
        .hunksOf(path)
        .reveal();
  }

  /// Opens [request] in the IDE of [thread]'s project: a file's changes,
  /// the lines asked for, or the file.
  void _openRequestInIde(AgentThread thread, FileOpenRequest request) {
    // Shown as a file, on this machine: read-only, its text read here.
    if (request.local) {
      final remote = RemoteLocation.isRemote(thread.project.path);
      if (ideIsImagePath(request.path)) {
        // The IDE of a remote project reads its host's files only.
        if (remote) return unawaited(openExternal(request.path));
        return _inIdeOf(thread, (ide) => ide.open(request.path));
      }
      final label = context.l10n.shownReadOnly;
      return _inIdeOf(
        thread,
        (ide) => ide.openRevision(
          request.path,
          label: label,
          read: () => _localFiles.read(request.path),
        ),
      );
    }
    if (request.change case final change? when request.diff) {
      final range = request.range;
      return _openChange(
        thread,
        change,
        request.original,
        lines: range == null ? null : (start: range.start, end: range.end),
      );
    }
    if (request.range case final range?) {
      return _openCode(thread, request.path, range.start, range.end);
    }
    if (request.diff) _revealAgentChange(thread, request.path);
    _inIdeOf(thread, (ide) => ide.open(request.path));
  }

  /// Whether [thread]'s pane is the one showing its project's terminals:
  /// the first of its project's panes, so two panes of one project show
  /// them once (a terminal shows in one place at a time).
  bool _showsTerminals(AgentThread thread) {
    final panes = _workspace.grid.panes;
    return panes.isEmpty ||
        panes.firstWhere(
              (pane) => pane.project.path == thread.project.path,
              orElse: () => thread,
            ) ==
            thread;
  }

  /// [child] with [root]'s terminal panel under it (see
  /// [ChatTerminalArea]): in a pane, its own project's, at its width.
  Widget _withTerminal(Widget child, AgentThread thread) =>
      switch (_terminals) {
        final terminals? => ChatTerminalArea(
          terminals: terminals,
          root: thread.project.path,
          tasks: SessionTerminalTasks(thread.session),
          files: _projectFiles(thread).files,
          onOpenLink: _openTerminalLink,
          child: child,
        ),
        null => child,
      };

  Widget _buildGrid({required bool showToggle}) {
    if (_stashing) {
      if (StashController.current case final stash?) {
        return _buildStash(stash, showToggle: showToggle);
      }
    }
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
      paneBuilder: (context, thread, place) {
        // A project's terminals under the first of its panes: the panes of
        // one project show them once.
        final showsTerminals = _showsTerminals(thread);
        final chat = _buildChat(
          showToggle: showToggle,
          pane: thread,
          place: place,
          showsTerminals: showsTerminals,
        );
        return showsTerminals ? _withTerminal(chat, thread) : chat;
      },
      // Those not focused in the sidebar's color, set apart.
      paneBackground: (thread) => identical(thread, _workspace.current)
          ? null
          : AppColors.unfocusedConversationSurface,
      focused: _workspace.current,
      onLinesMoved: _workspace.keepGridLines,
    );
  }

  /// The stashes, in place of the conversations, as Customize is.
  Widget _buildStash(StashController stash, {required bool showToggle}) {
    final header = WindowControls.drawsHeader;
    return StashView(
      key: _stashKey,
      controller: stash,
      initial: _stashShown,
      onClose: _closeCustomize,
      onOpenAgent: _openAgent,
      onHotkeySettings: () => unawaited(openSettings(SettingsSection.stash)),
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
    );
  }

  /// Customize, in place of the conversations: its title bar as a chat's,
  /// the sidebar's toggle by the traffic lights while it is hidden.
  Widget _buildCustomize(CustomizationStore store, {required bool showToggle}) {
    final header = WindowControls.drawsHeader;
    // The machine the sidebar is on: a remote host's agents read its own.
    final host = _workspace.sidebarHost;
    final projects = _workspace.sidebarProjectsOn(host);
    final project = _paletteProject;
    return CustomizeView(
      key: _customizeKey,
      store: host == null
          ? store
          : _hostCustomizations[host] ??= CustomizationStore(
              disk: RemoteCustomizationDisk(SshHosts.instance[host]),
            ),
      host: host == null ? null : _workspace.hostLabel(host),
      projects: projects,
      project: project != null && projects.contains(project)
          ? project
          : projects.firstOrNull,
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

  /// An agent from the sidebar, or a pane's title bar, released over the
  /// conversations.
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
    if (drop.rearrange) {
      _workspace.rearrangePane(drop.thread, drop.target, side: drop.side);
    } else if (drop.side case final side?) {
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
  ///
  /// [openEditor] gives the file open beside it, for the agent to be told
  /// of: by default the side panel's. [showsTerminals] says its project's
  /// terminal panel is under it (see [_withTerminal]), whose toggle its
  /// title bar then has.
  Widget _buildChat({
    required bool showToggle,
    bool embedded = false,
    AgentThread? pane,
    ChatPanePlace place = _whole,
    OpenEditor? Function()? openEditor,
    bool showsTerminals = false,
  }) {
    final thread = pane ?? _workspace.current;
    // Windows keeps the toggle and the pin in its header (see
    // window_header/), and the terminal, side panel and editor buttons too
    // while there is one conversation: all that is left for its row is the
    // session's title, which then sits in the middle of it. Elsewhere the
    // toggle is in the top left pane, by the traffic lights, and the others
    // in each pane's title bar (the pin, the window's, in the top right one).
    final header = WindowControls.drawsHeader;
    // The side panel at the window's left has it, by the traffic lights.
    showToggle =
        showToggle && place.topLeft && (embedded || !_sidePanelAtWindowLeft);
    final leading = !header && showToggle
        ? SidebarIconButton(
            icon: Codicons.layoutSidebarLeftOff,
            tooltip: context.l10n.windowShowSidebar,
            command: 'workbench.action.toggleSidebarVisibility',
            onTap: _toggle,
          )
        : null;
    final titleBarInset = !header && showToggle
        ? AppMetrics.trafficLightsWidth + 8
        : 12.0;
    if (thread == null) {
      return _EmptyWorkspace(
        tips: _main ? _tips : null,
        narrow: _narrow,
        loading: _workspace.loading,
        leading: leading,
        titleBarInset: titleBarInset,
        onOpenFolder: WindowControls.canPickDirectory ? _openFolder : null,
        onOpenRemote: WindowControls.canPickDirectory
            ? _openRemoteProject
            : null,
      );
    }
    final windowTools = !header && !embedded && place.topRight;
    // Each pane is a window of its own: its title bar's buttons are its
    // agent's and its project's, not the focused agent's. Only the pin,
    // which is the window's, is the top right pane's alone. A click on any
    // of them leaves the focus where it is, as closing another pane does.
    // So under Windows' header too, once there are panes: the header keeps
    // the pin, and the others leave it for theirs (see [_toolsInPanes]).
    final paneTools = !embedded && (!header || !place.alone);
    final terminals = _terminals;
    // In the order of the IDE's title bar ([panel][chat][pin][back]): the
    // terminal and the side panel as its panel and chat, then the pin, then
    // the way to the other layout at the end, so each is where it was after
    // a switch.
    final tools = [
      if (!place.alone) ...[
        // With Close Pane's keys, which close the focused pane: as each of
        // upstream's tabs titles its close button with Close's.
        SidebarIconButton(
          icon: Codicons.close,
          tooltip: context.l10n.workspaceClosePane,
          command: ChatCommandIds.closePane,
          onTap: () => _workspace.closePane(thread),
        ),
        if (windowTools) const SizedBox(width: 8),
      ],
      if (paneTools) ...[
        // The panel is under each conversation (see [_withTerminal]), so
        // the button in a pane is that pane's project's.
        if (showsTerminals && terminals != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ChatTerminalToggle(
              shown: terminals.shownFor(thread.project.path),
              onTap: () => _toggleTerminalOf(thread),
              size: 22,
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: SidePanelToggle(
            shown: _sidePanelShownFor(thread),
            onTap: () => _toggleSidePanelOf(thread),
            size: 22,
          ),
        ),
        if (windowTools) ...[
          const SizedBox(width: 2),
          PinWindowButton(pinned: _pinned, onChanged: _setPinned),
          const SizedBox(width: 8),
        ],
        OpenInEditorButton(
          workspace: _workspace,
          project: thread.project,
          agent: thread,
          compact: !place.alone,
        ),
      ],
    ];
    final draggable = !embedded && !place.alone && _agentThread == null;
    // The layout's context keys, for the chat's keybindings (see ChatKeys).
    final chat = ChatKeyScope(
      lookup: embedded ? _ideChatKeyContext : _chatKeyContext,
      child: ChatScreen(
        key: _chatKey(thread),
        embedded: embedded,
        session: thread.session,
        title: thread.localizedTitle(context.l10n),
        autofocus: thread.session.itemCount == 0,
        onRename: (title) => _workspace.rename(thread, title),
        titleDragBuilder: draggable
            ? (title) => MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: ChatDragSource(
                  drag: _drag,
                  thread: thread,
                  rearrange: true,
                  child: title,
                ),
              )
            : null,
        onTitleDragStart: draggable
            ? (event) => _drag.start(
                thread,
                event.pointer,
                event.position,
                rearrange: true,
              )
            : null,
        // Beside the sidebar, the traffic lights are over it, not here.
        titleBarInset: titleBarInset,
        leading: leading,
        trailing: tools.isEmpty
            ? null
            : KeepPaneFocus(
                child: Row(mainAxisSize: MainAxisSize.min, children: tools),
              ),
        windowTitleBar: place.top,
        titleBar: !(place.alone && _titleInHeader),
        focused: place.alone || identical(thread, _workspace.current),
        onOpenChange: (change, original) =>
            _openChange(thread, change, original),
        onOpenCode: (path, start, end) => _openCode(thread, path, start, end),
        fileLinks: _fileLinks(thread, embedded: embedded),
        onOpenTerminalTask: embedded
            ? (task) => _ide?.showTerminalTask(task.id)
            : (task) => _sidePanel.openTerminal(thread.session, task.id),
        colorizeCode: _colorizeCode,
        colorizeCodeBlock: _colorizeCodeBlock,
        // Where a new agent is to work: the IDE's chat works in the IDE's
        // project, and a kept session where it was.
        start: embedded || thread.record != null
            ? null
            : NewChatFolderBar(
                workspace: _workspace,
                thread: thread,
                openRemote: (onOpen, {host}) =>
                    _openRemoteProject(onOpen: onOpen, host: host),
              ),
        // The setup checklist, over the new agent's composer.
        startHint: switch (_tips) {
          final tips? when _main => (context, hint) => FeatureTipsCard(
            controller: tips,
            narrow: _narrow,
            orElse: hint,
          ),
          _ => null,
        },
        below: _branchBar(thread),
        sessions: () => _mentionable(thread),
        fileMentions: _fileMentionsOf(thread.project),
        commandFile: widget.customizations == null
            ? null
            : (name) => _commandFileOf(thread, name),
        openEditor: openEditor ?? () => _sidePanelEditor(thread),
      ),
    );
    if (place.alone || embedded) return chat;
    return _paneSidePanel(thread, chat, top: place.top);
  }

  /// [chat], a pane among others, with a side panel of its own, of its
  /// agent: beside it on its side, as the window's beside one conversation;
  /// over it where the pane has not the room. While it is hidden, its rail
  /// over the pane's top right (left, the panel at the left), under its
  /// title bar.
  ///
  /// [top]: the pane is along the window's top, and so is the panel's bar.
  Widget _paneSidePanel(AgentThread thread, Widget chat, {required bool top}) =>
      AgentSidePanelArea(
        panel: _sidePanel,
        conversation: thread.session,
        hidden: _sidePanelHidden,
        rail: _railFor(thread),
        builder: (context) => _buildSidePanel(thread, windowTitleBar: top),
        child: chat,
      );

  /// The file in front on the side panel, while it shows [thread]'s: on
  /// the files page, where it is edited (its cursor and selection with
  /// it); on the changes page, whose changes show.
  OpenEditor? _sidePanelEditor(AgentThread thread) {
    if (!_sidePanelShownFor(thread) || _replacingChat) return null;
    if (!_panesSidePanels &&
        !identical(_agentThread ?? _workspace.current, thread)) {
      return null;
    }
    final tabs = _sidePanel.tabsOf(thread.session);
    return switch (tabs.shown) {
      SidePanelSection.files => switch (tabs.active) {
        SidePanelTab(:final path, edit: final edit?) => OpenEditor.at(
          path,
          edit.controller.document.snapshot,
          edit.controller.value.selection,
        ),
        final tab? => OpenEditor(tab.path),
        null => null,
      },
      SidePanelSection.changes => switch (tabs.activeDiff) {
        final tab? => OpenEditor(tab.path),
        null => null,
      },
      SidePanelSection.terminal ||
      SidePanelSection.browser ||
      SidePanelSection.plan => null,
    };
  }

  /// The conversations [thread]'s messages may refer to, under their
  /// projects (see [Workspace.mentionable]).
  List<Suggestion> _mentionable(AgentThread thread) {
    final l10n = context.l10n;
    return [
      for (final (:project, :threads) in _workspace.mentionable(thread))
        for (final other in threads)
          Suggestion.session(
            title: other.localizedTitle(l10n),
            id: other.id!,
            project: project.name,
          ),
    ];
  }

  /// Opens a file [thread]'s agent changed in the IDE: the file, its
  /// change shown in it with Undo and Keep (see [IdeAgentEdits]), at
  /// [lines] when given; its text before the change ([original]) alone
  /// where the agent deleted it.
  void _openChange(
    AgentThread thread,
    FileChange change,
    Future<String> Function()? original, {
    ({int start, int end})? lines,
  }) {
    if ((original, change.kind) case (final read?, FileChangeKind.deleted)) {
      final label = context.l10n.stripChangesDiff;
      return _inIdeOf(
        thread,
        (ide) => ide.openRevision(change.path, label: label, read: read),
      );
    }
    if (lines != null) {
      return _openCode(thread, change.path, lines.start, lines.end);
    }
    _revealAgentChange(thread, change.path);
    _inIdeOf(thread, (ide) => ide.open(change.path));
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
    // An agent's window shows its own alone.
    if (_agentWindow) return;
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
  bool terminalsRunning({required bool childProcesses}) =>
      (_terminals?.running(childProcesses: childProcesses) ?? false) ||
      _ideKeys.values.any(
        (key) =>
            key.currentState?.terminalsRunning(
              childProcesses: childProcesses,
            ) ??
            false,
      );

  /// The quick pick over the chat's window, while it shows (see
  /// [showQuickPick]); its keys are keybindings (see [_handleQuickInputKey]).
  GlobalKey<IdeQuickInputState>? _quickInputKey;

  /// Hides that quick pick.
  VoidCallback? _hideQuickInput;

  @override
  void showQuickPick(IdeQuickPick pick) {
    if (_ide case final ide? when _showsIde) {
      ide.showQuickPick(pick);
      return;
    }
    // The chat's window: over it, as the IDE shows one, in place of one
    // shown already.
    _hideQuickInput?.call();
    final key = _quickInputKey = GlobalKey<IdeQuickInputState>();
    var closed = false;
    void hide() {
      if (closed || !mounted) return;
      closed = true;
      // The dialog's navigator (see showGeneralDialog).
      Navigator.of(context, rootNavigator: true).pop();
    }

    _hideQuickInput = hide;
    unawaited(
      showGeneralDialog<void>(
        context: context,
        barrierColor: Colors.transparent,
        // Over the whole window, header included: below it, as the IDE's.
        pageBuilder: (context, _, _) => Padding(
          padding: EdgeInsets.only(
            top: WindowControls.drawsHeader
                ? WindowControls.headerInset
                : AppMetrics.titleBarHeight,
          ),
          child: IdeQuickInput.pick(key: key, pick: pick, onClose: hide),
        ),
      ).then((_) {
        closed = true;
        if (identical(_quickInputKey, key)) {
          _quickInputKey = null;
          _hideQuickInput = null;
        }
        pick.onDidHide?.call();
      }),
    );
  }

  /// A key for the quick pick over the chat's window: the quick input's
  /// keybindings (Escape hides it, Enter accepts, the arrows move), as the
  /// IDE resolves them for its own.
  bool _handleQuickInputKey(IdeQuickInputState quick, KeyEvent event) {
    void focus(IdeQuickPickFocus what) => quick.focus(what);
    final commands = <String, VoidCallback>{
      'quickInput.next': () => focus(IdeQuickPickFocus.next),
      'quickInput.previous': () => focus(IdeQuickPickFocus.previous),
      'quickInput.first': () => focus(IdeQuickPickFocus.first),
      'quickInput.last': () => focus(IdeQuickPickFocus.last),
      'quickInput.pageNext': () => focus(IdeQuickPickFocus.nextPage),
      'quickInput.pagePrevious': () => focus(IdeQuickPickFocus.previousPage),
      'quickInput.accept': quick.accept,
      'quickInput.acceptInBackground': () => quick.accept(inBackground: true),
      'quickInput.hide': quick.hide,
      'workbench.action.closeQuickOpen': quick.hide,
      'workbench.action.acceptSelectedQuickOpenItem': quick.accept,
      'workbench.action.focusQuickOpen': quick.focusInput,
      'workbench.action.quickOpenSelectNext': () => quick.navigate(next: true),
      'workbench.action.quickOpenSelectPrevious': () =>
          quick.navigate(next: false),
      'workbench.action.quickOpenNavigateNext': () =>
          quick.navigate(next: true),
      'workbench.action.quickOpenNavigatePrevious': () =>
          quick.navigate(next: false),
    };
    final result = KeybindingService.instance.resolveEvent(
      event,
      context: (key) => switch (key) {
        'inQuickOpen' || 'inQuickInput' => true,
        'quickInputType' => 'quickPick',
        'cursorAtEndOfQuickInputBox' => quick.cursorAtEnd,
        'inputFocus' || 'textInputFocus' =>
          FocusManager.instance.primaryFocus?.context
                  ?.findAncestorStateOfType<EditableTextState>() !=
              null,
        _ => null,
      },
      canRun: (item) => commands.containsKey(item.command),
    );
    if (result case KeybindingFound(:final command)) {
      commands[command]!();
      return true;
    }
    return false;
  }

  @override
  void runCommand(String command) => _runMenuCommand(command);

  /// The code agents cite or write in the editor's colors, by TextMate:
  /// started as the first is shown.
  TextMateSyntax? _chatCode;

  TextMateSyntax get _chatSyntax =>
      _chatCode ??= TextMateSyntax(themes: WorkbenchThemeService.instance);

  Future<List<List<TextSpan>>?> _colorizeCode(String path, String code) async {
    final syntax = _chatSyntax;
    final language = await syntax.languageIdForPath(path);
    return language == null ? null : syntax.colorize(language, code);
  }

  Future<List<List<TextSpan>>?> _colorizeCodeBlock(
    String language,
    String code,
  ) => _chatSyntax.colorize(language, code);
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
    this.tips,
    this.narrow = false,
    required this.loading,
    required this.titleBarInset,
    this.leading,
    this.onOpenFolder,
    this.onOpenRemote,
  });

  final bool loading;
  final double titleBarInset;
  final Widget? leading;
  final VoidCallback? onOpenFolder;

  /// The setup checklist, under the buttons.
  final FeatureTipsController? tips;

  /// The window narrow (see [Workbench.narrowWidth]): the checklist a tile
  /// a row.
  final bool narrow;

  /// Open Remote Project…: a folder on a host reached over SSH.
  final VoidCallback? onOpenRemote;

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
                  if (onOpenRemote case final remote?) ...[
                    const SizedBox(height: 8),
                    IntrinsicWidth(
                      child: PanelButton(
                        label: l10n.cmdOpenRemoteFolder.replaceFirst(
                          RegExp(r'(\.\.\.|…)$'),
                          '',
                        ),
                        onTap: remote,
                      ),
                    ),
                  ],
                ],
                if (tips case final tips? when !loading)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: FeatureTipsCard(controller: tips, narrow: narrow),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
