import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A mouse wheel's notch moving a view by [distance] in [duration], eased
/// out (`1 - (1 - x)³`, as editors scroll smoothly): fastest at once, a
/// third of the way in 17 ms (a frame at 60 a second), and slowing to rest.
/// Not eased in, which reads as the view lagging behind the wheel.
///
/// Each frame moves the view on by what the curve went since the last
/// ([step]), not to a place set as it began: what else moves the view
/// meanwhile stays moved, not undone in the next frame. (A list moves
/// itself as it lays out a row it took for taller or shorter, to keep what
/// shows where it was.)
class WheelGlide {
  /// Taken up as a notch comes, between frames: timed from the frame shown
  /// last, [frame] long.
  WheelGlide(this.distance, {required this.frame})
    : _shownAt = SchedulerBinding.instance.currentSystemFrameTimeStamp;

  /// The glide a notch's [delta] sets a view at [at] going: on from where
  /// [going], the last notch's, was taking it (adding to what that had
  /// left), kept between [min] and [max]. Null where that is where the view
  /// is (back where it was going from, or still at an end).
  static WheelGlide? next(
    WheelGlide? going, {
    required double at,
    required double delta,
    required double min,
    required double max,
    required Duration frame,
  }) {
    final distance = (at + (going?.left ?? 0) + delta).clamp(min, max) - at;
    if (distance.abs() < precisionErrorTolerance) return null;
    return WheelGlide(distance, frame: frame);
  }

  static const duration = Duration(milliseconds: 120);

  /// Whether a wheel's [delta] is a notch to glide: not one of the small
  /// steps a wheel that scrolls smoothly sends (its driver's, a free
  /// spinning one's, precise deltas the system gives as they come), as
  /// smooth already as they go, which a glide each only held back (55ms
  /// behind, tool/perf `follow.*`). A notch is a line: 40px on macOS.
  static bool glides(double delta) => delta.abs() >= 32;

  final double distance;

  /// A frame of the display.
  final Duration frame;

  /// The frame shown as it was taken up, and when it is timed from: that
  /// frame, or one [frame] before the first it moves the view in, if that
  /// was long ago. So the frame after the notch moves the view already,
  /// and a notch taken up mid-way never holds it still for a frame.
  final Duration _shownAt;
  Duration? _startedAt;

  /// How far it has moved the view.
  double _moved = 0;

  /// How far through its time it is, 0 to 1.
  double _x = 0;

  /// How far it is yet to move the view.
  double get left => distance - _moved;

  /// Whether it has moved the view all the way.
  bool get done => _x >= 1;

  /// Pixels a second, now.
  double get velocity {
    if (done) return 0;
    final slope = 3 * (1 - _x) * (1 - _x);
    return distance * slope / (duration.inMicroseconds / 1e6);
  }

  static double _ease(double x) => 1 - (1 - x) * (1 - x) * (1 - x);

  /// How far to move the view in the frame being shown.
  double step() {
    final now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    final started = _startedAt ??= now - frame > _shownAt
        ? now - frame
        : _shownAt;
    _x = ((now - started).inMicroseconds / duration.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    final target = distance * _ease(_x);
    if ((distance - target).abs() < 0.5) {
      _x = 1.0;
      final step = distance - _moved;
      _moved = distance;
      return step;
    }
    final step = target - _moved;
    _moved += step;
    return step;
  }

  /// A frame of the display [context] is on (144 a second, say); of one at
  /// 60 a second where that is not known.
  static Duration frameOf(BuildContext? context) {
    final rate = context == null
        ? null
        : View.maybeOf(context)?.display.refreshRate;
    if (rate == null || rate < 24) return const Duration(microseconds: 16667);
    return Duration(microseconds: (1e6 / rate).round());
  }
}

/// Glides a view either way as a mouse wheel's notches come ([WheelGlide]),
/// on the frames of a ticker from `vsync`.
class WheelGlider {
  WheelGlider({required TickerProvider vsync, required this.move}) {
    _ticker = vsync.createTicker(_tick);
  }

  /// Moves the view by what a frame gives, and says which ways it went all
  /// of that (not stopped at an end), to go on.
  final ({bool x, bool y}) Function(Offset by) move;

  late final Ticker _ticker;
  WheelGlide? _x, _y;

  /// Whether it is moving the view.
  bool get gliding => _x != null || _y != null;

  /// Takes up a notch's [delta] for a view at [at] that goes from zero to
  /// [max] each way, on displays whose frames are [frame] long.
  void add(
    Offset delta, {
    required Offset at,
    required Offset max,
    required Duration frame,
  }) {
    // A smooth wheel's steps move the view as they come.
    if (!WheelGlide.glides(delta.dx) && !WheelGlide.glides(delta.dy)) {
      stop();
      move(delta);
      return;
    }
    if (delta.dx != 0) {
      _x = WheelGlide.next(
        _x,
        at: at.dx,
        delta: delta.dx,
        min: 0,
        max: max.dx,
        frame: frame,
      );
    }
    if (delta.dy != 0) {
      _y = WheelGlide.next(
        _y,
        at: at.dy,
        delta: delta.dy,
        min: 0,
        max: max.dy,
        frame: frame,
      );
    }
    if (!gliding) {
      stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  /// Leaves the view where it is.
  void stop() {
    _x = _y = null;
    if (_ticker.isActive) _ticker.stop();
  }

  void _tick(Duration _) {
    final x = _x, y = _y;
    final went = move(Offset(x?.step() ?? 0, y?.step() ?? 0));
    // Stopped, or another notch taken up, by what the move set off.
    if (!identical(x, _x) || !identical(y, _y)) return;
    if (x != null && (x.done || !went.x)) _x = null;
    if (y != null && (y.done || !went.y)) _y = null;
    if (!gliding) _ticker.stop();
  }

  void dispose() => _ticker.dispose();
}
