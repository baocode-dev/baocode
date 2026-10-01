// Copyright (c) 2016 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/CircularList.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/common/circular_list.dart';

Matcher _throwsMessage(String message) => throwsA(
  isA<Error>().having((e) => e.toString(), 'message', contains(message)),
);

void main() {
  group('CircularList', () {
    group('push', () {
      test('should push values onto the array', () {
        final list = CircularList<String>(5);
        list.push('1');
        list.push('2');
        list.push('3');
        list.push('4');
        list.push('5');
        expect(list.get(0), '1');
        expect(list.get(1), '2');
        expect(list.get(2), '3');
        expect(list.get(3), '4');
        expect(list.get(4), '5');
      });

      test('should push old values from the start out of the array when max length is reached', () {
        final list = CircularList<String>(2);
        list.push('1');
        list.push('2');
        expect(list.get(0), '1');
        expect(list.get(1), '2');
        list.push('3');
        expect(list.get(0), '2');
        expect(list.get(1), '3');
        list.push('4');
        expect(list.get(0), '3');
        expect(list.get(1), '4');
      });
    });

    group('maxLength', () {
      test('should increase the size of the list', () {
        final list = CircularList<String>(2);
        list.push('1');
        list.push('2');
        expect(list.get(0), '1');
        expect(list.get(1), '2');
        list.maxLength = 4;
        list.push('3');
        list.push('4');
        expect(list.get(0), '1');
        expect(list.get(1), '2');
        expect(list.get(2), '3');
        expect(list.get(3), '4');
        list.push('wrapped');
        expect(list.get(0), '2');
        expect(list.get(1), '3');
        expect(list.get(2), '4');
        expect(list.get(3), 'wrapped');
      });

      test('should return the maximum length of the list', () {
        final list = CircularList<String>(2);
        expect(list.maxLength, 2);
        list.push('1');
        list.push('2');
        expect(list.maxLength, 2);
        list.push('3');
        expect(list.maxLength, 2);
        list.maxLength = 4;
        expect(list.maxLength, 4);
      });
    });

    group('length', () {
      test('should return the current length of the list, capped at the maximum length', () {
        final list = CircularList<String>(2);
        expect(list.length, 0);
        list.push('1');
        expect(list.length, 1);
        list.push('2');
        expect(list.length, 2);
        list.push('3');
        expect(list.length, 2);
      });
    });

    group('splice', () {
      test('should delete items', () {
        final list = CircularList<String>(2);
        list.push('1');
        list.push('2');
        list.splice(0, 1);
        expect(list.length, 1);
        expect(list.get(0), '2');
        list.push('3');
        list.splice(1, 1);
        expect(list.length, 1);
        expect(list.get(0), '2');
      });

      test('should insert items', () {
        final list = CircularList<String>(2);
        list.push('1');
        list.splice(0, 0, ['2']);
        expect(list.length, 2);
        expect(list.get(0), '2');
        expect(list.get(1), '1');
        list.splice(1, 0, ['3']);
        expect(list.length, 2);
        expect(list.get(0), '3');
        expect(list.get(1), '1');
      });

      test('should delete items then insert items', () {
        final list = CircularList<String>(3);
        list.push('1');
        list.push('2');
        list.splice(0, 1, ['3', '4']);
        expect(list.length, 3);
        expect(list.get(0), '3');
        expect(list.get(1), '4');
        expect(list.get(2), '2');
      });

      test('should wrap the array correctly when more items are inserted than deleted', () {
        final list = CircularList<String>(3);
        list.push('1');
        list.push('2');
        list.splice(1, 0, ['3', '4']);
        expect(list.length, 3);
        expect(list.get(0), '3');
        expect(list.get(1), '4');
        expect(list.get(2), '2');
      });
    });

    group('trimStart', () {
      test('should remove items from the beginning of the list', () {
        final list = CircularList<String>(5);
        list.push('1');
        list.push('2');
        list.push('3');
        list.push('4');
        list.push('5');
        list.trimStart(1);
        expect(list.length, 4);
        expect(list.get(0), equals('2'));
        expect(list.get(1), equals('3'));
        expect(list.get(2), equals('4'));
        expect(list.get(3), equals('5'));
        list.trimStart(2);
        expect(list.length, 2);
        expect(list.get(0), equals('4'));
        expect(list.get(1), equals('5'));
      });

      test("should remove all items if the requested trim amount is larger than the list's length", () {
        final list = CircularList<String>(5);
        list.push('1');
        list.trimStart(2);
        expect(list.length, 0);
      });
    });

    group('shiftElements', () {
      test('should not mutate the list when count is 0', () {
        final list = CircularList<int>(5);
        list.push(1);
        list.push(2);
        list.shiftElements(0, 0, 1);
        expect(list.length, 2);
        expect(list.get(0), 1);
        expect(list.get(1), 2);
      });

      test('should throw for invalid args', () {
        final list = CircularList<int>(5);
        list.push(1);
        expect(
          () => list.shiftElements(-1, 1, 1),
          _throwsMessage('start argument out of range'),
        );
        expect(
          () => list.shiftElements(1, 1, 1),
          _throwsMessage('start argument out of range'),
        );
        expect(
          () => list.shiftElements(0, 1, -1),
          _throwsMessage('Cannot shift elements in list beyond index 0'),
        );
      });

      test('should shift an element forward', () {
        final list = CircularList<int>(5);
        list.push(1);
        list.push(2);
        list.shiftElements(0, 1, 1);
        expect(list.length, 2);
        expect(list.get(0), 1);
        expect(list.get(1), 1);
      });

      test('should shift elements forward', () {
        final list = CircularList<int>(5);
        list.push(1);
        list.push(2);
        list.push(3);
        list.push(4);
        list.shiftElements(0, 2, 2);
        expect(list.length, 4);
        expect(list.get(0), 1);
        expect(list.get(1), 2);
        expect(list.get(2), 1);
        expect(list.get(3), 2);
      });

      test('should shift elements forward, expanding the list if needed', () {
        final list = CircularList<int>(5);
        list.push(1);
        list.push(2);
        list.shiftElements(0, 2, 2);
        expect(list.length, 4);
        expect(list.get(0), 1);
        expect(list.get(1), 2);
        expect(list.get(2), 1);
        expect(list.get(3), 2);
      });

      test('should shift elements forward, wrapping the list if needed', () {
        final list = CircularList<int>(5);
        list.push(1);
        list.push(2);
        list.push(3);
        list.push(4);
        list.push(5);
        list.shiftElements(2, 2, 3);
        expect(list.length, 5);
        expect(list.get(0), 3);
        expect(list.get(1), 4);
        expect(list.get(2), 5);
        expect(list.get(3), 3);
        expect(list.get(4), 4);
      });

      test('should shift an element backwards', () {
        final list = CircularList<int>(5);
        list.push(1);
        list.push(2);
        list.shiftElements(1, 1, -1);
        expect(list.length, 2);
        expect(list.get(0), 2);
        expect(list.get(1), 2);
      });

      test('should shift elements backwards', () {
        final list = CircularList<int>(5);
        list.push(1);
        list.push(2);
        list.push(3);
        list.push(4);
        list.shiftElements(2, 2, -2);
        expect(list.length, 4);
        expect(list.get(0), 3);
        expect(list.get(1), 4);
        expect(list.get(2), 3);
        expect(list.get(3), 4);
      });
    });
  });
}
