import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Where a pane goes beside another.
enum PaneSide { left, top, right, bottom }

/// Up to four conversations at once, in a strict 2×2 grid: one line down
/// the middle and one across, each pane on one cell or on two (a whole row
/// or column), so a line never stops against the middle of a pane.
///
/// One line runs straight through the grid ([columnsFirst]: the column
/// line); the other is in two parts, one each side of it, each moving on its
/// own: the panes of one column are sized apart from the other's.
class ChatGrid<T extends Object> {
  /// The pane on each cell, row by row: top left, top right, bottom left,
  /// bottom right. Empty with no pane at all.
  List<T> _cells = const [];

  static const maxPanes = 4;

  /// Where the column line is in each row, as a share of the width; the
  /// row line in each column, of the height. A line that appears starts in
  /// the middle; a straight one is at its first.
  List<double> _columnRatios = [.5, .5];
  List<double> _rowRatios = [.5, .5];

  /// With four panes, whether the column line is the straight one: as it
  /// was before the fourth came.
  bool _columnsFirst = true;

  List<double> get columnRatios => List.unmodifiable(_columnRatios);
  set columnRatios(List<double> ratios) {
    assert(ratios.length == 2);
    _columnRatios = [...ratios];
  }

  List<double> get rowRatios => List.unmodifiable(_rowRatios);
  set rowRatios(List<double> ratios) {
    assert(ratios.length == 2);
    _rowRatios = [...ratios];
  }

  /// Whether the column line runs straight through both rows, and the row
  /// line is in a part for each column: where a pane has a whole column;
  /// a whole row, the other way; with four, as they were.
  bool get columnsFirst {
    if (_cells.isEmpty) return _columnsFirst;
    final column = _cells[0] == _cells[2] || _cells[1] == _cells[3];
    final row = _cells[0] == _cells[1] || _cells[2] == _cells[3];
    return column == row ? _columnsFirst : column;
  }

  set columnsFirst(bool value) => _columnsFirst = value;

  /// Where the column line is in [row]: the straight line's, the same in
  /// both.
  double columnRatioIn(int row) => _columnRatios[columnsFirst ? 0 : row];
  double rowRatioIn(int column) => _rowRatios[columnsFirst ? column : 0];

  /// Moves the column line in [row]; the straight one, in both.
  void setColumnRatioIn(int row, double ratio) {
    if (columnsFirst) {
      _columnRatios = [ratio, ratio];
    } else {
      _columnRatios[row] = ratio;
    }
  }

  void setRowRatioIn(int column, double ratio) {
    if (columnsFirst) {
      _rowRatios[column] = ratio;
    } else {
      _rowRatios = [ratio, ratio];
    }
  }

  /// Changes the cells with [change], the lines kept where they were: a
  /// part that appears in the middle, or where the other part of its line
  /// is, the line now straight.
  void _keepLines(void Function() change) {
    final columnsIn = [columnLineIn(0), columnLineIn(1)];
    final rowsIn = [rowLineIn(0), rowLineIn(1)];
    _columnsFirst = columnsFirst;
    change();
    _columnRatios = _kept(_columnRatios, columnsIn, straight: columnsFirst);
    _rowRatios = _kept(_rowRatios, rowsIn, straight: !columnsFirst);
  }

  static List<double> _kept(
    List<double> ratios,
    List<bool> were, {
    required bool straight,
  }) {
    final any = were[0]
        ? ratios[0]
        : were[1]
        ? ratios[1]
        : .5;
    if (straight) return [any, any];
    return [for (var i = 0; i < 2; i++) were[i] ? ratios[i] : any];
  }

  bool get isEmpty => _cells.isEmpty;

  /// Under each pane, the ones it covered (see [cover]), the last covered
  /// last: closed, it shows the last of them again ([uncover]). They are
  /// not built while covered.
  Map<T, List<T>> _under = {};

  /// The panes [pane] covers, the next to show again last.
  List<T> under(T pane) => List.unmodifiable(_under[pane] ?? const []);

  /// When each pane came to the slot it is in, for [tabs]' order: shown
  /// again from under another, it keeps its place.
  final Map<T, int> _opened = {};
  int _openings = 0;

  void _open(T pane) => _opened[pane] = _openings++;

  /// [pane] and those it covers, as tabs: in the order they came to its
  /// slot, whichever shows.
  List<T> tabs(T pane) {
    if (!contains(pane)) return const [];
    return [...?_under[pane], pane]
      ..sort((a, b) => (_opened[a] ?? -1).compareTo(_opened[b] ?? -1));
  }

  /// The pane beside [pane] on its [side]: the first along that edge (the
  /// upper or left one); null at the grid's edge.
  T? neighbor(T pane, PaneSide side) {
    for (final cell in _cellsOf(pane).toList()..sort()) {
      final next = switch (side) {
        PaneSide.left => cell.isOdd ? cell - 1 : null,
        PaneSide.right => cell.isEven ? cell + 1 : null,
        PaneSide.top => cell >= 2 ? cell - 2 : null,
        PaneSide.bottom => cell < 2 ? cell + 2 : null,
      };
      if (next != null && _cells[next] != pane) return _cells[next];
    }
    return null;
  }

  /// Whether [pane] is covered by another: not shown, kept to show again.
  bool isCovered(T pane) => _under.values.any((under) => under.contains(pane));

  /// [pane] no longer under any other: shown elsewhere, or gone.
  void forget(T pane) {
    for (final under in _under.values) {
      under.remove(pane);
    }
    _under.removeWhere((_, under) => under.isEmpty);
  }

  /// [covered], under [pane], shown in its place over it: [pane] goes on top
  /// of the rest under it.
  void raise(T pane, T covered) {
    final under = _under.remove(pane);
    if (under == null || !under.remove(covered) || !contains(pane)) {
      if (under != null) _under[pane] = under;
      return;
    }
    _cells = [for (final cell in _cells) cell == pane ? covered : cell];
    _under[covered] = [...under, pane];
  }

  /// Shows [pane] over [old], in its place: [old] and those it covered under
  /// it, to show again once [pane] closes; the [maxUnder] last covered.
  void cover(T old, T pane) {
    assert(contains(old) && !contains(pane));
    forget(pane);
    final under = [...?_under.remove(old), old];
    if (under.length > maxUnder) under.removeRange(0, under.length - maxUnder);
    _open(pane);
    _cells = [for (final shown in _cells) shown == old ? pane : shown];
    _under[pane] = under;
  }

  static const maxUnder = 8;

  /// [pane] closed where it covers another: the last it covered shows in its
  /// place again, over the rest. Null, nothing changed, where it covers none.
  T? uncover(T pane) {
    final under = _under.remove(pane);
    if (under == null || under.isEmpty || !contains(pane)) return null;
    final shown = under.removeLast();
    _cells = [for (final cell in _cells) cell == pane ? shown : cell];
    if (under.isNotEmpty) _under[shown] = under;
    return shown;
  }

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
    _under = {};
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
    _under = {};
    _open(pane);
  }

  void clear() {
    _cells = const [];
    _under = {};
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
    forget(added);
    _open(added);
    _keepLines(
      () => _cells = [
        for (final (cell, pane) in _cells.indexed)
          pane == target && _onSide(cell, side) ? added : pane,
      ],
    );
  }

  /// Moves [pane] beside [target] on [side], or swaps their places when
  /// [side] is null. Nothing changes where removing [pane] leaves [target]
  /// too small to split, or either pane is gone.
  bool rearrange(T pane, T target, {PaneSide? side}) {
    if (pane == target || !contains(pane) || !contains(target)) return false;
    if (side == null) {
      _cells = [
        for (final shown in _cells)
          shown == pane
              ? target
              : shown == target
              ? pane
              : shown,
      ];
      return true;
    }
    final next = copy()..remove(pane);
    if (!next.canSplit(target, side)) return false;
    next.split(target, side, pane);
    // What it covered goes with it, its tab where it was.
    if (_under[pane] case final under?) next._under[pane] = under;
    if (_opened[pane] case final opened?) next._opened[pane] = opened;
    _cells = next._cells;
    _under = next._under;
    _opened
      ..clear()
      ..addAll(next._opened);
    _openings = next._openings;
    _columnRatios = next._columnRatios;
    _rowRatios = next._rowRatios;
    _columnsFirst = next._columnsFirst;
    return true;
  }

  /// Shows [pane] where [old] was, over what [old] covered.
  void replace(T old, T pane) {
    assert(!contains(pane));
    forget(pane);
    _opened[pane] = _opened[old] ?? _openings++;
    _cells = [for (final shown in _cells) shown == old ? pane : shown];
    if (_under.remove(old) case final under?) _under[pane] = under;
  }

  /// Takes [pane] out, and those it covered with it: a pane beside it takes
  /// its cells, the one across the
  /// straight line first (see [columnsFirst]: above or below where it is the
  /// column line). Where no one pane can (it had a whole row or column, the
  /// other half split), each cell goes to the pane across from it. Returns
  /// the pane now on its first cell; null when it was the last.
  T? remove(T pane) {
    final gone = _cellsOf(pane);
    if (gone.isEmpty) return null;
    if (gone.length == 4) {
      clear();
      return null;
    }
    _under.remove(pane);
    // Across the straight line first: it stays straight, and the other's
    // parts where they were.
    final first = columnsFirst ? 2 : 1;
    final neighbors = [
      for (final cell in gone) _cells[cell ^ first],
      for (final cell in gone) _cells[cell ^ (3 - first)],
    ].where((other) => other != pane);
    final heir = neighbors
        .where((other) => _isRectangle({..._cellsOf(other), ...gone}))
        .firstOrNull;
    // Down a column the cells go across; along a row, up or down.
    final column = gone.every((cell) => cell.isEven == gone.first.isEven);
    _keepLines(
      () => _cells = [
        for (final (cell, shown) in _cells.indexed)
          shown != pane ? shown : heir ?? _cells[column ? cell ^ 1 : cell ^ 2],
      ],
    );
    // Alone, a pane shows another in its place, not over it (see [cover]).
    if (length == 1) _under = {};
    return _cells[gone.reduce(math.min)];
  }

  static bool _isRectangle(Set<int> cells) {
    final rows = {for (final cell in cells) cell ~/ 2};
    final columns = {for (final cell in cells) cell % 2};
    return cells.length == rows.length * columns.length;
  }

  /// A grid the same as this one, to change without changing it.
  ChatGrid<T> copy() => ChatGrid<T>()
    .._opened.addAll(_opened)
    .._openings = _openings
    .._cells = [..._cells]
    .._under = {
      for (final MapEntry(:key, :value) in _under.entries) key: [...value],
    }
    .._columnRatios = [..._columnRatios]
    .._rowRatios = [..._rowRatios]
    .._columnsFirst = _columnsFirst;

  /// Where a line is in [extent]: at [ratio], but leaving each side
  /// [minPane] where there is room for both (in the middle where there is
  /// not).
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

  /// Where the column line is in each row, and the row line in each
  /// column, in [size] (see [line]).
  ({List<double> xs, List<double> ys}) lines(
    Size size, {
    required double gap,
    Size minPane = Size.zero,
  }) => (
    xs: [
      for (var row = 0; row < 2; row++)
        line(columnRatioIn(row), size.width, gap: gap, minPane: minPane.width),
    ],
    ys: [
      for (var column = 0; column < 2; column++)
        line(
          rowRatioIn(column),
          size.height,
          gap: gap,
          minPane: minPane.height,
        ),
    ],
  );

  /// Each pane's rectangle in [size], [gap] between them, the lines kept
  /// where the panes either side have [minPane] of room (see [line]).
  Map<T, Rect> layout(
    Size size, {
    required double gap,
    Size minPane = Size.zero,
  }) {
    final (:xs, :ys) = lines(size, gap: gap, minPane: minPane);
    final columns = columnsSplit;
    final rows = rowsSplit;
    final rects = <T, Rect>{};
    for (final (cell, pane) in _cells.indexed) {
      final column = cell % 2, row = cell ~/ 2;
      final x = xs[row], y = ys[column];
      final (left, right) = !columns
          ? (0.0, size.width)
          : column == 0
          ? (0.0, x - gap / 2)
          : (x + gap / 2, size.width);
      final (top, bottom) = !rows
          ? (0.0, size.height)
          : row == 0
          ? (0.0, y - gap / 2)
          : (y + gap / 2, size.height);
      final rect = Rect.fromLTRB(left, top, right, bottom);
      rects[pane] = rects[pane]?.expandToInclude(rect) ?? rect;
    }
    return rects;
  }
}
