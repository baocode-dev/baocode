// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See
// lib/addons/addon_search/LICENSE.
// Ported from xterm.js addons/addon-search/src/SearchAddon.ts (c58ea36).
//
// The typings' `SearchAddon` interface is imported `as api` (upstream:
// `SearchAddon as ISearchApi`). The addon activates on an [ISearchTerminal]
// (upstream: the browser `Terminal`); `activate` narrows the headless
// `ITerminalAddon`'s parameter with `covariant`.

import '../../common/async.dart';
import '../../common/event.dart';
import '../../common/lifecycle.dart';
import 'decoration_manager.dart';
import 'search_engine.dart';
import 'search_line_cache.dart';
import 'search_result_tracker.dart';
import 'search_state.dart';
import 'typings/addon_search.dart' hide SearchAddon;
import 'typings/addon_search.dart' as api show SearchAddon;

class IInternalSearchOptions {
  IInternalSearchOptions({required this.noScroll});

  bool noScroll;
}

/// Configuration constants for the search addon functionality.
abstract final class _Constants {
  /// Default maximum number of search results to highlight simultaneously.
  /// This limit prevents performance degradation when searching for very
  /// common terms that would result in excessive highlighting decorations.
  static const int defaultHighlightLimit = 1000;
}

class SearchAddon extends Disposable implements api.SearchAddon {
  SearchAddon([ISearchAddonOptions? options]) {
    _highlightTimeout = register(MutableDisposable<IDisposable>());
    _lineCache = register(MutableDisposable<SearchLineCache>());
    _resultTracker = register(SearchResultTracker());
    _onAfterSearch = register(Emitter<void>());
    _onBeforeSearch = register(Emitter<void>());

    _highlightLimit =
        options?.highlightLimit ?? _Constants.defaultHighlightLimit;
  }

  ISearchTerminal? _terminal;
  late final int _highlightLimit;
  late final MutableDisposable<IDisposable> _highlightTimeout;
  late final MutableDisposable<SearchLineCache> _lineCache;

  // Component instances
  final SearchState _state = SearchState();
  SearchEngine? _engine;
  DecorationManager? _decorationManager;
  late final SearchResultTracker _resultTracker;

  late final Emitter<void> _onAfterSearch;
  @override
  IEvent<void> get onAfterSearch => _onAfterSearch.event;
  late final Emitter<void> _onBeforeSearch;
  @override
  IEvent<void> get onBeforeSearch => _onBeforeSearch.event;

  @override
  IEvent<ISearchResultChangeEvent> get onDidChangeResults =>
      _resultTracker.onDidChangeResults;

  @override
  void activate(covariant ISearchTerminal terminal) {
    _terminal = terminal;
    _lineCache.value = SearchLineCache(terminal);
    _engine = SearchEngine(terminal, _lineCache.value!);
    _decorationManager = DecorationManager(terminal);
    register(terminal.onWriteParsed((_) => _updateMatches()));
    register(terminal.onResize((_) => _updateMatches()));
    register(toDisposable(() => clearDecorations()));
  }

  void _updateMatches() {
    _highlightTimeout.clear();
    final cachedSearchTerm = _state.cachedSearchTerm;
    if (cachedSearchTerm != null &&
        cachedSearchTerm.isNotEmpty &&
        _state.lastSearchOptions?.decorations != null) {
      _highlightTimeout.value = disposableTimeout(() {
        // A term cleared since searches for '' (upstream: undefined, which
        // finds nothing the same way).
        final term = _state.cachedSearchTerm ?? '';
        _state.clearCachedTerm();
        final lastSearchOptions = _state.lastSearchOptions;
        findPrevious(
          term,
          ISearchOptions(
            regex: lastSearchOptions?.regex,
            wholeWord: lastSearchOptions?.wholeWord,
            caseSensitive: lastSearchOptions?.caseSensitive,
            incremental: true,
            decorations: lastSearchOptions?.decorations,
          ),
          IInternalSearchOptions(noScroll: true),
        );
      }, 200);
    }
  }

  /// Clears the decorations and selection; the cached search term too unless
  /// [retainCachedSearchTerm].
  @override
  void clearDecorations([bool? retainCachedSearchTerm]) {
    _resultTracker.clearSelectedDecoration();
    _decorationManager?.clearHighlightDecorations();
    _resultTracker.clearResults();
    if (!(retainCachedSearchTerm ?? false)) {
      _state.clearCachedTerm();
    }
  }

  @override
  void clearActiveDecoration() {
    _resultTracker.clearSelectedDecoration();
  }

  /// Find the next instance of the [term], then scroll to and select it. If
  /// it doesn't exist, do nothing. Returns whether a result was found.
  @override
  bool findNext(
    String term, [
    ISearchOptions? searchOptions,
    IInternalSearchOptions? internalSearchOptions,
  ]) {
    if (_terminal == null || _engine == null) {
      throw StateError('Cannot use addon until it has been loaded');
    }

    _onBeforeSearch.fire(null);

    _state.lastSearchOptions = searchOptions;

    if (_state.shouldUpdateHighlighting(term, searchOptions)) {
      _highlightAllMatches(term, searchOptions!);
    }

    final found = _findNextAndSelect(
      term,
      searchOptions,
      internalSearchOptions,
    );
    _fireResults(searchOptions);
    _state.cachedSearchTerm = term;

    _onAfterSearch.fire(null);

    return found;
  }

  void _highlightAllMatches(String term, ISearchOptions searchOptions) {
    final terminal = _terminal;
    final engine = _engine;
    final decorationManager = _decorationManager;
    if (terminal == null || engine == null || decorationManager == null) {
      throw StateError('Cannot use addon until it has been loaded');
    }
    if (!_state.isValidSearchTerm(term)) {
      clearDecorations();
      return;
    }

    // new search, clear out the old decorations
    clearDecorations(true);

    final results = <ISearchResult>[];
    ISearchResult? prevResult;
    var result = engine.find(term, 0, 0, searchOptions);

    while (result != null &&
        (prevResult?.row != result.row || prevResult?.col != result.col)) {
      if (results.length >= _highlightLimit) {
        break;
      }
      prevResult = result;
      results.add(prevResult);
      final cols = terminal.cols;
      var nextCol = prevResult.col + prevResult.size;
      var nextRow = prevResult.row;
      if (nextCol >= cols) {
        nextRow += nextCol ~/ cols;
        nextCol = nextCol % cols;
      }
      result = engine.find(term, nextRow, nextCol, searchOptions);
    }

    _resultTracker.updateResults(results, _highlightLimit);
    final decorations = searchOptions.decorations;
    if (decorations != null) {
      decorationManager.createHighlightDecorations(results, decorations);
    }
  }

  bool _findNextAndSelect(
    String term, [
    ISearchOptions? searchOptions,
    IInternalSearchOptions? internalSearchOptions,
  ]) {
    final terminal = _terminal;
    final engine = _engine;
    if (terminal == null || engine == null) {
      return false;
    }
    if (!_state.isValidSearchTerm(term)) {
      terminal.clearSelection();
      clearDecorations();
      return false;
    }

    final result = engine.findNextWithSelection(
      term,
      searchOptions,
      _state.cachedSearchTerm,
    );
    return _selectResult(
      result,
      searchOptions?.decorations,
      internalSearchOptions?.noScroll,
    );
  }

  /// Find the previous instance of the [term], then scroll to and select it.
  /// If it doesn't exist, do nothing. Returns whether a result was found.
  @override
  bool findPrevious(
    String term, [
    ISearchOptions? searchOptions,
    IInternalSearchOptions? internalSearchOptions,
  ]) {
    if (_terminal == null || _engine == null) {
      throw StateError('Cannot use addon until it has been loaded');
    }

    _onBeforeSearch.fire(null);

    _state.lastSearchOptions = searchOptions;

    if (_state.shouldUpdateHighlighting(term, searchOptions)) {
      _highlightAllMatches(term, searchOptions!);
    }

    final found = _findPreviousAndSelect(
      term,
      searchOptions,
      internalSearchOptions,
    );
    _fireResults(searchOptions);
    _state.cachedSearchTerm = term;

    _onAfterSearch.fire(null);

    return found;
  }

  void _fireResults([ISearchOptions? searchOptions]) {
    _resultTracker.fireResultsChanged(searchOptions?.decorations != null);
  }

  bool _findPreviousAndSelect(
    String term, [
    ISearchOptions? searchOptions,
    IInternalSearchOptions? internalSearchOptions,
  ]) {
    final terminal = _terminal;
    final engine = _engine;
    if (terminal == null || engine == null) {
      return false;
    }
    if (!_state.isValidSearchTerm(term)) {
      terminal.clearSelection();
      clearDecorations();
      return false;
    }

    final result = engine.findPreviousWithSelection(
      term,
      searchOptions,
      _state.cachedSearchTerm,
    );
    return _selectResult(
      result,
      searchOptions?.decorations,
      internalSearchOptions?.noScroll,
    );
  }

  /// Selects and scrolls to a [result]; returns whether a result was
  /// selected.
  bool _selectResult(
    ISearchResult? result, [
    ISearchDecorationOptions? options,
    bool? noScroll,
  ]) {
    final terminal = _terminal;
    final decorationManager = _decorationManager;
    if (terminal == null || decorationManager == null) {
      return false;
    }

    _resultTracker.clearSelectedDecoration();
    if (result == null) {
      terminal.clearSelection();
      return false;
    }

    terminal.select(result.col, result.row, result.size);
    if (options != null) {
      final activeDecoration = decorationManager.createActiveDecoration(
        result,
        options,
      );
      if (activeDecoration != null) {
        _resultTracker.selectedDecoration = activeDecoration;
      }
    }

    if (!(noScroll ?? false)) {
      // If it is not in the viewport then we scroll else it just gets selected
      final viewportY = terminal.buffer.active.viewportY;
      if (result.row >= (viewportY + terminal.rows) || result.row < viewportY) {
        var scroll = result.row - viewportY;
        scroll -= (terminal.rows / 2).floor();
        terminal.scrollLines(scroll);
      }
    }
    return true;
  }
}
