// Copyright (c) 2026 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/services/BufferService.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/attribute_data.dart';
import 'package:baocode/ide/terminal/xterm/common/services/buffer_service.dart';
import 'package:baocode/ide/terminal/xterm/common/services/options_service.dart';
import 'package:baocode/ide/terminal/xterm/typings/xterm.dart'
    show ITerminalOptions;

import '../test_utils.dart';

void main() {
  group('BufferService', () {
    group('scroll', () {
      final eraseAttr = AttributeData();

      test('should decrement ydisp when the buffer is full and the user has scrolled up', () {
        final optionsService = OptionsService(
          ITerminalOptions(rows: 3, cols: 10, scrollback: 2),
        );
        final bufferService = BufferService(optionsService, MockLogService());
        final buffer = bufferService.buffer;

        while (!buffer.lines.isFull) {
          bufferService.scroll(eraseAttr);
        }
        expect(buffer.lines.length, 5);

        bufferService.isUserScrolling = true;
        buffer.ydisp = 2;
        final ybaseBefore = buffer.ybase;

        bufferService.scroll(eraseAttr);

        expect(buffer.ybase, ybaseBefore);
        expect(buffer.ydisp, 1);
      });

      test('should not advance ydisp with ybase while the user has scrolled up and the buffer is not full', () {
        final optionsService = OptionsService(
          ITerminalOptions(rows: 3, cols: 10, scrollback: 2),
        );
        final bufferService = BufferService(optionsService, MockLogService());
        final buffer = bufferService.buffer;

        bufferService.isUserScrolling = true;
        buffer.ydisp = 0;
        final ybaseBefore = buffer.ybase;

        bufferService.scroll(eraseAttr);

        expect(buffer.ybase, ybaseBefore + 1);
        expect(buffer.ydisp, 0);
      });

      test('should follow ybase with ydisp when the user is not scrolling', () {
        final optionsService = OptionsService(
          ITerminalOptions(rows: 3, cols: 10, scrollback: 2),
        );
        final bufferService = BufferService(optionsService, MockLogService());
        final buffer = bufferService.buffer;

        while (!buffer.lines.isFull) {
          bufferService.scroll(eraseAttr);
        }

        bufferService.isUserScrolling = false;
        bufferService.scroll(eraseAttr);

        expect(buffer.ydisp, buffer.ybase);
      });

      test('should scroll within DECSTBM margins without affecting lines outside the region', () {
        final optionsService = OptionsService(
          ITerminalOptions(rows: 5, cols: 10, scrollback: 10),
        );
        final bufferService = BufferService(optionsService, MockLogService());
        final buffer = bufferService.buffer;

        void markRow(int row, String ch) {
          buffer.lines
              .get(buffer.ybase + row)!
              .setCellFromCodepoint(0, ch.codeUnitAt(0), 1, eraseAttr);
        }

        markRow(0, 'A');
        markRow(1, 'B');
        markRow(2, 'C');
        markRow(3, 'D');
        markRow(4, 'E');
        buffer.scrollTop = 1;
        buffer.scrollBottom = 3;

        bufferService.scroll(eraseAttr);

        expect(
          buffer.lines.get(buffer.ybase + 0)!.translateToString().trim(),
          'A',
        );
        expect(
          buffer.lines.get(buffer.ybase + 1)!.translateToString().trim(),
          'C',
        );
        expect(
          buffer.lines.get(buffer.ybase + 2)!.translateToString().trim(),
          'D',
        );
        expect(
          buffer.lines.get(buffer.ybase + 3)!.translateToString(true).trim(),
          '',
        );
        expect(
          buffer.lines.get(buffer.ybase + 4)!.translateToString().trim(),
          'E',
        );
      });
    });

    group('scrollLines', () {
      test('should move ydisp and set isUserScrolling when scrolling up', () {
        final optionsService = OptionsService(
          ITerminalOptions(rows: 10, cols: 80, scrollback: 10),
        );
        final bufferService = BufferService(optionsService, MockLogService());
        final buffer = bufferService.buffer;
        buffer.ybase = 5;
        buffer.ydisp = 5;

        int? scrollEvent;
        bufferService.onScroll((e) {
          scrollEvent = e;
        });

        bufferService.scrollLines(-2);

        expect(buffer.ydisp, 3);
        expect(bufferService.isUserScrolling, true);
        expect(scrollEvent, 3);
      });

      test('should not scroll above the top of the buffer', () {
        final optionsService = OptionsService(
          ITerminalOptions(rows: 10, cols: 80, scrollback: 10),
        );
        final bufferService = BufferService(optionsService, MockLogService());
        final buffer = bufferService.buffer;
        buffer.ybase = 5;
        buffer.ydisp = 0;

        bufferService.scrollLines(-1);

        expect(buffer.ydisp, 0);
        expect(bufferService.isUserScrolling, false);
      });

      test('should clear isUserScrolling when scrolling to the bottom', () {
        final optionsService = OptionsService(
          ITerminalOptions(rows: 10, cols: 80, scrollback: 10),
        );
        final bufferService = BufferService(optionsService, MockLogService());
        final buffer = bufferService.buffer;
        buffer.ybase = 5;
        buffer.ydisp = 2;
        bufferService.isUserScrolling = true;

        bufferService.scrollLines(10);

        expect(buffer.ydisp, 5);
        expect(bufferService.isUserScrolling, false);
      });
    });
  });
}
