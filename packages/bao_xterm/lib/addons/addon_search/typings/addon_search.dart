// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See
// lib/addons/addon_search/LICENSE.
// Ported from xterm.js addons/addon-search/typings/addon-search.d.ts
// (c58ea36).
//
// Upstream's addon runs on the browser `Terminal` of `@xterm/xterm`, which
// the Dart typings do not have. [ISearchTerminal] (not upstream) is the
// headless `Terminal` plus the members of the browser one that the addon and
// its embedders (VS Code's find widget) use: the selection and decorations,
// which belong to whoever draws the terminal. The constructor of
// `SearchAddon`, which takes a `Partial<ISearchAddonOptions>`, belongs to the
// implementing class (search_addon.dart).

/// The public API of the search addon (`@xterm/addon-search`).
library;

import '../../../typings/xterm.dart' show IDecoration, IDecorationOptions;
import '../../../typings/xterm_headless.dart';

/// Options for a search.
class ISearchOptions {
  ISearchOptions({
    this.regex,
    this.wholeWord,
    this.caseSensitive,
    this.incremental,
    this.decorations,
  });

  /// Whether the search term is a regex.
  bool? regex;

  /// Whether to search for a whole word, the result is only valid if it's
  /// surrounded in "non-word" characters such as `_`, `(`, `)` or space.
  bool? wholeWord;

  /// Whether the search is case sensitive.
  bool? caseSensitive;

  /// Whether to do an incremental search, this will expand the selection if
  /// it still matches the term the user typed. Note that this only affects
  /// `findNext`, not `findPrevious`.
  bool? incremental;

  /// When set, will highlight all instances of the word on search and show
  /// them in the overview ruler if it's enabled.
  ISearchDecorationOptions? decorations;
}

/// Options for showing decorations when searching.
class ISearchDecorationOptions {
  ISearchDecorationOptions({
    this.matchBackground,
    this.matchBorder,
    required this.matchOverviewRuler,
    this.activeMatchBackground,
    this.activeMatchBorder,
    required this.activeMatchColorOverviewRuler,
  });

  /// The background color of a match, this must use #RRGGBB format.
  String? matchBackground;

  /// The border color of a match.
  String? matchBorder;

  /// The overview ruler color of a match.
  String matchOverviewRuler;

  /// The background color for the currently active match, this must use
  /// #RRGGBB format.
  String? activeMatchBackground;

  /// The border color of the currently active match.
  String? activeMatchBorder;

  /// The overview ruler color of the currently active match.
  String activeMatchColorOverviewRuler;
}

/// Event data fired when search results change.
class ISearchResultChangeEvent {
  ISearchResultChangeEvent({
    required this.resultIndex,
    required this.resultCount,
  });

  /// The index of the currently active result, -1 when the threshold of
  /// matches is exceeded.
  int resultIndex;

  /// The total number of search results found.
  int resultCount;

  @override
  bool operator ==(Object other) =>
      other is ISearchResultChangeEvent &&
      other.resultIndex == resultIndex &&
      other.resultCount == resultCount;

  @override
  int get hashCode => Object.hash(resultIndex, resultCount);

  @override
  String toString() => '{resultCount: $resultCount, resultIndex: $resultIndex}';
}

/// Options for the search addon.
///
/// The constructor takes upstream's `Partial<ISearchAddonOptions>`, so the
/// field is nullable.
class ISearchAddonOptions {
  ISearchAddonOptions({this.highlightLimit});

  /// Max number of matches highlighted when decorations are enabled.
  /// Defaults to 1000 highlighted matches
  int? highlightLimit;
}

/// The terminal the addon runs on (not upstream): the headless API plus the
/// browser `Terminal`'s selection and decorations (xterm.d.ts).
///
/// An embedder implements it over its selection service and decoration
/// service, as CoreBrowserTerminal forwards these to its SelectionService and
/// DecorationService.
abstract interface class ISearchTerminal implements Terminal {
  /// Fires when the selection changes.
  IEvent<void> get onSelectionChange;

  /// (EXPERIMENTAL) Adds a decoration to the terminal using [decorationOptions]
  /// or null when the marker has been disposed of.
  IDecoration? registerDecoration(IDecorationOptions decorationOptions);

  /// Gets whether the terminal has an active selection.
  bool hasSelection();

  /// Gets the terminal's current selection, this is useful for implementing
  /// copy behavior outside of xterm.js.
  String getSelection();

  /// Gets the selection position or null if there is no selection. Upstream
  /// returns the selection service's 0-based `[x, y]` start and end (the end
  /// exclusive) in the [IBufferRange].
  IBufferRange? getSelectionPosition();

  /// Clears the current terminal selection.
  void clearSelection();

  /// Selects text within the terminal: [length] cells from [column] of buffer
  /// line [row].
  void select(int column, int row, int length);
}

/// An xterm.js addon that provides search functionality.
abstract interface class SearchAddon implements ITerminalAddon {
  /// Activates the addon; [terminal] is the terminal the addon is being
  /// loaded in (upstream: the browser `Terminal`).
  @override
  void activate(covariant ISearchTerminal terminal);

  /// Disposes the addon.
  @override
  void dispose();

  /// Search forwards for the next result that matches the search term and
  /// options.
  bool findNext(String term, [ISearchOptions? searchOptions]);

  /// Search backwards for the previous result that matches the search term
  /// and options.
  bool findPrevious(String term, [ISearchOptions? searchOptions]);

  /// Clears the decorations and selection
  void clearDecorations();

  /// Clears the active result decoration, this decoration is applied on top
  /// of the selection so removing it will reveal the selection underneath.
  /// This is intended to be called on the search textarea's `blur` event.
  void clearActiveDecoration();

  /// Fires after a search is performed.
  IEvent<void> get onAfterSearch;

  /// Fires before a search is performed.
  IEvent<void> get onBeforeSearch;

  /// When decorations are enabled, fires when the search results change.
  IEvent<ISearchResultChangeEvent> get onDidChangeResults;
}
