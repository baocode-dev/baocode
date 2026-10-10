/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The word at a position, for default completion and rename ranges.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/common/core/wordHelper.ts (`USUAL_WORD_SEPARATORS`,
// `DEFAULT_WORD_REGEXP`, `getWordAtText`).
//
// Deviations:
// - Always the default word definition (language configurations are not
//   consulted) and a plain scan of the line instead of the windowed search.

/// `USUAL_WORD_SEPARATORS`.
const usualWordSeparators = '`~!@#\$%^&*()-=+[{]}\\|;:\'",.<>/?';

/// `DEFAULT_WORD_REGEXP`.
final RegExp defaultWordRegExp = RegExp(
  r'(-?\d*\.\d\w*)|([^' +
      usualWordSeparators.split('').map(RegExp.escape).join() +
      r'\s]+)',
);

/// `IWordAtPosition`: one-based columns, [endColumn] exclusive.
class WordAtPosition {
  const WordAtPosition(this.word, this.startColumn, this.endColumn);

  final String word;
  final int startColumn;
  final int endColumn;
}

/// `getWordAtText`: the word of [text] around one-based [column].
WordAtPosition? getWordAtText(int column, String text) {
  final pos = column - 1;
  for (final match in defaultWordRegExp.allMatches(text)) {
    if (match.start > pos) break;
    if (match.start <= pos && match.end >= pos) {
      return WordAtPosition(match[0]!, match.start + 1, match.end + 1);
    }
  }
  return null;
}
