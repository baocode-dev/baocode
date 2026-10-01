// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Adapted from xterm.js src/browser/input/Mouse.test.ts (c58ea36).
//
// Upstream clicks a jsdom element at the window's origin with no padding;
// here the positions are relative to the element's content box.

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_xterm/browser/input/mouse.dart';

const double charWidth = 10;
const double charHeight = 20;

void main() {
  group('Mouse getCoords', () {
    test('should return the cell that was clicked', () {
      List<int>? coords;
      coords = getCoords(
        charWidth / 2,
        charHeight / 2,
        10,
        10,
        true,
        charWidth,
        charHeight,
      );
      expect(coords, equals([1, 1]));
      coords = getCoords(
        charWidth,
        charHeight,
        10,
        10,
        true,
        charWidth,
        charHeight,
      );
      expect(coords, equals([1, 1]));
      coords = getCoords(
        charWidth,
        charHeight + 1,
        10,
        10,
        true,
        charWidth,
        charHeight,
      );
      expect(coords, equals([1, 2]));
      coords = getCoords(
        charWidth + 1,
        charHeight,
        10,
        10,
        true,
        charWidth,
        charHeight,
      );
      expect(coords, equals([2, 1]));
    });

    test('should ensure the coordinates are returned within the terminal '
        'bounds', () {
      List<int>? coords;
      coords = getCoords(-1, -1, 10, 10, true, charWidth, charHeight);
      expect(coords, equals([1, 1]));
      // Event are double the cols/rows
      coords = getCoords(
        charWidth * 20,
        charHeight * 20,
        10,
        10,
        true,
        charWidth,
        charHeight,
      );
      expect(
        coords,
        equals([10, 10]),
        reason:
            'coordinates should never come back as larger than the '
            'terminal',
      );
    });
  });
}
