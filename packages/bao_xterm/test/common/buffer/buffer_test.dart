// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Adapted from xterm.js src/common/buffer/Buffer.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_xterm/common/buffer/buffer.dart';
import 'package:bao_xterm/common/buffer/buffer_line.dart';
import 'package:bao_xterm/common/buffer/cell_data.dart';
import 'package:bao_xterm/common/buffer/types.dart';
import 'package:bao_xterm/common/circular_list.dart';
import 'package:bao_xterm/typings/xterm.dart'
    show ITerminalOptions, IWindowsPty;

import 'package:bao_xterm/testing/test_utils.dart';

const int initCols = 80;
const int initRows = 24;
const int initScrollback = 1000;

class TestBuffer extends Buffer {
  TestBuffer(
    super.hasScrollback,
    super.optionsService,
    super.bufferService,
    super.logService,
  );
}

void main() {
  group('Buffer', () {
    late MockOptionsService optionsService;
    late MockBufferService bufferService;
    late TestBuffer buffer;

    IBufferLine lineAt(int y) => buffer.lines.get(y)!;

    /// Upstream's loop asserting `isWrapped` of every line.
    void expectWrappedLines(List<int> wrappedLines) {
      for (var i = 0; i < buffer.lines.length; i++) {
        expect(
          lineAt(i).isWrapped,
          wrappedLines.contains(i),
          reason: 'line $i isWrapped must equal ${wrappedLines.contains(i)}',
        );
      }
    }

    setUp(() {
      optionsService = MockOptionsService(
        ITerminalOptions(scrollback: initScrollback),
      );
      bufferService = MockBufferService(initCols, initRows);
      buffer = TestBuffer(
        true,
        optionsService,
        bufferService,
        MockLogService(),
      );
    });

    group('constructor', () {
      test('should create a CircularList with max length equal to rows + scrollback, for its lines', () {
        expect(buffer.lines, isA<CircularList<IBufferLine>>());
        expect(buffer.lines.maxLength, bufferService.rows + initScrollback);
      });
      test('should set the Buffer\'s scrollBottom value equal to the terminal\'s rows -1', () {
        expect(buffer.scrollBottom, bufferService.rows - 1);
      });
    });

    group('fillViewportRows', () {
      test('should fill the buffer with blank lines based on the size of the viewport', () {
        final blankLineChar = buffer
            .getBlankLine(defaultAttrData)
            .loadCell(0, CellData())
            .getAsCharData();
        buffer.fillViewportRows();
        expect(buffer.lines.length, initRows);
        for (var y = 0; y < initRows; y++) {
          expect(lineAt(y).length, initCols);
          for (var x = 0; x < initCols; x++) {
            expect(
              lineAt(y).loadCell(x, CellData()).getAsCharData(),
              equals(blankLineChar),
            );
          }
        }
      });
    });

    group('getWrappedRangeForLine', () {
      group('non-wrapped', () {
        test('should return a single row for the first row', () {
          buffer.fillViewportRows();
          expect(buffer.getWrappedRangeForLine(0), (first: 0, last: 0));
        });
        test('should return a single row for a middle row', () {
          buffer.fillViewportRows();
          expect(buffer.getWrappedRangeForLine(12), (first: 12, last: 12));
        });
        test('should return a single row for the last row', () {
          buffer.fillViewportRows();
          expect(buffer.getWrappedRangeForLine(buffer.lines.length - 1), (
            first: 23,
            last: 23,
          ));
        });
      });
      group('wrapped', () {
        test('should return a range for the first row', () {
          buffer.fillViewportRows();
          lineAt(1).isWrapped = true;
          expect(buffer.getWrappedRangeForLine(0), (first: 0, last: 1));
        });
        test('should return a range for a middle row wrapping upwards', () {
          buffer.fillViewportRows();
          lineAt(12).isWrapped = true;
          expect(buffer.getWrappedRangeForLine(12), (first: 11, last: 12));
        });
        test('should return a range for a middle row wrapping downwards', () {
          buffer.fillViewportRows();
          lineAt(13).isWrapped = true;
          expect(buffer.getWrappedRangeForLine(12), (first: 12, last: 13));
        });
        test('should return a range for a middle row wrapping both ways', () {
          buffer.fillViewportRows();
          lineAt(11).isWrapped = true;
          lineAt(12).isWrapped = true;
          lineAt(13).isWrapped = true;
          lineAt(14).isWrapped = true;
          expect(buffer.getWrappedRangeForLine(12), (first: 10, last: 14));
        });
        test('should return a range for the last row', () {
          buffer.fillViewportRows();
          lineAt(23).isWrapped = true;
          expect(buffer.getWrappedRangeForLine(buffer.lines.length - 1), (
            first: 22,
            last: 23,
          ));
        });
        test(
          'should return a range for a row that wraps upward to first row',
          () {
            buffer.fillViewportRows();
            lineAt(1).isWrapped = true;
            expect(buffer.getWrappedRangeForLine(1), (first: 0, last: 1));
          },
        );
        test(
          'should return a range for a row that wraps downward to last row',
          () {
            buffer.fillViewportRows();
            lineAt(buffer.lines.length - 1).isWrapped = true;
            expect(buffer.getWrappedRangeForLine(buffer.lines.length - 2), (
              first: 22,
              last: 23,
            ));
          },
        );
      });
    });

    group('resize', () {
      group('column size is reduced', () {
        test('should trim the data in the buffer', () {
          buffer.fillViewportRows();
          buffer.resize(initCols ~/ 2, initRows);
          expect(buffer.lines.length, initRows);
          for (var i = 0; i < initRows; i++) {
            expect(lineAt(i).length, initCols ~/ 2);
          }
        });
      });

      group('column size is increased', () {
        test('should add pad columns', () {
          buffer.fillViewportRows();
          buffer.resize(initCols + 10, initRows);
          expect(buffer.lines.length, initRows);
          for (var i = 0; i < initRows; i++) {
            expect(lineAt(i).length, initCols + 10);
          }
        });
      });

      group('row size reduced', () {
        test('should trim blank lines from the end', () {
          buffer.fillViewportRows();
          buffer.resize(initCols, initRows - 10);
          expect(buffer.lines.length, initRows - 10);
        });

        test('should move the viewport down when it\'s at the end', () {
          buffer.fillViewportRows();
          // Set cursor y to have 5 blank lines below it
          buffer.y = initRows - 5 - 1;
          buffer.resize(initCols, initRows - 10);
          // Trim 5 rows
          expect(buffer.lines.length, initRows - 5);
          // Shift the viewport down 5 rows
          expect(buffer.ydisp, 5);
          expect(buffer.ybase, 5);
        });

        group('no scrollback', () {
          test('should trim from the top of the buffer when the cursor reaches the bottom', () {
            buffer = TestBuffer(
              true,
              MockOptionsService(ITerminalOptions(scrollback: 0)),
              bufferService,
              MockLogService(),
            );
            expect(buffer.lines.maxLength, initRows);
            buffer.y = initRows - 1;
            buffer.fillViewportRows();
            var chData = lineAt(5).loadCell(0, CellData()).getAsCharData();
            lineAt(5).setCell(
              0,
              CellData.fromCharData((chData.$1, 'a', chData.$3, chData.$4)),
            );
            chData = lineAt(initRows - 1)
                .loadCell(0, CellData())
                .getAsCharData();
            lineAt(initRows - 1).setCell(
              0,
              CellData.fromCharData((chData.$1, 'b', chData.$3, chData.$4)),
            );
            buffer.resize(initCols, initRows - 5);
            expect(lineAt(0).loadCell(0, CellData()).getAsCharData().$2, 'a');
            expect(
              lineAt(initRows - 1 - 5)
                  .loadCell(0, CellData())
                  .getAsCharData()
                  .$2,
              'b',
            );
          });
        });
      });

      group('row size increased', () {
        group('empty buffer', () {
          test('should add blank lines to end', () {
            buffer.fillViewportRows();
            expect(buffer.ydisp, 0);
            buffer.resize(initCols, initRows + 10);
            expect(buffer.ydisp, 0);
            expect(buffer.lines.length, initRows + 10);
          });
        });

        group('filled buffer', () {
          test('should show more of the buffer above', () {
            buffer.fillViewportRows();
            // Create 10 extra blank lines
            for (var i = 0; i < 10; i++) {
              buffer.lines.push(buffer.getBlankLine(defaultAttrData));
            }
            // Set cursor to the bottom of the buffer
            buffer.y = initRows - 1;
            // Scroll down 10 lines
            buffer.ybase = 10;
            buffer.ydisp = 10;
            expect(buffer.lines.length, initRows + 10);
            buffer.resize(initCols, initRows + 5);
            // Should be should 5 more lines
            expect(buffer.ydisp, 5);
            expect(buffer.ybase, 5);
            // Should not trim the buffer
            expect(buffer.lines.length, initRows + 10);
          });

          test('should show more of the buffer below when the viewport is at the top of the buffer', () {
            buffer.fillViewportRows();
            // Create 10 extra blank lines
            for (var i = 0; i < 10; i++) {
              buffer.lines.push(buffer.getBlankLine(defaultAttrData));
            }
            // Set cursor to the bottom of the buffer
            buffer.y = initRows - 1;
            // Scroll down 10 lines
            buffer.ybase = 10;
            buffer.ydisp = 0;
            expect(buffer.lines.length, initRows + 10);
            buffer.resize(initCols, initRows + 5);
            // The viewport should remain at the top
            expect(buffer.ydisp, 0);
            // The buffer ybase should move up 5 lines
            expect(buffer.ybase, 5);
            // Should not trim the buffer
            expect(buffer.lines.length, initRows + 10);
          });
        });

        group('Windows ConPTY', () {
          setUp(() {
            optionsService.options.windowsPty = IWindowsPty(
              backend: 'conpty',
              buildNumber: 19000,
            );
          });

          test('should not adjust ybase or ydisp when growing rows', () {
            buffer.fillViewportRows();
            for (var i = 0; i < 10; i++) {
              buffer.lines.push(buffer.getBlankLine(defaultAttrData));
            }
            buffer.y = initRows - 1;
            buffer.ybase = 10;
            buffer.ydisp = 10;
            final linesBefore = buffer.lines.length;
            buffer.resize(initCols, initRows + 5);
            expect(buffer.ybase, 10);
            expect(buffer.ydisp, 10);
            expect(buffer.lines.length, linesBefore + 5);
          });
        });
      });

      group('row and column increased', () {
        test('should resize properly', () {
          buffer.fillViewportRows();
          buffer.resize(initCols + 5, initRows + 5);
          expect(buffer.lines.length, initRows + 5);
          for (var i = 0; i < initRows + 5; i++) {
            expect(lineAt(i).length, initCols + 5);
          }
        });
      });

      group('reflow', () {
        test('should not wrap empty lines', () {
          buffer.fillViewportRows();
          expect(buffer.lines.length, initRows);
          buffer.resize(initCols - 5, initRows);
          expect(buffer.lines.length, initRows);
        });
        test('should shrink row length', () {
          buffer.fillViewportRows();
          buffer.resize(5, 10);
          expect(buffer.lines.length, 10);
          expect(lineAt(0).length, 5);
          expect(lineAt(1).length, 5);
          expect(lineAt(2).length, 5);
          expect(lineAt(3).length, 5);
          expect(lineAt(4).length, 5);
          expect(lineAt(5).length, 5);
          expect(lineAt(6).length, 5);
          expect(lineAt(7).length, 5);
          expect(lineAt(8).length, 5);
          expect(lineAt(9).length, 5);
        });
        test('should wrap and unwrap lines', () {
          buffer.fillViewportRows();
          buffer.resize(5, 10);
          final firstLine = lineAt(0);
          for (var i = 0; i < 5; i++) {
            final code = 'a'.codeUnitAt(0) + i;
            final char = String.fromCharCode(code);
            firstLine.set(i, (0, char, 1, code));
          }
          buffer.y = 1;
          expect(lineAt(0).length, 5);
          expect(lineAt(0).translateToString(), 'abcde');
          buffer.resize(1, 10);
          expect(buffer.lines.length, 10);
          expect(lineAt(0).translateToString(), 'a');
          expect(lineAt(1).translateToString(), 'b');
          expect(lineAt(2).translateToString(), 'c');
          expect(lineAt(3).translateToString(), 'd');
          expect(lineAt(4).translateToString(), 'e');
          expect(lineAt(5).translateToString(), ' ');
          expect(lineAt(6).translateToString(), ' ');
          expect(lineAt(7).translateToString(), ' ');
          expect(lineAt(8).translateToString(), ' ');
          expect(lineAt(9).translateToString(), ' ');
          buffer.resize(5, 10);
          expect(buffer.lines.length, 10);
          expect(lineAt(0).translateToString(), 'abcde');
          expect(lineAt(1).translateToString(), '     ');
          expect(lineAt(2).translateToString(), '     ');
          expect(lineAt(3).translateToString(), '     ');
          expect(lineAt(4).translateToString(), '     ');
          expect(lineAt(5).translateToString(), '     ');
          expect(lineAt(6).translateToString(), '     ');
          expect(lineAt(7).translateToString(), '     ');
          expect(lineAt(8).translateToString(), '     ');
          expect(lineAt(9).translateToString(), '     ');
        });
        test('should gate reflow on ConPTY buildNumber 21376', () {
          void prepareWrappedShrink() {
            buffer.fillViewportRows();
            buffer.resize(5, 10);
            final firstLine = lineAt(0);
            for (var i = 0; i < 5; i++) {
              final code = 'a'.codeUnitAt(0) + i;
              firstLine.set(i, (0, String.fromCharCode(code), 1, code));
            }
            buffer.y = 1;
            buffer.resize(1, 10);
          }

          optionsService.options.windowsPty = IWindowsPty(
            backend: 'conpty',
            buildNumber: 21375,
          );
          prepareWrappedShrink();
          expect(lineAt(1).translateToString().trim(), '');

          buffer = TestBuffer(
            true,
            optionsService,
            bufferService,
            MockLogService(),
          );
          optionsService.options.windowsPty = IWindowsPty(
            backend: 'conpty',
            buildNumber: 21376,
          );
          prepareWrappedShrink();
          expect(lineAt(1).translateToString().trim(), 'b');
          expect(lineAt(1).isWrapped, isTrue);
        });
        test('should unwrap lines on ConPTY builds with reflow support', () {
          optionsService.options.windowsPty = IWindowsPty(
            backend: 'conpty',
            buildNumber: 21376,
          );
          buffer.fillViewportRows();
          buffer.resize(5, 10);
          final firstLine = lineAt(0);
          for (var i = 0; i < 5; i++) {
            final code = 'a'.codeUnitAt(0) + i;
            firstLine.set(i, (0, String.fromCharCode(code), 1, code));
          }
          buffer.y = 1;
          buffer.resize(1, 10);
          buffer.resize(5, 10);
          expect(lineAt(0).translateToString(), 'abcde');
          expect(lineAt(1).translateToString(), '     ');
        });
        test('should reflow wrapped lines containing the cursor when reflowCursorLine is enabled', () {
          optionsService.options.reflowCursorLine = true;
          buffer.fillViewportRows();
          buffer.resize(5, 10);
          final firstLine = lineAt(0);
          for (var i = 0; i < 5; i++) {
            final code = 'a'.codeUnitAt(0) + i;
            firstLine.set(i, (0, String.fromCharCode(code), 1, code));
          }
          buffer.resize(1, 10);
          buffer.y = 2;
          buffer.resize(5, 10);
          expect(lineAt(0).translateToString(), 'abcde');
        });
        test(
          'should not reflow wrapped lines containing the cursor by default',
          () {
            buffer.fillViewportRows();
            buffer.resize(5, 10);
            final firstLine = lineAt(0);
            for (var i = 0; i < 5; i++) {
              final code = 'a'.codeUnitAt(0) + i;
              firstLine.set(i, (0, String.fromCharCode(code), 1, code));
            }
            buffer.resize(1, 10);
            buffer.y = 2;
            buffer.resize(5, 10);
            expect(lineAt(0).translateToString(), isNot('abcde'));
          },
        );
        test(
          'should discard parts of wrapped lines that go out of the scrollback',
          () {
            buffer.fillViewportRows();
            optionsService.options.scrollback = 1;
            buffer.resize(10, 5);
            final lastLine = lineAt(3);
            for (var i = 0; i < 10; i++) {
              final code = 'a'.codeUnitAt(0) + i;
              final char = String.fromCharCode(code);
              lastLine.set(i, (0, char, 1, code));
            }
            expect(buffer.lines.length, 5);
            buffer.y = 4;
            buffer.resize(2, 5);
            expect(buffer.y, 4);
            expect(buffer.ybase, 1);
            expect(buffer.lines.length, 6);
            expect(lineAt(0).translateToString(), 'ab');
            expect(lineAt(1).translateToString(), 'cd');
            expect(lineAt(2).translateToString(), 'ef');
            expect(lineAt(3).translateToString(), 'gh');
            expect(lineAt(4).translateToString(), 'ij');
            expect(lineAt(5).translateToString(), '  ');
            buffer.resize(1, 5);
            expect(buffer.y, 4);
            expect(buffer.ybase, 1);
            expect(buffer.lines.length, 6);
            expect(lineAt(0).translateToString(), 'f');
            expect(lineAt(1).translateToString(), 'g');
            expect(lineAt(2).translateToString(), 'h');
            expect(lineAt(3).translateToString(), 'i');
            expect(lineAt(4).translateToString(), 'j');
            expect(lineAt(5).translateToString(), ' ');
            buffer.resize(10, 5);
            expect(buffer.y, 1);
            expect(buffer.ybase, 0);
            expect(buffer.lines.length, 5);
            expect(lineAt(0).translateToString(), 'fghij     ');
            expect(lineAt(1).translateToString(), '          ');
            expect(lineAt(2).translateToString(), '          ');
            expect(lineAt(3).translateToString(), '          ');
            expect(lineAt(4).translateToString(), '          ');
          },
        );
        test(
          'should remove the correct amount of rows when reflowing larger',
          () {
            // This is a regression test to ensure that successive wrapped lines
            // that are getting 3+ lines removed on a reflow actually remove the
            // right lines
            buffer.fillViewportRows();
            buffer.resize(10, 10);
            buffer.y = 2;
            final firstLine = lineAt(0);
            final secondLine = lineAt(1);
            for (var i = 0; i < 10; i++) {
              final code = 'a'.codeUnitAt(0) + i;
              final char = String.fromCharCode(code);
              firstLine.set(i, (0, char, 1, code));
            }
            for (var i = 0; i < 10; i++) {
              final code = '0'.codeUnitAt(0) + i;
              final char = String.fromCharCode(code);
              secondLine.set(i, (0, char, 1, code));
            }
            expect(buffer.lines.length, 10);
            expect(lineAt(0).translateToString(), 'abcdefghij');
            expect(lineAt(1).translateToString(), '0123456789');
            for (var i = 2; i < 10; i++) {
              expect(lineAt(i).translateToString(), '          ');
            }
            buffer.resize(2, 10);
            expect(buffer.ybase, 1);
            expect(buffer.lines.length, 11);
            expect(lineAt(0).translateToString(), 'ab');
            expect(lineAt(1).translateToString(), 'cd');
            expect(lineAt(2).translateToString(), 'ef');
            expect(lineAt(3).translateToString(), 'gh');
            expect(lineAt(4).translateToString(), 'ij');
            expect(lineAt(5).translateToString(), '01');
            expect(lineAt(6).translateToString(), '23');
            expect(lineAt(7).translateToString(), '45');
            expect(lineAt(8).translateToString(), '67');
            expect(lineAt(9).translateToString(), '89');
            expect(lineAt(10).translateToString(), '  ');
            buffer.resize(10, 10);
            expect(buffer.ybase, 0);
            expect(buffer.lines.length, 10);
            expect(lineAt(0).translateToString(), 'abcdefghij');
            expect(lineAt(1).translateToString(), '0123456789');
            for (var i = 2; i < 10; i++) {
              expect(lineAt(i).translateToString(), '          ');
            }
          },
        );
        test('should transfer combined char data over to reflowed lines', () {
          buffer.fillViewportRows();
          buffer.resize(4, 3);
          buffer.y = 2;
          final firstLine = lineAt(0);
          firstLine.set(0, (0, 'a', 1, 'a'.codeUnitAt(0)));
          firstLine.set(1, (0, 'b', 1, 'b'.codeUnitAt(0)));
          firstLine.set(2, (0, 'c', 1, 'c'.codeUnitAt(0)));
          firstLine.set(3, (0, '😁', 1, '😁'.codeUnitAt(0)));
          expect(buffer.lines.length, 3);
          expect(lineAt(0).translateToString(), 'abc😁');
          expect(lineAt(1).translateToString(), '    ');
          buffer.resize(2, 3);
          expect(lineAt(0).translateToString(), 'ab');
          expect(lineAt(1).translateToString(), 'c😁');
        });
        test('should adjust markers when reflowing', () {
          buffer.fillViewportRows();
          buffer.resize(10, 16);
          for (var i = 0; i < 10; i++) {
            final code = 'a'.codeUnitAt(0) + i;
            final char = String.fromCharCode(code);
            lineAt(0).set(i, (0, char, 1, code));
          }
          for (var i = 0; i < 10; i++) {
            final code = '0'.codeUnitAt(0) + i;
            final char = String.fromCharCode(code);
            lineAt(1).set(i, (0, char, 1, code));
          }
          for (var i = 0; i < 10; i++) {
            final code = 'k'.codeUnitAt(0) + i;
            final char = String.fromCharCode(code);
            lineAt(2).set(i, (0, char, 1, code));
          }
          buffer.y = 3;
          // Buffer:
          // abcdefghij
          // 0123456789
          // abcdefghij
          final firstMarker = buffer.addMarker(0);
          final secondMarker = buffer.addMarker(1);
          final thirdMarker = buffer.addMarker(2);
          expect(lineAt(0).translateToString(), 'abcdefghij');
          expect(lineAt(1).translateToString(), '0123456789');
          expect(lineAt(2).translateToString(), 'klmnopqrst');
          expect(firstMarker.line, 0);
          expect(secondMarker.line, 1);
          expect(thirdMarker.line, 2);
          buffer.resize(2, 16);
          expect(lineAt(0).translateToString(), 'ab');
          expect(lineAt(1).translateToString(), 'cd');
          expect(lineAt(2).translateToString(), 'ef');
          expect(lineAt(3).translateToString(), 'gh');
          expect(lineAt(4).translateToString(), 'ij');
          expect(lineAt(5).translateToString(), '01');
          expect(lineAt(6).translateToString(), '23');
          expect(lineAt(7).translateToString(), '45');
          expect(lineAt(8).translateToString(), '67');
          expect(lineAt(9).translateToString(), '89');
          expect(lineAt(10).translateToString(), 'kl');
          expect(lineAt(11).translateToString(), 'mn');
          expect(lineAt(12).translateToString(), 'op');
          expect(lineAt(13).translateToString(), 'qr');
          expect(lineAt(14).translateToString(), 'st');
          expect(
            firstMarker.line,
            0,
            reason: 'first marker should remain unchanged',
          );
          expect(
            secondMarker.line,
            5,
            reason:
                'second marker should be shifted since the first line wrapped',
          );
          expect(
            thirdMarker.line,
            10,
            reason: 'third marker should be shifted since the first and second lines wrapped',
          );
          buffer.resize(10, 16);
          expect(lineAt(0).translateToString(), 'abcdefghij');
          expect(lineAt(1).translateToString(), '0123456789');
          expect(lineAt(2).translateToString(), 'klmnopqrst');
          expect(
            firstMarker.line,
            0,
            reason: 'first marker should remain unchanged',
          );
          expect(
            secondMarker.line,
            1,
            reason: 'second marker should be restored to it\'s original line',
          );
          expect(
            thirdMarker.line,
            2,
            reason: 'third marker should be restored to it\'s original line',
          );
          expect(firstMarker.isDisposed, false);
          expect(secondMarker.isDisposed, false);
          expect(thirdMarker.isDisposed, false);
        });
        test(
          'should dispose markers whose rows are trimmed during a reflow',
          () {
            buffer.fillViewportRows();
            optionsService.options.scrollback = 1;
            buffer.resize(10, 11);
            for (var i = 0; i < 10; i++) {
              final code = 'a'.codeUnitAt(0) + i;
              final char = String.fromCharCode(code);
              lineAt(0).set(i, (0, char, 1, code));
            }
            for (var i = 0; i < 10; i++) {
              final code = '0'.codeUnitAt(0) + i;
              final char = String.fromCharCode(code);
              lineAt(1).set(i, (0, char, 1, code));
            }
            for (var i = 0; i < 10; i++) {
              final code = 'k'.codeUnitAt(0) + i;
              final char = String.fromCharCode(code);
              lineAt(2).set(i, (0, char, 1, code));
            }
            buffer.y = 10;
            // Buffer:
            // abcdefghij
            // 0123456789
            // abcdefghij
            final firstMarker = buffer.addMarker(0);
            final secondMarker = buffer.addMarker(1);
            final thirdMarker = buffer.addMarker(2);
            buffer.y = 3;
            expect(lineAt(0).translateToString(), 'abcdefghij');
            expect(lineAt(1).translateToString(), '0123456789');
            expect(lineAt(2).translateToString(), 'klmnopqrst');
            expect(firstMarker.line, 0);
            expect(secondMarker.line, 1);
            expect(thirdMarker.line, 2);
            buffer.resize(2, 11);
            expect(lineAt(0).translateToString(), 'ij');
            expect(lineAt(1).translateToString(), '01');
            expect(lineAt(2).translateToString(), '23');
            expect(lineAt(3).translateToString(), '45');
            expect(lineAt(4).translateToString(), '67');
            expect(lineAt(5).translateToString(), '89');
            expect(lineAt(6).translateToString(), 'kl');
            expect(lineAt(7).translateToString(), 'mn');
            expect(lineAt(8).translateToString(), 'op');
            expect(lineAt(9).translateToString(), 'qr');
            expect(lineAt(10).translateToString(), 'st');
            expect(
              secondMarker.line,
              1,
              reason: 'second marker should remain the same as it was shifted 4 and trimmed 4',
            );
            expect(
              thirdMarker.line,
              6,
              reason: 'third marker should be shifted since the first and second lines wrapped',
            );
            expect(
              firstMarker.isDisposed,
              true,
              reason: 'first marker was trimmed',
            );
            expect(secondMarker.isDisposed, false);
            expect(thirdMarker.isDisposed, false);
            buffer.resize(10, 11);
            expect(lineAt(0).translateToString(), 'ij        ');
            expect(lineAt(1).translateToString(), '0123456789');
            expect(lineAt(2).translateToString(), 'klmnopqrst');
            expect(
              secondMarker.line,
              1,
              reason: 'second marker should be restored',
            );
            expect(
              thirdMarker.line,
              2,
              reason: 'third marker should be restored',
            );
          },
        );
        test('should correctly reflow wrapped lines that end in 0 space (via tab char)', () {
          buffer.fillViewportRows();
          buffer.resize(4, 10);
          buffer.y = 2;
          lineAt(0).set(0, (0, 'a', 1, 'a'.codeUnitAt(0)));
          lineAt(0).set(1, (0, 'b', 1, 'b'.codeUnitAt(0)));
          lineAt(1).set(0, (0, 'c', 1, 'c'.codeUnitAt(0)));
          lineAt(1).set(1, (0, 'd', 1, 'd'.codeUnitAt(0)));
          lineAt(1).isWrapped = true;
          // Buffer:
          // "ab  " (wrapped)
          // "cd"
          buffer.resize(5, 10);
          expect(buffer.ybase, 0);
          expect(buffer.lines.length, 10);
          expect(lineAt(0).translateToString(true), 'ab  c');
          expect(lineAt(1).translateToString(false), 'd    ');
          buffer.resize(6, 10);
          expect(buffer.ybase, 0);
          expect(buffer.lines.length, 10);
          expect(lineAt(0).translateToString(true), 'ab  cd');
          expect(lineAt(1).translateToString(false), '      ');
        });
        test('should wrap wide characters correctly when reflowing larger', () {
          buffer.fillViewportRows();
          buffer.resize(12, 10);
          buffer.y = 2;
          for (var i = 0; i < 12; i += 4) {
            lineAt(0).set(i, (0, '汉', 2, '汉'.codeUnitAt(0)));
            lineAt(1).set(i, (0, '汉', 2, '汉'.codeUnitAt(0)));
          }
          for (var i = 2; i < 12; i += 4) {
            lineAt(0).set(i, (0, '语', 2, '语'.codeUnitAt(0)));
            lineAt(1).set(i, (0, '语', 2, '语'.codeUnitAt(0)));
          }
          for (var i = 1; i < 12; i += 2) {
            lineAt(0).set(i, (0, '', 0, 0));
            lineAt(1).set(i, (0, '', 0, 0));
          }
          lineAt(1).isWrapped = true;
          // Buffer:
          // 汉语汉语汉语 (wrapped)
          // 汉语汉语汉语
          expect(lineAt(0).translateToString(true), '汉语汉语汉语');
          expect(lineAt(1).translateToString(true), '汉语汉语汉语');
          buffer.resize(13, 10);
          expect(buffer.ybase, 0);
          expect(buffer.lines.length, 10);
          expect(lineAt(0).translateToString(true), '汉语汉语汉语');
          expect(lineAt(0).translateToString(false), '汉语汉语汉语 ');
          expect(lineAt(1).translateToString(true), '汉语汉语汉语');
          expect(lineAt(1).translateToString(false), '汉语汉语汉语 ');
          buffer.resize(14, 10);
          expect(lineAt(0).translateToString(true), '汉语汉语汉语汉');
          expect(lineAt(0).translateToString(false), '汉语汉语汉语汉');
          expect(lineAt(1).translateToString(true), '语汉语汉语');
          expect(lineAt(1).translateToString(false), '语汉语汉语    ');
        });
        test('should correctly reflow wrapped lines that end in 0 space (via tab char)', () {
          buffer.fillViewportRows();
          buffer.resize(4, 10);
          buffer.y = 2;
          lineAt(0).set(0, (0, 'a', 1, 'a'.codeUnitAt(0)));
          lineAt(0).set(1, (0, 'b', 1, 'b'.codeUnitAt(0)));
          lineAt(1).set(0, (0, 'c', 1, 'c'.codeUnitAt(0)));
          lineAt(1).set(1, (0, 'd', 1, 'd'.codeUnitAt(0)));
          lineAt(1).isWrapped = true;
          // Buffer:
          // "ab  " (wrapped)
          // "cd"
          buffer.resize(3, 10);
          expect(buffer.y, 2);
          expect(buffer.ybase, 0);
          expect(buffer.lines.length, 10);
          expect(lineAt(0).translateToString(false), 'ab ');
          expect(lineAt(1).translateToString(false), ' cd');
          buffer.resize(2, 10);
          expect(buffer.y, 3);
          expect(buffer.ybase, 0);
          expect(buffer.lines.length, 10);
          expect(lineAt(0).translateToString(false), 'ab');
          expect(lineAt(1).translateToString(false), '  ');
          expect(lineAt(2).translateToString(false), 'cd');
        });
        test(
          'should wrap wide characters correctly when reflowing smaller',
          () {
            buffer.fillViewportRows();
            buffer.resize(12, 10);
            buffer.y = 2;
            for (var i = 0; i < 12; i += 4) {
              lineAt(0).set(i, (0, '汉', 2, '汉'.codeUnitAt(0)));
              lineAt(1).set(i, (0, '汉', 2, '汉'.codeUnitAt(0)));
            }
            for (var i = 2; i < 12; i += 4) {
              lineAt(0).set(i, (0, '语', 2, '语'.codeUnitAt(0)));
              lineAt(1).set(i, (0, '语', 2, '语'.codeUnitAt(0)));
            }
            for (var i = 1; i < 12; i += 2) {
              lineAt(0).set(i, (0, '', 0, 0));
              lineAt(1).set(i, (0, '', 0, 0));
            }
            lineAt(1).isWrapped = true;
            // Buffer:
            // 汉语汉语汉语 (wrapped)
            // 汉语汉语汉语
            expect(lineAt(0).translateToString(true), '汉语汉语汉语');
            expect(lineAt(1).translateToString(true), '汉语汉语汉语');
            buffer.resize(11, 10);
            expect(buffer.ybase, 0);
            expect(buffer.lines.length, 10);
            expect(lineAt(0).translateToString(true), '汉语汉语汉');
            expect(lineAt(1).translateToString(true), '语汉语汉语');
            expect(lineAt(2).translateToString(true), '汉语');
            buffer.resize(10, 10);
            expect(lineAt(0).translateToString(true), '汉语汉语汉');
            expect(lineAt(1).translateToString(true), '语汉语汉语');
            expect(lineAt(2).translateToString(true), '汉语');
            buffer.resize(9, 10);
            expect(lineAt(0).translateToString(true), '汉语汉语');
            expect(lineAt(1).translateToString(true), '汉语汉语');
            expect(lineAt(2).translateToString(true), '汉语汉语');
            buffer.resize(8, 10);
            expect(lineAt(0).translateToString(true), '汉语汉语');
            expect(lineAt(1).translateToString(true), '汉语汉语');
            expect(lineAt(2).translateToString(true), '汉语汉语');
            buffer.resize(7, 10);
            expect(lineAt(0).translateToString(true), '汉语汉');
            expect(lineAt(1).translateToString(true), '语汉语');
            expect(lineAt(2).translateToString(true), '汉语汉');
            expect(lineAt(3).translateToString(true), '语汉语');
            buffer.resize(6, 10);
            expect(lineAt(0).translateToString(true), '汉语汉');
            expect(lineAt(1).translateToString(true), '语汉语');
            expect(lineAt(2).translateToString(true), '汉语汉');
            expect(lineAt(3).translateToString(true), '语汉语');
          },
        );

        group('reflowLarger cases', () {
          setUp(() {
            // Setup buffer state:
            // 'ab'
            // 'cd' (wrapped)
            // 'ef'
            // 'gh' (wrapped)
            // 'ij'
            // 'kl' (wrapped)
            // '  '
            // '  '
            // '  '
            // '  '
            buffer.fillViewportRows();
            buffer.resize(2, 10);
            lineAt(0).set(0, (0, 'a', 1, 'a'.codeUnitAt(0)));
            lineAt(0).set(1, (0, 'b', 1, 'b'.codeUnitAt(0)));
            lineAt(1).set(0, (0, 'c', 1, 'c'.codeUnitAt(0)));
            lineAt(1).set(1, (0, 'd', 1, 'd'.codeUnitAt(0)));
            lineAt(1).isWrapped = true;
            lineAt(2).set(0, (0, 'e', 1, 'e'.codeUnitAt(0)));
            lineAt(2).set(1, (0, 'f', 1, 'f'.codeUnitAt(0)));
            lineAt(3).set(0, (0, 'g', 1, 'g'.codeUnitAt(0)));
            lineAt(3).set(1, (0, 'h', 1, 'h'.codeUnitAt(0)));
            lineAt(3).isWrapped = true;
            lineAt(4).set(0, (0, 'i', 1, 'i'.codeUnitAt(0)));
            lineAt(4).set(1, (0, 'j', 1, 'j'.codeUnitAt(0)));
            lineAt(5).set(0, (0, 'k', 1, 'k'.codeUnitAt(0)));
            lineAt(5).set(1, (0, 'l', 1, 'l'.codeUnitAt(0)));
            lineAt(5).isWrapped = true;
          });
          group('viewport not yet filled', () {
            test('should move the cursor up and add empty lines', () {
              buffer.y = 6;
              buffer.resize(4, 10);
              expect(buffer.y, 3);
              expect(buffer.ydisp, 0);
              expect(buffer.ybase, 0);
              expect(buffer.lines.length, 10);
              expect(lineAt(0).translateToString(), 'abcd');
              expect(lineAt(1).translateToString(), 'efgh');
              expect(lineAt(2).translateToString(), 'ijkl');
              for (var i = 3; i < 10; i++) {
                expect(lineAt(i).translateToString(), '    ');
              }
              expectWrappedLines(<int>[]);
            });
          });
          group('viewport filled, scrollback remaining', () {
            setUp(() {
              buffer.y = 9;
            });
            group('ybase === 0', () {
              test('should move the cursor up and add empty lines', () {
                buffer.resize(4, 10);
                expect(buffer.y, 6);
                expect(buffer.ydisp, 0);
                expect(buffer.ybase, 0);
                expect(buffer.lines.length, 10);
                expect(lineAt(0).translateToString(), 'abcd');
                expect(lineAt(1).translateToString(), 'efgh');
                expect(lineAt(2).translateToString(), 'ijkl');
                for (var i = 3; i < 10; i++) {
                  expect(lineAt(i).translateToString(), '    ');
                }
                expectWrappedLines(<int>[]);
              });
            });
            group('ybase !== 0', () {
              setUp(() {
                // Add 10 empty rows to start
                for (var i = 0; i < 10; i++) {
                  buffer.lines.splice(0, 0, [
                    buffer.getBlankLine(defaultAttrData),
                  ]);
                }
                buffer.ybase = 10;
              });
              group('&& ydisp === ybase', () {
                test('should adjust the viewport and keep ydisp = ybase', () {
                  buffer.ydisp = 10;
                  buffer.resize(4, 10);
                  expect(buffer.y, 9);
                  expect(buffer.ydisp, 7);
                  expect(buffer.ybase, 7);
                  expect(buffer.lines.length, 17);
                  for (var i = 0; i < 10; i++) {
                    expect(lineAt(i).translateToString(), '    ');
                  }
                  expect(lineAt(10).translateToString(), 'abcd');
                  expect(lineAt(11).translateToString(), 'efgh');
                  expect(lineAt(12).translateToString(), 'ijkl');
                  for (var i = 13; i < 17; i++) {
                    expect(lineAt(i).translateToString(), '    ');
                  }
                  expectWrappedLines(<int>[]);
                });
              });
              group('&& ydisp !== ybase', () {
                test('should keep ydisp at the same value', () {
                  buffer.ydisp = 5;
                  buffer.resize(4, 10);
                  expect(buffer.y, 9);
                  expect(buffer.ydisp, 5);
                  expect(buffer.ybase, 7);
                  expect(buffer.lines.length, 17);
                  for (var i = 0; i < 10; i++) {
                    expect(lineAt(i).translateToString(), '    ');
                  }
                  expect(lineAt(10).translateToString(), 'abcd');
                  expect(lineAt(11).translateToString(), 'efgh');
                  expect(lineAt(12).translateToString(), 'ijkl');
                  for (var i = 13; i < 17; i++) {
                    expect(lineAt(i).translateToString(), '    ');
                  }
                  expectWrappedLines(<int>[]);
                });
              });
            });
          });
          group('viewport filled, no scrollback remaining', () {
            // ybase === 0 doesn't make sense here as scrollback=0 isn't really
            // supported
            group('ybase !== 0', () {
              setUp(() {
                optionsService.options.scrollback = 10;
                // Add 10 empty rows to start
                for (var i = 0; i < 10; i++) {
                  buffer.lines.splice(0, 0, [
                    buffer.getBlankLine(defaultAttrData),
                  ]);
                }
                buffer.y = 9;
                buffer.ybase = 10;
              });
              group('&& ydisp === ybase', () {
                test('should trim lines and keep ydisp = ybase', () {
                  buffer.ydisp = 10;
                  buffer.resize(4, 10);
                  expect(buffer.y, 9);
                  expect(buffer.ydisp, 7);
                  expect(buffer.ybase, 7);
                  expect(buffer.lines.length, 17);
                  for (var i = 0; i < 10; i++) {
                    expect(lineAt(i).translateToString(), '    ');
                  }
                  expect(lineAt(10).translateToString(), 'abcd');
                  expect(lineAt(11).translateToString(), 'efgh');
                  expect(lineAt(12).translateToString(), 'ijkl');
                  for (var i = 13; i < 17; i++) {
                    expect(lineAt(i).translateToString(), '    ');
                  }
                  expectWrappedLines(<int>[]);
                });
              });
              group('&& ydisp !== ybase', () {
                test('should trim lines and not change ydisp', () {
                  buffer.ydisp = 5;
                  buffer.resize(4, 10);
                  expect(buffer.y, 9);
                  expect(buffer.ydisp, 5);
                  expect(buffer.ybase, 7);
                  expect(buffer.lines.length, 17);
                  for (var i = 0; i < 10; i++) {
                    expect(lineAt(i).translateToString(), '    ');
                  }
                  expect(lineAt(10).translateToString(), 'abcd');
                  expect(lineAt(11).translateToString(), 'efgh');
                  expect(lineAt(12).translateToString(), 'ijkl');
                  for (var i = 13; i < 17; i++) {
                    expect(lineAt(i).translateToString(), '    ');
                  }
                  expectWrappedLines(<int>[]);
                });
              });
            });
          });
        });
        group('reflowSmaller cases', () {
          setUp(() {
            // Setup buffer state:
            // 'abcd'
            // 'efgh' (wrapped)
            // 'ijkl'
            // '    '
            // '    '
            // '    '
            // '    '
            // '    '
            // '    '
            // '    '
            buffer.fillViewportRows();
            buffer.resize(4, 10);
            lineAt(0).set(0, (0, 'a', 1, 'a'.codeUnitAt(0)));
            lineAt(0).set(1, (0, 'b', 1, 'b'.codeUnitAt(0)));
            lineAt(0).set(2, (0, 'c', 1, 'c'.codeUnitAt(0)));
            lineAt(0).set(3, (0, 'd', 1, 'd'.codeUnitAt(0)));
            lineAt(1).set(0, (0, 'e', 1, 'e'.codeUnitAt(0)));
            lineAt(1).set(1, (0, 'f', 1, 'f'.codeUnitAt(0)));
            lineAt(1).set(2, (0, 'g', 1, 'g'.codeUnitAt(0)));
            lineAt(1).set(3, (0, 'h', 1, 'h'.codeUnitAt(0)));
            lineAt(2).set(0, (0, 'i', 1, 'i'.codeUnitAt(0)));
            lineAt(2).set(1, (0, 'j', 1, 'j'.codeUnitAt(0)));
            lineAt(2).set(2, (0, 'k', 1, 'k'.codeUnitAt(0)));
            lineAt(2).set(3, (0, 'l', 1, 'l'.codeUnitAt(0)));
          });
          group('viewport not yet filled', () {
            test('should move the cursor down', () {
              buffer.y = 3;
              buffer.resize(2, 10);
              expect(buffer.y, 6);
              expect(buffer.ydisp, 0);
              expect(buffer.ybase, 0);
              expect(buffer.lines.length, 10);
              expect(lineAt(0).translateToString(), 'ab');
              expect(lineAt(1).translateToString(), 'cd');
              expect(lineAt(2).translateToString(), 'ef');
              expect(lineAt(3).translateToString(), 'gh');
              expect(lineAt(4).translateToString(), 'ij');
              expect(lineAt(5).translateToString(), 'kl');
              for (var i = 6; i < 10; i++) {
                expect(lineAt(i).translateToString(), '  ');
              }
              expectWrappedLines(<int>[1, 3, 5]);
            });
          });
          group('viewport filled, scrollback remaining', () {
            setUp(() {
              buffer.y = 9;
            });
            group('ybase === 0', () {
              test('should trim the top', () {
                buffer.resize(2, 10);
                expect(buffer.y, 9);
                expect(buffer.ydisp, 3);
                expect(buffer.ybase, 3);
                expect(buffer.lines.length, 13);
                expect(lineAt(0).translateToString(), 'ab');
                expect(lineAt(1).translateToString(), 'cd');
                expect(lineAt(2).translateToString(), 'ef');
                expect(lineAt(3).translateToString(), 'gh');
                expect(lineAt(4).translateToString(), 'ij');
                expect(lineAt(5).translateToString(), 'kl');
                for (var i = 6; i < 13; i++) {
                  expect(lineAt(i).translateToString(), '  ');
                }
                expectWrappedLines(<int>[1, 3, 5]);
              });
            });
            group('ybase !== 0', () {
              setUp(() {
                // Add 10 empty rows to start
                for (var i = 0; i < 10; i++) {
                  buffer.lines.splice(0, 0, [
                    buffer.getBlankLine(defaultAttrData),
                  ]);
                }
                buffer.ybase = 10;
              });
              group('&& ydisp === ybase', () {
                test('should adjust the viewport and keep ydisp = ybase', () {
                  buffer.ydisp = 10;
                  buffer.resize(2, 10);
                  expect(buffer.ydisp, 13);
                  expect(buffer.ybase, 13);
                  expect(buffer.lines.length, 23);
                  for (var i = 0; i < 10; i++) {
                    expect(lineAt(i).translateToString(), '  ');
                  }
                  expect(lineAt(10).translateToString(), 'ab');
                  expect(lineAt(11).translateToString(), 'cd');
                  expect(lineAt(12).translateToString(), 'ef');
                  expect(lineAt(13).translateToString(), 'gh');
                  expect(lineAt(14).translateToString(), 'ij');
                  expect(lineAt(15).translateToString(), 'kl');
                  for (var i = 16; i < 23; i++) {
                    expect(lineAt(i).translateToString(), '  ');
                  }
                  expectWrappedLines(<int>[11, 13, 15]);
                });
              });
              group('&& ydisp !== ybase', () {
                test('should keep ydisp at the same value', () {
                  buffer.ydisp = 5;
                  buffer.resize(2, 10);
                  expect(buffer.ydisp, 5);
                  expect(buffer.ybase, 13);
                  expect(buffer.lines.length, 23);
                  for (var i = 0; i < 10; i++) {
                    expect(lineAt(i).translateToString(), '  ');
                  }
                  expect(lineAt(10).translateToString(), 'ab');
                  expect(lineAt(11).translateToString(), 'cd');
                  expect(lineAt(12).translateToString(), 'ef');
                  expect(lineAt(13).translateToString(), 'gh');
                  expect(lineAt(14).translateToString(), 'ij');
                  expect(lineAt(15).translateToString(), 'kl');
                  for (var i = 16; i < 23; i++) {
                    expect(lineAt(i).translateToString(), '  ');
                  }
                  expectWrappedLines(<int>[11, 13, 15]);
                });
              });
            });
          });
          group('viewport filled, no scrollback remaining', () {
            // ybase === 0 doesn't make sense here as scrollback=0 isn't really
            // supported
            group('ybase !== 0', () {
              setUp(() {
                optionsService.options.scrollback = 10;
                // Add 10 empty rows to start
                for (var i = 0; i < 10; i++) {
                  buffer.lines.splice(0, 0, [
                    buffer.getBlankLine(defaultAttrData),
                  ]);
                }
                buffer.ybase = 10;
              });
              group('&& ydisp === ybase', () {
                test('should trim lines and keep ydisp = ybase', () {
                  buffer.ydisp = 10;
                  buffer.y = 13;
                  buffer.resize(2, 10);
                  expect(buffer.ydisp, 10);
                  expect(buffer.ybase, 10);
                  expect(buffer.lines.length, 20);
                  for (var i = 0; i < 7; i++) {
                    expect(lineAt(i).translateToString(), '  ');
                  }
                  expect(lineAt(7).translateToString(), 'ab');
                  expect(lineAt(8).translateToString(), 'cd');
                  expect(lineAt(9).translateToString(), 'ef');
                  expect(lineAt(10).translateToString(), 'gh');
                  expect(lineAt(11).translateToString(), 'ij');
                  expect(lineAt(12).translateToString(), 'kl');
                  for (var i = 13; i < 20; i++) {
                    expect(lineAt(i).translateToString(), '  ');
                  }
                  expectWrappedLines(<int>[8, 10, 12]);
                });
              });
              group('&& ydisp !== ybase', () {
                test('should trim lines and not change ydisp', () {
                  buffer.ydisp = 5;
                  buffer.y = 13;
                  buffer.resize(2, 10);
                  expect(buffer.ydisp, 5);
                  expect(buffer.ybase, 10);
                  expect(buffer.lines.length, 20);
                  for (var i = 0; i < 7; i++) {
                    expect(lineAt(i).translateToString(), '  ');
                  }
                  expect(lineAt(7).translateToString(), 'ab');
                  expect(lineAt(8).translateToString(), 'cd');
                  expect(lineAt(9).translateToString(), 'ef');
                  expect(lineAt(10).translateToString(), 'gh');
                  expect(lineAt(11).translateToString(), 'ij');
                  expect(lineAt(12).translateToString(), 'kl');
                  for (var i = 13; i < 20; i++) {
                    expect(lineAt(i).translateToString(), '  ');
                  }
                  expectWrappedLines(<int>[8, 10, 12]);
                });
              });
            });
          });
        });
      });
    });

    group('buffer marked to have no scrollback', () {
      test('should always have a scrollback of 0', () {
        // Test size on initialization
        buffer = TestBuffer(
          false,
          MockOptionsService(ITerminalOptions(scrollback: 1000)),
          bufferService,
          MockLogService(),
        );
        buffer.fillViewportRows();
        expect(buffer.lines.maxLength, initRows);
        // Test size on buffer increase
        buffer.resize(initCols, initRows * 2);
        expect(buffer.lines.maxLength, initRows * 2);
        // Test size on buffer decrease
        buffer.resize(initCols, initRows ~/ 2);
        expect(buffer.lines.maxLength, initRows ~/ 2);
      });
    });

    group('addMarker', () {
      test('should adjust a marker line when the buffer is trimmed', () {
        buffer = TestBuffer(
          true,
          MockOptionsService(ITerminalOptions(scrollback: 0)),
          bufferService,
          MockLogService(),
        );
        buffer.fillViewportRows();
        final marker = buffer.addMarker(buffer.lines.length - 1);
        expect(marker.line, buffer.lines.length - 1);
        buffer.lines.onTrimEmitter.fire(1);
        expect(marker.line, buffer.lines.length - 2);
      });
      test('should dispose of a marker if it is trimmed off the buffer', () {
        buffer = TestBuffer(
          true,
          MockOptionsService(ITerminalOptions(scrollback: 0)),
          bufferService,
          MockLogService(),
        );
        buffer.fillViewportRows();
        expect(buffer.markers.length, 0);
        final marker = buffer.addMarker(0);
        expect(marker.isDisposed, false);
        expect(buffer.markers.length, 1);
        buffer.lines.onTrimEmitter.fire(1);
        expect(marker.isDisposed, true);
        expect(buffer.markers.length, 0);
      });
      test('should call onDispose', () {
        final eventStack = <String>[];
        buffer = TestBuffer(
          true,
          MockOptionsService(ITerminalOptions(scrollback: 0)),
          bufferService,
          MockLogService(),
        );
        buffer.fillViewportRows();
        expect(buffer.markers.length, 0);
        final marker = buffer.addMarker(0);
        marker.onDispose((_) => eventStack.add('disposed'));
        expect(marker.isDisposed, false);
        expect(buffer.markers.length, 1);
        buffer.lines.onTrimEmitter.fire(1);
        expect(marker.isDisposed, true);
        expect(buffer.markers.length, 0);
        expect(eventStack, equals(['disposed']));
      });
    });

    group('translateBufferLineToString', () {
      test('should handle selecting a section of ascii text', () {
        final line = BufferLine(4);
        line.setCell(0, createCellData(0, 'a', 1));
        line.setCell(1, createCellData(0, 'b', 1));
        line.setCell(2, createCellData(0, 'c', 1));
        line.setCell(3, createCellData(0, 'd', 1));
        buffer.lines.set(0, line);

        final str = buffer.translateBufferLineToString(0, true, 0, 2);
        expect(str, 'ab');
      });

      test(
        'should handle a cut-off double width character by including it',
        () {
          final line = BufferLine(3);
          line.setCell(0, createCellData(0, '語', 2));
          line.setCell(1, createCellData(0, '', 0));
          line.setCell(2, createCellData(0, 'a', 1));
          buffer.lines.set(0, line);

          final str1 = buffer.translateBufferLineToString(0, true, 0, 1);
          expect(str1, '語');
        },
      );

      test('should handle a zero width character in the middle of the string by not including it', () {
        final line = BufferLine(3);
        line.setCell(0, createCellData(0, '語', 2));
        line.setCell(1, createCellData(0, '', 0));
        line.setCell(2, createCellData(0, 'a', 1));
        buffer.lines.set(0, line);

        final str0 = buffer.translateBufferLineToString(0, true, 0, 1);
        expect(str0, '語');

        final str1 = buffer.translateBufferLineToString(0, true, 0, 2);
        expect(str1, '語');

        final str2 = buffer.translateBufferLineToString(0, true, 0, 3);
        expect(str2, '語a');
      });

      test('should handle single width emojis', () {
        final line = BufferLine(2);
        line.setCell(0, createCellData(0, '😁', 1));
        line.setCell(1, createCellData(0, 'a', 1));
        buffer.lines.set(0, line);

        final str1 = buffer.translateBufferLineToString(0, true, 0, 1);
        expect(str1, '😁');

        final str2 = buffer.translateBufferLineToString(0, true, 0, 2);
        expect(str2, '😁a');
      });

      test('should handle double width emojis', () {
        final line = BufferLine(2);
        line.setCell(0, createCellData(0, '😁', 2));
        line.setCell(1, createCellData(0, '', 0));
        buffer.lines.set(0, line);

        final str1 = buffer.translateBufferLineToString(0, true, 0, 1);
        expect(str1, '😁');

        final str2 = buffer.translateBufferLineToString(0, true, 0, 2);
        expect(str2, '😁');

        final line2 = BufferLine(3);
        line2.setCell(0, createCellData(0, '😁', 2));
        line2.setCell(1, createCellData(0, '', 0));
        line2.setCell(2, createCellData(0, 'a', 1));
        buffer.lines.set(0, line2);

        final str3 = buffer.translateBufferLineToString(0, true, 0, 3);
        expect(str3, '😁a');
      });
    });

    group('memory cleanup after shrinking', () {
      test('should realign memory from idle task execution', () async {
        buffer.fillViewportRows();

        // shrink more than 2 times to trigger lazy memory cleanup
        buffer.resize(initCols ~/ 2 - 1, initRows);

        // sync
        for (var i = 0; i < initRows; i++) {
          final line = lineAt(i) as BufferLine;
          // line memory is still at old size from initialization
          expect(line.data.buffer.lengthInBytes, initCols * 3 * 4);
          // array.length and .length get immediately adjusted
          expect(line.data.length, (initCols ~/ 2 - 1) * 3);
          expect(line.length, initCols ~/ 2 - 1);
        }

        // wait for a bit to give IdleTaskQueue a chance to kick in
        // and finish memory cleaning
        await Future<void>.delayed(const Duration(milliseconds: 30));

        // cleanup should have realigned memory with exact bytelength
        for (var i = 0; i < initRows; i++) {
          final line = lineAt(i) as BufferLine;
          expect(line.data.buffer.lengthInBytes, (initCols ~/ 2 - 1) * 3 * 4);
        }
      });
    });
  });
}
