import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../base/give_way_row.dart';
import '../base/smooth_scroll.dart';
import '../chat/chat_keys.dart';
import '../chat/floating/floating_placement.dart';
import '../chat/widgets/hover_builder.dart';
import '../chat/widgets/inline_rename_field.dart';
import '../chat/widgets/pixel_loader.dart';
import '../forge/forge_api.dart' show ForgeState;
import '../forge/forge_ref.dart' show ForgeItemKind;
import '../forge/forge_view.dart' show forgeStateLook;
import '../icons/project_icon_picker.dart';
import '../icons/project_icon_view.dart';
import '../ide/ide_button.dart' show IdeButtonColors;
import '../ide/ide_commands.dart' show ideUsesMacKeys;
import '../ide/ide_hover.dart';
import '../ide/ide_list.dart';
import '../ide/ide_spinning.dart';
import '../kernel/agent_kernel.dart' show KernelChoiceKind;
import '../keybindings/chat_keybindings.dart';
import '../keybindings/default_keybindings.dart' show openSettingsCommandId;
import '../keybindings/keybinding_service.dart';
import '../l10n/l10n.dart';
import '../models/model_provider.dart' show parseModelRef;
import '../models/model_providers.dart';
import '../remote/remote_location.dart';
import '../remote/remote_status.dart' show sshErrorText;
import '../remote/ssh_host.dart' show SshHost, SshHostState, SshHosts;
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../update/update_service.dart';
import '../workspace/chat_drag.dart';
import '../workspace/editor_launcher.dart';
import '../workspace/title_bar_double_click.dart';
import '../workspace/window_controls.dart';
import '../workspace/workspace.dart';
import '../workspace/workspace_dialog.dart';
import 'sidebar_menu.dart';
import 'sidebar_times.dart';

enum SidebarGrouping {
  project('Project', Icons.folder_outlined),
  time('Date', Icons.schedule_rounded),
  status('Status', Icons.radio_button_checked_rounded);

  const SidebarGrouping(this.label, this.icon);

  /// In English; see [localizedLabel].
  final String label;
  final IconData icon;

  String localizedLabel(AppLocalizations l10n) => switch (this) {
    project => l10n.sidebarGroupingProject,
    time => l10n.sidebarGroupingDate,
    status => l10n.sidebarGroupingStatus,
  };

  /// `By project`, as the list's heading says how it is grouped.
  String localizedBy(AppLocalizations l10n) => switch (this) {
    project => l10n.sidebarByProject,
    time => l10n.sidebarByDate,
    status => l10n.sidebarByStatus,
  };
}

/// `now`, `5m`, `3h`, `2d`, `3w`, then the date; in [l10n]'s language
/// (English when null).
String relativeTime(DateTime time, DateTime now, [AppLocalizations? l10n]) {
  final strings = l10n ?? englishLocalizations;
  final elapsed = now.difference(time);
  if (elapsed.inMinutes < 1) return strings.sidebarTimeNow;
  if (elapsed.inHours < 1) return strings.sidebarTimeMinutes(elapsed.inMinutes);
  if (elapsed.inDays < 1) return strings.sidebarTimeHours(elapsed.inHours);
  if (elapsed.inDays < 7) return strings.sidebarTimeDays(elapsed.inDays);
  if (elapsed.inDays < 35) return strings.sidebarTimeWeeks(elapsed.inDays ~/ 7);
  return strings.sidebarMonthDay('${time.month}', time.day);
}

/// A heading and the agents under it.
class _Group {
  const _Group(this.id, this.label, this.threads, {this.project});

  final String id;
  final String label;
  final List<AgentThread> threads;

  /// Set for a project group, which can start a new agent there.
  final Project? project;

  bool get pinned => id == _pinnedGroup;
}

const _pinnedGroup = 'pinned';

/// The group of the archived agents, while they show.
const _archivedGroup = 'archived';

/// Where an agent dragged within the list would go: in [group], before or
/// after an agent there, or on top (neither).
@immutable
class _Spot {
  const _Spot(this.group, {this.before, this.after});

  final _Group group;
  final AgentThread? before;
  final AgentThread? after;

  @override
  bool operator ==(Object other) =>
      other is _Spot &&
      other.group.id == group.id &&
      identical(other.before, before) &&
      identical(other.after, after);

  @override
  int get hashCode => Object.hash(group.id, before, after);
}

/// What the list shows of a group: its rows, and how many more there are
/// (shown on asking), or that all are and can be fewer again.
typedef _Rows = ({List<AgentThread> threads, int more, bool less});

enum _ListRowKind { header, thread, more, pinZone }

/// Visible row data, independent of whether the list built its widget.
class _ListRow {
  const _ListRow(
    this.kind,
    this.group,
    this.key,
    this.extent, {
    this.thread,
    this.more,
  });

  final _ListRowKind kind;
  final _Group group;
  final Key key;
  final double extent;
  final AgentThread? thread;
  final _Rows? more;
}

/// What the window asks of its sidebar, for the chat's keybindings: the
/// agents in the order it lists them.
class SidebarLink {
  _SidebarState? _state;

  /// Whether a sidebar is built (shown, or tucked away beside the chat).
  bool get attached => _state != null;

  /// The agents listed, top to bottom (not those of collapsed groups);
  /// null without a sidebar.
  List<AgentThread>? get visibleThreads => _state?._visibleThreads();
}

/// Agents list: new agent, search and customize, the agents grouped by
/// project, date or status, pinned ones on top and archived ones tucked
/// away at the bottom.
class Sidebar extends StatefulWidget {
  const Sidebar({
    super.key,
    required this.workspace,
    required this.onCollapse,
    this.onOpened,
    this.onOpenFolder,
    this.onAddSshHost,
    this.onOpenFolderOn,
    this.editSshHost,
    this.onOpenSettings,
    this.onSearch,
    this.onCustomize,
    this.customizing = false,
    this.onStash,
    this.stashing = false,
    this.stashes,
    this.drag,
    this.link,
    this.current,
    this.onSelect,
    this.onNewAgent,
    this.updates,
    this.onUpdate,
    this.setup,
  });

  /// Over the foot's row: the setup checklist folded ("Setup n/m"), which
  /// shows nothing when the checklist does not fold there.
  final Widget? setup;

  final Workspace workspace;

  /// The app's updates: while one waits to be installed
  /// ([UpdateService.pending]), an Update button beside the gear, which
  /// runs [onUpdate] (Restart to Update).
  final UpdateService? updates;
  final VoidCallback? onUpdate;

  /// The agent shown where the sidebar is, selected among the rows: an
  /// agent's window's own; by default the workspace's current one.
  final AgentThread? current;

  /// Shows an agent picked here; by default the workspace selects it.
  final ValueChanged<AgentThread>? onSelect;

  /// Opens a new agent in a project (by default the current one's); by
  /// default the workspace creates it.
  final ValueChanged<Project?>? onNewAgent;

  /// Opens a project's folder in an app (a project's menu); replaceable
  /// under test.
  @visibleForTesting
  static Future<bool> Function(Editor editor, String path) launch =
      openInEditor;
  final VoidCallback onCollapse;

  /// Where rows are dragged to show beside the open agent; none when null.
  final ChatDrag? drag;

  /// Asks for a folder to open as a project; null where there is none to
  /// ask (the web).
  final VoidCallback? onOpenFolder;

  /// Adds an SSH host (connected to, then a folder there to open, or not),
  /// listed once connected: the heading switches between this machine and
  /// the hosts. None, none added here.
  final VoidCallback? onAddSshHost;

  /// Asks for a folder of an SSH host to open as a project.
  final ValueChanged<String>? onOpenFolderOn;

  /// How to edit an SSH host's connection (the host picker's form): null
  /// where it cannot be (one of `~/.ssh/config`, edited there).
  final VoidCallback? Function(String host)? editSshHost;

  /// Opens the settings: the gear at the bottom; none without it.
  final VoidCallback? onOpenSettings;

  /// Opens the search palette (agents, what was said in them, files,
  /// actions); no Search row without it.
  final VoidCallback? onSearch;

  /// Shows Claude Code's customizations in place of the chat; no
  /// Customize row without it.
  final VoidCallback? onCustomize;

  /// They show: the Customize row is selected.
  final bool customizing;

  /// Shows the stashes in place of the chat (docs/stash.md); no Stash row
  /// without it.
  final VoidCallback? onStash;

  /// They show: the Stash row is selected.
  final bool stashing;

  /// The stashes each conversation carries out, on its row; none without
  /// the Stash.
  final SidebarStashes? stashes;

  /// An agent was opened or created from here (the drawer closes).
  final VoidCallback? onOpened;

  /// Reaches this sidebar from the window.
  final SidebarLink? link;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar>
    with IdeKeyboardList<Sidebar>
    implements ChatDragList {
  static const _rowHeight = IdeListColors.rowHeight;

  /// The agents a project shows until asked for more (pinned ones apart).
  static const _recent = 5;

  AgentThread? _renaming;

  /// Renaming the SSH host switched to, in the heading.
  bool _renamingHost = false;

  /// The heading's host icon, the icon picker's anchor.
  final GlobalKey _hostIconKey = GlobalKey();

  /// Keeps the relative times current.
  late final Timer _clock;

  Workspace get _workspace => widget.workspace;

  // Kept by the workspace, between runs and as the sidebar is built anew
  // (between the docked sidebar and the drawer, not built while closed).
  SidebarGrouping get _grouping =>
      SidebarGrouping.values.asNameMap()[_workspace.sidebarGrouping] ??
      SidebarGrouping.project;
  bool get _showArchived => _workspace.showArchived;

  final ScrollController _listScroll = SmoothScrollController();
  final FocusNode _listFocus = FocusNode();
  final IdeListSelection<AgentThread> _listSelection = IdeListSelection();

  bool _rowsDirty = true;
  AgentThread? _listedCurrent;
  List<Project> _listProjects = const [];
  List<_ListRow> _listRows = const [];
  List<double> _rowOffsets = const [0];
  Map<Key, int> _rowIndices = const {};
  Map<AgentThread, int> _threadIndices = const {};
  Timer? _autoScroll;
  Offset? _dragPosition;
  Offset? _projectDragPosition;
  List<Project> _projectDragProjects = const [];

  /// Shows the archived agents or hides them; shown, they are scrolled to,
  /// at the bottom of the list.
  void _toggleArchived() {
    final show = !_showArchived;
    _workspace.showArchived = show;
    if (!show) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_scrollToEnd());
    });
  }

  /// The list lays out only nearby rows; its extent can settle by a few
  /// pixels as the last rows enter the viewport.
  Future<void> _scrollToEnd() async {
    for (var i = 0; i < 4; i++) {
      if (!mounted || !_listScroll.hasClients) return;
      final position = _listScroll.position;
      final end = position.maxScrollExtent;
      if (position.pixels >= end) return;
      await position.animateTo(
        end,
        duration: Duration(milliseconds: i == 0 ? 240 : 120),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      _rowsDirty = true;
      setState(() {});
    });
    _workspace.addListener(_markRowsDirty);
    SidebarTimes.shown.addListener(_timesChanged);
    _listFocus.addListener(_focusChanged);
    widget.link?._state = this;
    _attachDrag(widget.drag);
  }

  void _markRowsDirty() => _rowsDirty = true;

  void _timesChanged() => setState(_markRowsDirty);

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rowsDirty = true;
  }

  @override
  void didUpdateWidget(Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      oldWidget.workspace.removeListener(_markRowsDirty);
      widget.workspace.addListener(_markRowsDirty);
      _rowsDirty = true;
    }
    if (oldWidget.link != widget.link) {
      if (oldWidget.link?._state == this) oldWidget.link!._state = null;
      widget.link?._state = this;
    }
    if (oldWidget.drag != widget.drag) {
      _dragPosition = null;
      _stopAutoScroll();
      _detachDrag(oldWidget.drag);
      _attachDrag(widget.drag);
    }
    // Customize or the Stash shown: its row is the one picked, not the
    // conversation picked before it.
    if (_onPage && !(oldWidget.customizing || oldWidget.stashing)) {
      _listSelection.select(null);
    }
  }

  /// Customize or the Stash is shown in place of the chat.
  bool get _onPage => widget.customizing || widget.stashing;

  @override
  void dispose() {
    if (widget.link?._state == this) widget.link!._state = null;
    _detachDrag(widget.drag);
    _workspace.removeListener(_markRowsDirty);
    SidebarTimes.shown.removeListener(_timesChanged);
    _clock.cancel();
    _autoScroll?.cancel();
    _listFocus.removeListener(_focusChanged);
    _listFocus.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  /// The agents listed, top to bottom (see [_buildList]).
  List<AgentThread> _visibleThreads() => [
    for (final group in _groups()) ..._rows(group).threads,
  ];

  /// Whether [group] folds: not the only project's, which is all there is.
  bool _collapsible(_Group group) => group.project == null || _projectsShown;

  bool _collapsed(_Group group) =>
      _collapsible(group) && _workspace.isCollapsed(group.id);

  /// A project's most recent agents, unless asked for all (the open one
  /// too, wherever it is).
  _Rows _rows(_Group group) {
    if (_collapsed(group)) return (threads: const [], more: 0, less: false);
    final all = group.threads;
    if (group.project == null || all.length <= _recent) {
      return (threads: all, more: 0, less: false);
    }
    if (_workspace.isExpanded(group.id)) {
      return (threads: all, more: 0, less: true);
    }
    final current = _current;
    final shown = [
      for (final (i, thread) in all.indexed)
        if (i < _recent || identical(thread, current)) thread,
    ];
    return (threads: shown, more: all.length - shown.length, less: false);
  }

  /// A new agent nothing was sent to is listed only while it shows: one
  /// left for another is not worth a row.
  bool _listed(AgentThread thread) =>
      !_workspace.isHidden(thread.project) &&
      _workspace.listsHost(thread.project.host) &&
      (!thread.untouched ||
          identical(thread, _current) ||
          _workspace.grid.contains(thread));

  AgentThread? get _current => widget.current ?? _workspace.current;

  void _open(AgentThread thread) {
    (widget.onSelect ?? _workspace.select)(thread);
    widget.onOpened?.call();
  }

  /// A plain click opens immediately; modifier clicks only change selection.
  void _handleRowTap(AgentThread thread) {
    _listFocus.requestFocus();
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed) {
      _selectRange(thread);
      return;
    }
    if (ideUsesMacKeys ? keyboard.isMetaPressed : keyboard.isControlPressed) {
      setState(() => _listSelection.toggle(thread));
      return;
    }
    setState(() => _listSelection.select(thread));
    _open(thread);
  }

  List<AgentThread> get _selectable => [
    for (final row in _listRows) ?row.thread,
  ];

  void _selectRange(AgentThread thread) =>
      setState(() => _listSelection.range(thread, _selectable));

  List<AgentThread> _targetsFor(AgentThread thread) =>
      _listSelection.values.length < 2 ||
          !_listSelection.values.contains(thread)
      ? [thread]
      : [
          for (final row in _listRows)
            if (row.thread case final t? when _listSelection.values.contains(t))
              t,
        ];

  void _rowContext(AgentThread thread) {
    _listFocus.requestFocus();
    if (_listSelection.values.contains(thread)) return;
    setState(() => _listSelection.select(thread));
  }

  @override
  bool get listHasFocus => _listFocus.hasFocus;

  @override
  int get listLength => _selectable.length;

  @override
  int get listFocusedIndex => switch (_listSelection.focused) {
    final thread? => _selectable.indexOf(thread),
    null => -1,
  };

  @override
  int get listPageSize => ideRowsPerPage(_listScroll, rowHeight: _rowHeight);

  @override
  bool get listSupportsMultiselect => true;

  @override
  bool get listHasSelection =>
      _listSelection.focused != null || _listSelection.values.isNotEmpty;

  @override
  void listFocusAt(int index) {
    final visible = _selectable;
    if (visible.isEmpty) return;
    final thread = visible[index.clamp(0, visible.length - 1)];
    setState(() => _listSelection.select(thread));
    _revealRow(thread);
  }

  @override
  void listSelect() {
    if (_listSelection.focused case final thread?) _open(thread);
  }

  @override
  void listExpandSelection(int delta) {
    final visible = _selectable;
    if (visible.isEmpty) return;
    final index = listFocusedIndex;
    if (index < 0) return listFocusAt(0);
    final next = visible[(index + delta).clamp(0, visible.length - 1)];
    _selectRange(next);
    _revealRow(next);
  }

  @override
  void listSelectAll() => setState(() => _listSelection.selectAll(_selectable));

  @override
  void listClear() => setState(() => _listSelection.select(null));

  KeyEventResult _onListKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || _renaming != null) {
      return KeyEventResult.ignored;
    }
    int rows(Object? args) => args is num ? args.toInt() : 1;
    final commands = <String, void Function(Object?)>{
      'list.focusDown': (args) => listFocusNext(rows(args)),
      'list.focusUp': (args) => listFocusNext(-rows(args)),
      'list.focusPageDown': (_) => listFocusPage(1),
      'list.focusPageUp': (_) => listFocusPage(-1),
      'list.focusFirst': (_) => listFocusFirst(),
      'list.focusLast': (_) => listFocusLast(),
      'list.expandSelectionDown': (_) => listExpandSelection(1),
      'list.expandSelectionUp': (_) => listExpandSelection(-1),
      'list.selectAll': (_) => listSelectAll(),
      'list.clear': (_) => listClear(),
      'list.select': (_) => listSelect(),
      'list.toggleExpand': (_) => listToggleExpand(),
    };
    final resolution = KeybindingService.instance.resolveEvent(
      event,
      context: (key) => switch (key) {
        'listFocus' || 'listSupportsKeyboardNavigation' => true,
        'listSupportsMultiselect' => listSupportsMultiselect,
        'listHasSelectionOrFocus' => listHasSelection,
        'inputFocus' || 'textInputFocus' => false,
        _ => null,
      },
      canRun: (item) => commands.containsKey(item.command),
    );
    if (resolution case KeybindingFound(:final command, :final item)) {
      commands[command]!(item.entry.args);
      return KeyEventResult.handled;
    }
    return ideListNavigationKeys.contains(event.logicalKey)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  void _revealRow(AgentThread thread) {
    final index = _threadIndices[thread];
    if (index == null) return;
    ideRevealRange(_listScroll, _rowOffsets[index], _rowOffsets[index + 1]);
  }

  void _create([Project? project]) {
    // Where the sidebar lists: the open agent's project if it is there.
    project ??= switch (_current?.project) {
      final current? when _workspace.listsHost(current.host) => current,
      _ => _workspace.sidebarProjectsHere.firstOrNull,
    };
    if (widget.onNewAgent case final open?) {
      open(project);
    } else {
      _workspace.create(project: project);
    }
    widget.onOpened?.call();
  }

  List<_Group> _groups() {
    final l10n = context.l10n;
    final threads = [
      for (final thread in _workspace.threads)
        // Archived ones are listed whatever their project: the footer
        // counts them all, so one of a project taken off the sidebar (see
        // [Workspace.hideProject]) would be counted with no way back.
        if ((thread.archived
                ? _workspace.listsHost(thread.project.host)
                : _listed(thread)) &&
            _workspace.listsInSidebar(thread))
          thread,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final active = [
      for (final thread in threads)
        if (!thread.archived) thread,
    ];
    final pinned = _workspace.inPinnedOrder([
      for (final thread in active)
        if (thread.pinned) thread,
    ]);
    final rest = [
      for (final thread in active)
        if (!thread.pinned) thread,
    ];
    List<AgentThread> where(bool Function(AgentThread) test) =>
        rest.where(test).toList();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int daysAgo(AgentThread thread) {
      final time = thread.updatedAt;
      return today.difference(DateTime(time.year, time.month, time.day)).inDays;
    }

    return [
      // While an agent is dragged, a place to pin it, if none is yet.
      if (pinned.isNotEmpty || _pinZone)
        _Group(_pinnedGroup, l10n.sidebarPinned, pinned),
      ...switch (_grouping) {
        SidebarGrouping.project => [
          for (final project in _workspace.sidebarProjectsHere)
            _Group(
              Workspace.projectGroup(project.path),
              // Every host's together: a remote one's says where it is.
              switch (project.host) {
                final host? when _workspace.sidebarAllHosts =>
                  '${project.name} · ${_workspace.hostLabel(host)}',
                _ => project.name,
              },
              _workspace.inProjectOrder(
                project,
                where((thread) => thread.project == project),
              ),
              project: project,
            ),
        ],
        SidebarGrouping.time => [
          _Group('today', l10n.sidebarToday, where((t) => daysAgo(t) <= 0)),
          _Group(
            'yesterday',
            l10n.sidebarYesterday,
            where((t) => daysAgo(t) == 1),
          ),
          _Group(
            'week',
            l10n.sidebarPrevious7Days,
            where((t) => daysAgo(t) > 1 && daysAgo(t) <= 7),
          ),
          _Group('older', l10n.sidebarOlder, where((t) => daysAgo(t) > 7)),
        ],
        SidebarGrouping.status => [
          _Group(
            'needsInput',
            l10n.sidebarNeedsInput,
            where((t) => t.shownStatus == ThreadStatus.needsInput),
          ),
          _Group(
            'running',
            l10n.sidebarRunning,
            where((t) => t.shownStatus == ThreadStatus.running),
          ),
          _Group(
            'unread',
            l10n.sidebarUnread,
            where((t) => t.shownStatus == ThreadStatus.unread),
          ),
          _Group(
            'idle',
            l10n.sidebarDone,
            where((t) => t.shownStatus == ThreadStatus.idle),
          ),
        ],
      },
      if (_showArchived)
        _Group(_archivedGroup, l10n.sidebarArchived, [
          for (final thread in threads)
            if (thread.archived) thread,
        ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.sidebarSurface,
      child: ListenableBuilder(
        listenable: _workspace,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The toggle lives in the window's header on Windows (see
            // window_header/), which is where this row would have been.
            if (!WindowControls.drawsHeader) _buildTopBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                8,
                AppMetrics.contentInset,
                8,
                6,
              ),
              // A new chat picks its folder over its input (see
              // NewChatFolderBar): a folder first only without any.
              child: _NewAgentButton(
                onTap: switch (_workspace.sidebarHost) {
                  final host? when _workspace.sidebarProjectsOn(host).isEmpty =>
                    () => widget.onOpenFolderOn?.call(host),
                  null when _workspace.sidebarProjectsHere.isEmpty =>
                    widget.onOpenFolder ?? () {},
                  _ => _create,
                },
              ),
            ),
            if (switch (_workspace.sidebarHost) {
                  final host? when widget.onOpenFolderOn != null =>
                    () => widget.onOpenFolderOn!(host),
                  null => widget.onOpenFolder,
                  _ => null,
                }
                case final open?)
              _NavRow(
                icon: Codicons.folderOpened,
                label: context.l10n.sidebarOpenProject,
                onTap: open,
              ),
            if (widget.onSearch case final search?)
              _NavRow(
                icon: Codicons.search,
                label: context.l10n.sidebarSearch,
                hover: ChatKeys.titleWithKey(
                  context.l10n.cmdChatSearch,
                  ChatCommandIds.search,
                  ChatKeys.chatLayout,
                ),
                onTap: search,
              ),
            if (widget.onCustomize case final customize?)
              _NavRow(
                icon: Codicons.plug,
                label: context.l10n.sidebarCustomize,
                selected: widget.customizing,
                onTap: customize,
              ),
            if (widget.onStash case final stash?)
              switch (widget.stashes) {
                final stashes? => ListenableBuilder(
                  listenable: stashes.changes,
                  builder: (context, _) => _NavRow(
                    icon: Codicons.note,
                    label: context.l10n.stashTitle,
                    selected: widget.stashing,
                    badge: stashes.news(),
                    badgeHover: context.l10n.stashNewsSidebar(stashes.news()),
                    onTap: stash,
                  ),
                ),
                null => _NavRow(
                  icon: Codicons.note,
                  label: context.l10n.stashTitle,
                  selected: widget.stashing,
                  onTap: stash,
                ),
              },
            if (widget.onSearch != null ||
                widget.onCustomize != null ||
                widget.onStash != null)
              const SizedBox(height: 4),
            _buildGroupingBar(),
            Expanded(child: _buildList()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  /// Under the window's traffic lights; the collapse button on the right.
  Widget _buildTopBar() {
    return TitleBarDoubleClick(
      child: SizedBox(
        height: AppMetrics.titleBarHeight,
        child: Row(
          children: [
            const Spacer(),
            SidebarIconButton(
              icon: Codicons.layoutSidebarLeft,
              tooltip: context.l10n.windowHideSidebar,
              command: 'workbench.action.toggleSidebarVisibility',
              onTap: widget.onCollapse,
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupingBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 2),
      child: Row(
        children: [
          Expanded(
            child: _workspace.sshHosts.isEmpty
                ? Text(
                    context.l10n.sidebarAgents,
                    style: TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: _buildHostSwitcher(),
                  ),
          ),
          ?_buildCollapseAll(),
          SidebarMenu(
            width: 150,
            placement: (side: FloatingSide.bottom, align: FloatingAlign.end),
            items: () => [
              for (final grouping in SidebarGrouping.values)
                SidebarMenuItem(
                  grouping.localizedLabel(context.l10n),
                  icon: grouping.icon,
                  checked: grouping == _grouping,
                  onSelected: () => _workspace.sidebarGrouping = grouping.name,
                ),
            ],
            builder: (context, menu) => HoverBuilder(
              cursor: SystemMouseCursors.click,
              builder: (context, hovered) => GestureDetector(
                onTap: menu.open,
                child: Container(
                  height: 20,
                  padding: const EdgeInsets.only(left: 6, right: 2),
                  decoration: BoxDecoration(
                    color: hovered || menu.isOpen
                        ? AppColors.hover
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _grouping.localizedBy(context.l10n),
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 14,
                        color: AppColors.textFaint,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Folds every group that folds, or, all folded, unfolds them (#300):
  /// shown where there are several to fold.
  Widget? _buildCollapseAll() {
    final groups = [
      for (final group in _groups())
        if (_collapsible(group)) group.id,
    ];
    if (groups.length < 2) return null;
    final expand = groups.every(_workspace.isCollapsed);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: SidebarIconButton(
        icon: expand ? Codicons.expandAll : Codicons.collapseAll,
        tooltip: expand ? l10n.sidebarExpandAll : l10n.sidebarCollapseAll,
        size: 20,
        onTap: () => _workspace.setCollapsed(groups, !expand),
      ),
    );
  }

  /// The heading once there are SSH hosts: where the sidebar lists (this
  /// machine, or a host, its connection's dot after it), and a menu to
  /// switch, add a host, or open a folder there, reconnect, disconnect or
  /// remove it. A dot over the icon while agents elsewhere need the user.
  Widget _buildHostSwitcher() {
    final l10n = context.l10n;
    final hosts = SshHosts.instance;
    return ListenableBuilder(
      listenable: hosts,
      builder: (context, _) {
        final current = _workspace.sidebarHost;
        final all = _workspace.sidebarAllHosts;
        final elsewhere = _needingYou(
          where: (host) => !_workspace.listsHost(host),
        );
        final icon = _HostIcon(
          key: _hostIconKey,
          workspace: _workspace,
          host: current,
          all: all,
          attention: _mostUrgent(elsewhere),
        );
        if (_renamingHost && current != null) {
          return Row(
            children: [
              icon,
              const SizedBox(width: 5),
              Expanded(
                child: InlineRenameField(
                  initial: _workspace.hostLabel(current),
                  style: TextStyle(color: AppColors.text, fontSize: 11.5),
                  onDone: (name) {
                    setState(() => _renamingHost = false);
                    if (name != null) _workspace.renameHost(current, name);
                  },
                ),
              ),
            ],
          );
        }
        final label = all
            ? l10n.sidebarAllHosts
            : current == null
            ? l10n.sidebarThisMachine
            : _workspace.hostLabel(current);
        return SidebarMenu(
          width: 240,
          placement: (side: FloatingSide.bottom, align: FloatingAlign.start),
          items: () => _hostItems(l10n),
          builder: (context, menu) => HoverBuilder(
            cursor: SystemMouseCursors.click,
            builder: (context, hovered) => _RowHover(
              content: (context) => Text(
                [
                  if (current != null && label != current) current,
                  elsewhere.isEmpty
                      ? l10n.sidebarSwitchHost
                      : l10n.sidebarElsewhereNeedsYou(elsewhere.length),
                ].join('\n'),
              ),
              child: GestureDetector(
                onTap: menu.open,
                child: Container(
                  height: 20,
                  padding: const EdgeInsets.only(left: 4, right: 2),
                  decoration: BoxDecoration(
                    color: hovered || menu.isOpen
                        ? AppColors.hover
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      icon,
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (current != null) ...[
                        const SizedBox(width: 5),
                        _HostDot(hosts[current]),
                      ],
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 14,
                        color: AppColors.textFaint,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The agents not archived that wait on the user or finished unseen, on
  /// the hosts [where] takes (null for this machine).
  List<AgentThread> _needingYou({required bool Function(String?) where}) => [
    for (final thread in _workspace.threads)
      if (!thread.archived &&
          !_workspace.isHidden(thread.project) &&
          _workspace.listsInSidebar(thread) &&
          where(thread.project.host) &&
          (thread.status == ThreadStatus.needsInput ||
              thread.status == ThreadStatus.unread))
        thread,
  ];

  static ThreadStatus? _mostUrgent(List<AgentThread> threads) =>
      threads.any((t) => t.status == ThreadStatus.needsInput)
      ? ThreadStatus.needsInput
      : threads.isEmpty
      ? null
      : ThreadStatus.unread;

  List<SidebarMenuItem> _hostItems(AppLocalizations l10n) {
    final current = _workspace.sidebarHost;
    final hosts = SshHosts.instance;
    String? waiting(String? host) {
      final count = _needingYou(where: (h) => h == host).length;
      return count == 0 ? null : '$count';
    }

    final add = widget.onAddSshHost;
    final open = widget.onOpenFolderOn;
    final ssh = current == null ? null : hosts[current];
    final all = _workspace.sidebarAllHosts;
    return [
      SidebarMenuItem(
        l10n.sidebarAllHosts,
        leading: _HostIcon(
          workspace: _workspace,
          host: null,
          all: true,
          attention: null,
        ),
        checked: all,
        onSelected: () => _workspace.sidebarAllHosts = true,
      ),
      SidebarMenuItem(
        l10n.sidebarThisMachine,
        leading: _HostIcon(workspace: _workspace, host: null, attention: null),
        detail: waiting(null),
        checked: !all && current == null,
        onSelected: () => _workspace.sidebarHost = null,
      ),
      for (final host in _workspace.sshHosts)
        SidebarMenuItem(
          RemoteLocation.hostName(host),
          leading: _HostIcon(
            workspace: _workspace,
            host: host,
            attention: null,
          ),
          detail: waiting(host) ?? _stateLabel(l10n, hosts[host]),
          checked: current == host,
          onSelected: () => _workspace.sidebarHost = host,
        ),
      if (add != null) ...[
        const SidebarMenuItem.divider(),
        SidebarMenuItem(
          l10n.sidebarAddSshHost,
          icon: Codicons.add,
          onSelected: add,
        ),
      ],
      if (current != null && ssh != null) ...[
        const SidebarMenuItem.divider(),
        if (open != null)
          SidebarMenuItem(
            l10n.sidebarOpenFolderOn(current),
            icon: Codicons.folderOpened,
            onSelected: () => open(current),
          ),
        SidebarMenuItem(
          l10n.sidebarRenameHost,
          icon: Icons.edit_outlined,
          onSelected: () => setState(() => _renamingHost = true),
        ),
        if (widget.editSshHost?.call(current) case final edit?)
          SidebarMenuItem(
            l10n.sidebarEditHost,
            icon: Codicons.gear,
            onSelected: edit,
          ),
        SidebarMenuItem(
          l10n.sidebarChangeIcon,
          icon: Icons.emoji_emotions_outlined,
          onSelected: () => _openHostIconPicker(current),
        ),
        if (ssh.state == SshHostState.connected)
          SidebarMenuItem(
            l10n.sidebarDisconnectHost,
            icon: Codicons.debugDisconnect,
            onSelected: () => unawaited(ssh.close()),
          )
        else
          SidebarMenuItem(
            l10n.remoteReconnect,
            icon: Codicons.refresh,
            onSelected: () => ssh.reconnect().ignore(),
          ),
        SidebarMenuItem(
          l10n.sidebarRemoveHost,
          icon: Codicons.trash,
          destructive: true,
          onSelected: () => unawaited(_confirmRemoveHost(current)),
        ),
      ],
    ];
  }

  /// [host]'s icon picker, under its icon in the heading.
  void _openHostIconPicker(String host) {
    final box = _hostIconKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    ProjectIconPicker.toggle(
      context,
      workspace: _workspace,
      project: _workspace.hostIconProject(host),
      anchor: box.localToGlobal(Offset.zero) & box.size,
    );
  }

  static String _stateLabel(AppLocalizations l10n, SshHost host) =>
      switch (host.state) {
        SshHostState.connected => l10n.sidebarHostConnected,
        SshHostState.connecting ||
        SshHostState.reconnecting => l10n.sidebarHostConnecting,
        SshHostState.failed => l10n.sidebarHostDisconnected,
        SshHostState.idle => l10n.sidebarHostIdle,
      };

  Future<void> _confirmRemoveHost(String host) async {
    final confirmed = await showDialog<bool>(
      context: context,
      // Black, not the theme's: as upstream's dialogs dim the window.
      barrierColor: const Color(0x99000000),
      builder: (context) {
        final l10n = context.l10n;
        return _ConfirmDialog(
          title: l10n.sidebarRemoveHostTitle(RemoteLocation.hostName(host)),
          message: l10n.sidebarRemoveHostMessage,
          action: l10n.sidebarRemove,
        );
      },
    );
    if (confirmed ?? false) _workspace.removeSshHost(host);
  }

  /// A host switched to with no project there: a folder there to open.
  Widget _buildNoProjectsOn(String host) {
    final open = widget.onOpenFolderOn;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.sidebarNoProjectsOn(RemoteLocation.hostName(host)),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textFaint, fontSize: 12),
          ),
          if (open != null) ...[
            const SizedBox(height: 10),
            HoverBuilder(
              cursor: SystemMouseCursors.click,
              builder: (context, hovered) => GestureDetector(
                onTap: () => open(host),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: hovered ? AppColors.hover : Colors.transparent,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Codicons.folderOpened,
                        size: 13,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          context.l10n.sidebarOpenFolderOn(
                            RemoteLocation.hostName(host),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Anchors for the list and project icon popovers.
  final Map<Object, BuildContext> _slots = {};
  static const _listSlot = #list;

  Widget _buildList() {
    final switched = !identical(_listedCurrent, _current);
    if (switched) _rowsDirty = true;
    if (_rowsDirty) {
      _listedCurrent = _current;
      final groups = [
        for (final group in _groups())
          // Empty projects stay to start an agent in; other empty groups go.
          if (group.threads.isNotEmpty || group.project != null || group.pinned)
            group,
      ];
      _listProjects = [for (final group in groups) ?group.project];
      final rows = <_ListRow>[];
      for (final group in groups) {
        rows.add(_ListRow(_ListRowKind.header, group, ValueKey(group.id), 32));
        if (group.pinned && group.threads.isEmpty) {
          rows.add(
            _ListRow(_ListRowKind.pinZone, group, const ValueKey(#pinZone), 30),
          );
        }
        final shown = _rows(group);
        for (final thread in shown.threads) {
          rows.add(
            _ListRow(
              _ListRowKind.thread,
              group,
              ObjectKey(thread),
              _rowHeight,
              thread: thread,
            ),
          );
        }
        if (shown.more > 0 || shown.less) {
          rows.add(
            _ListRow(
              _ListRowKind.more,
              group,
              ValueKey('${group.id}.more'),
              24,
              more: shown,
            ),
          );
        }
      }
      _listRows = rows;
      final offsets = <double>[0];
      for (final row in rows) {
        offsets.add(offsets.last + row.extent);
      }
      _rowOffsets = offsets;
      _rowIndices = {for (final (index, row) in rows.indexed) row.key: index};
      _threadIndices = {
        for (final (index, row) in rows.indexed) ?row.thread: index,
      };
      // Another agent shown, opened from wherever (a new one, the search,
      // a shortcut): the rows picked follow it, not left on the one before.
      if (switched && !_listSelection.values.contains(_current)) {
        _listSelection.select(
          _onPage || !_threadIndices.containsKey(_current) ? null : _current,
        );
      }
      _listSelection.values.retainWhere(_threadIndices.containsKey);
      if (!_threadIndices.containsKey(_listSelection.focused)) {
        _listSelection.focused = null;
      }
      if (!_threadIndices.containsKey(_listSelection.anchor)) {
        _listSelection.anchor = null;
      }
      _rowsDirty = false;
    }
    final rows = _listRows;
    final projects = _listProjects;
    if (rows.isEmpty) {
      if (_workspace.sidebarHost case final host?) {
        return _buildNoProjectsOn(host);
      }
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          context.l10n.sidebarNoAgentsYet,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textFaint, fontSize: 12),
        ),
      );
    }
    return Focus(
      focusNode: _listFocus,
      onKeyEvent: _onListKey,
      child: _Slot(
        slot: _listSlot,
        slots: _slots,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            _listFocus.requestFocus();
            listClear();
          },
          child: ListView.builder(
            controller: _listScroll,
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: rows.length,
            itemExtentBuilder: (index, _) =>
                index < rows.length ? rows[index].extent : null,
            findChildIndexCallback: (key) => _rowIndices[key],
            itemBuilder: (context, index) {
              final row = rows[index];
              final child = switch (row.kind) {
                _ListRowKind.header => _Slot(
                  slot: row.group.id,
                  slots: _slots,
                  child: _buildHeader(row.group, projects),
                ),
                _ListRowKind.thread => _buildRow(row.thread!, row.group),
                _ListRowKind.pinZone => _PinZone(
                  height: _rowHeight,
                  active: _spot?.group.id == row.group.id,
                ),
                _ListRowKind.more => _MoreRow(
                  label: row.more!.less
                      ? context.l10n.sidebarShowLess
                      : context.l10n.sidebarShowMore(row.more!.more),
                  onTap: () => _workspace.toggleExpanded(row.group.id),
                ),
              };
              final spot = _spot;
              final before =
                  (row.thread != null && identical(spot?.before, row.thread)) ||
                  (row.kind == _ListRowKind.header &&
                      row.group.project != null &&
                      _projectSpot == projects.indexOf(row.group.project!));
              final after =
                  (row.thread != null && identical(spot?.after, row.thread)) ||
                  (row.kind == _ListRowKind.header &&
                      spot != null &&
                      spot.group.id == row.group.id &&
                      spot.before == null &&
                      spot.after == null &&
                      row.group.threads.isNotEmpty) ||
                  (index == rows.length - 1 && _projectSpot == projects.length);
              return Stack(
                key: row.key,
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: child),
                  if (before)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _DropLine(),
                    ),
                  if (after)
                    const Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: _DropLine(),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(_Group group, List<Project> projects) {
    final project = group.project;
    final collapsible = _collapsible(group);
    final header = _GroupHeader(
      group: group,
      collapsed: _collapsed(group),
      light: !collapsible,
      onToggle: collapsible ? () => _workspace.toggleCollapsed(group.id) : null,
      onCreate: project == null ? null : () => _create(project),
      // The archived agents' as the footer's toggle has it: unarchive or
      // delete them all.
      menu: project != null
          ? () => _projectItems(project)
          : group.id == _archivedGroup
          ? () => _archivedItems(context.l10n)
          : null,
      folders: project == null
          ? null
          : _workspace.workspaceOf(project)?.folders,
      dragged: project != null && identical(project, _draggedProject),
      pinned: project != null && _workspace.isPinnedProject(project),
      icon: project == null
          ? null
          : _Slot(
              slot: _iconSlot(project),
              slots: _slots,
              child: _HeaderIcon(
                project: project,
                workspace: _workspace,
                onTap: () => _openIconPicker(project),
              ),
            ),
    );
    // Projects are ordered by dragging their headers, where there are
    // several to order.
    if (project == null || projects.length < 2) return header;
    return _ProjectDragSource(
      onStart: () => setState(() => _draggedProject = project),
      onUpdate: (position) => _moveProjectDrag(position, projects),
      onEnd: () => _endProjectDrag(projects),
      child: header,
    );
  }

  Widget _buildRow(AgentThread thread, _Group group) =>
      switch (widget.stashes) {
        // Linked to one, or done with it, meanwhile.
        final stashes? => ListenableBuilder(
          listenable: stashes.changes,
          builder: (context, _) => _buildThreadRow(thread, group),
        ),
        null => _buildThreadRow(thread, group),
      };

  /// The model [thread] runs on, by its upstream and name: its session's,
  /// open, else the one it opens with again (#245).
  String? _modelOf(AgentThread thread) {
    if (thread.isOpen) {
      if (thread.session.models?.selected case final model?) {
        return [?model.group?.label, model.label].join(' · ');
      }
    }
    final kept = _workspace.keptChoice(thread, KernelChoiceKind.model);
    if (parseModelRef(kept) case (:final provider, :final model)) {
      final upstream = ModelProviders.current.provider(provider);
      final name = upstream?.models
          .where((option) => option.id == model)
          .firstOrNull
          ?.displayName;
      return [?upstream?.name, name ?? model].join(' · ');
    }
    return kept;
  }

  Widget _buildThreadRow(AgentThread thread, _Group group) {
    return _ThreadRow(
      thread: thread,
      model: () => _modelOf(thread),
      height: _rowHeight,
      stashes: switch ((widget.stashes, thread.id)) {
        (final stashes?, final session?) => stashes.of(session),
        _ => const [],
      },
      onOpenStash: widget.stashes?.open,
      pulls: switch ((widget.stashes, thread.id)) {
        (final stashes?, final session?) => stashes.pulls(session),
        _ => const [],
      },
      onOpenPull: widget.stashes?.openPull,
      selected:
          _listSelection.values.contains(thread) ||
          (!_onPage &&
              !_listFocus.hasFocus &&
              _listSelection.values.isEmpty &&
              identical(thread, _current)),
      focusedItem: identical(_listSelection.focused, thread),
      focused: _listFocus.hasFocus,
      menuTargets: () => _targetsFor(thread),
      onContextMenu: () => _rowContext(thread),
      onPinAll: (threads, pinned) => _workspace.setPinnedAll(threads, pinned),
      onArchiveAll: (threads, archived) =>
          _workspace.setArchivedAll(threads, archived),
      onDeleteAll: (threads) => unawaited(_confirmDelete(threads)),
      dragThreads: () => _targetsFor(thread),
      drag: widget.drag,
      showProject: group.project == null,
      showTime: SidebarTimes.shown.value,
      projectIcon: switch (_workspace.iconOf(thread.project)) {
        null when _workspace.workspaceOf(thread.project) != null => Icon(
          Codicons.folderLibrary,
          size: 12,
          color: AppColors.textFaint,
        ),
        null => null,
        final icon => ProjectIconView(
          icon: icon,
          library: _workspace.icons,
          size: 14,
          color: AppColors.textFaint,
        ),
      },
      renaming: identical(thread, _renaming),
      onTap: () => _handleRowTap(thread),
      onRename: () => setState(() => _renaming = thread),
      onRenamed: (title) {
        if (title != null) _workspace.rename(thread, title);
        setState(() => _renaming = null);
      },
      onPin: () => _workspace.setPinned(thread, !thread.pinned),
      onArchive: () => _workspace.setArchived(thread, !thread.archived),
      onFork: () => unawaited(
        _workspace.fork(thread).then((forked) {
          if (forked != null && mounted) _open(forked);
        }),
      ),
      onDelete: () => unawaited(_confirmDelete([thread])),
    );
  }

  // --- A project's menu ------------------------------------------------------

  List<SidebarMenuItem> _projectItems(Project project) {
    final l10n = context.l10n;
    final editor = _workspace.preferredEditor;
    final multi = _workspace.workspaceOf(project);
    final pinned = _workspace.isPinnedProject(project);
    return [
      SidebarMenuItem(
        l10n.sidebarNewAgentHere,
        icon: Icons.add_rounded,
        onSelected: () => _create(project),
      ),
      if (multi != null)
        SidebarMenuItem(
          l10n.sidebarEditWorkspace,
          icon: Icons.edit_outlined,
          onSelected: () => unawaited(
            showWorkspaceDialog(context, workspace: _workspace, editing: multi),
          ),
        )
      else
        SidebarMenuItem(
          l10n.sidebarEditProject,
          icon: Icons.edit_outlined,
          onSelected: () => unawaited(
            showProjectDialog(context, workspace: _workspace, project: project),
          ),
        ),
      SidebarMenuItem(
        l10n.sidebarRevealIn(Editor.folder.localizedPlatformLabel(l10n)),
        icon: Editor.folder.icon,
        onSelected: () =>
            unawaited(Sidebar.launch(Editor.folder, project.path)),
      ),
      if (editor != Editor.folder)
        SidebarMenuItem(
          l10n.workspaceOpenIn(editor.localizedPlatformLabel(l10n)),
          icon: editor.icon,
          onSelected: () => _openInEditor(project, editor),
        ),
      SidebarMenuItem(
        pinned ? l10n.sidebarUnpin : l10n.sidebarPin,
        icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
        onSelected: () => _workspace.setPinnedProject(project, !pinned),
      ),
      SidebarMenuItem(
        l10n.sidebarChangeIcon,
        icon: Icons.emoji_emotions_outlined,
        onSelected: () => _openIconPicker(project),
      ),
      SidebarMenuItem(
        l10n.workspaceCopyPath,
        icon: Icons.content_copy_rounded,
        onSelected: () =>
            unawaited(Clipboard.setData(ClipboardData(text: project.path))),
      ),
      if (_workspace.isManuallyOrdered(project))
        SidebarMenuItem(
          l10n.sidebarSortByTime,
          icon: Icons.schedule_rounded,
          onSelected: () => _workspace.sortByTime(project),
        ),
      SidebarMenuItem(
        l10n.sidebarArchiveAll,
        icon: Icons.inventory_2_outlined,
        onSelected: () => _workspace.archiveAll(project),
      ),
      SidebarMenuItem(
        l10n.sidebarRemoveFromList,
        icon: Icons.visibility_off_outlined,
        onSelected: () => _workspace.hideProject(project),
      ),
      if (multi != null)
        SidebarMenuItem(
          l10n.sidebarDeleteWorkspace,
          icon: Icons.delete_outline_rounded,
          onSelected: () => _workspace.deleteWorkspace(multi),
        ),
    ];
  }

  static Object _iconSlot(Project project) => (#icon, project.path);

  /// [project]'s icon picker, under its icon in its header.
  void _openIconPicker(Project project) {
    final box =
        _box(_iconSlot(project)) ?? _box(Workspace.projectGroup(project.path));
    if (box == null) return;
    ProjectIconPicker.toggle(
      context,
      workspace: _workspace,
      project: project,
      anchor: box.localToGlobal(Offset.zero) & box.size,
    );
  }

  /// The Fast Ide opens [project]'s folder, as the window header's button
  /// does: with the current agent's chat there when it is the project's.
  void _openInEditor(Project project, Editor editor) {
    // A remote project's files open in the IDE's own editor alone.
    if (!editor.builtIn && project.host == null) {
      unawaited(Sidebar.launch(editor, project.path));
      return;
    }
    if (_current case final thread? when thread.project == project) {
      _workspace.openInIde(thread);
    } else {
      _workspace
        ..openIdeFolder(project.path)
        ..layout = WorkspaceLayout.ide;
    }
  }

  // --- Dragging projects -----------------------------------------------------

  Project? _draggedProject;

  /// Where the dragged project would go among the projects listed (it
  /// included), as the line between them shows.
  int? _projectSpot;

  void _moveProjectDrag(Offset position, List<Project> projects) {
    _projectDragPosition = position;
    _projectDragProjects = projects;
    _updateAutoScroll(position);
    final list = _box(_listSlot);
    if (list == null || !_listScroll.hasClients) return;
    final y = list.globalToLocal(position).dy + _listScroll.offset;
    var at = projects.length;
    for (final (index, project) in projects.indexed) {
      final row = _rowIndices[ValueKey(Workspace.projectGroup(project.path))];
      if (row != null && y < _rowOffsets[row] + _listRows[row].extent / 2) {
        at = index;
        break;
      }
    }
    // Pinned ones stay on top: the dragged one moves among its kind.
    final pinned = projects.where(_workspace.isPinnedProject).length;
    at = _workspace.isPinnedProject(_draggedProject!)
        ? at.clamp(0, pinned)
        : at.clamp(pinned, projects.length);
    final from = projects.indexOf(_draggedProject!);
    final spot = at == from || at == from + 1 ? null : at;
    if (spot != _projectSpot) setState(() => _projectSpot = spot);
  }

  void _endProjectDrag(List<Project> projects) {
    _projectDragPosition = null;
    _stopAutoScroll();
    final (project, at) = (_draggedProject, _projectSpot);
    setState(() => _draggedProject = _projectSpot = null);
    if (project == null || at == null) return;
    _workspace.moveProject(project, before: projects.elementAtOrNull(at));
  }

  // --- Dragging agents within the list ---------------------------------------

  /// Where a dragged agent would go in the list, if anywhere.
  _Spot? _spot;

  /// An agent is dragged that can be pinned: an empty pinned group shows,
  /// to drop it on.
  bool _pinZone = false;

  void _attachDrag(ChatDrag? drag) {
    drag?.list = this;
    drag?.addListener(_dragChanged);
  }

  void _detachDrag(ChatDrag? drag) {
    if (drag?.list == this) drag!.list = null;
    drag?.removeListener(_dragChanged);
  }

  void _dragChanged() {
    final dragged = widget.drag?.thread;
    final threads = widget.drag?.threads ?? const <AgentThread>[];
    final pinZone =
        threads.isNotEmpty &&
        threads.every((thread) => !thread.archived) &&
        threads.any((thread) => !thread.pinned);
    if (dragged == null) {
      _dragPosition = null;
      _stopAutoScroll();
    }
    if (pinZone == _pinZone && (dragged != null || _spot == null)) return;
    setState(() {
      if (pinZone != _pinZone) _rowsDirty = true;
      _pinZone = pinZone;
      if (dragged == null) _spot = null;
    });
  }

  RenderBox? _box(Object slot) {
    final context = _slots[slot];
    final box = context != null && context.mounted
        ? context.findRenderObject()
        : null;
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  @override
  bool hover(List<AgentThread> threads, Offset position) {
    final list = _box(_listSlot);
    final over =
        list != null &&
        (Offset.zero & list.size).contains(list.globalToLocal(position));
    _dragPosition = over ? position : null;
    _updateAutoScroll(over ? position : null);
    final spot = over ? _spotAt(threads, position) : null;
    if (spot != _spot) setState(() => _spot = spot);
    return over;
  }

  @override
  void drop(List<AgentThread> threads, Offset position) {
    final spot = _spotAt(threads, position);
    _dragPosition = null;
    _stopAutoScroll();
    setState(() => _spot = null);
    if (spot == null) return;
    final group = spot.group;
    final moving = threads.toSet();
    final ordered = [
      for (final other in group.threads)
        if (!moving.contains(other)) other,
    ];
    final at = switch (spot) {
      _Spot(:final before?) => ordered.indexOf(before),
      _Spot(:final after?) => ordered.indexOf(after) + 1,
      _ => 0,
    };
    ordered.insertAll(at.clamp(0, ordered.length), threads);
    if (group.pinned) {
      _workspace.reorderPinned(ordered);
    } else if (group.project case final project?) {
      _workspace.reorder(project, ordered, unpin: true);
    }
  }

  bool _takes(_Group group, List<AgentThread> threads) =>
      threads.isNotEmpty &&
      threads.every(
        (thread) =>
            _threadIndices.containsKey(thread) &&
            !thread.archived &&
            (group.pinned || group.project == thread.project),
      );

  /// Binary search over row extents, including rows not built by the viewport.
  int? _rowAt(double y) {
    if (y < 0 || y >= _rowOffsets.last) return null;
    var low = 0;
    var high = _listRows.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_rowOffsets[middle + 1] <= y) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  _Spot? _spotAt(List<AgentThread> threads, Offset position) {
    final list = _box(_listSlot);
    if (list == null || !_listScroll.hasClients) return null;
    final local = list.globalToLocal(position);
    if (!(Offset.zero & list.size).contains(local)) return null;
    final y = local.dy + _listScroll.offset;
    final index = _rowAt(y);
    if (index == null) return null;
    final row = _listRows[index];
    final group = row.group;
    if (!_takes(group, threads) || row.kind == _ListRowKind.more) return null;
    final thread = row.thread;
    if (thread == null) return _Spot(group);
    if (threads.contains(thread)) return null;
    return y < _rowOffsets[index] + row.extent / 2
        ? _Spot(group, before: thread)
        : _Spot(group, after: thread);
  }

  void _stopAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  double _scrollStep(Offset? position) {
    final list = _box(_listSlot);
    if (position == null || list == null || !_listScroll.hasClients) return 0;
    final at = list.globalToLocal(position);
    if (!(Offset.zero & list.size).contains(at)) return 0;
    const edge = 32.0;
    if (at.dy < edge && _listScroll.offset > 0) return -12 * (1 - at.dy / edge);
    final bottom = list.size.height - at.dy;
    if (bottom < edge &&
        _listScroll.offset < _listScroll.position.maxScrollExtent) {
      return 12 * (1 - bottom / edge);
    }
    return 0;
  }

  void _updateAutoScroll(Offset? position) {
    if (_scrollStep(position) == 0) {
      _stopAutoScroll();
      return;
    }
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) return _stopAutoScroll();
      final step = _scrollStep(_dragPosition ?? _projectDragPosition);
      if (step == 0) return _stopAutoScroll();
      final scroll = _listScroll.position;
      _listScroll.jumpTo(
        (scroll.pixels + step).clamp(0.0, scroll.maxScrollExtent),
      );
      if (_projectDragPosition case final at?) {
        _moveProjectDrag(at, _projectDragProjects);
      } else {
        widget.drag?.refresh();
      }
    });
  }

  /// Several projects in the sidebar: their groups fold.
  bool get _projectsShown => _workspace.sidebarProjectsHere.length > 1;

  /// Whether [thread] is listed where the sidebar is (this machine, or the
  /// SSH host switched to).
  bool Function(AgentThread thread) get _here {
    final workspace = _workspace;
    return (thread) => workspace.listsHost(thread.project.host);
  }

  int get _archivedCount {
    final here = _here;
    return _workspace.threads.where((t) => t.archived && here(t)).length;
  }

  /// The archived toggle, when there are archived agents, an update's
  /// button, and the settings' gear.
  Widget _buildFooter() {
    final updates = widget.updates;
    final onUpdate = widget.onUpdate;
    if (updates == null || onUpdate == null) return _buildFooterRow(null);
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) => _buildFooterRow(
        updates.pending
            ? _UpdateButton(updates: updates, onTap: onUpdate)
            : null,
      ),
    );
  }

  Widget _buildFooterRow(Widget? update) {
    final count = _archivedCount;
    final settings = widget.onOpenSettings;
    if (count == 0 &&
        settings == null &&
        update == null &&
        widget.setup == null) {
      return const SizedBox.shrink();
    }
    // No line over it: the list fades out above it instead.
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [?widget.setup, _buildFooterButtons(count, settings, update)],
      ),
    );
  }

  Widget _buildFooterButtons(
    int count,
    VoidCallback? settings,
    Widget? update,
  ) {
    return Row(
      children: [
        Expanded(
          child: count == 0
              ? const SizedBox.shrink()
              : _buildArchivedToggle(count),
        ),
        if (update != null) ...[const SizedBox(width: 4), update],
        if (settings != null) ...[
          const SizedBox(width: 4),
          SidebarIconButton(
            icon: Codicons.settingsGear,
            tooltip: context.l10n.settingsTitle,
            command: openSettingsCommandId,
            onTap: settings,
          ),
        ],
      ],
    );
  }

  /// Shows or hides the archived agents; its menu (a right click)
  /// unarchives them all or deletes them all.
  Widget _buildArchivedToggle(int count) {
    return SidebarMenu(
      items: () => _archivedItems(context.l10n),
      placement: (side: FloatingSide.top, align: FloatingAlign.start),
      builder: (context, menu) => HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: _toggleArchived,
          onSecondaryTapUp: (details) => menu.open(details.globalPosition),
          child: _buildArchivedLabel(count, hovered || menu.isOpen),
        ),
      ),
    );
  }

  List<SidebarMenuItem> _archivedItems(AppLocalizations l10n) => [
    SidebarMenuItem(
      // Checked while they show, as a click on the button switches them.
      l10n.sidebarArchived,
      icon: Icons.inventory_2_outlined,
      checked: _showArchived,
      onSelected: _toggleArchived,
    ),
    SidebarMenuItem(
      l10n.sidebarUnarchiveAll,
      icon: Icons.unarchive_outlined,
      onSelected: () {
        _workspace
          ..unarchiveAll(where: _here)
          ..showArchived = false;
      },
    ),
    SidebarMenuItem(
      l10n.sidebarDeleteArchived,
      icon: Icons.delete_outline_rounded,
      destructive: true,
      onSelected: () => unawaited(_confirmDeleteArchived()),
    ),
  ];

  Future<void> _confirmDeleteArchived() async {
    final count = _archivedCount;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      // Black, not the theme's: as upstream's dialogs dim the window.
      barrierColor: const Color(0x99000000),
      builder: (context) {
        final l10n = context.l10n;
        return _ConfirmDialog(
          title: l10n.sidebarDeleteArchivedTitle,
          message: l10n.sidebarDeleteArchivedMessage(count),
          action: l10n.commonDelete,
        );
      },
    );
    if (!(confirmed ?? false)) return;
    _workspace
      ..deleteArchived(where: _here)
      ..showArchived = false;
  }

  Widget _buildArchivedLabel(int count, bool active) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: active ? AppColors.hover : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 13,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _showArchived
                  ? context.l10n.sidebarHideArchived
                  : context.l10n.sidebarArchivedCount(count),
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(List<AgentThread> threads) async {
    if (threads.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      // Black, not the theme's: as upstream's dialogs dim the window.
      barrierColor: const Color(0x99000000),
      builder: (context) {
        final l10n = context.l10n;
        final thread = threads.first;
        final title = thread.localizedTitle(l10n);
        return _ConfirmDialog(
          title: threads.length == 1
              ? l10n.sidebarDeleteAgentTitle
              : l10n.sidebarDeleteAgentsTitle,
          message: threads.length == 1
              ? thread.kernel.catalog == null
                    ? l10n.sidebarDeleteAgentMessage(title)
                    : l10n.sidebarDeleteAgentMessageKernel(
                        title,
                        thread.kernel.label,
                      )
              : l10n.sidebarDeleteAgentsMessage(threads.length),
          action: l10n.commonDelete,
        );
      },
    );
    if (!(confirmed ?? false)) return;
    if (threads.length == 1) {
      _workspace.delete(threads.first);
    } else {
      _workspace.deleteAll(threads);
    }
  }
}

class _NewAgentButton extends StatelessWidget {
  const _NewAgentButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The agent sessions window's New Session button; its hover with the
    // keys of New Agent, which does the same (a folder first, without one).
    final colors = themeColors;
    final foreground = colors['agentsNewSessionButton.foreground'];
    return IdeHover(
      message: ChatKeys.titleWithKey(
        context.l10n.sidebarNewAgent,
        ChatCommandIds.newChat,
        ChatKeys.chatLayout,
      ),
      excludeFromSemantics: true,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color:
                  colors[hovered
                      ? 'agentsNewSessionButton.hoverBackground'
                      : 'agentsNewSessionButton.background'],
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: colors['agentsNewSessionButton.border'],
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.add_rounded, size: 16, color: foreground),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.l10n.sidebarNewAgent,
                    style: TextStyle(color: foreground, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row under New Agent that opens something of the window's (Search,
/// Customize): an icon and a label, as Cursor's sidebar has them.
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hover,
    this.selected = false,
    this.badge = 0,
    this.badgeHover,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// How many new things it has, at its end; none when 0. [badgeHover]
  /// says what they are.
  final int badge;
  final String? badgeHover;

  /// Its hover's text, e.g. with the keys that do the same; none when null.
  final String? hover;

  /// What it opens shows.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final row = Semantics(
      button: true,
      selected: selected,
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: IdeListRow(
            height: IdeListColors.rowHeight,
            selected: selected,
            keepSelectionActive: true,
            onTap: onTap,
            builder: (context, hovered) {
              final foreground = selected
                  ? IdeListColors.activeSelectionForeground
                  : hovered
                  ? IdeListColors.hoverForeground
                  : IdeListColors.foreground;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        size: 15,
                        color: selected
                            ? themeColors.get(
                                    'list.activeSelectionIconForeground',
                                  ) ??
                                  foreground
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: foreground, fontSize: 12.5),
                        ),
                      ),
                      if (badge > 0) _badge(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    final message = [?hover, if (badge > 0) ?badgeHover].join('\n');
    return switch (message.isEmpty ? null : message) {
      final message? => IdeHover(
        message: message,
        excludeFromSemantics: true,
        child: row,
      ),
      null => row,
    };
  }
}

extension on _NavRow {
  Widget _badge() => Container(
    constraints: const BoxConstraints(minWidth: 16),
    height: 16,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      badge > 99 ? '99+' : '$badge',
      style: TextStyle(
        color: themeColors.get('badge.foreground') ?? Colors.white,
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        height: 1,
      ),
    ),
  );
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.collapsed,
    required this.onToggle,
    this.light = false,
    this.onCreate,
    this.menu,
    this.dragged = false,
    this.pinned = false,
    this.icon,
    this.folders,
  });

  final _Group group;
  final bool collapsed;

  /// Null where the group does not fold.
  final VoidCallback? onToggle;

  /// The only project's: its name, nothing to fold or count.
  final bool light;
  final VoidCallback? onCreate;

  /// The project's menu (or the archived agents'), on a right click or its
  /// "…" button.
  final List<SidebarMenuItem> Function()? menu;

  /// Being dragged to another place among the projects.
  final bool dragged;

  /// The project is pinned on top of the others: a pin after its name.
  final bool pinned;

  /// The project's icon, before its name.
  final Widget? icon;

  /// The folders of the project, a multi-folder workspace's; null for a
  /// folder's.
  final List<String>? folders;

  @override
  Widget build(BuildContext context) {
    final menu = this.menu;
    if (menu == null) return _build(context, null);
    return SidebarMenu(
      items: menu,
      placement: (side: FloatingSide.bottom, align: FloatingAlign.end),
      builder: _build,
    );
  }

  Widget _build(BuildContext context, SidebarMenuState? menu) {
    final project = group.project;
    final header = HoverBuilder(
      cursor: onToggle == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hovered) {
        final active = hovered || (menu?.isOpen ?? false);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          onSecondaryTapUp: menu == null
              ? null
              : (details) => menu.open(details.globalPosition),
          child: Container(
            height: 26,
            margin: const EdgeInsets.only(top: 6),
            padding: EdgeInsets.only(left: light ? 6 : 4, right: 2),
            decoration: BoxDecoration(
              color: (active || dragged) && project != null
                  ? AppColors.hover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: [
                if (!light) ...[
                  AnimatedRotation(
                    turns: collapsed ? 0 : 0.25,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 15,
                      color: hovered
                          ? AppColors.textMuted
                          : AppColors.textFaint,
                    ),
                  ),
                  const SizedBox(width: 2),
                ],
                if (icon case final icon?) ...[icon, const SizedBox(width: 4)],
                // The dot right after the name, the rest of the row after.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(child: _label(project)),
                      if (pinned) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.push_pin,
                          size: 11,
                          color: AppColors.textFaint,
                        ),
                      ],
                      if (_hiddenStatus(context) case final status?) ...[
                        const SizedBox(width: 6),
                        status,
                      ],
                    ],
                  ),
                ),
                if (collapsed && !light && group.threads.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      '${group.threads.length}',
                      style: TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (active && menu != null)
                  SidebarIconButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: context.l10n.sidebarMoreActions,
                    size: 20,
                    onTap: menu.open,
                  ),
                if (onCreate case final onCreate? when active)
                  SidebarIconButton(
                    icon: Icons.add_rounded,
                    tooltip: context.l10n.sidebarNewAgentIn(group.label),
                    size: 20,
                    onTap: onCreate,
                  ),
              ],
            ),
          ),
        );
      },
    );
    return header;
  }

  /// Folded, the dot of the agent in it that most needs attention: one
  /// waiting on a question, else one finished unseen.
  Widget? _hiddenStatus(BuildContext context) {
    if (!collapsed) return null;
    final statuses = {for (final thread in group.threads) thread.status};
    final (status, label) = switch (statuses) {
      _ when statuses.contains(ThreadStatus.needsInput) => (
        ThreadStatus.needsInput,
        context.l10n.sidebarNeedsInput,
      ),
      _ when statuses.contains(ThreadStatus.unread) => (
        ThreadStatus.unread,
        context.l10n.sidebarUnread,
      ),
      _ => (null, null),
    };
    if (status == null) return null;
    return Semantics(label: label, child: StatusIndicator(status));
  }

  Widget _label(Project? project) {
    final label = Text(
      group.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: project != null ? AppColors.text : AppColors.textMuted,
        fontSize: project != null ? 12.5 : 11.5,
        fontWeight: FontWeight.w500,
      ),
    );
    if (project == null) return label;
    if (folders case final folders?) {
      // A workspace: how many folders after its name, which they are over
      // it.
      final color = AppColors.textFaint;
      return _RowHover(
        content: (context) => Text(
          [
            context.l10n.workspaceHover(
              folders.map(RemoteLocation.nameOf).join(', '),
            ),
            ...folders,
          ].join('\n'),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: label),
              const SizedBox(width: 6),
              Icon(Codicons.folderLibrary, size: 11, color: color),
              const SizedBox(width: 2),
              Text(
                '${folders.length}',
                style: TextStyle(color: color, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }
    final host = project.host;
    if (host == null) {
      // Where the project is: its name says only which. Over the name
      // alone, not the buttons beside it, which come and go with the
      // pointer.
      return _RowHover(
        content: (context) => Text(project.path),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: label,
        ),
      );
    }
    // A remote project, listed under its host (the heading says which):
    // a red mark after its name while the host cannot be reached (a click
    // tries again).
    final ssh = SshHosts.instance[host];
    return ListenableBuilder(
      listenable: ssh,
      builder: (context, _) {
        final failed = ssh.state == SshHostState.failed;
        final (message, _) = failed
            ? sshErrorText(ssh.error, context.l10n)
            : (null, null);
        Widget? badge;
        if (failed) {
          badge = MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ssh.reconnect().ignore(),
              child: Icon(
                Codicons.debugDisconnect,
                size: 11,
                color: themeColors['errorForeground'],
              ),
            ),
          );
        }
        return _RowHover(
          content: (context) => Text(
            [
              project.root,
              context.l10n.remoteProjectTooltip(
                RemoteLocation.reachedBy(host),
                RemoteLocation.hostName(host),
              ),
              if (failed) ...[
                context.l10n.remoteStatusTooltipLost(
                  RemoteLocation.hostName(host),
                ),
                ?message,
              ],
            ].join('\n'),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: label),
                if (badge != null) ...[const SizedBox(width: 6), badge],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The workbench hover of a row or header, placed as [IdeHover.followMouse]
/// places it, in an overlay entry of its own: an [IdeHover] (an
/// OverlayPortal) within the menu's OverlayPortal around each row leaves
/// the desktop engines' semantics tree behind as it hides.
class _RowHover extends StatefulWidget {
  const _RowHover({required this.content, required this.child});

  final WidgetBuilder content;
  final Widget child;

  @override
  State<_RowHover> createState() => _RowHoverState();
}

class _RowHoverState extends State<_RowHover> {
  Timer? _timer;
  OverlayEntry? _entry;

  /// Where the pointer last moved over the target, in the target.
  Offset _mouse = Offset.zero;

  void _enter(PointerEnterEvent event) {
    _mouse = event.localPosition;
    _timer?.cancel();
    _timer = Timer(ideHoverDelay, _show);
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _entry
      ?..remove()
      ..dispose();
    _entry = null;
  }

  void _show() {
    final box = context.findRenderObject();
    final overlay = Overlay.maybeOf(context);
    final overlayBox = overlay?.context.findRenderObject();
    if (overlay == null ||
        box is! RenderBox ||
        !box.attached ||
        overlayBox is! RenderBox) {
      return;
    }
    final target =
        box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
    final x = target.left + _mouse.dx + 10;
    final entry = _entry = OverlayEntry(
      builder: (context) => CustomSingleChildLayout(
        delegate: _BelowMouse(target, x),
        child: IgnorePointer(
          child: ExcludeSemantics(
            // In the window's overlay, above the sidebar's Material: the
            // text style is its own.
            child: Material(
              type: MaterialType.transparency,
              child: IdeHoverBox(
                compact: false,
                child: widget.content(context),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _hide(),
    onPointerSignal: (_) => _hide(),
    child: MouseRegion(
      onEnter: _enter,
      onHover: (event) => _mouse = event.localPosition,
      onExit: (_) => _hide(),
      child: widget.child,
    ),
  );
}

/// Below the target (above where there is no room), from [x]; inside the
/// overlay (hoverWidget.ts `layout`).
class _BelowMouse extends SingleChildLayoutDelegate {
  const _BelowMouse(this.target, this.x);

  final Rect target;
  final double x;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final y = target.bottom + childSize.height > size.height
        ? target.top - childSize.height
        : target.bottom - 2;
    return clampHoverOffset(Offset(x, y), childSize, size);
  }

  @override
  bool shouldRelayout(_BelowMouse oldDelegate) =>
      oldDelegate.target != target || oldDelegate.x != x;
}

/// A project's header dragged to another place among the projects: past a
/// few pixels, so a click still folds it.
class _ProjectDragSource extends StatefulWidget {
  const _ProjectDragSource({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.child,
  });

  final VoidCallback onStart;

  /// Where the pointer is, globally.
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  final Widget child;

  @override
  State<_ProjectDragSource> createState() => _ProjectDragSourceState();
}

class _ProjectDragSourceState extends State<_ProjectDragSource>
    with AutomaticKeepAliveClientMixin {
  bool _dragging = false;

  // Scrolling the source header away must not dispose its recognizer mid-drag.
  @override
  bool get wantKeepAlive => _dragging;

  void _end() {
    _dragging = false;
    updateKeepAlive();
    widget.onEnd();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RawGestureDetector(
      gestures: {
        _ProjectDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_ProjectDragRecognizer>(
              _ProjectDragRecognizer.new,
              (recognizer) {
                recognizer
                  ..onStart = ((_) {
                    _dragging = true;
                    updateKeepAlive();
                    widget.onStart();
                  })
                  ..onUpdate = ((details) =>
                      widget.onUpdate(details.globalPosition))
                  ..onEnd = ((_) => _end())
                  ..onCancel = _end;
              },
            ),
      },
      child: widget.child,
    );
  }
}

/// A vertical drag that starts past 4 pixels, mouse or not (a mouse's
/// slop is otherwise 1, which a click can move).
class _ProjectDragRecognizer extends VerticalDragGestureRecognizer {
  _ProjectDragRecognizer() : super(supportedDevices: null);

  // Two-finger scrolling must not enter project reordering.
  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) => false;

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => globalDistanceMoved.abs() > 4;
}

/// Where a dragged agent or project would go, between rows: drawn over
/// them, taking no room.
class _DropLine extends StatelessWidget {
  const _DropLine();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 0,
    child: OverflowBox(
      maxHeight: 2,
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: themeColors['focusBorder'],
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    ),
  );
}

/// The pinned group while there is none yet and an agent is dragged: a
/// place to drop it on, to pin it.
class _PinZone extends StatelessWidget {
  const _PinZone({required this.height, required this.active});

  final double height;

  /// The agent is over it.
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    margin: const EdgeInsets.only(top: 2),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: active ? AppColors.hover : Colors.transparent,
      border: Border.all(
        color: active ? themeColors['focusBorder'] : AppColors.partBorder,
      ),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      context.l10n.sidebarDropToPin,
      style: TextStyle(color: AppColors.textFaint, fontSize: 11.5),
    ),
  );
}

/// Something in the list a drag finds by [slot]: where it is built is
/// kept in [slots] while it is.
class _Slot extends StatefulWidget {
  const _Slot({required this.slot, required this.slots, required this.child});

  final Object slot;
  final Map<Object, BuildContext> slots;
  final Widget child;

  @override
  State<_Slot> createState() => _SlotState();
}

class _SlotState extends State<_Slot> {
  @override
  void initState() {
    super.initState();
    widget.slots[widget.slot] = context;
  }

  @override
  void didUpdateWidget(_Slot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _forget(oldWidget);
    widget.slots[widget.slot] = context;
  }

  @override
  void dispose() {
    _forget(widget);
    super.dispose();
  }

  void _forget(_Slot of) {
    if (identical(of.slots[of.slot], context)) of.slots.remove(of.slot);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Under a project's most recent agents: the rest, or fewer again.
class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    cursor: SystemMouseCursors.click,
    builder: (context, hovered) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 24,
        padding: const EdgeInsets.only(left: 28),
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(
            color: hovered ? AppColors.textMuted : AppColors.textFaint,
            fontSize: 11.5,
          ),
        ),
      ),
    ),
  );
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.thread,
    required this.model,
    required this.height,
    this.stashes = const [],
    this.onOpenStash,
    this.pulls = const [],
    this.onOpenPull,
    required this.selected,
    required this.focusedItem,
    required this.focused,
    required this.drag,
    required this.showProject,
    required this.showTime,
    this.projectIcon,
    required this.renaming,
    required this.onTap,
    required this.onRename,
    required this.onRenamed,
    required this.onPin,
    required this.onArchive,
    required this.onFork,
    required this.onDelete,
    required this.menuTargets,
    required this.onContextMenu,
    required this.onPinAll,
    required this.onArchiveAll,
    required this.onDeleteAll,
    required this.dragThreads,
  });

  final AgentThread thread;

  /// The model it runs on, as its hover shows it; none when unknown.
  final String? Function() model;
  final double height;

  /// The stashes it carries out: a tag on it, opened by [onOpenStash].
  final List<SidebarStash> stashes;
  final ValueChanged<int>? onOpenStash;

  /// The pull requests it opened (or worked on), by their stash: a tag
  /// on it, opened by [onOpenPull].
  final List<SidebarPull> pulls;
  final ValueChanged<String>? onOpenPull;

  final bool selected;
  final bool focusedItem;
  final bool focused;

  final ChatDrag? drag;
  final bool showProject;

  /// Whether the time it last did something shows at its end (its hover
  /// shows it either way).
  final bool showTime;

  /// Before the project's name, when it shows and has an icon.
  final Widget? projectIcon;
  final bool renaming;
  final VoidCallback onTap;
  final VoidCallback onRename;

  /// The new title, or null when renaming was cancelled.
  final ValueChanged<String?> onRenamed;
  final VoidCallback onPin;
  final VoidCallback onArchive;

  /// Copies the conversation into a new agent, shown.
  final VoidCallback onFork;
  final VoidCallback onDelete;
  final List<AgentThread> Function() menuTargets;
  final VoidCallback onContextMenu;
  final void Function(List<AgentThread>, bool) onPinAll;
  final void Function(List<AgentThread>, bool) onArchiveAll;
  final ValueChanged<List<AgentThread>> onDeleteAll;
  final List<AgentThread> Function() dragThreads;

  List<SidebarMenuItem> _items(AppLocalizations l10n) {
    final targets = menuTargets();
    final pinned = targets.every((thread) => thread.pinned);
    final archived = targets.every((thread) => thread.archived);
    final count = targets.length;
    // Several: only what is done to them all, saying how many.
    if (count > 1) {
      return [
        if (targets.every((thread) => !thread.archived))
          SidebarMenuItem(
            pinned
                ? l10n.sidebarUnpinCount(count)
                : l10n.sidebarPinCount(count),
            icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
            onSelected: () => onPinAll(targets, !pinned),
          ),
        SidebarMenuItem(
          archived
              ? l10n.sidebarUnarchiveCount(count)
              : l10n.sidebarArchiveCount(count),
          icon: Icons.inventory_2_outlined,
          onSelected: () => onArchiveAll(targets, !archived),
        ),
        SidebarMenuItem(
          l10n.sidebarDeleteCount(count),
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onSelected: () => onDeleteAll(targets),
        ),
      ];
    }
    return [
      if (onOpenStash case final open?)
        for (final stash in stashes)
          SidebarMenuItem(
            l10n.sidebarOpenStash(stash.id),
            icon: Codicons.note,
            onSelected: () => open(stash.id),
          ),
      if (onOpenPull case final open?)
        for (final pull in pulls)
          SidebarMenuItem(
            l10n.sidebarOpenPull(pull.tag),
            icon: Codicons.gitPullRequest,
            onSelected: () => open(pull.url),
          ),
      SidebarMenuItem(
        l10n.commonRename,
        icon: Icons.edit_outlined,
        onSelected: onRename,
      ),
      if (!thread.archived)
        SidebarMenuItem(
          pinned ? l10n.sidebarUnpin : l10n.sidebarPin,
          icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
          onSelected: onPin,
        ),
      SidebarMenuItem(
        archived ? l10n.sidebarUnarchive : l10n.sidebarArchive,
        icon: Icons.inventory_2_outlined,
        onSelected: onArchive,
      ),
      // A conversation to copy: none before the first message.
      if (thread.id != null && (!thread.isOpen || thread.session.canFork))
        SidebarMenuItem(
          l10n.sidebarFork,
          icon: Codicons.repoForked,
          onSelected: onFork,
        ),
      // Claude Code finds the conversation by it (none before the first
      // message).
      if (thread.id case final id?)
        SidebarMenuItem(
          l10n.sidebarCopySessionId,
          icon: Icons.content_copy_rounded,
          onSelected: () =>
              unawaited(Clipboard.setData(ClipboardData(text: id))),
        ),
      SidebarMenuItem(
        l10n.commonDelete,
        icon: Icons.delete_outline_rounded,
        destructive: true,
        onSelected: onDelete,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final row = SidebarMenu(
      items: () => _items(context.l10n),
      placement: (side: FloatingSide.bottom, align: FloatingAlign.end),
      builder: (context, menu) => IdeListRow(
        height: height,
        selected: selected,
        focusedItem: focusedItem,
        focused: focused,
        keepSelectionActive: true,
        onTap: renaming ? null : onTap,
        onDoubleTap: renaming ? null : onRename,
        onContextMenu: (position) {
          onContextMenu();
          menu.open(position);
        },
        builder: (context, hovered) {
          final active = hovered || menu.isOpen;
          final foreground = selected
              ? IdeListColors.activeSelectionForeground
              : hovered
              ? IdeListColors.hoverForeground
              : IdeListColors.foreground;
          return Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 4),
                // Too narrow, what is beside the title gives way (its hover
                // tells it), before the title is cut to nothing.
                child: GiveWayRow(
                  children: [
                    GiveWay(
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: SizedBox(
                          width: 14,
                          child: Center(
                            child: StatusIndicator(thread.shownStatus),
                          ),
                        ),
                      ),
                    ),
                    GiveWay.fill(
                      minWidth: renaming ? 0 : _titleMinWidth,
                      renaming
                          ? InlineRenameField(
                              initial: thread.localizedTitle(context.l10n),
                              onDone: onRenamed,
                            )
                          // What the row has no room for, over the title
                          // (not the buttons that come and go beside it).
                          : _RowHover(
                              content: (context) => _buildHover(context.l10n),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _buildTitle(context.l10n, foreground),
                              ),
                            ),
                    ),
                    if (!renaming)
                      ..._buildTrailing(active, context.l10n, foreground),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    // Dragged out onto the conversations, it shows beside them.
    return ChatDragSource(
      drag: renaming ? null : drag,
      thread: thread,
      threads: dragThreads,
      child: Semantics(selected: selected, child: row),
    );
  }

  /// What the row has no room for: the whole title, where the agent works,
  /// what it is doing and when it last did.
  Widget _buildHover(AppLocalizations l10n) {
    final diff = thread.diff;
    final status = switch (thread.shownStatus) {
      ThreadStatus.needsInput => l10n.sidebarNeedsInput,
      ThreadStatus.running => l10n.sidebarRunning,
      ThreadStatus.unread => l10n.sidebarUnread,
      ThreadStatus.idle => null,
    };
    final faint = TextStyle(color: AppColors.textMuted, fontSize: 12);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            thread.localizedTitle(l10n),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(thread.project.path, style: faint),
          if (model() case final model?)
            Text(
              l10n.sidebarHoverModel(model),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: faint,
            ),
          for (final stash in stashes)
            Text(
              'Stash #${stash.id} · ${stash.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: faint,
            ),
          for (final pull in pulls)
            Text(
              [pull.tag, ?pull.title].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: faint,
            ),
          Text(
            [
              ?status,
              relativeTime(thread.updatedAt, DateTime.now(), l10n),
              if (diff != null) '+${diff.added} −${diff.removed}',
            ].join(' · '),
            style: faint,
          ),
        ],
      ),
    );
  }

  Widget _buildTitle(AppLocalizations l10n, Color foreground) {
    final status = thread.status;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: thread.localizedTitle(l10n)),
          if (showProject) ...[
            const TextSpan(text: '  '),
            if (projectIcon case final icon?) ...[
              WidgetSpan(alignment: PlaceholderAlignment.middle, child: icon),
              const TextSpan(text: ' '),
            ],
            TextSpan(
              text: thread.project.name,
              style: TextStyle(
                color: selected ? foreground : AppColors.textFaint,
                fontSize: 11.5,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ],
      ),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      // Hover actions change the available width. Keep the line metrics
      // stable when truncation changes which fallback fonts remain visible.
      strutStyle: const StrutStyle(
        fontSize: 12.5,
        height: 1.4,
        forceStrutHeight: true,
      ),
      style: TextStyle(
        color: foreground,
        fontSize: 12.5,
        fontWeight: status == ThreadStatus.unread
            ? FontWeight.w600
            : FontWeight.normal,
      ),
    );
  }

  /// The least the title is cut to before what is beside it gives way.
  static const _titleMinWidth = 80.0;

  /// What is beside the title, each a gap before it; giving way the diff
  /// first, then the time, the pull request's tag, the stash's.
  List<GiveWay> _buildTrailing(
    bool active,
    AppLocalizations l10n,
    Color foreground,
  ) {
    final diff = thread.diff;
    Widget gap(Widget child) =>
        Padding(padding: const EdgeInsets.only(left: 6), child: child);
    return [
      if (stashes.isNotEmpty)
        GiveWay(
          priority: 3,
          gap(
            _StashTag(
              stashes: stashes,
              color: selected ? foreground : AppColors.textMuted,
              onOpen: onOpenStash,
            ),
          ),
        ),
      if (pulls.isNotEmpty)
        GiveWay(
          priority: 2,
          gap(
            _PullTag(
              pulls: pulls,
              color: selected ? foreground : AppColors.textMuted,
              onOpen: onOpenPull,
            ),
          ),
        ),
      if (diff != null && !active)
        GiveWay(
          priority: 0,
          gap(
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '+${diff.added}',
                    style: TextStyle(
                      color: themeColors['chat.linesAddedForeground'],
                    ),
                  ),
                  TextSpan(
                    text: ' −${diff.removed}',
                    style: TextStyle(
                      color: themeColors['chat.linesRemovedForeground'],
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              style: const TextStyle(
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      // The time; while hovered, pin and archive in its place (the rest is
      // in the context menu), which never give way.
      if (active)
        GiveWay(
          gap(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!thread.archived)
                  SidebarIconButton(
                    icon: thread.pinned
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                    tooltip: thread.pinned
                        ? l10n.sidebarUnpin
                        : l10n.sidebarPin,
                    size: 20,
                    onTap: onPin,
                  ),
                SidebarIconButton(
                  icon: thread.archived
                      ? Icons.unarchive_outlined
                      : Icons.inventory_2_outlined,
                  tooltip: thread.archived
                      ? l10n.sidebarUnarchive
                      : l10n.sidebarArchive,
                  size: 20,
                  onTap: onArchive,
                ),
              ],
            ),
          ),
        )
      else if (showTime)
        GiveWay(
          priority: 1,
          gap(
            // Wider where the language's times are.
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 26),
              child: Text(
                thread.status == ThreadStatus.needsInput
                    ? ''
                    : relativeTime(thread.updatedAt, DateTime.now(), l10n),
                textAlign: TextAlign.right,
                maxLines: 1,
                // The color of the buttons it gives way to on hover.
                style: TextStyle(
                  color: selected ? foreground : AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ),
      const GiveWay(SizedBox(width: 2)),
    ];
  }
}

/// A stash a conversation carries out, as its row shows it.
typedef SidebarStash = ({int id, String title, bool done});

/// What the sidebar shows of the stashes (docs/stash.md): those each
/// conversation carries out, by its session, and how to open one; told
/// by [changes] when they may have changed.
class SidebarStashes {
  const SidebarStashes({
    required this.changes,
    required this.of,
    required this.open,
    this.pulls = _none,
    this.openPull,
    this.news = _noNews,
  });

  final Listenable changes;
  final List<SidebarStash> Function(String session) of;
  final ValueChanged<int> open;

  /// The pull requests each conversation opened, by its session; opened
  /// (in the browser) by [openPull].
  final List<SidebarPull> Function(String session) pulls;
  final ValueChanged<String>? openPull;

  /// How many stashes have news about the user not seen yet: on the
  /// Stash row.
  final int Function() news;

  static List<SidebarPull> _none(String session) => const [];
  static int _noNews() => 0;
}

/// A pull (merge) request a conversation opened, as its row shows it: its
/// link, `o/r#7`, its title and state when known.
typedef SidebarPull = ({
  String url,
  String tag,
  String? title,
  ForgeState? state,
});

/// On a conversation's row: the pull request it opened (`#7`, `+1` for
/// each other) in its state's icon and color, its title on hover; a click
/// opens it.
class _PullTag extends StatelessWidget {
  const _PullTag({
    required this.pulls,
    required this.color,
    required this.onOpen,
  });

  final List<SidebarPull> pulls;
  final Color color;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final first = pulls.first;
    final (icon, stateColor) = forgeStateLook(ForgeItemKind.pull, first.state);
    final number = RegExp(r'[#!]\d+$').firstMatch(first.tag)?[0] ?? first.tag;
    // In its state's color, its icon telling it from a stash's.
    final tag = _TagPill(
      color: first.state == null ? color : stateColor,
      icon: icon,
      label: '$number${pulls.length > 1 ? ' +${pulls.length - 1}' : ''}',
    );
    return IdeHover(
      message: [
        for (final pull in pulls) [pull.tag, ?pull.title].join(' · '),
      ].join('\n'),
      child: switch (onOpen) {
        final open? => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => open(first.url),
            child: tag,
          ),
        ),
        null => tag,
      },
    );
  }
}

/// On a conversation's row: the stash it carries out (`#31`, `+1` for
/// each other) in a pill of the row's text's color, faded once done; its
/// title on hover; a click opens it.
class _StashTag extends StatelessWidget {
  const _StashTag({
    required this.stashes,
    required this.color,
    required this.onOpen,
  });

  final List<SidebarStash> stashes;
  final Color color;
  final ValueChanged<int>? onOpen;

  @override
  Widget build(BuildContext context) {
    final first = stashes.first;
    final tag = Opacity(
      opacity: first.done ? .55 : 1,
      child: _TagPill(
        color: color,
        label:
            '#${first.id}${stashes.length > 1 ? ' +${stashes.length - 1}' : ''}',
      ),
    );
    return IdeHover(
      message: [
        for (final stash in stashes) 'Stash #${stash.id} · ${stash.title}',
      ].join('\n'),
      child: switch (onOpen) {
        final open? => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => open(first.id),
            child: tag,
          ),
        ),
        null => tag,
      },
    );
  }
}

/// A conversation's row's tag: [label] in [color], on a pill of it, faint.
class _TagPill extends StatelessWidget {
  const _TagPill({required this.color, required this.label, this.icon});

  final Color color;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    height: 16,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon case final icon?) ...[
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 2),
        ],
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            height: 1.2,
            fontWeight: FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

/// What an agent needs: a spinner while it runs, an amber dot when it
/// waits on a question, a blue dot when it finished unseen.
class StatusIndicator extends StatelessWidget {
  const StatusIndicator(this.status, {super.key});

  /// As the agent sessions list shows an agent waiting on the user.
  static Color get needsInputColor => themeColors['list.warningForeground'];

  final ThreadStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      // A little under the list's text, as its dots are.
      ThreadStatus.running => const PixelLoader.agent(size: 12),
      ThreadStatus.needsInput => _Dot(needsInputColor),
      ThreadStatus.unread => _Dot(AppColors.accent),
      ThreadStatus.idle => const SizedBox.shrink(),
    };
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Small square icon button with a hover fill.
class SidebarIconButton extends StatelessWidget {
  const SidebarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 24,
    this.command,
    this.keyContext = ChatKeys.chatLayout,
    this.spinning = false,
  });

  final IconData icon;

  /// Its icon turning: what it started still goes on.
  final bool spinning;

  /// What it does: its label, and its hover's text.
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  /// The command it runs, if a keybinding can run it too: its hover adds
  /// the key, as the keybindings have it now (`Hide sidebar (⌘B)`).
  final String? command;

  /// The context keys where it is, which pick the keybinding shown: the
  /// chat layout's by default.
  final Map<String, Object> keyContext;

  @override
  Widget build(BuildContext context) {
    // The workbench hover, as the IDE's action buttons have, titled as
    // upstream's action bar items are (actionViewItems.ts `getTooltip`,
    // `titleAndKb`); the label without the key.
    return IdeHover(
      message: switch (command) {
        final command? => ChatKeys.titleWithKey(tooltip, command, keyContext),
        null => tooltip,
      },
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            onTap: onTap,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: hovered
                    ? themeColors['toolbar.hoverBackground']
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
              child: switch (Icon(
                icon,
                size: size * 0.65,
                color: hovered ? AppColors.text : AppColors.textMuted,
              )) {
                final icon when spinning => IdeSpinning(icon),
                final icon => icon,
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Update, beside the settings' gear while an update waits: a pill in the
/// theme's button colors; its hover says which version and what a click
/// does.
class _UpdateButton extends StatelessWidget {
  const _UpdateButton({required this.updates, required this.onTap});

  final UpdateService updates;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final release = updates.release!;
    final version = release.version.marketing;
    final message = updates.isMandatory(release)
        ? l10n.updateMandatory(version)
        : updates.status == UpdateStatus.ready
        ? l10n.updateReady(version)
        : l10n.updateAvailable(version);
    return IdeHover(
      message: message,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: '${l10n.updateButton}: $message',
        excludeSemantics: true,
        onTap: onTap,
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            onTap: onTap,
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hovered
                    ? IdeButtonColors.hoverBackground
                    : IdeButtonColors.background,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                l10n.updateButton,
                style: TextStyle(
                  color: IdeButtonColors.foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.action,
  });

  final String title;
  final String message;
  final String action;

  @override
  Widget build(BuildContext context) {
    // As upstream's dialog: a widget's colors, bordered in high contrast.
    final colors = themeColors;
    return Dialog(
      backgroundColor: AppColors.surface,
      shadowColor: colors['widget.shadow'],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: switch (colors.get('contrastBorder')) {
          final border? => BorderSide(color: border),
          null => BorderSide.none,
        },
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(
                  color: colors['editorWidget.foreground'],
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _DialogButton(
                    label: context.l10n.commonCancel,
                    onTap: () => Navigator.pop(context, false),
                  ),
                  const SizedBox(width: 8),
                  _DialogButton(
                    label: action,
                    destructive: true,
                    onTap: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    // The dialog's buttons: the action primary, as upstream's.
    final colors = themeColors;
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                colors[switch ((destructive, hovered)) {
                  (true, true) => 'button.hoverBackground',
                  (true, false) => 'button.background',
                  (false, true) => 'button.secondaryHoverBackground',
                  (false, false) => 'button.secondaryBackground',
                }],
            borderRadius: BorderRadius.circular(6),
            border: switch (colors.get(
              destructive ? 'button.border' : 'button.secondaryBorder',
            )) {
              final border? => Border.all(color: border),
              null => null,
            },
          ),
          child: Text(
            label,
            style: TextStyle(
              color:
                  colors[destructive
                      ? 'button.foreground'
                      : 'button.secondaryForeground'],
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// A project's icon in its header (its folder, when it has none): a click
/// opens the icon picker, or closes it.
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.project,
    required this.workspace,
    required this.onTap,
  });

  final Project project;
  final Workspace workspace;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TapRegion(
    groupId: ProjectIconPicker.tapRegion,
    child: Semantics(
      button: true,
      label: context.l10n.sidebarProjectIcon(project.name),
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hovered
                  ? themeColors['toolbar.hoverBackground']
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: ExcludeSemantics(
              child: ProjectIconView(
                icon: workspace.iconOf(project),
                library: workspace.icons,
                size: 22,
                color: AppColors.textMuted,
                fallback: workspace.workspaceOf(project) != null
                    ? Codicons.folderLibrary
                    : Icons.folder_outlined,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// This machine's icon, or an SSH host's; the dot of what most needs the
/// user elsewhere ([attention]) over its corner.
class _HostIcon extends StatelessWidget {
  const _HostIcon({
    super.key,
    required this.workspace,
    required this.host,
    required this.attention,
    this.all = false,
  });

  final Workspace workspace;
  final String? host;
  final ThreadStatus? attention;

  /// For every host together, not one.
  final bool all;

  @override
  Widget build(BuildContext context) {
    final host = this.host;
    final icon = SizedBox.square(
      dimension: 14,
      child: Center(
        child: all
            ? Icon(Codicons.layers, size: 13, color: AppColors.textMuted)
            : host == null
            ? Icon(Codicons.deviceDesktop, size: 13, color: AppColors.textMuted)
            : ProjectIconView(
                icon: workspace.iconOf(workspace.hostIconProject(host)),
                library: workspace.icons,
                size: 14,
                color: AppColors.textMuted,
                fallback: Codicons.remote,
              ),
      ),
    );
    final attention = this.attention;
    if (attention == null) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -3,
          top: -2,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: attention == ThreadStatus.needsInput
                  ? StatusIndicator.needsInputColor
                  : AppColors.accent,
              border: Border.all(color: AppColors.sidebarSurface, width: 1),
            ),
          ),
        ),
      ],
    );
  }
}

/// How [host]'s connection is: green while connected, red once failed,
/// hollow otherwise.
class _HostDot extends StatelessWidget {
  const _HostDot(this.host);

  final SshHost host;

  @override
  Widget build(BuildContext context) {
    final color = switch (host.state) {
      SshHostState.connected => themeColors['charts.green'],
      SshHostState.failed => themeColors['errorForeground'],
      SshHostState.connecting ||
      SshHostState.reconnecting => themeColors['charts.yellow'],
      SshHostState.idle => null,
    };
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: color == null
            ? Border.all(color: AppColors.textFaint, width: 1)
            : null,
      ),
    );
  }
}
