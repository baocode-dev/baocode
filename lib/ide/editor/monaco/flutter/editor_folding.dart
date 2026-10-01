import 'dart:typed_data';

import 'package:flutter/services.dart' show TextSelection;

import '../vs/editor/common/languages/language_configuration.dart';
import '../vs/editor/contrib/folding/browser/folding_ranges.dart';
import '../vs/editor/contrib/folding/browser/indent_range_provider.dart';
import 'document_snapshot.dart';
import 'viewport_layout.dart' show HiddenLineRanges;

class _SnapshotLines implements FoldingLineSource {
  _SnapshotLines(this.snapshot);

  final DocumentSnapshot snapshot;

  @override
  int get lineCount => snapshot.lineCount;

  @override
  String getLineContent(int lineNumber) => snapshot.text.substring(
    snapshot.lineStarts[lineNumber - 1],
    snapshot.contentEnds[lineNumber - 1],
  );
}

class _SelectedLines implements SelectedLines {
  _SelectedLines(this.lines);

  final List<int> lines;

  @override
  bool startsInside(int startLine, int endLine) =>
      lines.any((line) => line >= startLine && line <= endLine);
}

/// Line-structure difference between two snapshots from their common UTF-16
/// prefix and suffix. One-based old lines before [firstChangedLine] keep their
/// numbers (their text starts before the edit); old lines at or after
/// [firstShiftedLine] start after the edit and move by [delta]; lines in
/// between started inside replaced text.
typedef LineShift = ({int firstChangedLine, int firstShiftedLine, int delta});

LineShift computeLineShift(DocumentSnapshot before, DocumentSnapshot after) {
  final a = before.text;
  final b = after.text;
  final common = a.length < b.length ? a.length : b.length;
  var prefix = 0;
  while (prefix < common && a.codeUnitAt(prefix) == b.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < common - prefix &&
      a.codeUnitAt(a.length - 1 - suffix) ==
          b.codeUnitAt(b.length - 1 - suffix)) {
    suffix++;
  }
  // Number of old lines whose start is strictly below [offset].
  int linesStartingBefore(int offset) {
    final starts = before.lineStarts;
    var low = 0;
    var high = starts.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (starts[mid] < offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  return (
    firstChangedLine: linesStartingBefore(prefix) + 1,
    firstShiftedLine: linesStartingBefore(a.length - suffix) + 1,
    delta: after.lineCount - before.lineCount,
  );
}

/// Indent/marker folding state for the painted editor, in the spirit of
/// Monaco's `FoldingModel` + `HiddenRangeModel` (not a port): regions come
/// from the ported [computeRanges], and collapsed state is reconciled with
/// the ported [FoldingRegions.sanitizeAndMerge] when regions are recomputed.
/// Between recomputations, edits shift regions by their line delta using
/// [computeLineShift]; a region whose header line started inside replaced
/// text is dropped (Monaco tracks regions with decorations instead).
class EditorFoldingModel {
  FoldingRegions _regions = FoldingRegions(Uint32List(0), Uint32List(0));
  HiddenLineRanges _hidden = HiddenLineRanges.none;
  DocumentSnapshot? _snapshot;
  bool _stale = true;

  FoldingRegions get regions => _regions;

  /// Model lines hidden by collapsed regions.
  HiddenLineRanges get hiddenLines => _hidden;

  /// Whether regions need [recompute] for the current snapshot.
  bool get isStale => _stale;

  bool get hasCollapsed => !_hidden.isEmpty;

  /// Tracks [snapshot]; returns true when hidden lines changed. With
  /// [shiftRegions] false (for a caller that recomputes right away and has
  /// nothing collapsed), the O(document) edit diff is skipped.
  bool updateSnapshot(DocumentSnapshot snapshot, {bool shiftRegions = true}) {
    final previous = _snapshot;
    if (identical(previous, snapshot)) return false;
    _snapshot = snapshot;
    _stale = true;
    if (previous == null || _regions.length == 0) return false;
    if (!shiftRegions && !hasCollapsed) return false;
    final shift = computeLineShift(previous, snapshot);
    if (shift.delta == 0 && shift.firstChangedLine == shift.firstShiftedLine) {
      return false; // edits within one line keep every region
    }
    final shifted = <FoldRange>[];
    for (var i = 0; i < _regions.length; i++) {
      final range = _regions.toFoldRange(i);
      final start = _shiftLine(range.startLineNumber, shift);
      if (start == null) continue;
      final end = _shiftLine(range.endLineNumber, shift, inChanged: true)!;
      if (end <= start || end > snapshot.lineCount) continue;
      range
        ..startLineNumber = start
        ..endLineNumber = end;
      shifted.add(range);
    }
    return _setRanges(
      FoldingRegions.sanitizeAndMerge(shifted, <FoldRange>[], null),
    );
  }

  static int? _shiftLine(int line, LineShift shift, {bool inChanged = false}) {
    if (line < shift.firstChangedLine) return line;
    if (line >= shift.firstShiftedLine) return line + shift.delta;
    if (!inChanged) return null;
    final shifted = line + shift.delta;
    return shifted < shift.firstChangedLine ? shift.firstChangedLine : shifted;
  }

  /// Recomputes regions for the tracked snapshot (O(document)); keeps
  /// collapsed regions that still exist (or are recovered), expanding those
  /// whose size changed while a selection starts inside them.
  bool recompute({
    required int tabSize,
    FoldingRules? rules,
    List<TextSelection> selections = const [],
  }) {
    final snapshot = _snapshot;
    if (snapshot == null) return false;
    _stale = false;
    final computed = computeRanges(
      _SnapshotLines(snapshot),
      rules?.offSide ?? false,
      markers: rules?.markers,
      tabSize: tabSize < 1 ? 1 : tabSize,
    );
    final collapsed = <FoldRange>[
      for (var i = 0; i < _regions.length; i++)
        if (_regions.isCollapsed(i)) _regions.toFoldRange(i),
    ];
    final selected = _SelectedLines([
      for (final selection in selections)
        if (selection.isValid)
          snapshot.positionAtOffset(selection.start).lineNumber,
    ]);
    return _setRanges(
      FoldingRegions.sanitizeAndMerge(
        computed,
        collapsed,
        snapshot.lineCount,
        selected,
      ),
    );
  }

  bool _setRanges(List<FoldRange> ranges) {
    _regions = FoldingRegions.fromFoldRanges(ranges);
    return _updateHidden();
  }

  bool _updateHidden() {
    final next = HiddenLineRanges([
      for (var i = 0; i < _regions.length; i++)
        if (_regions.isCollapsed(i))
          (_regions.getStartLineNumber(i) + 1, _regions.getEndLineNumber(i)),
    ]);
    if (next == _hidden) return false;
    _hidden = next;
    return true;
  }

  /// Index of the region whose header is [lineNumber], or -1.
  int regionAt(int lineNumber) {
    var low = 0;
    var high = _regions.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      final start = _regions.getStartLineNumber(mid);
      if (start == lineNumber) return mid;
      if (start < lineNumber) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return -1;
  }

  bool isCollapsedAt(int lineNumber) {
    final index = regionAt(lineNumber);
    return index >= 0 && _regions.isCollapsed(index);
  }

  /// Toggles the region headed by [lineNumber]; returns false if none.
  bool toggle(int lineNumber) {
    final index = regionAt(lineNumber);
    if (index < 0) return false;
    _regions.setCollapsed(index, !_regions.isCollapsed(index));
    _regions.setSource(index, FoldSource.userDefined);
    _updateHidden();
    return true;
  }

  /// Sets the collapsed state of the region headed by [lineNumber].
  bool setCollapsed(int lineNumber, bool collapsed) {
    final index = regionAt(lineNumber);
    if (index < 0 || _regions.isCollapsed(index) == collapsed) return false;
    _regions.setCollapsed(index, collapsed);
    return _updateHidden();
  }

  /// Expands every collapsed region that hides one of [lineNumbers], like
  /// Monaco revealing a cursor that moves into a folded range.
  bool reveal(Iterable<int> lineNumbers) {
    if (_hidden.isEmpty) return false;
    var changed = false;
    for (final line in lineNumbers) {
      if (!_hidden.isHidden(line)) continue;
      for (var i = 0; i < _regions.length; i++) {
        if (_regions.getStartLineNumber(i) >= line) break;
        if (_regions.isCollapsed(i) && _regions.toRegion(i).hidesLine(line)) {
          _regions.setCollapsed(i, false);
          changed = true;
        }
      }
    }
    return changed && _updateHidden();
  }

  /// Expands every region.
  bool unfoldAll() {
    for (var i = 0; i < _regions.length; i++) {
      _regions.setCollapsed(i, false);
    }
    return _updateHidden();
  }

  // The folding actions' helpers, ported from VS Code
  // src/vs/editor/contrib/folding/browser/foldingModel.ts at
  // 6a598d4a13031703d483d103c1d934a36ad27971 (`FoldingModel.
  // getAllRegionsAtLine`, `getRegionAtLine`, `getRegionsInside`,
  // `toggleCollapseState` and the `setCollapseState*` functions). Each
  // returns whether a region's state changed. Deviation: toggling does not
  // update decorations (the hidden lines are recomputed instead).

  /// The innermost region containing [lineNumber], then its ancestors, that
  /// pass [filter] (given the region's level, 1 for the innermost).
  List<FoldingRegion> _allRegionsAtLine(
    int lineNumber, [
    bool Function(FoldingRegion region, int level)? filter,
  ]) {
    final result = <FoldingRegion>[];
    var index = _regions.findRange(lineNumber);
    var level = 1;
    while (index >= 0) {
      final current = _regions.toRegion(index);
      if (filter == null || filter(current, level)) result.add(current);
      level++;
      index = current.parentIndex;
    }
    return result;
  }

  FoldingRegion? _regionAtLine(int lineNumber) {
    final index = _regions.findRange(lineNumber);
    return index >= 0 ? _regions.toRegion(index) : null;
  }

  /// The regions inside [region] (every region when null) that pass
  /// [filter], given their nesting level (1 for the outermost).
  List<FoldingRegion> _regionsInside(
    FoldingRegion? region,
    bool Function(FoldingRegion region, int level) filter,
  ) {
    final result = <FoldingRegion>[];
    final start = region == null ? 0 : region.regionIndex + 1;
    final endLineNumber = region?.endLineNumber;
    final levelStack = <FoldingRegion>[];
    for (var i = start; i < _regions.length; i++) {
      if (endLineNumber != null &&
          _regions.getStartLineNumber(i) >= endLineNumber) {
        break;
      }
      final current = _regions.toRegion(i);
      while (levelStack.isNotEmpty && !current.containedBy(levelStack.last)) {
        levelStack.removeLast();
      }
      levelStack.add(current);
      if (filter(current, levelStack.length)) result.add(current);
    }
    return result;
  }

  bool _toggleCollapseState(List<FoldingRegion> regions) {
    if (regions.isEmpty) return false;
    final indexes = {for (final region in regions) region.regionIndex};
    for (final index in indexes) {
      _regions.setCollapsed(index, !_regions.isCollapsed(index));
    }
    _updateHidden();
    return true;
  }

  /// Toggles the innermost region at each of [lineNumbers], and with
  /// [levels] > 1 the regions inside it (upstream `toggleCollapseState`).
  bool toggleCollapseState(int levels, List<int> lineNumbers) {
    final toToggle = <FoldingRegion>[];
    for (final lineNumber in lineNumbers) {
      final region = _regionAtLine(lineNumber);
      if (region == null) continue;
      final doCollapse = !region.isCollapsed;
      toToggle.add(region);
      if (levels > 1) {
        toToggle.addAll(
          _regionsInside(
            region,
            (r, level) => r.isCollapsed != doCollapse && level < levels,
          ),
        );
      }
    }
    return _toggleCollapseState(toToggle);
  }

  /// Collapses or expands the regions at [lineNumbers] (every region when
  /// null or empty) and [levels] - 1 levels of their children.
  bool setCollapseStateLevelsDown(
    bool doCollapse, {
    int levels = 1 << 30,
    List<int>? lineNumbers,
  }) {
    final toToggle = <FoldingRegion>[];
    if (lineNumbers != null && lineNumbers.isNotEmpty) {
      for (final lineNumber in lineNumbers) {
        final region = _regionAtLine(lineNumber);
        if (region == null) continue;
        if (region.isCollapsed != doCollapse) toToggle.add(region);
        if (levels > 1) {
          toToggle.addAll(
            _regionsInside(
              region,
              (r, level) => r.isCollapsed != doCollapse && level < levels,
            ),
          );
        }
      }
    } else {
      toToggle.addAll(
        _regionsInside(
          null,
          (r, level) => r.isCollapsed != doCollapse && level < levels,
        ),
      );
    }
    return _toggleCollapseState(toToggle);
  }

  /// Collapses or expands the regions at [lineNumbers] and [levels] - 1
  /// levels of their parents.
  bool setCollapseStateLevelsUp(
    bool doCollapse,
    int levels,
    List<int> lineNumbers,
  ) => _toggleCollapseState([
    for (final lineNumber in lineNumbers)
      ..._allRegionsAtLine(
        lineNumber,
        (region, level) => region.isCollapsed != doCollapse && level <= levels,
      ),
  ]);

  /// Collapses or expands the innermost region at each of [lineNumbers], or
  /// its first parent when that one already is.
  bool setCollapseStateUp(bool doCollapse, List<int> lineNumbers) =>
      _toggleCollapseState([
        for (final lineNumber in lineNumbers)
          ?_allRegionsAtLine(
            lineNumber,
            (region, _) => region.isCollapsed != doCollapse,
          ).firstOrNull,
      ]);

  /// Collapses or expands the regions of level [foldLevel] (1 is the top
  /// level) that contain none of [blockedLineNumbers].
  bool setCollapseStateAtLevel(
    int foldLevel,
    bool doCollapse,
    List<int> blockedLineNumbers,
  ) => _toggleCollapseState(
    _regionsInside(
      null,
      (region, level) =>
          level == foldLevel &&
          region.isCollapsed != doCollapse &&
          !blockedLineNumbers.any(region.containsLine),
    ),
  );

  /// Collapses or expands every region that neither contains nor is
  /// contained by the innermost region of one of [blockedLineNumbers].
  bool setCollapseStateForRest(bool doCollapse, List<int> blockedLineNumbers) {
    final blocked = [
      for (final lineNumber in blockedLineNumbers)
        ?_allRegionsAtLine(lineNumber).firstOrNull,
    ];
    return _toggleCollapseState(
      _regionsInside(
        null,
        (region, _) =>
            blocked.every(
              (b) => !b.containedBy(region) && !region.containedBy(b),
            ) &&
            region.isCollapsed != doCollapse,
      ),
    );
  }

  /// Collapses or expands the regions whose header line matches [regExp].
  bool setCollapseStateForMatchingLines(RegExp regExp, bool doCollapse) {
    final snapshot = _snapshot;
    if (snapshot == null) return false;
    final lines = _SnapshotLines(snapshot);
    return _toggleCollapseState([
      for (var i = _regions.length - 1; i >= 0; i--)
        if (doCollapse != _regions.isCollapsed(i) &&
            _regions.getStartLineNumber(i) <= snapshot.lineCount &&
            regExp.hasMatch(
              lines.getLineContent(_regions.getStartLineNumber(i)),
            ))
          _regions.toRegion(i),
    ]);
  }
}
