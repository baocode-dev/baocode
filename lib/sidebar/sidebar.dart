import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/chat_keys.dart';
import '../chat/floating/floating_placement.dart';
import '../chat/widgets/hover_builder.dart';
import '../chat/widgets/inline_rename_field.dart';
import '../ide/ide_hover.dart';
import '../l10n/l10n.dart';
import '../keybindings/chat_keybindings.dart';
import '../keybindings/default_keybindings.dart' show openSettingsCommandId;
import '../theme/codicons.dart';
import '../theme/cursor_theme.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/chat_drag.dart';
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
}

/// What the window asks of its sidebar, for the chat's keybindings: the
/// agents in the order it lists them, and its search.
class SidebarLink {
  _SidebarState? _state;

  /// Whether a sidebar is built (shown, or tucked away beside the chat).
  bool get attached => _state != null;

  /// The agents listed, top to bottom (not those of collapsed groups, but
  /// while searching); null without a sidebar.
  List<AgentThread>? get visibleThreads => _state?._visibleThreads();

  /// Focuses the search field, its text selected.
  void focusSearch() => _state?._focusSearch();
}

/// Agents list: new agent, search, grouped by project, date or status,
/// pinned ones on top and archived ones tucked away at the bottom.
class Sidebar extends StatefulWidget {
  const Sidebar({
    super.key,
    required this.workspace,
    required this.onCollapse,
    this.onOpened,
    this.onOpenFolder,
    this.onOpenSettings,
    this.drag,
    this.link,
  });

  final Workspace workspace;
  final VoidCallback onCollapse;

  /// Where rows are dragged to show beside the open agent; none when null.
  final ChatDrag? drag;

  /// Asks for a folder to open as a project; null where there is none to
  /// ask (the web).
  final VoidCallback? onOpenFolder;

  /// Opens the settings: the gear at the bottom; none without it.
  final VoidCallback? onOpenSettings;

  /// An agent was opened or created from here (the drawer closes).
  final VoidCallback? onOpened;

  /// Reaches this sidebar from the window.
  final SidebarLink? link;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  static const _rowHeight = 28.0;

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  SidebarGrouping _grouping = SidebarGrouping.project;
  final Set<String> _collapsed = {};
  bool _showArchived = false;
  AgentThread? _renaming;

  /// Keeps the relative times current.
  late final Timer _clock;

  Workspace get _workspace => widget.workspace;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
    _search.addListener(() => setState(() {}));
    widget.link?._state = this;
  }

  @override
  void didUpdateWidget(Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.link != widget.link) {
      if (oldWidget.link?._state == this) oldWidget.link!._state = null;
      widget.link?._state = this;
    }
  }

  @override
  void dispose() {
    if (widget.link?._state == this) widget.link!._state = null;
    _clock.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// The agents listed, top to bottom (see [_buildList]).
  List<AgentThread> _visibleThreads() {
    final searching = _search.text.trim().isNotEmpty;
    return [
      for (final group in _groups())
        if (!_collapsed.contains(group.id) || searching) ...group.threads,
    ];
  }

  void _focusSearch() {
    _search.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _search.text.length,
    );
    _searchFocus.requestFocus();
  }

  void _open(AgentThread thread) {
    _workspace.select(thread);
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
    _workspace.create(project: project);
    widget.onOpened?.call();
  }

  bool _matches(AgentThread thread) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    return thread.localizedTitle(context.l10n).toLowerCase().contains(query) ||
        thread.project.name.toLowerCase().contains(query);
  }

  List<_Group> _groups() {
    final l10n = context.l10n;
    final threads = [
      for (final thread in _workspace.threads)
        if (_matches(thread)) thread,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final active = [
      for (final thread in threads)
        if (!thread.archived) thread,
    ];
    final pinned = [
      for (final thread in active)
        if (thread.pinned) thread,
    ];
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
      if (pinned.isNotEmpty) _Group('pinned', l10n.sidebarPinned, pinned),
      ...switch (_grouping) {
        SidebarGrouping.project => [
          for (final project in _workspace.projects)
            _Group(
              'project:${project.path}',
              project.name,
              where((thread) => thread.project == project),
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
      color: CursorColors.sidebarSurface,
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
                CursorMetrics.contentInset,
                8,
                6,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _NewAgentButton(
                      onTap: _workspace.projects.isEmpty
                          ? (widget.onOpenFolder ?? () {})
                          : _create,
                    ),
                  ),
                  if (widget.onOpenFolder case final open?) ...[
                    const SizedBox(width: 4),
                    SidebarIconButton(
                      icon: Icons.create_new_folder_outlined,
                      tooltip: context.l10n.sidebarOpenFolder,
                      size: 30,
                      onTap: open,
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: _SearchField(controller: _search, focusNode: _searchFocus),
            ),
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
        height: CursorMetrics.titleBarHeight,
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
                color: CursorColors.textFaint,
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
                  onSelected: () => setState(() => _grouping = grouping),
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
                        ? CursorColors.hover
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _grouping.localizedBy(context.l10n),
                        style: TextStyle(
                          color: CursorColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 14,
                        color: CursorColors.textFaint,
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

  Widget _buildList() {
    final searching = _search.text.trim().isNotEmpty;
    final groups = [
      for (final group in _groups())
        // Empty projects stay, to start an agent in; other empty groups go.
        if (group.threads.isNotEmpty || (group.project != null && !searching))
          group,
    ];
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          searching
              ? context.l10n.sidebarNoMatchingAgents
              : context.l10n.sidebarNoAgentsYet,
          textAlign: TextAlign.center,
          style: TextStyle(color: CursorColors.textFaint, fontSize: 12),
        ),
      );
    }
    final selected = _workspace.selected;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
        children: [
          for (final group in groups) ...[
            _GroupHeader(
              group: group,
              collapsed: _collapsed.contains(group.id) && !searching,
              onToggle: () => setState(() {
                if (!_collapsed.remove(group.id)) _collapsed.add(group.id);
              }),
              onCreate: group.project == null
                  ? null
                  : () => _create(group.project),
            ),
            if (!_collapsed.contains(group.id) || searching)
              for (final thread in group.threads)
                _ThreadRow(
                  key: ObjectKey(thread),
                  thread: thread,
                  height: _rowHeight,
                  selected: identical(thread, selected),
                  shown: _workspace.grid.contains(thread),
                  drag: widget.drag,
                  showProject: group.project == null && _projectsShown,
                  renaming: identical(thread, _renaming),
                  onTap: () => _handleRowTap(thread),
                  onRename: () => setState(() => _renaming = thread),
                  onRenamed: (title) {
                    if (title != null) _workspace.rename(thread, title);
                    setState(() => _renaming = null);
                  },
                  onPin: () => _workspace.setPinned(thread, !thread.pinned),
                  onArchive: () =>
                      _workspace.setArchived(thread, !thread.archived),
                  onDelete: () => _confirmDelete(thread),
                ),
          ],
        ],
      ),
    );
  }

  /// Project names are worth showing on rows only when there are several.
  bool get _projectsShown => _workspace.projects.length > 1;

  /// The archived toggle, when there are archived agents, and the
  /// settings' gear.
  Widget _buildFooter() {
    final count = _workspace.threads.where((t) => t.archived).length;
    final settings = widget.onOpenSettings;
    if (count == 0 && settings == null) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: CursorColors.border)),
      ),
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          Expanded(
            child: count == 0
                ? const SizedBox.shrink()
                : _buildArchivedToggle(count),
          ),
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
      ),
    );
  }

  Widget _buildArchivedToggle(int count) {
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: () => setState(() => _showArchived = !_showArchived),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: hovered ? CursorColors.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 13,
                color: CursorColors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _showArchived
                      ? context.l10n.sidebarHideArchived
                      : context.l10n.sidebarArchivedCount(count),
                  style: TextStyle(color: CursorColors.textMuted, fontSize: 12),
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

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    // An input box; its hover with the keys that focus it, as upstream's
    // command center has (`Search monad (⌘P)`).
    final colors = themeColors;
    final box = SizedBox(
      height: 28,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            controller.clear();
            focusNode.unfocus();
          },
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          style: TextStyle(color: colors['input.foreground'], fontSize: 12.5),
          cursorColor: CursorColors.text,
          cursorHeight: 14,
          decoration: InputDecoration(
            isDense: true,
            hintText: context.l10n.sidebarSearchAgents,
            hintStyle: TextStyle(
              color: colors['input.placeholderForeground'],
              fontSize: 12.5,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 15,
              color: CursorColors.textFaint,
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 30),
            suffixIcon: controller.text.isEmpty
                ? null
                : GestureDetector(
                    onTap: controller.clear,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: CursorColors.textMuted,
                      ),
                    ),
                  ),
            suffixIconConstraints: const BoxConstraints(minWidth: 28),
            contentPadding: const EdgeInsets.symmetric(vertical: 7),
            filled: true,
            fillColor: colors['input.background'],
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: CursorColors.borderStrong),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: colors['focusBorder']),
            ),
          ),
        ),
      ),
    );
    return IdeHover(
      message: ChatKeys.titleWithKey(
        context.l10n.cmdChatSearchAgents,
        ChatCommandIds.searchAgents,
        ChatKeys.chatLayout,
      ),
      excludeFromSemantics: true,
      child: box,
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.collapsed,
    required this.onToggle,
    this.onCreate,
  });

  final _Group group;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final project = group.project;
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Container(
          height: 26,
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.only(left: 4, right: 2),
          decoration: BoxDecoration(
            color: hovered && project != null
                ? CursorColors.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              AnimatedRotation(
                turns: collapsed ? 0 : 0.25,
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 15,
                  color: hovered
                      ? CursorColors.textMuted
                      : CursorColors.textFaint,
                ),
              ),
              const SizedBox(width: 2),
              if (project != null) ...[
                Icon(
                  Icons.folder_outlined,
                  size: 13,
                  color: CursorColors.textMuted,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  group.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: project != null
                        ? CursorColors.text
                        : CursorColors.textMuted,
                    fontSize: project != null ? 12.5 : 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (collapsed && group.threads.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    '${group.threads.length}',
                    style: TextStyle(
                      color: CursorColors.textFaint,
                      fontSize: 11,
                    ),
                  ),
                ),
              if (onCreate case final onCreate? when hovered)
                SidebarIconButton(
                  icon: Icons.add_rounded,
                  tooltip: context.l10n.sidebarNewAgentIn(group.label),
                  size: 20,
                  onTap: onCreate,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    super.key,
    required this.thread,
    required this.height,
    required this.selected,
    required this.shown,
    required this.drag,
    required this.showProject,
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
                    ? CursorColors.hover
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
                        : _buildTitle(context.l10n),
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

  Widget _buildTitle(AppLocalizations l10n) {
    final status = thread.status;
    final emphasized = selected || status == ThreadStatus.unread;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: thread.localizedTitle(l10n)),
          if (showProject)
            TextSpan(
              text: '  ${thread.project.name}',
              style: TextStyle(
                color: CursorColors.textFaint,
                fontSize: 11.5,
                fontWeight: FontWeight.normal,
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: selected
            ? themeColors['list.activeSelectionForeground']
            : emphasized
            ? CursorColors.textPrimary
            : CursorColors.text,
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
            style: TextStyle(color: CursorColors.textFaint, fontSize: 11),
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
          color: CursorColors.textMuted,
        ),
      ),
      ThreadStatus.needsInput => _Dot(needsInputColor),
      ThreadStatus.unread => _Dot(CursorColors.accent),
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
                color: hovered ? CursorColors.text : CursorColors.textMuted,
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
      backgroundColor: CursorColors.surface,
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
                  color: CursorColors.textPrimary,
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
