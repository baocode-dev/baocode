import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Where a pane goes beside another.
enum PaneSide { left, top, right, bottom }

/// Up to four conversations at once, in a strict 2×2 grid: one line down
/// the middle and one across, each pane on one cell or on two (a whole row
/// or column), so a line never stops against the middle of a pane.
///
/// The lines are shared: the column line is at the same place in both rows,
/// and the row line in both columns ([columnRatio], [rowRatio]).
class ChatGrid<T extends Object> {
  /// The pane on each cell, row by row: top left, top right, bottom left,
  /// bottom right. Empty with no pane at all.
  List<T> _cells = const [];

  static const maxPanes = 4;

  /// Where the column line is, as a share of the width; the row line, of
  /// the height. A line that appears starts in the middle.
  double columnRatio = .5;
  double rowRatio = .5;

  bool get isEmpty => _cells.isEmpty;

  /// The panes, top left first, row by row.
  List<T> get panes => {..._cells}.toList();
  int get length => panes.length;

  bool contains(T pane) => _cells.contains(pane);

  /// The pane on each cell, row by row (see [at]); empty with none.
  List<T> get cells => List.unmodifiable(_cells);

  /// Has the panes on [cells] again (as [cells] gave them), when they make
  /// a grid: four cells, each pane's a rectangle. Whether they did.
  bool restore(List<T> cells) {
    if (cells.length != 4) return false;
    for (final pane in cells.toSet()) {
      final own = {
        for (final (cell, shown) in cells.indexed)
          if (shown == pane) cell,
      };
      if (!_isRectangle(own)) return false;
    }
    _cells = [...cells];
    return true;
  }

  /// The pane on [cell] (0 top left, 1 top right, 2 bottom left, 3 bottom
  /// right); null with no pane.
  T? at(int cell) => _cells.elementAtOrNull(cell);

  /// Whether the column line runs through [row] (0 the top one): the cells
  /// either side of it have different panes.
  bool columnLineIn(int row) =>
      _cells.isNotEmpty && _cells[row * 2] != _cells[row * 2 + 1];

  /// Whether the row line runs through [column] (0 the left one).
  bool rowLineIn(int column) =>
      _cells.isNotEmpty && _cells[column] != _cells[column + 2];

  bool get columnsSplit => columnLineIn(0) || columnLineIn(1);
  bool get rowsSplit => rowLineIn(0) || rowLineIn(1);

  Set<int> _cellsOf(T pane) => {
    for (final (cell, shown) in _cells.indexed)
      if (shown == pane) cell,
  };

  /// Whether [pane] has a cell on its [side] of the grid: it touches that
  /// edge.
  bool touches(T pane, PaneSide side) =>
      _cellsOf(pane).any((cell) => _onSide(cell, side));

  static bool _onSide(int cell, PaneSide side) => switch (side) {
    PaneSide.left => cell.isEven,
    PaneSide.right => cell.isOdd,
    PaneSide.top => cell < 2,
    PaneSide.bottom => cell >= 2,
  };

  /// [pane] alone, on the whole grid.
  void show(T pane) {
    _cells = List.filled(4, pane);
  }

  void clear() {
    _cells = const [];
  }

  /// Whether [pane] can give another the half of it on [side]: it has two
  /// cells across that way (both columns for left and right, both rows for
  /// top and bottom). None can once there are four.
  bool canSplit(T pane, PaneSide side) {
    final cells = _cellsOf(pane);
    return switch (side) {
      PaneSide.left || PaneSide.right =>
        cells.any((cell) => cell.isEven) && cells.any((cell) => cell.isOdd),
      PaneSide.top || PaneSide.bottom =>
        cells.any((cell) => cell < 2) && cells.any((cell) => cell >= 2),
    };
  }

  /// Gives [added] the half of [target] on its [side] (see [canSplit]).
  void split(T target, PaneSide side, T added) {
    assert(canSplit(target, side) && !contains(added));
    final columns = columnsSplit;
    final rows = rowsSplit;
    _cells = [
      for (final (cell, pane) in _cells.indexed)
        pane == target && _onSide(cell, side) ? added : pane,
    ];
    if (!columns && columnsSplit) columnRatio = .5;
    if (!rows && rowsSplit) rowRatio = .5;
  }

  /// Shows [pane] where [old] was.
  void replace(T old, T pane) {
    assert(!contains(pane));
    _cells = [for (final shown in _cells) shown == old ? pane : shown];
  }

  /// Takes [pane] out: a pane beside it takes its cells, the one above or
  /// below first. Where no one pane can (it had a whole row or column, the
  /// other half split), each cell goes to the pane across from it. Returns
  /// the pane now on its first cell; null when it was the last.
  T? remove(T pane) {
    final gone = _cellsOf(pane);
    if (gone.isEmpty) return null;
    if (gone.length == 4) {
      clear();
      return null;
    }
    final neighbors = [
      for (final cell in gone) _cells[cell ^ 2],
      for (final cell in gone) _cells[cell ^ 1],
    ].where((other) => other != pane);
    final heir = neighbors
        .where((other) => _isRectangle({..._cellsOf(other), ...gone}))
        .firstOrNull;
    // Down a column the cells go across; along a row, up or down.
    final column = gone.every((cell) => cell.isEven == gone.first.isEven);
    _cells = [
      for (final (cell, shown) in _cells.indexed)
        shown != pane ? shown : heir ?? _cells[column ? cell ^ 1 : cell ^ 2],
    ];
    return _cells[gone.reduce(math.min)];
  }

  static bool _isRectangle(Set<int> cells) {
    final rows = {for (final cell in cells) cell ~/ 2};
    final columns = {for (final cell in cells) cell % 2};
    return cells.length == rows.length * columns.length;
  }

  /// A grid the same as this one, to change without changing it.
  ChatGrid<T> copy() => ChatGrid<T>()
    .._cells = [..._cells]
    ..columnRatio = columnRatio
    ..rowRatio = rowRatio;

  /// Where the column line is in [width]: at [columnRatio], but leaving
  /// each column [minPane] wide where there is room for both (in the middle
  /// where there is not).
  static double line(
    double ratio,
    double extent, {
    required double gap,
    required double minPane,
  }) {
    final least = minPane + gap / 2;
    final most = extent - least;
    return least <= most ? (ratio * extent).clamp(least, most) : extent / 2;
  }

  /// Each pane's rectangle in [size], [gap] between them, the lines kept
  /// where the panes either side have [minPane] of room (see [line]).
  Map<T, Rect> layout(
    Size size, {
    required double gap,
    Size minPane = Size.zero,
  }) {
    final x = line(columnRatio, size.width, gap: gap, minPane: minPane.width);
    final y = line(rowRatio, size.height, gap: gap, minPane: minPane.height);
    final columns = columnsSplit
        ? [(0.0, x - gap / 2), (x + gap / 2, size.width)]
        : [(0.0, size.width), (0.0, size.width)];
    final rows = rowsSplit
        ? [(0.0, y - gap / 2), (y + gap / 2, size.height)]
        : [(0.0, size.height), (0.0, size.height)];
    final rects = <T, Rect>{};
    for (final (cell, pane) in _cells.indexed) {
      final (left, right) = columns[cell % 2];
      final (top, bottom) = rows[cell ~/ 2];
      final rect = Rect.fromLTRB(left, top, right, bottom);
      rects[pane] = rects[pane]?.expandToInclude(rect) ?? rect;
    }
    return rects;
  }
}
