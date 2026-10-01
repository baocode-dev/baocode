/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/contrib/smartSelect/browser/
// {smartSelect,wordSelections,bracketSelections}.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971 (`provideSelectionRanges`,
// `SelectionRanges`, `WordSelectionRangeProvider`,
// `BracketSelectionRangeProvider`).
//
// Deviations:
// - Only the providers upstream falls back to when no language provides
//   selection ranges (words and brackets): the IDE's language services have
//   no `textDocument/selectionRange` request.
// - Words are those of the editor's word separators
//   (`WordOperations.getWordAtPosition`), not the language's word
//   definition.
// - Brackets are the language configuration's pairs matched as plain text,
//   so brackets in strings and comments count; the search is synchronous
//   and scans at most [SmartSelect.maxBracketSearchCharacters] characters in
//   each direction instead of yielding every 30 ms for two rounds.
// - The caller keeps the `SmartSelectController` state ([SelectionRanges]).

import '../../../../base/common/strings.dart'
    show isLowerAsciiLetter, isUpperAsciiLetter;
import '../../../common/core/position.dart';
import '../../../common/core/range.dart';
import '../../../common/core/word_character_classifier.dart';
import '../../../common/cursor/cursor_common.dart';
import '../../../common/cursor/cursor_word_operations.dart';
import '../../../common/languages/language_configuration.dart'
    show CharacterPair;

/// A cursor's selection ranges, smallest first, and the one selected.
class SelectionRanges {
  const SelectionRanges(this.index, this.ranges);

  final int index;
  final List<Range> ranges;

  Range get current => ranges[index];

  /// The next larger ([fwd]) or smaller range, skipping equal ones; this one
  /// at either end.
  SelectionRanges mov(bool fwd) {
    final next = index + (fwd ? 1 : -1);
    if (next < 0 || next >= ranges.length) return this;
    final res = SelectionRanges(next, ranges);
    if (res.ranges[next].equalsRange(ranges[index])) {
      // next range equals this range, retry with next-next
      return res.mov(fwd);
    }
    return res;
  }
}

abstract final class SmartSelect {
  /// How far the bracket search looks in each direction.
  static const maxBracketSearchCharacters = 1 << 20;

  /// The ranges expanding the selection at each of [positions] goes
  /// through, smallest first (upstream `provideSelectionRanges` with the
  /// `editor.smartSelect` defaults: subwords, and leading/trailing
  /// whitespace ranges).
  static List<List<Range>> provideSelectionRanges(
    ICursorSimpleModel model,
    WordCharacterClassifier wordSeparators,
    List<Position> positions, {
    List<CharacterPair> brackets = const [('(', ')'), ('[', ']'), ('{', '}')],
    bool selectLeadingAndTrailingWhitespace = true,
    bool selectSubwords = true,
  }) {
    final allRawRanges = <List<Range>>[
      for (final position in positions)
        [
          for (final range in [
            ..._bracketRanges(model, position, brackets),
            ..._wordRanges(model, wordSeparators, position, selectSubwords),
          ])
            if (range.containsPosition(position)) range,
        ],
    ];
    return [
      for (final oneRawRanges in allRawRanges)
        _normalize(model, oneRawRanges, selectLeadingAndTrailingWhitespace),
    ];
  }

  static List<Range> _normalize(
    ICursorSimpleModel model,
    List<Range> oneRawRanges,
    bool selectLeadingAndTrailingWhitespace,
  ) {
    if (oneRawRanges.isEmpty) return [];
    // sort all by start/end position
    oneRawRanges.sort((a, b) {
      if (a.getStartPosition().isBefore(b.getStartPosition())) return 1;
      if (b.getStartPosition().isBefore(a.getStartPosition())) return -1;
      if (a.getEndPosition().isBefore(b.getEndPosition())) return -1;
      if (b.getEndPosition().isBefore(a.getEndPosition())) return 1;
      return 0;
    });
    // remove ranges that don't contain the former range or that are equal to
    // the former range
    final oneRanges = <Range>[];
    Range? last;
    for (final range in oneRawRanges) {
      if (last == null ||
          (range.containsRange(last) && !range.equalsRange(last))) {
        oneRanges.add(range);
        last = range;
      }
    }
    if (!selectLeadingAndTrailingWhitespace) return oneRanges;

    // add ranges that expand trivia at line starts and ends whenever a range
    // wraps onto the a new line
    final oneRangesWithTrivia = <Range>[oneRanges[0]];
    for (var i = 1; i < oneRanges.length; i++) {
      final prev = oneRanges[i - 1];
      final cur = oneRanges[i];
      if (cur.startLineNumber != prev.startLineNumber ||
          cur.endLineNumber != prev.endLineNumber) {
        // add line/block range without leading/failing whitespace
        final rangeNoWhitespace = Range(
          prev.startLineNumber,
          model.getLineFirstNonWhitespaceColumn(prev.startLineNumber),
          prev.endLineNumber,
          model.getLineLastNonWhitespaceColumn(prev.endLineNumber),
        );
        if (rangeNoWhitespace.containsRange(prev) &&
            !rangeNoWhitespace.equalsRange(prev) &&
            cur.containsRange(rangeNoWhitespace) &&
            !cur.equalsRange(rangeNoWhitespace)) {
          oneRangesWithTrivia.add(rangeNoWhitespace);
        }
        // add line/block range
        final rangeFull = Range(
          prev.startLineNumber,
          1,
          prev.endLineNumber,
          model.getLineMaxColumn(prev.endLineNumber),
        );
        if (rangeFull.containsRange(prev) &&
            !rangeFull.equalsRange(rangeNoWhitespace) &&
            cur.containsRange(rangeFull) &&
            !cur.equalsRange(rangeFull)) {
          oneRangesWithTrivia.add(rangeFull);
        }
      }
      oneRangesWithTrivia.add(cur);
    }
    return oneRangesWithTrivia;
  }

  // ---- WordSelectionRangeProvider -----------------------------------------

  static List<Range> _wordRanges(
    ICursorSimpleModel model,
    WordCharacterClassifier wordSeparators,
    Position position,
    bool selectSubwords,
  ) {
    final bucket = <Range>[];
    final word = WordOperations.getWordAtPosition(
      model,
      wordSeparators,
      position,
    );
    if (selectSubwords && word != null) {
      _addInWordRanges(bucket, word, position);
    }
    if (word != null) {
      bucket.add(
        Range(
          position.lineNumber,
          word.startColumn,
          position.lineNumber,
          word.endColumn,
        ),
      );
    }
    _addWhitespaceLine(bucket, model, position);
    final lineCount = model.getLineCount();
    bucket.add(Range(1, 1, lineCount, model.getLineMaxColumn(lineCount)));
    return bucket;
  }

  static void _addInWordRanges(
    List<Range> bucket,
    WordAtPosition obj,
    Position pos,
  ) {
    final word = obj.word;
    final startColumn = obj.startColumn;
    final offset = pos.column - startColumn;
    // Out of range reads NaN upstream, which matches no class.
    int charAt(int index) =>
        index >= 0 && index < word.length ? word.codeUnitAt(index) : -1;
    var start = offset;
    var end = offset;
    var lastCh = 0;

    // LEFT anchor (start)
    for (; start >= 0; start--) {
      final ch = charAt(start);
      if (start != offset && (ch == _underline || ch == _dash)) {
        // foo-bar OR foo_bar
        break;
      } else if (isLowerAsciiLetter(ch) && isUpperAsciiLetter(lastCh)) {
        // fooBar
        break;
      }
      lastCh = ch;
    }
    start += 1;

    // RIGHT anchor (end)
    for (; end < word.length; end++) {
      final ch = charAt(end);
      if (isUpperAsciiLetter(ch) && isLowerAsciiLetter(lastCh)) {
        // fooBar
        break;
      } else if (ch == _underline || ch == _dash) {
        // foo-bar OR foo_bar
        break;
      }
      lastCh = ch;
    }

    if (start < end) {
      bucket.add(
        Range(
          pos.lineNumber,
          startColumn + start,
          pos.lineNumber,
          startColumn + end,
        ),
      );
    }
  }

  static const _underline = 0x5F;
  static const _dash = 0x2D;

  static void _addWhitespaceLine(
    List<Range> bucket,
    ICursorSimpleModel model,
    Position pos,
  ) {
    final line = pos.lineNumber;
    if (model.getLineMaxColumn(line) > 1 &&
        model.getLineFirstNonWhitespaceColumn(line) == 0 &&
        model.getLineLastNonWhitespaceColumn(line) == 0) {
      bucket.add(Range(line, 1, line, model.getLineMaxColumn(line)));
    }
  }

  // ---- BracketSelectionRangeProvider --------------------------------------

  static List<Range> _bracketRanges(
    ICursorSimpleModel model,
    Position position,
    List<CharacterPair> pairs,
  ) {
    final bucket = <Range>[];
    final brackets = _BracketScanner(model, pairs);
    if (!brackets.hasBrackets) return bucket;
    // _bracketsRightYield: unmatched closing brackets after the position.
    final ranges = <String, List<Range>>{};
    var counts = <String, int>{};
    Position? pos = position;
    var budget = maxBracketSearchCharacters;
    while (pos != null) {
      final bracket = brackets.next(pos, budget);
      if (bracket == null) break;
      budget = bracket.budget;
      if (bracket.isOpening) {
        // wait for closing
        counts[bracket.key] = (counts[bracket.key] ?? 0) + 1;
      } else {
        // process closing
        final val = (counts[bracket.key] ?? 0) - 1;
        counts[bracket.key] = val < 0 ? 0 : val;
        if (val < 0) (ranges[bracket.key] ??= []).add(bracket.range);
      }
      pos = bracket.range.getEndPosition();
    }
    // _bracketsLeftYield: their opening brackets before the position.
    counts = {};
    pos = position;
    budget = maxBracketSearchCharacters;
    while (pos != null && ranges.isNotEmpty) {
      final bracket = brackets.previous(pos, budget);
      if (bracket == null) break;
      budget = bracket.budget;
      if (!bracket.isOpening) {
        // wait for opening
        counts[bracket.key] = (counts[bracket.key] ?? 0) + 1;
      } else {
        // opening
        final val = (counts[bracket.key] ?? 0) - 1;
        counts[bracket.key] = val < 0 ? 0 : val;
        if (val < 0) {
          final list = ranges[bracket.key];
          if (list != null) {
            final closing = list.removeAt(0);
            if (list.isEmpty) ranges.remove(bracket.key);
            final innerBracket = Range.fromPositions(
              bracket.range.getEndPosition(),
              closing.getStartPosition(),
            );
            final outerBracket = Range.fromPositions(
              bracket.range.getStartPosition(),
              closing.getEndPosition(),
            );
            bucket
              ..add(innerBracket)
              ..add(outerBracket);
            _addBracketLeading(model, outerBracket, bucket);
          }
        }
      }
      pos = bracket.range.getStartPosition();
    }
    return bucket;
  }

  static void _addBracketLeading(
    ICursorSimpleModel model,
    Range bracket,
    List<Range> bucket,
  ) {
    if (bracket.startLineNumber == bracket.endLineNumber) return;
    // xxxxxxxx {
    //
    // }
    final startLine = bracket.startLineNumber;
    final column = model.getLineFirstNonWhitespaceColumn(startLine);
    if (column != 0 && column != bracket.startColumn) {
      bucket
        ..add(
          Range.fromPositions(
            Position(startLine, column),
            bracket.getEndPosition(),
          ),
        )
        ..add(
          Range.fromPositions(Position(startLine, 1), bracket.getEndPosition()),
        );
    }
    // xxxxxxxx
    // {
    //
    // }
    final aboveLine = startLine - 1;
    if (aboveLine > 0) {
      final column = model.getLineFirstNonWhitespaceColumn(aboveLine);
      if (column == bracket.startColumn &&
          column != model.getLineLastNonWhitespaceColumn(aboveLine)) {
        bucket
          ..add(
            Range.fromPositions(
              Position(aboveLine, column),
              bracket.getEndPosition(),
            ),
          )
          ..add(
            Range.fromPositions(
              Position(aboveLine, 1),
              bracket.getEndPosition(),
            ),
          );
      }
    }
  }
}

/// A bracket found by [_BracketScanner]: its range, whether it opens, its
/// pair's opening text, and the search budget left.
typedef _FoundBracket = ({Range range, bool isOpening, String key, int budget});

/// `model.bracketPairs.findNextBracket` / `findPrevBracket` over the plain
/// text: the nearest bracket starting at or after (ending at or before) a
/// position, the longest one where several match.
class _BracketScanner {
  _BracketScanner(this.model, List<CharacterPair> pairs)
    : _tokens = [
        for (final (open, close) in pairs)
          if (open.isNotEmpty && close.isNotEmpty) ...[
            (text: open, isOpening: true, key: open),
            (text: close, isOpening: false, key: open),
          ],
      ]..sort((a, b) => b.text.length.compareTo(a.text.length));

  final ICursorSimpleModel model;
  final List<({String text, bool isOpening, String key})> _tokens;

  bool get hasBrackets => _tokens.isNotEmpty;

  _FoundBracket? next(Position from, int budget) {
    final lineCount = model.getLineCount();
    for (var line = from.lineNumber; line <= lineCount; line++) {
      final text = model.getLineContent(line);
      final start = line == from.lineNumber ? from.column - 1 : 0;
      for (var i = start; i < text.length; i++) {
        if (--budget < 0) return null;
        for (final token in _tokens) {
          if (text.startsWith(token.text, i)) {
            return (
              range: Range(line, i + 1, line, i + 1 + token.text.length),
              isOpening: token.isOpening,
              key: token.key,
              budget: budget,
            );
          }
        }
      }
    }
    return null;
  }

  _FoundBracket? previous(Position before, int budget) {
    for (var line = before.lineNumber; line >= 1; line--) {
      final text = model.getLineContent(line);
      final end = line == before.lineNumber ? before.column - 1 : text.length;
      for (var i = end; i > 0; i--) {
        if (--budget < 0) return null;
        for (final token in _tokens) {
          final start = i - token.text.length;
          if (start >= 0 && text.startsWith(token.text, start)) {
            return (
              range: Range(line, start + 1, line, i + 1),
              isOpening: token.isOpening,
              key: token.key,
              budget: budget,
            );
          }
        }
      }
    }
    return null;
  }
}
