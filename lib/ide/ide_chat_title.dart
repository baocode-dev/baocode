// The title over the IDE's chat: the folder's chats as tabs, each
// closable (by a right click, the others too) and dragged to order, its agent's status on it (as the
// sidebar's), a button for a new one, and one listing the folder's agents to
// open one as a tab (as VS Code's chat view titles its New Chat and Show
// Chats actions).

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../keybindings/chat_keybindings.dart';
import '../keybindings/keybinding_service.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart' show AppColors;
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/workspace.dart';
import 'ide_dates.dart';
import 'ide_hover.dart';
import 'ide_menu.dart';
import 'ide_quick_input.dart';
import 'ide_tab_bar.dart';
import 'ide_workbench.dart';
import 'tab_strip_scroll.dart';

class IdeChatTitle extends StatelessWidget {
  const IdeChatTitle({
    super.key,
    required this.tabs,
    required this.threads,
    required this.current,
    required this.onNew,
    required this.onOpen,
    required this.onClose,
    required this.onPin,
    required this.onMove,
  });

  /// The chats open as tabs, in order.
  final List<AgentThread> tabs;

  /// The folder's agents, archived ones included (they are left out).
  final List<AgentThread> threads;

  /// The agent the chat shows.
  final AgentThread? current;

  final VoidCallback onNew;

  /// Shows an agent: its tab, or a new tab of it.
  final ValueChanged<AgentThread> onOpen;

  /// Closes the tabs of these agents.
  final ValueChanged<List<AgentThread>> onClose;

  /// Pins an agent, or unpins a pinned one.
  final ValueChanged<AgentThread> onPin;

  /// Moves a tab dragged to [index] among the tabs.
  final void Function(AgentThread thread, int index) onMove;

  /// The agents as the history lists them: pinned ones first, then by date.
  /// A new one nothing was sent to has no history yet.
  List<AgentThread> get _listed {
    final listed = [
      for (final thread in threads)
        if (!thread.archived && !thread.untouched) thread,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [
      ...listed.where((thread) => thread.pinned),
      ...listed.where((thread) => !thread.pinned),
    ];
  }

  void _showHistory(BuildContext context) {
    final workbench = context.findAncestorStateOfType<IdeWorkbenchState>();
    if (workbench == null) return;
    final l10n = context.l10n;
    final items = <AgentThread, IdeQuickPickItem>{
      for (final thread in _listed)
        thread: IdeQuickPickItem(
          label: thread.localizedTitle(l10n),
          description: ideFromNow(thread.updatedAt, ago: true, l10n: l10n),
          icon: _ThreadIcon(thread),
          badge: _StatusBuilder(
            thread,
            (context, status) => switch (status) {
              ThreadStatus.needsInput || ThreadStatus.unread => Padding(
                padding: const EdgeInsetsDirectional.only(start: 6),
                child: _StatusMark(status),
              ),
              _ => const SizedBox.shrink(),
            },
          ),
          onAccept: () => onOpen(thread),
        ),
    };
    workbench.showQuickPick(
      IdeQuickPick(
        items: items.isEmpty
            ? [IdeQuickPickItem(label: l10n.ideChatNoAgents)]
            : items.values.toList(),
        placeholder: l10n.sidebarSearchAgents,
        sortByLabel: false,
        activeItems: [?items[current]],
        onDidAccept: (item) => item?.onAccept?.call(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final keybindings = KeybindingService.instance;
    // The editor's tab strip, as its tabs are the editor's.
    return IdeTabStrip(
      child: Row(
        children: [
          Expanded(
            child: _ChatTabs(
              tabs: tabs,
              current: current,
              onOpen: onOpen,
              onClose: onClose,
              onPin: onPin,
              onMove: onMove,
            ),
          ),
          // Squares nearer the strip's height than a view title's.
          IdeActionButton(
            icon: Codicons.add,
            size: 28,
            tooltip: keybindings.titleWithKeybinding(
              l10n.sidebarNewAgent,
              ChatCommandIds.newChat,
            ),
            onPressed: onNew,
          ),
          IdeActionButton(
            icon: Codicons.history,
            size: 28,
            tooltip: l10n.ideChatHistory,
            onPressed: () => _showHistory(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// The tabs, scrolled sideways when they are too many: by the wheel, or
/// by a thin bar under them shown while the pointer is over them (as
/// VS Code's editor tabs); one dragged goes where a line shows.
class _ChatTabs extends StatefulWidget {
  const _ChatTabs({
    required this.tabs,
    required this.current,
    required this.onOpen,
    required this.onClose,
    required this.onPin,
    required this.onMove,
  });

  final List<AgentThread> tabs;
  final AgentThread? current;
  final ValueChanged<AgentThread> onOpen;
  final ValueChanged<List<AgentThread>> onClose;
  final ValueChanged<AgentThread> onPin;
  final void Function(AgentThread thread, int index) onMove;

  @override
  State<_ChatTabs> createState() => _ChatTabsState();
}

class _ChatTabsState extends State<_ChatTabs> {
  final _scroll = ScrollController();
  final Map<AgentThread, GlobalKey> _keys = {};

  /// The tab dragged, and where it would go: before the tab at that index,
  /// or after the last; none where it is already.
  AgentThread? _dragged;
  int? _spot;

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(_ChatTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.current, widget.current) ||
        oldWidget.tabs.length != widget.tabs.length) {
      _scheduleReveal();
    }
    _keys.removeWhere((thread, _) => !widget.tabs.contains(thread));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls the shown chat's tab into view.
  void _scheduleReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = widget.current;
      final context = current == null ? null : _keys[current]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  void _moveDrag(Offset position) {
    final tabs = widget.tabs;
    final dragged = _dragged;
    if (dragged == null) return;
    // Near an end, the tabs scroll on.
    if (context.findRenderObject() case final RenderBox box
        when _scroll.hasClients) {
      final x = box.globalToLocal(position).dx;
      final step = x < 24 ? -8.0 : (x > box.size.width - 24 ? 8.0 : 0.0);
      if (step != 0) {
        final scrolled = _scroll.position;
        _scroll.jumpTo(
          (scrolled.pixels + step).clamp(
            scrolled.minScrollExtent,
            scrolled.maxScrollExtent,
          ),
        );
      }
    }
    var at = tabs.length;
    for (final (i, thread) in tabs.indexed) {
      final box = _keys[thread]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final middle = box.localToGlobal(box.size.center(Offset.zero)).dx;
      if (position.dx < middle) {
        at = i;
        break;
      }
    }
    final from = tabs.indexOf(dragged);
    final spot = at == from || at == from + 1 ? null : at;
    if (spot != _spot) setState(() => _spot = spot);
  }

  void _endDrag() {
    final (thread, at) = (_dragged, _spot);
    setState(() => _dragged = _spot = null);
    if (thread == null || at == null) return;
    final from = widget.tabs.indexOf(thread);
    if (from < 0) return;
    widget.onMove(thread, at > from ? at - 1 : at);
  }

  /// A tab's right-click menu, at [position]: as an editor tab's, its
  /// closes; then its agent's pin.
  void _showMenu(AgentThread thread, Offset position) {
    final tabs = widget.tabs;
    final at = tabs.indexOf(thread);
    final l10n = context.l10n;
    IdeMenuAction item(
      String label,
      VoidCallback onSelected, {
      bool enabled = true,
    }) => IdeMenuAction(
      label,
      enabled: enabled,
      onSelected: () {
        if (mounted) onSelected();
      },
    );
    unawaited(
      showIdeMenu(
        context,
        position: position,
        entries: ideMenuGroups([
          [
            item(l10n.tabClose, () => widget.onClose([thread])),
            item(
              l10n.tabCloseOthers,
              () => widget.onClose([
                for (final tab in widget.tabs)
                  if (!identical(tab, thread)) tab,
              ]),
              enabled: tabs.length > 1,
            ),
            item(l10n.tabCloseToTheRight, () {
              final from = widget.tabs.indexOf(thread);
              if (from >= 0) widget.onClose(widget.tabs.sublist(from + 1));
            }, enabled: at >= 0 && at < tabs.length - 1),
            item(l10n.tabCloseAll, () => widget.onClose([...widget.tabs])),
          ],
          [
            // A new one, nothing sent to it, is in no list to pin it in.
            if (!thread.untouched && !thread.archived)
              item(
                thread.pinned ? l10n.sidebarUnpin : l10n.sidebarPin,
                () => widget.onPin(thread),
              ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tabs = widget.tabs;
    return TabStripScroll(
      controller: _scroll,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, thread) in tabs.indexed) ...[
            if (_spot == i) const _DropLine(),
            _TabDragSource(
              enabled: tabs.length > 1,
              onStart: () => setState(() => _dragged = thread),
              onUpdate: _moveDrag,
              onEnd: _endDrag,
              child: Opacity(
                opacity: identical(thread, _dragged) ? .5 : 1,
                child: _ChatTab(
                  key: _keys.putIfAbsent(thread, GlobalKey.new),
                  thread: thread,
                  title: thread.localizedTitle(l10n),
                  active: identical(thread, widget.current),
                  closeTooltip: l10n.commonClose,
                  onSelect: () => widget.onOpen(thread),
                  onClose: () => widget.onClose([thread]),
                  onMenu: (position) => _showMenu(thread, position),
                ),
              ),
            ),
          ],
          if (_spot == tabs.length) const _DropLine(),
        ],
      ),
    );
  }
}

/// An agent's icon in the history: a spinner while it runs, as the
/// sidebar shows it; else pinned, or a chat.
class _ThreadIcon extends StatelessWidget {
  const _ThreadIcon(this.thread);

  final AgentThread thread;

  @override
  Widget build(BuildContext context) => _StatusBuilder(
    thread,
    (context, status) => status == ThreadStatus.running
        ? SizedBox.square(
            dimension: 16,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: IconTheme.of(context).color,
              ),
            ),
          )
        : Icon(thread.pinned ? Codicons.pinned : Codicons.commentDiscussion),
  );
}

/// Builds with [thread]'s status, again as it changes: a session not
/// opened has none to change; one that is may start, stop or ask while
/// shown.
class _StatusBuilder extends StatelessWidget {
  const _StatusBuilder(this.thread, this.builder);

  final AgentThread thread;
  final Widget Function(BuildContext context, ThreadStatus status) builder;

  @override
  Widget build(BuildContext context) {
    if (!thread.isOpen) return builder(context, thread.status);
    return ListenableBuilder(
      listenable: thread.session,
      builder: (context, _) => builder(context, thread.status),
    );
  }
}

/// What an agent needs, as the sidebar shows it: a spinner while it runs,
/// an amber dot when it waits on a question, a blue dot when it finished
/// unseen; nothing when idle.
class _StatusMark extends StatelessWidget {
  const _StatusMark(this.status);

  final ThreadStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
    ThreadStatus.running => SizedBox.square(
      dimension: 10,
      child: CircularProgressIndicator(
        strokeWidth: 1.5,
        color: AppColors.textMuted,
      ),
    ),
    ThreadStatus.needsInput => _dot(themeColors['list.warningForeground']),
    ThreadStatus.unread => _dot(AppColors.accent),
    ThreadStatus.idle => const SizedBox.shrink(),
  };

  static Widget _dot(Color color) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// A tab dragged among the tabs: past a few pixels, so a click still
/// selects it.
class _TabDragSource extends StatelessWidget {
  const _TabDragSource({
    required this.enabled,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onStart;

  /// Where the pointer is, globally.
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) => !enabled
      ? child
      : RawGestureDetector(
          gestures: {
            _TabDragRecognizer:
                GestureRecognizerFactoryWithHandlers<_TabDragRecognizer>(
                  _TabDragRecognizer.new,
                  (recognizer) {
                    recognizer
                      ..onStart = ((_) => onStart())
                      ..onUpdate = ((details) =>
                          onUpdate(details.globalPosition))
                      ..onEnd = ((_) => onEnd())
                      ..onCancel = onEnd;
                  },
                ),
          },
          child: child,
        );
}

/// A sideways drag that starts past 4 pixels, mouse or not (a mouse's
/// slop is otherwise 1, which a click can move).
class _TabDragRecognizer extends HorizontalDragGestureRecognizer {
  _TabDragRecognizer() : super(supportedDevices: null);

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => globalDistanceMoved.abs() > 4;
}

/// Where a dragged tab would go: a line between tabs, taking no room.
class _DropLine extends StatelessWidget {
  const _DropLine();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 0,
    height: 22,
    child: OverflowBox(
      maxWidth: 2,
      child: Container(
        width: 2,
        decoration: BoxDecoration(
          color: themeColors['focusBorder'],
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    ),
  );
}

/// One chat's tab, as an editor's: its icon (a spinner while its agent
/// runs), its title, and a close button while it is the shown one or
/// hovered; a dot in its place when its agent asks or finished unseen, as
/// an editor tab's dirty dot.
class _ChatTab extends StatelessWidget {
  const _ChatTab({
    super.key,
    required this.thread,
    required this.title,
    required this.active,
    required this.closeTooltip,
    required this.onSelect,
    required this.onClose,
    required this.onMenu,
  });

  final AgentThread thread;
  final String title;
  final bool active;
  final String closeTooltip;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  /// Opens its menu at a right click's global position.
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) => _StatusBuilder(
    thread,
    (context, status) => IdeEditorTab(
      icon: _ThreadIcon(thread),
      label: title,
      active: active,
      mark: switch (status) {
        ThreadStatus.needsInput ||
        ThreadStatus.unread => (_) => Center(child: _StatusMark(status)),
        _ => null,
      },
      closeTooltip: closeTooltip,
      onSelect: onSelect,
      onClose: onClose,
      onMenu: onMenu,
    ),
  );
}
