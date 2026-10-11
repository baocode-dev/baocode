import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Paint selection across rows. The first row fixes the value for the stroke;
/// fast pointer movements include crossed rows, and revisits never toggle back.
class IdeDragSelection extends StatefulWidget {
  const IdeDragSelection({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  State<IdeDragSelection> createState() => _IdeDragSelectionState();
}

class _IdeDragSelectionState extends State<IdeDragSelection>
    with SingleTickerProviderStateMixin {
  final _targets = <_IdeDragSelectTargetState>{};
  final _visited = <Object>{};
  int? _pointer;
  bool _value = false;
  Offset? _position;
  Duration? _lastTick;
  late final Ticker _ticker = createTicker(_scroll);

  void _begin(_IdeDragSelectTargetState target, PointerDownEvent event) {
    if (_pointer != null || event.buttons != kPrimaryButton) return;
    _pointer = event.pointer;
    _value = !target.widget.checked;
    _position = event.position;
    _visited.clear();
    _apply(target);
    _ticker.start();
  }

  void _apply(_IdeDragSelectTargetState target) {
    if (!target.mounted || !_visited.add(target.widget.id)) return;
    if (target.widget.checked != _value) target.widget.onChanged(_value);
  }

  Rect? get _bounds {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
  }

  void _paint(Offset from, Offset to) {
    final viewport = _bounds;
    if (viewport == null) return;
    for (final target in _targets.toList()) {
      final box = target.context.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final rect = (box.localToGlobal(Offset.zero) & box.size).intersect(
        viewport,
      );
      if (rect.isEmpty) continue;
      var enter = 0.0;
      var leave = 1.0;
      bool intersectsAxis(double start, double delta, double min, double max) {
        if (delta == 0) return start >= min && start <= max;
        final a = (min - start) / delta;
        final b = (max - start) / delta;
        enter = math.max(enter, math.min(a, b));
        leave = math.min(leave, math.max(a, b));
        return enter <= leave;
      }

      if (intersectsAxis(from.dx, to.dx - from.dx, rect.left, rect.right) &&
          intersectsAxis(from.dy, to.dy - from.dy, rect.top, rect.bottom)) {
        _apply(target);
      }
    }
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _paint(_position ?? event.position, event.position);
    _position = event.position;
  }

  void _finish(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _position = null;
    _lastTick = null;
    _visited.clear();
    _ticker.stop();
  }

  void _scroll(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    final position = _position;
    final bounds = _bounds;
    final controller = widget.controller;
    if (previous == null ||
        position == null ||
        bounds == null ||
        !controller.hasClients) {
      return;
    }
    const edge = 24.0;
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
    final next = (controller.offset + direction * seconds * 400).clamp(
      controller.position.minScrollExtent,
      controller.position.maxScrollExtent,
    );
    if (next == controller.offset) return;
    controller.jumpTo(next);
    // Lazy rows enter the stroke only once laid out, even if the mouse is still.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pointer != null) _paint(position, position);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DragSelectionScope(
    state: this,
    child: Listener(
      onPointerMove: _move,
      onPointerUp: _finish,
      onPointerCancel: _finish,
      child: widget.child,
    ),
  );
}

class _DragSelectionScope extends InheritedWidget {
  const _DragSelectionScope({required this.state, required super.child});
  final _IdeDragSelectionState state;
  @override
  bool updateShouldNotify(_DragSelectionScope oldWidget) =>
      state != oldWidget.state;
}

/// Wrap an entire selection row, with its visual checkbox ignoring pointers.
/// Accessibility activation remains a normal toggle on the checkbox itself.
class IdeDragSelectTarget extends StatefulWidget {
  const IdeDragSelectTarget({
    super.key,
    required this.id,
    required this.checked,
    required this.onChanged,
    required this.child,
  });
  final Object id;
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
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DragSelectionScope>()
        ?.state;
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
    behavior: HitTestBehavior.opaque,
    onPointerDown: (event) => _scope?._begin(this, event),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _scope == null ? () => widget.onChanged(!widget.checked) : () {},
      // A stroke starting on a selectable row paints rather than pans the list.
      onPanStart: _scope == null ? null : (_) {},
      onPanUpdate: _scope == null ? null : (_) {},
      child: widget.child,
    ),
  );
}
