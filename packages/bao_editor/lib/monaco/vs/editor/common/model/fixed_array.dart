/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/model/fixedArray.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971.

/// An array that avoids being sparse by always filling up unused indices with
/// a default value.
class FixedArray<T> {
  FixedArray(this._default);

  final T _default;
  List<T> _store = [];

  T get(int index) => index < _store.length ? _store[index] : _default;

  void set(int index, T value) {
    while (index >= _store.length) {
      _store.add(_default);
    }
    _store[index] = value;
  }

  void replace(int index, int oldLength, int newLength) {
    if (index >= _store.length) return;

    if (oldLength == 0) {
      insert(index, newLength);
      return;
    } else if (newLength == 0) {
      delete(index, oldLength);
      return;
    }

    // JS `slice` clamps an end past the array.
    final after = index + oldLength < _store.length
        ? _store.sublist(index + oldLength)
        : <T>[];
    _store = [
      ..._store.sublist(0, index),
      for (var i = 0; i < newLength; i++) _default,
      ...after,
    ];
  }

  void delete(int deleteIndex, int deleteCount) {
    if (deleteCount == 0 || deleteIndex >= _store.length) return;
    final end = deleteIndex + deleteCount;
    _store.removeRange(deleteIndex, end < _store.length ? end : _store.length);
  }

  void insert(int insertIndex, int insertCount) {
    if (insertCount == 0 || insertIndex >= _store.length) return;
    _store.insertAll(insertIndex, [
      for (var i = 0; i < insertCount; i++) _default,
    ]);
  }
}
