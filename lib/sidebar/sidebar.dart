import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/chat_keys.dart';
import '../chat/floating/floating_placement.dart';
import '../chat/widgets/hover_builder.dart';
import '../chat/widgets/inline_rename_field.dart';
import '../icons/project_icon_picker.dart';
import '../icons/project_icon_view.dart';
import '../ide/ide_button.dart' show IdeButtonColors;
import '../ide/ide_hover.dart';
import '../l10n/l10n.dart';
import '../keybindings/chat_keybindings.dart';
import '../keybindings/default_keybindings.dart' show openSettingsCommandId;
import '../remote/remote_status.dart' show sshErrorText;
import '../remote/ssh_host.dart' show SshHostState, SshHosts;
import '../theme/codicons.dart';
import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../update/update_service.dart';
import '../workspace/chat_drag.dart';
import '../workspace/editor_launcher.dart';
import '../workspace/title_bar_double_click.dart';
import '../workspace/window_controls.dart';
import '../workspace/workspace.dart';
import 'sidebar_menu.dart';

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
    this.onOpenSettings,
    this.onSearch,
    this.onCustomize,
    this.customizing = false,
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

  /// An agent was opened or created from here (the drawer closes).
  final VoidCallback? onOpened;

  /// Reaches this sidebar from the window.
  final SidebarLink? link;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> implements ChatDragList {
  static const _rowHeight = 28.0;

  /// The agents a project shows until asked for more (pinned ones apart).
  static const _recent = 5;

  AgentThread? _renaming;

  /// Keeps the relative times current.
  late final Timer _clock;

  Workspace get _workspace => widget.workspace;

  // Kept by the workspace, between runs and as the sidebar is built anew
  // (between the docked sidebar and the drawer, not built while closed).
  SidebarGrouping get _grouping =>
      SidebarGrouping.values.asNameMap()[_workspace.sidebarGrouping] ??
      SidebarGrouping.project;
  bool get _showArchived => _workspace.showArchived;

  final ScrollController _listScroll = ScrollController();

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

  /// Scrolls to the bottom of the list. The list lays out only the rows
  /// near what shows, so its extent is an estimate until the bottom ones
  /// are reached (short of the archived ones, from far above): the bottom
  /// is chased until it stays put.
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
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
    widget.link?._state = this;
    _attachDrag(widget.drag);
  }

  @override
  void didUpdateWidget(Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.link != widget.link) {
      if (oldWidget.link?._state == this) oldWidget.link!._state = null;
      widget.link?._state = this;
    }
    if (oldWidget.drag != widget.drag) {
      _detachDrag(oldWidget.drag);
      _attachDrag(widget.drag);
    }
  }

  @override
  void dispose() {
    if (widget.link?._state == this) widget.link!._state = null;
    _detachDrag(widget.drag);
    _clock.cancel();
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
      (!thread.untouched ||
          identical(thread, _current) ||
          _workspace.grid.contains(thread));

  AgentThread? get _current => widget.current ?? _workspace.current;

  void _open(AgentThread thread) {
    (widget.onSelect ?? _workspace.select)(thread);
    widget.onOpened?.call();
  }

  /// The last click on a row, to tell a double click.
  ({AgentThread thread, DateTime at})? _lastTap;

  /// A click opens the agent at once (not after waiting out a double
  /// click); a second one on it soon after renames it.
  void _handleRowTap(AgentThread thread) {
    final now = DateTime.now();
    final last = _lastTap;
    if (last != null &&
        identical(last.thread, thread) &&
        now.difference(last.at) < kDoubleTapTimeout) {
      _lastTap = null;
      setState(() => _renaming = thread);
      return;
    }
    _lastTap = (thread: thread, at: now);
    _open(thread);
  }

  void _create([Project? project]) {
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
        if ((thread.archived || _listed(thread)) &&
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
          for (final project in _workspace.sidebarProjects)
            _Group(
              Workspace.projectGroup(project.path),
              project.name,
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
            where((t) => t.status == ThreadStatus.needsInput),
          ),
          _Group(
            'running',
            l10n.sidebarRunning,
            where((t) => t.status == ThreadStatus.running),
          ),
          _Group(
            'unread',
            l10n.sidebarUnread,
            where((t) => t.status == ThreadStatus.unread),
          ),
          _Group(
            'idle',
            l10n.sidebarDone,
            where((t) => t.status == ThreadStatus.idle),
          ),
        ],
      },
      if (_showArchived)
        _Group('archived', l10n.sidebarArchived, [
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
                onTap: _workspace.sidebarProjects.isEmpty
                    ? (widget.onOpenFolder ?? () {})
                    : _create,
              ),
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
                icon: Codicons.extensions,
                label: context.l10n.sidebarCustomize,
                selected: widget.customizing,
                onTap: customize,
              ),
            if (widget.onSearch != null || widget.onCustomize != null)
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
            child: Text(
              context.l10n.sidebarAgents,
              style: TextStyle(
                color: AppColors.textFaint,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
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

  /// What [_buildList] laid out last, top to bottom, to find where a drag
  /// is: each group's header, then its rows (an empty pinned group's
  /// place to drop on instead).
  List<({_Group group, AgentThread? thread, Object slot})> _laidOut = const [];

  /// Where each of [_laidOut], and the list, is built now (a [_Slot]).
  final Map<Object, BuildContext> _slots = {};
  static const _listSlot = #list;

  Widget _buildList() {
    final groups = [
      for (final group in _groups())
        // Empty projects stay, to start an agent in; other empty groups go
        // (but the place to pin a dragged agent).
        if (group.threads.isNotEmpty || group.project != null || group.pinned)
          group,
    ];
    _laidOut = const [];
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          context.l10n.sidebarNoAgentsYet,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textFaint, fontSize: 12),
        ),
      );
    }
    final selected = _current;
    final spot = _spot;
    final laidOut = <({_Group group, AgentThread? thread, Object slot})>[];
    final projects = [for (final group in groups) ?group.project];
    final children = <Widget>[];
    for (final group in groups) {
      final project = group.project;
      if (project != null && _projectSpot == projects.indexOf(project)) {
        children.add(const _DropLine());
      }
      laidOut.add((group: group, thread: null, slot: group.id));
      children.add(
        _Slot(
          key: ValueKey(group.id),
          slot: group.id,
          slots: _slots,
          child: _buildHeader(group, projects),
        ),
      );
      if (spot case _Spot(before: null, after: null)
          when spot.group.id == group.id && group.threads.isNotEmpty) {
        children.add(const _DropLine());
      }
      if (group.pinned && group.threads.isEmpty) {
        const zone = #pinZone;
        laidOut.add((group: group, thread: null, slot: zone));
        children.add(
          _Slot(
            key: const ValueKey(zone),
            slot: zone,
            slots: _slots,
            child: _PinZone(
              height: _rowHeight,
              active: spot?.group.id == group.id,
            ),
          ),
        );
      }
      final rows = _rows(group);
      for (final thread in rows.threads) {
        if (spot != null && identical(spot.before, thread)) {
          children.add(const _DropLine());
        }
        laidOut.add((group: group, thread: thread, slot: thread));
        children.add(
          _Slot(
            key: ObjectKey(thread),
            slot: thread,
            slots: _slots,
            child: _buildRow(thread, group, selected),
          ),
        );
        if (spot != null && identical(spot.after, thread)) {
          children.add(const _DropLine());
        }
      }
      if (rows.more > 0 || rows.less) {
        children.add(
          _MoreRow(
            key: ValueKey('${group.id}.more'),
            label: rows.less
                ? context.l10n.sidebarShowLess
                : context.l10n.sidebarShowMore(rows.more),
            onTap: () => _workspace.toggleExpanded(group.id),
          ),
        );
      }
    }
    if (_projectSpot != null && _projectSpot == projects.length) {
      children.add(const _DropLine());
    }
    _laidOut = laidOut;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: _Slot(
        slot: _listSlot,
        slots: _slots,
        child: ListView(
          controller: _listScroll,
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          children: children,
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
      menu: project == null ? null : () => _projectItems(project),
      dragged: project != null && identical(project, _draggedProject),
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

  Widget _buildRow(AgentThread thread, _Group group, AgentThread? selected) {
    return _ThreadRow(
      thread: thread,
      height: _rowHeight,
      selected: identical(thread, selected),
      shown: _workspace.grid.contains(thread),
      drag: widget.drag,
      showProject: group.project == null,
      projectIcon: switch (_workspace.iconOf(thread.project)) {
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
      onDelete: () => _confirmDelete(thread),
    );
  }

  // --- A project's menu ------------------------------------------------------

  List<SidebarMenuItem> _projectItems(Project project) {
    final l10n = context.l10n;
    final editor = _workspace.preferredEditor;
    return [
      SidebarMenuItem(
        l10n.sidebarNewAgentHere,
        icon: Icons.add_rounded,
        onSelected: () => _create(project),
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
    // Before the first header whose middle is below the pointer.
    var at = projects.length;
    for (final (i, project) in projects.indexed) {
      final box = _box(Workspace.projectGroup(project.path));
      if (box == null) continue;
      final middle = box.localToGlobal(box.size.center(Offset.zero)).dy;
      if (position.dy < middle) {
        at = i;
        break;
      }
    }
    final from = projects.indexOf(_draggedProject!);
    // Where it is already: no line.
    final spot = at == from || at == from + 1 ? null : at;
    if (spot != _projectSpot) setState(() => _projectSpot = spot);
  }

  void _endProjectDrag(List<Project> projects) {
    final (project, at) = (_draggedProject, _projectSpot);
    setState(() => _draggedProject = _projectSpot = null);
    if (project == null || at == null) return;
    final from = projects.indexOf(project);
    _workspace.moveProject(project, at > from ? at - 1 : at);
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
    final pinZone = dragged != null && !dragged.pinned && !dragged.archived;
    if (pinZone == _pinZone && (dragged != null || _spot == null)) return;
    setState(() {
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
  bool hover(AgentThread thread, Offset position) {
    final list = _box(_listSlot);
    final over =
        list != null &&
        (Offset.zero & list.size).contains(list.globalToLocal(position));
    final spot = over ? _spotAt(thread, position) : null;
    if (spot != _spot) setState(() => _spot = spot);
    return over;
  }

  @override
  void drop(AgentThread thread, Offset position) {
    final spot = _spotAt(thread, position);
    setState(() => _spot = null);
    if (spot == null) return;
    final group = spot.group;
    final ordered = [
      for (final other in group.threads)
        if (!identical(other, thread)) other,
    ];
    final at = switch (spot) {
      _Spot(:final before?) => ordered.indexOf(before),
      _Spot(:final after?) => ordered.indexOf(after) + 1,
      _ => 0,
    };
    ordered.insert(at.clamp(0, ordered.length), thread);
    if (group.pinned) {
      _workspace.reorderPinned(ordered);
    } else if (group.project case final project?) {
      if (thread.pinned) _workspace.setPinned(thread, false);
      _workspace.reorder(project, ordered);
    }
  }

  /// Whether [thread] can be dropped in [group]: pinned there, or ordered
  /// among its project's (not into another's).
  bool _takes(_Group group, AgentThread thread) =>
      !thread.archived && (group.pinned || group.project == thread.project);

  _Spot? _spotAt(AgentThread thread, Offset position) {
    for (final (:group, thread: row, :slot) in _laidOut) {
      final box = _box(slot);
      if (box == null) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (position.dy < top || position.dy >= top + box.size.height) continue;
      if (!_takes(group, thread)) return null;
      if (row == null) return _Spot(group);
      if (identical(row, thread)) return null;
      return position.dy < top + box.size.height / 2
          ? _Spot(group, before: row)
          : _Spot(group, after: row);
    }
    return null;
  }

  /// Several projects in the sidebar: their groups fold.
  bool get _projectsShown => _workspace.sidebarProjects.length > 1;

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
    final count = _workspace.threads.where((t) => t.archived).length;
    final settings = widget.onOpenSettings;
    if (count == 0 &&
        settings == null &&
        update == null &&
        widget.setup == null) {
      return const SizedBox.shrink();
    }
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
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

  Widget _buildArchivedToggle(int count) {
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: _toggleArchived,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: hovered ? AppColors.hover : Colors.transparent,
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
        ),
      ),
    );
  }

  Future<void> _confirmDelete(AgentThread thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      // Black, not the theme's: as upstream's dialogs dim the window.
      barrierColor: const Color(0x99000000),
      builder: (context) {
        final l10n = context.l10n;
        final title = thread.localizedTitle(l10n);
        return _ConfirmDialog(
          title: l10n.sidebarDeleteAgentTitle,
          message: thread.kernel.catalog == null
              ? l10n.sidebarDeleteAgentMessage(title)
              : l10n.sidebarDeleteAgentMessageKernel(
                  title,
                  thread.kernel.label,
                ),
          action: l10n.commonDelete,
        );
      },
    );
    if (confirmed ?? false) _workspace.delete(thread);
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
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

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
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: selected
                  ? themeColors['list.activeSelectionBackground']
                  : hovered
                  ? AppColors.hover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: selected
                        ? themeColors['list.activeSelectionForeground']
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? themeColors['list.activeSelectionForeground']
                            : AppColors.text,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return switch (hover) {
      final message? => IdeHover(
        message: message,
        excludeFromSemantics: true,
        child: row,
      ),
      null => row,
    };
  }
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
    this.icon,
  });

  final _Group group;
  final bool collapsed;

  /// Null where the group does not fold.
  final VoidCallback? onToggle;

  /// The only project's: its name, nothing to fold or count.
  final bool light;
  final VoidCallback? onCreate;

  /// The project's menu, on a right click or its "…" button.
  final List<SidebarMenuItem> Function()? menu;

  /// Being dragged to another place among the projects.
  final bool dragged;

  /// The project's icon, before its name.
  final Widget? icon;

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
    // A remote project: its host after its name, red while it cannot be
    // reached (a click tries again).
    final ssh = SshHosts.instance[host];
    return ListenableBuilder(
      listenable: ssh,
      builder: (context, _) {
        final failed = ssh.state == SshHostState.failed;
        final color = failed
            ? themeColors['errorForeground']
            : AppColors.textFaint;
        final (message, _) = failed ? sshErrorText(ssh.error) : (null, null);
        Widget badge = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              failed ? Codicons.debugDisconnect : Codicons.remote,
              size: 11,
              color: color,
            ),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 11),
              ),
            ),
          ],
        );
        if (failed) {
          badge = MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ssh.reconnect().ignore(),
              child: badge,
            ),
          );
        }
        return _RowHover(
          content: (context) => Text(
            [
              project.root,
              context.l10n.remoteProjectTooltip(host),
              if (failed) ...[
                context.l10n.remoteStatusTooltipLost(host),
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
                const SizedBox(width: 6),
                Flexible(child: badge),
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
    return Offset(
      x.clamp(0, math.max(0, size.width - childSize.width)),
      y.clamp(0, math.max(0, size.height - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(_BelowMouse oldDelegate) =>
      oldDelegate.target != target || oldDelegate.x != x;
}

/// A project's header dragged to another place among the projects: past a
/// few pixels, so a click still folds it.
class _ProjectDragSource extends StatelessWidget {
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
  Widget build(BuildContext context) => RawGestureDetector(
    gestures: {
      _ProjectDragRecognizer:
          GestureRecognizerFactoryWithHandlers<_ProjectDragRecognizer>(
            _ProjectDragRecognizer.new,
            (recognizer) {
              recognizer
                ..onStart = ((_) => onStart())
                ..onUpdate = ((details) => onUpdate(details.globalPosition))
                ..onEnd = ((_) => onEnd())
                ..onCancel = onEnd;
            },
          ),
    },
    child: child,
  );
}

/// A vertical drag that starts past 4 pixels, mouse or not (a mouse's
/// slop is otherwise 1, which a click can move).
class _ProjectDragRecognizer extends VerticalDragGestureRecognizer {
  _ProjectDragRecognizer() : super(supportedDevices: null);

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
        color: active ? themeColors['focusBorder'] : AppColors.border,
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
  const _Slot({
    super.key,
    required this.slot,
    required this.slots,
    required this.child,
  });

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
  const _MoreRow({super.key, required this.label, required this.onTap});

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
    required this.height,
    required this.selected,
    required this.shown,
    required this.drag,
    required this.showProject,
    this.projectIcon,
    required this.renaming,
    required this.onTap,
    required this.onRename,
    required this.onRenamed,
    required this.onPin,
    required this.onArchive,
    required this.onDelete,
  });

  final AgentThread thread;
  final double height;
  final bool selected;

  /// Open in a pane beside the selected one.
  final bool shown;
  final ChatDrag? drag;
  final bool showProject;

  /// Before the project's name, when it shows and has an icon.
  final Widget? projectIcon;
  final bool renaming;
  final VoidCallback onTap;
  final VoidCallback onRename;

  /// The new title, or null when renaming was cancelled.
  final ValueChanged<String?> onRenamed;
  final VoidCallback onPin;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  List<SidebarMenuItem> _items(AppLocalizations l10n) => [
    SidebarMenuItem(
      l10n.commonRename,
      icon: Icons.edit_outlined,
      onSelected: onRename,
    ),
    if (!thread.archived)
      SidebarMenuItem(
        thread.pinned ? l10n.sidebarUnpin : l10n.sidebarPin,
        icon: thread.pinned ? Icons.push_pin : Icons.push_pin_outlined,
        onSelected: onPin,
      ),
    SidebarMenuItem(
      thread.archived ? l10n.sidebarUnarchive : l10n.sidebarArchive,
      icon: Icons.inventory_2_outlined,
      onSelected: onArchive,
    ),
    // Claude Code finds the conversation by it (none before the first
    // message).
    if (thread.id case final id?)
      SidebarMenuItem(
        l10n.sidebarCopySessionId,
        icon: Icons.content_copy_rounded,
        onSelected: () => unawaited(Clipboard.setData(ClipboardData(text: id))),
      ),
    SidebarMenuItem(
      l10n.commonDelete,
      icon: Icons.delete_outline_rounded,
      destructive: true,
      onSelected: onDelete,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final row = SidebarMenu(
      items: () => _items(context.l10n),
      placement: (side: FloatingSide.bottom, align: FloatingAlign.end),
      builder: (context, menu) => HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) {
          final active = hovered || menu.isOpen;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: renaming ? null : onTap,
            onSecondaryTapUp: (details) => menu.open(details.globalPosition),
            child: Container(
              height: height,
              padding: const EdgeInsets.only(left: 8, right: 4),
              decoration: BoxDecoration(
                color: selected
                    ? themeColors['list.activeSelectionBackground']
                    : active
                    ? AppColors.hover
                    : shown
                    ? themeColors['list.inactiveSelectionBackground']
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
              // High contrast themes outline the selection and the hovered
              // row, as the IDE's lists do (IdeListRow: dotted and dashed
              // upstream).
              foregroundDecoration: switch (selected || active
                  ? themeColors.get('contrastActiveBorder')
                  : null) {
                final outline? => BoxDecoration(
                  border: Border.all(color: outline),
                  borderRadius: BorderRadius.circular(5),
                ),
                null => null,
              },
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    child: Center(child: StatusIndicator(thread.status)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: renaming
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
                              child: _buildTitle(context.l10n),
                            ),
                          ),
                  ),
                  if (!renaming) ..._buildTrailing(active, context.l10n),
                ],
              ),
            ),
          );
        },
      ),
    );
    // Dragged out onto the conversations, it shows beside them.
    return ChatDragSource(
      drag: renaming ? null : drag,
      thread: thread,
      child: row,
    );
  }

  /// What the row has no room for: the whole title, where the agent works,
  /// what it is doing and when it last did.
  Widget _buildHover(AppLocalizations l10n) {
    final diff = thread.diff;
    final status = switch (thread.status) {
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

  Widget _buildTitle(AppLocalizations l10n) {
    final status = thread.status;
    final emphasized = selected || status == ThreadStatus.unread;
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
                color: AppColors.textFaint,
                fontSize: 11.5,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: selected
            ? themeColors['list.activeSelectionForeground']
            : emphasized
            ? AppColors.textPrimary
            : AppColors.text,
        fontSize: 12.5,
        fontWeight: status == ThreadStatus.unread
            ? FontWeight.w600
            : FontWeight.normal,
      ),
    );
  }

  List<Widget> _buildTrailing(bool active, AppLocalizations l10n) {
    final diff = thread.diff;
    return [
      if (diff != null && !active) ...[
        const SizedBox(width: 6),
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
          style: const TextStyle(
            fontSize: 11,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
      const SizedBox(width: 6),
      // The time; while hovered, pin and archive in its place (the rest is
      // in the context menu).
      if (active) ...[
        if (!thread.archived)
          SidebarIconButton(
            icon: thread.pinned ? Icons.push_pin : Icons.push_pin_outlined,
            tooltip: thread.pinned ? l10n.sidebarUnpin : l10n.sidebarPin,
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
      ] else
        // Wider where the language's times are.
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 26),
          child: Text(
            thread.status == ThreadStatus.needsInput
                ? ''
                : relativeTime(thread.updatedAt, DateTime.now(), l10n),
            textAlign: TextAlign.right,
            maxLines: 1,
            style: TextStyle(color: AppColors.textFaint, fontSize: 11),
          ),
        ),
      const SizedBox(width: 2),
    ];
  }
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
      ThreadStatus.running => SizedBox.square(
        dimension: 10,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: AppColors.textMuted,
        ),
      ),
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
  });

  final IconData icon;

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
              child: Icon(
                icon,
                size: size * 0.65,
                color: hovered ? AppColors.text : AppColors.textMuted,
              ),
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
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
