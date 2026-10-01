// Copyright (c) 2022 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/MultiKeyMap.ts (c58ea36).
//
// Upstream's keys are `string | number` object keys; here any keys with
// `==`/`hashCode`, so `1` and `'1'` are different keys.

class TwoKeyMap<TFirst, TSecond, TValue> {
  Map<TFirst, Map<TSecond, TValue?>> _data = <TFirst, Map<TSecond, TValue?>>{};

  void set(TFirst first, TSecond second, TValue value) {
    (_data[first] ??= <TSecond, TValue?>{})[second] = value;
  }

  TValue? get(TFirst first, TSecond second) {
    return _data[first]?[second];
  }

  void clear() {
    _data = <TFirst, Map<TSecond, TValue?>>{};
  }
}

class FourKeyMap<TFirst, TSecond, TThird, TFourth, TValue> {
  final TwoKeyMap<TFirst, TSecond, TwoKeyMap<TThird, TFourth, TValue>> _data =
      TwoKeyMap<TFirst, TSecond, TwoKeyMap<TThird, TFourth, TValue>>();

  void set(
    TFirst first,
    TSecond second,
    TThird third,
    TFourth fourth,
    TValue value,
  ) {
    if (_data.get(first, second) == null) {
      _data.set(first, second, TwoKeyMap<TThird, TFourth, TValue>());
    }
    _data.get(first, second)!.set(third, fourth, value);
  }

  TValue? get(TFirst first, TSecond second, TThird third, TFourth fourth) {
    return _data.get(first, second)?.get(third, fourth);
  }

  void clear() {
    _data.clear();
  }
}
