// Copyright (c) 2026 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js addons/addon-webgl/test/WebglCustomGlyphs.test.ts
// (c58ea36), with pixel checks of CustomGlyphRasterizer.ts' geometry.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/terminal_custom_glyphs.dart';
import 'package:monad/ide/terminal/xterm/addons/addon_webgl/custom_glyphs/custom_glyph_definitions.dart';
import 'package:monad/ide/terminal/xterm/addons/addon_webgl/custom_glyphs/types.dart';

const _white = Color(0xFFFFFFFF);

/// A painted image, in device pixels.
class _Pixels {
  _Pixels(this.width, this.height, this.data);

  final int width;
  final int height;
  final ByteData data;

  int alpha(int x, int y) => data.getUint8((y * width + x) * 4 + 3);

  /// The (premultiplied) RGBA at a pixel.
  int rgba(int x, int y) => data.getUint32((y * width + x) * 4);

  bool on(int x, int y) => alpha(x, y) > 200;

  bool off(int x, int y) => alpha(x, y) < 56;

  bool anyIn(int left, int top, int right, int bottom) {
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        if (alpha(x, y) > 0) return true;
      }
    }
    return false;
  }
}

Future<_Pixels> _paint(
  void Function(Canvas canvas) paint,
  int width,
  int height, {
  double devicePixelRatio = 1,
}) async {
  final recorder = ui.PictureRecorder();
  // As a Flutter canvas: logical pixels, scaled to device pixels.
  final canvas = Canvas(recorder)..scale(devicePixelRatio);
  paint(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return _Pixels(width, height, data!);
}

/// [codePoint] in white in a [width] x [height] cell at the origin.
Future<_Pixels> _glyph(
  int codePoint, {
  double width = 10,
  double height = 20,
  double devicePixelRatio = 1,
  Size? charSize,
  Color? backgroundColor,
  int? variantOffset,
}) => _paint(
  (canvas) => paintCustomGlyph(
    canvas,
    codePoint,
    Rect.fromLTWH(0, 0, width, height),
    _white,
    devicePixelRatio: devicePixelRatio,
    fontSize: 12,
    charSize: charSize,
    backgroundColor: backgroundColor,
    variantOffset: variantOffset,
  ),
  (width * devicePixelRatio).round(),
  (height * devicePixelRatio).round(),
  devicePixelRatio: devicePixelRatio,
);

/// The path instructions of a part, with sample cell proportions for the
/// generated ones.
List<String> _instructions(Object data) => switch (data) {
  final String d => d.split(' '),
  final String Function(double, double) f => f(.15, .075).split(' '),
  _ => throw ArgumentError(data),
};

const _argCounts = {
  'M': 2,
  'L': 2,
  'T': 2,
  'Q': 4,
  'C': 6,
  'A': 7,
  'V': 1,
  'H': 1,
  'Z': 0,
};

void main() {
  group('customGlyphDefinitions', () {
    test('has every upstream definition', () {
      // 522 written out upstream, and the 256 braille patterns.
      expect(customGlyphDefinitions, hasLength(778));
      for (var i = 0x2500; i <= 0x257F; i++) {
        expect(isCustomGlyph(i), isTrue, reason: 'U+${i.toRadixString(16)}');
      }
      for (var i = 0x2800; i <= 0x28FF; i++) {
        expect(isCustomGlyph(i), isTrue);
      }
      for (var i = 0x1FB00; i <= 0x1FB3B; i++) {
        expect(isCustomGlyph(i), isTrue);
      }
      expect(isCustomGlyph(0xE0B0), isTrue);
      expect(isCustomGlyph(0xF5EE), isTrue);
      expect(isCustomGlyph(0x1FBFA), isTrue);
      // Reserved or unused upstream.
      expect(isCustomGlyph(0x1FB93), isFalse);
      expect(isCustomGlyph(0xE0C9), isFalse);
      expect(isCustomGlyph(0x41), isFalse);
    });

    test('keys are single characters', () {
      for (final key in customGlyphDefinitions.keys) {
        expect(key.runes, hasLength(1), reason: key);
      }
    });

    test('data is what the part type says', () {
      for (final MapEntry(:key, :value) in customGlyphDefinitions.entries) {
        expect(value, isNotEmpty);
        for (final part in value) {
          final data = part.data;
          final matches = switch (part.type) {
            CustomGlyphDefinitionType.solidOctantBlockVector =>
              data is List<ICustomGlyphSolidOctantBlockVector>,
            CustomGlyphDefinitionType.blockPattern =>
              data is CustomGlyphPatternDefinition,
            CustomGlyphDefinitionType.pathFunction =>
              data is String || data is CustomGlyphPathDrawFunctionDefinition,
            CustomGlyphDefinitionType.path =>
              data is String || data is CustomGlyphPathDrawFunctionDefinition,
            CustomGlyphDefinitionType.pathNegative ||
            CustomGlyphDefinitionType.vectorShape =>
              data is ICustomGlyphVectorShape,
            CustomGlyphDefinitionType.braille => data is int,
          };
          expect(matches, isTrue, reason: '$key ${part.type}');
        }
      }
    });

    test('paths use only the commands their drawer knows', () {
      void check(String key, List<String> instructions, String commands) {
        for (final instruction in instructions) {
          final command = instruction[0];
          expect(commands, contains(command), reason: '$key $instruction');
          final args = instruction.substring(1);
          expect(
            args.isEmpty ? 0 : args.split(',').length,
            _argCounts[command],
            reason: '$key $instruction',
          );
        }
      }

      for (final MapEntry(:key, :value) in customGlyphDefinitions.entries) {
        for (final part in value) {
          final data = part.data;
          switch (part.type) {
            case CustomGlyphDefinitionType.pathFunction:
              check(key, _instructions(data), 'MLQTCZ');
            case CustomGlyphDefinitionType.path:
              check(key, _instructions(data), 'MLQTCAVHZ');
            case CustomGlyphDefinitionType.pathNegative:
              check(
                key,
                _instructions((data as ICustomGlyphVectorShape).d),
                'MLZ',
              );
            case CustomGlyphDefinitionType.vectorShape:
              check(
                key,
                _instructions((data as ICustomGlyphVectorShape).d),
                'MLQTCZ',
              );
            default:
          }
          if (part.clipPath case final clipPath?) {
            check(key, clipPath.split(' '), 'MLZ');
          }
        }
      }
    });

    test('blockPatternCodepoints are the glyphs with patterns', () {
      final withPatterns = {
        for (final MapEntry(:key, :value) in customGlyphDefinitions.entries)
          if (value.any(
            (p) => p.type == CustomGlyphDefinitionType.blockPattern,
          ))
            key.runes.single,
      };
      expect(blockPatternCodepoints, withPatterns);
    });
  });

  group('paintCustomGlyph', () {
    test('paints nothing for other characters', () async {
      late bool painted;
      final pixels = await _paint(
        (canvas) => painted = paintCustomGlyph(
          canvas,
          0x41,
          const Rect.fromLTWH(0, 0, 10, 20),
          _white,
          devicePixelRatio: 1,
          fontSize: 12,
        ),
        10,
        20,
      );
      expect(painted, isFalse);
      expect(pixels.anyIn(0, 0, 10, 20), isFalse);
    });

    test('─ reaches the left and right edges on the middle row', () async {
      final pixels = await _glyph(0x2500);
      // Snapped to the pixel row under the middle, 1px thick.
      expect(pixels.on(0, 10), isTrue);
      expect(pixels.on(9, 10), isTrue);
      expect(pixels.off(0, 9), isTrue);
      expect(pixels.off(9, 11), isTrue);
      expect(pixels.off(5, 2), isTrue);
    });

    test('│ reaches the top and bottom edges', () async {
      final pixels = await _glyph(0x2502);
      expect(pixels.on(5, 0), isTrue);
      expect(pixels.on(5, 19), isTrue);
      expect(pixels.off(4, 10), isTrue);
      expect(pixels.off(6, 10), isTrue);
    });

    test('━ is 3px thick', () async {
      final pixels = await _glyph(0x2501);
      for (final y in [9, 10, 11]) {
        expect(pixels.on(0, y), isTrue);
        expect(pixels.on(9, y), isTrue);
      }
      expect(pixels.off(5, 8), isTrue);
      expect(pixels.off(5, 12), isTrue);
    });

    test('─ reaches both edges at devicePixelRatio 2', () async {
      final pixels = await _glyph(0x2500, devicePixelRatio: 2);
      // 2 device pixels thick around the half pixel under the middle.
      expect(pixels.on(0, 20), isTrue);
      expect(pixels.on(19, 20), isTrue);
      expect(pixels.off(10, 17), isTrue);
      expect(pixels.off(10, 23), isTrue);
    });

    test('═ draws two lines 15% of the cell width apart', () async {
      final pixels = await _glyph(0x2550);
      // .5 ∓ .15 / 20 * 10 of the height: rows 8 and 11.
      expect(pixels.on(0, 8), isTrue);
      expect(pixels.on(9, 11), isTrue);
      expect(pixels.off(5, 9), isTrue);
      expect(pixels.off(5, 10), isTrue);
    });

    test('█ fills the cell', () async {
      final pixels = await _glyph(0x2588);
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 10; x++) {
          expect(pixels.on(x, y), isTrue, reason: '($x, $y)');
        }
      }
    });

    test('█ fills the cell at devicePixelRatio 1.5', () async {
      final pixels = await _glyph(0x2588, devicePixelRatio: 1.5);
      expect(pixels.on(0, 0), isTrue);
      expect(pixels.on(14, 29), isTrue);
      expect(pixels.on(7, 15), isTrue);
    });

    test('▀ fills the upper half', () async {
      final pixels = await _glyph(0x2580);
      expect(pixels.on(0, 0), isTrue);
      expect(pixels.on(9, 9), isTrue);
      expect(pixels.off(0, 10), isTrue);
      expect(pixels.off(9, 19), isTrue);
    });

    test('the Powerline triangle U+E0B0 fills from the left edge', () async {
      final pixels = await _glyph(0xE0B0);
      expect(pixels.on(0, 1), isTrue);
      expect(pixels.on(0, 10), isTrue);
      expect(pixels.on(0, 18), isTrue);
      expect(pixels.on(7, 10), isTrue);
      expect(pixels.off(9, 0), isTrue);
      expect(pixels.off(9, 19), isTrue);
      // Its tip stops short of the right edge by fontSize / 12.
      expect(pixels.off(9, 10), isTrue);
    });

    test('sextant U+1FB00 fills the upper left sixth', () async {
      final pixels = await _glyph(0x1FB00);
      expect(pixels.on(0, 0), isTrue);
      expect(pixels.on(4, 6), isTrue);
      // Path functions snap to half pixels, fills too: the right edge at 5.5,
      // the bottom at 7.5.
      expect(pixels.alpha(5, 2), inInclusiveRange(100, 155));
      expect(pixels.alpha(2, 7), inInclusiveRange(100, 155));
      expect(pixels.off(6, 2), isTrue);
      expect(pixels.off(2, 8), isTrue);
    });

    test('braille ⣿ has eight dots, ⠀ none', () async {
      final full = await _glyph(0x28FF);
      // Dot centers: x at 2/8 and 6/8 of 10, y at 2 + (1, 3, 5, 7) * 2.
      for (final x in [2, 7]) {
        for (final y in [4, 8, 12, 16]) {
          expect(full.alpha(x, y), greaterThan(0), reason: '($x, $y)');
        }
      }
      expect(full.off(5, 10), isTrue);
      final blank = await _glyph(0x2800);
      expect(blank.anyIn(0, 0, 10, 20), isFalse);
    });

    // Adapted from WebglCustomGlyphs.test.ts "pattern glyphs render": the
    // shades are drawn without a pattern canvas.
    test('shades ░ ▒ ▓ are their pixel patterns', () async {
      final light = await _glyph(0x2591);
      final medium = await _glyph(0x2592);
      final dark = await _glyph(0x2593);
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 10; x++) {
          expect(light.on(x, y), x.isEven && y.isEven, reason: '░ ($x, $y)');
          expect(medium.on(x, y), (x + y).isEven, reason: '▒ ($x, $y)');
          expect(dark.on(x, y), !(x.isOdd && y.isOdd), reason: '▓ ($x, $y)');
          expect(medium.on(x, y) || medium.off(x, y), isTrue);
        }
      }
    });

    test('shades tile across cells of odd sizes', () async {
      final pixels = await _paint(
        (canvas) {
          for (var row = 0; row < 2; row++) {
            for (var column = 0; column < 2; column++) {
              paintCustomGlyph(
                canvas,
                0x2592,
                Rect.fromLTWH(column * 9, row * 19, 9, 19),
                _white,
                devicePixelRatio: 1,
                fontSize: 12,
              );
            }
          }
        },
        18,
        38,
      );
      for (var y = 0; y < 38; y++) {
        for (var x = 0; x < 18; x++) {
          expect(pixels.on(x, y), (x + y).isEven, reason: '($x, $y)');
        }
      }
    });

    test('variantOffset shifts the shade in its cell', () async {
      // Upstream's offset for the cell at column 1 of 9px cells: x shift.
      final pixels = await _paint(
        (canvas) => paintCustomGlyph(
          canvas,
          0x2592,
          const Rect.fromLTWH(0, 0, 9, 19),
          _white,
          devicePixelRatio: 1,
          fontSize: 12,
          variantOffset: 2,
        ),
        9,
        19,
      );
      for (var y = 0; y < 19; y++) {
        for (var x = 0; x < 9; x++) {
          expect(pixels.on(x, y), (x + y).isOdd, reason: '($x, $y)');
        }
      }
    });

    test('clip paths restrict the shade to half the cell', () async {
      // LEFT HALF MEDIUM SHADE.
      final pixels = await _glyph(0x1FB8C);
      expect(pixels.on(0, 0), isTrue);
      expect(pixels.on(4, 2), isTrue);
      expect(pixels.anyIn(5, 0, 10, 20), isFalse);
    });

    test('negative glyphs draw their shape in the background', () async {
      const background = Color(0xFF191A1B);
      // NEGATIVE DIAGONAL CROSS: a filled cell crossed out.
      // At devicePixelRatio 4 its 4px strokes cover the middle.
      final drawn = await _glyph(
        0x1FBBD,
        devicePixelRatio: 4,
        backgroundColor: background,
      );
      expect(drawn.rgba(19, 39), 0x191A1BFF);
      expect(drawn.rgba(20, 40), 0x191A1BFF);
      expect(drawn.rgba(20, 8), 0xFFFFFFFF);
      final cut = await _glyph(0x1FBBD, devicePixelRatio: 4);
      expect(cut.alpha(19, 39), 0);
      expect(cut.alpha(20, 40), 0);
      expect(cut.rgba(20, 8), 0xFFFFFFFF);
    });

    test('char-scaled glyphs stay in the character area', () async {
      // ARROWHEAD-SHAPED POINTER, in a 6x10 character centered in the cell.
      final pixels = await _glyph(0x1FBB0, charSize: const Size(6, 10));
      expect(pixels.anyIn(2, 5, 8, 15), isTrue);
      expect(pixels.anyIn(0, 0, 10, 5), isFalse);
      expect(pixels.anyIn(0, 15, 10, 20), isFalse);
      expect(pixels.anyIn(0, 0, 2, 20), isFalse);
      expect(pixels.anyIn(8, 0, 10, 20), isFalse);
    });

    test('every glyph paints in its cell', () async {
      final codePoints = [
        for (final key in customGlyphDefinitions.keys) key.runes.single,
      ];
      const columns = 32;
      // Cells 10x20 with as much room between them, which some paths reach.
      final pixels = await _paint(
        (canvas) {
          for (var i = 0; i < codePoints.length; i++) {
            final painted = paintCustomGlyph(
              canvas,
              codePoints[i],
              Rect.fromLTWH(
                i % columns * 20 + 5,
                i ~/ columns * 40 + 10,
                10,
                20,
              ),
              _white,
              devicePixelRatio: 1,
              fontSize: 12,
            );
            expect(painted, isTrue);
          }
        },
        columns * 20,
        (codePoints.length / columns).ceil() * 40,
      );
      for (var i = 0; i < codePoints.length; i++) {
        final left = i % columns * 20 + 5;
        final top = i ~/ columns * 40 + 10;
        if (codePoints[i] == 0x2800) continue; // BRAILLE PATTERN BLANK
        expect(
          pixels.anyIn(left, top, left + 10, top + 20),
          isTrue,
          reason: 'U+${codePoints[i].toRadixString(16).toUpperCase()}',
        );
      }
    });
  });
}
