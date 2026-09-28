import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Wheel scrolling of a scroll view inside another, as browsers do it: a
/// wheel gesture keeps to the scroll view it started scrolling.
///
/// - Started over the inner view, while it can move that way: it scrolls
///   the inner view only, and stops at its end rather than go on to the
///   outer one.
/// - Started elsewhere (or with the inner view already at that end): it
///   scrolls the outer view, even once the pointer is over the inner one.
///
/// A gesture ends after [gap] without wheel events. Goes inside the inner
/// scroll view, around its content. (A trackpad pan is a drag, which the
/// inner view keeps to itself already.)
class WheelLatch extends StatefulWidget {
  const WheelLatch({super.key, required this.child});

  final Widget child;

  static const gap = Duration(milliseconds: 300);

  @override
  State<WheelLatch> createState() => _WheelLatchState();
}

class _WheelLatchState extends State<WheelLatch> {
  // One gesture at a time, app wide: the last wheel event, and the scroll
  // view that has the gesture (null: none of these inner ones).
  static Duration? _lastWheel;
  static Object? _latched;
  static Duration? _latchedAt;
  static bool _watching = false;

  /// Sees every wheel event, after the views under the pointer have: a
  /// gesture started anywhere else belongs to no inner view.
  static void _watch(PointerEvent event) {
    if (event is! PointerScrollEvent) return;
    final last = _lastWheel;
    final starts = last == null || event.timeStamp - last >= WheelLatch.gap;
    if (starts && _latchedAt != event.timeStamp) _latched = null;
    _lastWheel = event.timeStamp;
  }

  @override
  void initState() {
    super.initState();
    if (!_watching) {
      _watching = true;
      GestureBinding.instance.pointerRouter.addGlobalRoute(_watch);
    }
  }

  void _handleSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final inner = Scrollable.maybeOf(context);
    if (inner == null) return;
    final delta = event.scrollDelta.dy;
    final last = _lastWheel;
    if (last == null || event.timeStamp - last >= WheelLatch.gap) {
      final position = inner.position;
      final moves = delta > 0
          ? position.pixels < position.maxScrollExtent
          : delta < 0 && position.pixels > position.minScrollExtent;
      _latched = moves ? this : null;
      _latchedAt = event.timeStamp;
    }
    if (_latched == this) {
      // Taken first (the inner view's own handling passes at its ends).
      GestureBinding.instance.pointerSignalResolver.register(event, (event) {
        final position = inner.position;
        final target = (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if (target != position.pixels) position.pointerScroll(delta);
      });
      return;
    }
    // Another view's gesture: not the inner view's, even where it could
    // move. The outer view takes it as if the inner one were not there.
    final outer = Scrollable.maybeOf(inner.context);
    if (outer == null) return;
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (event) => outer.position.pointerScroll(delta),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Anywhere over it, text or not.
      behavior: HitTestBehavior.translucent,
      onPointerSignal: _handleSignal,
      child: widget.child,
    );
  }
}
