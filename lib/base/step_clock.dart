import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A clock for what moves in steps (a loader's frames, a spinner's turns):
/// it tells its listeners at each [step], and only then, where an
/// [AnimationController] would ask for a frame at every vsync (120 a second
/// and more) to show the same step again. Its steps fall on those of one
/// clock the app shares: loaders on the same step change in the same frame.
class StepClock extends ChangeNotifier {
  StepClock(this._step);

  static final Stopwatch _epoch = Stopwatch()..start();

  Duration _step;
  Timer? _timer;
  int _ticks = 0;
  bool _disposed = false;

  Duration get step => _step;
  set step(Duration value) {
    if (value == _step) return;
    _step = value;
    _ticks = _now();
    if (isRunning) {
      _timer!.cancel();
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
    _ticks = _now();
    _schedule();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  // The steps gone, to the nearest: a timer a little early or late tells
  // the step it was set for.
  int _now() =>
      (_epoch.elapsedMicroseconds + _step.inMicroseconds ~/ 2) ~/
      _step.inMicroseconds;

  void _schedule() {
    final step = _step.inMicroseconds;
    final wait = step - _epoch.elapsedMicroseconds % step;
    // Too near this step, the next one.
    _timer = Timer(
      Duration(microseconds: wait < step ~/ 4 ? wait + step : wait),
      () {
        // A step on at least: where time is made up (tests), it is still.
        _ticks = math.max(_ticks + 1, _now());
        _schedule();
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
