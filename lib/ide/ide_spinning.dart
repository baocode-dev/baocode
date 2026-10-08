import 'dart:async';

import 'package:flutter/widgets.dart';

/// A codicon turning as `codicon-modifier-spin` turns one: once in 1.5s, in
/// 30 steps; still where motion is turned down.
class IdeSpinning extends StatefulWidget {
  const IdeSpinning(this.child, {super.key});

  final Widget child;

  @override
  State<IdeSpinning> createState() => _IdeSpinningState();
}

class _IdeSpinningState extends State<IdeSpinning>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turns = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _turns.stop();
    } else if (!_turns.isAnimating) {
      unawaited(_turns.repeat());
    }
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _turns.drive(CurveTween(curve: const _Steps(30))),
    child: widget.child,
  );
}

/// CSS `steps(n)`: jumps at the end of each of [steps] intervals.
class _Steps extends Curve {
  const _Steps(this.steps);

  final int steps;

  @override
  double transformInternal(double t) => (t * steps).floor() / steps;
}
