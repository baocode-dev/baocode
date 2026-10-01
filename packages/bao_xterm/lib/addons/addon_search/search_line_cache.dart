// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See
// lib/addons/addon_search/LICENSE.
// Ported from xterm.js addons/addon-search/src/SearchLineCache.ts (c58ea36).
//
// Upstream types the browser `Terminal` but uses only its headless API. The
// cache is a sparse array sized to the buffer; here it is a map, which reads
// null for any row (upstream: undefined, negative rows too) and takes any row.

import '../../common/async.dart';
import '../../common/lifecycle.dart';
import '../../typings/xterm_headless.dart';

/// Upstream's labeled tuple `[lineAsString, lineOffsets]`: the string
/// representation of a line (as opposed to the buffer cell representation),
/// and the offsets where each line starts when the entry describes a wrapped
/// line.
typedef LineCacheEntry = (String lineAsString, List<int> lineOffsets);

/// Configuration constants for the search line cache functionality.
abstract final class _Constants {
  /// Time-to-live for cached search results in milliseconds. After this
  /// duration, cached search results will be invalidated to ensure they remain
  /// consistent with terminal content changes.
  static const int linesCacheTimeToLive = 15000;
}

class SearchLineCache extends Disposable {
  SearchLineCache(this._terminal) {
    _linesCacheTimeout = register(MutableDisposable<IDisposable>());
    _linesCacheDisposables = register(MutableDisposable<IDisposable>());
    register(toDisposable(() => _destroyLinesCache()));
  }

  final Terminal _terminal;

  /// translateBufferLineToStringWithWrap is a fairly expensive call.
  /// We memoize the calls into an array that has a time based ttl.
  /// _linesCache is also invalidated when the terminal cursor moves.
  Map<int, LineCacheEntry>? _linesCache;
  late final MutableDisposable<IDisposable> _linesCacheTimeout;
  late final MutableDisposable<IDisposable> _linesCacheDisposables;
  // Track access to avoid recreating a timeout on every init call which
  // occurs once per search result (findNext/findPrevious ->
  // _highlightAllMatches -> find loop).
  int _lastAccessTimestamp = 0;

  /// Sets up a line cache with a ttl
  void initLinesCache() {
    if (_linesCache == null) {
      _linesCache = <int, LineCacheEntry>{};
      _linesCacheDisposables.value = combinedDisposable(<IDisposable>[
        _terminal.onLineFeed((_) => _destroyLinesCache()),
        _terminal.onCursorMove((_) => _destroyLinesCache()),
        _terminal.onResize((_) => _destroyLinesCache()),
      ]);
    }

    _lastAccessTimestamp = DateTime.now().millisecondsSinceEpoch;
    if (_linesCacheTimeout.value == null) {
      _scheduleLinesCacheTimeout(_Constants.linesCacheTimeToLive);
    }
  }

  void _destroyLinesCache() {
    _linesCache = null;
    _lastAccessTimestamp = 0;
    _linesCacheDisposables.clear();
    _linesCacheTimeout.clear();
  }

  void _scheduleLinesCacheTimeout(int delay) {
    _linesCacheTimeout.value = disposableTimeout(() {
      if (_linesCache == null) {
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = now - _lastAccessTimestamp;
      if (elapsed >= _Constants.linesCacheTimeToLive) {
        _destroyLinesCache();
        return;
      }
      _scheduleLinesCacheTimeout(_Constants.linesCacheTimeToLive - elapsed);
    }, delay);
  }

  LineCacheEntry? getLineFromCache(int row) {
    return _linesCache?[row];
  }

  void setLineInCache(int row, LineCacheEntry entry) {
    _linesCache?[row] = entry;
  }

  /// Translates a buffer line to a string, including subsequent lines if they
  /// are wraps. Wide characters will count as two columns in the resulting
  /// string. This function is useful for getting the actual text underneath
  /// the raw selection position.
  ///
  /// [lineIndex] is the index of the line being translated; [trimRight]
  /// whether to trim whitespace to the right.
  LineCacheEntry translateBufferLineToStringWithWrap(
    int lineIndex,
    bool trimRight,
  ) {
    final strings = <String>[];
    final lineOffsets = <int>[0];
    var line = _terminal.buffer.active.getLine(lineIndex);
    while (line != null) {
      final nextLine = _terminal.buffer.active.getLine(lineIndex + 1);
      final lineWrapsToNext = nextLine != null ? nextLine.isWrapped : false;
      var string = line.translateToString(!lineWrapsToNext && trimRight);
      if (lineWrapsToNext) {
        final lastCell = line.getCell(line.length - 1);
        final lastCellIsNull =
            lastCell != null &&
            lastCell.getCode() == 0 &&
            lastCell.getWidth() == 1;
        // a wide character wrapped to the next line
        if (lastCellIsNull && nextLine.getCell(0)?.getWidth() == 2) {
          string = string.substring(0, string.isEmpty ? 0 : string.length - 1);
        }
      }
      strings.add(string);
      if (lineWrapsToNext) {
        lineOffsets.add(lineOffsets[lineOffsets.length - 1] + string.length);
      } else {
        break;
      }
      lineIndex++;
      line = nextLine;
    }
    return (strings.join(), lineOffsets);
  }
}
