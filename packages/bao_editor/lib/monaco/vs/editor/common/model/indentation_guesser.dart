/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/model/indentationGuesser.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971. The ITextBuffer source is
// replaced by a line count and a line-content callback (one-based lines).

class _SpacesDiffResult {
  int spacesDiff = 0;
  bool looksLikeAlignment = false;
}

/// Compute the diff in spaces between two line's indentation.
void _spacesDiff(
  String a,
  int aLength,
  String b,
  int bLength,
  _SpacesDiffResult result,
) {
  result.spacesDiff = 0;
  result.looksLikeAlignment = false;
  // This can go both ways (e.g.):
  //  - a: "\t"
  //  - b: "\t    "
  //  => This should count 1 tab and 4 spaces
  var i = 0;
  for (; i < aLength && i < bLength; i++) {
    if (a.codeUnitAt(i) != b.codeUnitAt(i)) break;
  }
  var aSpacesCnt = 0, aTabsCount = 0;
  for (var j = i; j < aLength; j++) {
    if (a.codeUnitAt(j) == 0x20) {
      aSpacesCnt++;
    } else {
      aTabsCount++;
    }
  }
  var bSpacesCnt = 0, bTabsCount = 0;
  for (var j = i; j < bLength; j++) {
    if (b.codeUnitAt(j) == 0x20) {
      bSpacesCnt++;
    } else {
      bTabsCount++;
    }
  }
  if (aSpacesCnt > 0 && aTabsCount > 0) return;
  if (bSpacesCnt > 0 && bTabsCount > 0) return;
  final tabsDiff = (aTabsCount - bTabsCount).abs();
  final spacesDiff = (aSpacesCnt - bSpacesCnt).abs();
  if (tabsDiff == 0) {
    // check if the indentation difference might be caused by alignment
    // reasons; sometime folks like to align their code, but this should not
    // be used as a hint
    result.spacesDiff = spacesDiff;
    if (spacesDiff > 0 &&
        0 <= bSpacesCnt - 1 &&
        bSpacesCnt - 1 < a.length &&
        bSpacesCnt < b.length) {
      if (b.codeUnitAt(bSpacesCnt) != 0x20 &&
          a.codeUnitAt(bSpacesCnt - 1) == 0x20) {
        if (a.codeUnitAt(a.length - 1) == 0x2C) {
          // This looks like an alignment desire: e.g.
          // const a = b + c,
          //       d = b - c;
          result.looksLikeAlignment = true;
        }
      }
    }
    return;
  }
  if (spacesDiff % tabsDiff == 0) {
    result.spacesDiff = spacesDiff ~/ tabsDiff;
  }
}

class GuessedIndentation {
  const GuessedIndentation(this.tabSize, this.insertSpaces);

  /// If indentation is based on spaces (`insertSpaces` = true), the number
  /// of spaces that make an indent.
  final int tabSize;

  /// Is indentation based on spaces?
  final bool insertSpaces;

  @override
  String toString() =>
      'GuessedIndentation(tabSize: $tabSize, insertSpaces: $insertSpaces)';
}

GuessedIndentation guessIndentation(
  int lineCount,
  String Function(int lineNumber) getLineContent,
  int defaultTabSize,
  bool defaultInsertSpaces,
) {
  // Look at most at the first 10k lines
  final linesCount = lineCount < 10000 ? lineCount : 10000;
  // number of lines that contain at least one tab in indentation
  var linesIndentedWithTabsCount = 0;
  // number of lines that contain only spaces in indentation
  var linesIndentedWithSpacesCount = 0;
  // content of latest line that contained non-whitespace chars
  var previousLineText = '';
  // index at which latest line contained the first non-whitespace char
  var previousLineIndentation = 0;
  // prefer even guesses for `tabSize`, limit to [2, 8].
  const allowedTabSizeGuesses = [2, 4, 6, 8, 3, 5, 7];
  const maxAllowedTabSizeGuess = 8;
  final spacesDiffCount = List<int>.filled(9, 0); // `tabSize` scores
  final tmp = _SpacesDiffResult();
  for (var lineNumber = 1; lineNumber <= linesCount; lineNumber++) {
    final currentLineText = getLineContent(lineNumber);
    final currentLineLength = currentLineText.length;
    var currentLineHasContent = false;
    var currentLineIndentation = 0;
    var currentLineSpacesCount = 0;
    var currentLineTabsCount = 0;
    for (var j = 0; j < currentLineLength; j++) {
      final charCode = currentLineText.codeUnitAt(j);
      if (charCode == 0x09) {
        currentLineTabsCount++;
      } else if (charCode == 0x20) {
        currentLineSpacesCount++;
      } else {
        // Hit non whitespace character on this line
        currentLineHasContent = true;
        currentLineIndentation = j;
        break;
      }
    }
    // Ignore empty or only whitespace lines
    if (!currentLineHasContent) continue;
    if (currentLineTabsCount > 0) {
      linesIndentedWithTabsCount++;
    } else if (currentLineSpacesCount > 1) {
      linesIndentedWithSpacesCount++;
    }
    _spacesDiff(
      previousLineText,
      previousLineIndentation,
      currentLineText,
      currentLineIndentation,
      tmp,
    );
    if (tmp.looksLikeAlignment) {
      // if defaultInsertSpaces === true && the spaces count == tabSize, we
      // may want to count it as valid indentation; otherwise skip this line
      if (!(defaultInsertSpaces && defaultTabSize == tmp.spacesDiff)) {
        continue;
      }
    }
    final currentSpacesDiff = tmp.spacesDiff;
    if (currentSpacesDiff <= maxAllowedTabSizeGuess) {
      spacesDiffCount[currentSpacesDiff]++;
    }
    previousLineText = currentLineText;
    previousLineIndentation = currentLineIndentation;
  }
  var insertSpaces = defaultInsertSpaces;
  if (linesIndentedWithTabsCount != linesIndentedWithSpacesCount) {
    insertSpaces = linesIndentedWithTabsCount < linesIndentedWithSpacesCount;
  }
  var tabSize = defaultTabSize;
  // Guess tabSize only if inserting spaces...
  if (insertSpaces) {
    var tabSizeScore = 0;
    for (final possibleTabSize in allowedTabSizeGuesses) {
      final possibleTabSizeScore = spacesDiffCount[possibleTabSize];
      if (possibleTabSizeScore > tabSizeScore) {
        tabSizeScore = possibleTabSizeScore;
        tabSize = possibleTabSize;
      }
    }
    // Let a tabSize of 2 win over 4 only if it has at least 2/3 of the
    // occurrences of 4
    if (tabSize == 4 &&
        spacesDiffCount[4] > 0 &&
        spacesDiffCount[2] > 0 &&
        spacesDiffCount[2] >= spacesDiffCount[4] * 2 / 3) {
      tabSize = 2;
    }
  }
  return GuessedIndentation(tabSize, insertSpaces);
}
