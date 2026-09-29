/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 6a598d4a, src/vs/editor/common/model/prefixSumComputer.ts.

import 'dart:typed_data';

// Keep the pinned base/common/uint.ts semantics, including its signed `v | 0`
// for values within the uint32 range. Uint32List assignments then wrap these
// signed values, just as Uint32Array assignments do upstream.
int _toUint32(num value) {
  if (value < 0) return 0;
  if (value > 0xffffffff) return 0xffffffff;
  if (value.isNaN) return 0;
  return value.truncate().toSigned(32);
}

// JavaScript slice/subarray bounds are relative to the end when negative.
int _sliceIndex(int index, int length) =>
    index < 0 ? (length + index).clamp(0, length) : index.clamp(0, length);

class PrefixSumComputer {
  /// The value at each index. As upstream, the constructor retains this array.
  Uint32List _values;

  /// _prefixSum[i] = SUM(values[j]), 0 <= j <= i.
  Uint32List _prefixSum;

  /// Prefix sums through this index can be trusted.
  final Int32List _prefixSumValidIndex = Int32List(1);

  PrefixSumComputer(Uint32List values)
    : _values = values,
      _prefixSum = Uint32List(values.length) {
    _prefixSumValidIndex[0] = -1;
  }

  int getCount() => _values.length;

  bool insertValues(num insertIndex, Uint32List insertValues) {
    final index = _toUint32(insertIndex);
    final oldValues = _values;
    final oldPrefixSum = _prefixSum;
    final insertValuesLen = insertValues.length;

    if (insertValuesLen == 0) {
      return false;
    }

    _values = Uint32List(oldValues.length + insertValuesLen);
    final split = _sliceIndex(index, oldValues.length);
    _values.setRange(0, split, oldValues);
    _values.setAll(index + insertValuesLen, oldValues.sublist(split));
    _values.setAll(index, insertValues);

    if (index - 1 < _prefixSumValidIndex[0]) {
      _prefixSumValidIndex[0] = index - 1;
    }

    _prefixSum = Uint32List(_values.length);
    if (_prefixSumValidIndex[0] >= 0) {
      _prefixSum.setRange(0, _prefixSumValidIndex[0] + 1, oldPrefixSum);
    }
    return true;
  }

  bool setValue(num index, num value) {
    final valueIndex = _toUint32(index);
    final newValue = _toUint32(value);

    // Out-of-bounds typed-array reads yield undefined and writes are ignored.
    if (valueIndex >= 0 && valueIndex < _values.length) {
      if (_values[valueIndex] == newValue) {
        return false;
      }
      _values[valueIndex] = newValue;
    }
    if (valueIndex - 1 < _prefixSumValidIndex[0]) {
      _prefixSumValidIndex[0] = valueIndex - 1;
    }
    return true;
  }

  bool removeValues(num startIndex, num count) {
    final start = _toUint32(startIndex);
    var deleteCount = _toUint32(count);
    final oldValues = _values;
    final oldPrefixSum = _prefixSum;

    if (start >= oldValues.length) {
      return false;
    }

    final maxCount = oldValues.length - start;
    if (deleteCount >= maxCount) {
      deleteCount = maxCount;
    }

    if (deleteCount == 0) {
      return false;
    }

    _values = Uint32List(oldValues.length - deleteCount);
    final beforeEnd = _sliceIndex(start, oldValues.length);
    _values.setRange(0, beforeEnd, oldValues);
    _values.setAll(
      start,
      oldValues.sublist(_sliceIndex(start + deleteCount, oldValues.length)),
    );

    _prefixSum = Uint32List(_values.length);
    if (start - 1 < _prefixSumValidIndex[0]) {
      _prefixSumValidIndex[0] = start - 1;
    }
    if (_prefixSumValidIndex[0] >= 0) {
      _prefixSum.setRange(0, _prefixSumValidIndex[0] + 1, oldPrefixSum);
    }
    return true;
  }

  int getTotalSum() {
    if (_values.isEmpty) {
      return 0;
    }
    return _getPrefixSum(_values.length - 1)!;
  }

  /// Returns the sum of the first [index] + 1 items.
  ///
  /// Negative inputs return zero; oversized indices clamp to the final item.
  /// Null represents upstream's undefined typed-array result (for example,
  /// a nonnegative query on an empty computer).
  int? getPrefixSum(num index) {
    if (index < 0) {
      return 0;
    }
    return _getPrefixSum(_toUint32(index));
  }

  int? _getPrefixSum(int index) {
    if (index <= _prefixSumValidIndex[0]) {
      return _readPrefixSum(index);
    }

    var startIndex = _prefixSumValidIndex[0] + 1;
    if (startIndex == 0) {
      if (_values.isNotEmpty) {
        _prefixSum[0] = _values[0];
      }
      startIndex++;
    }

    if (index >= _values.length) {
      index = _values.length - 1;
    }

    for (var i = startIndex; i <= index; i++) {
      // Uint32List, not an unbounded integer list: prefix sums wrap at 2^32.
      // Missing typed-array operands produce NaN, stored as zero upstream.
      if (i >= 0 && i < _prefixSum.length) {
        final previous = _readPrefixSum(i - 1);
        _prefixSum[i] = previous == null ? 0 : previous + _values[i];
      }
    }
    if (index > _prefixSumValidIndex[0]) {
      _prefixSumValidIndex[0] = index;
    }
    return _readPrefixSum(index);
  }

  int? _readPrefixSum(int index) =>
      index >= 0 && index < _prefixSum.length ? _prefixSum[index] : null;

  PrefixSumIndexOfResult getIndexOf(num sum) {
    sum = sum.isFinite ? sum.floor() : sum;

    // Compute all sums (to get a fully valid prefixSum).
    getTotalSum();

    var low = 0;
    var high = _values.length - 1;
    var mid = 0;
    var midStart = 0;

    while (low <= high) {
      mid = (low + (high - low) ~/ 2).toSigned(32);
      final midStop = _prefixSum[mid];
      midStart = midStop - _values[mid];

      if (sum < midStart) {
        high = mid - 1;
      } else if (sum >= midStop) {
        low = mid + 1;
      } else {
        break;
      }
    }

    return PrefixSumIndexOfResult(mid, sum - midStart);
  }
}

/// [getIndexOf] has amortized O(1) runtime, versus O(log n) for
/// [PrefixSumComputer.getIndexOf]. Values are nonnegative integer counts.
class ConstantTimePrefixSumComputer {
  List<int> _values;
  bool _isValid = false;
  int _validEndIndex = -1;

  /// _prefixSum[i] = SUM(values[j]), 0 <= j <= i.
  final List<int> _prefixSum = [];

  /// _indexBySum[sum] = idx => _prefixSum[idx - 1] <= sum < _prefixSum[idx].
  final List<int> _indexBySum = [];

  /// Retains [values], which must be growable for removals or appending writes.
  ConstantTimePrefixSumComputer(List<int> values) : _values = values;

  int getTotalSum() {
    _ensureValid();
    return _indexBySum.length;
  }

  /// Returns the sum of the first [count] items (not through an index).
  /// Null represents an undefined upstream array entry.
  int? getPrefixSum(int count) {
    _ensureValid();
    if (count == 0) {
      return 0;
    }
    return count > 0 && count <= _prefixSum.length
        ? _prefixSum[count - 1]
        : null;
  }

  /// Returns a result such that prefixSum(result.index) + remainder = sum.
  PrefixSumIndexOfResult getIndexOf(num sum) {
    _ensureValid();
    if (!sum.isFinite ||
        sum < 0 ||
        sum >= _indexBySum.length ||
        sum != sum.truncate()) {
      // No direct array entry (including empty and all-zero arrays).
      final lastIdx = _values.isEmpty ? 0 : _values.length - 1;
      final lastPrefixSum = lastIdx > 0 ? _prefixSum[lastIdx - 1] : 0;
      return PrefixSumIndexOfResult(lastIdx, sum - lastPrefixSum);
    }
    final idx = _indexBySum[sum.toInt()];
    final viewLinesAbove = idx > 0 ? _prefixSum[idx - 1] : 0;
    return PrefixSumIndexOfResult(idx, sum - viewLinesAbove);
  }

  void removeValues(int start, int deleteCount) {
    final from = _sliceIndex(start, _values.length);
    final count = deleteCount.clamp(0, _values.length - from);
    _values.removeRange(from, from + count);
    _invalidate(start);
  }

  void insertValues(int insertIndex, List<int> insertArr) {
    // base/common/arrays.ts arrayInsert uses slice + concat (a fresh array).
    final split = _sliceIndex(insertIndex, _values.length);
    _values = [
      ..._values.sublist(0, split),
      ...insertArr,
      ..._values.sublist(split),
    ];
    _invalidate(insertIndex);
  }

  void _invalidate(int index) {
    _isValid = false;
    if (index - 1 < _validEndIndex) {
      _validEndIndex = index - 1;
    }
  }

  void _ensureValid() {
    if (_isValid) {
      return;
    }

    for (var i = _validEndIndex + 1; i < _values.length; i++) {
      final value = _values[i];
      final sumAbove = i > 0 ? _prefixSum[i - 1] : 0;
      final sum = sumAbove + value;

      if (i < _prefixSum.length) {
        _prefixSum[i] = sum;
      } else {
        _prefixSum.add(sum);
      }
      for (var j = 0; j < value; j++) {
        final index = sumAbove + j;
        if (index < _indexBySum.length) {
          _indexBySum[index] = i;
        } else {
          _indexBySum.add(i);
        }
      }
    }

    // Trim things.
    _prefixSum.length = _values.length;
    _indexBySum.length = _values.isNotEmpty ? _prefixSum.last : 0;

    // Mark as valid.
    _isValid = true;
    _validEndIndex = _values.length - 1;
  }

  void setValue(int index, int value) {
    if (index == _values.length) {
      // A write immediately after the last entry grows a JavaScript array.
      _values.add(value);
    } else {
      if (_values[index] == value) {
        return;
      }
      _values[index] = value;
    }
    _invalidate(index);
  }
}

class PrefixSumIndexOfResult {
  final int index;
  final num remainder;

  const PrefixSumIndexOfResult(this.index, this.remainder);
}
