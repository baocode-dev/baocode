// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See
// lib/ide/terminal/xterm/addons/addon_search/LICENSE.
// Ported from xterm.js addons/addon-search/src/SearchEngine.ts (c58ea36).
//
// JavaScript's string and RegExp semantics are kept: offsets are UTF-16 code
// units; `indexOf`/`lastIndexOf` clamp their start as JavaScript does (Dart's
// throw past the end); a `g` regex's `exec` from `lastIndex` is `allMatches`
// from that index. An invalid regex throws Dart's `FormatException`
// (upstream: `SyntaxError`).

import 'dart:math' as math;

import 'search_line_cache.dart';
import 'typings/addon_search.dart';

/// Represents the position to start a search from.
class _ISearchPosition {
  _ISearchPosition({required this.startCol, required this.startRow});

  int startCol;
  int startRow;
}

/// Represents a search result with its position and content.
class ISearchResult {
  ISearchResult({
    required this.term,
    required this.col,
    required this.row,
    required this.size,
  });

  String term;
  int col;
  int row;
  int size;

  @override
  bool operator ==(Object other) =>
      other is ISearchResult &&
      other.term == term &&
      other.col == col &&
      other.row == row &&
      other.size == size;

  @override
  int get hashCode => Object.hash(term, col, row, size);

  @override
  String toString() => '{term: $term, col: $col, row: $row, size: $size}';
}

/// Configuration constants for the search engine functionality.
abstract final class _Constants {
  /// Characters that are considered non-word characters for search boundary
  /// detection. These characters are used to determine word boundaries when
  /// performing whole-word searches. Includes common punctuation, symbols, and
  /// whitespace characters.
  static const String nonWordCharacters =
      r''' ~!@#$%^&*()+`-=[]{}|\;:"',./<>?''';
}

/// Core search engine that handles finding text within terminal content.
/// This class is responsible for the actual search algorithms and position
/// calculations.
class SearchEngine {
  SearchEngine(this._terminal, this._lineCache);

  final ISearchTerminal _terminal;
  final SearchLineCache _lineCache;

  /// Find the first occurrence of a term starting from a specific position.
  ///
  /// [startRow] and [startCol] are the position to start searching from.
  /// Returns the search result if found, null otherwise.
  ISearchResult? find(
    String term,
    int startRow,
    int startCol, [
    ISearchOptions? searchOptions,
  ]) {
    if (term.isEmpty) {
      _terminal.clearSelection();
      return null;
    }
    if (startCol >= _terminal.cols) {
      throw RangeError(
        'Invalid col: $startCol to search in terminal of ${_terminal.cols} '
        'cols',
      );
    }

    _lineCache.initLinesCache();

    final searchPosition = _ISearchPosition(
      startRow: startRow,
      startCol: startCol,
    );

    // Search startRow
    var result = _findInLine(term, searchPosition, searchOptions);
    // Search from startRow + 1 to end
    if (result == null) {
      for (
        var y = startRow + 1;
        y < _terminal.buffer.active.baseY + _terminal.rows;
        y++
      ) {
        searchPosition.startRow = y;
        searchPosition.startCol = 0;
        result = _findInLine(term, searchPosition, searchOptions);
        if (result != null) {
          break;
        }
      }
    }
    return result;
  }

  /// Find the next occurrence of a term with wrapping and selection
  /// management.
  ///
  /// [cachedSearchTerm] is the cached search term to determine incremental
  /// behavior. Returns the search result if found, null otherwise.
  ISearchResult? findNextWithSelection(
    String term, [
    ISearchOptions? searchOptions,
    String? cachedSearchTerm,
  ]) {
    if (term.isEmpty) {
      _terminal.clearSelection();
      return null;
    }

    final prevSelectedPos = _terminal.getSelectionPosition();
    _terminal.clearSelection();

    var startCol = 0;
    var startRow = 0;
    if (prevSelectedPos != null) {
      if (cachedSearchTerm == term) {
        startCol = prevSelectedPos.end.x;
        startRow = prevSelectedPos.end.y;
      } else {
        startCol = prevSelectedPos.start.x;
        startRow = prevSelectedPos.start.y;
      }
    }

    _lineCache.initLinesCache();

    final searchPosition = _ISearchPosition(
      startRow: startRow,
      startCol: startCol,
    );

    // Search startRow
    var result = _findInLine(term, searchPosition, searchOptions);
    // Search from startRow + 1 to end
    if (result == null) {
      for (
        var y = startRow + 1;
        y < _terminal.buffer.active.baseY + _terminal.rows;
        y++
      ) {
        searchPosition.startRow = y;
        searchPosition.startCol = 0;
        result = _findInLine(term, searchPosition, searchOptions);
        if (result != null) {
          break;
        }
      }
    }
    // If we hit the bottom and didn't search from the very top wrap back up
    if (result == null && startRow != 0) {
      for (var y = 0; y < startRow; y++) {
        searchPosition.startRow = y;
        searchPosition.startCol = 0;
        result = _findInLine(term, searchPosition, searchOptions);
        if (result != null) {
          break;
        }
      }
    }

    // If there is only one result, wrap back and return selection if it
    // exists.
    if (result == null && prevSelectedPos != null) {
      searchPosition.startRow = prevSelectedPos.start.y;
      searchPosition.startCol = 0;
      result = _findInLine(term, searchPosition, searchOptions);
    }

    return result;
  }

  /// Find the previous occurrence of a term with wrapping and selection
  /// management.
  ///
  /// [cachedSearchTerm] is the cached search term to determine if expansion
  /// should occur. Returns the search result if found, null otherwise.
  ISearchResult? findPreviousWithSelection(
    String term, [
    ISearchOptions? searchOptions,
    String? cachedSearchTerm,
  ]) {
    if (term.isEmpty) {
      _terminal.clearSelection();
      return null;
    }

    final prevSelectedPos = _terminal.getSelectionPosition();
    _terminal.clearSelection();

    var startRow = _terminal.buffer.active.baseY + _terminal.rows - 1;
    final startCol = _terminal.cols;
    const isReverseSearch = true;

    _lineCache.initLinesCache();
    final searchPosition = _ISearchPosition(
      startRow: startRow,
      startCol: startCol,
    );

    ISearchResult? result;
    if (prevSelectedPos != null) {
      searchPosition.startRow = startRow = prevSelectedPos.start.y;
      searchPosition.startCol = prevSelectedPos.start.x;
      if (cachedSearchTerm != term) {
        // Try to expand selection to right first.
        result = _findInLine(term, searchPosition, searchOptions, false);
        if (result == null) {
          // If selection was not able to be expanded to the right, then try
          // reverse search
          searchPosition.startRow = startRow = prevSelectedPos.end.y;
          searchPosition.startCol = prevSelectedPos.end.x;
        }
      }
    }

    result ??= _findInLine(
      term,
      searchPosition,
      searchOptions,
      isReverseSearch,
    );

    // Search from startRow - 1 to top
    if (result == null) {
      searchPosition.startCol = math.max(
        searchPosition.startCol,
        _terminal.cols,
      );
      for (var y = startRow - 1; y >= 0; y--) {
        searchPosition.startRow = y;
        result = _findInLine(
          term,
          searchPosition,
          searchOptions,
          isReverseSearch,
        );
        if (result != null) {
          break;
        }
      }
    }
    // If we hit the top and didn't search from the very bottom wrap back down
    if (result == null &&
        startRow != (_terminal.buffer.active.baseY + _terminal.rows - 1)) {
      for (
        var y = (_terminal.buffer.active.baseY + _terminal.rows - 1);
        y >= startRow;
        y--
      ) {
        searchPosition.startRow = y;
        result = _findInLine(
          term,
          searchPosition,
          searchOptions,
          isReverseSearch,
        );
        if (result != null) {
          break;
        }
      }
    }

    return result;
  }

  /// A found substring is a whole word if it doesn't have an alphanumeric
  /// character directly adjacent to it.
  ///
  /// [searchIndex] is the starting index of the potential whole word
  /// substring, [line] the entire string in which the potential whole word
  /// was found, [term] the substring that starts at searchIndex.
  bool _isWholeWord(int searchIndex, String line, String term) {
    return ((searchIndex == 0) || _isNonWordCharacter(line, searchIndex - 1)) &&
        (((searchIndex + term.length) == line.length) ||
            _isNonWordCharacter(line, searchIndex + term.length));
  }

  /// `NON_WORD_CHARACTERS.includes(line[index])`: false past the ends, where
  /// JavaScript reads `undefined`.
  static bool _isNonWordCharacter(String line, int index) {
    if (index < 0 || index >= line.length) {
      return false;
    }
    return _Constants.nonWordCharacters.contains(line[index]);
  }

  /// Searches a line for a search term. Takes the provided terminal line and
  /// searches the text line, which may contain subsequent terminal lines if
  /// the text is wrapped. If the provided line number is part of a wrapped
  /// text line that started on an earlier line then it is skipped since it
  /// will be properly searched when the terminal line that the text starts on
  /// is searched.
  ///
  /// [searchPosition] is the position to start the search; [isReverseSearch]
  /// whether the search should start from the right side of the terminal and
  /// search to the left. Returns the search result if it was found.
  ISearchResult? _findInLine(
    String term,
    _ISearchPosition searchPosition, [
    ISearchOptions? searchOptions,
    bool isReverseSearch = false,
  ]) {
    searchOptions ??= ISearchOptions();
    final row = searchPosition.startRow;
    final col = searchPosition.startCol;

    // Ignore wrapped lines, only consider on unwrapped line (first row of
    // command string).
    final firstLine = _terminal.buffer.active.getLine(row);
    if (firstLine?.isWrapped ?? false) {
      if (isReverseSearch) {
        searchPosition.startCol += _terminal.cols;
        return null;
      }

      // This will iterate until we find the line start.
      // When we find it, we will search using the calculated start column.
      searchPosition.startRow--;
      searchPosition.startCol += _terminal.cols;
      return _findInLine(term, searchPosition, searchOptions);
    }
    var cache = _lineCache.getLineFromCache(row);
    if (cache == null) {
      cache = _lineCache.translateBufferLineToStringWithWrap(row, true);
      _lineCache.setLineInCache(row, cache);
    }
    final (stringLine, offsets) = cache;

    final offset = _bufferColsToStringOffset(row, col);
    var searchTerm = term;
    var searchStringLine = stringLine;
    final caseSensitive = searchOptions.caseSensitive ?? false;
    if (!(searchOptions.regex ?? false)) {
      searchTerm = caseSensitive ? term : term.toLowerCase();
      searchStringLine = caseSensitive ? stringLine : stringLine.toLowerCase();
    }

    var resultIndex = -1;
    if (searchOptions.regex ?? false) {
      final searchRegex = RegExp(searchTerm, caseSensitive: caseSensitive);
      if (isReverseSearch) {
        // This loop will get the resultIndex of the _last_ regex match in the
        // range 0..offset
        final input = searchStringLine.substring(
          0,
          math.min(offset, searchStringLine.length),
        );
        var lastIndex = 0;
        while (lastIndex <= input.length) {
          final foundTerm = _firstMatchFrom(searchRegex, input, lastIndex);
          if (foundTerm == null) {
            break;
          }
          lastIndex = foundTerm.end;
          resultIndex = lastIndex - foundTerm[0]!.length;
          term = foundTerm[0]!;
          lastIndex -= (term.length - 1);
        }
      } else {
        final foundTerm = searchRegex.firstMatch(
          searchStringLine.substring(math.min(offset, searchStringLine.length)),
        );
        if (foundTerm != null && foundTerm[0]!.isNotEmpty) {
          resultIndex = offset + foundTerm.start;
          term = foundTerm[0]!;
        }
      }
    } else {
      if (isReverseSearch) {
        if (offset - searchTerm.length >= 0) {
          resultIndex = searchStringLine.lastIndexOf(
            searchTerm,
            math.min(offset - searchTerm.length, searchStringLine.length),
          );
        }
      } else {
        resultIndex = searchStringLine.indexOf(
          searchTerm,
          math.min(offset, searchStringLine.length),
        );
      }
    }

    if (resultIndex >= 0) {
      if ((searchOptions.wholeWord ?? false) &&
          !_isWholeWord(resultIndex, searchStringLine, term)) {
        return null;
      }

      // Adjust the row number and search index if needed since a "line" of
      // text can span multiple rows
      var startRowOffset = 0;
      while (startRowOffset < offsets.length - 1 &&
          resultIndex >= offsets[startRowOffset + 1]) {
        startRowOffset++;
      }
      var endRowOffset = startRowOffset;
      while (endRowOffset < offsets.length - 1 &&
          resultIndex + term.length >= offsets[endRowOffset + 1]) {
        endRowOffset++;
      }
      final startColOffset = resultIndex - offsets[startRowOffset];
      final endColOffset = resultIndex + term.length - offsets[endRowOffset];
      final startColIndex = _stringLengthToBufferSize(
        row + startRowOffset,
        startColOffset,
      );
      final endColIndex = _stringLengthToBufferSize(
        row + endRowOffset,
        endColOffset,
      );
      final size =
          endColIndex -
          startColIndex +
          _terminal.cols * (endRowOffset - startRowOffset);

      return ISearchResult(
        term: term,
        col: startColIndex,
        row: row + startRowOffset,
        size: size,
      );
    }
    return null;
  }

  /// A `g` regex's `exec` with `lastIndex` at [start]: the first match at or
  /// after [start], which anchors and lookbehinds see in all of [input].
  static RegExpMatch? _firstMatchFrom(RegExp regex, String input, int start) {
    final matches = regex.allMatches(input, start).iterator;
    return matches.moveNext() ? matches.current : null;
  }

  int _stringLengthToBufferSize(int row, int offset) {
    final line = _terminal.buffer.active.getLine(row);
    if (line == null) {
      return 0;
    }
    for (var i = 0; i < offset; i++) {
      final cell = line.getCell(i);
      if (cell == null) {
        break;
      }
      // Adjust the searchIndex to normalize emoji into single chars
      final char = cell.getChars();
      if (char.length > 1) {
        offset -= char.length - 1;
      }
      // Adjust the searchIndex for empty characters following wide unicode
      // chars (eg. CJK)
      final nextCell = line.getCell(i + 1);
      if (nextCell != null && nextCell.getWidth() == 0) {
        offset++;
      }
    }
    return offset;
  }

  int _bufferColsToStringOffset(int startRow, int cols) {
    var lineIndex = startRow;
    var offset = 0;
    var line = _terminal.buffer.active.getLine(lineIndex);
    while (cols > 0 && line != null) {
      for (var i = 0; i < cols && i < _terminal.cols; i++) {
        final cell = line.getCell(i);
        if (cell == null) {
          break;
        }
        if (cell.getWidth() != 0) {
          // Treat null characters as whitespace to align with the
          // translateToString API
          offset += cell.getCode() == 0 ? 1 : cell.getChars().length;
        }
      }
      lineIndex++;
      line = _terminal.buffer.active.getLine(lineIndex);
      if (line != null && !line.isWrapped) {
        break;
      }
      cols -= _terminal.cols;
    }
    return offset;
  }
}
