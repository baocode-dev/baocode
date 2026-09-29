// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/ide/editor/monaco/LICENSE.txt.
// Adapted from the pinned VS Code
// src/vs/editor/contrib/folding/test/browser/{indentRangeProvider,indentFold,
// foldingRanges}.test.ts.

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/languages/language_configuration.dart';
import 'package:monad/ide/editor/monaco/vs/editor/contrib/folding/browser/folding_ranges.dart';
import 'package:monad/ide/editor/monaco/vs/editor/contrib/folding/browser/indent_range_provider.dart';

class _Lines implements FoldingLineSource {
  _Lines(this.lines);

  final List<String> lines;

  @override
  int get lineCount => lines.length;

  @override
  String getLineContent(int lineNumber) => lines[lineNumber - 1];
}

class _Limit implements FoldingLimitReporter {
  _Limit(this.limit);

  @override
  final int limit;
  Object? reported;

  @override
  void update(int computed, Object limited) => reported = limited;
}

typedef ExpectedRange = (int, int, int);

ExpectedRange r(int start, int end, int parent) => (start, end, parent);

void assertRanges(
  List<String> lines,
  List<ExpectedRange> expected,
  bool offSide, [
  FoldingMarkers? markers,
]) {
  final actual = computeRanges(_Lines(lines), offSide, markers: markers);
  expect([
    for (var i = 0; i < actual.length; i++)
      (
        actual.getStartLineNumber(i),
        actual.getEndLineNumber(i),
        actual.getParentIndex(i),
      ),
  ], expected);
}

final markers = FoldingMarkers(
  RegExp(r'^\s*#region\b'),
  RegExp(r'^\s*#endregion\b'),
);

void main() {
  group('Indentation Folding', () {
    test('Fold one level', () {
      final range = ['A', '  A', '  A', '  A'];
      assertRanges(range, [r(1, 4, -1)], true);
      assertRanges(range, [r(1, 4, -1)], false);
    });

    test('Fold two levels', () {
      final range = ['A', '  A', '  A', '    A', '    A'];
      assertRanges(range, [r(1, 5, -1), r(3, 5, 0)], true);
      assertRanges(range, [r(1, 5, -1), r(3, 5, 0)], false);
    });

    test('Fold three levels', () {
      final range = ['A', '  A', '    A', '      A', 'A'];
      assertRanges(range, [r(1, 4, -1), r(2, 4, 0), r(3, 4, 1)], true);
      assertRanges(range, [r(1, 4, -1), r(2, 4, 0), r(3, 4, 1)], false);
    });

    test('Fold decreasing indent', () {
      final range = ['    A', '  A', 'A'];
      assertRanges(range, [], true);
      assertRanges(range, [], false);
    });

    test('Fold Java', () {
      assertRanges(
        [
          'class A {',
          '  void foo() {',
          '    console.log();',
          '    console.log();',
          '  }',
          '',
          '  void bar() {',
          '    console.log();',
          '  }',
          '}',
          'interface B {',
          '  void bar();',
          '}',
        ],
        [r(1, 9, -1), r(2, 4, 0), r(7, 8, 0), r(11, 12, -1)],
        false,
      );
    });

    test('Fold Javadoc', () {
      assertRanges(
        ['/**', ' * Comment', ' */', 'class A {', '  void foo() {', '  }', '}'],
        [r(1, 3, -1), r(4, 6, -1)],
        false,
      );
    });

    test('Fold Whitespace Java', () {
      assertRanges(
        [
          'class A {',
          '',
          '  void foo() {',
          '     ',
          '     return 0;',
          '  }',
          '      ',
          '}',
        ],
        [r(1, 7, -1), r(3, 5, 0)],
        false,
      );
    });

    test('Fold Whitespace Python', () {
      assertRanges(
        [
          'def a:',
          '  pass',
          '   ',
          '  def b:',
          '    pass',
          '  ',
          '      ',
          'def c: # since there was a deintent here',
        ],
        [r(1, 5, -1), r(4, 5, 0)],
        true,
      );
    });

    test('Fold Tabs', () {
      assertRanges(
        [
          'class A {',
          '\t\t',
          '\tvoid foo() {',
          '\t \t//hello',
          '\t    return 0;',
          '  \t}',
          '      ',
          '}',
        ],
        [r(1, 7, -1), r(3, 5, 0)],
        false,
      );
    });
  });

  group('Folding with regions', () {
    test('Inside region, indented', () {
      assertRanges(
        [
          'class A {',
          '  #region',
          '  void foo() {',
          '     ',
          '     return 0;',
          '  }',
          '  #endregion',
          '}',
        ],
        [r(1, 7, -1), r(2, 7, 0), r(3, 5, 1)],
        false,
        markers,
      );
    });
    test('Inside region, not indented', () {
      assertRanges(
        [
          'var x;',
          '#region',
          'void foo() {',
          '     ',
          '     return 0;',
          '  }',
          '#endregion',
          '',
        ],
        [r(2, 7, -1), r(3, 6, 0)],
        false,
        markers,
      );
    });
    test('Empty Regions', () {
      assertRanges(
        [
          'var x;',
          '#region',
          '#endregion',
          '#region',
          '',
          '#endregion',
          'var y;',
        ],
        [r(2, 3, -1), r(4, 6, -1)],
        false,
        markers,
      );
    });
    test('Nested Regions', () {
      assertRanges(
        [
          'var x;',
          '#region',
          '#region',
          '',
          '#endregion',
          '#endregion',
          'var y;',
        ],
        [r(2, 6, -1), r(3, 5, 0)],
        false,
        markers,
      );
    });
    test('Nested Regions 2', () {
      assertRanges(
        [
          'class A {',
          '  #region',
          '',
          '  #region',
          '',
          '  #endregion',
          '  // comment',
          '  #endregion',
          '}',
        ],
        [r(1, 8, -1), r(2, 8, 0), r(4, 6, 1)],
        false,
        markers,
      );
    });
    test('Incomplete Regions', () {
      assertRanges(
        ['class A {', '#region', '  // comment', '}'],
        [r(2, 3, -1)],
        false,
        markers,
      );
    });
    test('Incomplete Regions 2', () {
      assertRanges(
        [
          '',
          '#region',
          '#region',
          '#region',
          '  // comment',
          '#endregion',
          '#endregion',
          ' // hello',
        ],
        [r(3, 7, -1), r(4, 6, 0)],
        false,
        markers,
      );
    });
    test('Indented region before', () {
      assertRanges(
        ['if (x)', '  return;', '', '#region', '  // comment', '#endregion'],
        [r(1, 3, -1), r(4, 6, -1)],
        false,
        markers,
      );
    });
    test('Indented region before 2', () {
      assertRanges(
        [
          'if (x)',
          '  log();',
          '',
          '    #region',
          '      // comment',
          '    #endregion',
        ],
        [r(1, 6, -1), r(2, 6, 0), r(4, 6, 1)],
        false,
        markers,
      );
    });
    test('Indented region in-between', () {
      assertRanges(
        [
          '#region',
          '  // comment',
          '  if (x)',
          '    return;',
          '',
          '#endregion',
        ],
        [r(1, 6, -1), r(3, 5, 0)],
        false,
        markers,
      );
    });
    test('Indented region after', () {
      assertRanges(
        [
          '#region',
          '  // comment',
          '',
          '#endregion',
          '  if (x)',
          '    return;',
        ],
        [r(1, 4, -1), r(5, 6, -1)],
        false,
        markers,
      );
    });
    test('With off-side', () {
      assertRanges(
        ['#region', '  ', '', '#endregion', ''],
        [r(1, 4, -1)],
        true,
        markers,
      );
    });
    test('Nested with off-side', () {
      assertRanges(
        ['#region', '  ', '#region', '', '#endregion', '', '#endregion', ''],
        [r(1, 7, -1), r(3, 5, 0)],
        true,
        markers,
      );
    });
    test('Issue 35981', () {
      assertRanges(
        [
          'function thisFoldsToEndOfPage() {',
          '  const variable = []',
          '    // #region',
          '    .reduce((a, b) => a,[]);',
          '}',
          '',
          'function thisFoldsProperly() {',
          '  const foo = "bar"',
          '}',
        ],
        [r(1, 4, -1), r(2, 4, 0), r(7, 8, -1)],
        false,
        markers,
      );
    });
    test('Misspelled Markers', () {
      assertRanges(
        [
          '#Region',
          '#endregion',
          '#regionsandmore',
          '#endregion',
          '#region',
          '#end region',
          '#region',
          '#endregionff',
        ],
        [],
        true,
        markers,
      );
    });
    test('Issue 79359', () {
      assertRanges(
        [
          '#region',
          '',
          'class A',
          '  foo',
          '',
          'class A',
          '  foo',
          '',
          '#endregion',
        ],
        [r(1, 9, -1), r(3, 4, 0), r(6, 7, 0)],
        true,
        markers,
      );
    });
    test('Markers with differing flags', () {
      assertRanges(
        ['#REGION', 'content', '#endregion'],
        [r(1, 3, -1)],
        false,
        FoldingMarkers(
          RegExp(r'^\s*#region\b', caseSensitive: false),
          RegExp(r'^\s*#endregion\b'),
        ),
      );
      assertRanges(
        ['#REGION', 'content', '#ENDREGION'],
        [],
        false,
        FoldingMarkers(
          RegExp(r'^\s*#region\b', caseSensitive: false),
          RegExp(r'^\s*#endregion\b'),
        ),
      );
      assertRanges(
        ['#REGION', 'content', '#ENDREGION'],
        [],
        false,
        FoldingMarkers(
          RegExp(r'^\s*#region\b'),
          RegExp(r'^\s*#endregion\b', caseSensitive: false),
        ),
      );
    });
  });

  test('Limit by indent', () {
    final lines = _Lines([
      'A',
      '  A',
      '  A',
      '    A',
      '      A',
      '    A',
      '      A',
      '      A',
      '         A',
      '      A',
      '         A',
      '  A',
      '              A',
      '                 A',
      'A',
      '  A',
    ]);
    const r1 = (1, 14), r2 = (3, 11), r3 = (4, 5), r4 = (6, 11);
    const r5 = (8, 9), r6 = (10, 11), r7 = (12, 14), r8 = (13, 14);
    const r9 = (15, 16);
    void assertLimit(int maxEntries, List<(int, int)> expected) {
      final limit = _Limit(maxEntries);
      final ranges = computeRanges(lines, true, foldingRangesLimit: limit);
      expect(ranges.length, lessThanOrEqualTo(maxEntries));
      expect(
        [
          for (var i = 0; i < ranges.length; i++)
            (ranges.getStartLineNumber(i), ranges.getEndLineNumber(i)),
        ],
        expected,
        reason: '$maxEntries',
      );
      expect(limit.reported, 9 <= maxEntries ? false : maxEntries);
    }

    assertLimit(1000, [r1, r2, r3, r4, r5, r6, r7, r8, r9]);
    assertLimit(9, [r1, r2, r3, r4, r5, r6, r7, r8, r9]);
    assertLimit(8, [r1, r2, r3, r4, r5, r6, r7, r9]);
    assertLimit(7, [r1, r2, r3, r4, r5, r7, r9]);
    assertLimit(6, [r1, r2, r3, r4, r7, r9]);
    assertLimit(5, [r1, r2, r3, r7, r9]);
    assertLimit(4, [r1, r2, r7, r9]);
    assertLimit(3, [r1, r2, r9]);
    assertLimit(2, [r1, r9]);
    assertLimit(1, [r1]);
    assertLimit(0, []);
  });

  group('FoldingRanges', () {
    final exact = FoldingMarkers(RegExp(r'^#region$'), RegExp(r'^#endregion$'));
    FoldRange foldRange(
      int from,
      int to, [
      bool collapsed = false,
      FoldSource source = FoldSource.provider,
      String? type,
    ]) => FoldRange(
      startLineNumber: from,
      endLineNumber: to,
      type: type,
      isCollapsed: collapsed,
      source: source,
    );
    void assertEqualRanges(FoldRange a, FoldRange b, String message) {
      expect(
        (a.startLineNumber, a.endLineNumber, a.type, a.isCollapsed, a.source),
        (b.startLineNumber, b.endLineNumber, b.type, b.isCollapsed, b.source),
        reason: message,
      );
    }

    test('test max folding regions', () {
      final lines = <String>[];
      final collector = RangesCollector(_Limit(maxFoldingRegions));
      for (var i = 0; i < maxFoldingRegions; i++) {
        final startLineNumber = lines.length;
        lines.add('#region');
        final endLineNumber = lines.length;
        lines.add('#endregion');
        collector.insertFirst(startLineNumber, endLineNumber, 0);
      }
      final actual = collector.toIndentRanges(_Lines(lines), 4);
      expect(actual.length, maxFoldingRegions);
    });

    test('findRange', () {
      final actual = computeRanges(
        _Lines([
          '#region',
          '#endregion',
          'class A {',
          '  void foo() {',
          '    if (true) {',
          '        return;',
          '    }',
          '',
          '    if (true) {',
          '      return;',
          '    }',
          '  }',
          '}',
        ]),
        false,
        markers: exact,
      );
      final expected = [0, 0, 1, 2, 3, 3, 2, 2, 4, 4, 2, 1, -1];
      for (var line = 1; line <= 13; line++) {
        expect(actual.findRange(line), expected[line - 1], reason: '$line');
      }
    });

    test('setCollapsed', () {
      const nRegions = 500;
      final actual = computeRanges(
        _Lines([
          for (var i = 0; i < nRegions; i++) '#region',
          for (var i = 0; i < nRegions; i++) '#endregion',
        ]),
        false,
        markers: exact,
      );
      expect(actual.length, nRegions);
      for (var i = 0; i < nRegions; i++) {
        actual.setCollapsed(i, i % 3 == 0);
      }
      for (var i = 0; i < nRegions; i++) {
        expect(actual.isCollapsed(i), i % 3 == 0, reason: 'line $i');
      }
    });

    test('sanitizeAndMerge1', () {
      final result = FoldingRegions.sanitizeAndMerge(
        [
          foldRange(0, 100),
          foldRange(1, 100, false, FoldSource.provider, 'A'),
          foldRange(1, 100, false, FoldSource.provider, 'Z'),
          foldRange(10, 10, false),
          foldRange(20, 80, false, FoldSource.provider, 'C1'),
          foldRange(22, 80, true, FoldSource.provider, 'D1'),
          foldRange(90, 101),
        ],
        [
          foldRange(20, 80, true),
          foldRange(18, 80, true),
          foldRange(21, 81, true, FoldSource.provider, 'Z'),
          foldRange(22, 80, true, FoldSource.provider, 'D2'),
        ],
        100,
      );
      expect(result, hasLength(3));
      assertEqualRanges(
        result[0],
        foldRange(1, 100, false, FoldSource.provider, 'A'),
        'A1',
      );
      assertEqualRanges(
        result[1],
        foldRange(20, 80, true, FoldSource.provider, 'C1'),
        'C1',
      );
      assertEqualRanges(
        result[2],
        foldRange(22, 80, true, FoldSource.provider, 'D1'),
        'D1',
      );
    });

    test('sanitizeAndMerge2', () {
      final result = FoldingRegions.sanitizeAndMerge(
        [
          foldRange(1, 100, false, FoldSource.provider, 'a1'),
          foldRange(2, 100, false, FoldSource.provider, 'a2'),
          foldRange(3, 19, false, FoldSource.provider, 'a3'),
          foldRange(20, 71, false, FoldSource.provider, 'a4'),
          foldRange(21, 29, false, FoldSource.provider, 'a5'),
          foldRange(81, 91, false, FoldSource.provider, 'a6'),
        ],
        [
          foldRange(30, 39, true, FoldSource.provider, 'b1'),
          foldRange(40, 49, true, FoldSource.userDefined, 'b2'),
          foldRange(50, 100, true, FoldSource.userDefined, 'b3'),
          foldRange(80, 90, true, FoldSource.userDefined, 'b4'),
          foldRange(92, 100, true, FoldSource.userDefined, 'b5'),
        ],
        100,
      );
      expect(result, hasLength(9));
      final expected = [
        foldRange(1, 100, false, FoldSource.provider, 'a1'),
        foldRange(2, 100, false, FoldSource.provider, 'a2'),
        foldRange(3, 19, false, FoldSource.provider, 'a3'),
        foldRange(21, 29, false, FoldSource.provider, 'a5'),
        foldRange(30, 39, true, FoldSource.recovered, 'b1'),
        foldRange(40, 49, true, FoldSource.userDefined, 'b2'),
        foldRange(50, 100, true, FoldSource.userDefined, 'b3'),
        foldRange(80, 90, true, FoldSource.userDefined, 'b4'),
        foldRange(92, 100, true, FoldSource.userDefined, 'b5'),
      ];
      for (var i = 0; i < expected.length; i++) {
        assertEqualRanges(result[i], expected[i], 'P${i + 1}');
      }
    });

    test('sanitizeAndMerge3', () {
      final result = FoldingRegions.sanitizeAndMerge(
        [
          foldRange(1, 100, false, FoldSource.provider, 'a1'),
          foldRange(10, 29, false, FoldSource.provider, 'a2'),
          foldRange(35, 39, true, FoldSource.recovered, 'a3'),
        ],
        [
          foldRange(10, 29, true, FoldSource.recovered, 'b1'),
          foldRange(20, 28, true, FoldSource.provider, 'b2'),
          foldRange(30, 39, true, FoldSource.recovered, 'b3'),
        ],
        100,
      );
      expect(result, hasLength(5));
      final expected = [
        foldRange(1, 100, false, FoldSource.provider, 'a1'),
        foldRange(10, 29, true, FoldSource.provider, 'a2'),
        foldRange(20, 28, true, FoldSource.recovered, 'b2'),
        foldRange(30, 39, true, FoldSource.recovered, 'b3'),
        foldRange(35, 39, true, FoldSource.recovered, 'a3'),
      ];
      for (var i = 0; i < expected.length; i++) {
        assertEqualRanges(result[i], expected[i], 'R${i + 1}');
      }
    });

    test('sanitizeAndMerge4', () {
      final result = FoldingRegions.sanitizeAndMerge(
        [foldRange(1, 100, false, FoldSource.provider, 'a1')],
        [
          foldRange(20, 28, true, FoldSource.provider, 'b1'),
          foldRange(30, 38, true, FoldSource.provider, 'b2'),
        ],
        100,
      );
      expect(result, hasLength(3));
      assertEqualRanges(
        result[0],
        foldRange(1, 100, false, FoldSource.provider, 'a1'),
        'R1',
      );
      assertEqualRanges(
        result[1],
        foldRange(20, 28, true, FoldSource.recovered, 'b1'),
        'R2',
      );
      assertEqualRanges(
        result[2],
        foldRange(30, 38, true, FoldSource.recovered, 'b2'),
        'R3',
      );
    });
  });
}
