// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/buffer/BufferReflow.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/buffer_line.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/buffer_reflow.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/cell_data.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/constants.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/types.dart';
import 'package:baocode/ide/terminal/xterm/common/circular_list.dart';

void main() {
  group('BufferReflow', () {
    group('reflowSmallerGetNewLineLengths', () {
      test('should return correct line lengths for a small line with wide characters', () {
        final line = BufferLine(4);
        line.set(0, (0, '汉', 2, '汉'.codeUnitAt(0)));
        line.set(1, (0, '', 0, 0));
        line.set(2, (0, '语', 2, '语'.codeUnitAt(0)));
        line.set(3, (0, '', 0, 0));
        expect(line.translateToString(true), '汉语');
        expect(
          reflowSmallerGetNewLineLengths([line], 4, 3),
          equals([2, 2]),
          reason: 'line: 汉, 语',
        );
        expect(
          reflowSmallerGetNewLineLengths([line], 4, 2),
          equals([2, 2]),
          reason: 'line: 汉, 语',
        );
      });
      test('should return correct line lengths for a large line with wide characters', () {
        final line = BufferLine(12);
        for (var i = 0; i < 12; i += 4) {
          line.set(i, (0, '汉', 2, '汉'.codeUnitAt(0)));
          line.set(i + 2, (0, '语', 2, '语'.codeUnitAt(0)));
        }
        for (var i = 1; i < 12; i += 2) {
          line.set(i, (0, '', 0, 0));
          line.set(i, (0, '', 0, 0));
        }
        expect(line.translateToString(), '汉语汉语汉语');
        expect(
          reflowSmallerGetNewLineLengths([line], 12, 11),
          equals([10, 2]),
          reason: 'line: 汉语汉语汉, 语',
        );
        expect(
          reflowSmallerGetNewLineLengths([line], 12, 10),
          equals([10, 2]),
          reason: 'line: 汉语汉语汉, 语',
        );
        expect(
          reflowSmallerGetNewLineLengths([line], 12, 9),
          equals([8, 4]),
          reason: 'line: 汉语汉语, 汉语',
        );
        expect(
          reflowSmallerGetNewLineLengths([line], 12, 8),
          equals([8, 4]),
          reason: 'line: 汉语汉语, 汉语',
        );
        expect(
          reflowSmallerGetNewLineLengths([line], 12, 7),
          equals([6, 6]),
          reason: 'line: 汉语汉, 语汉语',
        );
        expect(
          reflowSmallerGetNewLineLengths([line], 12, 6),
          equals([6, 6]),
          reason: 'line: 汉语汉, 语汉语',
        );
        expect(
          reflowSmallerGetNewLineLengths([line], 12, 5),
          equals([4, 4, 4]),
          reason: 'line: 汉语, 汉语, 汉语',
        );
        expect(
          reflowSmallerGetNewLineLengths([line], 12, 4),
          equals([4, 4, 4]),
          reason: 'line: 汉语, 汉语, 汉语',
        );
        expect(
          reflowSmallerGetNewLineLengths([line], 12, 3),
          equals([2, 2, 2, 2, 2, 2]),
          reason: 'line: 汉, 语, 汉, 语, 汉, 语',
        );
        expect(
          reflowSmallerGetNewLineLengths([line], 12, 2),
          equals([2, 2, 2, 2, 2, 2]),
          reason: 'line: 汉, 语, 汉, 语, 汉, 语',
        );
      });
      test('should return correct line lengths for a string with wide and single characters', () {
        final line = BufferLine(6);
        line.set(0, (0, 'a', 1, 'a'.codeUnitAt(0)));
        line.set(1, (0, '汉', 2, '汉'.codeUnitAt(0)));
        line.set(2, (0, '', 0, 0));
        line.set(3, (0, '语', 2, '语'.codeUnitAt(0)));
        line.set(4, (0, '', 0, 0));
        line.set(5, (0, 'b', 1, 'b'.codeUnitAt(0)));
        expect(line.translateToString(), 'a汉语b');
        expect(
          reflowSmallerGetNewLineLengths([line], 6, 5),
          equals([5, 1]),
          reason: 'line: a汉语b',
        );
        expect(
          reflowSmallerGetNewLineLengths([line], 6, 4),
          equals([3, 3]),
          reason: 'line: a汉, 语b',
        );
        expect(
          reflowSmallerGetNewLineLengths([line], 6, 3),
          equals([3, 3]),
          reason: 'line: a汉, 语b',
        );
        expect(
          reflowSmallerGetNewLineLengths([line], 6, 2),
          equals([1, 2, 2, 1]),
          reason: 'line: a, 汉, 语, b',
        );
      });
      test('should return correct line lengths for a wrapped line with wide and single characters', () {
        final line1 = BufferLine(6);
        line1.set(0, (0, 'a', 1, 'a'.codeUnitAt(0)));
        line1.set(1, (0, '汉', 2, '汉'.codeUnitAt(0)));
        line1.set(2, (0, '', 0, 0));
        line1.set(3, (0, '语', 2, '语'.codeUnitAt(0)));
        line1.set(4, (0, '', 0, 0));
        line1.set(5, (0, 'b', 1, 'b'.codeUnitAt(0)));
        final line2 = BufferLine(6, null, true);
        line2.set(0, (0, 'a', 1, 'a'.codeUnitAt(0)));
        line2.set(1, (0, '汉', 2, '汉'.codeUnitAt(0)));
        line2.set(2, (0, '', 0, 0));
        line2.set(3, (0, '语', 2, '语'.codeUnitAt(0)));
        line2.set(4, (0, '', 0, 0));
        line2.set(5, (0, 'b', 1, 'b'.codeUnitAt(0)));
        expect(line1.translateToString(), 'a汉语b');
        expect(line2.translateToString(), 'a汉语b');
        expect(
          reflowSmallerGetNewLineLengths([line1, line2], 6, 5),
          equals([5, 4, 3]),
          reason: 'lines: a汉语, ba汉, 语b',
        );
        expect(
          reflowSmallerGetNewLineLengths([line1, line2], 6, 4),
          equals([3, 4, 4, 1]),
          reason: 'lines: a汉, 语ba, 汉语, b',
        );
        expect(
          reflowSmallerGetNewLineLengths([line1, line2], 6, 3),
          equals([3, 3, 3, 3]),
          reason: 'lines: a汉, 语b, a汉, 语b',
        );
        expect(
          reflowSmallerGetNewLineLengths([line1, line2], 6, 2),
          equals([1, 2, 2, 2, 2, 2, 1]),
          reason: 'lines: a, 汉, 语, ba, 汉, 语, b',
        );
      });
      test('should work on lines ending in null space', () {
        final line = BufferLine(5);
        line.set(0, (0, '汉', 2, '汉'.codeUnitAt(0)));
        line.set(1, (0, '', 0, 0));
        line.set(2, (0, '语', 2, '语'.codeUnitAt(0)));
        line.set(3, (0, '', 0, 0));
        line.set(4, (0, nullCellChar, nullCellWidth, nullCellCode));
        expect(line.translateToString(true), '汉语');
        expect(line.translateToString(false), '汉语 ');
        expect(
          reflowSmallerGetNewLineLengths([line], 4, 3),
          equals([2, 2]),
          reason: 'line: 汉, 语',
        );
        expect(
          reflowSmallerGetNewLineLengths([line], 4, 2),
          equals([2, 2]),
          reason: 'line: 汉, 语',
        );
      });
    });
    group('reflowLargerGetLinesToRemove', () {
      final nullCell = CellData.fromCharData((
        0,
        nullCellChar,
        nullCellWidth,
        nullCellCode,
      ));

      CircularList<IBufferLine> createWrappedLines(String chars) {
        final lines = CircularList<IBufferLine>(chars.length);
        for (var i = 0; i < chars.length; i++) {
          final line = BufferLine(1);
          line.set(0, (0, chars[i], 1, chars.codeUnitAt(i)));
          line.isWrapped = i > 0;
          lines.push(line);
        }
        return lines;
      }

      test('should skip reflow when the cursor is in a wrapped block and reflowCursorLine is false', () {
        final lines = createWrappedLines('abcde');
        final skipped = reflowLargerGetLinesToRemove(
          lines,
          1,
          5,
          2,
          nullCell,
          false,
        );
        final reflowed = reflowLargerGetLinesToRemove(
          lines,
          1,
          5,
          2,
          nullCell,
          true,
        );
        expect(skipped, equals(<int>[]));
        expect(reflowed, isNot(equals(<int>[])));
      });

      test(
        'should reflow wrapped blocks when the cursor is outside the block',
        () {
          final lines = createWrappedLines('abcde');
          expect(
            reflowLargerGetLinesToRemove(lines, 1, 5, 10, nullCell, false),
            isNot(equals(<int>[])),
          );
        },
      );
    });
  });
}
