// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See
// lib/ide/terminal/xterm/addons/addon_search/LICENSE.
// Ported from xterm.js addons/addon-search/src/SearchResultTracker.ts
// (c58ea36).

import 'dart:collection';

import '../../common/event.dart';
import '../../common/lifecycle.dart';
import 'search_engine.dart';
import 'typings/addon_search.dart';

/// Interface for managing a currently selected decoration.
///
/// Upstream's module-private interface; DecorationManager's
/// `IMultiHighlight` implements it (TypeScript matches it structurally).
abstract interface class ISelectedDecoration implements IDisposable {
  ISearchResult get match;
}

/// Tracks search results, manages result indexing, and fires events when
/// results change. This class provides centralized management of search
/// result state and notifications.
class SearchResultTracker extends Disposable {
  SearchResultTracker() {
    _onDidChangeResults = register(Emitter<ISearchResultChangeEvent>());
  }

  List<ISearchResult> _searchResults = <ISearchResult>[];

  /// The currently selected decoration.
  ISelectedDecoration? selectedDecoration;

  late final Emitter<ISearchResultChangeEvent> _onDidChangeResults;
  IEvent<ISearchResultChangeEvent> get onDidChangeResults =>
      _onDidChangeResults.event;

  /// Gets the current search results.
  List<ISearchResult> get searchResults =>
      UnmodifiableListView<ISearchResult>(_searchResults);

  /// Updates the search results with a new set of [results], keeping at most
  /// [maxResults] of them.
  void updateResults(List<ISearchResult> results, int maxResults) {
    _searchResults = results.sublist(0, maxResults.clamp(0, results.length));
  }

  /// Clears all search results.
  void clearResults() {
    _searchResults = <ISearchResult>[];
  }

  /// Clears the selected decoration.
  void clearSelectedDecoration() {
    final selectedDecoration = this.selectedDecoration;
    if (selectedDecoration != null) {
      selectedDecoration.dispose();
      this.selectedDecoration = null;
    }
  }

  /// Finds the index of a result in the current results array; returns -1 if
  /// not found.
  int findResultIndex(ISearchResult result) {
    for (var i = 0; i < _searchResults.length; i++) {
      final match = _searchResults[i];
      if (match.row == result.row &&
          match.col == result.col &&
          match.size == result.size) {
        return i;
      }
    }
    return -1;
  }

  /// Fires a result change event with the current state, if [hasDecorations]
  /// (whether decorations are enabled).
  void fireResultsChanged(bool hasDecorations) {
    if (!hasDecorations) {
      return;
    }

    var resultIndex = -1;
    final selectedDecoration = this.selectedDecoration;
    if (selectedDecoration != null) {
      resultIndex = findResultIndex(selectedDecoration.match);
    }

    _onDidChangeResults.fire(
      ISearchResultChangeEvent(
        resultIndex: resultIndex,
        resultCount: _searchResults.length,
      ),
    );
  }

  /// Resets all state.
  void reset() {
    clearSelectedDecoration();
    clearResults();
  }
}
