import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/floating/floating_placement.dart';
import '../chat/widgets/hover_builder.dart';
import '../chat/widgets/inline_rename_field.dart';
import '../theme/codicons.dart';
import '../theme/cursor_theme.dart';
import '../workspace/window_controls.dart';
import '../workspace/workspace.dart';
import 'sidebar_menu.dart';

enum SidebarGrouping {
  project('Project', Icons.folder_outlined),
  time('Date', Icons.schedule_rounded),
  status('Status', Icons.radio_button_checked_rounded);

  const SidebarGrouping(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// `now`, `5m`, `3h`, `2d`, `3w`, then the date.
String relativeTime(DateTime time, DateTime now) {
  final elapsed = now.difference(time);
  if (elapsed.inMinutes < 1) return 'now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d';
  if (elapsed.inDays < 35) return '${elapsed.inDays ~/ 7}w';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[time.month - 1]} ${time.day}';
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

/// Agents list: new agent, search, grouped by project, date or status,
/// pinned ones on top and archived ones tucked away at the bottom.
class Sidebar extends StatefulWidget {
  const Sidebar({
    super.key,
    required this.workspace,
    required this.onCollapse,
    this.onOpened,
    this.onOpenFolder,
  });

  final Workspace workspace;
  final VoidCallback onCollapse;

  /// Asks for a folder to open as a project; null where there is none to
  /// ask (the web).
  final VoidCallback? onOpenFolder;

  /// An agent was opened or created from here (the drawer closes).
  final VoidCallback? onOpened;

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
  }

  @override
  void dispose() {
    _clock.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
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
    return thread.title.toLowerCase().contains(query) ||
        thread.project.name.toLowerCase().contains(query);
  }

  List<_Group> _groups() {
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
      if (pinned.isNotEmpty) _Group('pinned', 'Pinned', pinned),
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
          _Group('today', 'Today', where((t) => daysAgo(t) <= 0)),
          _Group('yesterday', 'Yesterday', where((t) => daysAgo(t) == 1)),
          _Group(
            'week',
            'Previous 7 days',
            where((t) => daysAgo(t) > 1 && daysAgo(t) <= 7),
          ),
          _Group('older', 'Older', where((t) => daysAgo(t) > 7)),
        ],
        SidebarGrouping.status => [
          _Group(
            'needsInput',
            'Needs input',
            where((t) => t.status == ThreadStatus.needsInput),
          ),
          _Group(
            'running',
            'Running',
            where((t) => t.status == ThreadStatus.running),
          ),
          _Group(
            'unread',
            'Unread',
            where((t) => t.status == ThreadStatus.unread),
          ),
          _Group('idle', 'Done', where((t) => t.status == ThreadStatus.idle)),
        ],
      },
      if (_showArchived)
        _Group('archived', 'Archived', [
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
                      tooltip: 'Open folder…',
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
            _buildArchivedToggle(),
          ],
        ),
      ),
    );
  }

  /// Under the window's traffic lights; the collapse button on the right.
  Widget _buildTopBar() {
    return SizedBox(
      height: CursorMetrics.titleBarHeight,
      child: Row(
        children: [
          const Spacer(),
          SidebarIconButton(
            icon: Codicons.layoutSidebarLeft,
            tooltip: 'Hide sidebar',
            onTap: widget.onCollapse,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _buildGroupingBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 2),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Agents',
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
                  grouping.label,
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
                        'By ${_grouping.label.toLowerCase()}',
                        style: const TextStyle(
                          color: CursorColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                      const Icon(
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
          searching ? 'No matching agents' : 'No agents yet',
          textAlign: TextAlign.center,
          style: const TextStyle(color: CursorColors.textFaint, fontSize: 12),
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

  Widget _buildArchivedToggle() {
    final count = _workspace.threads.where((t) => t.archived).length;
    if (count == 0) return const SizedBox.shrink();
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: CursorColors.border)),
      ),
      padding: const EdgeInsets.all(6),
      child: HoverBuilder(
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
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 13,
                  color: CursorColors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _showArchived ? 'Hide archived' : 'Archived · $count',
                    style: const TextStyle(
                      color: CursorColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(AgentThread thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (context) => _ConfirmDialog(
        title: 'Delete agent?',
        message: thread.kernel.catalog == null
            ? '“${thread.title}” and its conversation will be removed.'
            : '“${thread.title}” and its conversation will be deleted, '
                  'from ${thread.kernel.label} too. This cannot be undone.',
        action: 'Delete',
      ),
    );
    if (confirmed ?? false) _workspace.delete(thread);
  }
}

class _NewAgentButton extends StatelessWidget {
  const _NewAgentButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: hovered ? const Color(0x14FFFFFF) : const Color(0x0AFFFFFF),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: CursorColors.border),
          ),
          child: const Row(
            children: [
              Icon(Icons.add_rounded, size: 16, color: CursorColors.text),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'New Agent',
                  style: TextStyle(color: CursorColors.text, fontSize: 12.5),
                ),
              ),
            ],
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
    return SizedBox(
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
          style: const TextStyle(color: CursorColors.text, fontSize: 12.5),
          cursorColor: CursorColors.text,
          cursorHeight: 14,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search agents…',
            hintStyle: const TextStyle(
              color: CursorColors.textFaint,
              fontSize: 12.5,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 15,
              color: CursorColors.textFaint,
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 30),
            suffixIcon: controller.text.isEmpty
                ? null
                : GestureDetector(
                    onTap: controller.clear,
                    child: const MouseRegion(
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
            fillColor: const Color(0x0AFFFFFF),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: CursorColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF4D4D4D)),
            ),
          ),
        ),
      ),
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
                const Icon(
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
                    style: const TextStyle(
                      color: CursorColors.textFaint,
                      fontSize: 11,
                    ),
                  ),
                ),
              if (onCreate case final onCreate? when hovered)
                SidebarIconButton(
                  icon: Icons.add_rounded,
                  tooltip: 'New agent in ${group.label}',
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
  final bool showProject;
  final bool renaming;
  final VoidCallback onTap;
  final VoidCallback onRename;

  /// The new title, or null when renaming was cancelled.
  final ValueChanged<String?> onRenamed;
  final VoidCallback onPin;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  List<SidebarMenuItem> _items() => [
    SidebarMenuItem('Rename', icon: Icons.edit_outlined, onSelected: onRename),
    if (!thread.archived)
      SidebarMenuItem(
        thread.pinned ? 'Unpin' : 'Pin',
        icon: thread.pinned ? Icons.push_pin : Icons.push_pin_outlined,
        onSelected: onPin,
      ),
    SidebarMenuItem(
      thread.archived ? 'Unarchive' : 'Archive',
      icon: Icons.inventory_2_outlined,
      onSelected: onArchive,
    ),
    SidebarMenuItem(
      'Delete',
      icon: Icons.delete_outline_rounded,
      destructive: true,
      onSelected: onDelete,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SidebarMenu(
      items: _items,
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
                    ? const Color(0x1FFFFFFF)
                    : active
                    ? CursorColors.hover
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
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
                            initial: thread.title,
                            onDone: onRenamed,
                          )
                        : _buildTitle(),
                  ),
                  if (!renaming) ..._buildTrailing(active),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTitle() {
    final status = thread.status;
    final emphasized = selected || status == ThreadStatus.unread;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: thread.title),
          if (showProject)
            TextSpan(
              text: '  ${thread.project.name}',
              style: const TextStyle(
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
        color: emphasized ? CursorColors.textPrimary : CursorColors.text,
        fontSize: 12.5,
        fontWeight: status == ThreadStatus.unread
            ? FontWeight.w600
            : FontWeight.normal,
      ),
    );
  }

  List<Widget> _buildTrailing(bool active) {
    final diff = thread.diff;
    return [
      if (diff != null && !active) ...[
        const SizedBox(width: 6),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '+${diff.added}',
                style: const TextStyle(color: CursorColors.added),
              ),
              TextSpan(
                text: ' −${diff.removed}',
                style: const TextStyle(color: CursorColors.removed),
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
            tooltip: thread.pinned ? 'Unpin' : 'Pin',
            size: 20,
            onTap: onPin,
          ),
        SidebarIconButton(
          icon: thread.archived
              ? Icons.unarchive_outlined
              : Icons.inventory_2_outlined,
          tooltip: thread.archived ? 'Unarchive' : 'Archive',
          size: 20,
          onTap: onArchive,
        ),
      ] else
        SizedBox(
          width: 26,
          child: Text(
            thread.status == ThreadStatus.needsInput
                ? ''
                : relativeTime(thread.updatedAt, DateTime.now()),
            textAlign: TextAlign.right,
            maxLines: 1,
            style: const TextStyle(color: CursorColors.textFaint, fontSize: 11),
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

  static const needsInputColor = Color(0xFFE5B454);

  final ThreadStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      ThreadStatus.running => const SizedBox.square(
        dimension: 10,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: CursorColors.textMuted,
        ),
      ),
      ThreadStatus.needsInput => const _Dot(needsInputColor),
      ThreadStatus.unread => const _Dot(CursorColors.accent),
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
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
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
              color: hovered ? const Color(0x1AFFFFFF) : Colors.transparent,
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
    return Dialog(
      backgroundColor: CursorColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: CursorColors.borderStrong),
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
                style: const TextStyle(
                  color: CursorColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(color: CursorColors.text, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _DialogButton(
                    label: 'Cancel',
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
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: destructive
                ? (hovered ? const Color(0xFFD9444B) : const Color(0xFFC23B41))
                : (hovered ? const Color(0x1AFFFFFF) : const Color(0x0FFFFFFF)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: destructive ? Colors.white : CursorColors.text,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}
