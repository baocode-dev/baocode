import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A checkbox-painting gesture shared by multi-select lists. The first box
/// determines the value for the whole stroke; revisiting never toggles it back.
class IdeDragSelection extends StatefulWidget {
  const IdeDragSelection({
    super.key,
    required this.child,
    this.scrollController,
    this.onStart,
    this.onEnd,
  });

  final Widget child;
  final ScrollController? scrollController;
  final VoidCallback? onStart;
  final VoidCallback? onEnd;

  static _IdeDragSelectionState? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DragSelectionScope>()?.state;

  @override
  State<IdeDragSelection> createState() => _IdeDragSelectionState();
}

class _IdeDragSelectionState extends State<IdeDragSelection>
    with SingleTickerProviderStateMixin {
  final _targets = <_IdeDragSelectTargetState>{};
  final _visited = <_IdeDragSelectTargetState>{};
  int? _pointer;
  bool _value = false;
  Offset? _position;
  Duration? _lastTick;
  late final Ticker _ticker = createTicker(_scroll);

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
  }

  void _begin(_IdeDragSelectTargetState target, PointerDownEvent event) {
    if (_pointer != null || event.buttons != kPrimaryButton) return;
    _pointer = event.pointer;
    _value = !target.widget.checked;
    _position = event.position;
    _visited.clear();
    widget.onStart?.call();
    _apply(target);
    if (widget.scrollController != null) _ticker.start();
  }

  void _apply(_IdeDragSelectTargetState target) {
    if (!target.mounted || !_visited.add(target)) return;
    if (target.widget.checked != _value) target.widget.onChanged(_value);
  }

  Rect? _bounds() {
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return null;
    return render.localToGlobal(Offset.zero) & render.size;
  }

  // Test the whole segment, not just the latest pointer position: a fast mouse
  // movement may cross several checkbox rows between two input events.
  void _paint(Offset from, Offset to) {
    final viewport = _bounds();
    if (viewport == null) return;
    for (final target in _targets.toList()) {
      final render = target.context.findRenderObject();
      if (render is! RenderBox || !render.hasSize || !render.attached) continue;
      final rect = (render.localToGlobal(Offset.zero) & render.size)
          .inflate(5)
          .intersect(viewport);
      if (rect.isEmpty) continue;
      final dx = to.dx - from.dx;
      final dy = to.dy - from.dy;
      var enter = 0.0;
      var leave = 1.0;
      bool axis(double start, double delta, double min, double max) {
        if (delta == 0) return start >= min && start <= max;
        var a = (min - start) / delta;
        var b = (max - start) / delta;
        if (a > b) {
          final swap = a;
          a = b;
          b = swap;
        }
        enter = math.max(enter, a);
        leave = math.min(leave, b);
        return enter <= leave;
      }

      if (axis(from.dx, dx, rect.left, rect.right) &&
          axis(from.dy, dy, rect.top, rect.bottom)) {
        _apply(target);
      }
    }
  }

  void _route(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      _paint(_position ?? event.position, event.position);
      _position = event.position;
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _finish();
    }
  }

  void _scroll(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    final controller = widget.scrollController;
    final position = _position;
    final bounds = _bounds();
    if (previous == null ||
        controller == null ||
        !controller.hasClients ||
        position == null ||
        bounds == null) {
      return;
    }
    const edge = 28.0;
    final direction = position.dy < bounds.top + edge
        ? -1.0
        : position.dy > bounds.bottom - edge
        ? 1.0
        : 0.0;
    if (direction == 0 ||
        position.dx < bounds.left ||
        position.dx > bounds.right) {
      return;
    }
    final seconds = math.min(
      (elapsed - previous).inMicroseconds / 1000000,
      .05,
    );
    final next = (controller.offset + direction * seconds * 450).clamp(
      controller.position.minScrollExtent,
      controller.position.maxScrollExtent,
    );
    if (next == controller.offset) return;
    controller.jumpTo(next);
    // Newly built lazy rows participate after their layout, while stationary.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pointer != null) _paint(position, position);
    });
  }

  void _finish() {
    if (_pointer == null) return;
    _pointer = null;
    _position = null;
    _lastTick = null;
    _ticker.stop();
    _visited.clear();
    widget.onEnd?.call();
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_route);
    _ticker.dispose();
    _targets.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _DragSelectionScope(state: this, child: widget.child);
}

class _DragSelectionScope extends InheritedWidget {
  const _DragSelectionScope({required this.state, required super.child});
  final _IdeDragSelectionState state;
  @override
  bool updateShouldNotify(_DragSelectionScope oldWidget) =>
      state != oldWidget.state;
}

/// Wrap only selection checkboxes, never a table's select-all header. Without a
/// surrounding scope it behaves like an ordinary checkbox tap.
class IdeDragSelectTarget extends StatefulWidget {
  const IdeDragSelectTarget({
    super.key,
    required this.checked,
    required this.onChanged,
    required this.child,
  });
  final bool checked;
  final ValueChanged<bool> onChanged;
  final Widget child;
  @override
  State<IdeDragSelectTarget> createState() => _IdeDragSelectTargetState();
}

class _IdeDragSelectTargetState extends State<IdeDragSelectTarget> {
  _IdeDragSelectionState? _scope;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = IdeDragSelection._of(context);
    if (scope == _scope) return;
    _scope?._targets.remove(this);
    _scope = scope;
    _scope?._targets.add(this);
  }

  @override
  void dispose() {
    _scope?._targets.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _scope == null
        ? null
        : (event) => _scope!._begin(this, event),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _scope == null ? () => widget.onChanged(!widget.checked) : () {},
      // Claim drags beginning on a checkbox so the list does not pan instead.
      onPanStart: _scope == null ? null : (_) {},
      onPanUpdate: _scope == null ? null : (_) {},
      child: widget.child,
    ),
  );
}
