import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/workspace/chat_grid.dart';

/// The grid's panes as a string: columns `A/C | B` (each top to bottom),
/// rows `A|B / C` (each left to right).
String shape(ChatGrid<String> grid) => grid.columnsFirst
    ? grid.groups.map((column) => column.join('/')).join(' | ')
    : grid.groups.map((row) => row.join('|')).join(' / ');

const GridLine first = (group: null, index: 0);

void main() {
  test('columns side by side, as many as there is room for, each of as '
      'many panes', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..split('B', PaneSide.right, 'C');
    expect(shape(grid), 'A | B | C');
    expect(grid.panes, ['A', 'B', 'C']);
    // A new column takes half the one beside it.
    var rects = grid.layout(const Size(1000, 800), gap: 0);
    expect(rects['A']!.width, 500);
    expect(rects['B']!.width, 250);
    expect(rects['C']!.width, 250);

    grid.split('A', PaneSide.left, 'D');
    expect(shape(grid), 'D | A | B | C');
    for (final (pane, below) in [('D', 'E'), ('A', 'F'), ('B', 'G')]) {
      grid.split(pane, PaneSide.bottom, below);
    }
    grid.split('C', PaneSide.top, 'H');
    expect(shape(grid), 'D/E | A/F | B/G | H/C');
    expect(grid.panes, ['D', 'A', 'B', 'H', 'E', 'F', 'G', 'C']);
    rects = grid.layout(const Size(1000, 800), gap: 0);
    expect(rects['C'], const Rect.fromLTRB(750, 400, 1000, 800));
    // A fifth column, a third in one: the room they need grows with them.
    expect(grid.least(const Size(300, 200), 4), const Size(4 * 304 - 4, 404));
    grid
      ..split('C', PaneSide.right, 'I')
      ..split('C', PaneSide.bottom, 'J');
    expect(shape(grid), 'D/E | A/F | B/G | H/C/J | I');
    expect(grid.panes, ['D', 'A', 'B', 'H', 'I', 'E', 'F', 'G', 'C', 'J']);
    expect(grid.least(const Size(300, 200), 4), const Size(5 * 304 - 4, 608));
  });

  test('rows, each of as many panes, their lines apart', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.bottom, 'D');
    expect(shape(grid), 'A / D');
    grid
      ..split('A', PaneSide.right, 'B')
      ..split('B', PaneSide.right, 'C')
      ..split('D', PaneSide.right, 'E');
    expect(shape(grid), 'A|B|C / D|E');
    expect(grid.columnsFirst, isFalse);
    final rects = grid.layout(const Size(1000, 800), gap: 0);
    expect(rects['C'], const Rect.fromLTRB(750, 0, 1000, 400));
    expect(rects['E'], const Rect.fromLTRB(500, 400, 1000, 800));
    expect(grid.neighbor('E', PaneSide.top), 'B');
    expect(grid.neighbor('A', PaneSide.bottom), 'D');
    expect(grid.neighbor('C', PaneSide.bottom), 'E');
    expect(grid.topRight, 'C');
    grid.split('D', PaneSide.bottom, 'F');
    expect(shape(grid), 'A|B|C / D|E / F');
  });

  test('four in columns: one more is a column of its own', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..split('A', PaneSide.bottom, 'C')
      ..split('B', PaneSide.bottom, 'D');
    expect(shape(grid), 'A/C | B/D');
    grid.split('B', PaneSide.right, 'E');
    expect(shape(grid), 'A/C | B/D | E');
    expect(grid.touches('E', PaneSide.top), isTrue);
    expect(grid.touches('E', PaneSide.bottom), isTrue);
    expect(grid.topRight, 'E');
  });

  test('a pane shown over another gives it back once closed; one shown '
      'elsewhere meanwhile is not given back', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..cover('A', 'C');
    expect(shape(grid), 'C | B');
    expect(grid.under('C'), ['A']);
    expect(grid.isCovered('A'), isTrue);
    grid.cover('C', 'D');
    expect(grid.under('D'), ['A', 'C']);
    expect(grid.uncover('D'), 'C');
    expect(shape(grid), 'C | B');
    expect(grid.under('C'), ['A']);

    // Shown in the other pane: under C no more.
    grid.cover('B', 'A');
    expect(shape(grid), 'C | A');
    expect(grid.isCovered('A'), isFalse);
    expect(grid.under('A'), ['B']);
    expect(grid.uncover('C'), isNull);
    expect(shape(grid), 'C | A');

    // Moved, it takes what it covers along.
    grid.split('C', PaneSide.bottom, 'E');
    expect(grid.rearrange('A', 'E', side: PaneSide.right), isTrue);
    expect(shape(grid), 'C / E|A');
    expect(grid.uncover('A'), 'B');
    expect(shape(grid), 'C / E|B');

    // Removed, those it covers go with it.
    grid.cover('E', 'F');
    grid.remove('F');
    expect(grid.isCovered('E'), isFalse);

    // One under it raised: in its place, it under the rest.
    grid
      ..cover('C', 'G')
      ..cover('G', 'H');
    expect(grid.under('H'), ['C', 'G']);
    grid.raise('H', 'C');
    expect(grid.topLeft, 'C');
    expect(grid.under('C'), ['G', 'H']);
  });

  test('a line that appears starts in the middle of what it splits; one '
      'that was there stays', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..setRatio(first, .3);
    grid.split('A', PaneSide.bottom, 'C');
    expect(grid.ratioOf(first), .3);
    expect(grid.ratioOf((group: 0, index: 0)), .5);
    grid.split('A', PaneSide.right, 'D');
    expect(grid.ratioOf(first), .15);
    expect(grid.ratioOf((group: null, index: 1)), .3);
  });

  test('the line through a column moves on its own; those between the '
      'columns stay straight', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..split('A', PaneSide.bottom, 'C')
      ..split('B', PaneSide.bottom, 'D');
    expect(grid.columnsFirst, isTrue);
    grid.setRatio((group: 0, index: 0), .3);
    const size = Size(1000, 800);
    var rects = grid.layout(size, gap: 4);
    expect(rects['A']!.bottom, 238);
    expect(rects['C']!.top, 242);
    expect(rects['B']!.bottom, 398);
    expect(rects['D']!.top, 402);
    grid.setRatio(first, .4);
    rects = grid.layout(size, gap: 4);
    expect(rects['A']!.right, 398);
    expect(rects['C']!.right, 398);

    // Closed, a pane goes to the other in its column: the other column's
    // line stays where it was.
    grid.remove('D');
    expect(shape(grid), 'A/C | B');
    expect(grid.ratioOf((group: 0, index: 0)), .3);

    // Rows first: the column line moves in each row on its own.
    final rows = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.bottom, 'C')
      ..split('A', PaneSide.right, 'B')
      ..split('C', PaneSide.right, 'D');
    expect(shape(rows), 'A|B / C|D');
    rows.setRatio((group: 1, index: 0), .7);
    rects = rows.layout(size, gap: 4);
    expect(rects['A']!.right, 498);
    expect(rects['C']!.right, 698);
  });

  test('a closed pane is taken over by the one before it in its group, '
      'else after it; a whole group by the group beside it', () {
    ChatGrid<String> four() => ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..split('A', PaneSide.bottom, 'C')
      ..split('B', PaneSide.bottom, 'D');
    var grid = four();
    expect(grid.remove('B'), 'D');
    expect(shape(grid), 'A/C | D');

    // A whole row, the other one split: the row left is columns.
    grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.bottom, 'C')
      ..split('C', PaneSide.right, 'D')
      ..setRatio((group: 1, index: 0), .3);
    expect(shape(grid), 'A / C|D');
    expect(grid.remove('A'), 'C');
    expect(shape(grid), 'C | D');
    expect(grid.columnsFirst, isTrue);
    expect(grid.ratioOf(first), .3);

    grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.bottom, 'C')
      ..split('C', PaneSide.right, 'D');
    expect(grid.remove('C'), 'D');
    expect(shape(grid), 'A / D');

    // The middle column to the one left of it.
    grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..split('B', PaneSide.right, 'C');
    expect(grid.remove('B'), 'A');
    expect(shape(grid), 'A | C');
    expect(grid.ratioOf(first), .75);

    grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B');
    expect(grid.remove('A'), 'B');
    expect(shape(grid), 'B');
    expect(grid.remove('B'), isNull);
    expect(grid.isEmpty, isTrue);
  });

  test('lays the panes out on shared lines, each side kept at its least '
      'where there is room', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..split('B', PaneSide.bottom, 'C');
    const size = Size(1000, 800);
    var rects = grid.layout(size, gap: 4);
    expect(rects['A'], const Rect.fromLTRB(0, 0, 498, 800));
    expect(rects['B'], const Rect.fromLTRB(502, 0, 1000, 398));
    expect(rects['C'], const Rect.fromLTRB(502, 402, 1000, 800));

    grid.setRatio(first, .1);
    rects = grid.layout(size, gap: 4, minPane: const Size(300, 300));
    expect(rects['A']!.width, 300);
    // No room for both: in the middle.
    rects = grid.layout(
      const Size(500, 800),
      gap: 4,
      minPane: const Size(300, 300),
    );
    expect(rects['A']!.width, 248);

    // Three columns: each at its least, the lines kept apart.
    grid
      ..split('A', PaneSide.right, 'D')
      ..setRatio(first, .5)
      ..setRatio((group: null, index: 1), .55);
    rects = grid.layout(size, gap: 4, minPane: const Size(300, 300));
    expect(rects['A']!.width, 392);
    expect(rects['D']!.width, 300);
    expect(rects['B']!.width, 300);
    expect(
      grid.least(const Size(300, 300), 4),
      const Size(3 * 300 + 2 * 4, 2 * 300 + 4),
    );
  });

  test('a line dragged stops short of the lines beside it', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..split('B', PaneSide.right, 'C');
    const size = Size(1500, 800);
    const middle = (group: null, index: 1);
    grid.moveLine(middle, 100, size: size, gap: 4, minPane: const Size(300, 0));
    expect(grid.position(middle, size, gap: 4), 750 + 304);
    grid.moveLine(
      middle,
      2000,
      size: size,
      gap: 4,
      minPane: const Size(300, 0),
    );
    expect(grid.position(middle, size, gap: 4), 1500 - 302);
    grid.centerLine(middle);
    expect(grid.ratioOf(middle), .75);
  });

  test('swapping panes preserves their rectangles and the line positions', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..split('B', PaneSide.bottom, 'C')
      ..setRatio(first, .35);
    expect(grid.rearrange('A', 'C'), isTrue);
    expect(shape(grid), 'C | B/A');
    expect(grid.ratioOf(first), .35);
    expect(grid.rearrange('A', 'A'), isFalse);
    expect(grid.rearrange('A', 'gone'), isFalse);
    expect(shape(grid), 'C | B/A');
  });

  test('moving beside a pane removes its old place before splitting', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B');
    expect(grid.rearrange('A', 'B', side: PaneSide.bottom), isTrue);
    expect(shape(grid), 'B / A');
    expect(grid.panes, ['B', 'A']);
    expect(grid.columnsSplit, isFalse);
    expect(grid.rowsSplit, isTrue);
  });

  test('a move nowhere leaves the whole grid unchanged', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.bottom, 'B')
      ..split('A', PaneSide.right, 'C')
      ..split('B', PaneSide.right, 'D')
      ..setRatio(first, .7);
    // Onto itself, or a pane gone: nothing.
    expect(grid.rearrange('A', 'A', side: PaneSide.bottom), isFalse);
    expect(grid.rearrange('A', 'gone', side: PaneSide.bottom), isFalse);
    expect(shape(grid), 'A|C / B|D');
    expect(grid.ratioOf(first), .7);
    // A row of its own, the third.
    expect(grid.rearrange('A', 'D', side: PaneSide.bottom), isTrue);
    expect(shape(grid), 'C / B|D / A');
    expect(grid.rearrange('A', 'D', side: PaneSide.right), isTrue);
    expect(shape(grid), 'C / B|D|A');
  });

  test('every rearrangement keeps the grid whole', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..split('B', PaneSide.right, 'C')
      ..split('A', PaneSide.bottom, 'D')
      ..split('C', PaneSide.bottom, 'E');
    void check(ChatGrid<String> grid, int depth) {
      for (final source in grid.panes) {
        for (final target in grid.panes) {
          for (final side in [null, ...PaneSide.values]) {
            final next = grid.copy();
            final before = shape(next);
            final changed = next.rearrange(source, target, side: side);
            expect(next.panes.toSet(), grid.panes.toSet());
            final json = next.toJson(next.panes.indexOf);
            final restored = ChatGrid.fromJson(json)!;
            expect(restored.toJson((pane) => pane), json);
            if (!changed) expect(shape(next), before);
            if (changed && depth > 0) check(next, depth - 1);
          }
        }
      }
    }

    check(grid, 1);
  });

  test('kept and given back; an earlier run\'s 2×2 cells too', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.bottom, 'B')
      ..split('A', PaneSide.right, 'C')
      ..setRatio((group: 0, index: 0), .3);
    final panes = grid.panes;
    final json = grid.toJson(panes.indexOf);
    final restored = ChatGrid.fromJson(json)!;
    expect(restored.groups, [
      [0, 1],
      [2],
    ]);
    expect(restored.columnsFirst, isFalse);
    expect(restored.ratioOf((group: 0, index: 0)), .3);

    ChatGrid<int>? cells(
      List<int> cells, [
      Map<String, Object?> more = const {},
    ]) => ChatGrid.fromJson({'cells': cells, ...more});
    expect(cells([0, 1, 0, 2])!.groups, [
      [0],
      [1, 2],
    ]);
    final rows = cells(
      [0, 0, 1, 2],
      {
        'columnRatios': [.5, .3],
      },
    )!;
    expect(rows.columnsFirst, isFalse);
    expect(rows.groups, [
      [0],
      [1, 2],
    ]);
    expect(rows.ratioOf((group: 1, index: 0)), .3);
    expect(cells([0, 1, 0, 1], {'columnRatio': .3})!.ratioOf(first), .3);
    expect(cells([0, 0, 0, 0])!.groups, [
      [0],
    ]);
    // Not rectangles; nor a pane in two places.
    expect(cells([0, 1, 1, 0]), isNull);
    expect(
      ChatGrid.fromJson({
        'columnsFirst': true,
        'groups': [
          [0, 1],
          [1],
        ],
      }),
      isNull,
    );
    // One column of three is three rows.
    final column = ChatGrid.fromJson({
      'columnsFirst': true,
      'groups': [
        [0, 1, 2],
      ],
    })!;
    expect(column.columnsFirst, isFalse);
    expect(column.groups, [
      [0],
      [1],
      [2],
    ]);
  });

  test('a pane\'s tabs keep the order they came in, whichever shows', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..cover('A', 'C')
      ..cover('C', 'D');
    expect(grid.tabs('D'), ['A', 'C', 'D']);
    grid.raise('D', 'A');
    expect(grid.tabs('A'), ['A', 'C', 'D']);
    expect(grid.tabs('B'), ['B']);
    // Taken to the other pane, it is that one's last.
    grid.cover('B', 'C');
    expect(grid.tabs('A'), ['A', 'D']);
    expect(grid.tabs('C'), ['B', 'C']);
    // Moved with what it covers, it keeps its place among them.
    grid.split('C', PaneSide.bottom, 'E');
    expect(grid.rearrange('A', 'E', side: PaneSide.right), isTrue);
    expect(grid.tabs('A'), ['A', 'D']);
  });

  test("a pane's tabs given back, in their order, those taken left out", () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B');
    // A shown between C and D, D the next to show again; B shown, so not
    // A's too.
    grid.restoreTabs('A', ['C', 'A', 'D'], ['C', 'B', 'D']);
    expect(grid.under('A'), ['C', 'D']);
    expect(grid.tabs('A'), ['C', 'A', 'D']);
    expect(grid.tabs('B'), ['B']);
    // Under A already: not B's as well.
    grid.restoreTabs('B', ['B', 'C'], ['C']);
    expect(grid.tabs('B'), ['B']);
    expect(grid.uncover('A'), 'D');
    expect(grid.tabs('D'), ['C', 'D']);
  });

  test('the pane beside one each way, none past the edge', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..split('B', PaneSide.bottom, 'C');
    expect(shape(grid), 'A | B/C');
    expect(grid.neighbor('A', PaneSide.right), 'B');
    expect(grid.neighbor('A', PaneSide.left), isNull);
    expect(grid.neighbor('A', PaneSide.top), isNull);
    expect(grid.neighbor('B', PaneSide.bottom), 'C');
    expect(grid.neighbor('C', PaneSide.top), 'B');
    expect(grid.neighbor('C', PaneSide.left), 'A');
    expect(grid.neighbor('B', PaneSide.right), isNull);
  });
}
