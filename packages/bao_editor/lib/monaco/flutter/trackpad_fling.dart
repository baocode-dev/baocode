import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A trackpad's scrolling of a view that keeps its own offsets (not a
/// [Scrollable]'s), going on as the fingers lift as a list's would: by the
/// fling the [ScrollPhysics] of the [ScrollConfiguration] there give, from
/// the speed its velocity tracker takes the fingers at, a flick while it
/// goes adding to it. The system's own momentum never comes: Flutter's
/// embedders leave it for the framework to make.
///
/// The fingers' moves are the view's to follow as they come; this only
/// tracks them ([start], [update]) to fling it after ([end]).
class TrackpadFling {
  TrackpadFling({
    required TickerProvider vsync,
    required this.move,
    this.onDone,
  }) {
    _ticker = vsync.createTicker(_tick);
  }

  /// Moves the view by what a frame gives, and says which ways it went all
  /// of that (not stopped at an end), to go on.
  final ({bool x, bool y}) Function(Offset by) move;
  final VoidCallback? onDone;

  late final Ticker _ticker;
  VelocityTracker? _tracker;

  /// What a fling stopped by the fingers carries to the next, per axis
  /// ([ScrollPhysics.carriedMomentum]).
  Offset _carried = Offset.zero;
  Duration? _movedAt;
  _Fling? _x, _y;

  /// Whether it is moving the view.
  bool get flinging => _x != null || _y != null;

  /// Fingers down: what it was flinging stops, its speed kept for the next
  /// fling to add to, as a list's.
  void start(BuildContext context, PointerPanZoomStartEvent event) {
    final going = Offset(_x?.velocity ?? 0, _y?.velocity ?? 0);
    stop();
    final configuration = ScrollConfiguration.of(context);
    final physics = configuration.getScrollPhysics(context);
    _carried = Offset(
      physics.carriedMomentum(going.dx),
      physics.carriedMomentum(going.dy),
    );
    _tracker = configuration.velocityTrackerBuilder(context)(event)
      ..addPosition(event.timeStamp, Offset.zero);
    _movedAt = event.timeStamp;
  }

  void update(PointerPanZoomUpdateEvent event) {
    final tracker = _tracker;
    if (tracker == null) return;
    tracker.addPosition(event.timeStamp, event.pan);
    // Held still a while, the speed carried is lost (`ScrollDragController`).
    if (event.panDelta != Offset.zero) {
      _movedAt = event.timeStamp;
    } else if (event.timeStamp - _movedAt! >
        ScrollDragController.momentumRetainStationaryDurationThreshold) {
      _carried = Offset.zero;
    }
  }

  /// Fingers lifted from a view at [at] that goes from zero to [max] each
  /// way, [viewport] of it showing: it goes on if they flicked it.
  void end(
    BuildContext context, {
    required Offset at,
    required Offset max,
    required Size viewport,
  }) {
    final tracker = _tracker;
    _tracker = null;
    if (tracker == null) return;
    final estimate = tracker.getVelocityEstimate();
    if (estimate == null) return;
    final physics = ScrollConfiguration.of(context).getScrollPhysics(context);
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    // As a drag recognizer takes a fling, then a scroll view's drag ends it.
    double velocity(double fingers, double moved, double carried) {
      if (fingers.abs() <= physics.minFlingVelocity ||
          moved.abs() <= physics.minFlingDistance) {
        return 0;
      }
      final limit = physics.maxFlingVelocity;
      // Fingers moving down reveal what is above: the offset goes down.
      final velocity = -fingers.clamp(-limit, limit);
      final adds =
          velocity.sign == carried.sign &&
          velocity.abs() >
              carried.abs() *
                  ScrollDragController.momentumRetainVelocityThresholdFactor;
      return adds ? velocity + carried : velocity;
    }

    _Fling? fling(
      double velocity,
      double at,
      double max,
      double viewport,
      AxisDirection direction,
    ) {
      if (velocity == 0 || max <= 0) return null;
      final simulation = physics.createBallisticSimulation(
        FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: max,
          pixels: at,
          viewportDimension: viewport,
          axisDirection: direction,
          devicePixelRatio: ratio,
        ),
        velocity,
      );
      return simulation == null ? null : _Fling(simulation);
    }

    final speed = estimate.pixelsPerSecond;
    final moved = estimate.offset;
    _x = fling(
      velocity(speed.dx, moved.dx, _carried.dx),
      at.dx,
      max.dx,
      viewport.width,
      AxisDirection.right,
    );
    _y = fling(
      velocity(speed.dy, moved.dy, _carried.dy),
      at.dy,
      max.dy,
      viewport.height,
      AxisDirection.down,
    );
    _carried = Offset.zero;
    if (flinging) _ticker.start();
  }

  /// Leaves the view where it is.
  void stop() {
    _x = _y = null;
    if (_ticker.isActive) _ticker.stop();
  }

  void _tick(Duration elapsed) {
    final time = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final x = _x, y = _y;
    final went = move(Offset(x?.step(time) ?? 0, y?.step(time) ?? 0));
    // Stopped, or flung anew, by what the move set off.
    if (!identical(x, _x) || !identical(y, _y)) return;
    if (x != null && (x.simulation.isDone(time) || !went.x)) _x = null;
    if (y != null && (y.simulation.isDone(time) || !went.y)) _y = null;
    if (!flinging) {
      _ticker.stop();
      onDone?.call();
    }
  }

  void dispose() => _ticker.dispose();
}

/// A fling along one axis: each frame moves the view on by what the
/// simulation went since the last, not to a place set as it began, so what
/// else moves the view meanwhile stays moved (as a wheel's glide).
class _Fling {
  _Fling(this.simulation) : _at = simulation.x(0);

  final Simulation simulation;
  double _at;
  double _time = 0;

  /// Pixels a second, now.
  double get velocity => simulation.dx(_time);

  double step(double time) {
    _time = time;
    final to = simulation.x(time);
    final by = to - _at;
    _at = to;
    return by;
  }
}
