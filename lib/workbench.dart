import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'chat/chat_keys.dart';
import 'chat/chat_screen.dart';
import 'chat/panels/interaction_panel.dart';
import 'ide/git/git_repository.dart';
import 'ide/ide_commands.dart';
import 'ide/ide_modern_ui.dart';
import 'ide/ide_notifications.dart';
import 'ide/ide_workbench.dart';
import 'ide/ide_workspace.dart';
import 'ide/lsp/language_features.dart';
import 'ide/terminal/terminal_instance.dart';
import 'keybindings/chat_keybindings.dart';
import 'keybindings/default_keybindings.dart';
import 'keybindings/key_chord.dart';
import 'keybindings/keybinding_service.dart';
import 'l10n/l10n.dart';
import 'settings/app_settings.dart';
import 'settings/data_dir_startup.dart';
import 'settings/jsonc_file.dart';
import 'settings/settings_dialog.dart';
import 'sidebar/sidebar.dart';
import 'theme/codicons.dart';
import 'theme/app_theme.dart';
import 'theme/workbench_theme.dart' show WorkbenchThemeService, themeColors;
import 'workspace/chat_drag.dart';
import 'workspace/chat_grid_view.dart';
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
  });

  final Workspace workspace;

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

class _WorkbenchState extends State<Workbench> {
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
  final Map<String, IdeWorkspace> _ideSpaces = {};

  /// The window is kept above other apps' windows.
  bool _pinned = false;

  /// An agent dragged from the sidebar onto the conversations.
  late final ChatDrag _drag = ChatDrag(onDrop: _drop, onStart: _closeDrawer);

  void _setPinned(bool pinned) {
    setState(() => _pinned = pinned);
    WindowControls.setAlwaysOnTop(pinned);
  }

  /// Back in the app, the list picks up sessions started elsewhere (e.g.
  /// in a terminal) meanwhile.
  late final AppLifecycleListener _lifecycle;

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
    WindowControls.onMenuCommand = _runMenuCommand;
    WindowControls.handleEditCommands();
    WindowControls.handleWindowEvents();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_workspace.refresh()),
    );
    widget.settings?.files?.changes.addListener(_settingsFilesChanged);
    _settingsFilesChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
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
    _drag.dispose();
    _width.dispose();
    _lifecycle.dispose();
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _keybindings.removeListener(_keybindingsChanged);
    if (WindowControls.onMenuCommand == _runMenuCommand) {
      WindowControls.onMenuCommand = null;
    }
    _chordTimer?.cancel();
    widget.settings?.files?.changes.removeListener(_settingsFilesChanged);
    _notifications.dispose();
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
      if (current != null)
        ChatCommandIds.openIde: () => _workspace.layout = WorkspaceLayout.ide,
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
        if (!thread.archived) thread,
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
    if (!identical(thread, _workspace.current)) _workspace.select(thread);
    _focusChat(thread);
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
    _focusChat(_workspace.create());
  }

  /// Shows the sidebar if hidden, and focuses its search.
  void _searchAgents() {
    final shown = _narrow ? _drawerOpen : _docked;
    if (!shown) _toggle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sidebarLink.focusSearch();
    });
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
        _workspace.layout == WorkspaceLayout.ide ||
        KeyChord.fromEvent(event) == null ||
        !mounted) {
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

  /// A command of the system's menu bar (the app menu's Preferences…).
  void _runMenuCommand(String command) {
    if (command == openSettingsCommandId) unawaited(openSettings());
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
        return ColoredBox(
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
                bottom: _workspace.layout == WorkspaceLayout.ide ? 36 : 12,
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
    final project = _workspace.current?.project;
    final ide = _workspace.layout == WorkspaceLayout.ide && project != null;
    if (ide) _ideSpace(project);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final entry in _ideSpaces.entries)
          Offstage(
            key: ValueKey(entry.key),
            offstage: !ide || project.path != entry.key,
            child: TickerMode(
              enabled: ide && project.path == entry.key,
              child: ExcludeFocus(
                excluding: !ide || project.path != entry.key,
                child: IdeWorkbench(
                  workspace: entry.value,
                  project: Project.at(entry.key),
                  visible: ide && project.path == entry.key,
                  onBack: () => _workspace.layout = WorkspaceLayout.chat,
                  pinned: _pinned,
                  onPinnedChanged: _setPinned,
                  editorBuilder: widget.ideEditorBuilder,
                  ignoredRecommendations:
                      _workspace.ignoredServerRecommendations,
                  onIgnoreRecommendation: _workspace.ignoreServerRecommendation,
                  colorThemes: WorkbenchThemeService.instance,
                  commands: _settingsCommands,
                  terminalBackend:
                      widget.terminalBackend ??
                      const TerminalBackend(supported: false),
                  chat: ide && project.path == entry.key
                      ? _conversation(
                          _buildChat(showToggle: false, embedded: true),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        if (!ide) narrow ? _buildNarrow() : _buildWide(),
      ],
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
      onOpened: onOpened,
      onOpenFolder: WindowControls.canPickDirectory ? _openFolder : null,
      onOpenSettings: () => unawaited(openSettings()),
      drag: _drag,
    );
  }

  /// The bar Windows draws itself, over the sidebar and the chat (see
  /// window_header/): the sidebar toggle, the menus, the pin, the editor
  /// button and the window buttons, all of which are in the columns
  /// themselves elsewhere.
  /// The IDE's workspace for [project], made the first time it is shown
  /// (the header, built first, may be the first to ask).
  IdeWorkspace _ideSpace(Project project) => _ideSpaces.putIfAbsent(
    project.path,
    () => IdeWorkspace(
      project.path,
      languages: widget.languagesFor?.call(project.path),
      git: widget.gitFor?.call(project.path),
    ),
  );

  Widget _buildHeader() {
    final project = _workspace.current?.project;
    return WindowHeader(
      workspace: _workspace,
      project: project,
      sidebarShown: _narrow ? _drawerOpen : _docked,
      onToggleSidebar: _toggle,
      ideLayout: _workspace.layout == WorkspaceLayout.ide && project != null
          ? _ideSpace(project).layout
          : null,
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
    );
  }

  /// The chat of [thread]: a state of its own for each (and kept as it
  /// moves between the wide and narrow layouts), reached by the header.
  static GlobalKey _chatKey(Object thread) => GlobalObjectKey(thread);

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
        // Files come from the agent's own lookup, not a fixed list.
        mentions: const [],
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
                  PanelButton(
                    label: l10n.sidebarOpenFolder,
                    primary: true,
                    onTap: open,
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
