/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 6a598d4a,
// src/vs/editor/test/common/viewModel/prefixSumComputer.test.ts.
// All 48 upstream tests run against both implementations. The JS-only
// disposable-leak suite hook is not applicable to these non-disposable classes.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/vs/editor/common/model/prefix_sum_computer.dart';

typedef _TestPrefixSumComputer = ({
  int Function() getTotalSum,
  int? Function(int) getPrefixSum,
  PrefixSumIndexOfResult Function(num) getIndexOf,
  void Function(int, int) setValue,
  void Function(int, List<int>) insertValues,
  void Function(int, int) removeValues,
});

Uint32List _toUint32Array(List<int> values) => Uint32List.fromList([
  for (final value in values)
    value < 0
        ? 0
        : value > 0xffffffff
        ? 0xffffffff
        : value.toSigned(32),
]);

List<_TestPrefixSumComputer> _createBoth(List<int> values) {
  final psc = PrefixSumComputer(_toUint32Array(values));
  final ct = ConstantTimePrefixSumComputer([...values]);
  return [
    (
      getTotalSum: psc.getTotalSum,
      getPrefixSum: (count) => count == 0 ? 0 : psc.getPrefixSum(count - 1),
      getIndexOf: psc.getIndexOf,
      setValue: psc.setValue,
      insertValues: (index, values) {
        psc.insertValues(index, _toUint32Array(values));
      },
      removeValues: psc.removeValues,
    ),
    (
      getTotalSum: ct.getTotalSum,
      getPrefixSum: ct.getPrefixSum,
      getIndexOf: ct.getIndexOf,
      setValue: ct.setValue,
      insertValues: ct.insertValues,
      removeValues: ct.removeValues,
    ),
  ];
}

void _forBoth(
  List<int> values,
  void Function(_TestPrefixSumComputer) callback,
) {
  for (final psc in _createBoth(values)) {
    callback(psc);
  }
}

void _expectIndexOf(
  PrefixSumIndexOfResult actual,
  PrefixSumIndexOfResult expected,
) {
  expect(
    (actual.index, actual.remainder),
    (expected.index, expected.remainder),
  );
}

void main() {
  group('PrefixSumComputer uint and cache regressions', () {
    test('typed values and inserted values wrap rather than saturate', () {
      final psc = PrefixSumComputer(Uint32List.fromList([-1, 0x100000001]));
      expect(psc.getCount(), 2);
      expect(psc.getPrefixSum(0), 0xffffffff);
      expect(psc.getTotalSum(), 0);
      expect(
        psc.insertValues(1, Uint32List.fromList([-2, 0x100000003])),
        isTrue,
      );
      expect(psc.getCount(), 4);
      expect(
        [for (var i = 0; i < 4; i++) psc.getPrefixSum(i)],
        [0xffffffff, 0xfffffffd, 0, 1],
      );
    });

    test('prefix overflow and binary search match the pinned typed arrays', () {
      final psc = PrefixSumComputer(
        Uint32List.fromList([0xffffffff, 2, 0x80000000]),
      );
      expect(psc.getPrefixSum(0), 0xffffffff);
      expect(psc.getPrefixSum(1), 1);
      expect(psc.getTotalSum(), 0x80000001);
      _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(1, 1));
      _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(2, 0));
      _expectIndexOf(
        psc.getIndexOf(0xffffffff),
        PrefixSumIndexOfResult(2, 0xfffffffe),
      );
      expect(psc.setValue(0, 1), isTrue);
      expect(psc.getTotalSum(), 0x80000003);
    });

    test('setValue uses the exact clamped, signed toUint32 conversion', () {
      // (input, stored uint32, whether a repeated write reports a change).
      // The signed `v | 0` means high-bit values report a change even if their
      // Uint32Array representation is already present. This is upstream behavior.
      for (final (input, stored, repeatedChange) in <(num, int, bool)>[
        (-1, 0, false),
        (double.negativeInfinity, 0, false),
        (double.nan, 0, false),
        (0.9, 0, false),
        (1.9, 1, false),
        (0x7fffffff, 0x7fffffff, false),
        (0x80000000, 0x80000000, true),
        (0xfffffffe, 0xfffffffe, true),
        (0xffffffff, 0xffffffff, true),
        (0x100000000, 0xffffffff, false),
        (double.infinity, 0xffffffff, false),
      ]) {
        final psc = PrefixSumComputer(Uint32List(1));
        expect(psc.setValue(0, input), stored != 0, reason: '$input');
        expect(psc.getTotalSum(), stored, reason: '$input');
        expect(psc.setValue(0, input), repeatedChange, reason: '$input');
        expect(psc.getTotalSum(), stored, reason: '$input');
      }
    });

    test('indices clamp negatives, truncate fractions, and coerce NaN', () {
      final psc = PrefixSumComputer(Uint32List.fromList([2, 3, 5]));
      expect(psc.setValue(-10, 4.9), isTrue);
      expect(psc.setValue(1.9, 6), isTrue);
      expect(psc.setValue(double.nan, 7), isTrue);
      expect(psc.getPrefixSum(-0.5), 0);
      expect(psc.getPrefixSum(double.nan), 7);
      expect(psc.getPrefixSum(1.9), 13);
      expect(psc.getPrefixSum(100), 18);
      expect(psc.getPrefixSum(double.infinity), 18);
      // Within uint32 range, high-bit inputs become negative signed indices.
      expect(psc.getPrefixSum(0x80000000), isNull);
      expect(psc.getPrefixSum(0xffffffff), isNull);
      expect(psc.getPrefixSum(0x100000000), 18);
      expect(psc.insertValues(-3, Uint32List.fromList([1])), isTrue);
      expect(psc.insertValues(1.9, Uint32List.fromList([2])), isTrue);
      expect(psc.insertValues(double.nan, Uint32List.fromList([3])), isTrue);
      expect(psc.getTotalSum(), 24);
      expect(psc.getPrefixSum(2), 6);
    });

    test('removeValues clamps and truncates its indices and counts', () {
      final psc = PrefixSumComputer(Uint32List.fromList([1, 2, 3, 4]));
      expect(psc.getTotalSum(), 10);
      expect(psc.removeValues(1, -1), isFalse);
      expect(psc.removeValues(1, double.nan), isFalse);
      expect(psc.removeValues(1.9, 1.9), isTrue);
      expect(psc.getTotalSum(), 8);
      expect(psc.removeValues(-5, 1), isTrue);
      expect(psc.getTotalSum(), 7);
      expect(psc.removeValues(double.nan, double.infinity), isTrue);
      expect(psc.getCount(), 0);
      expect(psc.getTotalSum(), 0);
    });

    test('uint32 maximum count retains the upstream signed coercion quirk', () {
      final psc = PrefixSumComputer(Uint32List.fromList([1, 2, 3]));
      expect(psc.getTotalSum(), 6);
      // 0xffffffff is converted to -1, so this grows the typed array.
      expect(psc.removeValues(1, 0xffffffff), isTrue);
      expect(psc.getCount(), 4);
      expect([for (var i = 0; i < 4; i++) psc.getPrefixSum(i)], [1, 2, 4, 7]);
      // Just beyond the maximum is instead clamped to positive 0xffffffff.
      expect(psc.removeValues(1, 0x100000000), isTrue);
      expect(psc.getCount(), 1);
      expect(psc.getTotalSum(), 1);
    });

    test('mutation flags, count, and ignored out-of-bounds typed writes', () {
      final psc = PrefixSumComputer(Uint32List.fromList([1, 2, 3]));
      expect(psc.getTotalSum(), 6);
      expect(psc.setValue(1, 2), isFalse);
      expect(psc.insertValues(1, Uint32List(0)), isFalse);
      expect(psc.removeValues(1, 0), isFalse);
      expect(psc.removeValues(3, 1), isFalse);
      expect(psc.setValue(3, 9), isTrue);
      expect(psc.getCount(), 3);
      expect(psc.getTotalSum(), 6);
      expect(psc.removeValues(1, 99), isTrue);
      expect(psc.getCount(), 1);
      expect(psc.getTotalSum(), 1);
      expect(psc.removeValues(0, 1), isTrue);
      expect(psc.removeValues(0, 1), isFalse);
      expect(psc.getCount(), 0);
    });

    test('inclusive prefixes, empty lookups, and undefined array entries', () {
      final psc = PrefixSumComputer(Uint32List(0));
      expect(psc.getTotalSum(), 0);
      expect(psc.getPrefixSum(-1), 0);
      expect(psc.getPrefixSum(0), isNull);
      _expectIndexOf(psc.getIndexOf(7), PrefixSumIndexOfResult(0, 7));
      final ct = ConstantTimePrefixSumComputer([]);
      expect(ct.getPrefixSum(0), 0);
      expect(ct.getPrefixSum(1), isNull);
      _expectIndexOf(ct.getIndexOf(7), PrefixSumIndexOfResult(0, 7));
      psc.insertValues(0, Uint32List.fromList([2, 3]));
      ct.insertValues(0, [2, 3]);
      expect(psc.getPrefixSum(0), 2);
      expect(psc.getPrefixSum(1), 5);
      expect(psc.getPrefixSum(2), 5);
      expect(ct.getPrefixSum(1), 2);
      expect(ct.getPrefixSum(2), 5);
      expect(ct.getPrefixSum(3), isNull);
      expect(ct.getPrefixSum(-1), isNull);
    });

    test('binary lookup floors while constant-time lookup uses exact keys', () {
      final psc = PrefixSumComputer(Uint32List.fromList([2, 3, 1]));
      final ct = ConstantTimePrefixSumComputer([2, 3, 1]);
      _expectIndexOf(psc.getIndexOf(3.9), PrefixSumIndexOfResult(1, 1));
      _expectIndexOf(ct.getIndexOf(3.9), PrefixSumIndexOfResult(2, -1.1));
      _expectIndexOf(psc.getIndexOf(-0.1), PrefixSumIndexOfResult(0, -1));
      _expectIndexOf(ct.getIndexOf(-1), PrefixSumIndexOfResult(2, -6));
      _expectIndexOf(psc.getIndexOf(6), PrefixSumIndexOfResult(2, 1));
      _expectIndexOf(ct.getIndexOf(6), PrefixSumIndexOfResult(2, 1));
      _expectIndexOf(psc.getIndexOf(9), PrefixSumIndexOfResult(2, 4));
      _expectIndexOf(ct.getIndexOf(9), PrefixSumIndexOfResult(2, 4));
      expect(psc.getIndexOf(double.nan).index, 1);
      expect(psc.getIndexOf(double.nan).remainder, isNaN);
      expect(ct.getIndexOf(double.nan).index, 2);
      expect(ct.getIndexOf(double.nan).remainder, isNaN);
      _expectIndexOf(
        psc.getIndexOf(double.infinity),
        PrefixSumIndexOfResult(2, double.infinity),
      );
      _expectIndexOf(
        ct.getIndexOf(double.infinity),
        PrefixSumIndexOfResult(2, double.infinity),
      );
      _expectIndexOf(
        psc.getIndexOf(double.negativeInfinity),
        PrefixSumIndexOfResult(0, double.negativeInfinity),
      );
      _expectIndexOf(
        ct.getIndexOf(double.negativeInfinity),
        PrefixSumIndexOfResult(2, double.negativeInfinity),
      );
    });

    test('mutations before and after a partially cached prefix', () {
      _forBoth([1, 2, 3, 4], (psc) {
        expect(psc.getPrefixSum(2), 3);
        psc.setValue(3, 5);
        psc.insertValues(3, [2]);
        expect(psc.getPrefixSum(3), 6);
        psc.removeValues(1, 2);
        expect(psc.getPrefixSum(2), 3);
        expect(psc.getTotalSum(), 8);
        _expectIndexOf(psc.getIndexOf(3), PrefixSumIndexOfResult(2, 0));
        psc.insertValues(0, [4]);
        expect(psc.getTotalSum(), 12);
        psc.removeValues(0, 4);
        expect(psc.getTotalSum(), 0);
        psc.insertValues(0, [3]);
        expect(psc.getPrefixSum(1), 3);
      });
    });

    test('typed constructor storage aliases until a resize', () {
      final values = Uint32List.fromList([1, 2]);
      final psc = PrefixSumComputer(values);
      values[0] = 3;
      expect(psc.getTotalSum(), 5);
      psc.setValue(1, 4);
      expect(values, [3, 4]);
      expect(psc.getTotalSum(), 7);
      psc.insertValues(1, Uint32List.fromList([2]));
      psc.setValue(0, 5);
      expect(values, [3, 4]);
      expect(psc.getTotalSum(), 11);
    });

    test(
      'constant-time setValue can append without creating sparse entries',
      () {
        final values = <int>[];
        final ct = ConstantTimePrefixSumComputer(values);
        expect(ct.getTotalSum(), 0);
        ct.setValue(0, 2);
        expect(values, [2]);
        expect(ct.getTotalSum(), 2);
        ct.setValue(1, 0);
        ct.setValue(2, 3);
        expect(values, [2, 0, 3]);
        expect(ct.getTotalSum(), 5);
        expect(ct.getPrefixSum(2), 2);
        _expectIndexOf(ct.getIndexOf(2), PrefixSumIndexOfResult(2, 0));
        ct.setValue(2, 1);
        expect(ct.getTotalSum(), 3);
      },
    );

    test(
      'constant-time storage aliases through splice but not arrayInsert',
      () {
        final values = [1, 2, 3];
        final ct = ConstantTimePrefixSumComputer(values);
        values[0] = 4;
        expect(ct.getTotalSum(), 9);
        ct.setValue(1, 5);
        expect(values, [4, 5, 3]);
        ct.removeValues(0, 1);
        expect(values, [5, 3]);
        expect(ct.getTotalSum(), 8);
        ct.insertValues(1, [2]);
        ct.setValue(0, 6);
        expect(values, [5, 3]);
        expect(ct.getTotalSum(), 11);
      },
    );
  });

  group('Editor ViewModel - PrefixSumComputer', () {
    test('comprehensive setValue and getIndexOf', () {
      _forBoth([1, 1, 2, 1, 3], (psc) {
        expect(psc.getTotalSum(), 8);
        expect(psc.getPrefixSum(0), 0);
        expect(psc.getPrefixSum(1), 1);
        expect(psc.getPrefixSum(2), 2);
        expect(psc.getPrefixSum(3), 4);
        expect(psc.getPrefixSum(4), 5);
        expect(psc.getPrefixSum(5), 8);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(1, 0));
        _expectIndexOf(psc.getIndexOf(2), PrefixSumIndexOfResult(2, 0));
        _expectIndexOf(psc.getIndexOf(3), PrefixSumIndexOfResult(2, 1));
        _expectIndexOf(psc.getIndexOf(4), PrefixSumIndexOfResult(3, 0));
        _expectIndexOf(psc.getIndexOf(5), PrefixSumIndexOfResult(4, 0));
        _expectIndexOf(psc.getIndexOf(6), PrefixSumIndexOfResult(4, 1));
        _expectIndexOf(psc.getIndexOf(7), PrefixSumIndexOfResult(4, 2));
        _expectIndexOf(psc.getIndexOf(8), PrefixSumIndexOfResult(4, 3));

        // [1, 2, 2, 1, 3]
        psc.setValue(1, 2);
        expect(psc.getTotalSum(), 9);
        expect(psc.getPrefixSum(1), 1);
        expect(psc.getPrefixSum(2), 3);
        expect(psc.getPrefixSum(3), 5);
        expect(psc.getPrefixSum(4), 6);
        expect(psc.getPrefixSum(5), 9);

        // [1, 0, 2, 1, 3]
        psc.setValue(1, 0);
        expect(psc.getTotalSum(), 7);
        expect(psc.getPrefixSum(1), 1);
        expect(psc.getPrefixSum(2), 1);
        expect(psc.getPrefixSum(3), 3);
        expect(psc.getPrefixSum(4), 4);
        expect(psc.getPrefixSum(5), 7);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(2, 0));
        _expectIndexOf(psc.getIndexOf(2), PrefixSumIndexOfResult(2, 1));
        _expectIndexOf(psc.getIndexOf(3), PrefixSumIndexOfResult(3, 0));
        _expectIndexOf(psc.getIndexOf(4), PrefixSumIndexOfResult(4, 0));
        _expectIndexOf(psc.getIndexOf(5), PrefixSumIndexOfResult(4, 1));
        _expectIndexOf(psc.getIndexOf(6), PrefixSumIndexOfResult(4, 2));

        // [1, 0, 0, 1, 3]
        psc.setValue(2, 0);
        expect(psc.getTotalSum(), 5);
        expect(psc.getPrefixSum(1), 1);
        expect(psc.getPrefixSum(2), 1);
        expect(psc.getPrefixSum(3), 1);
        expect(psc.getPrefixSum(4), 2);
        expect(psc.getPrefixSum(5), 5);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(3, 0));
        _expectIndexOf(psc.getIndexOf(2), PrefixSumIndexOfResult(4, 0));
        _expectIndexOf(psc.getIndexOf(3), PrefixSumIndexOfResult(4, 1));
        _expectIndexOf(psc.getIndexOf(4), PrefixSumIndexOfResult(4, 2));

        // [1, 0, 0, 0, 3]
        psc.setValue(3, 0);
        expect(psc.getTotalSum(), 4);
        expect(psc.getPrefixSum(1), 1);
        expect(psc.getPrefixSum(2), 1);
        expect(psc.getPrefixSum(3), 1);
        expect(psc.getPrefixSum(4), 1);
        expect(psc.getPrefixSum(5), 4);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(4, 0));
        _expectIndexOf(psc.getIndexOf(2), PrefixSumIndexOfResult(4, 1));
        _expectIndexOf(psc.getIndexOf(3), PrefixSumIndexOfResult(4, 2));

        // [1, 1, 0, 1, 1]
        psc.setValue(1, 1);
        psc.setValue(3, 1);
        psc.setValue(4, 1);
        expect(psc.getTotalSum(), 4);
        expect(psc.getPrefixSum(1), 1);
        expect(psc.getPrefixSum(2), 2);
        expect(psc.getPrefixSum(3), 2);
        expect(psc.getPrefixSum(4), 3);
        expect(psc.getPrefixSum(5), 4);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(1, 0));
        _expectIndexOf(psc.getIndexOf(2), PrefixSumIndexOfResult(3, 0));
        _expectIndexOf(psc.getIndexOf(3), PrefixSumIndexOfResult(4, 0));
      });
    });

    // --- getTotalSum ---

    test('getTotalSum with typical values', () {
      _forBoth([1, 1, 2, 1, 3], (psc) => expect(psc.getTotalSum(), 8));
      _forBoth([10], (psc) => expect(psc.getTotalSum(), 10));
      _forBoth([5, 5, 5], (psc) => expect(psc.getTotalSum(), 15));
    });

    test('getTotalSum with all zeroes', () {
      _forBoth([0, 0, 0], (psc) => expect(psc.getTotalSum(), 0));
      _forBoth([0], (psc) => expect(psc.getTotalSum(), 0));
    });

    test('getTotalSum with empty array', () {
      _forBoth([], (psc) => expect(psc.getTotalSum(), 0));
    });

    test('getTotalSum with single element', () {
      _forBoth([0], (psc) => expect(psc.getTotalSum(), 0));
      _forBoth([1], (psc) => expect(psc.getTotalSum(), 1));
      _forBoth([100], (psc) => expect(psc.getTotalSum(), 100));
    });

    // --- getPrefixSum ---

    test('getPrefixSum with typical values', () {
      _forBoth([1, 1, 2, 1, 3], (psc) {
        expect(psc.getPrefixSum(0), 0);
        expect(psc.getPrefixSum(1), 1);
        expect(psc.getPrefixSum(2), 2);
        expect(psc.getPrefixSum(3), 4);
        expect(psc.getPrefixSum(4), 5);
        expect(psc.getPrefixSum(5), 8);
      });
    });

    test('getPrefixSum with all zeroes', () {
      _forBoth([0, 0, 0], (psc) {
        expect(psc.getPrefixSum(0), 0);
        expect(psc.getPrefixSum(1), 0);
        expect(psc.getPrefixSum(2), 0);
        expect(psc.getPrefixSum(3), 0);
      });
    });

    test('getPrefixSum with single element', () {
      _forBoth([7], (psc) {
        expect(psc.getPrefixSum(0), 0);
        expect(psc.getPrefixSum(1), 7);
      });
    });

    test('getPrefixSum with empty array', () {
      _forBoth([], (psc) {
        expect(psc.getPrefixSum(0), 0);
      });
    });

    test('getPrefixSum with leading/trailing zeroes', () {
      _forBoth([0, 0, 3, 0, 0], (psc) {
        expect(psc.getPrefixSum(0), 0);
        expect(psc.getPrefixSum(1), 0);
        expect(psc.getPrefixSum(2), 0);
        expect(psc.getPrefixSum(3), 3);
        expect(psc.getPrefixSum(4), 3);
        expect(psc.getPrefixSum(5), 3);
      });
    });

    // --- getIndexOf ---

    test('getIndexOf with typical values', () {
      _forBoth([1, 1, 2, 1, 3], (psc) {
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(1, 0));
        _expectIndexOf(psc.getIndexOf(2), PrefixSumIndexOfResult(2, 0));
        _expectIndexOf(psc.getIndexOf(3), PrefixSumIndexOfResult(2, 1));
        _expectIndexOf(psc.getIndexOf(4), PrefixSumIndexOfResult(3, 0));
        _expectIndexOf(psc.getIndexOf(5), PrefixSumIndexOfResult(4, 0));
        _expectIndexOf(psc.getIndexOf(6), PrefixSumIndexOfResult(4, 1));
        _expectIndexOf(psc.getIndexOf(7), PrefixSumIndexOfResult(4, 2));
        _expectIndexOf(psc.getIndexOf(8), PrefixSumIndexOfResult(4, 3));
      });
    });

    test('getIndexOf with all zeroes', () {
      _forBoth([0, 0, 0], (psc) {
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(2, 0));
      });
    });

    test('getIndexOf with single zero', () {
      _forBoth([0], (psc) {
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
      });
    });

    test('getIndexOf with single element', () {
      _forBoth([5], (psc) {
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(0, 1));
        _expectIndexOf(psc.getIndexOf(4), PrefixSumIndexOfResult(0, 4));
      });
    });

    test('getIndexOf with leading zeroes', () {
      _forBoth([0, 0, 3], (psc) {
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(2, 0));
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(2, 1));
        _expectIndexOf(psc.getIndexOf(2), PrefixSumIndexOfResult(2, 2));
      });
    });

    test('getIndexOf with trailing zeroes', () {
      _forBoth([3, 0, 0], (psc) {
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(0, 1));
        _expectIndexOf(psc.getIndexOf(2), PrefixSumIndexOfResult(0, 2));
      });
    });

    test('getIndexOf with interleaved zeroes', () {
      _forBoth([0, 1, 0, 2, 0], (psc) {
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(1, 0));
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(3, 0));
        _expectIndexOf(psc.getIndexOf(2), PrefixSumIndexOfResult(3, 1));
      });
    });

    test('getIndexOf with all ones', () {
      _forBoth([1, 1, 1, 1, 1], (psc) {
        for (var i = 0; i < 5; i++) {
          _expectIndexOf(psc.getIndexOf(i), PrefixSumIndexOfResult(i, 0));
        }
      });
    });

    test('getIndexOf with large value in single element', () {
      _forBoth([1000], (psc) {
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(500), PrefixSumIndexOfResult(0, 500));
        _expectIndexOf(psc.getIndexOf(999), PrefixSumIndexOfResult(0, 999));
      });
    });

    // --- setValue ---

    test('setValue no-op when value unchanged', () {
      _forBoth([1, 2, 3], (psc) {
        expect(psc.getTotalSum(), 6);
        psc.setValue(1, 2);
        expect(psc.getTotalSum(), 6);
      });
    });

    test('setValue increase', () {
      _forBoth([1, 2, 3], (psc) {
        psc.setValue(1, 5);
        expect(psc.getTotalSum(), 9);
        expect(psc.getPrefixSum(2), 6);
        expect(psc.getPrefixSum(3), 9);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(1, 0));
        _expectIndexOf(psc.getIndexOf(5), PrefixSumIndexOfResult(1, 4));
        _expectIndexOf(psc.getIndexOf(6), PrefixSumIndexOfResult(2, 0));
      });
    });

    test('setValue decrease', () {
      _forBoth([1, 5, 3], (psc) {
        psc.setValue(1, 2);
        expect(psc.getTotalSum(), 6);
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(1, 0));
        _expectIndexOf(psc.getIndexOf(2), PrefixSumIndexOfResult(1, 1));
        _expectIndexOf(psc.getIndexOf(3), PrefixSumIndexOfResult(2, 0));
      });
    });

    test('setValue to zero', () {
      _forBoth([1, 2, 3], (psc) {
        psc.setValue(1, 0);
        expect(psc.getTotalSum(), 4);
        expect(psc.getPrefixSum(2), 1);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(2, 0));
      });
    });

    test('setValue from zero', () {
      _forBoth([0, 0, 0], (psc) {
        psc.setValue(1, 3);
        expect(psc.getTotalSum(), 3);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(1, 0));
        _expectIndexOf(psc.getIndexOf(2), PrefixSumIndexOfResult(1, 2));
      });
    });

    test('setValue on first element', () {
      _forBoth([1, 2, 3], (psc) {
        psc.setValue(0, 10);
        expect(psc.getTotalSum(), 15);
        expect(psc.getPrefixSum(1), 10);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(9), PrefixSumIndexOfResult(0, 9));
        _expectIndexOf(psc.getIndexOf(10), PrefixSumIndexOfResult(1, 0));
      });
    });

    test('setValue on last element', () {
      _forBoth([1, 2, 3], (psc) {
        psc.setValue(2, 10);
        expect(psc.getTotalSum(), 13);
        _expectIndexOf(psc.getIndexOf(3), PrefixSumIndexOfResult(2, 0));
        _expectIndexOf(psc.getIndexOf(12), PrefixSumIndexOfResult(2, 9));
      });
    });

    test('set all values to zero then restore', () {
      _forBoth([1, 2, 3], (psc) {
        psc.setValue(0, 0);
        psc.setValue(1, 0);
        psc.setValue(2, 0);
        expect(psc.getTotalSum(), 0);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(2, 0));

        psc.setValue(0, 4);
        expect(psc.getTotalSum(), 4);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(3), PrefixSumIndexOfResult(0, 3));
      });
    });

    test('setValue multiple times on same index', () {
      _forBoth([1, 1, 1], (psc) {
        psc.setValue(1, 5);
        psc.setValue(1, 2);
        psc.setValue(1, 10);
        expect(psc.getTotalSum(), 12);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(1, 0));
        _expectIndexOf(psc.getIndexOf(10), PrefixSumIndexOfResult(1, 9));
        _expectIndexOf(psc.getIndexOf(11), PrefixSumIndexOfResult(2, 0));
      });
    });

    // --- insertValues ---

    test('insertValues at beginning', () {
      _forBoth([3, 4], (psc) {
        psc.insertValues(0, [1, 2]);
        expect(psc.getTotalSum(), 10);
        expect(psc.getPrefixSum(1), 1);
        expect(psc.getPrefixSum(2), 3);
        expect(psc.getPrefixSum(3), 6);
        expect(psc.getPrefixSum(4), 10);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(1, 0));
        _expectIndexOf(psc.getIndexOf(3), PrefixSumIndexOfResult(2, 0));
      });
    });

    test('insertValues at end', () {
      _forBoth([1, 2], (psc) {
        psc.insertValues(2, [3, 4]);
        expect(psc.getTotalSum(), 10);
        expect(psc.getPrefixSum(3), 6);
        expect(psc.getPrefixSum(4), 10);
      });
    });

    test('insertValues in the middle', () {
      _forBoth([1, 4], (psc) {
        psc.insertValues(1, [2, 3]);
        expect(psc.getTotalSum(), 10);
        expect(psc.getPrefixSum(1), 1);
        expect(psc.getPrefixSum(2), 3);
        expect(psc.getPrefixSum(3), 6);
        expect(psc.getPrefixSum(4), 10);
      });
    });

    test('insertValues with zeroes', () {
      _forBoth([1, 2], (psc) {
        psc.insertValues(1, [0, 0]);
        expect(psc.getTotalSum(), 3);
        expect(psc.getPrefixSum(1), 1);
        expect(psc.getPrefixSum(2), 1);
        expect(psc.getPrefixSum(3), 1);
        expect(psc.getPrefixSum(4), 3);
      });
    });

    test('insertValues into all-zeroes', () {
      _forBoth([0, 0, 0], (psc) {
        psc.insertValues(1, [2, 3]);
        expect(psc.getTotalSum(), 5);
        expect(psc.getPrefixSum(1), 0);
        expect(psc.getPrefixSum(2), 2);
        expect(psc.getPrefixSum(3), 5);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(1, 0));
        _expectIndexOf(psc.getIndexOf(2), PrefixSumIndexOfResult(2, 0));
        _expectIndexOf(psc.getIndexOf(4), PrefixSumIndexOfResult(2, 2));
      });
    });

    test('insertValues into empty computer', () {
      _forBoth([], (psc) {
        psc.insertValues(0, [5, 3]);
        expect(psc.getTotalSum(), 8);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(4), PrefixSumIndexOfResult(0, 4));
        _expectIndexOf(psc.getIndexOf(5), PrefixSumIndexOfResult(1, 0));
      });
    });

    // --- removeValues ---

    test('removeValues from beginning', () {
      _forBoth([1, 2, 3, 4], (psc) {
        psc.removeValues(0, 2);
        expect(psc.getTotalSum(), 7);
        expect(psc.getPrefixSum(1), 3);
        expect(psc.getPrefixSum(2), 7);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(3), PrefixSumIndexOfResult(1, 0));
      });
    });

    test('removeValues from end', () {
      _forBoth([1, 2, 3, 4], (psc) {
        psc.removeValues(2, 2);
        expect(psc.getTotalSum(), 3);
        expect(psc.getPrefixSum(1), 1);
        expect(psc.getPrefixSum(2), 3);
      });
    });

    test('removeValues from the middle', () {
      _forBoth([1, 2, 3, 4], (psc) {
        psc.removeValues(1, 2);
        expect(psc.getTotalSum(), 5);
        expect(psc.getPrefixSum(1), 1);
        expect(psc.getPrefixSum(2), 5);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(1, 0));
        _expectIndexOf(psc.getIndexOf(4), PrefixSumIndexOfResult(1, 3));
      });
    });

    test('removeValues all', () {
      _forBoth([1, 2, 3], (psc) {
        psc.removeValues(0, 3);
        expect(psc.getTotalSum(), 0);
      });
    });

    test('removeValues single element', () {
      _forBoth([5, 10, 15], (psc) {
        psc.removeValues(1, 1);
        expect(psc.getTotalSum(), 20);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(5), PrefixSumIndexOfResult(1, 0));
        _expectIndexOf(psc.getIndexOf(19), PrefixSumIndexOfResult(1, 14));
      });
    });

    test('removeValues zero-valued elements', () {
      _forBoth([0, 0, 5, 0, 0], (psc) {
        psc.removeValues(0, 2);
        expect(psc.getTotalSum(), 5);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(4), PrefixSumIndexOfResult(0, 4));
      });
    });

    // --- combined operations ---

    test('insert then remove', () {
      _forBoth([1, 2, 3], (psc) {
        psc.insertValues(1, [10, 20]);
        expect(psc.getTotalSum(), 36);
        psc.removeValues(1, 2);
        expect(psc.getTotalSum(), 6);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(1, 0));
        _expectIndexOf(psc.getIndexOf(3), PrefixSumIndexOfResult(2, 0));
      });
    });

    test('remove then insert at same position', () {
      _forBoth([1, 2, 3], (psc) {
        psc.removeValues(1, 1);
        psc.insertValues(1, [5]);
        expect(psc.getTotalSum(), 9);
        _expectIndexOf(psc.getIndexOf(1), PrefixSumIndexOfResult(1, 0));
        _expectIndexOf(psc.getIndexOf(5), PrefixSumIndexOfResult(1, 4));
        _expectIndexOf(psc.getIndexOf(6), PrefixSumIndexOfResult(2, 0));
      });
    });

    test('setValue then insert then remove', () {
      _forBoth([1, 1, 1], (psc) {
        psc.setValue(0, 5);
        psc.insertValues(1, [10]);
        psc.removeValues(3, 1);
        // [5, 10, 1]
        expect(psc.getTotalSum(), 16);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(4), PrefixSumIndexOfResult(0, 4));
        _expectIndexOf(psc.getIndexOf(5), PrefixSumIndexOfResult(1, 0));
        _expectIndexOf(psc.getIndexOf(14), PrefixSumIndexOfResult(1, 9));
        _expectIndexOf(psc.getIndexOf(15), PrefixSumIndexOfResult(2, 0));
      });
    });

    test('multiple queries between mutations are consistent', () {
      _forBoth([2, 3, 5], (psc) {
        expect(psc.getTotalSum(), 10);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));

        psc.setValue(1, 0);
        expect(psc.getTotalSum(), 7);
        _expectIndexOf(psc.getIndexOf(2), PrefixSumIndexOfResult(2, 0));

        psc.setValue(1, 3);
        expect(psc.getTotalSum(), 10);
        _expectIndexOf(psc.getIndexOf(2), PrefixSumIndexOfResult(1, 0));
      });
    });

    // --- edge cases ---

    test('large values', () {
      _forBoth([100, 200, 300], (psc) {
        expect(psc.getTotalSum(), 600);
        expect(psc.getPrefixSum(1), 100);
        expect(psc.getPrefixSum(2), 300);
        expect(psc.getPrefixSum(3), 600);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(0, 0));
        _expectIndexOf(psc.getIndexOf(99), PrefixSumIndexOfResult(0, 99));
        _expectIndexOf(psc.getIndexOf(100), PrefixSumIndexOfResult(1, 0));
        _expectIndexOf(psc.getIndexOf(299), PrefixSumIndexOfResult(1, 199));
        _expectIndexOf(psc.getIndexOf(300), PrefixSumIndexOfResult(2, 0));
        _expectIndexOf(psc.getIndexOf(599), PrefixSumIndexOfResult(2, 299));
      });
    });

    test('many elements', () {
      _forBoth(List<int>.filled(100, 1), (psc) {
        expect(psc.getTotalSum(), 100);
        expect(psc.getPrefixSum(50), 50);

        for (var i = 0; i < 100; i++) {
          _expectIndexOf(psc.getIndexOf(i), PrefixSumIndexOfResult(i, 0));
        }
      });
    });

    test('many elements all zeroes', () {
      _forBoth(List<int>.filled(100, 0), (psc) {
        expect(psc.getTotalSum(), 0);
        for (var i = 0; i <= 100; i++) {
          expect(psc.getPrefixSum(i), 0);
        }
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(99, 0));
      });
    });

    test('setValue between queries re-validates correctly', () {
      _forBoth([1, 1, 1, 1, 1], (psc) {
        expect(psc.getTotalSum(), 5);

        psc.setValue(2, 10);
        expect(psc.getTotalSum(), 14);
        expect(psc.getPrefixSum(3), 12);
        _expectIndexOf(psc.getIndexOf(2), PrefixSumIndexOfResult(2, 0));
        _expectIndexOf(psc.getIndexOf(11), PrefixSumIndexOfResult(2, 9));
        _expectIndexOf(psc.getIndexOf(12), PrefixSumIndexOfResult(3, 0));
        _expectIndexOf(psc.getIndexOf(13), PrefixSumIndexOfResult(4, 0));

        psc.setValue(0, 0);
        expect(psc.getTotalSum(), 13);
        _expectIndexOf(psc.getIndexOf(0), PrefixSumIndexOfResult(1, 0));
      });
    });
  });
}
