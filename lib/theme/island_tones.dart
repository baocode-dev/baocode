// The cards (Islands) and the window under them, set apart.
//
// A theme's editor is its cards' color and its side bar the window's (see
// AppColors). Many themes' are a shade apart, as the parts sat side by side
// with a line between them: Bao Dark's #282827 on #212120, the cards hardly
// told from the window. The theme's colors stay as they are, the IDE's
// parts (not islands) and everything on a card in them; the agents'
// window's own color, about its cards, is sunk under them instead.

import 'dart:math' as math;
import 'dart:ui';

/// How the agents' window is set apart from its cards: its color (a
/// theme's `sideBar.background`) sunk till the cards (its
/// `editor.background`) stand [darkStep] over it, [lightStep] in a light
/// theme, as they are where they already do.
abstract final class IslandTones {
  /// The least lightness (OKLab L) between a dark theme's cards and its
  /// window: further than the island prototype's (#222221 on #181817,
  /// 0.043).
  static const darkStep = 0.08;

  /// A light theme's: light grays being harder to tell apart, further.
  static const lightStep = 0.06;

  /// As dark as a dark theme's window is sunk, not to read black: less
  /// apart from its cards then.
  static const darkest = 0.19;

  /// The window's color about cards of [card], for a theme whose window
  /// is [base]: [base] sunk, or as it is where it is apart enough already,
  /// lighter than the cards, see-through, or [highContrast] (outlined).
  static Color window(Color card, Color base, {bool highContrast = false}) {
    if (highContrast || card.a < 1 || base.a < 1) return base;
    final cardL = lightness(card);
    final baseL = lightness(base);
    if (cardL < baseL) return base;
    final target = baseL < 0.5
        ? math.max(cardL - darkStep, math.min(darkest, baseL))
        : cardL - lightStep;
    return target >= baseL ? base : shift(base, target - baseL);
  }

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
