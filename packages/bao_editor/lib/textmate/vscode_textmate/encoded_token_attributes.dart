// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/encodedTokenAttributes.ts (MIT, see LICENSE.md).

import 'theme.dart';

/// Performance notes (benchmark on large TypeScript file ~3100ms total tokenization):
///
/// We tested multiple FontAttribute caching strategies:
/// - String key HashMap (current): ~3175ms - uses `${fontFamily}|${fontSize}|${lineHeight}` as key
/// - Linear array scan: ~3141ms - iterates through ~5 cached items
/// - Numeric key + transition cache: ~3184ms - complex caching with per-instance transitions
/// - NOOP (always return this): ~3097ms - theoretical upper bound
///
/// Conclusion: FontAttribute overhead is only ~45-80ms (1-2.5% of total time).
/// The simple string key HashMap is sufficient - additional optimization complexity
/// provides negligible benefit since there are typically only ~5 unique FontAttribute
/// combinations in practice.
class FontAttribute {
  FontAttribute._(this.fontFamily, this.fontSize, this.lineHeight);

  static final Map<String, FontAttribute> _map = <String, FontAttribute>{};

  static String _getKey(String? fontFamily, num? fontSize, num? lineHeight) {
    return '$fontFamily|$fontSize|$lineHeight';
  }

  static FontAttribute _get(
    String? fontFamily,
    num? fontSize,
    num? lineHeight,
  ) {
    final key = _getKey(fontFamily, fontSize, lineHeight);
    var result = _map[key];
    if (result == null) {
      result = FontAttribute._(fontFamily, fontSize, lineHeight);
      _map[key] = result;
    }
    return result;
  }

  static FontAttribute from(
    String? fontFamily,
    num? fontSize,
    num? lineHeight,
  ) {
    return FontAttribute._(fontFamily, fontSize, lineHeight);
  }

  final String? fontFamily;
  final num? fontSize;
  final num? lineHeight;

  FontAttribute withStyle(StyleAttributes? styleAttributes) {
    if (styleAttributes == null) {
      return this;
    }
    final family = styleAttributes.fontFamily;
    final size = styleAttributes.fontSize;
    final height = styleAttributes.lineHeight;
    return FontAttribute._get(
      family.isNotEmpty ? family : fontFamily,
      _numTruthy(size) ? size : fontSize,
      _numTruthy(height) ? height : lineHeight,
    );
  }

  static bool _numTruthy(num n) => n != 0 && !n.isNaN;
}

/// Helpers for the encoded token attributes (a 32-bit unsigned int).
abstract final class EncodedTokenAttributes {
  static String toBinaryStr(int encodedTokenAttributes) {
    return encodedTokenAttributes.toRadixString(2).padLeft(32, '0');
  }

  static int getLanguageId(int encodedTokenAttributes) {
    return (encodedTokenAttributes & EncodedTokenDataConsts.languageIdMask) >>>
        EncodedTokenDataConsts.languageIdOffset;
  }

  static int getTokenType(int encodedTokenAttributes) {
    return (encodedTokenAttributes & EncodedTokenDataConsts.tokenTypeMask) >>>
        EncodedTokenDataConsts.tokenTypeOffset;
  }

  static bool containsBalancedBrackets(int encodedTokenAttributes) {
    return (encodedTokenAttributes &
            EncodedTokenDataConsts.balancedBracketsMask) !=
        0;
  }

  static int getFontStyle(int encodedTokenAttributes) {
    return (encodedTokenAttributes & EncodedTokenDataConsts.fontStyleMask) >>>
        EncodedTokenDataConsts.fontStyleOffset;
  }

  static int getForeground(int encodedTokenAttributes) {
    return (encodedTokenAttributes & EncodedTokenDataConsts.foregroundMask) >>>
        EncodedTokenDataConsts.foregroundOffset;
  }

  static int getBackground(int encodedTokenAttributes) {
    return (encodedTokenAttributes & EncodedTokenDataConsts.backgroundMask) >>>
        EncodedTokenDataConsts.backgroundOffset;
  }

  /// Updates the fields in `metadata`.
  /// A value of `0`, `NotSet` or `null` indicates that the corresponding field should be left as is.
  static int set(
    int encodedTokenAttributes,
    int languageId,
    int tokenType,
    bool? containsBalancedBrackets,
    int fontStyle,
    int foreground,
    int background,
  ) {
    var languageIdValue = getLanguageId(encodedTokenAttributes);
    var tokenTypeValue = getTokenType(encodedTokenAttributes);
    var containsBalancedBracketsBit =
        EncodedTokenAttributes.containsBalancedBrackets(encodedTokenAttributes)
        ? 1
        : 0;
    var fontStyleValue = getFontStyle(encodedTokenAttributes);
    var foregroundValue = getForeground(encodedTokenAttributes);
    var backgroundValue = getBackground(encodedTokenAttributes);

    if (languageId != 0) {
      languageIdValue = languageId;
    }
    if (tokenType != OptionalStandardTokenType.notSet) {
      tokenTypeValue = _fromOptionalTokenType(tokenType);
    }
    if (containsBalancedBrackets != null) {
      containsBalancedBracketsBit = containsBalancedBrackets ? 1 : 0;
    }
    if (fontStyle != FontStyle.notSet) {
      fontStyleValue = fontStyle;
    }
    if (foreground != 0) {
      foregroundValue = foreground;
    }
    if (background != 0) {
      backgroundValue = background;
    }

    // `>>> 0` in JavaScript: the low 32 bits as an unsigned value.
    return ((languageIdValue << EncodedTokenDataConsts.languageIdOffset) |
            (tokenTypeValue << EncodedTokenDataConsts.tokenTypeOffset) |
            (containsBalancedBracketsBit <<
                EncodedTokenDataConsts.balancedBracketsOffset) |
            (fontStyleValue << EncodedTokenDataConsts.fontStyleOffset) |
            (foregroundValue << EncodedTokenDataConsts.foregroundOffset) |
            (backgroundValue << EncodedTokenDataConsts.backgroundOffset)) &
        0xFFFFFFFF;
  }
}

/// Helpers to manage the "collapsed" metadata of an entire StackElement stack.
/// The following assumptions have been made:
///  - languageId < 256 => needs 8 bits
///  - unique color count < 512 => needs 9 bits
///
/// The binary format is:
/// - -------------------------------------------
///     3322 2222 2222 1111 1111 1100 0000 0000
///     1098 7654 3210 9876 5432 1098 7654 3210
/// - -------------------------------------------
///     xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx
///     bbbb bbbb ffff ffff fFFF FBTT LLLL LLLL
/// - -------------------------------------------
///  - L = LanguageId (8 bits)
///  - T = StandardTokenType (2 bits)
///  - B = Balanced bracket (1 bit)
///  - F = FontStyle (4 bits)
///  - f = foreground color (9 bits)
///  - b = background color (9 bits)
abstract final class EncodedTokenDataConsts {
  static const int languageIdMask = 0x000000FF;
  static const int tokenTypeMask = 0x00000300;
  static const int balancedBracketsMask = 0x00000400;
  static const int fontStyleMask = 0x00007800;
  static const int foregroundMask = 0x00FF8000;
  static const int backgroundMask = 0xFF000000;

  static const int languageIdOffset = 0;
  static const int tokenTypeOffset = 8;
  static const int balancedBracketsOffset = 10;
  static const int fontStyleOffset = 11;
  static const int foregroundOffset = 15;
  static const int backgroundOffset = 24;
}

abstract final class StandardTokenType {
  static const int other = 0;
  static const int comment = 1;
  static const int string = 2;
  static const int regEx = 3;
}

int toOptionalTokenType(int standardType) {
  return standardType;
}

int _fromOptionalTokenType(int standardType) {
  return standardType;
}

/// Must have the same values as `StandardTokenType`!
abstract final class OptionalStandardTokenType {
  static const int other = 0;
  static const int comment = 1;
  static const int string = 2;
  static const int regEx = 3;

  /// Indicates that no token type is set.
  static const int notSet = 8;
}
