// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/buffer/BufferSet.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/buffer.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/buffer_set.dart';
import 'package:baocode/ide/terminal/xterm/typings/xterm.dart'
    show ITerminalOptions;

import '../test_utils.dart';

void main() {
  group('BufferSet', () {
    late BufferSet bufferSet;

    setUp(() {
      bufferSet = BufferSet(
        MockOptionsService(ITerminalOptions(scrollback: 1000)),
        MockBufferService(80, 24),
        MockLogService(),
      );
    });

    group('constructor', () {
      test('should create two different buffers: alt and normal', () {
        expect(bufferSet.normal, isA<Buffer>());
        expect(bufferSet.alt, isA<Buffer>());
        expect(bufferSet.normal, isNot(same(bufferSet.alt)));
      });
    });

    group('activateNormalBuffer', () {
      setUp(() {
        bufferSet.activateNormalBuffer();
      });

      test('should set the normal buffer as the currently active buffer', () {
        expect(bufferSet.active, same(bufferSet.normal));
      });
    });

    group('activateAltBuffer', () {
      setUp(() {
        bufferSet.activateAltBuffer();
      });

      test('should set the alt buffer as the currently active buffer', () {
        expect(bufferSet.active, same(bufferSet.alt));
      });
    });

    group('cursor handling when swapping buffers', () {
      setUp(() {
        bufferSet.normal.x = 0;
        bufferSet.normal.y = 0;
        bufferSet.alt.x = 0;
        bufferSet.alt.y = 0;
      });

      test('should keep the cursor stationary when activating alt buffer', () {
        bufferSet.activateNormalBuffer();
        bufferSet.active.x = 30;
        bufferSet.active.y = 10;
        bufferSet.activateAltBuffer();
        expect(bufferSet.active.x, 30);
        expect(bufferSet.active.y, 10);
      });
      test(
        'should keep the cursor stationary when activating normal buffer',
        () {
          bufferSet.activateAltBuffer();
          bufferSet.active.x = 30;
          bufferSet.active.y = 10;
          bufferSet.activateNormalBuffer();
          expect(bufferSet.active.x, 30);
          expect(bufferSet.active.y, 10);
        },
      );
    });

    group('markers', () {
      test('should clear the markers when the buffer is switched', () {
        bufferSet.activateAltBuffer();
        bufferSet.alt.addMarker(1);
        expect(bufferSet.alt.markers.length, 1);
        bufferSet.activateNormalBuffer();
        expect(bufferSet.alt.markers.length, 0);
      });
    });
  });
}
