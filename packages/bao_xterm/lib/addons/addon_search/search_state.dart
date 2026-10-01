// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See
// lib/ide/terminal/xterm/addons/addon_search/LICENSE.
// Ported from xterm.js addons/addon-search/src/SearchState.ts (c58ea36).

import 'typings/addon_search.dart';

/// Manages search state including cached search terms, options tracking, and
/// validation. This class provides a centralized way to handle search state
/// consistency and option changes.
class SearchState {
  /// The currently cached search term.
  String? cachedSearchTerm;

  /// The last search options used.
  ISearchOptions? lastSearchOptions;

  /// Validates a search term to ensure it's not empty or invalid; returns
  /// true if the term is valid for searching.
  bool isValidSearchTerm(String term) {
    return term.isNotEmpty;
  }

  /// Determines if search options have changed compared to the last search;
  /// returns true if the options have changed.
  bool didOptionsChange([ISearchOptions? newOptions]) {
    final lastSearchOptions = this.lastSearchOptions;
    if (lastSearchOptions == null) {
      return true;
    }
    if (newOptions == null) {
      return false;
    }
    if (lastSearchOptions.caseSensitive != newOptions.caseSensitive) {
      return true;
    }
    if (lastSearchOptions.regex != newOptions.regex) {
      return true;
    }
    if (lastSearchOptions.wholeWord != newOptions.wholeWord) {
      return true;
    }
    return false;
  }

  /// Determines if a new search should trigger highlighting updates; returns
  /// true if highlighting should be updated.
  bool shouldUpdateHighlighting(String term, [ISearchOptions? options]) {
    if (options?.decorations == null) {
      return false;
    }
    return cachedSearchTerm == null ||
        term != cachedSearchTerm ||
        didOptionsChange(options);
  }

  /// Clears the cached search term.
  void clearCachedTerm() {
    cachedSearchTerm = null;
  }

  /// Resets all state.
  void reset() {
    cachedSearchTerm = null;
    lastSearchOptions = null;
  }
}
