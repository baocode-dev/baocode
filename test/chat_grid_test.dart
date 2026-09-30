import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/workspace/chat_grid.dart';

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

  test('a line that appears starts in the middle; one that was there '
      'stays', () {
    final grid = ChatGrid<String>()
      ..show('A')
      ..split('A', PaneSide.right, 'B')
      ..columnRatio = .3;
    grid.split('A', PaneSide.bottom, 'C');
    expect(grid.columnRatio, .3);
    expect(grid.rowRatio, .5);
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

    grid.columnRatio = .1;
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
}
