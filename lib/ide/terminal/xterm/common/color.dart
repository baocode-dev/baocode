// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/Color.ts (c58ea36).
//
// Upstream's namespaces `channels`, `color`, `css`, `rgb` and `rgba` are
// classes of static members under the same lower-case names, so call sites
// read `css.toColor('#fff')` as upstream's do. `css.toColor` has no canvas to
// fall back on, so like upstream under Node.js it supports `#rgb[a]`,
// `#rrggbb[aa]`, `rgb()`, `rgba()` and `transparent` only.

// ignore_for_file: camel_case_types

import 'dart:math' as math;

import 'types.dart';

const IColor nullColor = IColor(css: '#00000000', rgba: 0);

/// JavaScript's `Math.round`: halves round towards +∞.
int _round(double x) {
  final floor = x.floorToDouble();
  return (x - floor >= 0.5 ? floor + 1 : floor).toInt();
}

/// JavaScript's `parseInt(s, 16)` of a hex prefix; 0 where it would be NaN
/// (every use feeds bit operations, which treat NaN as 0).
int _parseHexPrefix(String s) {
  var end = 0;
  while (end < s.length && _isHexDigit(s.codeUnitAt(end))) {
    end++;
  }
  return end == 0 ? 0 : int.parse(s.substring(0, end), radix: 16);
}

bool _isHexDigit(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x46) ||
    (c >= 0x61 && c <= 0x66);

/// Helper functions where the source type is "channels" (individual color
/// channels as numbers).
abstract final class channels {
  static String toCss(int r, int g, int b, [int? a]) {
    if (a != null) {
      return '#${toPaddedHex(r)}${toPaddedHex(g)}${toPaddedHex(b)}'
          '${toPaddedHex(a)}';
    }
    return '#${toPaddedHex(r)}${toPaddedHex(g)}${toPaddedHex(b)}';
  }

  static int toRgba(int r, int g, int b, [int? a]) {
    a ??= 0xFF;
    // Note: The aggregated number is RGBA32 (BE), thus needs to be converted to
    // ABGR32 on LE systems, before it can be used for direct 32-bit buffer
    // writes. The mask forces an unsigned 32-bit int.
    return ((r << 24) | (g << 16) | (b << 8) | a) & 0xFFFFFFFF;
  }

  static IColor toColor(int r, int g, int b, [int? a]) {
    return IColor(
      css: channels.toCss(r, g, b, a),
      rgba: channels.toRgba(r, g, b, a),
    );
  }
}

/// Helper functions where the source type is `IColor`.
abstract final class color {
  static IColor blend(IColor bg, IColor fg) {
    final a = (fg.rgba & 0xFF) / 255;
    if (a == 1) {
      return IColor(css: fg.css, rgba: fg.rgba);
    }
    final fgR = (fg.rgba >> 24) & 0xFF;
    final fgG = (fg.rgba >> 16) & 0xFF;
    final fgB = (fg.rgba >> 8) & 0xFF;
    final bgR = (bg.rgba >> 24) & 0xFF;
    final bgG = (bg.rgba >> 16) & 0xFF;
    final bgB = (bg.rgba >> 8) & 0xFF;
    final r = bgR + _round((fgR - bgR) * a);
    final g = bgG + _round((fgG - bgG) * a);
    final b = bgB + _round((fgB - bgB) * a);
    final css = channels.toCss(r, g, b);
    final rgba = channels.toRgba(r, g, b);
    return IColor(css: css, rgba: rgba);
  }

  static bool isOpaque(IColor color) {
    return (color.rgba & 0xFF) == 0xFF;
  }

  static IColor? ensureContrastRatio(IColor bg, IColor fg, double ratio) {
    final result = rgba.ensureContrastRatio(bg.rgba, fg.rgba, ratio);
    if (result == null || result == 0) {
      return null;
    }
    return channels.toColor(
      (result >> 24 & 0xFF),
      (result >> 16 & 0xFF),
      (result >> 8 & 0xFF),
    );
  }

  static IColor opaque(IColor color) {
    final rgbaColor = (color.rgba | 0xFF) & 0xFFFFFFFF;
    final c = rgba.toChannels(rgbaColor);
    return IColor(css: channels.toCss(c[0], c[1], c[2]), rgba: rgbaColor);
  }

  static IColor opacity(IColor color, double opacity) {
    final a = _round(opacity * 0xFF);
    final c = rgba.toChannels(color.rgba);
    return IColor(
      css: channels.toCss(c[0], c[1], c[2], a),
      rgba: channels.toRgba(c[0], c[1], c[2], a),
    );
  }

  static IColor multiplyOpacity(IColor color, double factor) {
    final a = color.rgba & 0xFF;
    return opacity(color, (a * factor) / 0xFF);
  }

  static IColorRGB toColorRGB(IColor color) {
    return <int>[
      (color.rgba >> 24) & 0xFF,
      (color.rgba >> 16) & 0xFF,
      (color.rgba >> 8) & 0xFF,
    ];
  }
}

/// Helper functions where the source type is "css" (string: '#rgb', '#rgba',
/// '#rrggbb', '#rrggbbaa').
abstract final class css {
  static final RegExp _hex = RegExp(r'#[\da-f]{3,8}', caseSensitive: false);
  static final RegExp _rgba = RegExp(
    r'rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(,\s*(0|1|\d?\.(\d+))\s*)?\)',
  );

  /// Converts a css string to an [IColor]; throws for an unsupported format.
  ///
  /// The ideal format to use is `#rrggbb[aa]` as it's the fastest to parse.
  static IColor toColor(String css) {
    // Formats: #rgb[a] and #rrggbb[aa]
    if (_hex.hasMatch(css)) {
      switch (css.length) {
        case 4: // #rgb
          final r = _parseHexPrefix(css.substring(1, 2) * 2);
          final g = _parseHexPrefix(css.substring(2, 3) * 2);
          final b = _parseHexPrefix(css.substring(3, 4) * 2);
          return channels.toColor(r, g, b);
        case 5: // #rgba
          final r = _parseHexPrefix(css.substring(1, 2) * 2);
          final g = _parseHexPrefix(css.substring(2, 3) * 2);
          final b = _parseHexPrefix(css.substring(3, 4) * 2);
          final a = _parseHexPrefix(css.substring(4, 5) * 2);
          return channels.toColor(r, g, b, a);
        case 7: // #rrggbb
          return IColor(
            css: css,
            rgba:
                ((_parseHexPrefix(css.substring(1)) << 8) | 0xFF) & 0xFFFFFFFF,
          );
        case 9: // #rrggbbaa
          return IColor(
            css: css,
            rgba: _parseHexPrefix(css.substring(1)) & 0xFFFFFFFF,
          );
      }
    }

    // Formats: rgb() or rgba()
    final rgbaMatch = _rgba.firstMatch(css);
    if (rgbaMatch != null) {
      final r = int.parse(rgbaMatch.group(1)!);
      final g = int.parse(rgbaMatch.group(2)!);
      final b = int.parse(rgbaMatch.group(3)!);
      final alpha = rgbaMatch.group(5);
      final a = _round((alpha == null ? 1 : double.parse(alpha)) * 0xFF);
      return channels.toColor(r, g, b, a);
    }

    // Handle the "transparent" keyword
    if (css == 'transparent') {
      return const IColor(css: 'transparent', rgba: 0x00000000);
    }

    // Upstream falls back to parsing on a canvas here; Dart has none, as
    // upstream under Node.js.
    throw ArgumentError('css.toColor: Unsupported css format');
  }
}

/// Helper functions where the source type is "rgb" (number: 0xrrggbb).
abstract final class rgb {
  /// Gets the relative luminance of an RGB color, this is useful in
  /// determining the contrast ratio between two colors.
  ///
  /// See https://www.w3.org/TR/WCAG20/#relativeluminancedef
  static double relativeLuminance(int rgb) {
    return relativeLuminance2(
      (rgb >> 16) & 0xFF,
      (rgb >> 8) & 0xFF,
      rgb & 0xFF,
    );
  }

  /// Gets the relative luminance of an RGB color given its channels
  /// (0x00 to 0xFF), this is useful in determining the contrast ratio between
  /// two colors.
  ///
  /// See https://www.w3.org/TR/WCAG20/#relativeluminancedef
  static double relativeLuminance2(int r, int g, int b) {
    final rs = r / 255;
    final gs = g / 255;
    final bs = b / 255;
    final rr = rs <= 0.03928
        ? rs / 12.92
        : math.pow((rs + 0.055) / 1.055, 2.4).toDouble();
    final rg = gs <= 0.03928
        ? gs / 12.92
        : math.pow((gs + 0.055) / 1.055, 2.4).toDouble();
    final rb = bs <= 0.03928
        ? bs / 12.92
        : math.pow((bs + 0.055) / 1.055, 2.4).toDouble();
    return rr * 0.2126 + rg * 0.7152 + rb * 0.0722;
  }
}

/// Helper functions where the source type is "rgba" (number: 0xrrggbbaa).
abstract final class rgba {
  static int blend(int bg, int fg) {
    final a = (fg & 0xFF) / 0xFF;
    if (a == 1) {
      return fg;
    }
    final fgR = (fg >> 24) & 0xFF;
    final fgG = (fg >> 16) & 0xFF;
    final fgB = (fg >> 8) & 0xFF;
    final bgR = (bg >> 24) & 0xFF;
    final bgG = (bg >> 16) & 0xFF;
    final bgB = (bg >> 8) & 0xFF;
    final r = bgR + _round((fgR - bgR) * a);
    final g = bgG + _round((fgG - bgG) * a);
    final b = bgB + _round((fgB - bgB) * a);
    return channels.toRgba(r, g, b);
  }

  /// Given a foreground color and a background color, either increase or
  /// reduce the luminance of the foreground color until the specified contrast
  /// ratio is met. If pure white or black is hit without the contrast ratio
  /// being met, go the other direction using the background color as the
  /// foreground color and take either the first or second result depending on
  /// which has the higher contrast ratio.
  ///
  /// Returns null if the contrast ratio is already met.
  static int? ensureContrastRatio(int bgRgba, int fgRgba, double ratio) {
    final bgL = rgb.relativeLuminance(bgRgba >> 8);
    final fgL = rgb.relativeLuminance(fgRgba >> 8);
    final cr = contrastRatio(bgL, fgL);
    if (cr < ratio) {
      if (fgL < bgL) {
        final resultA = reduceLuminance(bgRgba, fgRgba, ratio);
        final resultARatio = contrastRatio(
          bgL,
          rgb.relativeLuminance(resultA >> 8),
        );
        if (resultARatio < ratio) {
          final resultB = increaseLuminance(bgRgba, fgRgba, ratio);
          final resultBRatio = contrastRatio(
            bgL,
            rgb.relativeLuminance(resultB >> 8),
          );
          return resultARatio > resultBRatio ? resultA : resultB;
        }
        return resultA;
      }
      final resultA = increaseLuminance(bgRgba, fgRgba, ratio);
      final resultARatio = contrastRatio(
        bgL,
        rgb.relativeLuminance(resultA >> 8),
      );
      if (resultARatio < ratio) {
        final resultB = reduceLuminance(bgRgba, fgRgba, ratio);
        final resultBRatio = contrastRatio(
          bgL,
          rgb.relativeLuminance(resultB >> 8),
        );
        return resultARatio > resultBRatio ? resultA : resultB;
      }
      return resultA;
    }
    return null;
  }

  static int reduceLuminance(int bgRgba, int fgRgba, double ratio) {
    // This is a naive but fast approach to reducing luminance as converting to
    // HSL and back is expensive
    final bgR = (bgRgba >> 24) & 0xFF;
    final bgG = (bgRgba >> 16) & 0xFF;
    final bgB = (bgRgba >> 8) & 0xFF;
    var fgR = (fgRgba >> 24) & 0xFF;
    var fgG = (fgRgba >> 16) & 0xFF;
    var fgB = (fgRgba >> 8) & 0xFF;
    var cr = contrastRatio(
      rgb.relativeLuminance2(fgR, fgG, fgB),
      rgb.relativeLuminance2(bgR, bgG, bgB),
    );
    while (cr < ratio && (fgR > 0 || fgG > 0 || fgB > 0)) {
      // Reduce by 10% until the ratio is hit
      fgR -= math.max(0, (fgR * 0.1).ceil());
      fgG -= math.max(0, (fgG * 0.1).ceil());
      fgB -= math.max(0, (fgB * 0.1).ceil());
      cr = contrastRatio(
        rgb.relativeLuminance2(fgR, fgG, fgB),
        rgb.relativeLuminance2(bgR, bgG, bgB),
      );
    }
    return ((fgR << 24) | (fgG << 16) | (fgB << 8) | 0xFF) & 0xFFFFFFFF;
  }

  static int increaseLuminance(int bgRgba, int fgRgba, double ratio) {
    // This is a naive but fast approach to increasing luminance as converting
    // to HSL and back is expensive
    final bgR = (bgRgba >> 24) & 0xFF;
    final bgG = (bgRgba >> 16) & 0xFF;
    final bgB = (bgRgba >> 8) & 0xFF;
    var fgR = (fgRgba >> 24) & 0xFF;
    var fgG = (fgRgba >> 16) & 0xFF;
    var fgB = (fgRgba >> 8) & 0xFF;
    var cr = contrastRatio(
      rgb.relativeLuminance2(fgR, fgG, fgB),
      rgb.relativeLuminance2(bgR, bgG, bgB),
    );
    while (cr < ratio && (fgR < 0xFF || fgG < 0xFF || fgB < 0xFF)) {
      // Increase by 10% until the ratio is hit
      fgR = math.min(0xFF, fgR + ((255 - fgR) * 0.1).ceil());
      fgG = math.min(0xFF, fgG + ((255 - fgG) * 0.1).ceil());
      fgB = math.min(0xFF, fgB + ((255 - fgB) * 0.1).ceil());
      cr = contrastRatio(
        rgb.relativeLuminance2(fgR, fgG, fgB),
        rgb.relativeLuminance2(bgR, bgG, bgB),
      );
    }
    return ((fgR << 24) | (fgG << 16) | (fgB << 8) | 0xFF) & 0xFFFFFFFF;
  }

  /// `[r, g, b, a]`.
  static List<int> toChannels(int value) {
    return <int>[
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }
}

String toPaddedHex(int c) {
  final s = c.toRadixString(16);
  return s.length < 2 ? '0$s' : s;
}

/// Gets the contrast ratio between two relative luminance values.
///
/// See https://www.w3.org/TR/WCAG20/#contrast-ratiodef
double contrastRatio(double l1, double l2) {
  if (l1 < l2) {
    return (l2 + 0.05) / (l1 + 0.05);
  }
  return (l1 + 0.05) / (l2 + 0.05);
}
