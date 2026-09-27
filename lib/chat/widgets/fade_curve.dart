import 'package:flutter/animation.dart';

/// Samples of a soft fade for a gradient mask: `(t, opacity)` from fully
/// hidden at `t == 0` to fully shown at `t == 1`, eased at both ends so the
/// fade has no visible start, end or kink (a linear or few-stop gradient
/// shows its stops as bands).
Iterable<(double, double)> easedFade({int samples = 8}) sync* {
  for (var i = 0; i <= samples; i++) {
    final t = i / samples;
    yield (t, Curves.easeInOut.transform(t));
  }
}
