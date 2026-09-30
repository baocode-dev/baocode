/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/tokens/contiguousTokensEditing.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971. Tokens are in end-offset form
// (`LineTokens.convertToEndOffset`). Deviation: a `Uint32List` stands in for
// upstream's `Uint32Array | ArrayBuffer`, and [emptyLineTokens] is compared by
// identity as upstream compares `EMPTY_LINE_TOKENS`.

import 'dart:typed_data';

import 'line_tokens.dart';

/// `EMPTY_LINE_TOKENS`.
final Uint32List emptyLineTokens = Uint32List(0);

abstract final class ContiguousTokensEditing {
  static Uint32List? deleteBeginning(Uint32List? lineTokens, int toChIndex) {
    if (lineTokens == null || identical(lineTokens, emptyLineTokens)) {
      return lineTokens;
    }
    return delete(lineTokens, 0, toChIndex);
  }

  static Uint32List? deleteEnding(Uint32List? lineTokens, int fromChIndex) {
    if (lineTokens == null || identical(lineTokens, emptyLineTokens)) {
      return lineTokens;
    }
    final lineTextLength = lineTokens[lineTokens.length - 2];
    return delete(lineTokens, fromChIndex, lineTextLength);
  }

  static Uint32List? delete(
    Uint32List? lineTokens,
    int fromChIndex,
    int toChIndex,
  ) {
    if (lineTokens == null ||
        identical(lineTokens, emptyLineTokens) ||
        fromChIndex == toChIndex) {
      return lineTokens;
    }

    final tokens = lineTokens;
    final tokensCount = tokens.length >>> 1;

    // special case: deleting everything
    if (fromChIndex == 0 && tokens[tokens.length - 2] == toChIndex) {
      return emptyLineTokens;
    }

    final fromTokenIndex = LineTokens.findIndexInTokensArray(
      tokens,
      fromChIndex,
    );
    final fromTokenStartOffset = fromTokenIndex > 0
        ? tokens[(fromTokenIndex - 1) << 1]
        : 0;
    final fromTokenEndOffset = tokens[fromTokenIndex << 1];

    if (toChIndex < fromTokenEndOffset) {
      // the delete range is inside a single token
      final delta = toChIndex - fromChIndex;
      for (var i = fromTokenIndex; i < tokensCount; i++) {
        tokens[i << 1] -= delta;
      }
      return lineTokens;
    }

    int dest;
    int lastEnd;
    if (fromTokenStartOffset != fromChIndex) {
      tokens[fromTokenIndex << 1] = fromChIndex;
      dest = (fromTokenIndex + 1) << 1;
      lastEnd = fromChIndex;
    } else {
      dest = fromTokenIndex << 1;
      lastEnd = fromTokenStartOffset;
    }

    final delta = toChIndex - fromChIndex;
    for (
      var tokenIndex = fromTokenIndex + 1;
      tokenIndex < tokensCount;
      tokenIndex++
    ) {
      final tokenEndOffset = tokens[tokenIndex << 1] - delta;
      if (tokenEndOffset > lastEnd) {
        tokens[dest++] = tokenEndOffset;
        tokens[dest++] = tokens[(tokenIndex << 1) + 1];
        lastEnd = tokenEndOffset;
      }
    }

    if (dest == tokens.length) {
      // nothing to trim
      return lineTokens;
    }

    return Uint32List.fromList(tokens.sublist(0, dest));
  }

  static Uint32List? append(Uint32List? lineTokens, Uint32List? otherTokens) {
    if (identical(otherTokens, emptyLineTokens)) return lineTokens;
    if (identical(lineTokens, emptyLineTokens)) return otherTokens;
    if (lineTokens == null) return lineTokens;
    // cannot determine combined line length...
    if (otherTokens == null) return null;
    final otherTokensCount = otherTokens.length >>> 1;

    final result = Uint32List(lineTokens.length + otherTokens.length);
    result.setAll(0, lineTokens);
    var dest = lineTokens.length;
    final delta = lineTokens[lineTokens.length - 2];
    for (var i = 0; i < otherTokensCount; i++) {
      result[dest++] = otherTokens[i << 1] + delta;
      result[dest++] = otherTokens[(i << 1) + 1];
    }
    return result;
  }

  static Uint32List? insert(
    Uint32List? lineTokens,
    int chIndex,
    int textLength,
  ) {
    if (lineTokens == null || identical(lineTokens, emptyLineTokens)) {
      // nothing to do
      return lineTokens;
    }

    final tokens = lineTokens;
    final tokensCount = tokens.length >>> 1;

    var fromTokenIndex = LineTokens.findIndexInTokensArray(tokens, chIndex);
    if (fromTokenIndex > 0) {
      final fromTokenStartOffset = tokens[(fromTokenIndex - 1) << 1];
      if (fromTokenStartOffset == chIndex) {
        fromTokenIndex--;
      }
    }
    for (
      var tokenIndex = fromTokenIndex;
      tokenIndex < tokensCount;
      tokenIndex++
    ) {
      tokens[tokenIndex << 1] += textLength;
    }
    return lineTokens;
  }
}
