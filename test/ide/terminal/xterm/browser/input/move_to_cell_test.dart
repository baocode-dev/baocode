// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/browser/input/MoveToCell.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/xterm/browser/input/move_to_cell.dart';
import 'package:monad/ide/terminal/xterm/common/services/services.dart';

import '../../common/test_utils.dart';

String _times(String s, int n) => List<String>.filled(n, s).join();

void main() {
  group('MoveToCell', () {
    late IBufferService bufferService;

    setUp(() {
      bufferService = MockBufferService(5, 5);
      bufferService.buffer.x = 3;
      bufferService.buffer.y = 3;
    });

    group('normal buffer', () {
      test('should use the right directional escape sequences', () {
        expect(
          moveToCellSequence(1, 3, bufferService, false),
          '\x1b[D\x1b[D',
        );
        expect(moveToCellSequence(2, 3, bufferService, false), '\x1b[D');
        expect(moveToCellSequence(4, 3, bufferService, false), '\x1b[C');
        expect(
          moveToCellSequence(5, 3, bufferService, false),
          '\x1b[C\x1b[C',
        );
      });
      test(
        'should wrap around entire row instead of doing up and down when the '
        'Y value differs',
        () {
          const l = '\x1b[D';
          const r = '\x1b[C';
          expect(moveToCellSequence(1, 1, bufferService, false), _times(l, 12));
          expect(moveToCellSequence(2, 1, bufferService, false), _times(l, 11));
          expect(moveToCellSequence(3, 1, bufferService, false), _times(l, 10));
          expect(moveToCellSequence(4, 1, bufferService, false), _times(l, 9));
          expect(moveToCellSequence(5, 1, bufferService, false), _times(l, 8));
          expect(moveToCellSequence(1, 2, bufferService, false), _times(l, 7));
          expect(moveToCellSequence(2, 2, bufferService, false), _times(l, 6));
          expect(moveToCellSequence(3, 2, bufferService, false), _times(l, 5));
          expect(moveToCellSequence(4, 2, bufferService, false), _times(l, 4));
          expect(moveToCellSequence(5, 2, bufferService, false), _times(l, 3));
          expect(moveToCellSequence(1, 4, bufferService, false), _times(r, 3));
          expect(moveToCellSequence(2, 4, bufferService, false), _times(r, 4));
          expect(moveToCellSequence(3, 4, bufferService, false), _times(r, 5));
          expect(moveToCellSequence(4, 4, bufferService, false), _times(r, 6));
          expect(moveToCellSequence(5, 4, bufferService, false), _times(r, 7));
          expect(moveToCellSequence(1, 5, bufferService, false), _times(r, 8));
          expect(moveToCellSequence(2, 5, bufferService, false), _times(r, 9));
          expect(
            moveToCellSequence(3, 5, bufferService, false),
            _times(r, 10),
          );
          expect(
            moveToCellSequence(4, 5, bufferService, false),
            _times(r, 11),
          );
          expect(
            moveToCellSequence(5, 5, bufferService, false),
            _times(r, 12),
          );
        },
      );
      test('should use the correct character for application cursor', () {
        const l = '\x1bOD';
        const r = '\x1bOC';
        expect(moveToCellSequence(3, 1, bufferService, true), _times(l, 10));
        expect(moveToCellSequence(3, 2, bufferService, true), _times(l, 5));
        expect(moveToCellSequence(2, 3, bufferService, true), l);
        expect(moveToCellSequence(4, 3, bufferService, true), r);
        expect(moveToCellSequence(3, 4, bufferService, true), _times(r, 5));
        expect(moveToCellSequence(3, 5, bufferService, true), _times(r, 10));
      });
    });

    group('alt buffer', () {
      setUp(() {
        bufferService.buffers.activateAltBuffer();
        bufferService.buffer.x = 3;
        bufferService.buffer.y = 3;
      });

      test('should move the cursor across rows', () {
        expect(
          moveToCellSequence(4, 4, bufferService, false),
          '\x1b[B\x1b[C',
        );
      });
    });
  });
}
