// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See
// lib/addons/addon_search/LICENSE.
// Ported from xterm.js addons/addon-search/src/DecorationManager.ts
// (c58ea36).
//
// Upstream styles each decoration's DOM element when it renders
// (`_applyStyles`: a CSS class, and `matchBorder`/`activeMatchBorder` as an
// outline). There is no element here: the renderer paints a decoration's
// background color over its cells and its overview ruler mark, so
// `_applyStyles` and its `onRender` listener are left out and the border
// colors go unused.

import 'dart:math' as math;

import '../../common/lifecycle.dart';
import '../../typings/xterm.dart'
    show IDecoration, IDecorationOptions, IDecorationOverviewRulerOptions;
import 'search_engine.dart';
import 'search_result_tracker.dart';
import 'typings/addon_search.dart';

/// Interface for managing a highlight decoration.
class IHighlight implements IDisposable {
  IHighlight({required this.decoration, required this.match});

  final IDecoration decoration;
  final ISearchResult match;

  @override
  void dispose() {
    decoration.dispose();
  }
}

/// Interface for managing multiple decorations for a single match.
class IMultiHighlight implements ISelectedDecoration {
  IMultiHighlight({required this.decorations, required this.match});

  final List<IDecoration> decorations;
  @override
  final ISearchResult match;

  @override
  void dispose() {
    disposeAll(decorations);
  }
}

/// Manages visual decorations for search results including highlighting and
/// active selection indicators. This class handles the creation, styling, and
/// disposal of search-related decorations.
class DecorationManager extends Disposable {
  DecorationManager(this._terminal) {
    register(toDisposable(() => clearHighlightDecorations()));
  }

  final ISearchTerminal _terminal;
  List<IHighlight> _highlightDecorations = <IHighlight>[];
  final Set<int> _highlightedLines = <int>{};

  /// Creates decorations for all provided search [results] with the
  /// decoration [options].
  void createHighlightDecorations(
    List<ISearchResult> results,
    ISearchDecorationOptions options,
  ) {
    clearHighlightDecorations();

    for (final match in results) {
      final decorations = _createResultDecorations(match, options, false);
      if (decorations != null) {
        for (final decoration in decorations) {
          _storeDecoration(decoration, match);
        }
      }
    }
  }

  /// Creates decorations for the currently active search [result]; returns
  /// the multi-highlight decoration or null if creation failed.
  IMultiHighlight? createActiveDecoration(
    ISearchResult result,
    ISearchDecorationOptions options,
  ) {
    final decorations = _createResultDecorations(result, options, true);
    if (decorations != null) {
      return IMultiHighlight(decorations: decorations, match: result);
    }
    return null;
  }

  /// Clears all highlight decorations.
  void clearHighlightDecorations() {
    disposeAll(_highlightDecorations);
    _highlightDecorations = <IHighlight>[];
    _highlightedLines.clear();
  }

  /// Stores a [decoration] and tracks it for management; [match] is the
  /// search result this decoration represents.
  void _storeDecoration(IDecoration decoration, ISearchResult match) {
    _highlightedLines.add(decoration.marker.line);
    _highlightDecorations.add(IHighlight(decoration: decoration, match: match));
  }

  /// Creates a decoration for the [result] and applies styles; returns the
  /// decorations or null if the marker has already been disposed of.
  List<IDecoration>? _createResultDecorations(
    ISearchResult result,
    ISearchDecorationOptions options,
    bool isActiveResult,
  ) {
    // Gather decoration ranges for this match as it could wrap
    final decorationRanges = <(int, int, int)>[];
    var currentCol = result.col;
    var remainingSize = result.size;
    var markerOffset =
        -_terminal.buffer.active.baseY -
        _terminal.buffer.active.cursorY +
        result.row;
    while (remainingSize > 0) {
      final amountThisRow = math.min(
        _terminal.cols - currentCol,
        remainingSize,
      );
      decorationRanges.add((markerOffset, currentCol, amountThisRow));
      currentCol = 0;
      remainingSize -= amountThisRow;
      markerOffset++;
    }

    // Create the decorations
    final decorations = <IDecoration>[];
    for (final range in decorationRanges) {
      final marker = _terminal.registerMarker(range.$1);
      final decoration = _terminal.registerDecoration(
        IDecorationOptions(
          marker: marker,
          x: range.$2,
          width: range.$3,
          layer: isActiveResult ? 'top' : 'bottom',
          backgroundColor: isActiveResult
              ? options.activeMatchBackground
              : options.matchBackground,
          overviewRulerOptions: _highlightedLines.contains(marker.line)
              ? null
              : IDecorationOverviewRulerOptions(
                  color: isActiveResult
                      ? options.activeMatchColorOverviewRuler
                      : options.matchOverviewRuler,
                  position: 'center',
                ),
        ),
      );
      if (decoration != null) {
        final disposables = <IDisposable>[];
        disposables.add(marker);
        disposables.add(decoration.onDispose((_) => disposeAll(disposables)));
        decorations.add(decoration);
      }
    }

    return decorations.isEmpty ? null : decorations;
  }
}
