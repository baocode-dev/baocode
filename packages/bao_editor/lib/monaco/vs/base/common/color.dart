/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/base/common/color.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971. This is not Flutter's `dart:ui`
// `Color`.
//
// Deviations:
// - JavaScript number semantics are reproduced where colors depend on them:
//   `Math.round` rounds halves up, `x | 0` truncates and turns NaN into 0,
//   `Math.min`/`Math.max` propagate NaN, and `%` is [double.remainder]. A NaN
//   factor therefore yields the same color as upstream.
// - `new Color(hsla)`/`new Color(hsva)` are [Color.fromHSLA]/[Color.fromHSVA];
//   like upstream, such a color answers [Color.hsla]/[Color.hsva] with the
//   value it was made from.
// - Dart cannot have a static and an instance member of the same name: the
//   static `Color.transparent` is [Color.transparentColor], and the static
//   `equals` of `RGBA`, `HSLA`, `HSVA` and `Color` are [RGBA.equalsRGBA],
//   [HSLA.equalsHSLA], [HSVA.equalsHSVA] and [Color.equalsColors].
// - `flatten(...backgrounds)` takes a list; an empty one throws a
//   [StateError] where upstream throws a TypeError.
// - `Color.Format.CSS` is [ColorFormatCSS]; `parse` throws a
//   [FormatException] where upstream throws an Error.
// - `toString` and `toNumber32Bit` are not cached (colors are immutable).
// - `math.pow` may differ from V8's `Math.pow` in the last bit of a channel's
//   relative luminance (32 of the 256 channel values); after the rounding to
//   four decimals, [Color.getRelativeLuminance] equals upstream's for every
//   RGB color (test/ide/editor/monaco/vs/base/common/color_test.dart).

import 'dart:math' as math;

/// JavaScript's `Math.round`: halves round up; NaN and infinities stay.
double _jsRound(double x) {
  final floor = x.floorToDouble();
  return x - floor >= 0.5 ? floor + 1 : floor;
}

/// JavaScript's `Math.min` of two numbers.
double _jsMin(double a, double b) {
  if (a.isNaN || b.isNaN) return double.nan;
  if (a == 0 && b == 0) return a.isNegative || b.isNegative ? -0.0 : 0.0;
  return a < b ? a : b;
}

/// JavaScript's `Math.max` of two numbers.
double _jsMax(double a, double b) {
  if (a.isNaN || b.isNaN) return double.nan;
  if (a == 0 && b == 0) return a.isNegative && b.isNegative ? -0.0 : 0.0;
  return a > b ? a : b;
}

/// JavaScript's `x | 0` for the clamped values colors use.
int _toInt32(double x) => x.isFinite ? x.truncate() : 0;

/// How JavaScript prints a number.
String _jsNumber(double value) {
  if (value.isNaN) return 'NaN';
  if (value.isInfinite) return value > 0 ? 'Infinity' : '-Infinity';
  if (value == value.truncateToDouble() && value.abs() < 1e21) {
    return value.toInt().toString();
  }
  return value.toString();
}

double _roundFloat(double number, int decimalPoints) {
  final decimal = math.pow(10, decimalPoints).toDouble();
  return _jsRound(number * decimal) / decimal;
}

class RGBA {
  /// Clamps like upstream: channels to integers in [0, 255], alpha to
  /// [0, 1] rounded to three decimals.
  RGBA(num r, num g, num b, [num a = 1])
    : r = _channel(r),
      g = _channel(g),
      b = _channel(b),
      a = _roundFloat(_jsMax(_jsMin(1, a.toDouble()), 0), 3);

  static int _channel(num value) =>
      _toInt32(_jsMin(255, _jsMax(0, value.toDouble())));

  /// Red: integer in [0-255].
  final int r;

  /// Green: integer in [0-255].
  final int g;

  /// Blue: integer in [0-255].
  final int b;

  /// Alpha: float in [0-1].
  final double a;

  static bool equalsRGBA(RGBA a, RGBA b) =>
      a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a;
}

class HSLA {
  HSLA(num h, num s, num l, num a)
    : h = _toInt32(_jsMax(_jsMin(360, h.toDouble()), 0)),
      s = _roundFloat(_jsMax(_jsMin(1, s.toDouble()), 0), 3),
      l = _roundFloat(_jsMax(_jsMin(1, l.toDouble()), 0), 3),
      a = _roundFloat(_jsMax(_jsMin(1, a.toDouble()), 0), 3);

  /// Hue: integer in [0, 360].
  final int h;

  /// Saturation: float in [0, 1].
  final double s;

  /// Luminosity: float in [0, 1].
  final double l;

  /// Alpha: float in [0, 1].
  final double a;

  static bool equalsHSLA(HSLA a, HSLA b) =>
      a.h == b.h && a.s == b.s && a.l == b.l && a.a == b.a;

  /// Converts an RGB color value to HSL. Conversion formula
  /// adapted from http://en.wikipedia.org/wiki/HSL_color_space.
  /// Assumes r, g, and b are contained in the set [0, 255] and
  /// returns h in the set [0, 360], s, and l in the set [0, 1].
  static HSLA fromRGBA(RGBA rgba) {
    final r = rgba.r / 255;
    final g = rgba.g / 255;
    final b = rgba.b / 255;
    final a = rgba.a;

    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    var h = 0.0;
    var s = 0.0;
    final l = (min + max) / 2;
    final chroma = max - min;

    if (chroma > 0) {
      s = _jsMin(l <= 0.5 ? chroma / (2 * l) : chroma / (2 - (2 * l)), 1);

      if (max == r) {
        h = (g - b) / chroma + (g < b ? 6 : 0);
      } else if (max == g) {
        h = (b - r) / chroma + 2;
      } else if (max == b) {
        h = (r - g) / chroma + 4;
      }

      h *= 60;
      h = _jsRound(h);
    }
    return HSLA(h, s, l, a);
  }

  static double _hue2rgb(double p, double q, double t) {
    if (t < 0) {
      t += 1;
    }
    if (t > 1) {
      t -= 1;
    }
    if (t < 1 / 6) {
      return p + (q - p) * 6 * t;
    }
    if (t < 1 / 2) {
      return q;
    }
    if (t < 2 / 3) {
      return p + (q - p) * (2 / 3 - t) * 6;
    }
    return p;
  }

  /// Converts an HSL color value to RGB. Conversion formula
  /// adapted from http://en.wikipedia.org/wiki/HSL_color_space.
  /// Assumes h in the set [0, 360] s, and l are contained in the set [0, 1]
  /// and returns r, g, and b in the set [0, 255].
  static RGBA toRGBA(HSLA hsla) {
    final h = hsla.h / 360;
    final HSLA(:s, :l, :a) = hsla;
    double r, g, b;

    if (s == 0) {
      r = g = b = l; // achromatic
    } else {
      final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
      final p = 2 * l - q;
      r = _hue2rgb(p, q, h + 1 / 3);
      g = _hue2rgb(p, q, h);
      b = _hue2rgb(p, q, h - 1 / 3);
    }

    return RGBA(_jsRound(r * 255), _jsRound(g * 255), _jsRound(b * 255), a);
  }
}

class HSVA {
  HSVA(num h, num s, num v, num a)
    : h = _toInt32(_jsMax(_jsMin(360, h.toDouble()), 0)),
      s = _roundFloat(_jsMax(_jsMin(1, s.toDouble()), 0), 3),
      v = _roundFloat(_jsMax(_jsMin(1, v.toDouble()), 0), 3),
      a = _roundFloat(_jsMax(_jsMin(1, a.toDouble()), 0), 3);

  /// Hue: integer in [0, 360].
  final int h;

  /// Saturation: float in [0, 1].
  final double s;

  /// Value: float in [0, 1].
  final double v;

  /// Alpha: float in [0, 1].
  final double a;

  static bool equalsHSVA(HSVA a, HSVA b) =>
      a.h == b.h && a.s == b.s && a.v == b.v && a.a == b.a;

  // from http://www.rapidtables.com/convert/color/rgb-to-hsv.htm
  static HSVA fromRGBA(RGBA rgba) {
    final r = rgba.r / 255;
    final g = rgba.g / 255;
    final b = rgba.b / 255;
    final cmax = math.max(r, math.max(g, b));
    final cmin = math.min(r, math.min(g, b));
    final delta = cmax - cmin;
    final s = cmax == 0 ? 0 : (delta / cmax);
    double m;

    if (delta == 0) {
      m = 0;
    } else if (cmax == r) {
      m = ((((g - b) / delta).remainder(6)) + 6).remainder(6);
    } else if (cmax == g) {
      m = ((b - r) / delta) + 2;
    } else {
      m = ((r - g) / delta) + 4;
    }

    return HSVA(_jsRound(m * 60), s, cmax, rgba.a);
  }

  // from http://www.rapidtables.com/convert/color/hsv-to-rgb.htm
  static RGBA toRGBA(HSVA hsva) {
    final HSVA(:h, :s, :v, :a) = hsva;
    final c = v * s;
    final x = c * (1 - ((h / 60).remainder(2) - 1).abs());
    final m = v - c;
    var r = 0.0, g = 0.0, b = 0.0;

    if (h < 60) {
      r = c;
      g = x;
    } else if (h < 120) {
      r = x;
      g = c;
    } else if (h < 180) {
      g = c;
      b = x;
    } else if (h < 240) {
      g = x;
      b = c;
    } else if (h < 300) {
      r = x;
      b = c;
    } else if (h <= 360) {
      r = c;
      b = x;
    }

    r = _jsRound((r + m) * 255);
    g = _jsRound((g + m) * 255);
    b = _jsRound((b + m) * 255);

    return RGBA(r, g, b, a);
  }
}

class Color {
  Color(this.rgba) : _hsla = null, _hsva = null;

  /// Upstream's `new Color(hsla)`.
  Color.fromHSLA(HSLA hsla)
    : _hsla = hsla,
      _hsva = null,
      rgba = HSLA.toRGBA(hsla);

  /// Upstream's `new Color(hsva)`.
  Color.fromHSVA(HSVA hsva)
    : _hsla = null,
      _hsva = hsva,
      rgba = HSVA.toRGBA(hsva);

  /// `Color.Format.CSS.parseHex(hex) || Color.red`: an invalid string is red.
  static Color fromHex(String hex) => ColorFormatCSS.parseHex(hex) ?? red;

  static bool equalsColors(Color? a, Color? b) {
    if (a == null && b == null) {
      return true;
    }
    if (a == null || b == null) {
      return false;
    }
    return a.equals(b);
  }

  final RGBA rgba;

  final HSLA? _hsla;
  HSLA get hsla => _hsla ?? HSLA.fromRGBA(rgba);

  final HSVA? _hsva;
  HSVA get hsva => _hsva ?? HSVA.fromRGBA(rgba);

  bool equals(Color? other) =>
      other != null &&
      RGBA.equalsRGBA(rgba, other.rgba) &&
      HSLA.equalsHSLA(hsla, other.hsla) &&
      HSVA.equalsHSVA(hsva, other.hsva);

  /// http://www.w3.org/TR/WCAG20/#relativeluminancedef
  /// Returns the number in the set [0, 1]. O => Darkest Black. 1 => Lightest white.
  double getRelativeLuminance() {
    final R = _relativeLuminanceForComponent(rgba.r);
    final G = _relativeLuminanceForComponent(rgba.g);
    final B = _relativeLuminanceForComponent(rgba.b);
    final luminance = 0.2126 * R + 0.7152 * G + 0.0722 * B;

    return _roundFloat(luminance, 4);
  }

  /// Reduces the "foreground" color on this "background" color unti it is
  /// below the relative luminace ratio.
  /// Returns the new foreground color.
  // See https://github.com/xtermjs/xterm.js/blob/44f9fa39ae03e2ca6d28354d88a399608686770e/src/common/Color.ts#L315
  Color reduceRelativeLuminace(Color foreground, double ratio) {
    // This is a naive but fast approach to reducing luminance as converting to
    // HSL and back is expensive
    var RGBA(r: fgR, g: fgG, b: fgB) = foreground.rgba;

    var cr = getContrastRatio(foreground);
    while (cr < ratio && (fgR > 0 || fgG > 0 || fgB > 0)) {
      // Reduce by 10% until the ratio is hit
      fgR -= math.max(0, (fgR * 0.1).ceil());
      fgG -= math.max(0, (fgG * 0.1).ceil());
      fgB -= math.max(0, (fgB * 0.1).ceil());
      cr = getContrastRatio(Color(RGBA(fgR, fgG, fgB)));
    }

    return Color(RGBA(fgR, fgG, fgB));
  }

  /// Increases the "foreground" color on this "background" color unti it is
  /// below the relative luminace ratio.
  /// Returns the new foreground color.
  // See https://github.com/xtermjs/xterm.js/blob/44f9fa39ae03e2ca6d28354d88a399608686770e/src/common/Color.ts#L335
  Color increaseRelativeLuminace(Color foreground, double ratio) {
    // This is a naive but fast approach to reducing luminance as converting to
    // HSL and back is expensive
    var RGBA(r: fgR, g: fgG, b: fgB) = foreground.rgba;
    var cr = getContrastRatio(foreground);
    while (cr < ratio && (fgR < 0xFF || fgG < 0xFF || fgB < 0xFF)) {
      fgR = math.min(0xFF, fgR + ((255 - fgR) * 0.1).ceil());
      fgG = math.min(0xFF, fgG + ((255 - fgG) * 0.1).ceil());
      fgB = math.min(0xFF, fgB + ((255 - fgB) * 0.1).ceil());
      cr = getContrastRatio(Color(RGBA(fgR, fgG, fgB)));
    }

    return Color(RGBA(fgR, fgG, fgB));
  }

  static double _relativeLuminanceForComponent(int color) {
    final c = color / 255;
    return (c <= 0.03928)
        ? c / 12.92
        : math.pow(((c + 0.055) / 1.055), 2.4).toDouble();
  }

  /// http://www.w3.org/TR/WCAG20/#contrast-ratiodef
  /// Returns the contrast ration number in the set [1, 21].
  double getContrastRatio(Color another) {
    final lum1 = getRelativeLuminance();
    final lum2 = another.getRelativeLuminance();
    return lum1 > lum2
        ? (lum1 + 0.05) / (lum2 + 0.05)
        : (lum2 + 0.05) / (lum1 + 0.05);
  }

  /// http://24ways.org/2010/calculating-color-contrast
  /// Return 'true' if darker color otherwise 'false'
  bool isDarker() {
    final yiq = (rgba.r * 299 + rgba.g * 587 + rgba.b * 114) / 1000;
    return yiq < 128;
  }

  /// http://24ways.org/2010/calculating-color-contrast
  /// Return 'true' if lighter color otherwise 'false'
  bool isLighter() {
    final yiq = (rgba.r * 299 + rgba.g * 587 + rgba.b * 114) / 1000;
    return yiq >= 128;
  }

  bool isLighterThan(Color another) {
    final lum1 = getRelativeLuminance();
    final lum2 = another.getRelativeLuminance();
    return lum1 > lum2;
  }

  bool isDarkerThan(Color another) {
    final lum1 = getRelativeLuminance();
    final lum2 = another.getRelativeLuminance();
    return lum1 < lum2;
  }

  /// Based on xterm.js: https://github.com/xtermjs/xterm.js/blob/44f9fa39ae03e2ca6d28354d88a399608686770e/src/common/Color.ts#L288
  ///
  /// Given a foreground color and a background color, either increase or
  /// reduce the luminance of the foreground color until the specified
  /// contrast ratio is met. If pure white or black is hit without the
  /// contrast ratio being met, go the other direction using the background
  /// color as the foreground color and take either the first or second result
  /// depending on which has the higher contrast ratio.
  ///
  /// [foreground] The foreground color.
  /// [ratio] The contrast ratio to achieve.
  /// Returns the adjusted foreground color.
  Color ensureConstrast(Color foreground, double ratio) {
    final bgL = getRelativeLuminance();
    final fgL = foreground.getRelativeLuminance();
    final cr = getContrastRatio(foreground);
    if (cr < ratio) {
      if (fgL < bgL) {
        final resultA = reduceRelativeLuminace(foreground, ratio);
        final resultARatio = getContrastRatio(resultA);
        if (resultARatio < ratio) {
          final resultB = increaseRelativeLuminace(foreground, ratio);
          final resultBRatio = getContrastRatio(resultB);
          return resultARatio > resultBRatio ? resultA : resultB;
        }
        return resultA;
      }
      final resultA = increaseRelativeLuminace(foreground, ratio);
      final resultARatio = getContrastRatio(resultA);
      if (resultARatio < ratio) {
        final resultB = reduceRelativeLuminace(foreground, ratio);
        final resultBRatio = getContrastRatio(resultB);
        return resultARatio > resultBRatio ? resultA : resultB;
      }
      return resultA;
    }

    return foreground;
  }

  Color lighten(double factor) =>
      Color.fromHSLA(HSLA(hsla.h, hsla.s, hsla.l + hsla.l * factor, hsla.a));

  Color darken(double factor) =>
      Color.fromHSLA(HSLA(hsla.h, hsla.s, hsla.l - hsla.l * factor, hsla.a));

  Color transparent(double factor) {
    final RGBA(:r, :g, :b, :a) = rgba;
    return Color(RGBA(r, g, b, a * factor));
  }

  bool isTransparent() => rgba.a == 0;

  bool isOpaque() => rgba.a == 1;

  Color opposite() =>
      Color(RGBA(255 - rgba.r, 255 - rgba.g, 255 - rgba.b, rgba.a));

  Color blend(Color c) {
    final rgba = c.rgba;

    // Convert to 0..1 opacity
    final thisA = this.rgba.a;
    final colorA = rgba.a;

    final a = thisA + colorA * (1 - thisA);
    if (a < 1e-6) {
      return Color.transparentColor;
    }

    final r = this.rgba.r * thisA / a + rgba.r * colorA * (1 - thisA) / a;
    final g = this.rgba.g * thisA / a + rgba.g * colorA * (1 - thisA) / a;
    final b = this.rgba.b * thisA / a + rgba.b * colorA * (1 - thisA) / a;

    return Color(RGBA(r, g, b, a));
  }

  /// Mixes the current color with the provided color based on the given
  /// factor.
  /// [color] The color to mix with
  /// [factor] The factor of mixing (0 means this color, 1 means the input
  /// color, 0.5 means equal mix)
  /// Returns a new color representing the mix
  Color mix(Color color, [double factor = 0.5]) {
    final normalize = _jsMin(_jsMax(factor, 0), 1);
    final thisRGBA = rgba;
    final otherRGBA = color.rgba;

    final r = thisRGBA.r + (otherRGBA.r - thisRGBA.r) * normalize;
    final g = thisRGBA.g + (otherRGBA.g - thisRGBA.g) * normalize;
    final b = thisRGBA.b + (otherRGBA.b - thisRGBA.b) * normalize;
    final a = thisRGBA.a + (otherRGBA.a - thisRGBA.a) * normalize;

    return Color(RGBA(r, g, b, a));
  }

  Color makeOpaque(Color opaqueBackground) {
    if (isOpaque() || opaqueBackground.rgba.a != 1) {
      // only allow to blend onto a non-opaque color onto a opaque color
      return this;
    }

    final RGBA(:r, :g, :b, :a) = rgba;

    // https://stackoverflow.com/questions/12228548/finding-equivalent-color-with-opacity
    return Color(
      RGBA(
        opaqueBackground.rgba.r - a * (opaqueBackground.rgba.r - r),
        opaqueBackground.rgba.g - a * (opaqueBackground.rgba.g - g),
        opaqueBackground.rgba.b - a * (opaqueBackground.rgba.b - b),
        1,
      ),
    );
  }

  Color flatten(List<Color> backgrounds) {
    // `reduceRight` without an initial value.
    var background = backgrounds.last;
    for (var i = backgrounds.length - 2; i >= 0; i--) {
      background = _flatten(backgrounds[i], background);
    }
    return _flatten(this, background);
  }

  static Color _flatten(Color foreground, Color background) {
    final backgroundAlpha = 1 - foreground.rgba.a;
    return Color(
      RGBA(
        backgroundAlpha * background.rgba.r +
            foreground.rgba.a * foreground.rgba.r,
        backgroundAlpha * background.rgba.g +
            foreground.rgba.a * foreground.rgba.g,
        backgroundAlpha * background.rgba.b +
            foreground.rgba.a * foreground.rgba.b,
      ),
    );
  }

  @override
  String toString() => ColorFormatCSS.format(this);

  int toNumber32Bit() =>
      (rgba.r << 24 |
          rgba.g << 16 |
          rgba.b << 8 |
          _toInt32(rgba.a * 0xFF) << 0) &
      0xFFFFFFFF;

  static Color getLighterColor(Color of, Color relative, [double? factor]) {
    if (of.isLighterThan(relative)) {
      return of;
    }
    var f = factor == null || factor == 0 || factor.isNaN ? 0.5 : factor;
    final lum1 = of.getRelativeLuminance();
    final lum2 = relative.getRelativeLuminance();
    f = f * (lum2 - lum1) / lum2;
    return of.lighten(f);
  }

  static Color getDarkerColor(Color of, Color relative, [double? factor]) {
    if (of.isDarkerThan(relative)) {
      return of;
    }
    var f = factor == null || factor == 0 || factor.isNaN ? 0.5 : factor;
    final lum1 = of.getRelativeLuminance();
    final lum2 = relative.getRelativeLuminance();
    f = f * (lum1 - lum2) / lum1;
    return of.darken(f);
  }

  static final Color white = Color(RGBA(255, 255, 255, 1));
  static final Color black = Color(RGBA(0, 0, 0, 1));
  static final Color red = Color(RGBA(255, 0, 0, 1));
  static final Color blue = Color(RGBA(0, 0, 255, 1));
  static final Color green = Color(RGBA(0, 255, 0, 1));
  static final Color cyan = Color(RGBA(0, 255, 255, 1));
  static final Color lightgrey = Color(RGBA(211, 211, 211, 1));

  /// Upstream's static `Color.transparent`.
  static final Color transparentColor = Color(RGBA(0, 0, 0, 0));
}

/// Upstream's `Color.Format.CSS` namespace.
abstract final class ColorFormatCSS {
  static String formatRGB(Color color) {
    if (color.rgba.a == 1) {
      return 'rgb(${color.rgba.r}, ${color.rgba.g}, ${color.rgba.b})';
    }

    return formatRGBA(color);
  }

  static String formatRGBA(Color color) =>
      'rgba(${color.rgba.r}, ${color.rgba.g}, ${color.rgba.b}, '
      '${_jsNumber(double.parse(color.rgba.a.toStringAsFixed(2)))})';

  static String formatHSL(Color color) {
    if (color.hsla.a == 1) {
      return 'hsl(${color.hsla.h}, ${_jsNumber(_jsRound(color.hsla.s * 100))}%, '
          '${_jsNumber(_jsRound(color.hsla.l * 100))}%)';
    }

    return formatHSLA(color);
  }

  static String formatHSLA(Color color) =>
      'hsla(${color.hsla.h}, ${_jsNumber(_jsRound(color.hsla.s * 100))}%, '
      '${_jsNumber(_jsRound(color.hsla.l * 100))}%, '
      '${color.hsla.a.toStringAsFixed(2)})';

  static String _toTwoDigitHex(int n) {
    final r = n.toRadixString(16);
    return r.length != 2 ? '0$r' : r;
  }

  /// Formats the color as #RRGGBB
  static String formatHex(Color color) =>
      '#${_toTwoDigitHex(color.rgba.r)}${_toTwoDigitHex(color.rgba.g)}'
      '${_toTwoDigitHex(color.rgba.b)}';

  /// Formats the color as #RRGGBBAA
  /// If 'compact' is set, colors without transparancy will be printed as
  /// #RRGGBB
  static String formatHexA(Color color, [bool compact = false]) {
    if (compact && color.rgba.a == 1) {
      return formatHex(color);
    }

    return '#${_toTwoDigitHex(color.rgba.r)}${_toTwoDigitHex(color.rgba.g)}'
        '${_toTwoDigitHex(color.rgba.b)}'
        '${_toTwoDigitHex(_toInt32(_jsRound(color.rgba.a * 255)))}';
  }

  /// The default format will use HEX if opaque and RGBA otherwise.
  static String format(Color color) {
    if (color.isOpaque()) {
      return formatHex(color);
    }

    return formatRGBA(color);
  }

  static final RegExp _rgbaPattern = RegExp(
    r'rgba\((?<r>(?:\+|-)?\d+), *(?<g>(?:\+|-)?\d+), *(?<b>(?:\+|-)?\d+), *(?<a>(?:\+|-)?\d+(\.\d+)?)\)',
  );
  static final RegExp _rgbPattern = RegExp(
    r'rgb\((?<r>(?:\+|-)?\d+), *(?<g>(?:\+|-)?\d+), *(?<b>(?:\+|-)?\d+)\)',
  );

  /// Parse a CSS color and return a [Color].
  /// [css] The CSS color to parse.
  /// See https://drafts.csswg.org/css-color/#typedef-color
  static Color? parse(String css) {
    if (css == 'transparent') {
      return Color.transparentColor;
    }
    if (css.startsWith('#')) {
      return parseHex(css);
    }
    if (css.startsWith('rgba(')) {
      final color = _rgbaPattern.firstMatch(css);
      if (color == null) {
        throw FormatException('Invalid color format $css');
      }
      final r = int.parse(color.namedGroup('r') ?? '0');
      final g = int.parse(color.namedGroup('g') ?? '0');
      final b = int.parse(color.namedGroup('b') ?? '0');
      final a = double.parse(color.namedGroup('a') ?? '0');
      return Color(RGBA(r, g, b, a));
    }
    if (css.startsWith('rgb(')) {
      final color = _rgbPattern.firstMatch(css);
      if (color == null) {
        throw FormatException('Invalid color format $css');
      }
      final r = int.parse(color.namedGroup('r') ?? '0');
      final g = int.parse(color.namedGroup('g') ?? '0');
      final b = int.parse(color.namedGroup('b') ?? '0');
      return Color(RGBA(r, g, b));
    }
    // TODO: Support more formats as needed
    return _parseNamedKeyword(css);
  }

  static Color? _parseNamedKeyword(String css) {
    // https://drafts.csswg.org/css-color/#named-colors
    final rgb = _namedColors[css];
    return rgb == null ? null : Color(RGBA(rgb[0], rgb[1], rgb[2], 1));
  }

  static const Map<String, List<int>> _namedColors = {
    'aliceblue': [240, 248, 255],
    'antiquewhite': [250, 235, 215],
    'aqua': [0, 255, 255],
    'aquamarine': [127, 255, 212],
    'azure': [240, 255, 255],
    'beige': [245, 245, 220],
    'bisque': [255, 228, 196],
    'black': [0, 0, 0],
    'blanchedalmond': [255, 235, 205],
    'blue': [0, 0, 255],
    'blueviolet': [138, 43, 226],
    'brown': [165, 42, 42],
    'burlywood': [222, 184, 135],
    'cadetblue': [95, 158, 160],
    'chartreuse': [127, 255, 0],
    'chocolate': [210, 105, 30],
    'coral': [255, 127, 80],
    'cornflowerblue': [100, 149, 237],
    'cornsilk': [255, 248, 220],
    'crimson': [220, 20, 60],
    'cyan': [0, 255, 255],
    'darkblue': [0, 0, 139],
    'darkcyan': [0, 139, 139],
    'darkgoldenrod': [184, 134, 11],
    'darkgray': [169, 169, 169],
    'darkgreen': [0, 100, 0],
    'darkgrey': [169, 169, 169],
    'darkkhaki': [189, 183, 107],
    'darkmagenta': [139, 0, 139],
    'darkolivegreen': [85, 107, 47],
    'darkorange': [255, 140, 0],
    'darkorchid': [153, 50, 204],
    'darkred': [139, 0, 0],
    'darksalmon': [233, 150, 122],
    'darkseagreen': [143, 188, 143],
    'darkslateblue': [72, 61, 139],
    'darkslategray': [47, 79, 79],
    'darkslategrey': [47, 79, 79],
    'darkturquoise': [0, 206, 209],
    'darkviolet': [148, 0, 211],
    'deeppink': [255, 20, 147],
    'deepskyblue': [0, 191, 255],
    'dimgray': [105, 105, 105],
    'dimgrey': [105, 105, 105],
    'dodgerblue': [30, 144, 255],
    'firebrick': [178, 34, 34],
    'floralwhite': [255, 250, 240],
    'forestgreen': [34, 139, 34],
    'fuchsia': [255, 0, 255],
    'gainsboro': [220, 220, 220],
    'ghostwhite': [248, 248, 255],
    'gold': [255, 215, 0],
    'goldenrod': [218, 165, 32],
    'gray': [128, 128, 128],
    'green': [0, 128, 0],
    'greenyellow': [173, 255, 47],
    'grey': [128, 128, 128],
    'honeydew': [240, 255, 240],
    'hotpink': [255, 105, 180],
    'indianred': [205, 92, 92],
    'indigo': [75, 0, 130],
    'ivory': [255, 255, 240],
    'khaki': [240, 230, 140],
    'lavender': [230, 230, 250],
    'lavenderblush': [255, 240, 245],
    'lawngreen': [124, 252, 0],
    'lemonchiffon': [255, 250, 205],
    'lightblue': [173, 216, 230],
    'lightcoral': [240, 128, 128],
    'lightcyan': [224, 255, 255],
    'lightgoldenrodyellow': [250, 250, 210],
    'lightgray': [211, 211, 211],
    'lightgreen': [144, 238, 144],
    'lightgrey': [211, 211, 211],
    'lightpink': [255, 182, 193],
    'lightsalmon': [255, 160, 122],
    'lightseagreen': [32, 178, 170],
    'lightskyblue': [135, 206, 250],
    'lightslategray': [119, 136, 153],
    'lightslategrey': [119, 136, 153],
    'lightsteelblue': [176, 196, 222],
    'lightyellow': [255, 255, 224],
    'lime': [0, 255, 0],
    'limegreen': [50, 205, 50],
    'linen': [250, 240, 230],
    'magenta': [255, 0, 255],
    'maroon': [128, 0, 0],
    'mediumaquamarine': [102, 205, 170],
    'mediumblue': [0, 0, 205],
    'mediumorchid': [186, 85, 211],
    'mediumpurple': [147, 112, 219],
    'mediumseagreen': [60, 179, 113],
    'mediumslateblue': [123, 104, 238],
    'mediumspringgreen': [0, 250, 154],
    'mediumturquoise': [72, 209, 204],
    'mediumvioletred': [199, 21, 133],
    'midnightblue': [25, 25, 112],
    'mintcream': [245, 255, 250],
    'mistyrose': [255, 228, 225],
    'moccasin': [255, 228, 181],
    'navajowhite': [255, 222, 173],
    'navy': [0, 0, 128],
    'oldlace': [253, 245, 230],
    'olive': [128, 128, 0],
    'olivedrab': [107, 142, 35],
    'orange': [255, 165, 0],
    'orangered': [255, 69, 0],
    'orchid': [218, 112, 214],
    'palegoldenrod': [238, 232, 170],
    'palegreen': [152, 251, 152],
    'paleturquoise': [175, 238, 238],
    'palevioletred': [219, 112, 147],
    'papayawhip': [255, 239, 213],
    'peachpuff': [255, 218, 185],
    'peru': [205, 133, 63],
    'pink': [255, 192, 203],
    'plum': [221, 160, 221],
    'powderblue': [176, 224, 230],
    'purple': [128, 0, 128],
    'rebeccapurple': [102, 51, 153],
    'red': [255, 0, 0],
    'rosybrown': [188, 143, 143],
    'royalblue': [65, 105, 225],
    'saddlebrown': [139, 69, 19],
    'salmon': [250, 128, 114],
    'sandybrown': [244, 164, 96],
    'seagreen': [46, 139, 87],
    'seashell': [255, 245, 238],
    'sienna': [160, 82, 45],
    'silver': [192, 192, 192],
    'skyblue': [135, 206, 235],
    'slateblue': [106, 90, 205],
    'slategray': [112, 128, 144],
    'slategrey': [112, 128, 144],
    'snow': [255, 250, 250],
    'springgreen': [0, 255, 127],
    'steelblue': [70, 130, 180],
    'tan': [210, 180, 140],
    'teal': [0, 128, 128],
    'thistle': [216, 191, 216],
    'tomato': [255, 99, 71],
    'turquoise': [64, 224, 208],
    'violet': [238, 130, 238],
    'wheat': [245, 222, 179],
    'white': [255, 255, 255],
    'whitesmoke': [245, 245, 245],
    'yellow': [255, 255, 0],
    'yellowgreen': [154, 205, 50],
  };

  /// Converts an Hex color value to a Color.
  /// returns r, g, and b are contained in the set [0, 255]
  /// [hex] string (#RGB, #RGBA, #RRGGBB or #RRGGBBAA).
  static Color? parseHex(String hex) {
    final length = hex.length;

    if (length == 0) {
      // Invalid color
      return null;
    }

    if (hex.codeUnitAt(0) != 0x23 /* # */ ) {
      // Does not begin with a #
      return null;
    }

    int digit(int index) => _parseHexDigit(hex.codeUnitAt(index));

    if (length == 7) {
      // #RRGGBB format
      final r = 16 * digit(1) + digit(2);
      final g = 16 * digit(3) + digit(4);
      final b = 16 * digit(5) + digit(6);
      return Color(RGBA(r, g, b, 1));
    }

    if (length == 9) {
      // #RRGGBBAA format
      final r = 16 * digit(1) + digit(2);
      final g = 16 * digit(3) + digit(4);
      final b = 16 * digit(5) + digit(6);
      final a = 16 * digit(7) + digit(8);
      return Color(RGBA(r, g, b, a / 255));
    }

    if (length == 4) {
      // #RGB format
      final r = digit(1);
      final g = digit(2);
      final b = digit(3);
      return Color(RGBA(16 * r + r, 16 * g + g, 16 * b + b));
    }

    if (length == 5) {
      // #RGBA format
      final r = digit(1);
      final g = digit(2);
      final b = digit(3);
      final a = digit(4);
      return Color(
        RGBA(16 * r + r, 16 * g + g, 16 * b + b, (16 * a + a) / 255),
      );
    }

    // Invalid color
    return null;
  }

  static int _parseHexDigit(int charCode) {
    if (charCode >= 0x30 && charCode <= 0x39) return charCode - 0x30; // 0-9
    if (charCode >= 0x61 && charCode <= 0x66) return charCode - 0x61 + 10;
    if (charCode >= 0x41 && charCode <= 0x46) return charCode - 0x41 + 10;
    return 0;
  }
}
