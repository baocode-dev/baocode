/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../../../lib/ide/editor/monaco/LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/base/test/common/color.test.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971 (the 'Color' suite), plus a
// replay of results the real color.ts computed for seeded random inputs
// (`colorOps` and `luminance` in test/fixtures/theme/color_registry.json.gz,
// written by tool/generate_color_registry.mjs).
//
// `assert.deepStrictEqual` compares RGBA, HSLA and HSVA field by field; for a
// Color it compares the RGBA (the upstream cases only compare colors made
// from an RGBA).

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/base/common/color.dart';

Object? _deep(Object? value) => switch (value) {
  RGBA() => ['RGBA', value.r, value.g, value.b, value.a],
  HSLA() => ['HSLA', value.h, value.s, value.l, value.a],
  HSVA() => ['HSVA', value.h, value.s, value.v, value.a],
  Color() => ['Color', _deep(value.rgba)],
  _ => value,
};

void expectDeep(Object? actual, Object? expected) =>
    expect(_deep(actual), _deep(expected));

void expectNotDeep(Object? actual, Object? expected) =>
    expect(_deep(actual), isNot(_deep(expected)));

Color rgbaFromInt(int value) => Color(
  RGBA(
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    (value) & 0xff,
  ),
);

void assertContrastRatio(
  int background,
  int foreground,
  double ratio, [
  int? expected,
]) {
  final bgColor = rgbaFromInt(background);
  final fgColor = rgbaFromInt(foreground);
  expectDeep(
    bgColor.ensureConstrast(fgColor, ratio).rgba,
    rgbaFromInt(expected ?? foreground).rgba,
  );
}

// --- Replay of color.ts results ------------------------------------------------

double _number(Object? value) =>
    value == 'NaN' ? double.nan : (value as num).toDouble();

List<double> _numbers(Object? list) => [
  for (final value in list as List<Object?>) _number(value),
];

/// A color as the generator wrote it: its RGBA and, for a color made from an
/// HSLA/HSVA, that value.
Color _color(Map<String, Object?> json) {
  final rgba = _numbers(json['rgba']);
  final Color color;
  if (json['hsla'] case final Object hsla) {
    final h = _numbers(hsla);
    color = Color.fromHSLA(HSLA(h[0], h[1], h[2], h[3]));
  } else if (json['hsva'] case final Object hsva) {
    final h = _numbers(hsva);
    color = Color.fromHSVA(HSVA(h[0], h[1], h[2], h[3]));
  } else {
    color = Color(RGBA(rgba[0], rgba[1], rgba[2], rgba[3]));
  }
  expect([color.rgba.r, color.rgba.g, color.rgba.b, color.rgba.a], rgba);
  return color;
}

/// Doubles compared like `Object.is`: NaN equals NaN.
Matcher _same(List<double> expected) => pairwiseCompare<double, Object?>(
  expected,
  (e, a) => a is num && (e.isNaN ? a.isNaN : a == e),
  'equal (NaN equals NaN)',
);

void _expectColor(Color actual, Map<String, Object?> expected, String reason) {
  final rgba = _numbers(expected['rgba']);
  expect(
    [actual.rgba.r, actual.rgba.g, actual.rgba.b, actual.rgba.a],
    _same(rgba),
    reason: '$reason rgba',
  );
  // A color answers `hsla`/`hsva` with the value it was made from, if any.
  final expectedRgba = RGBA(rgba[0], rgba[1], rgba[2], rgba[3]);
  final hsla = expected['hsla'] != null
      ? _numbers(expected['hsla'])
      : _hslaList(HSLA.fromRGBA(expectedRgba));
  expect(_hslaList(actual.hsla), _same(hsla), reason: '$reason hsla');
  final hsva = expected['hsva'] != null
      ? _numbers(expected['hsva'])
      : _hsvaList(HSVA.fromRGBA(expectedRgba));
  expect(_hsvaList(actual.hsva), _same(hsva), reason: '$reason hsva');
}

List<double> _hslaList(HSLA v) => [v.h.toDouble(), v.s, v.l, v.a];
List<double> _hsvaList(HSVA v) => [v.h.toDouble(), v.s, v.v, v.a];

Object? _run(String op, List<Object> args) {
  Color c(int i) => args[i] as Color;
  double n(int i) => args[i] as double;
  return switch (op) {
    'hsla' => c(0).hsla,
    'hsva' => c(0).hsva,
    'lighten' => c(0).lighten(n(1)),
    'darken' => c(0).darken(n(1)),
    'lighten.darken' => c(0).lighten(n(1)).darken(n(2)),
    'darken.lighten.hsla' => c(0).darken(n(1)).lighten(n(2)).hsla,
    'transparent' => c(0).transparent(n(1)),
    'opposite' => c(0).opposite(),
    'blend' => c(0).blend(c(1)),
    'mix' => c(0).mix(c(1), n(2)),
    'mixDefault' => c(0).mix(c(1)),
    'makeOpaque' => c(0).makeOpaque(c(1)),
    'flatten' => c(0).flatten([for (var i = 1; i < args.length; i++) c(i)]),
    'getRelativeLuminance' => c(0).getRelativeLuminance(),
    'getContrastRatio' => c(0).getContrastRatio(c(1)),
    'isDarker' => c(0).isDarker(),
    'isLighter' => c(0).isLighter(),
    'isDarkerThan' => c(0).isDarkerThan(c(1)),
    'isLighterThan' => c(0).isLighterThan(c(1)),
    'getLighterColor' => Color.getLighterColor(c(0), c(1), n(2)),
    'getDarkerColor' => Color.getDarkerColor(c(0), c(1), n(2)),
    'getLighterColorDefault' => Color.getLighterColor(c(0), c(1)),
    'getDarkerColorDefault' => Color.getDarkerColor(c(0), c(1)),
    'ensureConstrast' => c(0).ensureConstrast(c(1), n(2)),
    'equals' => c(0).equals(c(1)),
    'equalsSelf' => c(
      0,
    ).equals(Color(RGBA(c(0).rgba.r, c(0).rgba.g, c(0).rgba.b, c(0).rgba.a))),
    'toString' => c(0).toString(),
    'formatRGB' => ColorFormatCSS.formatRGB(c(0)),
    'formatRGBA' => ColorFormatCSS.formatRGBA(c(0)),
    'formatHSL' => ColorFormatCSS.formatHSL(c(0)),
    'formatHSLA' => ColorFormatCSS.formatHSLA(c(0)),
    'formatHexA' => ColorFormatCSS.formatHexA(c(0)),
    'toNumber32Bit' => c(0).toNumber32Bit(),
    'hslaToRGBA' => HSLA.toRGBA(c(0).hsla),
    'hsvaToRGBA' => HSVA.toRGBA(c(0).hsva),
    _ => throw ArgumentError('Unknown op $op'),
  };
}

void main() {
  group('color.ts goldens', () {
    final fixture = jsonDecode(
      utf8.decode(
        gzip.decode(
          File('test/fixtures/theme/color_registry.json.gz').readAsBytesSync(),
        ),
      ),
    ) as Map<String, Object?>;

    test('getRelativeLuminance matches V8 for every RGB color', () {
      // V8's Math.pow of the 256 channel values; Dart's math.pow differs in
      // the last bit for some of them.
      final component = _numbers(fixture['luminance']);
      expect(component, hasLength(256));
      for (var color = 0; color < 256; color++) {
        final c = color / 255;
        final value = (c <= 0.03928)
            ? c / 12.92
            : math.pow(((c + 0.055) / 1.055), 2.4).toDouble();
        final ulp = component[color] * 2.220446049250313e-16;
        expect((value - component[color]).abs(), lessThanOrEqualTo(ulp));
      }
      // After the rounding to four decimals no color tells them apart.
      var differences = 0;
      for (var r = 0; r < 256; r++) {
        for (var g = 0; g < 256; g++) {
          for (var b = 0; b < 256; b++) {
            final luminance =
                0.2126 * component[r] +
                0.7152 * component[g] +
                0.0722 * component[b];
            final expected = (luminance * 10000).roundToDouble() / 10000;
            if (Color(RGBA(r, g, b)).getRelativeLuminance() != expected) {
              differences++;
            }
          }
        }
      }
      expect(differences, 0);
    });

    test('color operations', () {
      final ops = fixture['colorOps'] as List<Object?>;
      expect(ops, isNotEmpty);
      for (final (index, entry) in ops.indexed) {
        final op = entry as Map<String, Object?>;
        final name = op['op'] as String;
        final args = [
          for (final arg in op['args'] as List<Object?>)
            switch (arg as Map<String, Object?>) {
              {'color': final Map<String, Object?> color} => _color(color),
              {'number': final number} => _number(number),
              _ => throw StateError('arg $arg'),
            },
        ];
        final reason = '#$index $name(${op['args']})';
        final actual = _run(name, args);
        switch (op['result'] as Map<String, Object?>) {
          case {'color': final Map<String, Object?> color}:
            _expectColor(actual as Color, color, reason);
          case {'hsla': final Object hsla}:
            expect(
              _hslaList(actual as HSLA),
              _same(_numbers(hsla)),
              reason: reason,
            );
          case {'hsva': final Object hsva}:
            expect(
              _hsvaList(actual as HSVA),
              _same(_numbers(hsva)),
              reason: reason,
            );
          case {'rgba': final Object rgba}:
            final value = actual as RGBA;
            expect(
              [value.r, value.g, value.b, value.a],
              _same(_numbers(rgba)),
              reason: reason,
            );
          case {'number': final number}:
            expect([actual as num], _same([_number(number)]), reason: reason);
          case {'value': final value}:
            expect(actual, value, reason: reason);
          case final result:
            fail('$reason: unexpected result $result');
        }
      }
    });
  });

  group('upstream tests', () {
    ported();
  });

  test('number formatting follows JavaScript', () {
    // Expectations from the real color.ts in node.
    Color alpha(double a) => Color(RGBA(1, 2, 3, a));
    expect(ColorFormatCSS.formatRGBA(alpha(0.125)), 'rgba(1, 2, 3, 0.13)');
    expect(ColorFormatCSS.formatRGBA(alpha(0.875)), 'rgba(1, 2, 3, 0.88)');
    expect(ColorFormatCSS.formatRGBA(alpha(0.5)), 'rgba(1, 2, 3, 0.5)');
    expect(ColorFormatCSS.formatRGBA(alpha(0)), 'rgba(1, 2, 3, 0)');
    expect(ColorFormatCSS.formatRGB(alpha(1)), 'rgb(1, 2, 3)');
    expect(
      ColorFormatCSS.formatHSLA(Color.fromHSLA(HSLA(10, 0.5, 0.25, 0.125))),
      'hsla(10, 50%, 25%, 0.13)',
    );
    expect(() => ColorFormatCSS.parse('rgba(1, 2, 3)'), throwsFormatException);
    expect(() => ColorFormatCSS.parse('rgba(1,2)'), throwsFormatException);
    expect(ColorFormatCSS.parse('nope'), isNull);
  });
}

void ported() {
  group('Color', () {
    test('isLighterColor', () {
      final color1 = Color.fromHSLA(HSLA(60, 1, 0.5, 1)),
          color2 = Color.fromHSLA(HSLA(0, 0, 0.753, 1));

      expect(color1.isLighterThan(color2), isTrue);

      // Abyss theme
      expect(
        Color.fromHex('#770811').isLighterThan(Color.fromHex('#000c18')),
        isTrue,
      );
    });

    test('getLighterColor', () {
      final color1 = Color.fromHSLA(HSLA(60, 1, 0.5, 1)),
          color2 = Color.fromHSLA(HSLA(0, 0, 0.753, 1));

      expectDeep(color1.hsla, Color.getLighterColor(color1, color2).hsla);
      expectDeep(
        HSLA(0, 0, 0.916, 1),
        Color.getLighterColor(color2, color1).hsla,
      );
      expectDeep(
        HSLA(0, 0, 0.851, 1),
        Color.getLighterColor(color2, color1, 0.3).hsla,
      );
      expectDeep(
        HSLA(0, 0, 0.981, 1),
        Color.getLighterColor(color2, color1, 0.7).hsla,
      );
      expectDeep(
        HSLA(0, 0, 1, 1),
        Color.getLighterColor(color2, color1, 1).hsla,
      );
    });

    test('isDarkerColor', () {
      final color1 = Color.fromHSLA(HSLA(60, 1, 0.5, 1)),
          color2 = Color.fromHSLA(HSLA(0, 0, 0.753, 1));

      expect(color2.isDarkerThan(color1), isTrue);
    });

    test('getDarkerColor', () {
      final color1 = Color.fromHSLA(HSLA(60, 1, 0.5, 1)),
          color2 = Color.fromHSLA(HSLA(0, 0, 0.753, 1));

      expectDeep(color2.hsla, Color.getDarkerColor(color2, color1).hsla);
      expectDeep(
        HSLA(60, 1, 0.392, 1),
        Color.getDarkerColor(color1, color2).hsla,
      );
      expectDeep(
        HSLA(60, 1, 0.435, 1),
        Color.getDarkerColor(color1, color2, 0.3).hsla,
      );
      expectDeep(
        HSLA(60, 1, 0.349, 1),
        Color.getDarkerColor(color1, color2, 0.7).hsla,
      );
      expectDeep(
        HSLA(60, 1, 0.284, 1),
        Color.getDarkerColor(color1, color2, 1).hsla,
      );

      // Abyss theme
      expectDeep(
        HSLA(355, 0.874, 0.157, 1),
        Color.getDarkerColor(
          Color.fromHex('#770811'),
          Color.fromHex('#000c18'),
          0.4,
        ).hsla,
      );
    });

    test('luminance', () {
      expectDeep(0, Color(RGBA(0, 0, 0, 1)).getRelativeLuminance());
      expectDeep(1, Color(RGBA(255, 255, 255, 1)).getRelativeLuminance());

      expectDeep(0.2126, Color(RGBA(255, 0, 0, 1)).getRelativeLuminance());
      expectDeep(0.7152, Color(RGBA(0, 255, 0, 1)).getRelativeLuminance());
      expectDeep(0.0722, Color(RGBA(0, 0, 255, 1)).getRelativeLuminance());

      expectDeep(0.9278, Color(RGBA(255, 255, 0, 1)).getRelativeLuminance());
      expectDeep(0.7874, Color(RGBA(0, 255, 255, 1)).getRelativeLuminance());
      expectDeep(0.2848, Color(RGBA(255, 0, 255, 1)).getRelativeLuminance());

      expectDeep(0.5271, Color(RGBA(192, 192, 192, 1)).getRelativeLuminance());

      expectDeep(0.2159, Color(RGBA(128, 128, 128, 1)).getRelativeLuminance());
      expectDeep(0.0459, Color(RGBA(128, 0, 0, 1)).getRelativeLuminance());
      expectDeep(0.2003, Color(RGBA(128, 128, 0, 1)).getRelativeLuminance());
      expectDeep(0.1544, Color(RGBA(0, 128, 0, 1)).getRelativeLuminance());
      expectDeep(0.0615, Color(RGBA(128, 0, 128, 1)).getRelativeLuminance());
      expectDeep(0.17, Color(RGBA(0, 128, 128, 1)).getRelativeLuminance());
      expectDeep(0.0156, Color(RGBA(0, 0, 128, 1)).getRelativeLuminance());
    });

    test('blending', () {
      expectDeep(
        Color(RGBA(0, 0, 0, 0)).blend(Color(RGBA(243, 34, 43))),
        Color(RGBA(243, 34, 43)),
      );
      expectDeep(
        Color(RGBA(255, 255, 255)).blend(Color(RGBA(243, 34, 43))),
        Color(RGBA(255, 255, 255)),
      );
      expectDeep(
        Color(RGBA(122, 122, 122, 0.7)).blend(Color(RGBA(243, 34, 43))),
        Color(RGBA(158, 95, 98)),
      );
      expectDeep(
        Color(RGBA(0, 0, 0, 0.58)).blend(Color(RGBA(255, 255, 255, 0.33))),
        Color(RGBA(49, 49, 49, 0.719)),
      );
    });

    group('toString', () {
      test('alpha channel', () {
        expectDeep(Color.fromHex('#00000000').toString(), 'rgba(0, 0, 0, 0)');
        expectDeep(Color.fromHex('#00000080').toString(), 'rgba(0, 0, 0, 0.5)');
        expectDeep(Color.fromHex('#000000FF').toString(), '#000000');
      });

      test('opaque', () {
        expectDeep(
          Color.fromHex('#000000').toString().toUpperCase(),
          '#000000'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#FFFFFF').toString().toUpperCase(),
          '#FFFFFF'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#FF0000').toString().toUpperCase(),
          '#FF0000'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#00FF00').toString().toUpperCase(),
          '#00FF00'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#0000FF').toString().toUpperCase(),
          '#0000FF'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#FFFF00').toString().toUpperCase(),
          '#FFFF00'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#00FFFF').toString().toUpperCase(),
          '#00FFFF'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#FF00FF').toString().toUpperCase(),
          '#FF00FF'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#C0C0C0').toString().toUpperCase(),
          '#C0C0C0'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#808080').toString().toUpperCase(),
          '#808080'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#800000').toString().toUpperCase(),
          '#800000'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#808000').toString().toUpperCase(),
          '#808000'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#008000').toString().toUpperCase(),
          '#008000'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#800080').toString().toUpperCase(),
          '#800080'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#008080').toString().toUpperCase(),
          '#008080'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#000080').toString().toUpperCase(),
          '#000080'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#010203').toString().toUpperCase(),
          '#010203'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#040506').toString().toUpperCase(),
          '#040506'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#070809').toString().toUpperCase(),
          '#070809'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#0a0A0a').toString().toUpperCase(),
          '#0a0A0a'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#0b0B0b').toString().toUpperCase(),
          '#0b0B0b'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#0c0C0c').toString().toUpperCase(),
          '#0c0C0c'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#0d0D0d').toString().toUpperCase(),
          '#0d0D0d'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#0e0E0e').toString().toUpperCase(),
          '#0e0E0e'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#0f0F0f').toString().toUpperCase(),
          '#0f0F0f'.toUpperCase(),
        );
        expectDeep(
          Color.fromHex('#a0A0a0').toString().toUpperCase(),
          '#a0A0a0'.toUpperCase(),
        );
      });
    });

    group('toNumber32Bit', () {
      test('alpha channel', () {
        expectDeep(Color.fromHex('#00000000').toNumber32Bit(), 0x00000000);
        expectDeep(Color.fromHex('#00000080').toNumber32Bit(), 0x00000080);
        expectDeep(Color.fromHex('#000000FF').toNumber32Bit(), 0x000000FF);
      });

      test('opaque', () {
        expectDeep(Color.fromHex('#000000').toNumber32Bit(), 0x000000FF);
        expectDeep(Color.fromHex('#FFFFFF').toNumber32Bit(), 0xFFFFFFFF);
        expectDeep(Color.fromHex('#FF0000').toNumber32Bit(), 0xFF0000FF);
        expectDeep(Color.fromHex('#00FF00').toNumber32Bit(), 0x00FF00FF);
        expectDeep(Color.fromHex('#0000FF').toNumber32Bit(), 0x0000FFFF);
        expectDeep(Color.fromHex('#FFFF00').toNumber32Bit(), 0xFFFF00FF);
        expectDeep(Color.fromHex('#00FFFF').toNumber32Bit(), 0x00FFFFFF);
        expectDeep(Color.fromHex('#FF00FF').toNumber32Bit(), 0xFF00FFFF);
        expectDeep(Color.fromHex('#C0C0C0').toNumber32Bit(), 0xC0C0C0FF);
        expectDeep(Color.fromHex('#808080').toNumber32Bit(), 0x808080FF);
        expectDeep(Color.fromHex('#800000').toNumber32Bit(), 0x800000FF);
        expectDeep(Color.fromHex('#808000').toNumber32Bit(), 0x808000FF);
        expectDeep(Color.fromHex('#008000').toNumber32Bit(), 0x008000FF);
        expectDeep(Color.fromHex('#800080').toNumber32Bit(), 0x800080FF);
        expectDeep(Color.fromHex('#008080').toNumber32Bit(), 0x008080FF);
        expectDeep(Color.fromHex('#000080').toNumber32Bit(), 0x000080FF);
        expectDeep(Color.fromHex('#010203').toNumber32Bit(), 0x010203FF);
        expectDeep(Color.fromHex('#040506').toNumber32Bit(), 0x040506FF);
        expectDeep(Color.fromHex('#070809').toNumber32Bit(), 0x070809FF);
        expectDeep(Color.fromHex('#0a0A0a').toNumber32Bit(), 0x0a0A0aFF);
        expectDeep(Color.fromHex('#0b0B0b').toNumber32Bit(), 0x0b0B0bFF);
        expectDeep(Color.fromHex('#0c0C0c').toNumber32Bit(), 0x0c0C0cFF);
        expectDeep(Color.fromHex('#0d0D0d').toNumber32Bit(), 0x0d0D0dFF);
        expectDeep(Color.fromHex('#0e0E0e').toNumber32Bit(), 0x0e0E0eFF);
        expectDeep(Color.fromHex('#0f0F0f').toNumber32Bit(), 0x0f0F0fFF);
        expectDeep(Color.fromHex('#a0A0a0').toNumber32Bit(), 0xa0A0a0FF);
      });
    });

    group('HSLA', () {
      test('HSLA.toRGBA', () {
        expectDeep(HSLA.toRGBA(HSLA(0, 0, 0, 0)), RGBA(0, 0, 0, 0));
        expectDeep(HSLA.toRGBA(HSLA(0, 0, 0, 1)), RGBA(0, 0, 0, 1));
        expectDeep(HSLA.toRGBA(HSLA(0, 0, 1, 1)), RGBA(255, 255, 255, 1));

        expectDeep(HSLA.toRGBA(HSLA(0, 1, 0.5, 1)), RGBA(255, 0, 0, 1));
        expectDeep(HSLA.toRGBA(HSLA(120, 1, 0.5, 1)), RGBA(0, 255, 0, 1));
        expectDeep(HSLA.toRGBA(HSLA(240, 1, 0.5, 1)), RGBA(0, 0, 255, 1));

        expectDeep(HSLA.toRGBA(HSLA(60, 1, 0.5, 1)), RGBA(255, 255, 0, 1));
        expectDeep(HSLA.toRGBA(HSLA(180, 1, 0.5, 1)), RGBA(0, 255, 255, 1));
        expectDeep(HSLA.toRGBA(HSLA(300, 1, 0.5, 1)), RGBA(255, 0, 255, 1));

        expectDeep(HSLA.toRGBA(HSLA(0, 0, 0.753, 1)), RGBA(192, 192, 192, 1));

        expectDeep(HSLA.toRGBA(HSLA(0, 0, 0.502, 1)), RGBA(128, 128, 128, 1));
        expectDeep(HSLA.toRGBA(HSLA(0, 1, 0.251, 1)), RGBA(128, 0, 0, 1));
        expectDeep(HSLA.toRGBA(HSLA(60, 1, 0.251, 1)), RGBA(128, 128, 0, 1));
        expectDeep(HSLA.toRGBA(HSLA(120, 1, 0.251, 1)), RGBA(0, 128, 0, 1));
        expectDeep(HSLA.toRGBA(HSLA(300, 1, 0.251, 1)), RGBA(128, 0, 128, 1));
        expectDeep(HSLA.toRGBA(HSLA(180, 1, 0.251, 1)), RGBA(0, 128, 128, 1));
        expectDeep(HSLA.toRGBA(HSLA(240, 1, 0.251, 1)), RGBA(0, 0, 128, 1));
      });

      test('HSLA.fromRGBA', () {
        expectDeep(HSLA.fromRGBA(RGBA(0, 0, 0, 0)), HSLA(0, 0, 0, 0));
        expectDeep(HSLA.fromRGBA(RGBA(0, 0, 0, 1)), HSLA(0, 0, 0, 1));
        expectDeep(HSLA.fromRGBA(RGBA(255, 255, 255, 1)), HSLA(0, 0, 1, 1));

        expectDeep(HSLA.fromRGBA(RGBA(255, 0, 0, 1)), HSLA(0, 1, 0.5, 1));
        expectDeep(HSLA.fromRGBA(RGBA(0, 255, 0, 1)), HSLA(120, 1, 0.5, 1));
        expectDeep(HSLA.fromRGBA(RGBA(0, 0, 255, 1)), HSLA(240, 1, 0.5, 1));

        expectDeep(HSLA.fromRGBA(RGBA(255, 255, 0, 1)), HSLA(60, 1, 0.5, 1));
        expectDeep(HSLA.fromRGBA(RGBA(0, 255, 255, 1)), HSLA(180, 1, 0.5, 1));
        expectDeep(HSLA.fromRGBA(RGBA(255, 0, 255, 1)), HSLA(300, 1, 0.5, 1));

        expectDeep(HSLA.fromRGBA(RGBA(192, 192, 192, 1)), HSLA(0, 0, 0.753, 1));

        expectDeep(HSLA.fromRGBA(RGBA(128, 128, 128, 1)), HSLA(0, 0, 0.502, 1));
        expectDeep(HSLA.fromRGBA(RGBA(128, 0, 0, 1)), HSLA(0, 1, 0.251, 1));
        expectDeep(HSLA.fromRGBA(RGBA(128, 128, 0, 1)), HSLA(60, 1, 0.251, 1));
        expectDeep(HSLA.fromRGBA(RGBA(0, 128, 0, 1)), HSLA(120, 1, 0.251, 1));
        expectDeep(HSLA.fromRGBA(RGBA(128, 0, 128, 1)), HSLA(300, 1, 0.251, 1));
        expectDeep(HSLA.fromRGBA(RGBA(0, 128, 128, 1)), HSLA(180, 1, 0.251, 1));
        expectDeep(HSLA.fromRGBA(RGBA(0, 0, 128, 1)), HSLA(240, 1, 0.251, 1));
      });
    });

    group('HSVA', () {
      test('HSVA.toRGBA', () {
        expectDeep(HSVA.toRGBA(HSVA(0, 0, 0, 0)), RGBA(0, 0, 0, 0));
        expectDeep(HSVA.toRGBA(HSVA(0, 0, 0, 1)), RGBA(0, 0, 0, 1));
        expectDeep(HSVA.toRGBA(HSVA(0, 0, 1, 1)), RGBA(255, 255, 255, 1));

        expectDeep(HSVA.toRGBA(HSVA(0, 1, 1, 1)), RGBA(255, 0, 0, 1));
        expectDeep(HSVA.toRGBA(HSVA(120, 1, 1, 1)), RGBA(0, 255, 0, 1));
        expectDeep(HSVA.toRGBA(HSVA(240, 1, 1, 1)), RGBA(0, 0, 255, 1));

        expectDeep(HSVA.toRGBA(HSVA(60, 1, 1, 1)), RGBA(255, 255, 0, 1));
        expectDeep(HSVA.toRGBA(HSVA(180, 1, 1, 1)), RGBA(0, 255, 255, 1));
        expectDeep(HSVA.toRGBA(HSVA(300, 1, 1, 1)), RGBA(255, 0, 255, 1));

        expectDeep(HSVA.toRGBA(HSVA(0, 0, 0.753, 1)), RGBA(192, 192, 192, 1));

        expectDeep(HSVA.toRGBA(HSVA(0, 0, 0.502, 1)), RGBA(128, 128, 128, 1));
        expectDeep(HSVA.toRGBA(HSVA(0, 1, 0.502, 1)), RGBA(128, 0, 0, 1));
        expectDeep(HSVA.toRGBA(HSVA(60, 1, 0.502, 1)), RGBA(128, 128, 0, 1));
        expectDeep(HSVA.toRGBA(HSVA(120, 1, 0.502, 1)), RGBA(0, 128, 0, 1));
        expectDeep(HSVA.toRGBA(HSVA(300, 1, 0.502, 1)), RGBA(128, 0, 128, 1));
        expectDeep(HSVA.toRGBA(HSVA(180, 1, 0.502, 1)), RGBA(0, 128, 128, 1));
        expectDeep(HSVA.toRGBA(HSVA(240, 1, 0.502, 1)), RGBA(0, 0, 128, 1));

        expectDeep(HSVA.toRGBA(HSVA(360, 0, 0, 0)), RGBA(0, 0, 0, 0));
        expectDeep(HSVA.toRGBA(HSVA(360, 0, 0, 1)), RGBA(0, 0, 0, 1));
        expectDeep(HSVA.toRGBA(HSVA(360, 0, 1, 1)), RGBA(255, 255, 255, 1));
        expectDeep(HSVA.toRGBA(HSVA(360, 1, 1, 1)), RGBA(255, 0, 0, 1));
        expectDeep(HSVA.toRGBA(HSVA(360, 0, 0.753, 1)), RGBA(192, 192, 192, 1));
        expectDeep(HSVA.toRGBA(HSVA(360, 0, 0.502, 1)), RGBA(128, 128, 128, 1));
        expectDeep(HSVA.toRGBA(HSVA(360, 1, 0.502, 1)), RGBA(128, 0, 0, 1));
      });

      test('HSVA.fromRGBA', () {
        expectDeep(HSVA.fromRGBA(RGBA(0, 0, 0, 0)), HSVA(0, 0, 0, 0));
        expectDeep(HSVA.fromRGBA(RGBA(0, 0, 0, 1)), HSVA(0, 0, 0, 1));
        expectDeep(HSVA.fromRGBA(RGBA(255, 255, 255, 1)), HSVA(0, 0, 1, 1));

        expectDeep(HSVA.fromRGBA(RGBA(255, 0, 0, 1)), HSVA(0, 1, 1, 1));
        expectDeep(HSVA.fromRGBA(RGBA(0, 255, 0, 1)), HSVA(120, 1, 1, 1));
        expectDeep(HSVA.fromRGBA(RGBA(0, 0, 255, 1)), HSVA(240, 1, 1, 1));

        expectDeep(HSVA.fromRGBA(RGBA(255, 255, 0, 1)), HSVA(60, 1, 1, 1));
        expectDeep(HSVA.fromRGBA(RGBA(0, 255, 255, 1)), HSVA(180, 1, 1, 1));
        expectDeep(HSVA.fromRGBA(RGBA(255, 0, 255, 1)), HSVA(300, 1, 1, 1));

        expectDeep(HSVA.fromRGBA(RGBA(192, 192, 192, 1)), HSVA(0, 0, 0.753, 1));

        expectDeep(HSVA.fromRGBA(RGBA(128, 128, 128, 1)), HSVA(0, 0, 0.502, 1));
        expectDeep(HSVA.fromRGBA(RGBA(128, 0, 0, 1)), HSVA(0, 1, 0.502, 1));
        expectDeep(HSVA.fromRGBA(RGBA(128, 128, 0, 1)), HSVA(60, 1, 0.502, 1));
        expectDeep(HSVA.fromRGBA(RGBA(0, 128, 0, 1)), HSVA(120, 1, 0.502, 1));
        expectDeep(HSVA.fromRGBA(RGBA(128, 0, 128, 1)), HSVA(300, 1, 0.502, 1));
        expectDeep(HSVA.fromRGBA(RGBA(0, 128, 128, 1)), HSVA(180, 1, 0.502, 1));
        expectDeep(HSVA.fromRGBA(RGBA(0, 0, 128, 1)), HSVA(240, 1, 0.502, 1));
      });

      test('Keep hue value when saturation is 0', () {
        expectDeep(
          HSVA.toRGBA(HSVA(10, 0, 0, 0)),
          HSVA.toRGBA(HSVA(20, 0, 0, 0)),
        );
        expectDeep(
          Color.fromHSVA(HSVA(10, 0, 0, 0)).rgba,
          Color.fromHSVA(HSVA(20, 0, 0, 0)).rgba,
        );
        expectNotDeep(
          Color.fromHSVA(HSVA(10, 0, 0, 0)).hsva,
          Color.fromHSVA(HSVA(20, 0, 0, 0)).hsva,
        );
      });

      test('bug#36240', () {
        expectDeep(
          HSVA.fromRGBA(RGBA(92, 106, 196, 1)),
          HSVA(232, 0.531, 0.769, 1),
        );
        expectDeep(
          HSVA.toRGBA(HSVA.fromRGBA(RGBA(92, 106, 196, 1))),
          RGBA(92, 106, 196, 1),
        );
      });
    });

    group('Format', () {
      group('CSS', () {
        group('parse', () {
          test('invalid', () {
            expectDeep(ColorFormatCSS.parse(''), null);
            expectDeep(ColorFormatCSS.parse('#'), null);
            expectDeep(ColorFormatCSS.parse('#0102030'), null);
          });

          test('transparent', () {
            expectDeep(
              ColorFormatCSS.parse('transparent')!.rgba,
              RGBA(0, 0, 0, 0),
            );
          });

          test('named keyword', () {
            expectDeep(
              ColorFormatCSS.parse('aliceblue')!.rgba,
              RGBA(240, 248, 255, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('antiquewhite')!.rgba,
              RGBA(250, 235, 215, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('aqua')!.rgba,
              RGBA(0, 255, 255, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('aquamarine')!.rgba,
              RGBA(127, 255, 212, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('azure')!.rgba,
              RGBA(240, 255, 255, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('beige')!.rgba,
              RGBA(245, 245, 220, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('bisque')!.rgba,
              RGBA(255, 228, 196, 1),
            );
            expectDeep(ColorFormatCSS.parse('black')!.rgba, RGBA(0, 0, 0, 1));
            expectDeep(
              ColorFormatCSS.parse('blanchedalmond')!.rgba,
              RGBA(255, 235, 205, 1),
            );
            expectDeep(ColorFormatCSS.parse('blue')!.rgba, RGBA(0, 0, 255, 1));
            expectDeep(
              ColorFormatCSS.parse('blueviolet')!.rgba,
              RGBA(138, 43, 226, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('brown')!.rgba,
              RGBA(165, 42, 42, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('burlywood')!.rgba,
              RGBA(222, 184, 135, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('cadetblue')!.rgba,
              RGBA(95, 158, 160, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('chartreuse')!.rgba,
              RGBA(127, 255, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('chocolate')!.rgba,
              RGBA(210, 105, 30, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('coral')!.rgba,
              RGBA(255, 127, 80, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('cornflowerblue')!.rgba,
              RGBA(100, 149, 237, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('cornsilk')!.rgba,
              RGBA(255, 248, 220, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('crimson')!.rgba,
              RGBA(220, 20, 60, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('cyan')!.rgba,
              RGBA(0, 255, 255, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkblue')!.rgba,
              RGBA(0, 0, 139, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkcyan')!.rgba,
              RGBA(0, 139, 139, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkgoldenrod')!.rgba,
              RGBA(184, 134, 11, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkgray')!.rgba,
              RGBA(169, 169, 169, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkgreen')!.rgba,
              RGBA(0, 100, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkgrey')!.rgba,
              RGBA(169, 169, 169, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkkhaki')!.rgba,
              RGBA(189, 183, 107, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkmagenta')!.rgba,
              RGBA(139, 0, 139, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkolivegreen')!.rgba,
              RGBA(85, 107, 47, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkorange')!.rgba,
              RGBA(255, 140, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkorchid')!.rgba,
              RGBA(153, 50, 204, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkred')!.rgba,
              RGBA(139, 0, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darksalmon')!.rgba,
              RGBA(233, 150, 122, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkseagreen')!.rgba,
              RGBA(143, 188, 143, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkslateblue')!.rgba,
              RGBA(72, 61, 139, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkslategray')!.rgba,
              RGBA(47, 79, 79, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkslategrey')!.rgba,
              RGBA(47, 79, 79, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkturquoise')!.rgba,
              RGBA(0, 206, 209, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('darkviolet')!.rgba,
              RGBA(148, 0, 211, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('deeppink')!.rgba,
              RGBA(255, 20, 147, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('deepskyblue')!.rgba,
              RGBA(0, 191, 255, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('dimgray')!.rgba,
              RGBA(105, 105, 105, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('dimgrey')!.rgba,
              RGBA(105, 105, 105, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('dodgerblue')!.rgba,
              RGBA(30, 144, 255, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('firebrick')!.rgba,
              RGBA(178, 34, 34, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('floralwhite')!.rgba,
              RGBA(255, 250, 240, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('forestgreen')!.rgba,
              RGBA(34, 139, 34, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('fuchsia')!.rgba,
              RGBA(255, 0, 255, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('gainsboro')!.rgba,
              RGBA(220, 220, 220, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('ghostwhite')!.rgba,
              RGBA(248, 248, 255, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('gold')!.rgba,
              RGBA(255, 215, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('goldenrod')!.rgba,
              RGBA(218, 165, 32, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('gray')!.rgba,
              RGBA(128, 128, 128, 1),
            );
            expectDeep(ColorFormatCSS.parse('green')!.rgba, RGBA(0, 128, 0, 1));
            expectDeep(
              ColorFormatCSS.parse('greenyellow')!.rgba,
              RGBA(173, 255, 47, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('grey')!.rgba,
              RGBA(128, 128, 128, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('honeydew')!.rgba,
              RGBA(240, 255, 240, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('hotpink')!.rgba,
              RGBA(255, 105, 180, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('indianred')!.rgba,
              RGBA(205, 92, 92, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('indigo')!.rgba,
              RGBA(75, 0, 130, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('ivory')!.rgba,
              RGBA(255, 255, 240, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('khaki')!.rgba,
              RGBA(240, 230, 140, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lavender')!.rgba,
              RGBA(230, 230, 250, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lavenderblush')!.rgba,
              RGBA(255, 240, 245, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lawngreen')!.rgba,
              RGBA(124, 252, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lemonchiffon')!.rgba,
              RGBA(255, 250, 205, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lightblue')!.rgba,
              RGBA(173, 216, 230, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lightcoral')!.rgba,
              RGBA(240, 128, 128, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lightcyan')!.rgba,
              RGBA(224, 255, 255, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lightgoldenrodyellow')!.rgba,
              RGBA(250, 250, 210, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lightgray')!.rgba,
              RGBA(211, 211, 211, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lightgreen')!.rgba,
              RGBA(144, 238, 144, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lightgrey')!.rgba,
              RGBA(211, 211, 211, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lightpink')!.rgba,
              RGBA(255, 182, 193, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lightsalmon')!.rgba,
              RGBA(255, 160, 122, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lightseagreen')!.rgba,
              RGBA(32, 178, 170, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lightskyblue')!.rgba,
              RGBA(135, 206, 250, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lightslategray')!.rgba,
              RGBA(119, 136, 153, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lightslategrey')!.rgba,
              RGBA(119, 136, 153, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lightsteelblue')!.rgba,
              RGBA(176, 196, 222, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('lightyellow')!.rgba,
              RGBA(255, 255, 224, 1),
            );
            expectDeep(ColorFormatCSS.parse('lime')!.rgba, RGBA(0, 255, 0, 1));
            expectDeep(
              ColorFormatCSS.parse('limegreen')!.rgba,
              RGBA(50, 205, 50, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('linen')!.rgba,
              RGBA(250, 240, 230, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('magenta')!.rgba,
              RGBA(255, 0, 255, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('maroon')!.rgba,
              RGBA(128, 0, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('mediumaquamarine')!.rgba,
              RGBA(102, 205, 170, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('mediumblue')!.rgba,
              RGBA(0, 0, 205, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('mediumorchid')!.rgba,
              RGBA(186, 85, 211, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('mediumpurple')!.rgba,
              RGBA(147, 112, 219, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('mediumseagreen')!.rgba,
              RGBA(60, 179, 113, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('mediumslateblue')!.rgba,
              RGBA(123, 104, 238, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('mediumspringgreen')!.rgba,
              RGBA(0, 250, 154, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('mediumturquoise')!.rgba,
              RGBA(72, 209, 204, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('mediumvioletred')!.rgba,
              RGBA(199, 21, 133, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('midnightblue')!.rgba,
              RGBA(25, 25, 112, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('mintcream')!.rgba,
              RGBA(245, 255, 250, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('mistyrose')!.rgba,
              RGBA(255, 228, 225, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('moccasin')!.rgba,
              RGBA(255, 228, 181, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('navajowhite')!.rgba,
              RGBA(255, 222, 173, 1),
            );
            expectDeep(ColorFormatCSS.parse('navy')!.rgba, RGBA(0, 0, 128, 1));
            expectDeep(
              ColorFormatCSS.parse('oldlace')!.rgba,
              RGBA(253, 245, 230, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('olive')!.rgba,
              RGBA(128, 128, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('olivedrab')!.rgba,
              RGBA(107, 142, 35, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('orange')!.rgba,
              RGBA(255, 165, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('orangered')!.rgba,
              RGBA(255, 69, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('orchid')!.rgba,
              RGBA(218, 112, 214, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('palegoldenrod')!.rgba,
              RGBA(238, 232, 170, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('palegreen')!.rgba,
              RGBA(152, 251, 152, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('paleturquoise')!.rgba,
              RGBA(175, 238, 238, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('palevioletred')!.rgba,
              RGBA(219, 112, 147, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('papayawhip')!.rgba,
              RGBA(255, 239, 213, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('peachpuff')!.rgba,
              RGBA(255, 218, 185, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('peru')!.rgba,
              RGBA(205, 133, 63, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('pink')!.rgba,
              RGBA(255, 192, 203, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('plum')!.rgba,
              RGBA(221, 160, 221, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('powderblue')!.rgba,
              RGBA(176, 224, 230, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('purple')!.rgba,
              RGBA(128, 0, 128, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rebeccapurple')!.rgba,
              RGBA(102, 51, 153, 1),
            );
            expectDeep(ColorFormatCSS.parse('red')!.rgba, RGBA(255, 0, 0, 1));
            expectDeep(
              ColorFormatCSS.parse('rosybrown')!.rgba,
              RGBA(188, 143, 143, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('royalblue')!.rgba,
              RGBA(65, 105, 225, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('saddlebrown')!.rgba,
              RGBA(139, 69, 19, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('salmon')!.rgba,
              RGBA(250, 128, 114, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('sandybrown')!.rgba,
              RGBA(244, 164, 96, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('seagreen')!.rgba,
              RGBA(46, 139, 87, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('seashell')!.rgba,
              RGBA(255, 245, 238, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('sienna')!.rgba,
              RGBA(160, 82, 45, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('silver')!.rgba,
              RGBA(192, 192, 192, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('skyblue')!.rgba,
              RGBA(135, 206, 235, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('slateblue')!.rgba,
              RGBA(106, 90, 205, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('slategray')!.rgba,
              RGBA(112, 128, 144, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('slategrey')!.rgba,
              RGBA(112, 128, 144, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('snow')!.rgba,
              RGBA(255, 250, 250, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('springgreen')!.rgba,
              RGBA(0, 255, 127, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('steelblue')!.rgba,
              RGBA(70, 130, 180, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('tan')!.rgba,
              RGBA(210, 180, 140, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('teal')!.rgba,
              RGBA(0, 128, 128, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('thistle')!.rgba,
              RGBA(216, 191, 216, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('tomato')!.rgba,
              RGBA(255, 99, 71, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('turquoise')!.rgba,
              RGBA(64, 224, 208, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('violet')!.rgba,
              RGBA(238, 130, 238, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('wheat')!.rgba,
              RGBA(245, 222, 179, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('white')!.rgba,
              RGBA(255, 255, 255, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('whitesmoke')!.rgba,
              RGBA(245, 245, 245, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('yellow')!.rgba,
              RGBA(255, 255, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('yellowgreen')!.rgba,
              RGBA(154, 205, 50, 1),
            );
          });

          test('hex-color', () {
            // somewhat valid
            expectDeep(
              ColorFormatCSS.parse('#FFFFG0')!.rgba,
              RGBA(255, 255, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#FFFFg0')!.rgba,
              RGBA(255, 255, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#-FFF00')!.rgba,
              RGBA(15, 255, 0, 1),
            );

            // valid
            expectDeep(ColorFormatCSS.parse('#000000')!.rgba, RGBA(0, 0, 0, 1));
            expectDeep(
              ColorFormatCSS.parse('#FFFFFF')!.rgba,
              RGBA(255, 255, 255, 1),
            );

            expectDeep(
              ColorFormatCSS.parse('#FF0000')!.rgba,
              RGBA(255, 0, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#00FF00')!.rgba,
              RGBA(0, 255, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#0000FF')!.rgba,
              RGBA(0, 0, 255, 1),
            );

            expectDeep(
              ColorFormatCSS.parse('#FFFF00')!.rgba,
              RGBA(255, 255, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#00FFFF')!.rgba,
              RGBA(0, 255, 255, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#FF00FF')!.rgba,
              RGBA(255, 0, 255, 1),
            );

            expectDeep(
              ColorFormatCSS.parse('#C0C0C0')!.rgba,
              RGBA(192, 192, 192, 1),
            );

            expectDeep(
              ColorFormatCSS.parse('#808080')!.rgba,
              RGBA(128, 128, 128, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#800000')!.rgba,
              RGBA(128, 0, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#808000')!.rgba,
              RGBA(128, 128, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#008000')!.rgba,
              RGBA(0, 128, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#800080')!.rgba,
              RGBA(128, 0, 128, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#008080')!.rgba,
              RGBA(0, 128, 128, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#000080')!.rgba,
              RGBA(0, 0, 128, 1),
            );

            expectDeep(ColorFormatCSS.parse('#010203')!.rgba, RGBA(1, 2, 3, 1));
            expectDeep(ColorFormatCSS.parse('#040506')!.rgba, RGBA(4, 5, 6, 1));
            expectDeep(ColorFormatCSS.parse('#070809')!.rgba, RGBA(7, 8, 9, 1));
            expectDeep(
              ColorFormatCSS.parse('#0a0A0a')!.rgba,
              RGBA(10, 10, 10, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#0b0B0b')!.rgba,
              RGBA(11, 11, 11, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#0c0C0c')!.rgba,
              RGBA(12, 12, 12, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#0d0D0d')!.rgba,
              RGBA(13, 13, 13, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#0e0E0e')!.rgba,
              RGBA(14, 14, 14, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#0f0F0f')!.rgba,
              RGBA(15, 15, 15, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#a0A0a0')!.rgba,
              RGBA(160, 160, 160, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#CFA')!.rgba,
              RGBA(204, 255, 170, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('#CFA8')!.rgba,
              RGBA(204, 255, 170, 0.533),
            );
          });

          test('rgb()', () {
            // somewhat valid / unusual
            expectDeep(
              ColorFormatCSS.parse('rgb(-255, 0, 0)')!.rgba,
              RGBA(0, 0, 0),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(+255, 0, 0)')!.rgba,
              RGBA(255, 0, 0),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(800, 0, 0)')!.rgba,
              RGBA(255, 0, 0),
            );

            // valid
            expectDeep(
              ColorFormatCSS.parse('rgb(0, 0, 0)')!.rgba,
              RGBA(0, 0, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(255, 255, 255)')!.rgba,
              RGBA(255, 255, 255, 1),
            );

            expectDeep(
              ColorFormatCSS.parse('rgb(255, 0, 0)')!.rgba,
              RGBA(255, 0, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(0, 255, 0)')!.rgba,
              RGBA(0, 255, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(0, 0, 255)')!.rgba,
              RGBA(0, 0, 255, 1),
            );

            expectDeep(
              ColorFormatCSS.parse('rgb(255, 255, 0)')!.rgba,
              RGBA(255, 255, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(0, 255, 255)')!.rgba,
              RGBA(0, 255, 255, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(255, 0, 255)')!.rgba,
              RGBA(255, 0, 255, 1),
            );

            expectDeep(
              ColorFormatCSS.parse('rgb(192, 192, 192)')!.rgba,
              RGBA(192, 192, 192, 1),
            );

            expectDeep(
              ColorFormatCSS.parse('rgb(128, 128, 128)')!.rgba,
              RGBA(128, 128, 128, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(128, 0, 0)')!.rgba,
              RGBA(128, 0, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(128, 128, 0)')!.rgba,
              RGBA(128, 128, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(0, 128, 0)')!.rgba,
              RGBA(0, 128, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(128, 0, 128)')!.rgba,
              RGBA(128, 0, 128, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(0, 128, 128)')!.rgba,
              RGBA(0, 128, 128, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(0, 0, 128)')!.rgba,
              RGBA(0, 0, 128, 1),
            );

            expectDeep(
              ColorFormatCSS.parse('rgb(1, 2, 3)')!.rgba,
              RGBA(1, 2, 3, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(4, 5, 6)')!.rgba,
              RGBA(4, 5, 6, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(7, 8, 9)')!.rgba,
              RGBA(7, 8, 9, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(10, 10, 10)')!.rgba,
              RGBA(10, 10, 10, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(11, 11, 11)')!.rgba,
              RGBA(11, 11, 11, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(12, 12, 12)')!.rgba,
              RGBA(12, 12, 12, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(13, 13, 13)')!.rgba,
              RGBA(13, 13, 13, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(14, 14, 14)')!.rgba,
              RGBA(14, 14, 14, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgb(15, 15, 15)')!.rgba,
              RGBA(15, 15, 15, 1),
            );
          });

          test('rgba()', () {
            // somewhat valid / unusual
            expectDeep(
              ColorFormatCSS.parse('rgba(0, 0, 0, 255)')!.rgba,
              RGBA(0, 0, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(-255, 0, 0, 1)')!.rgba,
              RGBA(0, 0, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(+255, 0, 0, 1)')!.rgba,
              RGBA(255, 0, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(800, 0, 0, 1)')!.rgba,
              RGBA(255, 0, 0, 1),
            );

            // alpha values
            expectDeep(
              ColorFormatCSS.parse('rgba(255, 0, 0, 0.2)')!.rgba,
              RGBA(255, 0, 0, 0.2),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(255, 0, 0, 0.5)')!.rgba,
              RGBA(255, 0, 0, 0.5),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(255, 0, 0, 0.75)')!.rgba,
              RGBA(255, 0, 0, 0.75),
            );

            // valid
            expectDeep(
              ColorFormatCSS.parse('rgba(0, 0, 0, 1)')!.rgba,
              RGBA(0, 0, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(255, 255, 255, 1)')!.rgba,
              RGBA(255, 255, 255, 1),
            );

            expectDeep(
              ColorFormatCSS.parse('rgba(255, 0, 0, 1)')!.rgba,
              RGBA(255, 0, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(0, 255, 0, 1)')!.rgba,
              RGBA(0, 255, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(0, 0, 255, 1)')!.rgba,
              RGBA(0, 0, 255, 1),
            );

            expectDeep(
              ColorFormatCSS.parse('rgba(255, 255, 0, 1)')!.rgba,
              RGBA(255, 255, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(0, 255, 255, 1)')!.rgba,
              RGBA(0, 255, 255, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(255, 0, 255, 1)')!.rgba,
              RGBA(255, 0, 255, 1),
            );

            expectDeep(
              ColorFormatCSS.parse('rgba(192, 192, 192, 1)')!.rgba,
              RGBA(192, 192, 192, 1),
            );

            expectDeep(
              ColorFormatCSS.parse('rgba(128, 128, 128, 1)')!.rgba,
              RGBA(128, 128, 128, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(128, 0, 0, 1)')!.rgba,
              RGBA(128, 0, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(128, 128, 0, 1)')!.rgba,
              RGBA(128, 128, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(0, 128, 0, 1)')!.rgba,
              RGBA(0, 128, 0, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(128, 0, 128, 1)')!.rgba,
              RGBA(128, 0, 128, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(0, 128, 128, 1)')!.rgba,
              RGBA(0, 128, 128, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(0, 0, 128, 1)')!.rgba,
              RGBA(0, 0, 128, 1),
            );

            expectDeep(
              ColorFormatCSS.parse('rgba(1, 2, 3, 1)')!.rgba,
              RGBA(1, 2, 3, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(4, 5, 6, 1)')!.rgba,
              RGBA(4, 5, 6, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(7, 8, 9, 1)')!.rgba,
              RGBA(7, 8, 9, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(10, 10, 10, 1)')!.rgba,
              RGBA(10, 10, 10, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(11, 11, 11, 1)')!.rgba,
              RGBA(11, 11, 11, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(12, 12, 12, 1)')!.rgba,
              RGBA(12, 12, 12, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(13, 13, 13, 1)')!.rgba,
              RGBA(13, 13, 13, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(14, 14, 14, 1)')!.rgba,
              RGBA(14, 14, 14, 1),
            );
            expectDeep(
              ColorFormatCSS.parse('rgba(15, 15, 15, 1)')!.rgba,
              RGBA(15, 15, 15, 1),
            );
          });
        });

        test('parseHex', () {
          // invalid
          expectDeep(ColorFormatCSS.parseHex(''), null);
          expectDeep(ColorFormatCSS.parseHex('#'), null);
          expectDeep(ColorFormatCSS.parseHex('#0102030'), null);

          // somewhat valid
          expectDeep(
            ColorFormatCSS.parseHex('#FFFFG0')!.rgba,
            RGBA(255, 255, 0, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#FFFFg0')!.rgba,
            RGBA(255, 255, 0, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#-FFF00')!.rgba,
            RGBA(15, 255, 0, 1),
          );

          // valid
          expectDeep(
            ColorFormatCSS.parseHex('#000000')!.rgba,
            RGBA(0, 0, 0, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#FFFFFF')!.rgba,
            RGBA(255, 255, 255, 1),
          );

          expectDeep(
            ColorFormatCSS.parseHex('#FF0000')!.rgba,
            RGBA(255, 0, 0, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#00FF00')!.rgba,
            RGBA(0, 255, 0, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#0000FF')!.rgba,
            RGBA(0, 0, 255, 1),
          );

          expectDeep(
            ColorFormatCSS.parseHex('#FFFF00')!.rgba,
            RGBA(255, 255, 0, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#00FFFF')!.rgba,
            RGBA(0, 255, 255, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#FF00FF')!.rgba,
            RGBA(255, 0, 255, 1),
          );

          expectDeep(
            ColorFormatCSS.parseHex('#C0C0C0')!.rgba,
            RGBA(192, 192, 192, 1),
          );

          expectDeep(
            ColorFormatCSS.parseHex('#808080')!.rgba,
            RGBA(128, 128, 128, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#800000')!.rgba,
            RGBA(128, 0, 0, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#808000')!.rgba,
            RGBA(128, 128, 0, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#008000')!.rgba,
            RGBA(0, 128, 0, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#800080')!.rgba,
            RGBA(128, 0, 128, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#008080')!.rgba,
            RGBA(0, 128, 128, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#000080')!.rgba,
            RGBA(0, 0, 128, 1),
          );

          expectDeep(
            ColorFormatCSS.parseHex('#010203')!.rgba,
            RGBA(1, 2, 3, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#040506')!.rgba,
            RGBA(4, 5, 6, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#070809')!.rgba,
            RGBA(7, 8, 9, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#0a0A0a')!.rgba,
            RGBA(10, 10, 10, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#0b0B0b')!.rgba,
            RGBA(11, 11, 11, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#0c0C0c')!.rgba,
            RGBA(12, 12, 12, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#0d0D0d')!.rgba,
            RGBA(13, 13, 13, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#0e0E0e')!.rgba,
            RGBA(14, 14, 14, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#0f0F0f')!.rgba,
            RGBA(15, 15, 15, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#a0A0a0')!.rgba,
            RGBA(160, 160, 160, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#CFA')!.rgba,
            RGBA(204, 255, 170, 1),
          );
          expectDeep(
            ColorFormatCSS.parseHex('#CFA8')!.rgba,
            RGBA(204, 255, 170, 0.533),
          );
        });

        group('format', () {
          test('formatHSL should use whole numbers for percentages', () {
            // Test case matching the issue: color with fractional percentages that should be rounded
            final color1 = Color.fromHSLA(
              HSLA(0, 0.857, 0.437, 1),
            ); // Should format as hsl(0, 86%, 44%)
            expect(ColorFormatCSS.formatHSL(color1), 'hsl(0, 86%, 44%)');

            // Test edge cases
            final color2 = Color.fromHSLA(
              HSLA(120, 0.5, 0.75, 1),
            ); // Should format as hsl(120, 50%, 75%)
            expect(ColorFormatCSS.formatHSL(color2), 'hsl(120, 50%, 75%)');

            // Test case with values that would round differently
            final color3 = Color.fromHSLA(
              HSLA(240, 0.334, 0.666, 1),
            ); // Should format as hsl(240, 33%, 67%)
            expect(ColorFormatCSS.formatHSL(color3), 'hsl(240, 33%, 67%)');
          });

          test('formatHSLA should use whole numbers for percentages', () {
            // Test case with alpha
            final color1 = Color.fromHSLA(
              HSLA(0, 0.857, 0.437, 0.85),
            ); // Should format as hsla(0, 86%, 44%, 0.85)
            expect(
              ColorFormatCSS.formatHSLA(color1),
              'hsla(0, 86%, 44%, 0.85)',
            );

            // Test edge cases
            final color2 = Color.fromHSLA(
              HSLA(180, 0.25, 0.5, 0.5),
            ); // Should format as hsla(180, 25%, 50%, 0.50)
            expect(
              ColorFormatCSS.formatHSLA(color2),
              'hsla(180, 25%, 50%, 0.50)',
            );
          });
        });
      });
    });

    // https://github.com/xtermjs/xterm.js/blob/44f9fa39ae03e2ca6d28354d88a399608686770e/src/common/Color.test.ts#L355
    group('ensureContrastRatio', () {
      test('should return undefined if the color already meets the contrast ratio (black bg)', () {
        assertContrastRatio(0x000000ff, 0x606060ff, 1, null);
        assertContrastRatio(0x000000ff, 0x606060ff, 2, null);
        assertContrastRatio(0x000000ff, 0x606060ff, 3, null);
      });
      test(
        'should return a color that meets the contrast ratio (black bg)',
        () {
          assertContrastRatio(0x000000ff, 0x606060ff, 4, 0x707070ff);
          assertContrastRatio(0x000000ff, 0x606060ff, 5, 0x7f7f7fff);
          assertContrastRatio(0x000000ff, 0x606060ff, 6, 0x8c8c8cff);
          assertContrastRatio(0x000000ff, 0x606060ff, 7, 0x989898ff);
          assertContrastRatio(0x000000ff, 0x606060ff, 8, 0xa3a3a3ff);
          assertContrastRatio(0x000000ff, 0x606060ff, 9, 0xadadadff);
          assertContrastRatio(0x000000ff, 0x606060ff, 10, 0xb6b6b6ff);
          assertContrastRatio(0x000000ff, 0x606060ff, 11, 0xbebebeff);
          assertContrastRatio(0x000000ff, 0x606060ff, 12, 0xc5c5c5ff);
          assertContrastRatio(0x000000ff, 0x606060ff, 13, 0xd1d1d1ff);
          assertContrastRatio(0x000000ff, 0x606060ff, 14, 0xd6d6d6ff);
          assertContrastRatio(0x000000ff, 0x606060ff, 15, 0xdbdbdbff);
          assertContrastRatio(0x000000ff, 0x606060ff, 16, 0xe3e3e3ff);
          assertContrastRatio(0x000000ff, 0x606060ff, 17, 0xe9e9e9ff);
          assertContrastRatio(0x000000ff, 0x606060ff, 18, 0xeeeeeeff);
          assertContrastRatio(0x000000ff, 0x606060ff, 19, 0xf4f4f4ff);
          assertContrastRatio(0x000000ff, 0x606060ff, 20, 0xfafafaff);
          assertContrastRatio(0x000000ff, 0x606060ff, 21, 0xffffffff);
        },
      );
      test('should return undefined if the color already meets the contrast ratio (white bg)', () {
        assertContrastRatio(0xffffffff, 0x606060ff, 1, null);
        assertContrastRatio(0xffffffff, 0x606060ff, 2, null);
        assertContrastRatio(0xffffffff, 0x606060ff, 3, null);
        assertContrastRatio(0xffffffff, 0x606060ff, 4, null);
        assertContrastRatio(0xffffffff, 0x606060ff, 5, null);
        assertContrastRatio(0xffffffff, 0x606060ff, 6, null);
      });
      test(
        'should return a color that meets the contrast ratio (white bg)',
        () {
          assertContrastRatio(0xffffffff, 0x606060ff, 7, 0x565656ff);
          assertContrastRatio(0xffffffff, 0x606060ff, 8, 0x4d4d4dff);
          assertContrastRatio(0xffffffff, 0x606060ff, 9, 0x454545ff);
          assertContrastRatio(0xffffffff, 0x606060ff, 10, 0x3e3e3eff);
          assertContrastRatio(0xffffffff, 0x606060ff, 11, 0x373737ff);
          assertContrastRatio(0xffffffff, 0x606060ff, 12, 0x313131ff);
          assertContrastRatio(0xffffffff, 0x606060ff, 13, 0x313131ff);
          assertContrastRatio(0xffffffff, 0x606060ff, 14, 0x272727ff);
          assertContrastRatio(0xffffffff, 0x606060ff, 15, 0x232323ff);
          assertContrastRatio(0xffffffff, 0x606060ff, 16, 0x1f1f1fff);
          assertContrastRatio(0xffffffff, 0x606060ff, 17, 0x1b1b1bff);
          assertContrastRatio(0xffffffff, 0x606060ff, 18, 0x151515ff);
          assertContrastRatio(0xffffffff, 0x606060ff, 19, 0x101010ff);
          assertContrastRatio(0xffffffff, 0x606060ff, 20, 0x080808ff);
          assertContrastRatio(0xffffffff, 0x606060ff, 21, 0x000000ff);
        },
      );
    });
  });
}
