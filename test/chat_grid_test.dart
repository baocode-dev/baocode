import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/workspace/chat_grid.dart';

/// The grid's cells, row by row, as a string: `AB/CD`.
String cells(ChatGrid<String> grid) =>
    '${grid.at(0)}${grid.at(1)}/${grid.at(2)}${grid.at(3)}';

void main() {
  test('one pane splits any way; two only across their line', () {
    final grid = ChatGrid<String>()..show('A');
    for (final side in PaneSide.values) {
      expect(grid.canSplit('A', side), isTrue);
    }
    grid.split('A', PaneSide.right, 'B');
    expect(cells(grid), 'AB/AB');
    expect(grid.panes, ['A', 'B']);
    // A third column would not be a 2×2 grid.
    for (final pane in ['A', 'B']) {
      expect(grid.canSplit(pane, PaneSide.left), isFalse);
      expect(grid.canSplit(pane, PaneSide.right), isFalse);
      expect(grid.canSplit(pane, PaneSide.top), isTrue);
      expect(grid.canSplit(pane, PaneSide.bottom), isTrue);
    }
  });

  test('three: the pane with a whole column splits; four: none', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.left, 'B')
      ..split('A', PaneSide.bottom, 'C');
    expect(cells(grid), 'BA/BC');
    expect(grid.canSplit('A', PaneSide.top), isFalse);
    expect(grid.canSplit('C', PaneSide.left), isFalse);
    expect(grid.canSplit('B', PaneSide.top), isTrue);
    expect(grid.canSplit('B', PaneSide.right), isFalse);
    grid.split('B', PaneSide.top, 'D');
    expect(cells(grid), 'DA/BC');
    expect(grid.length, 4);
    for (final pane in grid.panes) {
      for (final side in PaneSide.values) {
        expect(grid.canSplit(pane, side), isFalse);
      }
    }
  });

  test('a pane shown over another gives it back once closed; one shown '
      'elsewhere meanwhile is not given back', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..cover('A', 'C');
    expect(cells(grid), 'CB/CB');
    expect(grid.under('C'), ['A']);
    expect(grid.isCovered('A'), isTrue);
    grid.cover('C', 'D');
    expect(grid.under('D'), ['A', 'C']);
    expect(grid.uncover('D'), 'C');
    expect(cells(grid), 'CB/CB');
    expect(grid.under('C'), ['A']);

    // Shown in the other pane: under C no more.
    grid.cover('B', 'A');
    expect(cells(grid), 'CA/CA');
    expect(grid.isCovered('A'), isFalse);
    expect(grid.under('A'), ['B']);
    expect(grid.uncover('C'), isNull);
    expect(cells(grid), 'CA/CA');

    // Moved, it takes what it covers along.
    grid.split('C', PaneSide.bottom, 'E');
    expect(grid.rearrange('A', 'E', side: PaneSide.right), isTrue);
    expect(cells(grid), 'CC/EA');
    expect(grid.uncover('A'), 'B');
    expect(cells(grid), 'CC/EB');

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
    expect(grid.at(0), 'C');
    expect(grid.under('C'), ['G', 'H']);
  });

  test('a line that appears starts in the middle; one that was there '
      'stays', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..setColumnRatioIn(0, .3);
    grid.split('A', PaneSide.bottom, 'C');
    expect(grid.columnRatios, [.3, .3]);
    expect(grid.rowRatios, [.5, .5]);
  });

  test('the line through a column moves on its own; the one beside it '
      'stays straight', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..split('A', PaneSide.bottom, 'C')
      ..split('B', PaneSide.bottom, 'D');
    expect(cells(grid), 'AB/CD');
    expect(grid.columnsFirst, isTrue);
    grid.setRowRatioIn(0, .3);
    const size = Size(1000, 800);
    var rects = grid.layout(size, gap: 4);
    expect(rects['A']!.bottom, 238);
    expect(rects['C']!.top, 242);
    expect(rects['B']!.bottom, 398);
    expect(rects['D']!.top, 402);
    // The straight one moves in both rows.
    grid.setColumnRatioIn(1, .4);
    rects = grid.layout(size, gap: 4);
    expect(rects['A']!.right, 398);
    expect(rects['C']!.right, 398);

    // Closed, a pane goes to the one across the straight line: the other
    // column's line stays where it was.
    grid.remove('D');
    expect(cells(grid), 'AB/CB');
    expect(grid.rowRatios.first, .3);

    // Rows first: the column line moves in each row on its own.
    final rows = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.bottom, 'C')
      ..split('A', PaneSide.right, 'B')
      ..split('C', PaneSide.right, 'D');
    expect(cells(rows), 'AB/CD');
    expect(rows.columnsFirst, isFalse);
    rows.setColumnRatioIn(1, .7);
    rects = rows.layout(size, gap: 4);
    expect(rects['A']!.right, 498);
    expect(rects['C']!.right, 698);
  });

  test('a closed pane is taken over by the one above or below it, else '
      'beside it', () {
    ChatGrid<String> four() => ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..split('A', PaneSide.bottom, 'C')
      ..split('B', PaneSide.bottom, 'D');
    var grid = four();
    expect(cells(grid), 'AB/CD');
    expect(grid.remove('B'), 'D');
    expect(cells(grid), 'AD/CD');

    // A whole row, the other one split: each cell to the pane below.
    grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.bottom, 'C')
      ..split('C', PaneSide.right, 'D');
    expect(cells(grid), 'AA/CD');
    expect(grid.remove('A'), 'C');
    expect(cells(grid), 'CD/CD');

    // Beside it where there is no one pane above or below.
    grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.bottom, 'C')
      ..split('C', PaneSide.right, 'D');
    expect(grid.remove('C'), 'D');
    expect(cells(grid), 'AA/DD');

    grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B');
    expect(grid.remove('A'), 'B');
    expect(cells(grid), 'BB/BB');
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

    grid.setColumnRatioIn(0, .1);
    rects = grid.layout(size, gap: 4, minPane: const Size(300, 300));
    expect(rects['A']!.width, 300);
    // No room for both: in the middle.
    rects = grid.layout(
      const Size(500, 800),
      gap: 4,
      minPane: const Size(300, 300),
    );
    expect(rects['A']!.width, 248);
  });

  test('swapping panes preserves their rectangles and the line positions', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..split('B', PaneSide.bottom, 'C')
      ..columnRatios = [.35, .35]
      ..rowRatios = [.6, .6];
    expect(grid.rearrange('A', 'C'), isTrue);
    expect(cells(grid), 'CB/CA');
    expect(grid.columnRatios, [.35, .35]);
    expect(grid.rowRatios, [.6, .6]);
    expect(grid.rearrange('A', 'A'), isFalse);
    expect(grid.rearrange('A', 'gone'), isFalse);
    expect(cells(grid), 'CB/CA');
  });

  test('moving beside a pane removes its old place before splitting', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B');
    expect(grid.rearrange('A', 'B', side: PaneSide.bottom), isTrue);
    expect(cells(grid), 'BB/AA');
    expect(grid.panes, ['B', 'A']);
    expect(grid.columnsSplit, isFalse);
    expect(grid.rowsSplit, isTrue);
  });

  test('an impossible move leaves the whole grid unchanged', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..split('A', PaneSide.bottom, 'C')
      ..split('B', PaneSide.bottom, 'D')
      ..columnRatios = [.4, .4]
      ..rowRatios = [.7, .7];
    // A's cells would go to C, leaving B too small to split horizontally.
    expect(grid.rearrange('A', 'B', side: PaneSide.left), isFalse);
    expect(cells(grid), 'AB/CD');
    expect(grid.columnRatios, [.4, .4]);
    expect(grid.rowRatios, [.7, .7]);
    expect(grid.rearrange('A', 'C', side: PaneSide.top), isTrue);
    expect(cells(grid), 'AB/CD');
  });

  test('every rearrangement keeps all panes as rectangles', () {
    const names = ['A', 'B', 'C', 'D'];
    for (var encoding = 0; encoding < 256; encoding++) {
      final original = [
        for (var cell = 0; cell < 4; cell++)
          names[(encoding >> (cell * 2)) & 3],
      ];
      final grid = ChatGrid<String>();
      if (!grid.restore(original)) continue;
      for (final source in grid.panes) {
        for (final target in grid.panes) {
          for (final side in [null, ...PaneSide.values]) {
            final next = grid.copy();
            final changed = next.rearrange(source, target, side: side);
            expect(next.panes.toSet(), grid.panes.toSet());
            expect(ChatGrid<String>().restore(next.cells), isTrue);
            if (!changed) expect(next.cells, original);
          }
        }
      }
    }
  });

  test('cells are given back only where they make a grid', () {
    final grid = ChatGrid<String>()..show('A');
    expect(grid.restore(['A', 'B', 'A', 'C']), isTrue);
    expect(cells(grid), 'AB/AC');
    expect(grid.panes, ['A', 'B', 'C']);
    // B's cells are not a rectangle; nor are three cells a grid.
    expect(grid.restore(['A', 'B', 'B', 'A']), isFalse);
    expect(grid.restore(['A', 'B', 'A']), isFalse);
    expect(cells(grid), 'AB/AC');
  });
}
