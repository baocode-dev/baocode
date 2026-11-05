// The sashes between the parts (upstream sash.ts): a line dragged to
// size the parts beside it, double clicked to reset them.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../ide_modern_ui.dart';
import '../style.dart';

/// [sash] over the line [x] across a row [width] wide, inside it: at the
/// row's edge, all of it on the near side.
Widget positionedSash(double x, double width, Widget sash) => Positioned(
  key: ValueKey(sash.key),
  left: (x - WorkbenchStyle.sashWidth / 2)
      .clamp(0.0, math.max(0.0, width - WorkbenchStyle.sashWidth))
      .toDouble(),
  top: 0,
  bottom: 0,
  width: WorkbenchStyle.sashWidth,
  child: sash,
);

/// A draggable line between two parts, over it: invisible at rest,
/// `sash.hoverBorder` while hovered or dragged. Its cursor says which ways it can go (`.monaco-sash.minimum`,
/// `.maximum`), and stays while dragged past where it stops; a double click
/// resets what it sizes.
class WorkbenchSash extends StatefulWidget {
  const WorkbenchSash({
    super.key,
    required this.onStart,
    required this.onDrag,
    required this.onReset,
    this.onEnd,
    this.axis = Axis.horizontal,
    this.canMoveBack = true,
    this.canMoveForward = true,
  });

  final VoidCallback onStart;

  /// How far the pointer is from where the drag began, along [axis].
  final ValueChanged<double> onDrag;
  final VoidCallback onReset;
  final VoidCallback? onEnd;

  /// Which way it moves: between columns, or (vertical) between rows.
  final Axis axis;

  /// Whether it can go left (or up), and right (or down).
  final bool canMoveBack;
  final bool canMoveForward;

  MouseCursor get cursor => switch ((axis, canMoveBack, canMoveForward)) {
    (_, false, false) => SystemMouseCursors.basic,
    (Axis.horizontal, true, true) => SystemMouseCursors.resizeColumn,
    (Axis.horizontal, true, false) => SystemMouseCursors.resizeLeft,
    (Axis.horizontal, false, true) => SystemMouseCursors.resizeRight,
    (Axis.vertical, true, true) => SystemMouseCursors.resizeRow,
    (Axis.vertical, true, false) => SystemMouseCursors.resizeUp,
    (Axis.vertical, false, true) => SystemMouseCursors.resizeDown,
  };

  @override
  State<WorkbenchSash> createState() => _WorkbenchSashState();
}

class _WorkbenchSashState extends State<WorkbenchSash> {
  bool _hover = false;
  bool _dragging = false;
  double _start = 0;

  /// Over the window while dragging, with the sash's cursor: the pointer
  /// leaves the sash where it stops, and the cursor goes with it rather
  /// than turn into what it is over (VS Code's drag shield).
  OverlayEntry? _shield;

  @override
  void didUpdateWidget(WorkbenchSash oldWidget) {
    super.didUpdateWidget(oldWidget);
    // After this frame's build: the shield is the overlay's, not below us.
    if (_shield != null && widget.cursor != oldWidget.cursor) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _shield?.markNeedsBuild(),
      );
    }
  }

  @override
  void dispose() {
    _removeShield();
    super.dispose();
  }

  double _along(Offset position) =>
      widget.axis == Axis.horizontal ? position.dx : position.dy;

  void _begin(DragStartDetails details) {
    _start = _along(details.globalPosition);
    widget.onStart();
    setState(() => _dragging = true);
    if (Overlay.maybeOf(context) case final overlay?) {
      _shield = OverlayEntry(
        builder: (context) => MouseRegion(cursor: widget.cursor, opaque: true),
      );
      overlay.insert(_shield!);
    }
  }

  void _end() {
    _removeShield();
    setState(() => _dragging = false);
    widget.onEnd?.call();
  }

  void _removeShield() {
    _shield
      ?..remove()
      ..dispose();
    _shield = null;
  }

  @override
  Widget build(BuildContext context) {
    final active = _hover || _dragging;
    final horizontal = widget.axis == Axis.horizontal;
    void update(DragUpdateDetails details) =>
        widget.onDrag(_along(details.globalPosition) - _start);
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: horizontal ? _begin : null,
        onHorizontalDragUpdate: horizontal ? update : null,
        onHorizontalDragEnd: horizontal ? (_) => _end() : null,
        onHorizontalDragCancel: horizontal ? _end : null,
        onVerticalDragStart: horizontal ? null : _begin,
        onVerticalDragUpdate: horizontal ? null : update,
        onVerticalDragEnd: horizontal ? null : (_) => _end(),
        onVerticalDragCancel: horizontal ? null : _end,
        onDoubleTap: widget.onReset,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: horizontal ? WorkbenchStyle.sashWidth : null,
          height: horizontal ? null : WorkbenchStyle.sashWidth,
          color: active ? IdeModernUI.sashHover : const Color(0x00000000),
        ),
      ),
    );
  }
}

/// An activity bar item: a 24px codicon in a 36px square; the active and
/// the hovered item sit on a rounded 32px box.
