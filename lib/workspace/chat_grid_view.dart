import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../ide/ide_modern_ui.dart';
import '../l10n/l10n.dart';
import '../sidebar/sidebar.dart' show StatusIndicator;
import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'chat_drag.dart';
import 'chat_grid.dart';
import 'workspace.dart';

/// Where a pane is in the grid, for what the window keeps at its top
/// corners: the macOS traffic lights and the sidebar's toggle at the left,
/// the pin and the editor button at the right.
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
class ChatGridView extends StatefulWidget {
  const ChatGridView({
    super.key,
    required this.grid,
    required this.drag,
    required this.onFocus,
    required this.paneBuilder,
    this.onLinesMoved,
    this.paneBackground,
    this.focused,
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

  /// Behind an agent's pane, of several (none: the view's own): the whole
  /// of its place, up to the lines either side and the view's edges, so
  /// no gap shows between it and them.
  final Color? Function(AgentThread thread)? paneBackground;

  /// The focused agent: of several, its pane outlined in the drop
  /// preview's line (see [frameColor]).
  final AgentThread? focused;

  /// The focused pane's outline: `focusBorder`, a little faded, as the
  /// drop preview's (see [_DropBox]).
  static Color get frameColor {
    final color = themeColors['focusBorder'];
    return color.withValues(alpha: color.a * .8);
  }

  /// Between two panes: the line in the middle, and the sash over it.
  static const gap = 5.0;

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
    // Shown already: its own pane, focused once released.
    if (rects[thread] case final rect?) {
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
    PaneSide? side;
    var nearest = ChatGridView.edgeZone;
    for (final candidate in PaneSide.values) {
      if (!grid.canSplit(target, candidate)) continue;
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
      );
    }
    final next = grid.copy()..split(target, side, thread);
    // A new line needs room for a pane at its least either side of it.
    final growth = Size(
      !grid.columnsSplit && next.columnsSplit
          ? math.max(0, 2 * _min.width + _gap - size.width)
          : 0,
      !grid.rowsSplit && next.rowsSplit
          ? math.max(0, 2 * _min.height + _gap - size.height)
          : 0,
    );
    final windowRoom = widget.drag.room;
    return ChatDrop(
      thread: thread,
      target: target,
      side: side,
      preview: _layout(next, size)[thread]!,
      growth: growth,
      // Less than a pixel short is room enough.
      fits:
          windowRoom == null ||
          (windowRoom.width + .5 >= growth.width &&
              windowRoom.height + .5 >= growth.height),
    );
  }

  ChatPanePlace _place(ChatGrid<AgentThread> grid, AgentThread thread) => (
    topLeft: grid.at(0) == thread,
    topRight: grid.at(1) == thread,
    top: grid.touches(thread, PaneSide.top),
    alone: grid.length == 1,
  );

  /// Where the line being dragged was when the drag began.
  double _dragStart = 0;

  /// Drags the column line (or, [axis] vertical, the row line) [delta] from
  /// where it was when the drag began.
  void _dragLine(Axis axis, double delta) {
    final grid = widget.grid;
    final extent = axis == Axis.horizontal ? _size.width : _size.height;
    if (extent <= 0) return;
    final least = axis == Axis.horizontal ? _min.width : _min.height;
    final ratio =
        ChatGrid.line(
          (_dragStart + delta) / extent,
          extent,
          gap: _gap,
          minPane: least,
        ) /
        extent;
    if (axis == Axis.horizontal) {
      grid.columnRatio = ratio;
    } else {
      grid.rowRatio = ratio;
    }
    _moved.value++;
  }

  Widget _sash(Axis axis) {
    final grid = widget.grid;
    final horizontal = axis == Axis.horizontal;
    return _GridSash(
      axis: axis,
      onStart: () => _dragStart = ChatGrid.line(
        horizontal ? grid.columnRatio : grid.rowRatio,
        horizontal ? _size.width : _size.height,
        gap: _gap,
        minPane: horizontal ? _min.width : _min.height,
      ),
      onDrag: (delta) => _dragLine(axis, delta),
      onEnd: () => widget.onLinesMoved?.call(),
      onReset: () {
        if (horizontal) {
          grid.columnRatio = .5;
        } else {
          grid.rowRatio = .5;
        }
        _moved.value++;
        widget.onLinesMoved?.call();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final grid = widget.grid;
    final background = grid.panes.length > 1 ? widget.paneBackground : null;
    return CustomMultiChildLayout(
      delegate: _GridLayout(
        grid,
        onLayout: (size) => _size = size,
        relayout: _moved,
      ),
      children: [
        // Under the panes, and the lines over them.
        if (background != null)
          for (final thread in grid.panes)
            if (background(thread) case final color?)
              LayoutId(
                id: _backdrop(thread),
                child: ColoredBox(color: color),
              ),
        for (final thread in grid.panes)
          LayoutId(
            id: thread,
            child: Listener(
              onPointerDown: (event) {
                if (event.pointer != KeepPaneFocus._pointer) {
                  widget.onFocus(thread);
                }
              },
              child: _framed(
                identical(thread, widget.focused) && grid.panes.length > 1,
                widget.paneBuilder(context, thread, _place(grid, thread)),
              ),
            ),
          ),
        if (grid.columnsSplit)
          LayoutId(
            key: const ValueKey('column sash'),
            id: _GridPart.columnLine,
            child: _sash(Axis.horizontal),
          ),
        if (grid.rowsSplit)
          LayoutId(
            key: const ValueKey('row sash'),
            id: _GridPart.rowLine,
            child: _sash(Axis.vertical),
          ),
        LayoutId(
          id: _GridPart.preview,
          child: _DropPreview(drag: widget.drag),
        ),
      ],
    );
  }
}

/// [child], outlined over it while [framed]: inset from its edges as the
/// drop preview is (see [_DropPreview]), off the window's.
Widget _framed(bool framed, Widget child) => Stack(
  fit: StackFit.passthrough,
  children: [
    child,
    if (framed)
      Positioned.fill(
        child: IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: ChatGridView.frameColor),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ),
  ],
);

/// Where a press does not focus the pane it is in: the window's own tools
/// in the top right pane's title bar (which act on the focused agent, not
/// that pane's), and a pane's close button.
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

enum _GridPart { columnLine, rowLine, preview, backdrop }

/// Behind [thread]'s pane (see [ChatGridView.paneBackground]).
(_GridPart, AgentThread) _backdrop(AgentThread thread) =>
    (_GridPart.backdrop, thread);

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
      // Out to the middle of each gap, where the line is, or to the edge.
      if (hasChild(_backdrop(pane))) {
        _place(
          _backdrop(pane),
          Rect.fromLTRB(
            rect.left > 0 ? rect.left - _gap / 2 : 0,
            rect.top > 0 ? rect.top - _gap / 2 : 0,
            rect.right < size.width ? rect.right + _gap / 2 : size.width,
            rect.bottom < size.height ? rect.bottom + _gap / 2 : size.height,
          ),
        );
      }
    }
    final x = ChatGrid.line(
      grid.columnRatio,
      size.width,
      gap: _gap,
      minPane: _min.width,
    );
    final y = ChatGrid.line(
      grid.rowRatio,
      size.height,
      gap: _gap,
      minPane: _min.height,
    );
    // Where one pane has a whole row (or column), the other line stops at
    // it.
    if (hasChild(_GridPart.columnLine)) {
      final top = grid.columnLineIn(0) ? 0.0 : y + _gap / 2;
      final bottom = grid.columnLineIn(1) ? size.height : y - _gap / 2;
      _place(
        _GridPart.columnLine,
        Rect.fromLTRB(x - _gap / 2, top, x + _gap / 2, bottom),
      );
    }
    if (hasChild(_GridPart.rowLine)) {
      final left = grid.rowLineIn(0) ? 0.0 : x + _gap / 2;
      final right = grid.rowLineIn(1) ? size.width : x - _gap / 2;
      _place(
        _GridPart.rowLine,
        Rect.fromLTRB(left, y - _gap / 2, right, y + _gap / 2),
      );
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
    final note = !drop.fits
        ? context.l10n.workspaceNotEnoughRoom
        : drop.growth != Size.zero
        ? context.l10n.workspaceWindowGrows
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
        // At rest the sidebar's border line, in the middle of the gap;
        // dragged, as thick as the IDE's sashes, in their `sash.hoverBorder`.
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: _horizontal ? (_dragging ? IdeModernUI.gap : 1) : null,
            height: _horizontal ? null : (_dragging ? IdeModernUI.gap : 1),
            color: _dragging ? IdeModernUI.sashHover : AppColors.partBorder,
          ),
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
        final at = drag.position;
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
              child: IgnorePointer(child: _DragChip(thread: thread)),
            ),
          ],
        );
      },
    );
  }
}

/// The agent being dragged: its status and title, as its row has them.
class _DragChip extends StatelessWidget {
  const _DragChip({required this.thread});

  final AgentThread thread;

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
            child: Center(child: StatusIndicator(thread.status)),
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
        ],
      ),
    );
  }
}
