// The IDE chat's history: the folder's agents in a panel floating at the
// chat's top right, the chat under it (as Cursor's chat panel lists its
// own), where the history button of its title shows them. A search over
// them, focused as it shows; the agents grouped by when they were last at
// work, pinned ones first; the arrows and Enter pick one, Escape or a click
// outside goes back to the chat. A row hovered has its agent's pin, archive
// and delete at hand, its right click the rest of its menu.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../base/smooth_scroll.dart';
import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/thread_status_mark.dart';
import '../workspace/workspace.dart';
import 'ide_chat_title.dart' show IdeThreadIcon;
import 'ide_dates.dart';
import 'ide_fuzzy.dart';
import 'ide_hover.dart';
import 'ide_input.dart';
import 'ide_menu.dart';
import 'ide_quick_input.dart' show IdeQuickInput;

/// An agent's own actions on a menu (as the sidebar's): rename where it
/// can be, pin or archive one that is listed, fork one with a
/// conversation, copy the id Claude Code finds it by.
List<IdeMenuAction> ideAgentMenuActions(
  BuildContext context,
  AgentThread thread, {
  VoidCallback? onRename,
  required ValueChanged<AgentThread> onPin,
  required ValueChanged<AgentThread> onArchive,
  required ValueChanged<AgentThread> onFork,
}) {
  final l10n = context.l10n;
  // A fork keeps the conversation: none before its first message.
  final canFork =
      thread.id != null && (!thread.isOpen || thread.session.canFork);
  return [
    if (onRename != null)
      IdeMenuAction(l10n.commonRename, onSelected: onRename),
    // A new one, nothing sent to it, is in no list to pin or archive it in.
    if (!thread.untouched) ...[
      if (!thread.archived)
        IdeMenuAction(
          thread.pinned ? l10n.sidebarUnpin : l10n.sidebarPin,
          onSelected: () => onPin(thread),
        ),
      IdeMenuAction(
        thread.archived ? l10n.sidebarUnarchive : l10n.sidebarArchive,
        onSelected: () => onArchive(thread),
      ),
    ],
    if (canFork)
      IdeMenuAction(l10n.sidebarFork, onSelected: () => onFork(thread)),
    // Claude Code finds the conversation by it (none before the first
    // message).
    if (thread.id case final id?)
      IdeMenuAction(
        l10n.sidebarCopySessionId,
        onSelected: () => unawaited(Clipboard.setData(ClipboardData(text: id))),
      ),
  ];
}

class IdeChatHistory extends StatefulWidget {
  const IdeChatHistory({
    super.key,
    required this.threads,
    required this.current,
    required this.onOpen,
    required this.onPin,
    required this.onArchive,
    required this.onFork,
    required this.onDelete,
    required this.onDismiss,
  });

  /// The folder's agents, archived ones included.
  final List<AgentThread> threads;

  /// The agent the chat shows.
  final AgentThread? current;

  /// Shows an agent in the chat; the history is then gone.
  final ValueChanged<AgentThread> onOpen;
  final ValueChanged<AgentThread> onPin;
  final ValueChanged<AgentThread> onArchive;
  final ValueChanged<AgentThread> onFork;

  /// Deletes an agent's conversation, once confirmed.
  final ValueChanged<AgentThread> onDelete;

  /// Goes back to the chat, nothing picked.
  final VoidCallback onDismiss;

  static const rowHeight = 28.0;
  static const headerHeight = 28.0;

  /// The panel's size at most, narrower or shorter in a small chat.
  static const width = 360.0;
  static const maxHeight = 480.0;

  @override
  State<IdeChatHistory> createState() => _IdeChatHistoryState();
}

/// A row of the list: a group's header, or one of its agents with where
/// its title matched the search.
sealed class _Entry {
  const _Entry();
}

class _Header extends _Entry {
  const _Header(this.label);

  final String label;
}

class _Agent extends _Entry {
  const _Agent(this.thread, this.title, this.matches);

  final AgentThread thread;
  final String title;
  final List<int> matches;
}

class _IdeChatHistoryState extends State<IdeChatHistory> {
  final _query = TextEditingController();
  final _input = FocusNode();
  final _scroll = SmoothScrollController();

  /// Archived agents listed too, in a group of their own at the end.
  bool _archived = false;

  /// The agent the arrows are on, which Enter opens.
  AgentThread? _selected;

  List<_Entry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _query.addListener(_queryChanged);
    _selected = widget.current;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _input.requestFocus();
      _reveal();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _relist();
  }

  @override
  void didUpdateWidget(IdeChatHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    _relist();
  }

  /// Lists the agents anew; one deleted or archived away leaves the arrows
  /// on the first.
  void _relist() {
    _entries = _list();
    if (!_agents.any((agent) => identical(agent.thread, _selected))) {
      _selected = _agents.firstOrNull?.thread;
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Iterable<_Agent> get _agents => _entries.whereType<_Agent>();

  void _queryChanged() {
    setState(() {
      _entries = _list();
      _selected = _agents.firstOrNull?.thread;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// The agents the search finds, grouped: pinned, then by the day each
  /// was last at work, then archived ones when they are asked for. A new
  /// one nothing was sent to has no history yet.
  List<_Entry> _list() {
    final l10n = context.l10n;
    final query = _query.text.trim();
    final found = <_Agent>[];
    final sorted = [
      for (final thread in widget.threads)
        if (!thread.untouched && (_archived || !thread.archived)) thread,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final thread in sorted) {
      final title = thread.localizedTitle(l10n);
      if (query.isEmpty) {
        found.add(_Agent(thread, title, const []));
      } else if (ideFuzzyMatch(query, title) case final match?) {
        found.add(_Agent(thread, title, match.positions));
      }
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int daysAgo(AgentThread thread) {
      final time = thread.updatedAt;
      return today.difference(DateTime(time.year, time.month, time.day)).inDays;
    }

    final groups = <(String, bool Function(AgentThread))>[
      (l10n.sidebarPinned, (t) => !t.archived && t.pinned),
      (l10n.sidebarToday, (t) => !t.archived && !t.pinned && daysAgo(t) <= 0),
      (
        l10n.sidebarYesterday,
        (t) => !t.archived && !t.pinned && daysAgo(t) == 1,
      ),
      (
        l10n.sidebarPrevious7Days,
        (t) => !t.archived && !t.pinned && daysAgo(t) > 1 && daysAgo(t) <= 7,
      ),
      (l10n.sidebarOlder, (t) => !t.archived && !t.pinned && daysAgo(t) > 7),
      (l10n.sidebarArchived, (t) => t.archived),
    ];
    final entries = <_Entry>[];
    for (final (label, test) in groups) {
      final agents = found.where((agent) => test(agent.thread));
      if (agents.isEmpty) continue;
      entries
        ..add(_Header(label))
        ..addAll(agents);
    }
    return entries;
  }

  double _heightOf(_Entry entry) => switch (entry) {
    _Header() => IdeChatHistory.headerHeight,
    _Agent() => IdeChatHistory.rowHeight,
  };

  /// Moves the arrows' agent by [by] rows, stopping at the ends.
  void _move(int by) {
    final agents = _agents.map((agent) => agent.thread).toList();
    if (agents.isEmpty) return;
    final at = agents.indexWhere((thread) => identical(thread, _selected));
    final next = at < 0
        ? (by > 0 ? 0 : agents.length - 1)
        : (at + by).clamp(0, agents.length - 1);
    setState(() => _selected = agents[next]);
    _reveal();
  }

  /// Scrolls the arrows' agent into view, its group's header too when it
  /// is the group's first.
  void _reveal() {
    if (!_scroll.hasClients) return;
    final at = _entries.indexWhere(
      (entry) => entry is _Agent && identical(entry.thread, _selected),
    );
    if (at < 0) return;
    var top = 0.0;
    for (var i = 0; i < at; i++) {
      top += _heightOf(_entries[i]);
    }
    final bottom = top + IdeChatHistory.rowHeight;
    if (at > 0 && _entries[at - 1] is _Header) {
      top -= IdeChatHistory.headerHeight;
    }
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top.clamp(0, position.maxScrollExtent));
    } else if (bottom > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(
        (bottom - position.viewportDimension).clamp(
          0,
          position.maxScrollExtent,
        ),
      );
    }
  }

  void _open(AgentThread thread) => widget.onOpen(thread);

  void _showMenu(AgentThread thread, Offset position) {
    void act(VoidCallback action) {
      if (mounted) action();
    }

    unawaited(
      showIdeMenu(
        context,
        position: position,
        entries: ideMenuGroups([
          ideAgentMenuActions(
            context,
            thread,
            onPin: (thread) => act(() => widget.onPin(thread)),
            onArchive: (thread) => act(() => widget.onArchive(thread)),
            onFork: (thread) => act(() => widget.onFork(thread)),
          ),
          [
            IdeMenuAction(
              context.l10n.commonDelete,
              onSelected: () => act(() => widget.onDelete(thread)),
            ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entries = _entries;
    final anyAgents = widget.threads.any(
      (thread) => !thread.untouched && (_archived || !thread.archived),
    );
    final panel = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: IdeInputBox(
            controller: _query,
            focusNode: _input,
            placeholder: l10n.sidebarSearchAgents,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            semanticsLabel: l10n.sidebarSearchAgents,
            toggles: [
              IdeInputToggle(
                icon: Codicons.archive,
                tooltip: l10n.ideChatShowArchived,
                checked: _archived,
                onChanged: (archived) => setState(() {
                  _archived = archived;
                  _relist();
                }),
              ),
            ],
            togglesInset: 3,
            onSubmitted: (_) {
              if (_selected case final thread?) {
                _open(thread);
              } else {
                _input.requestFocus();
              }
            },
            shortcuts: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _move(1),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _move(-1),
              const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                  _move(10),
              const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                  _move(-10),
              const SingleActivator(LogicalKeyboardKey.escape):
                  widget.onDismiss,
            },
          ),
        ),
        Flexible(
          child: entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Text(
                    anyAgents
                        ? l10n.sidebarNoMatchingAgents
                        : l10n.ideChatNoAgents,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: themeColors['descriptionForeground'],
                      fontSize: 12.5,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 6),
                  itemCount: entries.length,
                  itemExtentBuilder: (index, _) =>
                      index < entries.length ? _heightOf(entries[index]) : null,
                  itemBuilder: (context, index) => switch (entries[index]) {
                    final _Header header => _GroupHeader(header.label),
                    final _Agent agent => _HistoryRow(
                      thread: agent.thread,
                      title: agent.title,
                      matches: agent.matches,
                      current: identical(agent.thread, widget.current),
                      selected: identical(agent.thread, _selected),
                      onOpen: () => _open(agent.thread),
                      onPin: () => widget.onPin(agent.thread),
                      onArchive: () => widget.onArchive(agent.thread),
                      onDelete: () => widget.onDelete(agent.thread),
                      onMenu: (position) => _showMenu(agent.thread, position),
                    ),
                  },
                ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          // A click outside goes back to the chat, as the quick input's.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismiss,
            ),
          ),
          // Under the title's history button, as Cursor's: the quick
          // input's border, corners and shadow.
          Positioned(
            top: 6,
            right: 6,
            width: math.min(
              IdeChatHistory.width,
              math.max(0, constraints.maxWidth - 12),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.min(
                  IdeChatHistory.maxHeight,
                  math.max(0, constraints.maxHeight - 12),
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    IdeQuickInput.cornerRadius,
                  ),
                  boxShadow: IdeQuickInput.shadows,
                ),
                child: Material(
                  color: IdeQuickInput.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      IdeQuickInput.cornerRadius,
                    ),
                    side: BorderSide(color: IdeQuickInput.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: panel,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A group's name over its agents, as the sidebar's.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 2),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: themeColors['descriptionForeground'],
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// One agent: its icon (a spinner while it runs), its title with where the
/// search matched it and its status dot, and how long ago it was at work;
/// hovered, its pin, archive and delete in place of the time.
class _HistoryRow extends StatefulWidget {
  const _HistoryRow({
    required this.thread,
    required this.title,
    required this.matches,
    required this.current,
    required this.selected,
    required this.onOpen,
    required this.onPin,
    required this.onArchive,
    required this.onDelete,
    required this.onMenu,
  });

  final AgentThread thread;
  final String title;
  final List<int> matches;

  /// The agent the chat shows.
  final bool current;

  /// The one the arrows are on.
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onPin;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final ValueChanged<Offset> onMenu;

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final thread = widget.thread;
    final selected = widget.selected;
    final background = selected
        ? colors['quickInputList.focusBackground']
        : _hover
        ? colors['list.hoverBackground']
        : Colors.transparent;
    final color = selected
        ? colors.get('quickInputList.focusForeground') ?? colors['foreground']
        : _hover
        ? colors.get('list.hoverForeground') ?? colors['foreground']
        : colors['foreground'];
    final muted = color.withValues(alpha: color.a * (selected ? .85 : .65));
    final highlight = TextStyle(
      color:
          colors[selected
              ? 'quickInputList.focusHighlightForeground'
              : 'list.highlightForeground'],
      fontWeight: FontWeight.w600,
    );
    // Its dot after the title, the title cut short before it.
    final title = Row(
      children: [
        Flexible(
          child: Text.rich(
            TextSpan(
              children: ideHighlightSpans(
                widget.title,
                widget.matches,
                highlight,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: widget.current ? FontWeight.w600 : null,
                ),
              ),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ThreadStatusBuilder(
          thread,
          (context, status) => switch (status) {
            ThreadStatus.needsInput || ThreadStatus.unread => Padding(
              padding: const EdgeInsetsDirectional.only(start: 6),
              child: ThreadStatusMark(status),
            ),
            _ => const SizedBox.shrink(),
          },
        ),
      ],
    );
    final trailing = _hover
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!thread.archived)
                IdeActionButton(
                  icon: thread.pinned ? Codicons.pinned : Codicons.pin,
                  tooltip: thread.pinned ? l10n.sidebarUnpin : l10n.sidebarPin,
                  color: color,
                  onPressed: widget.onPin,
                ),
              IdeActionButton(
                icon: Codicons.archive,
                tooltip: thread.archived
                    ? l10n.sidebarUnarchive
                    : l10n.sidebarArchive,
                color: color,
                onPressed: widget.onArchive,
              ),
              IdeActionButton(
                icon: Codicons.trash,
                tooltip: l10n.commonDelete,
                color: color,
                onPressed: widget.onDelete,
              ),
            ],
          )
        : Text(
            ideFromNow(thread.updatedAt, ago: true, l10n: l10n),
            style: TextStyle(color: muted, fontSize: 11.5),
          );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        onSecondaryTapUp: (details) => widget.onMenu(details.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Container(
            padding: const EdgeInsets.only(left: 8, right: 4),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(4),
              border: switch (selected
                  ? colors.get('contrastActiveBorder')
                  : null) {
                final outline? => Border.all(color: outline),
                null => null,
              },
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  child: Center(
                    child: IconTheme.merge(
                      data: IconThemeData(color: color, size: 16),
                      child: IdeThreadIcon(thread),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: title),
                const SizedBox(width: 8),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
