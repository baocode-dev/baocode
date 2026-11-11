import 'dart:io';

import 'package:baocode/platform/svg_styles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';
import 'package:xml/xml.dart';

XmlElement _element(String svg, String id) =>
    XmlDocument.parse(svg).descendants
        .whereType<XmlElement>()
        .firstWhere((element) => element.getAttribute('id') == id);

String? _style(String svg, String id) =>
    _element(svg, id).getAttribute('style');

void main() {
  test('inlines the stylesheet of the SVG attached to issue 858', () {
    final svg = svgWithStyles(
      File('test/fixtures/svg/issue_858.svg').readAsStringSync(),
    );
    final elements = XmlDocument.parse(svg).descendants.whereType<XmlElement>();
    final button = elements.firstWhere(
      (element) => element.getAttribute('class') == 'button',
    );
    expect(button.getAttribute('style'), contains('fill:#fff'));
    expect(button.getAttribute('style'), contains('stroke:#cbd5e1'));
    final icon = elements.firstWhere(
      (element) => element.getAttribute('id') == 'chevron',
    );
    expect(icon.getAttribute('style'), contains('fill:none'));
    expect(icon.getAttribute('style'), contains('stroke:#64748b'));
    final text = elements.firstWhere((element) => element.name.local == 'text');
    expect(text.getAttribute('style'), contains('font-size:15px'));
    expect(text.getAttribute('style'), contains('fill:#1f2937'));
    final query = elements.firstWhere((element) => element.innerText == '查询');
    expect(query.getAttribute('style'), contains('fill:#fff'));
  });

  test(
    'specificity, source order and inline declarations follow the cascade',
    () {
      final svg = svgWithStyles('''
<svg xmlns="http://www.w3.org/2000/svg">
  <style>
    #a { fill: red; }
    rect.button { stroke: blue; }
    .button { fill: green; stroke: red; }
    rect { fill: black; }
    .button { stroke-width: 2; }
    .button { stroke-width: 3; }
  </style>
  <rect id="a" class="button other" fill="yellow"/>
  <rect id="b" class="button" style="fill:purple;opacity:.5"/>
</svg>''');
      expect(_style(svg, 'a'), contains('fill:#f00'));
      expect(_style(svg, 'a'), contains('stroke:#00f'));
      expect(_style(svg, 'a'), contains('stroke-width:3'));
      expect(_style(svg, 'b'), contains('fill:#800080'));
      expect(_style(svg, 'b'), contains('opacity:.5'));
    },
  );

  test('important declarations outrank normal inline styles', () {
    final svg = svgWithStyles('''
<svg><style>
  .button { fill: red !important; stroke: green !important; }
</style><rect id="a" class="button"
  style="fill:blue;stroke:purple !important"/></svg>''');
    expect(_style(svg, 'a'), contains('fill:#f00'));
    expect(_style(svg, 'a'), contains('stroke:#800080'));
    expect(_style(svg, 'a'), isNot(contains('!important')));
  });

  test(
    'supports lists, compound selectors, CDATA and multiple stylesheets',
    () {
      final svg = svgWithStyles('''
<svg><style><![CDATA[
  /* exported drawing */
  text, rect.button { fill: red; }
]]></style><style>.button { stroke: blue; }</style>
<rect id="a" class="button"/><text id="b">hello</text>
<rect id="c"/></svg>''');
      expect(_style(svg, 'a'), contains('fill:#f00'));
      expect(_style(svg, 'a'), contains('stroke:#00f'));
      expect(_style(svg, 'b'), contains('fill:#f00'));
      expect(_style(svg, 'c'), isNull);
    },
  );

  test(
    'does not apply conditional or unsupported selectors unconditionally',
    () {
      final svg = svgWithStyles('''
<svg><style>
  @media (prefers-color-scheme: dark) { .button { fill: red; } }
  g .button { stroke: blue; }
  .button:hover { opacity: 0; }
  .button { stroke-width: 2; }
</style><rect id="a" class="button"/></svg>''');
      expect(_style(svg, 'a'), 'stroke-width:2');
    },
  );

  test(
    'compiler paints stylesheet shapes and text like explicit attributes',
    () {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50">
<style>
  .button { fill: #fff; stroke: #cbd5e1; stroke-width: 1; }
  .icon { fill: none; stroke: #64748b; stroke-width: 1.7; }
  text { fill: #1f2937; font-size: 15px; }
</style>
<rect class="button" x="1" y="1" width="80" height="32"/>
<g class="icon"><path d="M5 5L10 10"/></g>
<text x="12" y="20">Button</text>
</svg>''';
      const explicit = '''
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50">
<rect fill="#fff" stroke="#cbd5e1" stroke-width="1"
  x="1" y="1" width="80" height="32"/>
<g fill="none" stroke="#64748b" stroke-width="1.7">
  <path d="M5 5L10 10"/>
</g>
<text fill="#1f2937" font-size="15px" x="12" y="20">Button</text>
</svg>''';
      final before = parseWithoutOptimizers(svg, warningsAsErrors: false);
      final after = parseWithoutOptimizers(
        svgWithStyles(svg),
        warningsAsErrors: false,
      );
      final expected = parseWithoutOptimizers(
        explicit,
        warningsAsErrors: false,
      );
      expect(before.paints, isNot(expected.paints));
      expect(after.paints, expected.paints);
      expect(after.text, expected.text);
    },
  );

  test('removes imports, executable CSS and external resources', () {
    final svg = svgWithStyles(r'''
<svg><style>
  @import url("https://attacker.example/import.css");
  @font-face { font-family: evil; src: url("https://attacker.example/font"); }
  .button {
    fill: url("javascript:alert(1)");
    stroke: url("https://attacker.example/tracking.svg#paint");
    opacity: expression(alert(1));
    behavior: url("https://attacker.example/payload.htc");
    -moz-binding: url("https://attacker.example/binding.xml");
    background-image: url("https://attacker.example/pixel");
    stroke-width: 2;
  }
</style><rect id="a" class="button"/></svg>''');
    expect(_style(svg, 'a'), 'stroke-width:2');
    expect(svg, isNot(contains('<style')));
    expect(svg, isNot(contains('attacker.example')));
    expect(svg, isNot(contains('alert')));
  });

  test('sanitizes inline styles without a stylesheet or matching rule', () {
    for (final prefix in ['', '<style>.other { fill: red; }</style>']) {
      final svg = svgWithStyles('''
<svg>$prefix<rect id="a" style="fill:url(data:image/svg+xml,evil);stroke:red;
  opacity:expression(alert(1));behavior:url(https://attacker.example/x)"/>
<rect id="b" style="fill:url(file:///etc/passwd)"/></svg>''');
      expect(_style(svg, 'a'), 'stroke:#f00');
      expect(_style(svg, 'b'), isNull);
      expect(svg, isNot(contains('attacker.example')));
      expect(svg, isNot(contains('passwd')));
    }
  });

  test('rejects escaped and entity-encoded malicious CSS', () {
    final svg = svgWithStyles(r'''
<svg><style>
  .button { fill: u\72l("https://attacker.example/x");
    opacity: e\78pression(alert(1)); stroke: blue; }
</style><rect id="a" class="button"
  style="fill:url(&quot;javascript:alert(1)&quot;)"/></svg>''');
    expect(_style(svg, 'a'), 'stroke:#00f');
    expect(svg, isNot(contains('alert')));
    expect(svg, isNot(contains('attacker.example')));
  });

  test('preserves local gradients, quoted font names and colors', () {
    final svg = svgWithStyles('''
<svg><style>
  .button { fill: url(#gradient); stroke: rgba(10,20,30,.5);
    font-family: "PingFang SC", "Microsoft YaHei", sans-serif; }
</style><defs><linearGradient id="gradient"/></defs>
<rect id="a" class="button"/></svg>''');
    expect(_style(svg, 'a'), contains('url('));
    expect(_style(svg, 'a'), contains('#gradient'));
    expect(_style(svg, 'a'), contains('stroke:'));
    expect(_style(svg, 'a'), contains('PingFang SC'));
  });

  test('rejects excessive stylesheet input before CSS parsing', () {
    final padding = List.filled(256 * 1024 + 1, ' ').join();
    expect(
      () => svgWithStyles('<svg><style>$padding</style></svg>'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'reason',
          contains('CSS input limit'),
        ),
      ),
    );
    expect(
      () => svgWithStyles('<svg style="$padding"/>'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects oversized styled SVGs and excessive element counts', () {
    final padding = List.filled(8 * 1024 * 1024, ' ').join();
    expect(
      () => svgWithStyles('<svg><style/>$padding</svg>'),
      throwsA(isA<FormatException>()),
    );
    final shapes = List.filled(20000, '<rect/>').join();
    expect(
      () => svgWithStyles('<svg><style/>$shapes</svg>'),
      throwsA(isA<FormatException>()),
    );
  });

  test('bounds selector expansion on small but expensive stylesheets', () {
    final rules = List.filled(500, '.a { fill: red; }').join();
    final shapes = List.filled(1200, '<rect class="a"/>').join();
    expect(
      () => svgWithStyles('<svg><style>$rules</style>$shapes</svg>'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'reason',
          contains('CSS processing limit'),
        ),
      ),
    );
  });

  test('leaves drawings without stylesheets unchanged', () {
    const svg = '<svg><rect fill="red"/><text>hello</text></svg>';
    expect(identical(svgWithStyles(svg), svg), isTrue);
  });
}
