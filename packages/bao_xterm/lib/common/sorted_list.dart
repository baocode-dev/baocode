// Copyright (c) 2022 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/SortedList.ts (c58ea36).

import 'services/services.dart';
import 'task_queue.dart';

// Work variables to avoid garbage collection.
int _i = 0;

/// A generic list that is maintained in sorted order and allows values with
/// duplicate keys.
///
/// Deferred batch insertion and deletion is used to significantly reduce the
/// time it takes to insert and delete a large amount of items in succession.
/// This list is based on binary search and as such locating a key will take
/// O(log n) amortized, this includes the by key iterator.
class SortedList<T> {
  SortedList(this._getKey, ILogService logService)
    : _flushInsertedTask = IdleTaskQueue(logService),
      _flushDeletedTask = IdleTaskQueue(logService);

  final int Function(T value) _getKey;

  List<T> _array = <T>[];

  final List<T> _insertedValues = <T>[];
  final IdleTaskQueue _flushInsertedTask;
  final bool _isFlushingInserted = false;

  final List<int> _deletedIndices = <int>[];
  final IdleTaskQueue _flushDeletedTask;
  bool _isFlushingDeleted = false;

  void clear() {
    _array.clear();
    _insertedValues.clear();
    _flushInsertedTask.clear();
    _deletedIndices.clear();
    _flushDeletedTask.clear();
    _isFlushingDeleted = false;
  }

  void insert(T value) {
    _flushCleanupDeleted();
    if (_insertedValues.isEmpty) {
      _flushInsertedTask.enqueue(() => _flushInserted());
    }
    _insertedValues.add(value);
  }

  void _flushInserted() {
    // JavaScript's sort is stable, Dart's is not: sort indices, ties by index.
    final order = List<int>.generate(_insertedValues.length, (i) => i);
    order.sort((a, b) {
      final byKey = _getKey(_insertedValues[a])
          .compareTo(_getKey(_insertedValues[b]));
      return byKey != 0 ? byKey : a - b;
    });
    final sortedAddedValues = [for (final i in order) _insertedValues[i]];
    var sortedAddedValuesIndex = 0;
    var arrayIndex = 0;

    final newLength = _array.length + _insertedValues.length;
    final newArray = <T>[];

    for (var newArrayIndex = 0; newArrayIndex < newLength; newArrayIndex++) {
      if (arrayIndex >= _array.length ||
          (sortedAddedValuesIndex < sortedAddedValues.length &&
              _getKey(sortedAddedValues[sortedAddedValuesIndex]) <=
                  _getKey(_array[arrayIndex]))) {
        newArray.add(sortedAddedValues[sortedAddedValuesIndex]);
        sortedAddedValuesIndex++;
      } else {
        newArray.add(_array[arrayIndex++]);
      }
    }

    _array = newArray;
    _insertedValues.clear();
  }

  void _flushCleanupInserted() {
    if (!_isFlushingInserted && _insertedValues.isNotEmpty) {
      _flushInsertedTask.flush();
    }
  }

  bool delete(T value) {
    _flushCleanupInserted();
    if (_array.isEmpty) {
      return false;
    }
    final key = _getKey(value);
    _i = _search(key);
    if (_i == -1) {
      return false;
    }
    if (_i >= _array.length || _getKey(_array[_i]) != key) {
      return false;
    }
    do {
      if (identical(_array[_i], value)) {
        if (_deletedIndices.isEmpty) {
          _flushDeletedTask.enqueue(() => _flushDeleted());
        }
        _deletedIndices.add(_i);
        return true;
      }
    } while (++_i < _array.length && _getKey(_array[_i]) == key);
    return false;
  }

  void _flushDeleted() {
    _isFlushingDeleted = true;
    final sortedDeletedIndices = _deletedIndices..sort((a, b) => a - b);
    var sortedDeletedIndicesIndex = 0;
    final newArray = <T>[];
    for (var i = 0; i < _array.length; i++) {
      if (sortedDeletedIndicesIndex < sortedDeletedIndices.length &&
          sortedDeletedIndices[sortedDeletedIndicesIndex] == i) {
        sortedDeletedIndicesIndex++;
      } else {
        newArray.add(_array[i]);
      }
    }
    _array = newArray;
    _deletedIndices.clear();
    _isFlushingDeleted = false;
  }

  void _flushCleanupDeleted() {
    if (!_isFlushingDeleted && _deletedIndices.isNotEmpty) {
      _flushDeletedTask.flush();
    }
  }

  /// The values with [key]; the pending insertions and deletions are flushed
  /// when the iteration starts.
  Iterable<T> getKeyIterator(int key) sync* {
    _flushCleanupInserted();
    _flushCleanupDeleted();
    if (_array.isEmpty) {
      return;
    }
    _i = _search(key);
    if (_i < 0 || _i >= _array.length) {
      return;
    }
    if (_getKey(_array[_i]) != key) {
      return;
    }
    do {
      yield _array[_i];
    } while (++_i < _array.length && _getKey(_array[_i]) == key);
  }

  void forEachByKey(int key, void Function(T value) callback) {
    _flushCleanupInserted();
    _flushCleanupDeleted();
    if (_array.isEmpty) {
      return;
    }
    _i = _search(key);
    if (_i < 0 || _i >= _array.length) {
      return;
    }
    if (_getKey(_array[_i]) != key) {
      return;
    }
    do {
      callback(_array[_i]);
    } while (++_i < _array.length && _getKey(_array[_i]) == key);
  }

  Iterable<T> values() {
    _flushCleanupInserted();
    _flushCleanupDeleted();
    // Duplicate the array to avoid issues when _array changes while iterating
    return List<T>.of(_array);
  }

  int _search(int key) {
    var min = 0;
    var max = _array.length - 1;
    while (max >= min) {
      var mid = (min + max) >> 1;
      final midKey = _getKey(_array[mid]);
      if (midKey > key) {
        max = mid - 1;
      } else if (midKey < key) {
        min = mid + 1;
      } else {
        // key in list, walk to lowest duplicate
        while (mid > 0 && _getKey(_array[mid - 1]) == key) {
          mid--;
        }
        return mid;
      }
    }
    // key not in list
    // still return closest min (also used as insert position)
    return min;
  }
}
