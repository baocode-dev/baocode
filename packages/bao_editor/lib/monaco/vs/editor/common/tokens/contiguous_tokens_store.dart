/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/tokens/contiguousTokensStore.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: a text model's tokens, one
// end-offset array per line, kept aligned with the text as it is edited.
// Deviations: [getTokens] returns the raw end-offset tokens (or the default
// token) instead of a `LineTokens`, which would copy them; a `Uint32List`
// stands in for `Uint32Array | ArrayBuffer`. `setMultilineTokens` is left
// to the caller, which sets lines one by one with [setTokens].

import 'dart:typed_data';

import '../encoded_token_attributes.dart';
import 'contiguous_tokens_editing.dart';
import 'line_tokens.dart';

class ContiguousTokensStore {
  ContiguousTokensStore(this._languageIdCodec);

  List<Uint32List?> _lineTokens = [];
  int _len = 0;
  final ILanguageIdCodec _languageIdCodec;

  void flush() {
    _lineTokens = [];
    _len = 0;
  }

  bool get hasTokens => _lineTokens.isNotEmpty;

  /// The end-offset tokens of the line at [lineIndex], or one default token
  /// over [lineText] when it has none.
  Uint32List getTokens(
    String topLevelLanguageId,
    int lineIndex,
    String lineText,
  ) {
    Uint32List? rawLineTokens;
    if (lineIndex < _len) {
      rawLineTokens = _lineTokens[lineIndex];
    }

    if (rawLineTokens != null && !identical(rawLineTokens, emptyLineTokens)) {
      return rawLineTokens;
    }

    final lineTokens = Uint32List(2);
    lineTokens[0] = lineText.length;
    lineTokens[1] = _getDefaultMetadata(
      _languageIdCodec.encodeLanguageId(topLevelLanguageId),
    );
    return lineTokens;
  }

  /// Whether the line at [lineIndex] has tokens of its own, rather than the
  /// default [getTokens] makes up.
  bool hasLineTokens(int lineIndex) =>
      lineIndex < _len && _lineTokens[lineIndex] != null;

  static Uint32List _massageTokens(
    int topLevelLanguageId,
    int lineTextLength,
    Uint32List? tokens,
  ) {
    if (lineTextLength == 0) {
      var hasDifferentLanguageId = false;
      if (tokens != null && tokens.length > 1) {
        hasDifferentLanguageId =
            TokenMetadata.getLanguageId(tokens[1]) != topLevelLanguageId;
      }

      if (!hasDifferentLanguageId) {
        return emptyLineTokens;
      }
    }

    if (tokens == null || tokens.isEmpty) {
      final tokens = Uint32List(2);
      tokens[0] = lineTextLength;
      tokens[1] = _getDefaultMetadata(topLevelLanguageId);
      return tokens;
    }

    // Ensure the last token covers the end of the text
    tokens[tokens.length - 2] = lineTextLength;

    return tokens;
  }

  void _ensureLine(int lineIndex) {
    while (lineIndex >= _len) {
      _lineTokens.add(null);
      _len++;
    }
  }

  void _deleteLines(int start, int deleteCount) {
    if (deleteCount == 0) {
      return;
    }
    if (start + deleteCount > _len) {
      deleteCount = _len - start;
    }
    _lineTokens.removeRange(start, start + deleteCount);
    _len -= deleteCount;
  }

  void _insertLines(int insertIndex, int insertCount) {
    if (insertCount == 0) {
      return;
    }
    _lineTokens.insertAll(
      insertIndex,
      List<Uint32List?>.filled(insertCount, null),
    );
    _len += insertCount;
  }

  bool setTokens(
    String topLevelLanguageId,
    int lineIndex,
    int lineTextLength,
    Uint32List? tokens,
    bool checkEquality,
  ) {
    final massaged = _massageTokens(
      _languageIdCodec.encodeLanguageId(topLevelLanguageId),
      lineTextLength,
      tokens,
    );
    _ensureLine(lineIndex);
    final oldTokens = _lineTokens[lineIndex];
    _lineTokens[lineIndex] = massaged;

    if (checkEquality) {
      return !_equals(oldTokens, massaged);
    }
    return false;
  }

  static bool _equals(Uint32List? a, Uint32List? b) {
    if (a == null || b == null) {
      return a == null && b == null;
    }

    if (a.length != b.length) {
      return false;
    }
    for (var i = 0, len = a.length; i < len; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  //#region Editing

  /// The text in the one-based range from (`startLineNumber`,
  /// `startColumn`) to (`endLineNumber`, `endColumn`) was replaced by text
  /// of [eolCount] line breaks whose first line is [firstLineLength] long.
  void acceptEdit(
    ({int startLineNumber, int startColumn, int endLineNumber, int endColumn})
    range,
    int eolCount,
    int firstLineLength,
  ) {
    _acceptDeleteRange(range);
    _acceptInsertText(
      range.startLineNumber,
      range.startColumn,
      eolCount,
      firstLineLength,
    );
  }

  void _acceptDeleteRange(
    ({int startLineNumber, int startColumn, int endLineNumber, int endColumn})
    range,
  ) {
    final firstLineIndex = range.startLineNumber - 1;
    if (firstLineIndex >= _len) {
      return;
    }

    if (range.startLineNumber == range.endLineNumber) {
      if (range.startColumn == range.endColumn) {
        // Nothing to delete
        return;
      }

      _lineTokens[firstLineIndex] = ContiguousTokensEditing.delete(
        _lineTokens[firstLineIndex],
        range.startColumn - 1,
        range.endColumn - 1,
      );
      return;
    }

    _lineTokens[firstLineIndex] = ContiguousTokensEditing.deleteEnding(
      _lineTokens[firstLineIndex],
      range.startColumn - 1,
    );

    final lastLineIndex = range.endLineNumber - 1;
    Uint32List? lastLineTokens;
    if (lastLineIndex < _len) {
      lastLineTokens = ContiguousTokensEditing.deleteBeginning(
        _lineTokens[lastLineIndex],
        range.endColumn - 1,
      );
    }

    // Take remaining text on last line and append it to remaining text on first line
    _lineTokens[firstLineIndex] = ContiguousTokensEditing.append(
      _lineTokens[firstLineIndex],
      lastLineTokens,
    );

    // Delete middle lines
    _deleteLines(
      range.startLineNumber,
      range.endLineNumber - range.startLineNumber,
    );
  }

  void _acceptInsertText(
    int lineNumber,
    int column,
    int eolCount,
    int firstLineLength,
  ) {
    if (eolCount == 0 && firstLineLength == 0) {
      // Nothing to insert
      return;
    }

    final lineIndex = lineNumber - 1;
    if (lineIndex >= _len) {
      return;
    }

    if (eolCount == 0) {
      // Inserting text on one line
      _lineTokens[lineIndex] = ContiguousTokensEditing.insert(
        _lineTokens[lineIndex],
        column - 1,
        firstLineLength,
      );
      return;
    }

    _lineTokens[lineIndex] = ContiguousTokensEditing.deleteEnding(
      _lineTokens[lineIndex],
      column - 1,
    );
    _lineTokens[lineIndex] = ContiguousTokensEditing.insert(
      _lineTokens[lineIndex],
      column - 1,
      firstLineLength,
    );

    _insertLines(lineNumber, eolCount);
  }

  //#endregion
}

int _getDefaultMetadata(int topLevelLanguageId) =>
    ((topLevelLanguageId << MetadataConsts.languageIdOffset) |
        (StandardTokenType.other << MetadataConsts.tokenTypeOffset) |
        (FontStyle.none << MetadataConsts.fontStyleOffset) |
        (ColorId.defaultForeground << MetadataConsts.foregroundOffset) |
        (ColorId.defaultBackground << MetadataConsts.backgroundOffset) |
        // If there is no grammar, we just take a guess and try to match brackets.
        (MetadataConsts.balancedBracketsMask)) >>>
    0;
