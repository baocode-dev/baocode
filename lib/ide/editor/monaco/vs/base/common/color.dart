/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/base/common/color.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: `RGBA`, and of `Color` the hex
// round trip color themes rely on (`fromHex`, `equals`, the `white`, `black`
// and `red` constants, and `Color.Format.CSS.{parseHex,formatHex,formatHexA}`
// as [ColorFormatCSS]). HSLA/HSVA, blending, contrast and the other CSS
// formats are not ported. This is not Flutter's `dart:ui` `Color`.

double _roundFloat(double number, int decimalPoints) {
  final decimal = _pow10(decimalPoints);
  return (number * decimal).round() / decimal;
}

double _pow10(int exponent) {
  var result = 1.0;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}

class RGBA {
  /// Clamps like upstream: channels to integers in [0, 255], alpha to
  /// [0, 1] rounded to three decimals.
  RGBA(num r, num g, num b, [num a = 1])
    : r = _channel(r),
      g = _channel(g),
      b = _channel(b),
      a = _roundFloat(a.clamp(0, 1).toDouble(), 3);

  static int _channel(num value) => value.clamp(0, 255).truncate();

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

class Color {
  Color(this.rgba);

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

  bool equals(Color? other) =>
      other != null && RGBA.equalsRGBA(rgba, other.rgba);

  bool isOpaque() => rgba.a == 1;

  @override
  String toString() => ColorFormatCSS.formatHexA(this);

  static final Color white = Color(RGBA(255, 255, 255, 1));
  static final Color black = Color(RGBA(0, 0, 0, 1));
  static final Color red = Color(RGBA(255, 0, 0, 1));
}

/// Upstream's `Color.Format.CSS` namespace (the hex subset).
abstract final class ColorFormatCSS {
  static String _toTwoDigitHex(int n) {
    final r = n.toRadixString(16);
    return r.length != 2 ? '0$r' : r;
  }

  /// Formats the color as #RRGGBB (lower case).
  static String formatHex(Color color) =>
      '#${_toTwoDigitHex(color.rgba.r)}${_toTwoDigitHex(color.rgba.g)}'
      '${_toTwoDigitHex(color.rgba.b)}';

  /// Formats the color as #RRGGBBAA. If [compact] is set, colors without
  /// transparency are printed as #RRGGBB.
  static String formatHexA(Color color, [bool compact = false]) {
    if (compact && color.rgba.a == 1) {
      return formatHex(color);
    }
    return '#${_toTwoDigitHex(color.rgba.r)}${_toTwoDigitHex(color.rgba.g)}'
        '${_toTwoDigitHex(color.rgba.b)}'
        '${_toTwoDigitHex((color.rgba.a * 255).round())}';
  }

  /// Parses #RGB, #RGBA, #RRGGBB and #RRGGBBAA; null for anything else. Like
  /// upstream, a non-hex digit counts as 0.
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
