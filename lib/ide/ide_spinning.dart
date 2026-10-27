import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../base/step_clock.dart';

/// A codicon turning as `codicon-modifier-spin` turns one: once in 1.5s;
/// still where motion is turned down.
///
/// Deviation: upstream's turns in 30 steps; this one a step each of
/// [StepClock.frame]s, which 30 steps of 50ms would not fall on evenly.
class IdeSpinning extends StatefulWidget {
  const IdeSpinning(this.child, {super.key});

  final Widget child;

  /// Once round.
  static const turn = Duration(milliseconds: 1500);

  @override
  State<IdeSpinning> createState() => _IdeSpinningState();
}

class _IdeSpinningState extends State<IdeSpinning> {
  final StepClock _clock = StepClock(StepClock.frame);
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = _clock.keepTo(context);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _clock,
    builder: (context, child) => Transform.rotate(
      angle: _still
          ? 0
          : _clock.time.inMicroseconds %
                IdeSpinning.turn.inMicroseconds /
                IdeSpinning.turn.inMicroseconds *
                2 *
                math.pi,
      child: child,
    ),
    child: widget.child,
  );
}
