import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../sidebar/sidebar.dart' show StatusIndicator;
import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'chat_drag.dart';
import 'chat_grid.dart';
import 'islands.dart';
import 'workspace.dart';

/// Where a pane is in the grid, for what the window keeps at its top
/// corners: the macOS traffic lights and the sidebar's toggle at the left,
/// the window's pin at the right.
typedef ChatPanePlace = ({bool topLeft, bool topRight, bool top, bool alone});

/// The agents of [grid], each in its pane: [ChatGrid.layout]'s rectangles,
/// [gap] apart, the whole of the view between them (none moves as another
/// comes or goes but the one split). In each gap, the line the sidebar has
/// beside the chat, over a sash that drags it.
///
/// A new size, or a line dragged, only lays the panes out anew: they are
/// built again only as the grid changes.
///
/// Over it, the place an agent dragged from the sidebar would go, released
/// there ([ChatDrag]): the half of the pane under the pointer on the side
/// it is near, where the grid can split that way; else the pane itself.
/// A title bar's drag moves the existing pane beside it, or swaps places.
class ChatGridView extends StatefulWidget {
  const ChatGridView({
    super.key,
    required this.grid,
    required this.drag,
    required this.onFocus,
    required this.paneBuilder,
    this.onLinesMoved,
  });

  final ChatGrid<AgentThread> grid;
  final ChatDrag drag;

  /// A press in the pane of an agent: it becomes the focused one.
  final ValueChanged<AgentThread> onFocus;

  final Widget Function(
    BuildContext context,
    AgentThread thread,
    ChatPanePlace place,
  )
  paneBuilder;

  /// A line dragged and let go, or put back in the middle.
  final VoidCallback? onLinesMoved;

  /// The focused pane's outline, of several (see [ChatScreen.islandBorder]):
  /// `focusBorder`, faded to half, enough to tell it from the cards' own
  /// outline without drawing the eye from what is in it.
  static Color get frameColor {
    final color = themeColors['focusBorder'];
    return color.withValues(alpha: color.a * .5);
  }

  /// Between two panes' cards: the sash in it.
  static const gap = Islands.gap;

  /// The least a pane is, where the window has room: the composer's
  /// toolbar across; the title, a few lines and the composer down.
  static const minPane = Size(360, 300);

  /// Within this share of a pane's width (or height) from one of its sides,
  /// a drop goes beside it; further in, in its place.
  static const edgeZone = 1 / 3;

  @override
  State<ChatGridView> createState() => _ChatGridViewState();
}

class _ChatGridViewState extends State<ChatGridView> {
  static const _gap = ChatGridView.gap;
  static const _min = ChatGridView.minPane;

  /// Ticks as a line is dragged: the grid is laid out again, not built.
  final ValueNotifier<int> _moved = ValueNotifier(0);

  /// The size the grid was last laid out at: what a line's drag is a share
  /// of.
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    widget.drag.resolve = _resolve;
  }

  @override
  void didUpdateWidget(ChatGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.drag, widget.drag)) {
      if (oldWidget.drag.resolve == _resolve) oldWidget.drag.resolve = null;
      widget.drag.resolve = _resolve;
    }
  }

  @override
  void dispose() {
    if (widget.drag.resolve == _resolve) widget.drag.resolve = null;
    _moved.dispose();
    super.dispose();
  }

  static Map<AgentThread, Rect> _layout(
    ChatGrid<AgentThread> grid,
    Size size,
  ) => grid.layout(size, gap: _gap, minPane: _min);

  /// How far [point] is from [rect]: 0 in it.
  static double _distance(Rect rect, Offset point) => Offset(
    math.max(0, math.max(rect.left - point.dx, point.dx - rect.right)),
    math.max(0, math.max(rect.top - point.dy, point.dy - rect.bottom)),
  ).distance;

  ChatDrop? _resolve(AgentThread thread, Offset position) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final size = box.size;
    final at = box.globalToLocal(position);
    if (!(Offset.zero & size).contains(at)) return null;
    final grid = widget.grid;
    final rects = _layout(grid, size);
    if (rects.isEmpty) return null;
    final rearrange = widget.drag.rearranging;
    if (rearrange && !grid.contains(thread)) return null;
    // A sidebar row shown already only focuses its pane. A title bar's
    // drag can move it elsewhere in the grid instead.
    if (!rearrange && rects[thread] != null) {
      final rect = rects[thread]!;
      return ChatDrop(
        thread: thread,
        target: thread,
        side: null,
        preview: rect,
      );
    }
    // The pane under the pointer; over a gap, the nearest.
    final MapEntry(key: target, value: rect) = rects.entries.reduce(
      (a, b) => _distance(a.value, at) <= _distance(b.value, at) ? a : b,
    );
    if (rearrange && identical(thread, target)) return null;
    // Removing the moved pane frees its cells before splitting the target.
    final splitGrid = rearrange ? (grid.copy()..remove(thread)) : grid;
    PaneSide? side;
    var nearest = ChatGridView.edgeZone;
    for (final candidate in PaneSide.values) {
      if (!splitGrid.canSplit(target, candidate)) continue;
      final away = switch (candidate) {
        PaneSide.left => (at.dx - rect.left) / rect.width,
        PaneSide.right => (rect.right - at.dx) / rect.width,
        PaneSide.top => (at.dy - rect.top) / rect.height,
        PaneSide.bottom => (rect.bottom - at.dy) / rect.height,
      };
      if (away < nearest) {
        nearest = away;
        side = candidate;
      }
    }
    if (side == null) {
      return ChatDrop(
        thread: thread,
        target: target,
        side: null,
        preview: rect,
        rearrange: rearrange,
        // Of several, over the pane (a title bar's swaps them).
        covers: !rearrange && grid.length > 1,
      );
    }
    final next = splitGrid.copy()..split(target, side, thread);
    // Room for each pane at its least, where the grid needs more than it did.
    final before = grid.least(_min, _gap);
    final after = next.least(_min, _gap);
    final growth = Size(
      after.width > before.width ? math.max(0, after.width - size.width) : 0,
      after.height > before.height
          ? math.max(0, after.height - size.height)
          : 0,
    );
    final windowRoom = widget.drag.room;
    return ChatDrop(
      thread: thread,
      target: target,
      side: side,
      preview: _layout(next, size)[thread]!,
      growth: growth,
      rearrange: rearrange,
      // Less than a pixel short is room enough.
      fits:
          windowRoom == null ||
          (windowRoom.width + .5 >= growth.width &&
              windowRoom.height + .5 >= growth.height),
    );
  }

  ChatPanePlace _place(ChatGrid<AgentThread> grid, AgentThread thread) => (
    topLeft: grid.topLeft == thread,
    topRight: grid.topRight == thread,
    top: grid.touches(thread, PaneSide.top),
    alone: grid.length == 1,
  );

  /// Where the line being dragged was when the drag began.
  double _dragStart = 0;

  Widget _sash(GridLine line) {
    final grid = widget.grid;
    return _GridSash(
      axis: grid.isColumnLine(line) ? Axis.horizontal : Axis.vertical,
      onStart: () =>
          _dragStart = grid.position(line, _size, gap: _gap, minPane: _min),
      onDrag: (delta) {
        grid.moveLine(
          line,
          _dragStart + delta,
          size: _size,
          gap: _gap,
          minPane: _min,
        );
        _moved.value++;
      },
      onEnd: () => widget.onLinesMoved?.call(),
      onReset: () {
        grid.centerLine(line);
        _moved.value++;
        widget.onLinesMoved?.call();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final grid = widget.grid;
    return CustomMultiChildLayout(
      delegate: _GridLayout(
        grid,
        onLayout: (size) => _size = size,
        relayout: _moved,
      ),
      children: [
        for (final thread in grid.panes)
          LayoutId(
            key: ObjectKey(thread),
            id: thread,
            child: Listener(
              onPointerDown: (event) {
                if (event.pointer != KeepPaneFocus._pointer) {
                  widget.onFocus(thread);
                }
              },
              child: widget.paneBuilder(context, thread, _place(grid, thread)),
            ),
          ),
        for (final line in grid.lines)
          LayoutId(
            key: ValueKey(_sashKey(grid, line)),
            id: line,
            child: _sash(line),
          ),
        LayoutId(
          id: _GridPart.preview,
          child: _DropPreview(drag: widget.drag),
        ),
      ],
    );
  }
}

/// Where a press does not focus the pane it is in: its title bar's tools,
/// including Close. Each acts on its own pane or project without changing
/// the focus, unless that action itself needs to (the side panel's).
class KeepPaneFocus extends StatelessWidget {
  const KeepPaneFocus({super.key, required this.child});

  final Widget child;

  /// The last press on one: the pane's own listener, an ancestor, hears it
  /// after (and each press has a pointer of its own).
  static int? _pointer;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) => _pointer = event.pointer,
    child: child,
  );
}

enum _GridPart { preview }

/// `column sash` for the first line between the columns (`row sash`, the
/// rows); `column sash 2` for the third; `row sash 1` for the row line in
/// the second column, `row sash 1.2` for the third in the second row's.
String _sashKey(ChatGrid<AgentThread> grid, GridLine line) {
  final axis = grid.isColumnLine(line) ? 'column' : 'row';
  return switch (line) {
    (group: null, index: 0) => '$axis sash',
    (group: null, :final index) => '$axis sash $index',
    (:final group?, index: 0) => '$axis sash $group',
    (:final group?, :final index) => '$axis sash $group.$index',
  };
}

/// The panes on [grid]'s rectangles (see [ChatGrid.layout]); the sashes on
/// the gaps between them; the drop preview over it all.
class _GridLayout extends MultiChildLayoutDelegate {
  _GridLayout(this.grid, {required this.onLayout, super.relayout});

  final ChatGrid<AgentThread> grid;

  /// The size laid out at.
  final ValueChanged<Size> onLayout;

  static const _gap = ChatGridView.gap;
  static const _min = ChatGridView.minPane;

  void _place(Object id, Rect rect) {
    layoutChild(id, BoxConstraints.tight(rect.size));
    positionChild(id, rect.topLeft);
  }

  @override
  void performLayout(Size size) {
    onLayout(size);
    for (final MapEntry(key: pane, value: rect)
        in grid.layout(size, gap: _gap, minPane: _min).entries) {
      if (hasChild(pane)) _place(pane, rect);
    }
    for (final line in grid.lines) {
      if (hasChild(line)) {
        _place(line, grid.lineRect(line, size, gap: _gap, minPane: _min));
      }
    }
    _place(_GridPart.preview, Offset.zero & size);
  }

  // The grid changes in place.
  @override
  bool shouldRelayout(_GridLayout oldDelegate) => true;
}

/// Where the agent dragged would go: the drop color over its place, the
/// error color where the window has no room to make for it.
class _DropPreview extends StatelessWidget {
  const _DropPreview({required this.drag});

  final ChatDrag drag;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: drag,
        builder: (context, _) => Stack(
          children: [
            if (drag.drop case final drop?)
              AnimatedPositioned.fromRect(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                rect: drop.preview.deflate(4),
                child: _DropBox(drop: drop),
              ),
          ],
        ),
      ),
    );
  }
}

class _DropBox extends StatelessWidget {
  const _DropBox({required this.drop});

  final ChatDrop drop;

  @override
  Widget build(BuildContext context) {
    final color = drop.fits
        ? themeColors['focusBorder']
        : themeColors['errorForeground'];
    final l10n = context.l10n;
    final note = !drop.fits
        ? l10n.workspaceNotEnoughRoom
        : drop.growth != Size.zero
        ? l10n.workspaceWindowGrows
        : drop.covers
        ? l10n.workspaceCovers(drop.target.localizedTitle(l10n))
        : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: color.a * .16),
        border: Border.all(color: color.withValues(alpha: color.a * .8)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: note == null
          ? const SizedBox.expand()
          : Center(
              child: Text(
                note,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: drop.fits ? AppColors.textPrimary : color,
                  fontSize: 12.5,
                ),
              ),
            ),
    );
  }
}

/// A line between panes, in the gap, as the sidebar's border is: as thick
/// as the IDE's sashes while dragged; a double click puts it back in the
/// middle.
class _GridSash extends StatefulWidget {
  const _GridSash({
    required this.axis,
    required this.onStart,
    required this.onDrag,
    required this.onEnd,
    required this.onReset,
  });

  /// Which way it moves: between columns, or (vertical) between rows.
  final Axis axis;
  final VoidCallback onStart;

  /// How far the pointer is from where the drag began, along [axis].
  final ValueChanged<double> onDrag;

  /// The drag over.
  final VoidCallback onEnd;
  final VoidCallback onReset;

  @override
  State<_GridSash> createState() => _GridSashState();
}

class _GridSashState extends State<_GridSash> {
  bool _dragging = false;
  double _start = 0;

  /// Over the window while dragging, with the sash's cursor: the pointer
  /// leaves the sash where the line stops, and the cursor stays.
  OverlayEntry? _shield;

  bool get _horizontal => widget.axis == Axis.horizontal;

  MouseCursor get _cursor => _horizontal
      ? SystemMouseCursors.resizeColumn
      : SystemMouseCursors.resizeRow;

  double _along(Offset position) => _horizontal ? position.dx : position.dy;

  void _begin(DragStartDetails details) {
    _start = _along(details.globalPosition);
    widget.onStart();
    setState(() => _dragging = true);
    if (Overlay.maybeOf(context) case final overlay?) {
      _shield = OverlayEntry(
        builder: (context) => MouseRegion(cursor: _cursor, opaque: true),
      );
      overlay.insert(_shield!);
    }
  }

  void _end() {
    _removeShield();
    if (mounted) setState(() => _dragging = false);
    widget.onEnd();
  }

  void _removeShield() {
    _shield
      ?..remove()
      ..dispose();
    _shield = null;
  }

  @override
  void dispose() {
    _removeShield();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void update(DragUpdateDetails details) =>
        widget.onDrag(_along(details.globalPosition) - _start);
    return MouseRegion(
      cursor: _cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: _horizontal ? _begin : null,
        onHorizontalDragUpdate: _horizontal ? update : null,
        onHorizontalDragEnd: _horizontal ? (_) => _end() : null,
        onHorizontalDragCancel: _horizontal ? _end : null,
        onVerticalDragStart: _horizontal ? null : _begin,
        onVerticalDragUpdate: _horizontal ? null : update,
        onVerticalDragEnd: _horizontal ? null : (_) => _end(),
        onVerticalDragCancel: _horizontal ? null : _end,
        onDoubleTap: widget.onReset,
        // The gap between the cards alone at rest; dragged, the IDE's sash.
        child: Islands.sashLine(
          dragging: _dragging,
          axis: _horizontal ? Axis.horizontal : Axis.vertical,
        ),
      ),
    );
  }
}

/// Over the window while an agent is dragged: the agent at the pointer,
/// and the dragging cursor everywhere (no hover effects under it). Covers
/// the window from its top left, where the pointer's position is from.
class ChatDragLayer extends StatelessWidget {
  const ChatDragLayer({super.key, required this.drag});

  final ChatDrag drag;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: drag,
      builder: (context, _) {
        final thread = drag.thread;
        if (thread == null) return const SizedBox.shrink();
        // The pointer is in the window's pixels; the layer may be zoomed
        // (UiZoom), so it is placed in the layer's own.
        final box = context.findRenderObject() as RenderBox?;
        final at = box != null && box.attached && box.hasSize
            ? box.globalToLocal(drag.position)
            : drag.position;
        return Stack(
          children: [
            const Positioned.fill(
              child: MouseRegion(
                cursor: SystemMouseCursors.grabbing,
                opaque: true,
              ),
            ),
            Positioned(
              left: at.dx + 12,
              top: at.dy + 10,
              child: IgnorePointer(
                child: _DragChip(thread: thread, count: drag.threads.length),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The agent being dragged: its status and title, as its row has them.
class _DragChip extends StatelessWidget {
  const _DragChip({required this.thread, required this.count});

  final AgentThread thread;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.all(color: AppColors.partBorder),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(color: themeColors['widget.shadow'], blurRadius: 12),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            child: Center(child: StatusIndicator(thread.shownStatus)),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              thread.localizedTitle(context.l10n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 12.5),
            ),
          ),
          if (count > 1) ...[
            const SizedBox(width: 6),
            Text(
              '+${count - 1}',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
