import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Shows [child], and flips to a new one (another key, as with
/// [AnimatedSwitcher]) as a cube rolls up about its X axis: the one shown
/// tips back over its top edge as the next comes up from below.
///
/// Each one shown stays at least [dwell]: what comes meanwhile waits, the
/// latest only (the ones between it and the shown one are skipped). The
/// first is simply there, and so is every one with animations off.
class FlipSwitcher extends StatefulWidget {
  const FlipSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 280),
    this.dwell = const Duration(milliseconds: 600),
  });

  final Widget child;
  final Duration duration;
  final Duration dwell;

  @override
  State<FlipSwitcher> createState() => _FlipSwitcherState();
}

class _FlipSwitcherState extends State<FlipSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );

  late Widget _shown = widget.child;

  /// The one flipping away, while [_flip] runs.
  Widget? _leaving;

  /// The latest come while [_shown] has not stayed its [FlipSwitcher.dwell].
  Widget? _waiting;

  /// Running while [_shown] stays its [FlipSwitcher.dwell]; none for the
  /// first, which was simply there.
  Timer? _dwell;

  @override
  void didUpdateWidget(FlipSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    _flip.duration = widget.duration;
    final next = widget.child;
    if (Widget.canUpdate(next, _shown)) {
      // The same one, anew (or back before the one waiting showed).
      _shown = next;
      _waiting = null;
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _waiting = null;
      _leaving = null;
      _flip.value = 1;
      _shown = next;
    } else if (_dwell != null) {
      _waiting = next;
    } else {
      _show(next);
    }
  }

  void _rested() {
    _dwell = null;
    final next = _waiting;
    _waiting = null;
    if (next != null && mounted) setState(() => _show(next));
  }

  void _show(Widget next) {
    _leaving = _shown;
    _shown = next;
    _dwell = Timer(widget.dwell, _rested);
    _flip.forward(from: 0).whenCompleteOrCancel(() {
      if (mounted) setState(() => _leaving = null);
    });
  }

  @override
  void dispose() {
    _dwell?.cancel();
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leaving = _leaving;
    if (leaving == null) return _shown;
    return ClipRect(
      child: AnimatedBuilder(
        animation: _flip,
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(_flip.value);
          // As wide as it is let be, not as the one leaving: the one
          // coming may be longer.
          return Stack(
            fit: StackFit.passthrough,
            children: [
              // Under the one coming: laid out alone, it sizes the stack.
              _Tipped(t: t, leaving: true, child: leaving),
              Positioned.fill(
                child: _Tipped(t: t, leaving: false, child: _shown),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// [child] [t] of the way through a flip: tipping back over its top edge
/// ([leaving]), or up from below.
class _Tipped extends StatelessWidget {
  const _Tipped({required this.t, required this.leaving, required this.child});

  final double t;
  final bool leaving;
  final Widget child;

  /// How much nearer edges grow than farther ones: enough for a line of
  /// text to read as turning, not shrinking.
  static const _perspective = 0.004;

  @override
  Widget build(BuildContext context) {
    // Turned 0 to 90° about its bottom edge as it leaves, so its top goes
    // back; -90 to 0° about its top edge as it comes, its bottom from back.
    final turn = leaving ? t : t - 1;
    return FractionalTranslation(
      translation: Offset(0, -turn),
      child: Transform(
        alignment: leaving ? Alignment.bottomCenter : Alignment.topCenter,
        transform: Matrix4.identity()
          ..setEntry(3, 2, _perspective)
          ..rotateX(-turn * math.pi / 2),
        child: Opacity(
          opacity: (leaving ? 1 - t : t).clamp(0.0, 1.0),
          child: child,
        ),
      ),
    );
  }
}
