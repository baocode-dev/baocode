// Lightness, and a color shifted by it, in OKLab: its hue and its chroma
// kept. What is raised on the cards (see AppColors.raised) and the faint
// text's steps from them.

import 'dart:math' as math;
import 'dart:ui';

/// A color's lightness, and the color made lighter or darker by it.
abstract final class IslandTones {
  /// Perceived lightness, OKLab's L for a gray: the cube root of the
  /// luminance.
  static double lightness(Color color) =>
      math.pow(color.withValues(alpha: 1).computeLuminance(), 1 / 3) * 1.0;

  /// [color] [by] lighter (darker, [by] negative) in OKLab, its hue and
  /// chroma kept: a warm gray as warm, a tinted selection as tinted, not
  /// washed out as mixing in white would.
  static Color shift(Color color, double by) {
    final (l, a, b) = _toOklab(color);
    return _fromOklab(l + by, a, b, color.a);
  }

  static double _linear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4) * 1.0;

  static double _gamma(double c) {
    final v = c <= 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
    return v.clamp(0.0, 1.0);
  }

  static double _cbrt(double v) =>
      v < 0 ? -math.pow(-v, 1 / 3) * 1.0 : math.pow(v, 1 / 3) * 1.0;

  static (double, double, double) _toOklab(Color color) {
    final r = _linear(color.r), g = _linear(color.g), b = _linear(color.b);
    final l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    final m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    final s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return (
      0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
      1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
      0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    );
  }

  static Color _fromOklab(double lightness, double a, double b, double alpha) {
    final l = math.pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3);
    final m = math.pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3);
    final s = math.pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3);
    return Color.from(
      alpha: alpha,
      red: _gamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
      green: _gamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
      blue: _gamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
    );
  }
}
