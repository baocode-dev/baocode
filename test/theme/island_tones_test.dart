import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/theme/island_tones.dart';

/// [color]'s hue, in degrees, and its chroma (HSV's).
(double, double) _hue(Color color) {
  final hsv = HSVColor.fromColor(color);
  return (hsv.hue, hsv.saturation * hsv.value);
}

void main() {
  test('a gray lifted stays a gray, as light as asked', () {
    final lifted = IslandTones.shift(const Color(0xFF181818), 0.08);
    expect(lifted.r, closeTo(lifted.g, 1e-6));
    expect(lifted.g, closeTo(lifted.b, 1e-6));
    expect(
      IslandTones.lightness(lifted) -
          IslandTones.lightness(const Color(0xFF181818)),
      closeTo(0.08, 0.002),
    );
  });

  test('a tinted color lifted keeps its hue and its chroma, not washed '
      'out towards white', () {
    // Bao Dark's warm selection on a card.
    const warm = Color(0xFF41382B);
    final lifted = IslandTones.shift(warm, 0.08);
    final (hue, chroma) = _hue(warm);
    final (liftedHue, liftedChroma) = _hue(lifted);
    expect(
      IslandTones.lightness(lifted),
      greaterThan(IslandTones.lightness(warm)),
    );
    expect((liftedHue - hue).abs(), lessThan(4));
    expect(liftedChroma, greaterThan(chroma * 0.9));
    // Mixed with white as far, it would have lost a good part of it.
    final mixed = Color.lerp(warm, Colors.white, 0.12)!;
    expect(liftedChroma, greaterThan(_hue(mixed).$2));
    expect(math.max(lifted.r, lifted.g), lifted.r);
  });
}
