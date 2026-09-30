// Copyright (c) 2026 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/WindowsMode.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/xterm/common/buffer/buffer_line.dart';
import 'package:monad/ide/terminal/xterm/common/services/buffer_service.dart';
import 'package:monad/ide/terminal/xterm/common/services/options_service.dart';
import 'package:monad/ide/terminal/xterm/common/windows_mode.dart';
import 'package:monad/ide/terminal/xterm/typings/xterm.dart'
    show ITerminalOptions;

import 'test_utils.dart';

void main() {
  group('WindowsMode', () {
    group('updateWindowsModeWrappedState', () {
      test('should mark the next line wrapped when the previous line ends in a non-whitespace character', () {
        final bufferService = BufferService(
          OptionsService(ITerminalOptions(rows: 5, cols: 10)),
          MockLogService(),
        );
        final buffer = bufferService.buffer;
        final previousLine = buffer.lines.get(buffer.ybase)!;
        for (var i = 0; i < bufferService.cols; i++) {
          previousLine.setCellFromCodepoint(
            i,
            'a'.codeUnitAt(0),
            1,
            defaultAttrData,
          );
        }
        buffer.y = 1;

        updateWindowsModeWrappedState(bufferService);

        expect(buffer.lines.get(buffer.ybase + 1)!.isWrapped, true);
      });

      test('should not mark the next line wrapped when the previous line ends in whitespace', () {
        final bufferService = BufferService(
          OptionsService(ITerminalOptions(rows: 5, cols: 10)),
          MockLogService(),
        );
        final buffer = bufferService.buffer;
        final previousLine = buffer.lines.get(buffer.ybase)!;
        for (var i = 0; i < bufferService.cols - 1; i++) {
          previousLine.setCellFromCodepoint(
            i,
            'a'.codeUnitAt(0),
            1,
            defaultAttrData,
          );
        }
        previousLine.setCellFromCodepoint(
          bufferService.cols - 1,
          ' '.codeUnitAt(0),
          1,
          defaultAttrData,
        );
        buffer.y = 1;

        updateWindowsModeWrappedState(bufferService);

        expect(buffer.lines.get(buffer.ybase + 1)!.isWrapped, false);
      });

      test('should not mark the next line wrapped when the previous line ends in a null cell', () {
        final bufferService = BufferService(
          OptionsService(ITerminalOptions(rows: 5, cols: 10)),
          MockLogService(),
        );
        final buffer = bufferService.buffer;
        buffer.y = 1;

        updateWindowsModeWrappedState(bufferService);

        expect(buffer.lines.get(buffer.ybase + 1)!.isWrapped, false);
      });
    });
  });
}
