// Copyright (c) 2018 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/MultiKeyMap.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/xterm/common/multi_key_map.dart';

void main() {
  group('TwoKeyMap', () {
    late TwoKeyMap<Object, Object, String> map;

    setUp(() {
      map = TwoKeyMap<Object, Object, String>();
    });

    test('set, get', () {
      expect(map.get(1, 2), null);
      map.set(1, 2, 'foo');
      expect(map.get(1, 2), 'foo');
      map.set(1, 3, 'bar');
      expect(map.get(1, 2), 'foo');
      expect(map.get(1, 3), 'bar');
      map.set(2, 2, 'foo2');
      map.set(2, 3, 'bar2');
      expect(map.get(1, 2), 'foo');
      expect(map.get(1, 3), 'bar');
      expect(map.get(2, 2), 'foo2');
      expect(map.get(2, 3), 'bar2');
    });
    test('clear', () {
      expect(map.get(1, 2), null);
      map.set(1, 2, 'foo');
      expect(map.get(1, 2), 'foo');
      map.clear();
      expect(map.get(1, 2), null);
    });
  });

  group('FourKeyMap', () {
    late FourKeyMap<Object, Object, Object, Object, String> map;

    setUp(() {
      map = FourKeyMap<Object, Object, Object, Object, String>();
    });

    test('set, get', () {
      expect(map.get(1, 2, 3, 4), null);
      map.set(1, 2, 3, 4, 'foo');
      expect(map.get(1, 2, 3, 4), 'foo');
      map.set(1, 3, 3, 4, 'bar');
      expect(map.get(1, 2, 3, 4), 'foo');
      expect(map.get(1, 3, 3, 4), 'bar');
      map.set(2, 2, 3, 4, 'foo2');
      map.set(2, 3, 3, 4, 'bar2');
      expect(map.get(1, 2, 3, 4), 'foo');
      expect(map.get(1, 3, 3, 4), 'bar');
      expect(map.get(2, 2, 3, 4), 'foo2');
      expect(map.get(2, 3, 3, 4), 'bar2');
    });
    test('clear', () {
      expect(map.get(1, 2, 3, 4), null);
      map.set(1, 2, 3, 4, 'foo');
      expect(map.get(1, 2, 3, 4), 'foo');
      map.clear();
      expect(map.get(1, 2, 3, 4), null);
    });
  });
}
