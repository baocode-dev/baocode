/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Adapted from VS Code src/vs/editor/contrib/gotoError/browser/
// markerNavigationService.ts (MarkerList: sorting, _initIdx, move) at
// 6a598d4a13031703d483d103c1d934a36ad27971.
// Deviations: markers are [NavigationMarker]s over resource strings; the
// list is a value built from a snapshot (the caller rebuilds it when
// markers change, which resets the index like upstream's onMarkerChanged);
// an empty marker range is not widened to the word at its start.
// `problems.sortOrder` is its default, 'severity'.

import '../../../common/core/position.dart';
import '../../../common/core/range.dart';

/// Marker severities, upstream `MarkerSeverity` values.
abstract final class MarkerSeverity {
  static const int hint = 1;
  static const int info = 2;
  static const int warning = 4;
  static const int error = 8;

  /// Higher severity first.
  static int compare(int a, int b) => b - a;
}

class NavigationMarker<T> {
  const NavigationMarker(this.resource, this.range, this.severity, this.data);

  final String resource;
  final Range range;
  final int severity;
  final T data;
}

class MarkerList<T> {
  /// Errors, warnings and infos (not hints) sorted by resource, severity and
  /// position.
  MarkerList(Iterable<NavigationMarker<T>> markers)
    : _markers =
          markers.where((m) => m.severity >= MarkerSeverity.info).toList()
            ..sort((a, b) {
              var res = a.resource.compareTo(b.resource);
              if (res == 0) {
                res = MarkerSeverity.compare(a.severity, b.severity);
                if (res == 0) {
                  res = Range.compareRangesUsingStarts(a.range, b.range);
                }
              }
              return res;
            });

  final List<NavigationMarker<T>> _markers;
  int _nextIdx = -1;

  List<NavigationMarker<T>> get markers => List.unmodifiable(_markers);

  /// The current marker, its one-based index and the total.
  ({NavigationMarker<T> marker, int index, int total})? get selected {
    if (_nextIdx < 0 || _nextIdx >= _markers.length) return null;
    return (
      marker: _markers[_nextIdx],
      index: _nextIdx + 1,
      total: _markers.length,
    );
  }

  void resetIndex() => _nextIdx = -1;

  void _initIdx(String resource, Position position, bool fwd) {
    var idx = _markers.indexWhere((marker) => marker.resource == resource);
    if (idx < 0) {
      // ignore model, position because this will be a different file
      idx = _markers.indexWhere((m) => m.resource.compareTo(resource) > 0);
      if (idx < 0) idx = _markers.length;
      if (fwd) {
        _nextIdx = idx;
      } else {
        _nextIdx = (_markers.length + idx - 1) % _markers.length;
      }
    } else {
      // find marker for file
      var found = false;
      var wentPast = false;
      for (var i = idx; i < _markers.length; i++) {
        final range = _markers[i].range;
        if (range.containsPosition(position) ||
            position.isBeforeOrEqual(range.getStartPosition())) {
          _nextIdx = i;
          found = true;
          wentPast = !range.containsPosition(position);
          break;
        }
        if (_markers[i].resource != resource) break;
      }
      if (!found) {
        // after the last change
        _nextIdx = fwd ? 0 : _markers.length - 1;
      } else if (wentPast && !fwd) {
        // we went past and have to go one back
        _nextIdx -= 1;
      }
    }
    if (_nextIdx < 0 || _nextIdx >= _markers.length) {
      _nextIdx = fwd ? 0 : _markers.length - 1;
    }
  }

  /// Moves to the next/previous marker from [position] in [resource] (or
  /// from the current one). Returns whether the index changed.
  bool move(bool fwd, String resource, Position position) {
    if (_markers.isEmpty) return false;
    final oldIdx = _nextIdx;
    if (_nextIdx == -1) {
      _initIdx(resource, position, fwd);
    } else if (fwd) {
      _nextIdx = (_nextIdx + 1) % _markers.length;
    } else {
      _nextIdx = (_nextIdx - 1 + _markers.length) % _markers.length;
    }
    return oldIdx != _nextIdx;
  }
}
