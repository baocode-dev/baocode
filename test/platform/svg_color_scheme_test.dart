// An SVG that picks its light or dark drawing with a style, as the
// JetBrains icon theme's "Auto" icons do.

import 'package:baocode/platform/svg_color_scheme.dart';
import 'package:flutter_test/flutter_test.dart';

const _auto =
    '<svg width="16" height="16" xmlns="http://www.w3.org/2000/svg">'
    '<style>.dark { display: none; } .light { display: block; } '
    '@media (prefers-color-scheme: dark) { .dark { display: block; } '
    '.light { display: none; } }</style>'
    '<g class="light"><path d="M1 1"/></g>'
    '<g class="dark"><path d="M2 2"/></g>'
    '</svg>';

void main() {
  test('hides the other scheme\'s drawing', () {
    expect(
      svgForColorScheme(_auto, dark: true),
      allOf(
        contains('<g class="light" display="none">'),
        contains('<g class="dark">'),
      ),
    );
    expect(
      svgForColorScheme(_auto, dark: false),
      allOf(
        contains('<g class="light">'),
        contains('<g class="dark" display="none">'),
      ),
    );
  });

  test('a light media query, several classes, self-closing tags and '
      'comments', () {
    const svg =
        '<svg><style>/* .a { display: none } */ .b, .c { fill: red; '
        'display: none } @media (prefers-color-scheme: light) '
        '{ .a { display: none } }</style>'
        "<path class='x a' d='M1 1'/><rect class=\"c\"/><circle class=\"y\"/>"
        '</svg>';
    final dark = svgForColorScheme(svg, dark: true);
    expect(dark, contains("<path class='x a' d='M1 1'/>"));
    expect(dark, contains('<rect class="c" display="none"/>'));
    expect(dark, contains('<circle class="y"/>'));
    expect(
      svgForColorScheme(svg, dark: false),
      contains("<path class='x a' d='M1 1' display=\"none\"/>"),
    );
  });

  test('an SVG whose style does not depend on the scheme is left alone', () {
    const svg = '<svg><style>.a { display: none }</style><g class="a"/></svg>';
    expect(svgForColorScheme(svg, dark: true), same(svg));
  });
}
