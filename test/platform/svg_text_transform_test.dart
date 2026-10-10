import 'package:baocode/platform/svg_text_transform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

/// A shields.io badge's text: drawn at a tenth of its font size.
const _badge =
    '<svg xmlns="http://www.w3.org/2000/svg" width="152.5" height="28">'
    '<g fill="#fff" text-anchor="middle" font-size="100">'
    '<text transform="scale(.1)" x="425" y="175" textLength="610">OPEN VSX'
    '</text><text x="1187.5" y="175" font-weight="bold">V1.7.8</text></g>'
    '</svg>';

void main() {
  test('a scaled text keeps its transform, so its font is scaled too', () {
    // The compiler folds a scale into the position and drops it.
    final before = parseWithoutOptimizers(_badge, warningsAsErrors: false);
    expect(before.textPositions.first.x, 42.5);
    expect(before.textPositions.first.transform, isNull);

    final svg = svgWithTextTransforms(_badge);
    expect(
      svg,
      contains('<text transform="scale(.1) skewX(0.000001)" x="425"'),
    );
    expect(
      svg,
      contains(
        '<text x="1187.5" y="175" font-weight="bold" '
        'transform="skewX(0.000001)">',
      ),
    );
    final after = parseWithoutOptimizers(svg, warningsAsErrors: false);
    final position = after.textPositions.first;
    expect(position.x, 425);
    final transform = position.transform!;
    expect(transform.a, closeTo(.1, 1e-9));
    expect(transform.d, closeTo(.1, 1e-9));
    expect(transform.c, isNot(0));
    expect(transform.c, closeTo(0, 1e-6));
  });

  test('an SVG without text or transforms is itself', () {
    const shapes = '<svg><g transform="scale(2)"><rect width="1"/></g></svg>';
    expect(identical(svgWithTextTransforms(shapes), shapes), isTrue);
    const text = '<svg><text x="1" y="2">a</text></svg>';
    expect(identical(svgWithTextTransforms(text), text), isTrue);
  });
}
