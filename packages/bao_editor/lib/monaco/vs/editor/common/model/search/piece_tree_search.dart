/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// textModelSearch.ts SearchParams.parseSearchRequest, isMultilineRegexSource,
// isValidMatch, Searcher.next/reset, TextModelSearch.findMatches and its
// _doFindMatchesLineByLine/_findMatchesInLine/_doFindMatchesMultiline helpers;
// model.ts SearchData and FindMatch; pieceTreeBase.ts findMatchesLineByLine
// and _findMatchesInLine. Piece-tree node-level findMatchesInNode and its
// buffer optimization are OMITTED: lines are read through PieceTreeBase's
// public API so matches spanning pieces work. TextModelSearch.findNextMatch,
// findPreviousMatch and their helpers are adapted from textModelSearch.ts
// lines 290-429. They use PieceTreeBase lines and LF-normalized ranges instead
// of TextModel/offset mapping; previous multiline search keeps upstream's 9990
// match cap. Invalid start positions throw RangeError rather than relying on
// TextModel's validated positions. JS RegExp is adapted to Dart RegExp (not
// identical syntax/Unicode case-folding); Intl.Segmenter locales and upstream's
// classifier cache are omitted. No full VS Code parity.

import '../../core/position.dart';
import '../../core/range.dart';
import '../piece_tree_text_buffer/piece_tree_base.dart';

/// One-based, UTF-16-based editor coordinates; captures include group zero.
class FindMatch {
  const FindMatch(this.range, this.matches);

  final Range range;
  final List<String?>? matches;
}

/// The subset of upstream's word classifier used by search.
class WordCharacterClassifier {
  WordCharacterClassifier(String separators)
    : _separators = separators.codeUnits.toSet()..addAll([9, 10, 13, 32]);

  final Set<int> _separators;

  bool isRegular(int codeUnit) => !_separators.contains(codeUnit);
}

class SearchData {
  const SearchData(
    this.regex,
    this.wordSeparators,
    this.simpleSearch,
    this.multiline,
  );

  final RegExp regex;
  final WordCharacterClassifier? wordSeparators;
  final String? simpleSearch;
  final bool multiline;
}

class SearchParams {
  const SearchParams(
    this.searchString, {
    this.isRegex = false,
    this.matchCase = false,
    this.wordSeparators,
  });

  final String searchString;
  final bool isRegex;
  final bool matchCase;

  /// Null/empty disables whole-word filtering; otherwise these UTF-16 code
  /// units, space, tab, CR and LF delimit words (as in upstream search).
  final String? wordSeparators;

  SearchData? parseSearchRequest() {
    if (searchString.isEmpty) return null;
    final multiline = isRegex
        ? isMultilineRegexSource(searchString)
        : searchString.contains('\n');
    try {
      final regex = RegExp(
        isRegex ? searchString : RegExp.escape(searchString),
        caseSensitive: matchCase,
        multiLine: multiline,
        unicode: true,
      );
      final simple =
          !isRegex &&
              !multiline &&
              (matchCase ||
                  searchString.toLowerCase() == searchString.toUpperCase())
          ? searchString
          : null;
      return SearchData(
        regex,
        wordSeparators == null || wordSeparators!.isEmpty
            ? null
            : WordCharacterClassifier(wordSeparators!),
        simple,
        multiline,
      );
    } on FormatException {
      return null;
    }
  }
}

/// Upstream intentionally treats escaped n, r and W as multiline, not all
/// expressions capable of consuming newlines (e.g. a character class).
bool isMultilineRegexSource(String source) {
  for (var i = 0; i < source.length; i++) {
    if (source.codeUnitAt(i) == 10) return true;
    if (source.codeUnitAt(i) == 92 && ++i < source.length) {
      final next = source.codeUnitAt(i);
      if (next == 110 || next == 114 || next == 87) return true;
    }
  }
  return false;
}

bool isValidMatch(
  WordCharacterClassifier separators,
  String text,
  int start,
  int length,
) {
  final left =
      start == 0 ||
      !separators.isRegular(text.codeUnitAt(start - 1)) ||
      (length > 0 && !separators.isRegular(text.codeUnitAt(start)));
  final end = start + length;
  final right =
      end == text.length ||
      !separators.isRegular(text.codeUnitAt(end)) ||
      (length > 0 && !separators.isRegular(text.codeUnitAt(end - 1)));
  return left && right;
}

/// Stateful non-overlapping regexp scanner; reset before each new line/range.
class Searcher {
  Searcher(this.wordSeparators, this.regex);

  final WordCharacterClassifier? wordSeparators;
  final RegExp regex;
  int _nextIndex = 0;
  int _previousStart = -1;
  int _previousLength = 0;

  void reset(int index) {
    _nextIndex = index;
    _previousStart = -1;
    _previousLength = 0;
  }

  RegExpMatch? next(String text) {
    while (_nextIndex <= text.length) {
      if (_previousStart + _previousLength == text.length) return null;
      // JS global RegExp.exec does not advance after a zero-width match;
      // advance by a full UTF-16 surrogate pair before trying again.
      if (_previousLength == 0 && _previousStart == _nextIndex) {
        if (_nextIndex < text.length &&
            text.codeUnitAt(_nextIndex) >= 0xd800 &&
            text.codeUnitAt(_nextIndex) <= 0xdbff &&
            _nextIndex + 1 < text.length &&
            text.codeUnitAt(_nextIndex + 1) >= 0xdc00 &&
            text.codeUnitAt(_nextIndex + 1) <= 0xdfff) {
          _nextIndex += 2;
        } else {
          _nextIndex++;
        }
        continue;
      }
      final iterator = regex.allMatches(text, _nextIndex).iterator;
      if (!iterator.moveNext()) return null;
      final match = iterator.current;
      _previousStart = match.start;
      _previousLength = match.end - match.start;
      _nextIndex = match.end;
      if (wordSeparators == null ||
          isValidMatch(wordSeparators!, text, match.start, _previousLength)) {
        return match;
      }
    }
    return null;
  }
}

/// Independent search service; it does not modify PieceTreeBase.
class PieceTreeSearch {
  const PieceTreeSearch._();

  static List<FindMatch> findMatches(
    PieceTreeBase tree,
    SearchParams params,
    Range searchRange, {
    bool captureMatches = false,
    int limitResultCount = 999,
  }) {
    final data = params.parseSearchRequest();
    if (data == null || limitResultCount <= 0) return [];
    if (searchRange.startLineNumber < 1 ||
        searchRange.endLineNumber > tree.getLineCount() ||
        searchRange.startColumn < 1 ||
        searchRange.endColumn < 1 ||
        searchRange.startColumn >
            tree.getLineLength(searchRange.startLineNumber) + 1 ||
        searchRange.endColumn >
            tree.getLineLength(searchRange.endLineNumber) + 1) {
      throw RangeError('Search range is outside the piece tree');
    }
    return data.multiline
        ? _findMultiline(
            tree,
            data,
            searchRange,
            captureMatches,
            limitResultCount,
          )
        : findMatchesLineByLine(
            tree,
            data,
            searchRange,
            captureMatches: captureMatches,
            limitResultCount: limitResultCount,
          );
  }

  /// Find the first match at or after [searchStart], wrapping to the top.
  static FindMatch? findNextMatch(
    PieceTreeBase tree,
    SearchParams params,
    Position searchStart,
    bool captureMatches,
  ) {
    final data = params.parseSearchRequest();
    if (data == null) return null;
    _validateStart(tree, searchStart);

    if (data.multiline) {
      final count = tree.getLineCount();
      final matches = _findMultiline(
        tree,
        data,
        Range(searchStart.lineNumber, 1, count, tree.getLineLength(count) + 1),
        captureMatches,
        1,
        fromIndex: searchStart.column - 1,
      );
      if (matches.isNotEmpty) return matches.first;
      if (searchStart.lineNumber == 1 && searchStart.column == 1) return null;
      final wrapped = _findMultiline(
        tree,
        data,
        _fullRange(tree),
        captureMatches,
        1,
      );
      return wrapped.isEmpty ? null : wrapped.first;
    }

    final searcher = Searcher(data.wordSeparators, data.regex);
    final count = tree.getLineCount();
    final line = searchStart.lineNumber;
    final first = _firstInLine(
      searcher,
      tree.getLineContent(line),
      line,
      searchStart.column,
      captureMatches,
    );
    if (first != null) return first;
    for (var i = 1; i <= count; i++) {
      final nextLine = (line + i - 1) % count + 1;
      final found = _firstInLine(
        searcher,
        tree.getLineContent(nextLine),
        nextLine,
        1,
        captureMatches,
      );
      if (found != null) return found;
    }
    return null;
  }

  /// Find the last match ending at or before [searchStart], wrapping to the end.
  static FindMatch? findPreviousMatch(
    PieceTreeBase tree,
    SearchParams params,
    Position searchStart,
    bool captureMatches,
  ) {
    final data = params.parseSearchRequest();
    if (data == null) return null;
    _validateStart(tree, searchStart);

    if (data.multiline) {
      // The upstream previous-match path limits its prefix scan to 10 * 999.
      final matches = _findMultiline(
        tree,
        data,
        Range(1, 1, searchStart.lineNumber, searchStart.column),
        captureMatches,
        9990,
      );
      if (matches.isNotEmpty) return matches.last;
      final count = tree.getLineCount();
      if (searchStart.lineNumber == count &&
          searchStart.column == tree.getLineLength(count) + 1) {
        return null;
      }
      final wrapped = _findMultiline(
        tree,
        data,
        _fullRange(tree),
        captureMatches,
        9990,
      );
      return wrapped.isEmpty ? null : wrapped.last;
    }

    final searcher = Searcher(data.wordSeparators, data.regex);
    final count = tree.getLineCount();
    final line = searchStart.lineNumber;
    final first = _lastInLine(
      searcher,
      tree.getLineContent(line).substring(0, searchStart.column - 1),
      line,
      captureMatches,
    );
    if (first != null) return first;
    for (var i = 1; i <= count; i++) {
      final previousLine = (count + line - i - 1) % count + 1;
      final found = _lastInLine(
        searcher,
        tree.getLineContent(previousLine),
        previousLine,
        captureMatches,
      );
      if (found != null) return found;
    }
    return null;
  }

  static Range _fullRange(PieceTreeBase tree) {
    final count = tree.getLineCount();
    return Range(1, 1, count, tree.getLineLength(count) + 1);
  }

  static void _validateStart(PieceTreeBase tree, Position start) {
    if (start.lineNumber < 1 ||
        start.lineNumber > tree.getLineCount() ||
        start.column < 1 ||
        start.column > tree.getLineLength(start.lineNumber) + 1) {
      throw RangeError('Search start is outside the piece tree');
    }
  }

  static FindMatch? _firstInLine(
    Searcher searcher,
    String text,
    int line,
    int column,
    bool captureMatches,
  ) {
    searcher.reset(column - 1);
    final match = searcher.next(text);
    return match == null
        ? null
        : _createMatch(
            Range(line, match.start + 1, line, match.end + 1),
            match,
            captureMatches,
          );
  }

  static FindMatch? _lastInLine(
    Searcher searcher,
    String text,
    int line,
    bool captureMatches,
  ) {
    searcher.reset(0);
    FindMatch? last;
    RegExpMatch? match;
    while ((match = searcher.next(text)) != null) {
      last = _createMatch(
        Range(line, match!.start + 1, line, match.end + 1),
        match,
        captureMatches,
      );
    }
    return last;
  }

  /// Adaptation of pieceTreeBase.findMatchesLineByLine: scans complete logical
  /// lines rather than internal nodes, so an edit splitting a match is safe.
  static List<FindMatch> findMatchesLineByLine(
    PieceTreeBase tree,
    SearchData data,
    Range searchRange, {
    bool captureMatches = false,
    int limitResultCount = 999,
  }) {
    if (limitResultCount <= 0) return [];
    final result = <FindMatch>[];
    final searcher = Searcher(data.wordSeparators, data.regex);
    for (
      var line = searchRange.startLineNumber;
      line <= searchRange.endLineNumber && result.length < limitResultCount;
      line++
    ) {
      final content = tree.getLineContent(line);
      final start = line == searchRange.startLineNumber
          ? searchRange.startColumn - 1
          : 0;
      final end = line == searchRange.endLineNumber
          ? searchRange.endColumn - 1
          : content.length;
      _findInLine(
        data,
        searcher,
        content.substring(start, end),
        line,
        start,
        result,
        captureMatches,
        limitResultCount,
      );
    }
    return result;
  }

  static void _findInLine(
    SearchData data,
    Searcher searcher,
    String text,
    int line,
    int columnOffset,
    List<FindMatch> result,
    bool captureMatches,
    int limit,
  ) {
    final simple = !captureMatches ? data.simpleSearch : null;
    if (simple != null) {
      var from = 0;
      while (from <= text.length - simple.length && result.length < limit) {
        final index = text.indexOf(simple, from);
        if (index < 0) break;
        if (data.wordSeparators == null ||
            isValidMatch(data.wordSeparators!, text, index, simple.length)) {
          result.add(
            FindMatch(
              Range(
                line,
                columnOffset + index + 1,
                line,
                columnOffset + index + simple.length + 1,
              ),
              null,
            ),
          );
        }
        from = index + simple.length;
      }
      return;
    }
    searcher.reset(0);
    RegExpMatch? match;
    while (result.length < limit && (match = searcher.next(text)) != null) {
      result.add(
        _createMatch(
          Range(
            line,
            columnOffset + match!.start + 1,
            line,
            columnOffset + match.end + 1,
          ),
          match,
          captureMatches,
        ),
      );
    }
  }

  static List<FindMatch> _findMultiline(
    PieceTreeBase tree,
    SearchData data,
    Range range,
    bool captureMatches,
    int limit, {
    int fromIndex = 0,
  }) {
    // Upstream uses LF for matching irrespective of the buffer's EOL.
    final text = tree.getValueInRange(range, '\n');
    final starts = <int>[0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) starts.add(i + 1);
    }
    Range matchRange(int start, int end) {
      (int, int) position(int offset) {
        var lo = 0;
        var hi = starts.length;
        while (lo < hi) {
          final mid = (lo + hi) ~/ 2;
          if (starts[mid] <= offset) {
            lo = mid + 1;
          } else {
            hi = mid;
          }
        }
        final line = lo - 1;
        return (
          range.startLineNumber + line,
          offset - starts[line] + (line == 0 ? range.startColumn : 1),
        );
      }

      final (startLine, startColumn) = position(start);
      final (endLine, endColumn) = position(end);
      return Range(startLine, startColumn, endLine, endColumn);
    }

    final result = <FindMatch>[];
    final searcher = Searcher(data.wordSeparators, data.regex)
      ..reset(fromIndex);
    RegExpMatch? match;
    while (result.length < limit && (match = searcher.next(text)) != null) {
      result.add(
        _createMatch(
          matchRange(match!.start, match.end),
          match,
          captureMatches,
        ),
      );
    }
    return result;
  }

  static FindMatch _createMatch(Range range, RegExpMatch match, bool capture) =>
      FindMatch(
        range,
        capture
            ? [for (var i = 0; i <= match.groupCount; i++) match.group(i)]
            : null,
      );
}
