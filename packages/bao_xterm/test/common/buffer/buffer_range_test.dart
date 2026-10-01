// Copyright (c) 2021 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/buffer/BufferRange.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/buffer_range.dart';
import 'package:baocode/ide/terminal/xterm/typings/xterm.dart';

void main() {
  group('BufferRange', () {
    group('getRangeLength', () {
      test('should get range for single line', () {
        expect(getRangeLength(createRange(1, 1, 4, 1), 0), 4);
      });
      test('should throw for invalid range', () {
        expect(
          () => getRangeLength(createRange(1, 3, 1, 1), 0),
          throwsA(isA<Error>()),
        );
      });
      test('should get range multiple lines', () {
        expect(getRangeLength(createRange(1, 1, 4, 5), 5), 24);
      });
      test('should get range for end line right after start line', () {
        expect(getRangeLength(createRange(1, 1, 7, 2), 5), 12);
      });
    });
  });
}

IBufferRange createRange(int x1, int y1, int x2, int y2) {
  return IBufferRange(
    start: IBufferCellPosition(x: x1, y: y1),
    end: IBufferCellPosition(x: x2, y: y2),
  );
}
