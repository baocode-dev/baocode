/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/languages/nullTokenize.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: `nullTokenizeEncoded`, with the
// `EncodedTokenizationResult` of languages.ts it returns. `nullTokenize` (the
// string-token form) is not ported. The result carries no font info: this
// editor draws no per-token fonts.

import 'dart:typed_data';

import '../encoded_token_attributes.dart';

/// `EncodedTokenizationResult`: a line's tokens as `[startIndex, metadata]`
/// pairs, and the state at its end.
class EncodedTokenizationResult<S> {
  const EncodedTokenizationResult(this.tokens, this.endState);

  final Uint32List tokens;
  final S endState;
}

/// One token over the whole line, in the default colors.
EncodedTokenizationResult<S> nullTokenizeEncoded<S>(int languageId, S state) {
  final tokens = Uint32List(2);
  tokens[0] = 0;
  tokens[1] =
      ((languageId << MetadataConsts.languageIdOffset) |
          (StandardTokenType.other << MetadataConsts.tokenTypeOffset) |
          (FontStyle.none << MetadataConsts.fontStyleOffset) |
          (ColorId.defaultForeground << MetadataConsts.foregroundOffset) |
          (ColorId.defaultBackground << MetadataConsts.backgroundOffset)) >>>
      0;
  return EncodedTokenizationResult(tokens, state);
}
