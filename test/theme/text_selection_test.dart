import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/theme/app_theme.dart';

/// [top] composited over [under].
Color over(Color top, Color under) => Color.from(
  alpha: 1,
  red: top.r * top.a + under.r * (1 - top.a),
  green: top.g * top.a + under.g * (1 - top.a),
  blue: top.b * top.a + under.b * (1 - top.a),
);

double distance(Color a, Color b) => [
  a.r - b.r,
  a.g - b.g,
  a.b - b.b,
].map((d) => d.abs()).reduce((a, b) => a > b ? a : b);

void main() {
  const background = Color(0xFF1F1F1F);

  test('a see-through selection is kept', () {
    const selection = Color(0x400069CC);
    expect(seeThroughSelection(selection, background), selection);
  });

  test('an opaque one is made see-through, looking as it did', () {
    // The default dark theme's, and 2026 Dark's, nearly opaque.
    for (final selection in const [Color(0xFF264F78), Color(0xDD276782)]) {
      final seeThrough = seeThroughSelection(selection, background);
      expect(seeThrough.a, closeTo(0.3, 0.01));
      expect(
        distance(over(seeThrough, background), over(selection, background)),
        lessThan(0.1),
      );
    }
  });

  test('text under it keeps most of its color', () {
    // Opaque and far from the text's color.
    const text = Color(0xFFFFFFFF);
    final seeThrough = seeThroughSelection(
      const Color(0xFF0000FF),
      const Color(0xFF000000),
    );
    expect(distance(over(seeThrough, text), text), lessThanOrEqualTo(0.31));
  });
}
