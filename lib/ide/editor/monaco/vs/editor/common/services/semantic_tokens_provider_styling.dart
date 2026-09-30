/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/services/
// semanticTokensProviderStyling.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: `getMetadata`, which encodes the
// theme's style of a semantic token as token metadata. Its `SEMANTIC_USE_*`
// bits tell SparseTokensStore which attributes of the syntax token to
// replace. `SemanticTokensLegend` comes from editor/common/languages.ts.
//
// Not ported: `toMultilineTokens2` (the editor decodes the protocol's tokens
// itself), the `warn*` methods and tracing. Deviations: the theme service is
// the [SemanticTokenStyleProvider] callback; the hash table is a [Map] keyed
// by the language id itself rather than its encoded number; the metadata
// computation is also exposed as [semanticTokenStyleToMetadata] for callers
// that have the token's type and modifier names rather than legend indices.

import '../encoded_token_attributes.dart';
import '../../../workbench/services/themes/common/color_theme_token_styles.dart';

abstract final class SemanticTokensProviderStylingConstants {
  static const int noStyling = 0x7FFFFFFF;
}

class SemanticTokensLegend {
  const SemanticTokensLegend({
    required this.tokenTypes,
    required this.tokenModifiers,
  });

  final List<String> tokenTypes;
  final List<String> tokenModifiers;
}

/// `themeService.getColorTheme().getTokenStyleMetadata`.
typedef SemanticTokenStyleProvider = ITokenStyle? Function(
  String tokenType,
  List<String> tokenModifiers,
  String languageId,
);

class SemanticTokensProviderStyling {
  SemanticTokensProviderStyling(this._legend, this._getTokenStyleMetadata);

  final SemanticTokensLegend _legend;
  final SemanticTokenStyleProvider _getTokenStyleMetadata;
  final Map<(int, int, String), int> _hashTable = {};

  int getMetadata(int tokenTypeIndex, int tokenModifierSet, String languageId) {
    final key = (tokenTypeIndex, tokenModifierSet, languageId);
    final entry = _hashTable[key];
    if (entry != null) {
      return entry;
    }
    final int metadata;
    final tokenType =
        tokenTypeIndex >= 0 && tokenTypeIndex < _legend.tokenTypes.length
        ? _legend.tokenTypes[tokenTypeIndex]
        : null;
    if (tokenType != null && tokenType.isNotEmpty) {
      final tokenModifiers = <String>[];
      var modifierSet = tokenModifierSet;
      for (
        var modifierIndex = 0;
        modifierSet > 0 && modifierIndex < _legend.tokenModifiers.length;
        modifierIndex++
      ) {
        if (modifierSet & 1 != 0) {
          tokenModifiers.add(_legend.tokenModifiers[modifierIndex]);
        }
        modifierSet = modifierSet >> 1;
      }

      metadata = semanticTokenStyleToMetadata(
        _getTokenStyleMetadata(tokenType, tokenModifiers, languageId),
      );
    } else {
      metadata = SemanticTokensProviderStylingConstants.noStyling;
    }
    _hashTable[key] = metadata;
    return metadata;
  }
}

/// The metadata `getMetadata` builds from a token's style:
/// [SemanticTokensProviderStylingConstants.noStyling] when the style sets
/// nothing.
int semanticTokenStyleToMetadata(ITokenStyle? tokenStyle) {
  if (tokenStyle == null) {
    return SemanticTokensProviderStylingConstants.noStyling;
  }
  var metadata = 0;
  if (tokenStyle.italic != null) {
    final italicBit =
        (tokenStyle.italic! ? FontStyle.italic : 0) <<
        MetadataConsts.fontStyleOffset;
    metadata |= italicBit | MetadataConsts.semanticUseItalic;
  }
  if (tokenStyle.bold != null) {
    final boldBit =
        (tokenStyle.bold! ? FontStyle.bold : 0) <<
        MetadataConsts.fontStyleOffset;
    metadata |= boldBit | MetadataConsts.semanticUseBold;
  }
  if (tokenStyle.underline != null) {
    final underlineBit =
        (tokenStyle.underline! ? FontStyle.underline : 0) <<
        MetadataConsts.fontStyleOffset;
    metadata |= underlineBit | MetadataConsts.semanticUseUnderline;
  }
  if (tokenStyle.strikethrough != null) {
    final strikethroughBit =
        (tokenStyle.strikethrough! ? FontStyle.strikethrough : 0) <<
        MetadataConsts.fontStyleOffset;
    metadata |= strikethroughBit | MetadataConsts.semanticUseStrikethrough;
  }
  final foreground = tokenStyle.foreground;
  if (foreground != null && foreground != 0) {
    final foregroundBits = foreground << MetadataConsts.foregroundOffset;
    metadata |= foregroundBits | MetadataConsts.semanticUseForeground;
  }
  // JavaScript's bitwise operators work on 32-bit integers.
  metadata = metadata.toSigned(32);
  if (metadata == 0) {
    // Nothing!
    metadata = SemanticTokensProviderStylingConstants.noStyling;
  }
  return metadata;
}
