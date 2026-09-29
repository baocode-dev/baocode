/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/base/common/filters.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: `fuzzyScore` (with its tables,
// `_doScore`, `isPatternInWord`, `_fillInMaxWordMatchPos`), `anyScore`,
// `createMatches`, `fuzzyScoreGraceful[Aggressive]`, `matchesPrefix` and
// `matchesFuzzy2`, plus `isEmojiImprecise` from strings.ts.
// Deviations: a [FuzzyScore] is a `List<int>` (`[score, wordStart,
// ...matches]`); indexing outside a string compares as "no character" like
// JavaScript's `undefined`; lower-casing uses Dart's `toLowerCase`. The
// camel-case, word, contiguous-substring and regexp-based `matchesFuzzy`
// filters and Korean alternate characters are not ported.

import 'dart:typed_data';

/// A matched range `[start, end)` in the word.
class FilterMatch {
  FilterMatch(this.start, this.end);

  int start;
  int end;

  @override
  bool operator ==(Object other) =>
      other is FilterMatch && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '{start: $start, end: $end}';
}

/// An array representing a fuzzy match: 0. the score, 1. the offset at which
/// matching started, 2... match positions (last to first) relative to 1.
typedef FuzzyScore = List<int>;

/// No matches and value `-100`.
const FuzzyScore fuzzyScoreDefault = [-100, 0];

bool isDefaultFuzzyScore(FuzzyScore? score) =>
    score == null || (score.length == 2 && score[0] == -100 && score[1] == 0);

class FuzzyScoreOptions {
  const FuzzyScoreOptions({
    required this.firstMatchCanBeWeak,
    required this.boostFullMatch,
  });

  static const FuzzyScoreOptions defaults = FuzzyScoreOptions(
    boostFullMatch: true,
    firstMatchCanBeWeak: false,
  );

  final bool firstMatchCanBeWeak;
  final bool boostFullMatch;
}

typedef FuzzyScorer = FuzzyScore? Function(
  String pattern,
  String lowPattern,
  int patternPos,
  String word,
  String lowWord,
  int wordPos, [
  FuzzyScoreOptions options,
]);

/// Case-insensitive prefix match (`matchesPrefix`).
List<FilterMatch>? matchesPrefix(String word, String wordToMatchAgainst) {
  if (wordToMatchAgainst.isEmpty || wordToMatchAgainst.length < word.length) {
    return null;
  }
  if (!wordToMatchAgainst.toLowerCase().startsWith(word.toLowerCase())) {
    return null;
  }
  return word.isNotEmpty ? [FilterMatch(0, word.length)] : [];
}

List<FilterMatch>? matchesFuzzy2(String pattern, String word) {
  final score = fuzzyScore(
    pattern,
    pattern.toLowerCase(),
    0,
    word,
    word.toLowerCase(),
    0,
    const FuzzyScoreOptions(firstMatchCanBeWeak: true, boostFullMatch: true),
  );
  return score != null ? createMatches(score) : null;
}

FuzzyScore anyScore(
  String pattern,
  String lowPattern,
  int patternPos,
  String word,
  String lowWord,
  int wordPos,
) {
  final max = pattern.length < 13 ? pattern.length : 13;
  for (; patternPos < max; patternPos++) {
    final result = fuzzyScore(
      pattern,
      lowPattern,
      patternPos,
      word,
      lowWord,
      wordPos,
      const FuzzyScoreOptions(firstMatchCanBeWeak: true, boostFullMatch: true),
    );
    if (result != null) return result;
  }
  return [0, wordPos];
}

List<FilterMatch> createMatches(FuzzyScore? score) {
  if (score == null) return [];
  final res = <FilterMatch>[];
  final wordPos = score[1];
  for (var i = score.length - 1; i > 1; i--) {
    final pos = score[i] + wordPos;
    final last = res.isEmpty ? null : res.last;
    if (last != null && last.end == pos) {
      last.end = pos + 1;
    } else {
      res.add(FilterMatch(pos, pos + 1));
    }
  }
  return res;
}

const int _maxLen = 128;
const int _minSafeInteger = -9007199254740991;

List<Int32List> _initTable() => [
  for (var i = 0; i <= _maxLen; i++) Int32List(_maxLen + 1),
];

// min/max word position for a certain pattern position
final Int32List _minWordMatchPos = Int32List(2 * _maxLen + 1);
final Int32List _maxWordMatchPos = Int32List(2 * _maxLen + 1);
// the length of a contiguous diagonal match
final List<Int32List> _diag = _initTable();
final List<Int32List> _table = _initTable();
final List<Int32List> _arrows = _initTable();

const int _arrowDiag = 1;
const int _arrowLeft = 2;
const int _arrowLeftLeft = 3;

/// `-1` when [index] is outside [value] (JavaScript's `undefined`).
int _unitAt(String value, int index) =>
    index < 0 || index >= value.length ? -1 : value.codeUnitAt(index);

bool isEmojiImprecise(int x) =>
    (x >= 0x1F1E6 && x <= 0x1F1FF) ||
    (x == 8986) ||
    (x == 8987) ||
    (x == 9200) ||
    (x == 9203) ||
    (x >= 9728 && x <= 10175) ||
    (x == 11088) ||
    (x == 11093) ||
    (x >= 127744 && x <= 128591) ||
    (x >= 128640 && x <= 128764) ||
    (x >= 128992 && x <= 129008) ||
    (x >= 129280 && x <= 129535) ||
    (x >= 129648 && x <= 129782);

bool _isSeparatorAtPos(String value, int index) {
  if (index < 0 || index >= value.length) return false;
  var code = value.codeUnitAt(index);
  if (code >= 0xD800 && code <= 0xDBFF && index + 1 < value.length) {
    final low = value.codeUnitAt(index + 1);
    if (low >= 0xDC00 && low <= 0xDFFF) {
      code = ((code - 0xD800) << 10) + (low - 0xDC00) + 0x10000;
    }
  }
  switch (code) {
    case 0x5F: // _
    case 0x2D: // -
    case 0x2E: // .
    case 0x20: // space
    case 0x2F: // /
    case 0x5C: // \
    case 0x27: // '
    case 0x22: // "
    case 0x3A: // :
    case 0x24: // $
    case 0x3C: // <
    case 0x3E: // >
    case 0x28: // (
    case 0x29: // )
    case 0x5B: // [
    case 0x5D: // ]
    case 0x7B: // {
    case 0x7D: // }
      return true;
    default:
      return isEmojiImprecise(code);
  }
}

bool _isWhitespaceAtPos(String value, int index) {
  if (index < 0 || index >= value.length) return false;
  final code = value.codeUnitAt(index);
  return code == 0x20 || code == 0x09;
}

bool _isUpperCaseAtPos(int pos, String word, String wordLow) =>
    _unitAt(word, pos) != _unitAt(wordLow, pos);

bool isPatternInWord(
  String patternLow,
  int patternPos,
  int patternLen,
  String wordLow,
  int wordPos,
  int wordLen, [
  bool fillMinWordPosArr = false,
]) {
  while (patternPos < patternLen && wordPos < wordLen) {
    if (patternLow.codeUnitAt(patternPos) == wordLow.codeUnitAt(wordPos)) {
      if (fillMinWordPosArr) {
        // Remember the min word position for each pattern position
        _minWordMatchPos[patternPos] = wordPos;
      }
      patternPos += 1;
    }
    wordPos += 1;
  }
  return patternPos == patternLen; // pattern must be exhausted
}

FuzzyScore? fuzzyScore(
  String pattern,
  String patternLow,
  int patternStart,
  String word,
  String wordLow,
  int wordStart, [
  FuzzyScoreOptions options = FuzzyScoreOptions.defaults,
]) {
  final patternLen = pattern.length > _maxLen ? _maxLen : pattern.length;
  final wordLen = word.length > _maxLen ? _maxLen : word.length;
  if (patternLow.length < patternLen || wordLow.length < wordLen) {
    // Lower-casing changed the length; there is no sensible alignment.
    return null;
  }

  if (patternStart >= patternLen ||
      wordStart >= wordLen ||
      (patternLen - patternStart) > (wordLen - wordStart)) {
    return null;
  }

  // Run a simple check if the characters of pattern occur
  // (in order) at all in word. If that isn't the case we
  // stop because no match will be possible
  if (!isPatternInWord(
    patternLow,
    patternStart,
    patternLen,
    wordLow,
    wordStart,
    wordLen,
    true,
  )) {
    return null;
  }

  // Find the max matching word position for each pattern position
  // NOTE: the min matching word position was filled in above, in the
  // `isPatternInWord` call
  _fillInMaxWordMatchPos(
    patternLen,
    wordLen,
    patternStart,
    wordStart,
    patternLow,
    wordLow,
  );

  var row = 1;
  var column = 1;
  var patternPos = patternStart;
  var wordPos = wordStart;

  final hasStrongFirstMatch = [false];

  // There will be a match, fill in tables
  row = 1;
  patternPos = patternStart;
  for (; patternPos < patternLen; row++, patternPos++) {
    // Reduce search space to possible matching word positions and to
    // possible access from next row
    final minWordMatchPos = _minWordMatchPos[patternPos];
    final maxWordMatchPos = _maxWordMatchPos[patternPos];
    final nextMaxWordMatchPos = patternPos + 1 < patternLen
        ? _maxWordMatchPos[patternPos + 1]
        : wordLen;

    column = minWordMatchPos - wordStart + 1;
    wordPos = minWordMatchPos;
    for (; wordPos < nextMaxWordMatchPos; column++, wordPos++) {
      var score = _minSafeInteger;
      var canComeDiag = false;

      if (wordPos <= maxWordMatchPos) {
        score = _doScore(
          pattern,
          patternLow,
          patternPos,
          patternStart,
          word,
          wordLow,
          wordPos,
          wordLen,
          wordStart,
          _diag[row - 1][column - 1] == 0,
          hasStrongFirstMatch,
        );
      }

      var diagScore = 0;
      if (score != _minSafeInteger) {
        canComeDiag = true;
        diagScore = score + _table[row - 1][column - 1];
      }

      final canComeLeft = wordPos > minWordMatchPos;
      final leftScore = canComeLeft
          ? _table[row][column - 1] + (_diag[row][column - 1] > 0 ? -5 : 0)
          : 0; // penalty for a gap start

      final canComeLeftLeft =
          wordPos > minWordMatchPos + 1 && _diag[row][column - 1] > 0;
      final leftLeftScore = canComeLeftLeft
          ? _table[row][column - 2] + (_diag[row][column - 2] > 0 ? -5 : 0)
          : 0; // penalty for a gap start

      if (canComeLeftLeft &&
          (!canComeLeft || leftLeftScore >= leftScore) &&
          (!canComeDiag || leftLeftScore >= diagScore)) {
        // always prefer choosing left left to jump over a diagonal because
        // that means a match is earlier in the word
        _table[row][column] = leftLeftScore;
        _arrows[row][column] = _arrowLeftLeft;
        _diag[row][column] = 0;
      } else if (canComeLeft && (!canComeDiag || leftScore >= diagScore)) {
        // always prefer choosing left since that means a match is earlier in
        // the word
        _table[row][column] = leftScore;
        _arrows[row][column] = _arrowLeft;
        _diag[row][column] = 0;
      } else if (canComeDiag) {
        _table[row][column] = diagScore;
        _arrows[row][column] = _arrowDiag;
        _diag[row][column] = _diag[row - 1][column - 1] + 1;
      } else {
        throw StateError('not possible');
      }
    }
  }

  if (!hasStrongFirstMatch[0] && !options.firstMatchCanBeWeak) {
    return null;
  }

  row--;
  column--;

  final result = <int>[_table[row][column], wordStart];

  var backwardsDiagLength = 0;
  var maxMatchColumn = 0;

  while (row >= 1) {
    // Find the column where we go diagonally up
    var diagColumn = column;
    do {
      final arrow = _arrows[row][diagColumn];
      if (arrow == _arrowLeftLeft) {
        diagColumn = diagColumn - 2;
      } else if (arrow == _arrowLeft) {
        diagColumn = diagColumn - 1;
      } else {
        // found the diagonal
        break;
      }
    } while (diagColumn >= 1);

    // Overturn the "forwards" decision if keeping the "backwards" diagonal
    // would give a better match
    if (backwardsDiagLength >
            1 && // only if we would have a contiguous match of 3 characters
        _unitAt(patternLow, patternStart + row - 1) ==
            _unitAt(
              wordLow,
              wordStart + column - 1,
            ) && // only if we can do a contiguous match diagonally
        !_isUpperCaseAtPos(
          diagColumn + wordStart - 1,
          word,
          wordLow,
        ) && // only if the forwards chose diagonal is not an uppercase
        backwardsDiagLength + 1 > _diag[row][diagColumn]) {
      // only if our contiguous match would be longer than the "forwards"
      // contiguous match
      diagColumn = column;
    }

    if (diagColumn == column) {
      // this is a contiguous match
      backwardsDiagLength++;
    } else {
      backwardsDiagLength = 1;
    }

    if (maxMatchColumn == 0) {
      // remember the last matched column
      maxMatchColumn = diagColumn;
    }

    row--;
    column = diagColumn - 1;
    result.add(column);
  }

  if (wordLen - wordStart == patternLen && options.boostFullMatch) {
    // the word matches the pattern with all characters!
    // giving the score a total match boost (to come up ahead other words)
    result[0] += 2;
  }

  // Add 1 penalty for each skipped character in the word
  final skippedCharsCount = maxMatchColumn - patternLen;
  result[0] -= skippedCharsCount;

  return result;
}

void _fillInMaxWordMatchPos(
  int patternLen,
  int wordLen,
  int patternStart,
  int wordStart,
  String patternLow,
  String wordLow,
) {
  var patternPos = patternLen - 1;
  var wordPos = wordLen - 1;
  while (patternPos >= patternStart && wordPos >= wordStart) {
    if (patternLow.codeUnitAt(patternPos) == wordLow.codeUnitAt(wordPos)) {
      _maxWordMatchPos[patternPos] = wordPos;
      patternPos--;
    }
    wordPos--;
  }
}

int _doScore(
  String pattern,
  String patternLow,
  int patternPos,
  int patternStart,
  String word,
  String wordLow,
  int wordPos,
  int wordLen,
  int wordStart,
  bool newMatchStart,
  List<bool> outFirstMatchStrong,
) {
  if (patternLow.codeUnitAt(patternPos) != wordLow.codeUnitAt(wordPos)) {
    return _minSafeInteger;
  }

  var score = 1;
  var isGapLocation = false;
  if (wordPos == (patternPos - patternStart)) {
    // common prefix: `foobar <-> foobaz`
    //                            ^^^^^
    score = pattern.codeUnitAt(patternPos) == word.codeUnitAt(wordPos) ? 7 : 5;
  } else if (_isUpperCaseAtPos(wordPos, word, wordLow) &&
      (wordPos == 0 || !_isUpperCaseAtPos(wordPos - 1, word, wordLow))) {
    // hitting upper-case: `foo <-> forOthers`
    //                              ^^ ^
    score = pattern.codeUnitAt(patternPos) == word.codeUnitAt(wordPos) ? 7 : 5;
    isGapLocation = true;
  } else if (_isSeparatorAtPos(wordLow, wordPos) &&
      (wordPos == 0 || !_isSeparatorAtPos(wordLow, wordPos - 1))) {
    // hitting a separator: `. <-> foo.bar`
    //                                ^
    score = 5;
  } else if (_isSeparatorAtPos(wordLow, wordPos - 1) ||
      _isWhitespaceAtPos(wordLow, wordPos - 1)) {
    // post separator: `foo <-> bar_foo`
    //                              ^^^
    score = 5;
    isGapLocation = true;
  }

  if (score > 1 && patternPos == patternStart) {
    outFirstMatchStrong[0] = true;
  }

  if (!isGapLocation) {
    isGapLocation =
        _isUpperCaseAtPos(wordPos, word, wordLow) ||
        _isSeparatorAtPos(wordLow, wordPos - 1) ||
        _isWhitespaceAtPos(wordLow, wordPos - 1);
  }

  if (patternPos == patternStart) {
    // first character in pattern
    if (wordPos > wordStart) {
      // the first pattern character would match a word character that is not
      // at the word start so introduce a penalty to account for the gap
      // preceding this match
      score -= isGapLocation ? 3 : 5;
    }
  } else {
    if (newMatchStart) {
      // this would be the beginning of a new match (i.e. there would be a gap
      // before this location)
      score += isGapLocation ? 2 : 0;
    } else {
      // this is part of a contiguous match, so give it a slight bonus, but do
      // so only if it would not be a preferred gap location
      score += isGapLocation ? 0 : 1;
    }
  }

  if (wordPos + 1 == wordLen) {
    // we always penalize gaps, but this gives unfair advantages to a match
    // that would match the last character in the word so pretend there is a
    // gap after the last character in the word to normalize things
    score -= isGapLocation ? 3 : 5;
  }

  return score;
}

// --- graceful ---

FuzzyScore? fuzzyScoreGracefulAggressive(
  String pattern,
  String lowPattern,
  int patternPos,
  String word,
  String lowWord,
  int wordPos, [
  FuzzyScoreOptions options = FuzzyScoreOptions.defaults,
]) => _fuzzyScoreWithPermutations(
  pattern,
  lowPattern,
  patternPos,
  word,
  lowWord,
  wordPos,
  true,
  options,
);

FuzzyScore? fuzzyScoreGraceful(
  String pattern,
  String lowPattern,
  int patternPos,
  String word,
  String lowWord,
  int wordPos, [
  FuzzyScoreOptions options = FuzzyScoreOptions.defaults,
]) => _fuzzyScoreWithPermutations(
  pattern,
  lowPattern,
  patternPos,
  word,
  lowWord,
  wordPos,
  false,
  options,
);

FuzzyScore? _fuzzyScoreWithPermutations(
  String pattern,
  String lowPattern,
  int patternPos,
  String word,
  String lowWord,
  int wordPos,
  bool aggressive,
  FuzzyScoreOptions options,
) {
  var top = fuzzyScore(
    pattern,
    lowPattern,
    patternPos,
    word,
    lowWord,
    wordPos,
    options,
  );

  if (top != null && !aggressive) {
    // when using the original pattern yield a result we return it unless we
    // are aggressive and try to find a better alignment, e.g. `cno` ->
    // `^co^ns^ole` or `^c^o^nsole`.
    return top;
  }

  if (pattern.length >= 3) {
    // When the pattern is long enough then try a few (max 7) permutations of
    // the pattern to find a better match. The permutations only swap
    // neighbouring characters, e.g `cnoso` becomes `conso`, `cnsoo`, `cnoos`.
    final tries = pattern.length - 1 < 7 ? pattern.length - 1 : 7;
    for (
      var movingPatternPos = patternPos + 1;
      movingPatternPos < tries;
      movingPatternPos++
    ) {
      final newPattern = _nextTypoPermutation(pattern, movingPatternPos);
      if (newPattern != null) {
        final candidate = fuzzyScore(
          newPattern,
          newPattern.toLowerCase(),
          patternPos,
          word,
          lowWord,
          wordPos,
          options,
        );
        if (candidate != null) {
          candidate[0] -= 3; // permutation penalty
          if (top == null || candidate[0] > top[0]) top = candidate;
        }
      }
    }
  }
  return top;
}

String? _nextTypoPermutation(String pattern, int patternPos) {
  if (patternPos + 1 >= pattern.length) return null;
  final swap1 = pattern[patternPos];
  final swap2 = pattern[patternPos + 1];
  if (swap1 == swap2) return null;
  return pattern.substring(0, patternPos) +
      swap2 +
      swap1 +
      pattern.substring(patternPos + 2);
}
