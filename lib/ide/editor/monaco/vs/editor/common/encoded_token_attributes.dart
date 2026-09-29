/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/encodedTokenAttributes.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971.
// TypeScript numeric enums become integer constants (camelCase in Dart).
// ITokenPresentation becomes the immutable TokenPresentation value below.
// All metadata helpers are ported; this does not implement a theme service.

/// Open-ended encoded language identifiers, not a language registry.
abstract final class LanguageId {
  static const int nullId = 0;
  static const int plainText = 1;
}

/// Bit flags, combinable with bitwise OR.
abstract final class FontStyle {
  static const int notSet = -1;
  static const int none = 0;
  static const int italic = 1;
  static const int bold = 2;
  static const int underline = 4;
  static const int strikethrough = 8;
}

/// Open-ended indices into a theme's color map.
abstract final class ColorId {
  static const int none = 0;
  static const int defaultForeground = 1;
  static const int defaultBackground = 2;
}

abstract final class StandardTokenType {
  static const int other = 0;
  static const int comment = 1;
  static const int string = 2;
  static const int regEx = 3;
}

/// The upstream 32-bit layout, from least to most significant bit:
/// language (8), token type (2), balanced brackets (1), font style (4),
/// foreground (9), background (8).
abstract final class MetadataConsts {
  static const int languageIdMask = 0x000000ff;
  static const int tokenTypeMask = 0x00000300;
  static const int balancedBracketsMask = 0x00000400;
  static const int fontStyleMask = 0x00007800;
  static const int foregroundMask = 0x00ff8000;
  static const int backgroundMask = 0xff000000;

  static const int italicMask = 0x00000800;
  static const int boldMask = 0x00001000;
  static const int underlineMask = 0x00002000;
  static const int strikethroughMask = 0x00004000;

  // Semantic tokens reuse the language byte as control bits.
  static const int semanticUseItalic = 0x01;
  static const int semanticUseBold = 0x02;
  static const int semanticUseUnderline = 0x04;
  static const int semanticUseStrikethrough = 0x08;
  static const int semanticUseForeground = 0x10;
  static const int semanticUseBackground = 0x20;

  static const int languageIdOffset = 0;
  static const int tokenTypeOffset = 8;
  static const int balancedBracketsOffset = 10;
  static const int fontStyleOffset = 11;
  static const int foregroundOffset = 15;
  static const int backgroundOffset = 24;
}

abstract final class TokenMetadata {
  static int getLanguageId(int metadata) =>
      (metadata & MetadataConsts.languageIdMask) >>>
      MetadataConsts.languageIdOffset;

  static int getTokenType(int metadata) =>
      (metadata & MetadataConsts.tokenTypeMask) >>>
      MetadataConsts.tokenTypeOffset;

  static bool containsBalancedBrackets(int metadata) =>
      (metadata & MetadataConsts.balancedBracketsMask) != 0;

  static int getFontStyle(int metadata) =>
      (metadata & MetadataConsts.fontStyleMask) >>>
      MetadataConsts.fontStyleOffset;

  static int getForeground(int metadata) =>
      (metadata & MetadataConsts.foregroundMask) >>>
      MetadataConsts.foregroundOffset;

  static int getBackground(int metadata) =>
      (metadata & MetadataConsts.backgroundMask) >>>
      MetadataConsts.backgroundOffset;

  static String getClassNameFromMetadata(int metadata) {
    final fontStyle = getFontStyle(metadata);
    var className = 'mtk${getForeground(metadata)}';
    if ((fontStyle & FontStyle.italic) != 0) className += ' mtki';
    if ((fontStyle & FontStyle.bold) != 0) className += ' mtkb';
    if ((fontStyle & FontStyle.underline) != 0) className += ' mtku';
    if ((fontStyle & FontStyle.strikethrough) != 0) className += ' mtks';
    return className;
  }

  /// [colorMap] must contain the foreground index. Unlike JavaScript's
  /// `undefined` string interpolation, a missing entry throws RangeError.
  static String getInlineStyleFromMetadata(
    int metadata,
    List<String> colorMap,
  ) {
    final fontStyle = getFontStyle(metadata);
    var result = 'color: ${colorMap[getForeground(metadata)]};';
    if ((fontStyle & FontStyle.italic) != 0) result += 'font-style: italic;';
    if ((fontStyle & FontStyle.bold) != 0) result += 'font-weight: bold;';
    var textDecoration = '';
    if ((fontStyle & FontStyle.underline) != 0) textDecoration += ' underline';
    if ((fontStyle & FontStyle.strikethrough) != 0) {
      textDecoration += ' line-through';
    }
    if (textDecoration.isNotEmpty) {
      result += 'text-decoration:$textDecoration;';
    }
    return result;
  }

  static TokenPresentation getPresentationFromMetadata(int metadata) {
    final fontStyle = getFontStyle(metadata);
    return TokenPresentation(
      foreground: getForeground(metadata),
      italic: (fontStyle & FontStyle.italic) != 0,
      bold: (fontStyle & FontStyle.bold) != 0,
      underline: (fontStyle & FontStyle.underline) != 0,
      strikethrough: (fontStyle & FontStyle.strikethrough) != 0,
    );
  }
}

/// Theme-independent rendering attributes. Like upstream ITokenPresentation,
/// this intentionally excludes the background and language identifier.
final class TokenPresentation {
  const TokenPresentation({
    required this.foreground,
    required this.italic,
    required this.bold,
    required this.underline,
    required this.strikethrough,
  });

  final int foreground;
  final bool italic;
  final bool bold;
  final bool underline;
  final bool strikethrough;
}
