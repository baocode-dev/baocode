// Copyright (c) 2018 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Adapted from xterm.js src/common/SortedList.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_xterm/common/services/services.dart';
import 'package:bao_xterm/common/sorted_list.dart';

/// Upstream's `MockLogService` from TestUtils.test.ts, which is ported
/// separately.
class _MockLogService implements ILogService {
  @override
  int get logLevel => LogLevelEnum.debug;
  @override
  void trace(String message, [List<Object?> optionalParams = const []]) {}
  @override
  void debug(String message, [List<Object?> optionalParams = const []]) {}
  @override
  void info(String message, [List<Object?> optionalParams = const []]) {}
  @override
  void warn(String message, [List<Object?> optionalParams = const []]) {}
  @override
  void error(String message, [List<Object?> optionalParams = const []]) {}
}

class _Keyed {
  _Keyed(this.key);

  final int key;

  @override
  bool operator ==(Object other) => other is _Keyed && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

void main() {
  group('SortedList', () {
    late SortedList<int> list;
    void assertList(List<int> expected) {
      expect(list.values().toList(), equals(expected));
    }

    setUp(() {
      list = SortedList<int>((e) => e, _MockLogService());
    });

    group('insert', () {
      test('should maintain sorted values', () {
        list.insert(10);
        assertList([10]);
        list.insert(8);
        assertList([8, 10]);
        list.insert(15);
        assertList([8, 10, 15]);
        list.insert(2);
        assertList([2, 8, 10, 15]);
        list.insert(1);
        assertList([1, 2, 8, 10, 15]);
        list.insert(6);
        assertList([1, 2, 6, 8, 10, 15]);
      });
      test('should allow duplicates of the same key', () {
        list.insert(5);
        assertList([5]);
        list.insert(5);
        assertList([5, 5]);
        list.insert(8);
        assertList([5, 5, 8]);
        list.insert(5);
        assertList([5, 5, 5, 8]);
        list.insert(8);
        assertList([5, 5, 5, 8, 8]);
        list.insert(6);
        assertList([5, 5, 5, 6, 8, 8]);
      });
    });
    test('delete', () {
      list.insert(1);
      list.insert(2);
      list.insert(4);
      list.insert(3);
      list.insert(5);
      assertList([1, 2, 3, 4, 5]);
      list.delete(1);
      assertList([2, 3, 4, 5]);
      list.delete(3);
      assertList([2, 4, 5]);
      list.delete(4);
      assertList([2, 5]);
      list.delete(5);
      assertList([2]);
      list.delete(2);
      assertList([]);
    });
    test('getKeyIterator', () {
      list.insert(5);
      list.insert(5);
      list.insert(8);
      list.insert(5);
      list.insert(8);
      list.insert(6);
      assertList([5, 5, 5, 6, 8, 8]);
      expect(list.getKeyIterator(1).toList(), equals(<int>[]));
      expect(list.getKeyIterator(5).toList(), equals([5, 5, 5]));
      expect(list.getKeyIterator(6).toList(), equals([6]));
      expect(list.getKeyIterator(8).toList(), equals([8, 8]));
      expect(list.getKeyIterator(9).toList(), equals(<int>[]));
    });
    test('clear', () {
      list.insert(1);
      list.insert(2);
      list.insert(4);
      list.insert(3);
      list.insert(5);
      list.clear();
      assertList([]);
    });
    test('custom key', () {
      final customList = SortedList<_Keyed>((e) => e.key, _MockLogService());
      customList.insert(_Keyed(5));
      customList.insert(_Keyed(2));
      customList.insert(_Keyed(10));
      customList.insert(_Keyed(5));
      customList.insert(_Keyed(6));
      expect(
        customList.values().toList(),
        equals([_Keyed(2), _Keyed(5), _Keyed(5), _Keyed(6), _Keyed(10)]),
      );
    });
    group('values', () {
      test(
        'should iterate correctly when list items change during iteration',
        () {
          list.insert(1);
          list.insert(2);
          list.insert(3);
          list.insert(4);
          final visited = <int>[];
          for (final item in list.values()) {
            visited.add(item);
            list.delete(item);
          }
          expect(visited, equals([1, 2, 3, 4]));
        },
      );
    });
  });
}
