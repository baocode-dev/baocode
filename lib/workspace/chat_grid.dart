import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Where a pane goes beside another.
enum PaneSide { left, top, right, bottom }

extension on PaneSide {
  /// Left or right: beside it across.
  bool get across => this == PaneSide.left || this == PaneSide.right;

  /// Right or below: after it.
  bool get after => this == PaneSide.right || this == PaneSide.bottom;
}

/// A line between panes (see [ChatGrid.lines]): one of those between the
/// groups ([group] null), or one within [group]; [index] its place among
/// them, the first the top or left one.
typedef GridLine = ({int? group, int index});

/// The conversations shown at once: up to four columns, of up to two panes
/// each; or up to two rows, of up to four. The lines one way run straight
/// through the grid ([columnsFirst]: the column lines), between the groups
/// (the columns, or the rows); the panes of each group are sized apart from
/// the other groups', so a line never stops against the middle of a pane.
class ChatGrid<T extends Object> {
  /// The panes, in their groups: each column top to bottom, left to right
  /// ([columnsFirst]); or each row left to right, top to bottom. Empty with
  /// no pane at all; one group of one with one. Never one group of several:
  /// those are each a group of their own, the other way.
  List<List<T>> _groups = [];

  /// Whether the groups are columns.
  bool _columnsFirst = true;

  static const maxColumns = 4;
  static const maxRows = 2;
  static const maxPanes = maxColumns * maxRows;

  /// Where each line between the groups is, as a share of the grid's width
  /// (or, the groups rows, its height), the first the left (or top) one.
  /// A line that appears starts in the middle of the one it splits.
  List<double> _lines = [];

  /// Each group's lines between its panes, as a share of the grid's height
  /// (or width).
  List<List<double>> _inner = [];

  /// Whether the column lines run straight through the grid, and the row
  /// lines are in a part for each column; else the row line runs straight,
  /// and the column lines are in a part for each row.
  bool get columnsFirst => _columnsFirst;

  /// The panes in their groups (see [columnsFirst]).
  List<List<T>> get groups => [
    for (final group in _groups) List.unmodifiable(group),
  ];

  bool get isEmpty => _groups.isEmpty;

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
    // On a grid of no gap, the panes either side of a line meet on it.
    final rects = layout(const Size(1, 1), gap: 0);
    final rect = rects[pane];
    if (rect == null) return null;
    T? nearest;
    Rect? nearestRect;
    for (final MapEntry(key: other, value: r) in rects.entries) {
      if (other == pane) continue;
      final down = r.left < rect.right && r.right > rect.left;
      final along = r.top < rect.bottom && r.bottom > rect.top;
      final beside = switch (side) {
        PaneSide.left => r.right == rect.left && along,
        PaneSide.right => r.left == rect.right && along,
        PaneSide.top => r.bottom == rect.top && down,
        PaneSide.bottom => r.top == rect.bottom && down,
      };
      if (!beside) continue;
      if (nearestRect == null ||
          (side.across ? r.top < nearestRect.top : r.left < nearestRect.left)) {
        nearest = other;
        nearestRect = r;
      }
    }
    return nearest;
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

  /// [pane] in [old]'s place.
  void _swap(T old, T pane) => _groups = [
    for (final group in _groups)
      [for (final shown in group) shown == old ? pane : shown],
  ];

  /// [covered], under [pane], shown in its place over it: [pane] goes on top
  /// of the rest under it.
  void raise(T pane, T covered) {
    final under = _under.remove(pane);
    if (under == null || !under.remove(covered) || !contains(pane)) {
      if (under != null) _under[pane] = under;
      return;
    }
    _swap(pane, covered);
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
    _swap(old, pane);
    _under[pane] = under;
  }

  static const maxUnder = 8;

  /// [pane] closed where it covers another: the last it covered shows in its
  /// place again, over the rest. Null, nothing changed, where it covers none.
  T? uncover(T pane) {
    final under = _under.remove(pane);
    if (under == null || under.isEmpty || !contains(pane)) return null;
    final shown = under.removeLast();
    _swap(pane, shown);
    if (under.isNotEmpty) _under[shown] = under;
    return shown;
  }

  /// The panes, row by row: in columns, the top ones left to right first.
  List<T> get panes => _columnsFirst
      ? [
          for (var row = 0; row < maxRows; row++)
            for (final group in _groups) ?group.elementAtOrNull(row),
        ]
      : [for (final group in _groups) ...group];

  int get length => _groups.fold(0, (sum, group) => sum + group.length);

  bool contains(T pane) => _groups.any((group) => group.contains(pane));

  /// The pane at the grid's top left corner, and at its top right; null with
  /// none.
  T? get topLeft => _groups.firstOrNull?.first;
  T? get topRight =>
      _columnsFirst ? _groups.lastOrNull?.first : _groups.firstOrNull?.last;

  /// [pane]'s group, and its place in it; -1 for both where it has none.
  (int, int) _find(T pane) {
    for (final (group, panes) in _groups.indexed) {
      final index = panes.indexOf(pane);
      if (index >= 0) return (group, index);
    }
    return (-1, -1);
  }

  /// Whether [side] is a side across the groups: a column's left or right,
  /// a row's top or bottom.
  bool _outer(PaneSide side) => side.across == _columnsFirst;

  /// Whether [pane] is at its [side] of the grid: it touches that edge.
  bool touches(T pane, PaneSide side) {
    final (group, index) = _find(pane);
    if (group < 0) return false;
    final (at, count) = _outer(side)
        ? (group, _groups.length)
        : (index, _groups[group].length);
    return side.after ? at == count - 1 : at == 0;
  }

  /// Whether two panes are side by side somewhere: a column line.
  bool get columnsSplit => _columnsFirst
      ? _groups.length > 1
      : _groups.any((group) => group.length > 1);

  /// Whether two panes are one above the other somewhere: a row line.
  bool get rowsSplit => _columnsFirst
      ? _groups.any((group) => group.length > 1)
      : _groups.length > 1;

  /// [pane] alone, on the whole grid.
  void show(T pane) {
    _groups = [
      [pane],
    ];
    _lines = [];
    _inner = [[]];
    _under = {};
    _open(pane);
  }

  void clear() {
    _groups = [];
    _lines = [];
    _inner = [];
    _under = {};
  }

  /// Whether another can go beside [pane] on [side]: across the groups, the
  /// grid has room for another group (a column, or a row); along its group,
  /// the group room for another pane.
  bool canSplit(T pane, PaneSide side) {
    final (group, _) = _find(pane);
    if (group < 0 || length >= maxPanes) return false;
    if (_outer(side)) {
      return _groups.length < (_columnsFirst ? maxColumns : maxRows);
    }
    return _groups[group].length < (_columnsFirst ? maxRows : maxColumns);
  }

  /// Gives [added] a place beside [target] on its [side] (see [canSplit]):
  /// along its group, half of [target]; across, a group of its own, half of
  /// [target]'s (a whole column, or row).
  void split(T target, PaneSide side, T added) {
    assert(canSplit(target, side) && !contains(added));
    forget(added);
    _open(added);
    final (group, index) = _find(target);
    final at = side.after ? 1 : 0;
    if (_outer(side)) {
      _lines.insert(group, _middle(_lines, group));
      _groups.insert(group + at, [added]);
      _inner.insert(group + at, []);
    } else {
      _inner[group].insert(index, _middle(_inner[group], index));
      _groups[group].insert(index + at, added);
    }
    _normalize();
  }

  /// The middle of the [index]th of the parts [lines] make.
  static double _middle(List<double> lines, int index) =>
      ((index == 0 ? 0.0 : lines[index - 1]) +
          (index == lines.length ? 1.0 : lines[index])) /
      2;

  /// One group of several made a group of each, the other way: one column
  /// is rows of one pane; one row, columns.
  void _normalize() {
    if (_groups.length != 1 || _groups.single.length < 2) return;
    _lines = _inner.single;
    _groups = [
      for (final pane in _groups.single) [pane],
    ];
    _inner = [for (final _ in _groups) []];
    _columnsFirst = !_columnsFirst;
  }

  /// Moves [pane] beside [target] on [side], or swaps their places when
  /// [side] is null. Nothing changes where the grid has no room for it
  /// there once [pane] is gone from its place, or either pane is gone.
  bool rearrange(T pane, T target, {PaneSide? side}) {
    if (pane == target || !contains(pane) || !contains(target)) return false;
    if (side == null) {
      _groups = [
        for (final group in _groups)
          [
            for (final shown in group)
              shown == pane
                  ? target
                  : shown == target
                  ? pane
                  : shown,
          ],
      ];
      return true;
    }
    final next = copy()..remove(pane);
    if (!next.canSplit(target, side)) return false;
    next.split(target, side, pane);
    // What it covered goes with it, its tab where it was.
    if (_under[pane] case final under?) next._under[pane] = under;
    if (_opened[pane] case final opened?) next._opened[pane] = opened;
    _groups = next._groups;
    _under = next._under;
    _opened
      ..clear()
      ..addAll(next._opened);
    _openings = next._openings;
    _lines = next._lines;
    _inner = next._inner;
    _columnsFirst = next._columnsFirst;
    return true;
  }

  /// Shows [pane] where [old] was, over what [old] covered.
  void replace(T old, T pane) {
    assert(!contains(pane));
    forget(pane);
    _opened[pane] = _opened[old] ?? _openings++;
    _swap(old, pane);
    if (_under.remove(old) case final under?) _under[pane] = under;
  }

  /// Takes [pane] out, and those it covered with it: the pane before it in
  /// its group takes its place (above it, or left of it), else the one after;
  /// the last of its group, the group before (or after) takes the group's.
  /// Returns the pane that took its place; null when it was the last.
  T? remove(T pane) {
    final (group, index) = _find(pane);
    if (group < 0) return null;
    _under.remove(pane);
    if (length == 1) {
      clear();
      return null;
    }
    final T heir;
    if (_groups[group].length > 1) {
      _groups[group].removeAt(index);
      _inner[group].removeAt(math.max(0, index - 1));
      heir = _groups[group][math.max(0, index - 1)];
    } else {
      _groups.removeAt(group);
      _inner.removeAt(group);
      _lines.removeAt(math.max(0, group - 1));
      heir = _groups[math.max(0, group - 1)].first;
    }
    _normalize();
    // Alone, a pane shows another in its place, not over it (see [cover]).
    if (length == 1) _under = {};
    return heir;
  }

  /// A grid the same as this one, to change without changing it.
  ChatGrid<T> copy() => ChatGrid<T>()
    .._opened.addAll(_opened)
    .._openings = _openings
    .._groups = [
      for (final group in _groups) [...group],
    ]
    .._under = {
      for (final MapEntry(:key, :value) in _under.entries) key: [...value],
    }
    .._lines = [..._lines]
    .._inner = [
      for (final lines in _inner) [...lines],
    ]
    .._columnsFirst = _columnsFirst;

  /// The layout of [other], each of its panes as [pane] gives it: none
  /// covered.
  void adopt<U extends Object>(ChatGrid<U> other, T Function(U pane) pane) {
    _groups = [
      for (final group in other._groups)
        [for (final shown in group) pane(shown)],
    ];
    _columnsFirst = other._columnsFirst;
    _lines = [...other._lines];
    _inner = [
      for (final lines in other._inner) [...lines],
    ];
    _under = {};
  }

  /// [pane]'s tabs again, as [tabs] and [under] gave them: those of [under]
  /// under it in that order, the tabs in [tabs]' order. Those shown or
  /// under another already are left out.
  void restoreTabs(T pane, List<T> tabs, List<T> under) {
    if (!contains(pane)) return;
    final taken = {...panes, ..._under.values.expand((under) => under)};
    final kept = {
      for (final covered in under)
        if (!taken.contains(covered)) covered,
    }.toList();
    if (kept.length > maxUnder) kept.removeRange(0, kept.length - maxUnder);
    if (kept.isNotEmpty) _under[pane] = kept;
    final slot = {pane, ...kept};
    for (final tab in {...tabs.where(slot.contains), ...slot}) {
      _open(tab);
    }
  }

  /// The layout as [fromJson] takes it again, each pane as [id] gives it.
  Map<String, Object?> toJson(Object? Function(T pane) id) => {
    'columnsFirst': _columnsFirst,
    'groups': [
      for (final group in _groups) [for (final pane in group) id(pane)],
    ],
    'lines': _lines,
    'innerLines': _inner,
  };

  /// The layout [json] keeps (see [toJson]), each pane by its number; or,
  /// kept by an earlier run, the 2×2 grid's cells and lines. Null where it
  /// makes no grid.
  static ChatGrid<int>? fromJson(Map<Object?, Object?> json) {
    final columnsFirst = json['columnsFirst'] != false;
    if (json['groups'] case final List<Object?> groups) {
      final kept = [
        for (final group in groups)
          if (group is List<Object?> && group.every((pane) => pane is int))
            group.cast<int>()
          else
            null,
      ];
      if (kept.contains(null)) return null;
      final inner = switch (json['innerLines']) {
        final List<Object?> lines => lines,
        _ => const <Object?>[],
      };
      return _restored(
        [for (final group in kept) group!],
        columnsFirst: columnsFirst,
        lines: json['lines'],
        inner: [for (var i = 0; i < kept.length; i++) inner.elementAtOrNull(i)],
      );
    }
    if (json['cells'] case [
      final int a,
      final int b,
      final int c,
      final int d,
    ]) {
      return _fromCells([a, b, c, d], columnsFirst: columnsFirst, json: json);
    }
    return null;
  }

  /// A 2×2 grid's cells (top left, top right, bottom left, bottom right),
  /// each pane's a rectangle, and its lines: the column line's share of the
  /// width in each row, the row line's of the height in each column.
  static ChatGrid<int>? _fromCells(
    List<int> cells, {
    required bool columnsFirst,
    required Map<Object?, Object?> json,
  }) {
    for (final pane in cells.toSet()) {
      final own = {
        for (final (cell, shown) in cells.indexed)
          if (shown == pane) cell,
      };
      final rows = {for (final cell in own) cell ~/ 2};
      final columns = {for (final cell in own) cell % 2};
      if (own.length != rows.length * columns.length) return null;
    }
    final columnRatios = _keptRatios(json, 'columnRatio');
    final rowRatios = _keptRatios(json, 'rowRatio');
    if (cells.toSet().length == 1) {
      return ChatGrid<int>()..show(cells.first);
    }
    final column = cells[0] == cells[2] || cells[1] == cells[3];
    final row = cells[0] == cells[1] || cells[2] == cells[3];
    final columns = column == row ? columnsFirst : column;
    // Each group's two cells: a column's, or a row's.
    List<int> group(int first, int second) => [
      cells[first],
      if (cells[second] != cells[first]) cells[second],
    ];
    final groups = columns
        ? [group(0, 2), group(1, 3)]
        : [group(0, 1), group(2, 3)];
    final (straight, parts) = columns
        ? (columnRatios, rowRatios)
        : (rowRatios, columnRatios);
    return _restored(
      groups,
      columnsFirst: columns,
      lines: [straight[0]],
      inner: [
        for (final (i, group) in groups.indexed)
          [if (group.length > 1) parts[i]],
      ],
    );
  }

  /// A line's ratios as an earlier run kept them under [name]`s`, one for
  /// each of its parts; or its one ratio under [name], for both; else in
  /// the middle.
  static List<double> _keptRatios(Map<Object?, Object?> kept, String name) {
    bool valid(Object? ratio) => ratio is num && ratio > 0 && ratio < 1;
    if (kept['${name}s'] case [final a, final b] when valid(a) && valid(b)) {
      return [(a as num).toDouble(), (b as num).toDouble()];
    }
    if (kept[name] case final num ratio when valid(ratio)) {
      return [ratio.toDouble(), ratio.toDouble()];
    }
    return [.5, .5];
  }

  /// A grid of [groups], where they make one: each pane in one place, no
  /// more groups or panes in a group than there is room for. Lines not
  /// given, or out of order, evenly apart.
  static ChatGrid<int>? _restored(
    List<List<int>> groups, {
    required bool columnsFirst,
    required Object? lines,
    required List<Object?> inner,
  }) {
    final all = [for (final group in groups) ...group];
    if (groups.isEmpty ||
        groups.any((group) => group.isEmpty) ||
        all.toSet().length != all.length ||
        groups.length > (columnsFirst ? maxColumns : maxRows) ||
        groups.any(
          (group) => group.length > (columnsFirst ? maxRows : maxColumns),
        )) {
      return null;
    }
    return ChatGrid<int>()
      .._groups = [
        for (final group in groups) [...group],
      ]
      .._columnsFirst = columnsFirst
      .._lines = _ratios(lines, groups.length - 1)
      .._inner = [
        for (final (i, group) in groups.indexed)
          _ratios(inner[i], group.length - 1),
      ]
      .._normalize();
  }

  /// [kept]'s [count] lines, each a share between 0 and 1, in order; else
  /// [count] evenly apart.
  static List<double> _ratios(Object? kept, int count) {
    if (kept is List<Object?> &&
        kept.length == count &&
        kept.every((ratio) => ratio is num && ratio > 0 && ratio < 1)) {
      final ratios = [for (final ratio in kept) (ratio as num).toDouble()];
      var ordered = true;
      for (var i = 1; i < count; i++) {
        if (ratios[i] <= ratios[i - 1]) ordered = false;
      }
      if (ordered) return ratios;
    }
    return [for (var i = 1; i <= count; i++) i / (count + 1)];
  }

  /// Every line: those between the groups first, then each group's.
  List<GridLine> get lines => [
    for (var index = 0; index < _lines.length; index++)
      (group: null, index: index),
    for (final (group, lines) in _inner.indexed)
      for (var index = 0; index < lines.length; index++)
        (group: group, index: index),
  ];

  /// Whether [line] is between columns (it moves across), not rows.
  bool isColumnLine(GridLine line) => (line.group == null) == _columnsFirst;

  /// [line]'s ratio: its share of the grid's width (or height).
  double ratioOf(GridLine line) =>
      (line.group == null ? _lines : _inner[line.group!])[line.index];

  void setRatio(GridLine line, double ratio) =>
      (line.group == null ? _lines : _inner[line.group!])[line.index] = ratio;

  /// Puts [line] back in the middle of the two panes (or groups) either side
  /// of it.
  void centerLine(GridLine line) {
    final lines = line.group == null ? _lines : _inner[line.group!];
    lines[line.index] =
        (line.index == 0 ? 0.0 : lines[line.index - 1]) / 2 +
        (line.index == lines.length - 1 ? 1.0 : lines[line.index + 1]) / 2;
  }

  /// Where lines at [ratios] are in [extent]: each part between them (and
  /// the edges) [minPane] at least, [gap] between them, where there is room
  /// for all; else evenly apart.
  static List<double> place(
    List<double> ratios,
    double extent, {
    required double gap,
    double minPane = 0,
  }) {
    final count = ratios.length;
    final step = minPane + gap;
    if ((count + 1) * minPane + count * gap > extent) {
      return [for (var i = 1; i <= count; i++) extent * i / (count + 1)];
    }
    final placed = <double>[];
    for (var i = 0; i < count; i++) {
      var at = ratios[i] * extent;
      if (placed.isNotEmpty) at = math.max(at, placed.last + step);
      placed.add(
        at.clamp(
          (i + 1) * step - gap / 2,
          extent - (count - i) * step + gap / 2,
        ),
      );
    }
    return placed;
  }

  /// Where the [index]th part between [placed] lines is in [extent].
  static (double, double) _span(
    List<double> placed,
    int index,
    double extent,
    double gap,
  ) => (
    index == 0 ? 0.0 : placed[index - 1] + gap / 2,
    index == placed.length ? extent : placed[index] - gap / 2,
  );

  /// [size] across the groups and along them, and [minPane] the same way.
  (double, double) _ways(Size size) =>
      _columnsFirst ? (size.width, size.height) : (size.height, size.width);

  Rect _rect((double, double) outer, (double, double) inner) => _columnsFirst
      ? Rect.fromLTRB(outer.$1, inner.$1, outer.$2, inner.$2)
      : Rect.fromLTRB(inner.$1, outer.$1, inner.$2, outer.$2);

  /// Each pane's rectangle in [size], [gap] between them, the lines kept
  /// where the panes either side have [minPane] of room (see [place]).
  Map<T, Rect> layout(
    Size size, {
    required double gap,
    Size minPane = Size.zero,
  }) {
    final (across, along) = _ways(size);
    final (leastAcross, leastAlong) = _ways(minPane);
    final outer = place(_lines, across, gap: gap, minPane: leastAcross);
    return {
      for (final (group, panes) in _groups.indexed)
        for (final (index, pane) in panes.indexed)
          pane: _rect(
            _span(outer, group, across, gap),
            _span(
              place(_inner[group], along, gap: gap, minPane: leastAlong),
              index,
              along,
              gap,
            ),
          ),
    };
  }

  /// Where [line] is in [size], along the way it moves (see [layout]).
  double position(
    GridLine line,
    Size size, {
    required double gap,
    Size minPane = Size.zero,
  }) {
    final (across, along) = _ways(size);
    final (leastAcross, leastAlong) = _ways(minPane);
    return line.group == null
        ? place(_lines, across, gap: gap, minPane: leastAcross)[line.index]
        : place(
            _inner[line.group!],
            along,
            gap: gap,
            minPane: leastAlong,
          )[line.index];
  }

  /// The gap [line] is on in [size]: a line between the groups across the
  /// whole grid, one in a group across the group.
  Rect lineRect(
    GridLine line,
    Size size, {
    required double gap,
    Size minPane = Size.zero,
  }) {
    final (across, along) = _ways(size);
    final (leastAcross, _) = _ways(minPane);
    final at = position(line, size, gap: gap, minPane: minPane);
    final band = (at - gap / 2, at + gap / 2);
    if (line.group case final group?) {
      final outer = place(_lines, across, gap: gap, minPane: leastAcross);
      return _rect(_span(outer, group, across, gap), band);
    }
    return _rect(band, (0.0, along));
  }

  /// Moves [line] to [position] in [size]: no nearer the lines either side
  /// of it (or the edges) than [minPane] lets it, where there is room.
  void moveLine(
    GridLine line,
    double position, {
    required Size size,
    required double gap,
    Size minPane = Size.zero,
  }) {
    final (across, along) = _ways(size);
    final (leastAcross, leastAlong) = _ways(minPane);
    final outer = line.group == null;
    final extent = outer ? across : along;
    final least = outer ? leastAcross : leastAlong;
    if (extent <= 0) return;
    final placed = place(
      outer ? _lines : _inner[line.group!],
      extent,
      gap: gap,
      minPane: least,
    );
    final index = line.index;
    final lowest = index == 0
        ? least + gap / 2
        : placed[index - 1] + least + gap;
    final highest = index == placed.length - 1
        ? extent - least - gap / 2
        : placed[index + 1] - least - gap;
    final at = lowest <= highest
        ? position.clamp(lowest, highest)
        : placed[index];
    setRatio(line, at / extent);
  }

  /// The least room the panes take, each [minPane], [gap] between them.
  Size least(Size minPane, double gap) {
    if (_groups.isEmpty) return Size.zero;
    final (leastAcross, leastAlong) = _ways(minPane);
    double run(int count, double each) => count * each + (count - 1) * gap;
    final across = run(_groups.length, leastAcross);
    final along = _groups
        .map((group) => run(group.length, leastAlong))
        .reduce(math.max);
    return _columnsFirst ? Size(across, along) : Size(along, across);
  }
}
