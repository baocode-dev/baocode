// Copyright (c) 2016 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/CircularList.ts (c58ea36).

import 'event.dart';
import 'lifecycle.dart';

class IInsertEvent {
  IInsertEvent({required this.index, required this.amount});

  int index;
  int amount;
}

class IDeleteEvent {
  IDeleteEvent({required this.index, required this.amount});

  int index;
  int amount;
}

abstract interface class ICircularList<T> {
  abstract int length;
  abstract int maxLength;
  bool get isFull;

  Emitter<IDeleteEvent> get onDeleteEmitter;
  IEvent<IDeleteEvent> get onDelete;
  Emitter<IInsertEvent> get onInsertEmitter;
  IEvent<IInsertEvent> get onInsert;
  Emitter<int> get onTrimEmitter;
  IEvent<int> get onTrim;

  T? get(int index);
  void set(int index, T value);
  void push(T value);
  T recycle();
  T? pop();

  /// Upstream's rest parameter `...items` is the list [items].
  void splice(int start, int deleteCount, [List<T> items = const []]);
  void trimStart(int count);
  void shiftElements(int start, int count, int offset);
}

/// A list with a maximum size that wraps around when [push] is called,
/// overriding values at the start of the list.
class CircularList<T> extends Disposable implements ICircularList<T> {
  CircularList(this._maxLength)
    : _array = List<T?>.filled(_maxLength, null, growable: true) {
    onDeleteEmitter = register(Emitter<IDeleteEvent>());
    onDelete = onDeleteEmitter.event;
    onInsertEmitter = register(Emitter<IInsertEvent>());
    onInsert = onInsertEmitter.event;
    onTrimEmitter = register(Emitter<int>());
    onTrim = onTrimEmitter.event;
  }

  /// Upstream protected `_array`, the backing store; unset slots are null.
  List<T?> _array;
  int _startIndex = 0;
  int _length = 0;
  int _maxLength;

  @override
  late final Emitter<IDeleteEvent> onDeleteEmitter;
  @override
  late final IEvent<IDeleteEvent> onDelete;
  @override
  late final Emitter<IInsertEvent> onInsertEmitter;
  @override
  late final IEvent<IInsertEvent> onInsert;
  @override
  late final Emitter<int> onTrimEmitter;
  @override
  late final IEvent<int> onTrim;

  @override
  int get maxLength => _maxLength;

  @override
  set maxLength(int newMaxLength) {
    // There was no change in maxLength, return early.
    if (_maxLength == newMaxLength) {
      return;
    }

    // Reconstruct array, starting at index 0. Only transfer values from the
    // indexes 0 to length.
    final newArray = List<T?>.filled(newMaxLength, null, growable: true);
    for (var i = 0; i < _min(newMaxLength, length); i++) {
      newArray[i] = _array[_getCyclicIndex(i)];
    }
    _array = newArray;
    _maxLength = newMaxLength;
    _startIndex = 0;
  }

  @override
  int get length => _length;

  @override
  set length(int newLength) {
    if (newLength > _length) {
      for (var i = _length; i < newLength; i++) {
        _write(i, null);
      }
    }
    _length = newLength;
  }

  /// Gets the value at an index.
  ///
  /// The index reference is circular so this returns a value for any index in
  /// range; like upstream's array read, an index outside the backing store
  /// yields null.
  @override
  T? get(int index) {
    final i = _getCyclicIndex(index);
    return i >= 0 && i < _array.length ? _array[i] : null;
  }

  /// Sets the value at an index.
  ///
  /// The index reference is circular so this should always hit the backing
  /// store.
  @override
  void set(int index, T? value) {
    _write(_getCyclicIndex(index), value);
  }

  /// Pushes a new value onto the list, wrapping around to the start of the
  /// array, overriding index 0 if the maximum length is reached.
  @override
  void push(T value) {
    _write(_getCyclicIndex(_length), value);
    if (_length == _maxLength) {
      _startIndex = ++_startIndex % _maxLength;
      onTrimEmitter.fire(1);
    } else {
      _length++;
    }
  }

  /// Advances the ringbuffer index and returns the current element for
  /// recycling.
  ///
  /// The buffer must be full for this method to work; throws otherwise.
  @override
  T recycle() {
    if (_length != _maxLength) {
      throw StateError('Can only recycle when the buffer is full');
    }
    _startIndex = ++_startIndex % _maxLength;
    onTrimEmitter.fire(1);
    return _array[_getCyclicIndex(_length - 1)] as T;
  }

  /// Whether the ringbuffer is at max length.
  @override
  bool get isFull => _length == _maxLength;

  /// Removes and returns the last value on the list.
  @override
  T? pop() {
    return get(_length-- - 1);
  }

  /// Deletes and/or inserts items at a particular index (in that order).
  ///
  /// Unlike `List.replaceRange`, this does not return the deleted items, to
  /// save creating a new list. This may shift all values in the list in the
  /// worst case.
  @override
  void splice(int start, int deleteCount, [List<T> items = const []]) {
    // Delete items
    if (deleteCount != 0) {
      for (var i = start; i < _length - deleteCount; i++) {
        _write(_getCyclicIndex(i), get(i + deleteCount));
      }
      _length -= deleteCount;
      onDeleteEmitter.fire(IDeleteEvent(index: start, amount: deleteCount));
    }

    // Add items
    for (var i = _length - 1; i >= start; i--) {
      _write(_getCyclicIndex(i + items.length), get(i));
    }
    for (var i = 0; i < items.length; i++) {
      _write(_getCyclicIndex(start + i), items[i]);
    }
    if (items.isNotEmpty) {
      onInsertEmitter.fire(IInsertEvent(index: start, amount: items.length));
    }

    // Adjust length as needed
    if (_length + items.length > _maxLength) {
      final countToTrim = (_length + items.length) - _maxLength;
      _startIndex += countToTrim;
      _length = _maxLength;
      onTrimEmitter.fire(countToTrim);
    } else {
      _length += items.length;
    }
  }

  /// Trims a number of items from the start of the list.
  @override
  void trimStart(int count) {
    if (count > _length) {
      count = _length;
    }
    _startIndex += count;
    _length -= count;
    onTrimEmitter.fire(count);
  }

  @override
  void shiftElements(int start, int count, int offset) {
    if (count <= 0) {
      return;
    }
    if (start < 0 || start >= _length) {
      throw RangeError('start argument out of range');
    }
    if (start + offset < 0) {
      throw RangeError('Cannot shift elements in list beyond index 0');
    }

    if (offset > 0) {
      for (var i = count - 1; i >= 0; i--) {
        set(start + i + offset, get(start + i));
      }
      final expandListBy = (start + count + offset) - _length;
      if (expandListBy > 0) {
        _length += expandListBy;
        while (_length > _maxLength) {
          _length--;
          _startIndex++;
          onTrimEmitter.fire(1);
        }
      }
    } else {
      for (var i = 0; i < count; i++) {
        set(start + i + offset, get(start + i));
      }
    }
  }

  /// Gets the cyclic index for the specified regular index. The cyclic index
  /// can then be used on the backing array to get the element associated with
  /// the regular index.
  ///
  /// `remainder` keeps JavaScript's `%` sign for negative indices.
  int _getCyclicIndex(int index) {
    return (_startIndex + index).remainder(_maxLength);
  }

  /// Upstream's plain array write: past the end grows the array, negative
  /// indices are ignored (JavaScript stores them as properties nobody reads).
  void _write(int i, T? value) {
    if (i < 0) {
      return;
    }
    if (i < _array.length) {
      _array[i] = value;
      return;
    }
    while (_array.length < i) {
      _array.add(null);
    }
    _array.add(value);
  }

  static int _min(int a, int b) => a < b ? a : b;
}
