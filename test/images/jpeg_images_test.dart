import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:baocode/images/jpeg_images.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A page-like picture: bands of colour, a gradient, lines of "text" and
/// some noise, so that its PNG is past the size [pngAsJpeg] starts at.
img.Image _page(
  int width,
  int height, {
  int numChannels = 3,
  img.Format format = img.Format.uint8,
}) {
  final image = img.Image(
    width: width,
    height: height,
    numChannels: numChannels,
    format: format,
  );
  final random = Random(7);
  final max = image.maxChannelValue;
  for (final pixel in image) {
    final x = pixel.x;
    final y = pixel.y;
    final text = (y ~/ 6).isEven && (x ~/ 3) % 4 != 0 && y % 120 < 60;
    final base = text ? 0.1 : (x / width) * 0.6 + 0.3;
    final noise = random.nextDouble() * 0.04;
    pixel
      ..r = ((base + noise).clamp(0, 1) * max)
      ..g = ((y % 200 < 100 ? base : 1 - base) * max)
      ..b = (((x + y) % 255) / 255 * max);
    if (numChannels == 4) pixel.a = max;
  }
  return image;
}

Future<(int, int, Uint8List)> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  final result = (image.width, image.height, data!.buffer.asUint8List());
  image.dispose();
  codec.dispose();
  return result;
}

/// The mean difference of [png]'s pixels and [jpeg]'s, out of 255.
Future<double> _difference(Uint8List png, Uint8List jpeg) async {
  final (w1, h1, a) = await _decode(png);
  final (w2, h2, b) = await _decode(jpeg);
  expect((w2, h2), (w1, h1));
  var sum = 0;
  for (var i = 0; i < a.length; i++) {
    if (i % 4 == 3) continue;
    sum += (a[i] - b[i]).abs();
  }
  return sum / (a.length * 3 / 4);
}

bool _isJpeg(Uint8List bytes) =>
    bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;

void main() {
  Future<Uint8List?> convert(WidgetTester tester, Uint8List png) async =>
      tester.runAsync<Uint8List?>(() => pngAsJpeg(png));

  testWidgets('an opaque PNG goes as a smaller JPEG, the same to the eye', (
    tester,
  ) async {
    final png = img.encodePng(_page(800, 500));
    expect(png.length, greaterThan(64 * 1024));
    final jpeg = await convert(tester, png);
    expect(jpeg, isNotNull);
    expect(_isJpeg(jpeg!), isTrue);
    expect(jpeg.length, lessThan(png.length));
    final difference = await tester.runAsync(() => _difference(png, jpeg));
    expect(difference, lessThan(4));
  });

  testWidgets('every kind of opaque PNG: RGBA, grey, palette, 16-bit', (
    tester,
  ) async {
    final page = _page(800, 500);
    final kinds = {
      'rgba': _page(800, 500, numChannels: 4),
      'grey': page.convert(numChannels: 1),
      'palette': img.quantize(page, numberOfColors: 256),
      '16-bit': _page(800, 500, format: img.Format.uint16),
    };
    for (final MapEntry(key: kind, value: image) in kinds.entries) {
      final png = img.encodePng(image);
      final jpeg = await convert(tester, png);
      if (jpeg == null) {
        // Kept: allowed (as when no smaller), never broken.
        expect(png.length, lessThan(300 * 1024), reason: kind);
        continue;
      }
      final difference = await tester.runAsync(() => _difference(png, jpeg));
      expect(difference, lessThan(6), reason: kind);
    }
  });

  testWidgets('kept: any transparency, small, not a PNG, animated', (
    tester,
  ) async {
    final clear = _page(800, 500, numChannels: 4);
    clear.getPixel(10, 10).a = 0;
    expect(await convert(tester, img.encodePng(clear)), isNull);

    final half = _page(800, 500, numChannels: 4);
    half.getPixel(400, 300).a = 200;
    expect(await convert(tester, img.encodePng(half)), isNull);

    expect(await convert(tester, img.encodePng(_page(60, 40))), isNull);

    final jpeg = img.encodeJpg(_page(800, 500));
    expect(await convert(tester, jpeg), isNull);

    final animated = _page(600, 400)..addFrame(_page(600, 400));
    expect(await convert(tester, img.encodePng(animated)), isNull);
  });

  testWidgets('kept when no smaller as JPEG: a picture of few colours', (
    tester,
  ) async {
    final png = img.encodePng(img.quantize(_page(800, 500)));
    expect(png.length, greaterThan(64 * 1024));
    expect(await convert(tester, png), isNull);
  });

  testWidgets('broken PNGs: kept, or a JPEG that decodes, never thrown', (
    tester,
  ) async {
    final png = img.encodePng(_page(800, 500));
    final broken = [
      png.sublist(0, png.length ~/ 2),
      png.sublist(0, 40),
      Uint8List.fromList([...png.sublist(0, 8), ...List.filled(90000, 7)]),
      Uint8List.fromList([
        ...png.sublist(0, 100),
        ...List.filled(5000, 0),
        ...png.sublist(5100),
      ]),
    ];
    for (final bytes in broken) {
      final jpeg = await convert(tester, bytes);
      if (jpeg == null) continue;
      expect(_isJpeg(jpeg), isTrue);
      await tester.runAsync(() => _decode(jpeg));
    }
  });

  testWidgets('a wide-gamut PNG (Display P3) decodes as Flutter shows it', (
    tester,
  ) async {
    final profile = File('/System/Library/ColorSync/Profiles/Display P3.icc');
    if (!profile.existsSync()) return;
    final image = _page(800, 500)
      ..iccProfile = img.IccProfile(
        'Display P3',
        img.IccProfileCompression.none,
        profile.readAsBytesSync(),
      );
    final png = img.encodePng(image);
    final jpeg = await convert(tester, png);
    expect(jpeg, isNotNull);
    final difference = await tester.runAsync(() => _difference(png, jpeg!));
    expect(difference, lessThan(4));
  });

  testWidgets('a large screenshot, off the UI isolate', (tester) async {
    final png = img.encodePng(_page(2844, 1474));
    final jpeg = await convert(tester, png);
    expect(jpeg, isNotNull);
    expect(jpeg!.length, lessThan(png.length ~/ 2));
  });
}
