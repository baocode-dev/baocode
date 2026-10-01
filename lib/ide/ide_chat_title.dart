// The title over the IDE's chat: the folder's chats as tabs, each
// closable and dragged to order, its agent's status on it (as the
// sidebar's), a button for a new one, and one listing the folder's agents to
// open one as a tab (as VS Code's chat view titles its New Chat and Show
// Chats actions).

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
import 'ide_panes.dart';
import 'ide_quick_input.dart';
import 'ide_workbench.dart';

class IdeChatTitle extends StatelessWidget {
  const IdeChatTitle({
    super.key,
    required this.tabs,
    required this.threads,
    required this.current,
    required this.onNew,
    required this.onOpen,
    required this.onClose,
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
  final ValueChanged<AgentThread> onClose;

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
    return SizedBox(
      height: 35,
      child: Row(
        children: [
          Expanded(
            child: _ChatTabs(
              tabs: tabs,
              current: current,
              onOpen: onOpen,
              onClose: onClose,
              onMove: onMove,
            ),
          ),
          IdePaneAction(
            icon: Codicons.add,
            tooltip: keybindings.titleWithKeybinding(
              l10n.sidebarNewAgent,
              ChatCommandIds.newChat,
            ),
            onPressed: onNew,
          ),
          IdePaneAction(
            icon: Codicons.history,
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
    required this.onMove,
  });

  final List<AgentThread> tabs;
  final AgentThread? current;
  final ValueChanged<AgentThread> onOpen;
  final ValueChanged<AgentThread> onClose;
  final void Function(AgentThread thread, int index) onMove;

  /// As VS Code's `workbench.editor.titleScrollbarSizing` by default.
  static const scrollbarThickness = 3.0;

  @override
  State<_ChatTabs> createState() => _ChatTabsState();
}

class _ChatTabsState extends State<_ChatTabs> {
  final _scroll = ScrollController();
  final Map<AgentThread, GlobalKey> _keys = {};
  bool _hover = false;

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

  /// A wheel, up and down or sideways, scrolls the tabs sideways.
  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final position = _scroll.position;
      _scroll.jumpTo(
        (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tabs = widget.tabs;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerSignal: _wheel,
        child: RawScrollbar(
          controller: _scroll,
          thumbVisibility: _hover,
          interactive: true,
          thickness: _ChatTabs.scrollbarThickness,
          radius: Radius.zero,
          crossAxisMargin: 0,
          mainAxisMargin: 0,
          minThumbLength: 24,
          thumbColor: themeColors['scrollbarSlider.background'],
          child: ScrollConfiguration(
            // Its own bar alone, not the platform's thicker one too.
            behavior: ScrollConfiguration.of(context)
                .copyWith(scrollbars: false),
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 6),
              child: Row(
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
                          onClose: () => widget.onClose(thread),
                        ),
                      ),
                    ),
                  ],
                  if (_spot == tabs.length) const _DropLine(),
                ],
              ),
            ),
          ),
        ),
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

/// One chat's tab: its title, and a close button while it is the shown one
/// or hovered (as an editor tab's).
class _ChatTab extends StatefulWidget {
  const _ChatTab({
    super.key,
    required this.thread,
    required this.title,
    required this.active,
    required this.closeTooltip,
    required this.onSelect,
    required this.onClose,
  });

  final AgentThread thread;
  final String title;
  final bool active;
  final String closeTooltip;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  bool _hover = false;

  /// The title's width in bold whether or not the tab is active, so that
  /// selecting a tab does not widen it and nudge the tabs after it.
  double _titleWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: widget.title,
        style: DefaultTextStyle.of(context).style
            .merge(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width > 140 ? 140 : width;
  }

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final active = widget.active;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        // A middle click closes it, as an editor tab.
        onTertiaryTapUp: (_) => widget.onClose(),
        child: Container(
          height: 26,
          margin: const EdgeInsets.only(right: 2),
          padding: const EdgeInsets.only(left: 8, right: 2),
          decoration: BoxDecoration(
            color: active
                ? colors['list.activeSelectionBackground'].withValues(alpha: .5)
                : _hover
                ? colors['list.hoverBackground']
                : null,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A spinner before its title while its agent runs, hovered
              // or not.
              _StatusBuilder(
                widget.thread,
                (context, status) => status == ThreadStatus.running
                    ? const Padding(
                        padding: EdgeInsetsDirectional.only(end: 6),
                        child: _StatusMark(ThreadStatus.running),
                      )
                    : const SizedBox.shrink(),
              ),
              SizedBox(
                width: _titleWidth(context),
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    color: active
                        ? IdeViewTitle.foreground
                        : colors['descriptionForeground'],
                  ),
                ),
              ),
              const SizedBox(width: 2),
              // A dot where the close button goes when its agent asks or
              // finished unseen, but while the pointer is over it (as an
              // editor tab's dirty dot).
              _StatusBuilder(
                widget.thread,
                (context, status) =>
                    (status == ThreadStatus.needsInput ||
                            status == ThreadStatus.unread) &&
                        !_hover
                    ? SizedBox.square(
                        dimension: 20,
                        child: Center(child: _StatusMark(status)),
                      )
                    : Opacity(
                        opacity: active || _hover ? 1 : 0,
                        child: IdeActionButton(
                          icon: Codicons.close,
                          tooltip: widget.closeTooltip,
                          onPressed: widget.onClose,
                          size: 20,
                          iconSize: 14,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
