/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/cursor/cursorWordOperations.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971.
// Deviations: no Intl.Segmenter words (see word_character_classifier.dart);
// `deleteWordLeft`/`deleteWordRight` take the auto-closing-pair check as a
// precomputed flag instead of a DeleteWordContext; `word` returns a Range for
// the first (non-drag) word selection and `wordDrag` the dragged position,
// instead of SingleCursorState. The word-part operations
// (`WordPartOperations`) take the same flags as `deleteWordLeft` and
// `deleteWordRight`; `deleteInsideWord` is not ported.

import '../../../base/common/strings.dart' as strings;
import '../core/position.dart';
import '../core/range.dart';
import '../core/selection.dart';
import '../core/word_character_classifier.dart';
import 'cursor_common.dart';

class _FindWordResult {
  const _FindWordResult(
    this.start,
    this.end,
    this.wordType,
    this.nextCharClass,
  );

  /// The index where the word starts.
  final int start;

  /// The index where the word ends.
  final int end;
  final _WordType wordType;

  /// The reason the word ended.
  final int nextCharClass;
}

enum _WordType { none, regular, separator }

enum WordNavigationType { wordStart, wordStartFast, wordEnd, wordAccessibility }

/// A word and its one-based columns, like upstream IWordAtPosition.
class WordAtPosition {
  const WordAtPosition(this.word, this.startColumn, this.endColumn);

  final String word;
  final int startColumn;
  final int endColumn;
}

abstract final class WordOperations {
  static _FindWordResult? _findPreviousWordOnLine(
    WordCharacterClassifier wordSeparators,
    ICursorSimpleModel model,
    Position position,
  ) => _doFindPreviousWordOnLine(
    model.getLineContent(position.lineNumber),
    wordSeparators,
    position,
  );

  static _FindWordResult? _doFindPreviousWordOnLine(
    String lineContent,
    WordCharacterClassifier wordSeparators,
    Position position,
  ) {
    var wordType = _WordType.none;
    for (var chIndex = position.column - 2; chIndex >= 0; chIndex--) {
      final chClass = wordSeparators.get(lineContent.codeUnitAt(chIndex));
      if (chClass == WordCharacterClass.regular) {
        if (wordType == _WordType.separator) {
          return _FindWordResult(
            chIndex + 1,
            _findEndOfWord(lineContent, wordSeparators, wordType, chIndex + 1),
            wordType,
            chClass,
          );
        }
        wordType = _WordType.regular;
      } else if (chClass == WordCharacterClass.wordSeparator) {
        if (wordType == _WordType.regular) {
          return _FindWordResult(
            chIndex + 1,
            _findEndOfWord(lineContent, wordSeparators, wordType, chIndex + 1),
            wordType,
            chClass,
          );
        }
        wordType = _WordType.separator;
      } else if (chClass == WordCharacterClass.whitespace) {
        if (wordType != _WordType.none) {
          return _FindWordResult(
            chIndex + 1,
            _findEndOfWord(lineContent, wordSeparators, wordType, chIndex + 1),
            wordType,
            chClass,
          );
        }
      }
    }
    if (wordType != _WordType.none) {
      return _FindWordResult(
        0,
        _findEndOfWord(lineContent, wordSeparators, wordType, 0),
        wordType,
        WordCharacterClass.whitespace,
      );
    }
    return null;
  }

  static int _findEndOfWord(
    String lineContent,
    WordCharacterClassifier wordSeparators,
    _WordType wordType,
    int startIndex,
  ) {
    final len = lineContent.length;
    for (var chIndex = startIndex; chIndex < len; chIndex++) {
      final chClass = wordSeparators.get(lineContent.codeUnitAt(chIndex));
      if (chClass == WordCharacterClass.whitespace) return chIndex;
      if (wordType == _WordType.regular &&
          chClass == WordCharacterClass.wordSeparator) {
        return chIndex;
      }
      if (wordType == _WordType.separator &&
          chClass == WordCharacterClass.regular) {
        return chIndex;
      }
    }
    return len;
  }

  static _FindWordResult? _findNextWordOnLine(
    WordCharacterClassifier wordSeparators,
    ICursorSimpleModel model,
    Position position,
  ) => _doFindNextWordOnLine(
    model.getLineContent(position.lineNumber),
    wordSeparators,
    position,
  );

  static _FindWordResult? _doFindNextWordOnLine(
    String lineContent,
    WordCharacterClassifier wordSeparators,
    Position position,
  ) {
    var wordType = _WordType.none;
    final len = lineContent.length;
    for (var chIndex = position.column - 1; chIndex < len; chIndex++) {
      final chClass = wordSeparators.get(lineContent.codeUnitAt(chIndex));
      if (chClass == WordCharacterClass.regular) {
        if (wordType == _WordType.separator) {
          return _FindWordResult(
            _findStartOfWord(
              lineContent,
              wordSeparators,
              wordType,
              chIndex - 1,
            ),
            chIndex,
            wordType,
            chClass,
          );
        }
        wordType = _WordType.regular;
      } else if (chClass == WordCharacterClass.wordSeparator) {
        if (wordType == _WordType.regular) {
          return _FindWordResult(
            _findStartOfWord(
              lineContent,
              wordSeparators,
              wordType,
              chIndex - 1,
            ),
            chIndex,
            wordType,
            chClass,
          );
        }
        wordType = _WordType.separator;
      } else if (chClass == WordCharacterClass.whitespace) {
        if (wordType != _WordType.none) {
          return _FindWordResult(
            _findStartOfWord(
              lineContent,
              wordSeparators,
              wordType,
              chIndex - 1,
            ),
            chIndex,
            wordType,
            chClass,
          );
        }
      }
    }
    if (wordType != _WordType.none) {
      return _FindWordResult(
        _findStartOfWord(lineContent, wordSeparators, wordType, len - 1),
        len,
        wordType,
        WordCharacterClass.whitespace,
      );
    }
    return null;
  }

  static int _findStartOfWord(
    String lineContent,
    WordCharacterClassifier wordSeparators,
    _WordType wordType,
    int startIndex,
  ) {
    for (var chIndex = startIndex; chIndex >= 0; chIndex--) {
      final chClass = wordSeparators.get(lineContent.codeUnitAt(chIndex));
      if (chClass == WordCharacterClass.whitespace) return chIndex + 1;
      if (wordType == _WordType.regular &&
          chClass == WordCharacterClass.wordSeparator) {
        return chIndex + 1;
      }
      if (wordType == _WordType.separator &&
          chClass == WordCharacterClass.regular) {
        return chIndex + 1;
      }
    }
    return 0;
  }

  static Position moveWordLeft(
    WordCharacterClassifier wordSeparators,
    ICursorSimpleModel model,
    Position position,
    WordNavigationType wordNavigationType,
    bool hasMulticursor,
  ) {
    var lineNumber = position.lineNumber;
    var column = position.column;
    if (column == 1) {
      if (lineNumber > 1) {
        lineNumber = lineNumber - 1;
        column = model.getLineMaxColumn(lineNumber);
      }
    }
    var prevWordOnLine = _findPreviousWordOnLine(
      wordSeparators,
      model,
      Position(lineNumber, column),
    );
    if (wordNavigationType == WordNavigationType.wordStart) {
      return Position(
        lineNumber,
        prevWordOnLine != null ? prevWordOnLine.start + 1 : 1,
      );
    }
    if (wordNavigationType == WordNavigationType.wordStartFast) {
      if (!hasMulticursor &&
          prevWordOnLine != null &&
          prevWordOnLine.wordType == _WordType.separator &&
          prevWordOnLine.end - prevWordOnLine.start == 1 &&
          prevWordOnLine.nextCharClass == WordCharacterClass.regular) {
        // Skip over a word made up of one single separator and followed by a
        // regular character
        prevWordOnLine = _findPreviousWordOnLine(
          wordSeparators,
          model,
          Position(lineNumber, prevWordOnLine.start + 1),
        );
      }
      return Position(
        lineNumber,
        prevWordOnLine != null ? prevWordOnLine.start + 1 : 1,
      );
    }
    if (wordNavigationType == WordNavigationType.wordAccessibility) {
      while (prevWordOnLine != null &&
          prevWordOnLine.wordType == _WordType.separator) {
        // Skip over words made up of only separators
        prevWordOnLine = _findPreviousWordOnLine(
          wordSeparators,
          model,
          Position(lineNumber, prevWordOnLine.start + 1),
        );
      }
      return Position(
        lineNumber,
        prevWordOnLine != null ? prevWordOnLine.start + 1 : 1,
      );
    }
    // We are stopping at the ending of words
    if (prevWordOnLine != null && column <= prevWordOnLine.end + 1) {
      prevWordOnLine = _findPreviousWordOnLine(
        wordSeparators,
        model,
        Position(lineNumber, prevWordOnLine.start + 1),
      );
    }
    return Position(
      lineNumber,
      prevWordOnLine != null ? prevWordOnLine.end + 1 : 1,
    );
  }

  static Position moveWordRight(
    WordCharacterClassifier wordSeparators,
    ICursorSimpleModel model,
    Position position,
    WordNavigationType wordNavigationType,
  ) {
    var lineNumber = position.lineNumber;
    var column = position.column;
    var movedDown = false;
    if (column == model.getLineMaxColumn(lineNumber)) {
      if (lineNumber < model.getLineCount()) {
        movedDown = true;
        lineNumber = lineNumber + 1;
        column = 1;
      }
    }
    var nextWordOnLine = _findNextWordOnLine(
      wordSeparators,
      model,
      Position(lineNumber, column),
    );
    if (wordNavigationType == WordNavigationType.wordEnd) {
      if (nextWordOnLine != null &&
          nextWordOnLine.wordType == _WordType.separator) {
        if (nextWordOnLine.end - nextWordOnLine.start == 1 &&
            nextWordOnLine.nextCharClass == WordCharacterClass.regular) {
          // Skip over a word made up of one single separator and followed by
          // a regular character
          nextWordOnLine = _findNextWordOnLine(
            wordSeparators,
            model,
            Position(lineNumber, nextWordOnLine.end + 1),
          );
        }
      }
      column = nextWordOnLine != null
          ? nextWordOnLine.end + 1
          : model.getLineMaxColumn(lineNumber);
    } else if (wordNavigationType == WordNavigationType.wordAccessibility) {
      if (movedDown) {
        // Pretend that the cursor is right before the first character.
        column = 0;
      }
      while (nextWordOnLine != null &&
          (nextWordOnLine.wordType == _WordType.separator ||
              nextWordOnLine.start + 1 <= column)) {
        nextWordOnLine = _findNextWordOnLine(
          wordSeparators,
          model,
          Position(lineNumber, nextWordOnLine.end + 1),
        );
      }
      column = nextWordOnLine != null
          ? nextWordOnLine.start + 1
          : model.getLineMaxColumn(lineNumber);
    } else {
      if (nextWordOnLine != null &&
          !movedDown &&
          column >= nextWordOnLine.start + 1) {
        nextWordOnLine = _findNextWordOnLine(
          wordSeparators,
          model,
          Position(lineNumber, nextWordOnLine.end + 1),
        );
      }
      column = nextWordOnLine != null
          ? nextWordOnLine.start + 1
          : model.getLineMaxColumn(lineNumber);
    }
    return Position(lineNumber, column);
  }

  static Range? _deleteWordLeftWhitespace(
    ICursorSimpleModel model,
    Position position,
  ) {
    final lineContent = model.getLineContent(position.lineNumber);
    final startIndex = position.column - 2;
    final lastNonWhitespace = lastNonWhitespaceIndex(lineContent, startIndex);
    if (lastNonWhitespace + 1 < startIndex) {
      return Range(
        position.lineNumber,
        lastNonWhitespace + 2,
        position.lineNumber,
        position.column,
      );
    }
    return null;
  }

  /// [isAutoClosingPairDelete] replaces upstream's DeleteWordContext check
  /// (`DeleteOperations.isAutoClosingPairDelete`).
  static Range? deleteWordLeft(
    WordCharacterClassifier wordSeparators,
    ICursorSimpleModel model,
    Selection selection,
    WordNavigationType wordNavigationType, {
    bool whitespaceHeuristics = true,
    bool isAutoClosingPairDelete = false,
  }) {
    if (!selection.isEmpty()) return selection;
    if (isAutoClosingPairDelete) {
      final position = selection.getPosition();
      return Range(
        position.lineNumber,
        position.column - 1,
        position.lineNumber,
        position.column + 1,
      );
    }
    final position = Position(
      selection.positionLineNumber,
      selection.positionColumn,
    );
    var lineNumber = position.lineNumber;
    var column = position.column;
    if (lineNumber == 1 && column == 1) {
      // Ignore deleting at beginning of file
      return null;
    }
    if (whitespaceHeuristics) {
      final r = _deleteWordLeftWhitespace(model, position);
      if (r != null) return r;
    }
    var prevWordOnLine = _findPreviousWordOnLine(
      wordSeparators,
      model,
      position,
    );
    if (wordNavigationType == WordNavigationType.wordStart) {
      if (prevWordOnLine != null) {
        column = prevWordOnLine.start + 1;
      } else if (column > 1) {
        column = 1;
      } else {
        lineNumber--;
        column = model.getLineMaxColumn(lineNumber);
      }
    } else {
      if (prevWordOnLine != null && column <= prevWordOnLine.end + 1) {
        prevWordOnLine = _findPreviousWordOnLine(
          wordSeparators,
          model,
          Position(lineNumber, prevWordOnLine.start + 1),
        );
      }
      if (prevWordOnLine != null) {
        column = prevWordOnLine.end + 1;
      } else if (column > 1) {
        column = 1;
      } else {
        lineNumber--;
        column = model.getLineMaxColumn(lineNumber);
      }
    }
    return Range(lineNumber, column, position.lineNumber, position.column);
  }

  static int _findFirstNonWhitespaceChar(String str, int startIndex) {
    for (var chIndex = startIndex; chIndex < str.length; chIndex++) {
      final ch = str.codeUnitAt(chIndex);
      if (ch != 0x20 && ch != 0x09) return chIndex;
    }
    return str.length;
  }

  static Range? _deleteWordRightWhitespace(
    ICursorSimpleModel model,
    Position position,
  ) {
    final lineContent = model.getLineContent(position.lineNumber);
    final startIndex = position.column - 1;
    final firstNonWhitespace = _findFirstNonWhitespaceChar(
      lineContent,
      startIndex,
    );
    if (startIndex < firstNonWhitespace) {
      return Range(
        position.lineNumber,
        position.column,
        position.lineNumber,
        firstNonWhitespace + 1,
      );
    }
    return null;
  }

  static Range? deleteWordRight(
    WordCharacterClassifier wordSeparators,
    ICursorSimpleModel model,
    Selection selection,
    WordNavigationType wordNavigationType, {
    bool whitespaceHeuristics = true,
  }) {
    if (!selection.isEmpty()) return selection;
    final position = Position(
      selection.positionLineNumber,
      selection.positionColumn,
    );
    var lineNumber = position.lineNumber;
    var column = position.column;
    final lineCount = model.getLineCount();
    final maxColumn = model.getLineMaxColumn(lineNumber);
    if (lineNumber == lineCount && column == maxColumn) {
      // Ignore deleting at end of file
      return null;
    }
    if (whitespaceHeuristics) {
      final r = _deleteWordRightWhitespace(model, position);
      if (r != null) return r;
    }
    var nextWordOnLine = _findNextWordOnLine(wordSeparators, model, position);
    if (wordNavigationType == WordNavigationType.wordEnd) {
      if (nextWordOnLine != null) {
        column = nextWordOnLine.end + 1;
      } else if (column < maxColumn || lineNumber == lineCount) {
        column = maxColumn;
      } else {
        lineNumber++;
        nextWordOnLine = _findNextWordOnLine(
          wordSeparators,
          model,
          Position(lineNumber, 1),
        );
        column = nextWordOnLine != null
            ? nextWordOnLine.start + 1
            : model.getLineMaxColumn(lineNumber);
      }
    } else {
      if (nextWordOnLine != null && column >= nextWordOnLine.start + 1) {
        nextWordOnLine = _findNextWordOnLine(
          wordSeparators,
          model,
          Position(lineNumber, nextWordOnLine.end + 1),
        );
      }
      if (nextWordOnLine != null) {
        column = nextWordOnLine.start + 1;
      } else if (column < maxColumn || lineNumber == lineCount) {
        column = maxColumn;
      } else {
        lineNumber++;
        nextWordOnLine = _findNextWordOnLine(
          wordSeparators,
          model,
          Position(lineNumber, 1),
        );
        column = nextWordOnLine != null
            ? nextWordOnLine.start + 1
            : model.getLineMaxColumn(lineNumber);
      }
    }
    return Range(lineNumber, column, position.lineNumber, position.column);
  }

  static WordAtPosition? getWordAtPosition(
    ICursorSimpleModel model,
    WordCharacterClassifier wordSeparators,
    Position position,
  ) {
    final line = model.getLineContent(position.lineNumber);
    final prevWord = _findPreviousWordOnLine(wordSeparators, model, position);
    if (prevWord != null &&
        prevWord.wordType == _WordType.regular &&
        prevWord.start <= position.column - 1 &&
        position.column - 1 <= prevWord.end) {
      return WordAtPosition(
        line.substring(prevWord.start, prevWord.end),
        prevWord.start + 1,
        prevWord.end + 1,
      );
    }
    final nextWord = _findNextWordOnLine(wordSeparators, model, position);
    if (nextWord != null &&
        nextWord.wordType == _WordType.regular &&
        nextWord.start <= position.column - 1 &&
        position.column - 1 <= nextWord.end) {
      return WordAtPosition(
        line.substring(nextWord.start, nextWord.end),
        nextWord.start + 1,
        nextWord.end + 1,
      );
    }
    return null;
  }

  /// The range selected when entering word selection (double click) at
  /// [position]: the touched word, or the whitespace between words.
  static Range word(
    WordCharacterClassifier wordSeparators,
    ICursorSimpleModel model,
    Position position,
  ) {
    final prevWord = _findPreviousWordOnLine(wordSeparators, model, position);
    final nextWord = _findNextWordOnLine(wordSeparators, model, position);
    final column = position.column - 1;
    int startColumn;
    int endColumn;
    if (prevWord != null &&
        prevWord.wordType == _WordType.regular &&
        prevWord.start <= column &&
        column <= prevWord.end) {
      startColumn = prevWord.start + 1;
      endColumn = prevWord.end + 1;
    } else if (prevWord != null &&
        prevWord.wordType == _WordType.separator &&
        prevWord.start <= column &&
        column < prevWord.end) {
      startColumn = prevWord.start + 1;
      endColumn = prevWord.end + 1;
    } else if (nextWord != null &&
        nextWord.wordType == _WordType.regular &&
        nextWord.start <= column &&
        column <= nextWord.end) {
      startColumn = nextWord.start + 1;
      endColumn = nextWord.end + 1;
    } else if (nextWord != null &&
        nextWord.wordType == _WordType.separator &&
        nextWord.start <= column &&
        column < nextWord.end) {
      startColumn = nextWord.start + 1;
      endColumn = nextWord.end + 1;
    } else {
      startColumn = prevWord != null ? prevWord.end + 1 : 1;
      endColumn = nextWord != null
          ? nextWord.start + 1
          : model.getLineMaxColumn(position.lineNumber);
    }
    return Range(
      position.lineNumber,
      startColumn,
      position.lineNumber,
      endColumn,
    );
  }

  /// Word-granular drag after a double click: the column to extend to when
  /// the pointer is at [position] and the initial word was [selectionStart].
  static Position wordDrag(
    WordCharacterClassifier wordSeparators,
    ICursorSimpleModel model,
    Range selectionStart,
    Position position,
  ) {
    final prevWord = _findPreviousWordOnLine(wordSeparators, model, position);
    final nextWord = _findNextWordOnLine(wordSeparators, model, position);
    final c = position.column - 1;
    int startColumn;
    int endColumn;
    if (prevWord != null &&
        prevWord.wordType == _WordType.regular &&
        prevWord.start < c &&
        c < prevWord.end) {
      startColumn = prevWord.start + 1;
      endColumn = prevWord.end + 1;
    } else if (nextWord != null &&
        nextWord.wordType == _WordType.regular &&
        nextWord.start < c &&
        c < nextWord.end) {
      startColumn = nextWord.start + 1;
      endColumn = nextWord.end + 1;
    } else {
      startColumn = position.column;
      endColumn = position.column;
    }
    final lineNumber = position.lineNumber;
    int column;
    if (selectionStart.containsPosition(position)) {
      column = selectionStart.endColumn;
    } else if (position.isBeforeOrEqual(selectionStart.getStartPosition())) {
      column = startColumn;
      if (selectionStart.containsPosition(Position(lineNumber, column))) {
        column = selectionStart.endColumn;
      }
    } else {
      column = endColumn;
      if (selectionStart.containsPosition(Position(lineNumber, column))) {
        column = selectionStart.startColumn;
      }
    }
    return Position(lineNumber, column);
  }

  static bool _isLowerOrDigit(int code) =>
      strings.isLowerAsciiLetter(code) || (code >= 0x30 && code <= 0x39);

  static Position _moveWordPartLeft(
    ICursorSimpleModel model,
    Position position,
  ) {
    final lineNumber = position.lineNumber;
    final maxColumn = model.getLineMaxColumn(lineNumber);
    if (position.column == 1) {
      return lineNumber > 1
          ? Position(lineNumber - 1, model.getLineMaxColumn(lineNumber - 1))
          : position;
    }
    final lineContent = model.getLineContent(lineNumber);
    for (var column = position.column - 1; column > 1; column--) {
      final left = lineContent.codeUnitAt(column - 2);
      final right = lineContent.codeUnitAt(column - 1);
      // snake_case_variables
      if (left == 0x5F && right != 0x5F) return Position(lineNumber, column);
      // kebab-case-variables
      if (left == 0x2D && right != 0x2D) return Position(lineNumber, column);
      // camelCaseVariables
      if (_isLowerOrDigit(left) && strings.isUpperAsciiLetter(right)) {
        return Position(lineNumber, column);
      }
      // thisIsACamelCaseWithOneLetterWords
      if (strings.isUpperAsciiLetter(left) &&
          strings.isUpperAsciiLetter(right) &&
          column + 1 < maxColumn &&
          _isLowerOrDigit(lineContent.codeUnitAt(column))) {
        return Position(lineNumber, column);
      }
    }
    return Position(lineNumber, 1);
  }

  static Position _moveWordPartRight(
    ICursorSimpleModel model,
    Position position,
  ) {
    final lineNumber = position.lineNumber;
    final maxColumn = model.getLineMaxColumn(lineNumber);
    if (position.column == maxColumn) {
      return lineNumber < model.getLineCount()
          ? Position(lineNumber + 1, 1)
          : position;
    }
    final lineContent = model.getLineContent(lineNumber);
    for (var column = position.column + 1; column < maxColumn; column++) {
      final left = lineContent.codeUnitAt(column - 2);
      final right = lineContent.codeUnitAt(column - 1);
      // snake_case_variables
      if (left != 0x5F && right == 0x5F) return Position(lineNumber, column);
      // kebab-case-variables
      if (left != 0x2D && right == 0x2D) return Position(lineNumber, column);
      // camelCaseVariables
      if (_isLowerOrDigit(left) && strings.isUpperAsciiLetter(right)) {
        return Position(lineNumber, column);
      }
      // thisIsACamelCaseWithOneLetterWords
      if (strings.isUpperAsciiLetter(left) &&
          strings.isUpperAsciiLetter(right) &&
          column + 1 < maxColumn &&
          _isLowerOrDigit(lineContent.codeUnitAt(column))) {
        return Position(lineNumber, column);
      }
    }
    return Position(lineNumber, maxColumn);
  }

  static Range _deleteWordPartLeft(
    ICursorSimpleModel model,
    Selection selection,
  ) {
    if (!selection.isEmpty()) return selection;
    final pos = selection.getPosition();
    final to = _moveWordPartLeft(model, pos);
    return Range(pos.lineNumber, pos.column, to.lineNumber, to.column);
  }

  static Range _deleteWordPartRight(
    ICursorSimpleModel model,
    Selection selection,
  ) {
    if (!selection.isEmpty()) return selection;
    final pos = selection.getPosition();
    final to = _moveWordPartRight(model, pos);
    return Range(pos.lineNumber, pos.column, to.lineNumber, to.column);
  }
}

/// Word-part (camelCase, snake_case, kebab-case) navigation: the nearest of
/// the word starts, the word ends and the word-part boundaries.
abstract final class WordPartOperations {
  static Range deleteWordPartLeft(
    WordCharacterClassifier wordSeparators,
    ICursorSimpleModel model,
    Selection selection, {
    bool whitespaceHeuristics = true,
    bool isAutoClosingPairDelete = false,
  }) {
    Range? delete(WordNavigationType type) => WordOperations.deleteWordLeft(
      wordSeparators,
      model,
      selection,
      type,
      whitespaceHeuristics: whitespaceHeuristics,
      isAutoClosingPairDelete: isAutoClosingPairDelete,
    );
    final candidates = [
      ?delete(WordNavigationType.wordStart),
      ?delete(WordNavigationType.wordEnd),
      WordOperations._deleteWordPartLeft(model, selection),
    ]..sort(Range.compareRangesUsingEnds);
    return candidates.last;
  }

  static Range deleteWordPartRight(
    WordCharacterClassifier wordSeparators,
    ICursorSimpleModel model,
    Selection selection, {
    bool whitespaceHeuristics = true,
  }) {
    Range? delete(WordNavigationType type) => WordOperations.deleteWordRight(
      wordSeparators,
      model,
      selection,
      type,
      whitespaceHeuristics: whitespaceHeuristics,
    );
    final candidates = [
      ?delete(WordNavigationType.wordStart),
      ?delete(WordNavigationType.wordEnd),
      WordOperations._deleteWordPartRight(model, selection),
    ]..sort(Range.compareRangesUsingStarts);
    return candidates.first;
  }

  static Position moveWordPartLeft(
    WordCharacterClassifier wordSeparators,
    ICursorSimpleModel model,
    Position position,
    bool hasMulticursor,
  ) {
    final candidates = [
      WordOperations.moveWordLeft(
        wordSeparators,
        model,
        position,
        WordNavigationType.wordStart,
        hasMulticursor,
      ),
      WordOperations.moveWordLeft(
        wordSeparators,
        model,
        position,
        WordNavigationType.wordEnd,
        hasMulticursor,
      ),
      WordOperations._moveWordPartLeft(model, position),
    ]..sort(Position.compare);
    return candidates.last;
  }

  static Position moveWordPartRight(
    WordCharacterClassifier wordSeparators,
    ICursorSimpleModel model,
    Position position,
  ) {
    final candidates = [
      WordOperations.moveWordRight(
        wordSeparators,
        model,
        position,
        WordNavigationType.wordStart,
      ),
      WordOperations.moveWordRight(
        wordSeparators,
        model,
        position,
        WordNavigationType.wordEnd,
      ),
      WordOperations._moveWordPartRight(model, position),
    ]..sort(Position.compare);
    return candidates.first;
  }
}
