import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';

/// A clock for what moves in steps (a loader's frames, a spinner's turns):
/// it tells its listeners at each [step], and only then, where an
/// [AnimationController] would ask for a frame at every vsync (120 a second
/// and more) to show the same step again.
///
/// Its steps fall on [frame]s of one clock the app shares, whatever their
/// length: all that moves so changes in the same frames, at most 30 a
/// second. A frame draws the whole window again, however little of it
/// changed; loaders each on their own step (an agent's, a subagent's, the
/// shimmer's) would add theirs up to near every vsync.
class StepClock extends ChangeNotifier {
  StepClock(this._step);

  /// What every step waits for the next of: a 30th of a second.
  static const frame = Duration(microseconds: 33333);

  Duration _step;
  Timer? _timer;
  int _ticks = 0;

  /// When the timer set is due, in microseconds of [clock].
  int _due = 0;
  bool _disposed = false;

  Duration get step => _step;
  set step(Duration value) {
    if (value == _step) return;
    _step = value;
    _ticks = _now ~/ value.inMicroseconds;
    if (isRunning) {
      _timer!.cancel();
      _due = 0;
      _schedule();
    }
  }

  bool get isRunning => _timer != null;

  /// The steps of the shared clock gone, as last told.
  int get ticks => _ticks;

  /// The time on the shared clock, to the step last told.
  Duration get time => _step * _ticks;

  /// Runs where [context]'s tickers are on and motion is not turned down;
  /// whether it is still (motion turned down). For a state's
  /// didChangeDependencies.
  bool keepTo(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    if (!still && TickerMode.valuesOf(context).enabled) {
      start();
    } else {
      stop();
    }
    return still;
  }

  void start() {
    if (isRunning || _disposed) return;
    _ticks = _now ~/ _step.inMicroseconds;
    _due = 0;
    _schedule();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  // [clock]'s, which tests make up as they pump.
  static int get _now => clock.now().microsecondsSinceEpoch;

  void _schedule() {
    final step = _step.inMicroseconds;
    final frame = StepClock.frame.inMicroseconds;
    final now = _now;
    // From the step last told while that is still to come: a timer a little
    // early sets the next step, not the same one again.
    final next = (math.max(now, _due) ~/ step + 1) * step;
    final due = _due = (next + frame - 1) ~/ frame * frame;
    _timer = Timer(Duration(microseconds: due - now), () {
      // A step on at least; a late timer's steps as far as they have come.
      _ticks = math.max(_ticks + 1, math.max(_now, due) ~/ step);
      _schedule();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
