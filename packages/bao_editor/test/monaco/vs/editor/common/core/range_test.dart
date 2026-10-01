// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/monaco/LICENSE.txt.
// Adapted from the pinned VS Code range.test.ts; additional API cases below.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';

class _RangeData implements IRange {
  const _RangeData(
    this.startLineNumber,
    this.startColumn,
    this.endLineNumber,
    this.endColumn,
  );

  @override
  final int startLineNumber;
  @override
  final int startColumn;
  @override
  final int endLineNumber;
  @override
  final int endColumn;
}

void main() {
  group('Editor Core - Range (VS Code range.test.ts)', () {
    test('empty range', () {
      final s = Range(1, 1, 1, 1);
      expect(s.startLineNumber, 1);
      expect(s.startColumn, 1);
      expect(s.endLineNumber, 1);
      expect(s.endColumn, 1);
      expect(s.isEmpty(), isTrue);
    });

    test('swap start and stop same line', () {
      final s = Range(1, 2, 1, 1);
      expect(s.startLineNumber, 1);
      expect(s.startColumn, 1);
      expect(s.endLineNumber, 1);
      expect(s.endColumn, 2);
      expect(s.isEmpty(), isFalse);
    });

    test('swap start and stop', () {
      final s = Range(2, 1, 1, 2);
      expect(s.startLineNumber, 1);
      expect(s.startColumn, 2);
      expect(s.endLineNumber, 2);
      expect(s.endColumn, 1);
      expect(s.isEmpty(), isFalse);
    });

    test('no swap same line', () {
      final s = Range(1, 1, 1, 2);
      expect(s.startLineNumber, 1);
      expect(s.startColumn, 1);
      expect(s.endLineNumber, 1);
      expect(s.endColumn, 2);
      expect(s.isEmpty(), isFalse);
    });

    test('no swap', () {
      final s = Range(1, 1, 2, 1);
      expect(s.startLineNumber, 1);
      expect(s.startColumn, 1);
      expect(s.endLineNumber, 2);
      expect(s.endColumn, 1);
      expect(s.isEmpty(), isFalse);
    });

    test('compareRangesUsingEnds', () {
      final cases = <(Range, Range, int)>[
        (Range(1, 1, 1, 3), Range(1, 2, 1, 4), -1),
        (Range(1, 1, 1, 3), Range(1, 1, 1, 4), -1),
        (Range(1, 2, 1, 3), Range(1, 1, 1, 4), -1),
        (Range(1, 1, 1, 4), Range(1, 2, 1, 4), -1),
        (Range(1, 1, 1, 4), Range(1, 1, 1, 4), 0),
        (Range(1, 2, 1, 4), Range(1, 1, 1, 4), 1),
        (Range(1, 1, 1, 5), Range(1, 2, 1, 4), 1),
        (Range(1, 1, 2, 4), Range(1, 1, 1, 4), 1),
        (Range(1, 2, 5, 1), Range(1, 1, 1, 4), 1),
      ];
      for (final (a, b, sign) in cases) {
        final result = Range.compareRangesUsingEnds(a, b);
        expect(result.sign, sign, reason: '$a versus $b');
      }
    });

    test('containsPosition', () {
      final range = Range(2, 2, 5, 10);
      final cases = <(Position, bool)>[
        (const Position(1, 3), false),
        (const Position(2, 1), false),
        (const Position(2, 2), true),
        (const Position(2, 3), true),
        (const Position(3, 1), true),
        (const Position(5, 9), true),
        (const Position(5, 10), true),
        (const Position(5, 11), false),
        (const Position(6, 1), false),
      ];
      for (final (position, expected) in cases) {
        expect(range.containsPosition(position), expected, reason: '$position');
        expect(Range.containsPositionInRange(range, position), expected);
      }
    });

    test('containsRange', () {
      final range = Range(2, 2, 5, 10);
      final cases = <(Range, bool)>[
        (Range(1, 3, 2, 2), false),
        (Range(2, 1, 2, 2), false),
        (Range(2, 2, 5, 11), false),
        (Range(2, 2, 6, 1), false),
        (Range(5, 9, 6, 1), false),
        (Range(5, 10, 6, 1), false),
        (Range(2, 2, 5, 10), true),
        (Range(2, 3, 5, 9), true),
        (Range(3, 100, 4, 100), true),
      ];
      for (final (other, expected) in cases) {
        expect(range.containsRange(other), expected, reason: '$other');
        expect(Range.containsRangeInRange(range, other), expected);
      }
    });

    test('areIntersecting', () {
      final cases = <(Range, Range, bool)>[
        (Range(2, 2, 3, 2), Range(4, 2, 5, 2), false),
        (Range(4, 2, 5, 2), Range(2, 2, 3, 2), false),
        (Range(4, 2, 5, 2), Range(5, 2, 6, 2), false),
        (Range(5, 2, 6, 2), Range(4, 2, 5, 2), false),
        (Range(2, 2, 2, 7), Range(2, 4, 2, 6), true),
        (Range(2, 2, 2, 7), Range(2, 4, 2, 9), true),
        (Range(2, 4, 2, 9), Range(2, 2, 2, 7), true),
      ];
      for (final (a, b, expected) in cases) {
        expect(Range.areIntersecting(a, b), expected, reason: '$a / $b');
      }
    });
  });

  group('Editor Core - Range (additional API)', () {
    test('strict position and range containment exclude both boundaries', () {
      final outer = Range(2, 2, 5, 10);
      expect(
        Range.strictContainsPosition(outer, const Position(2, 2)),
        isFalse,
      );
      expect(Range.strictContainsPosition(outer, const Position(2, 3)), isTrue);
      expect(Range.strictContainsPosition(outer, const Position(3, 1)), isTrue);
      expect(Range.strictContainsPosition(outer, const Position(5, 9)), isTrue);
      expect(
        Range.strictContainsPosition(outer, const Position(5, 10)),
        isFalse,
      );
      expect(
        Range.strictContainsPosition(Range(2, 2, 2, 2), const Position(2, 2)),
        isFalse,
      );
      expect(outer.strictContainsRange(Range(2, 3, 5, 9)), isTrue);
      expect(outer.strictContainsRange(Range(3, 1, 4, 1)), isTrue);
      expect(outer.strictContainsRange(Range(2, 2, 5, 9)), isFalse);
      expect(outer.strictContainsRange(Range(2, 3, 5, 10)), isFalse);
      expect(outer.strictContainsRange(Range(2, 2, 5, 10)), isFalse);
      expect(
        Range.strictContainsRangeInRange(outer, Range(1, 1, 3, 1)),
        isFalse,
      );
    });

    test('intersection returns overlap, empty meeting point, or null', () {
      final a = Range(1, 3, 3, 7);
      final b = Range(2, 1, 4, 2);
      expect(a.intersectRanges(b)?.equalsRange(Range(2, 1, 3, 7)), isTrue);
      expect(
        Range.intersectTwoRanges(b, a)?.equalsRange(Range(2, 1, 3, 7)),
        isTrue,
      );
      final touching = a.intersectRanges(Range(3, 7, 4, 1));
      expect(touching?.equalsRange(Range(3, 7, 3, 7)), isTrue);
      expect(touching?.isEmpty(), isTrue);
      expect(a.intersectRanges(Range(3, 8, 4, 1)), isNull);
      expect(a.intersectRanges(Range(4, 1, 5, 1)), isNull);
      expect(Range.intersectTwoRanges(a, a)?.equalsRange(a), isTrue);
    });

    test('union spans both ranges regardless of argument order', () {
      final a = Range(2, 3, 4, 2);
      final b = Range(2, 1, 5, 8);
      expect(a.plusRange(b).equalsRange(Range(2, 1, 5, 8)), isTrue);
      expect(Range.plusRanges(b, a).equalsRange(Range(2, 1, 5, 8)), isTrue);
      expect(
        Range.plusRanges(Range(1, 9, 3, 5), a).equalsRange(Range(1, 9, 4, 2)),
        isTrue,
      );
    });

    test(
      'touching and intersecting predicates retain upstream distinctions',
      () {
        final a = Range(1, 2, 1, 4);
        final touching = Range(1, 4, 1, 6);
        final gap = Range(1, 5, 1, 7);
        final overlap = Range(1, 3, 1, 5);
        for (final (left, right) in [(a, touching), (touching, a)]) {
          expect(Range.areIntersectingOrTouching(left, right), isTrue);
          expect(Range.areIntersecting(left, right), isFalse);
        }
        expect(Range.areIntersectingOrTouching(a, gap), isFalse);
        expect(Range.areIntersecting(a, overlap), isTrue);
        expect(Range.areOnlyIntersecting(a, gap), isTrue);
        expect(Range.areOnlyIntersecting(a, Range(1, 6, 1, 8)), isFalse);
        expect(
          Range.areOnlyIntersecting(Range(1, 1, 2, 1), Range(3, 1, 4, 1)),
          isTrue,
        );
        expect(
          Range.areOnlyIntersecting(Range(1, 1, 2, 1), Range(4, 1, 5, 1)),
          isFalse,
        );
      },
    );

    test('equality, endpoints, collapse, shift and formatting', () {
      final range = Range(2, 3, 4, 5);
      expect(range.equalsRange(const _RangeData(2, 3, 4, 5)), isTrue);
      expect(range.equalsRange(Range(2, 3, 4, 6)), isFalse);
      expect(range.equalsRange(null), isFalse);
      expect(Range.equalsRanges(null, null), isTrue);
      expect(Range.equalsRanges(null, range), isFalse);
      expect(range.getStartPosition().equals(const Position(2, 3)), isTrue);
      expect(range.getEndPosition().equals(const Position(4, 5)), isTrue);
      expect(Range.startPositionOf(range).equals(const Position(2, 3)), isTrue);
      expect(Range.endPositionOf(range).equals(const Position(4, 5)), isTrue);
      expect(range.collapseToStart().equalsRange(Range(2, 3, 2, 3)), isTrue);
      expect(range.collapseToEnd().equalsRange(Range(4, 5, 4, 5)), isTrue);
      expect(Range.collapseRangeToStart(range).isEmpty(), isTrue);
      expect(Range.collapseRangeToEnd(range).isEmpty(), isTrue);
      expect(range.delta(3).equalsRange(Range(5, 3, 7, 5)), isTrue);
      expect(
        range.setStartPosition(1, 1).equalsRange(Range(1, 1, 4, 5)),
        isTrue,
      );
      expect(range.setEndPosition(5, 6).equalsRange(Range(2, 3, 5, 6)), isTrue);
      expect(range.toString(), '[2,3 -> 4,5]');
      expect(range.isSingleLine(), isFalse);
      expect(Range.spansMultipleLines(range), isTrue);
      expect(Range(2, 1, 2, 2).isSingleLine(), isTrue);
      expect(Range.spansMultipleLines(Range(2, 1, 2, 2)), isFalse);
    });

    test('fromPositions, lift and structural checks', () {
      expect(
        Range.fromPositions(const Position(2, 3))
            .equalsRange(Range(2, 3, 2, 3)),
        isTrue,
      );
      expect(
        Range.fromPositions(
          const Position(3, 1),
          const Position(2, 5),
        ).equalsRange(Range(2, 5, 3, 1)),
        isTrue,
      );
      expect(Range.lift(null), isNull);
      final data = const _RangeData(2, 3, 4, 5);
      expect(Range.lift(data)?.equalsRange(Range(2, 3, 4, 5)), isTrue);
      expect(Range.lift(data), isA<Range>());
      expect(Range.isIRange(data), isTrue);
      expect(
        Range.isIRange({
          'startLineNumber': 2,
          'startColumn': 3,
          'endLineNumber': 4,
          'endColumn': 5,
        }),
        isTrue,
      );
      expect(
        Range.isIRange({
          'startLineNumber': 2.0,
          'startColumn': 3,
          'endLineNumber': 4,
          'endColumn': 5,
        }),
        isTrue,
      );
      expect(
        Range.isIRange({
          'startLineNumber': 2,
          'startColumn': '3',
          'endLineNumber': 4,
          'endColumn': 5,
        }),
        isFalse,
      );
      expect(Range.isIRange({'startLineNumber': 2, 'startColumn': 3}), isFalse);
      expect(Range.isIRange(null), isFalse);
    });

    test('start and end comparators sort lexicographically', () {
      final first = Range(1, 1, 2, 1);
      final short = Range(1, 1, 2, 2);
      final long = Range(1, 1, 3, 1);
      final later = Range(1, 2, 2, 1);
      expect(Range.compareRangesUsingStarts(null, null), 0);
      expect(Range.compareRangesUsingStarts(null, first), lessThan(0));
      expect(Range.compareRangesUsingStarts(first, null), greaterThan(0));
      expect(Range.compareRangesUsingStarts(first, short), lessThan(0));
      expect(Range.compareRangesUsingStarts(short, long), lessThan(0));
      expect(Range.compareRangesUsingStarts(long, later), lessThan(0));
      expect(Range.compareRangesUsingStarts(first, Range(1, 1, 2, 1)), 0);
      expect(Range.compareRangesUsingEnds(first, later), lessThan(0));
      expect(Range.compareRangesUsingEnds(first, short), lessThan(0));
      expect(Range.compareRangesUsingEnds(long, first), greaterThan(0));
      final ranges = [later, long, short, first]
        ..sort(Range.compareRangesUsingStarts);
      expect(ranges, [first, short, long, later]);
    });

    test('toJson serializes four named coordinates', () {
      final range = Range(2, 3, 4, 5);
      final expected = {
        'startLineNumber': 2,
        'startColumn': 3,
        'endLineNumber': 4,
        'endColumn': 5,
      };
      expect(range.toJson(), expected);
      expect(jsonDecode(jsonEncode(range.toJson())), expected);
    });
  });
}
