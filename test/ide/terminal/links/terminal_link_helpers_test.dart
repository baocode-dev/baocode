/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/links/test/browser/
// terminalLinkHelpers.test.ts, with tests of `updateLinkWithRelativeCwd`
// and `getXtermRangesByAttr` added.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/links/terminal_link_helpers.dart';
import 'package:bao_xterm/headless/public/terminal.dart';
import 'package:bao_xterm/typings/xterm_headless.dart' hide Terminal;
import 'package:path/path.dart' as p;

IBufferRange range((int, int) start, (int, int) end) => IBufferRange(
  start: IBufferCellPosition(x: start.$1, y: start.$2),
  end: IBufferCellPosition(x: end.$1, y: end.$2),
);

void main() {
  group('Workbench - Terminal Link Helpers', () {
    group('convertLinkRangeToBuffer', () {
      test('should convert ranges for ascii characters', () {
        final lines = createBufferLineArray([
          (text: 'AA http://t', width: 11),
          (text: '.com/f/', width: 8),
        ]);
        final bufferRange = convertLinkRangeToBuffer(lines, 11, (
          startColumn: 4,
          startLineNumber: 1,
          endColumn: 19,
          endLineNumber: 1,
        ), 0);
        expect(bufferRange, range((4, 1), (7, 2)));
      });
      test('should convert ranges for wide characters before the link', () {
        final lines = createBufferLineArray([
          (text: 'A文 http://', width: 11),
          (text: 't.com/f/', width: 9),
        ]);
        final bufferRange = convertLinkRangeToBuffer(lines, 11, (
          startColumn: 4,
          startLineNumber: 1,
          endColumn: 19,
          endLineNumber: 1,
        ), 0);
        expect(bufferRange, range((4 + 1, 1), (7 + 1, 2)));
      });
      test(
        'should give correct range for links containing multi-character emoji',
        () {
          final lines = createBufferLineArray([
            (text: 'A🙂 http://', width: 11),
          ]);
          final bufferRange = convertLinkRangeToBuffer(lines, 11, (
            startColumn: 0 + 1,
            startLineNumber: 1,
            endColumn: 2 + 1,
            endLineNumber: 1,
          ), 0);
          expect(bufferRange, range((1, 1), (2, 1)));
        },
      );
      test(
        'should convert ranges for combining characters before the link',
        () {
          final lines = createBufferLineArray([
            (text: 'A🙂 http://', width: 11),
            (text: 't.com/f/', width: 9),
          ]);
          final bufferRange = convertLinkRangeToBuffer(lines, 11, (
            startColumn: 4 + 1,
            startLineNumber: 1,
            endColumn: 19 + 1,
            endLineNumber: 1,
          ), 0);
          expect(bufferRange, range((6, 1), (9, 2)));
        },
      );
      test('should convert ranges for wide characters inside the link', () {
        final lines = createBufferLineArray([
          (text: 'AA http://t', width: 11),
          (text: '.com/文/', width: 8),
        ]);
        final bufferRange = convertLinkRangeToBuffer(lines, 11, (
          startColumn: 4,
          startLineNumber: 1,
          endColumn: 19,
          endLineNumber: 1,
        ), 0);
        expect(bufferRange, range((4, 1), (7 + 1, 2)));
      });
      test(
        'should convert ranges for wide characters before and inside the link',
        () {
          final lines = createBufferLineArray([
            (text: 'A文 http://', width: 11),
            (text: 't.com/文/', width: 9),
          ]);
          final bufferRange = convertLinkRangeToBuffer(lines, 11, (
            startColumn: 4,
            startLineNumber: 1,
            endColumn: 19,
            endLineNumber: 1,
          ), 0);
          expect(bufferRange, range((4 + 1, 1), (7 + 2, 2)));
        },
      );
      test(
        'should convert ranges for emoji before and wide inside the link',
        () {
          final lines = createBufferLineArray([
            (text: 'A🙂 http://', width: 11),
            (text: 't.com/文/', width: 9),
          ]);
          final bufferRange = convertLinkRangeToBuffer(lines, 11, (
            startColumn: 4 + 1,
            startLineNumber: 1,
            endColumn: 19 + 1,
            endLineNumber: 1,
          ), 0);
          expect(bufferRange, range((6, 1), (10 + 1, 2)));
        },
      );
      test(
        'should convert ranges for ascii characters (link starts on wrapped)',
        () {
          final lines = createBufferLineArray([
            (text: 'AAAAAAAAAAA', width: 11),
            (text: 'AA http://t', width: 11),
            (text: '.com/f/', width: 8),
          ]);
          final bufferRange = convertLinkRangeToBuffer(lines, 11, (
            startColumn: 15,
            startLineNumber: 1,
            endColumn: 30,
            endLineNumber: 1,
          ), 0);
          expect(bufferRange, range((4, 2), (7, 3)));
        },
      );
      test('should convert ranges for wide characters before the link (link starts on wrapped)', () {
        final lines = createBufferLineArray([
          (text: 'AAAAAAAAAAA', width: 11),
          (text: 'A文 http://', width: 11),
          (text: 't.com/f/', width: 9),
        ]);
        final bufferRange = convertLinkRangeToBuffer(lines, 11, (
          startColumn: 15,
          startLineNumber: 1,
          endColumn: 30,
          endLineNumber: 1,
        ), 0);
        expect(bufferRange, range((4 + 1, 2), (7 + 1, 3)));
      });
      test('regression test #147619: 获取模板 25235168 的预览图失败', () {
        final lines = createBufferLineArray([
          (text: '获取模板 25235168 的预览图失败', width: 30),
        ]);
        expect(
          convertLinkRangeToBuffer(lines, 30, (
            startColumn: 1,
            startLineNumber: 1,
            endColumn: 5,
            endLineNumber: 1,
          ), 0),
          range((1, 1), (8, 1)),
        );
        expect(
          convertLinkRangeToBuffer(lines, 30, (
            startColumn: 6,
            startLineNumber: 1,
            endColumn: 14,
            endLineNumber: 1,
          ), 0),
          range((10, 1), (17, 1)),
        );
        expect(
          convertLinkRangeToBuffer(lines, 30, (
            startColumn: 15,
            startLineNumber: 1,
            endColumn: 21,
            endLineNumber: 1,
          ), 0),
          range((19, 1), (30, 1)),
        );
      });
      test('should convert ranges for wide characters inside the link (link starts on wrapped)', () {
        final lines = createBufferLineArray([
          (text: 'AAAAAAAAAAA', width: 11),
          (text: 'AA http://t', width: 11),
          (text: '.com/文/', width: 8),
        ]);
        final bufferRange = convertLinkRangeToBuffer(lines, 11, (
          startColumn: 15,
          startLineNumber: 1,
          endColumn: 30,
          endLineNumber: 1,
        ), 0);
        expect(bufferRange, range((4, 2), (7 + 1, 3)));
      });
      test('should convert ranges for wide characters before and inside the link #2', () {
        final lines = createBufferLineArray([
          (text: 'AAAAAAAAAAA', width: 11),
          (text: 'A文 http://', width: 11),
          (text: 't.com/文/', width: 9),
        ]);
        final bufferRange = convertLinkRangeToBuffer(lines, 11, (
          startColumn: 15,
          startLineNumber: 1,
          endColumn: 30,
          endLineNumber: 1,
        ), 0);
        expect(bufferRange, range((4 + 1, 2), (7 + 2, 3)));
      });
      test(
        'should convert ranges for several wide characters before the link',
        () {
          final lines = createBufferLineArray([
            (text: 'A文文AAAAAA', width: 11),
            (text: 'AA文文 http', width: 11),
            (text: '://t.com/f/', width: 11),
          ]);
          final bufferRange = convertLinkRangeToBuffer(lines, 11, (
            startColumn: 15,
            startLineNumber: 1,
            endColumn: 30,
            endLineNumber: 1,
          ), 0);
          // This test ensures that the start offset is applied to the end
          // before it's counted
          expect(bufferRange, range((3 + 4, 2), (6 + 4, 3)));
        },
      );
      test('should convert ranges for several wide characters before and inside the link', () {
        final lines = createBufferLineArray([
          (text: 'A文文AAAAAA', width: 11),
          (text: 'AA文文 http', width: 11),
          (text: '://t.com/文', width: 11),
          (text: '文/', width: 3),
        ]);
        final bufferRange = convertLinkRangeToBuffer(lines, 11, (
          startColumn: 14,
          startLineNumber: 1,
          endColumn: 31,
          endLineNumber: 1,
        ), 0);
        // This test ensures that the start offset is applies to the end
        // before it's counted
        expect(bufferRange, range((5, 2), (1, 4)));
      });

      test(
        'converts a range of the real buffer with wide characters',
        () async {
          final xterm = Terminal(ITerminalOptions(cols: 11, rows: 5));
          await _write(xterm, 'A文 http://t.com/文/');
          final buffer = xterm.buffer.active;
          final lines = [buffer.getLine(0)!, buffer.getLine(1)!];
          expect(lines[1].isWrapped, isTrue);
          expect(
            convertLinkRangeToBuffer(lines, 11, (
              startColumn: 4,
              startLineNumber: 1,
              endColumn: 19,
              endLineNumber: 1,
            ), 0),
            range((4 + 1, 1), (7 + 2, 2)),
          );
          xterm.dispose();
        },
      );
    });

    group('getXtermLineContent', () {
      test('joins the rows of a wrapped line', () async {
        final xterm = Terminal(ITerminalOptions(cols: 5, rows: 5));
        await _write(xterm, 'abcdefg\r\nxyz');
        final buffer = xterm.buffer.active;
        expect(getXtermLineContent(buffer, 0, 1, 5), 'abcdefg');
        expect(getXtermLineContent(buffer, 2, 2, 5), 'xyz');
        xterm.dispose();
      });
    });

    group('getXtermRangesByAttr', () {
      test('splits rows where the style changes', () async {
        final xterm = Terminal(ITerminalOptions(cols: 10, rows: 5));
        await _write(xterm, 'ab\x1b[1mcde\x1b[0mfg');
        final ranges = getXtermRangesByAttr(xterm.buffer.active, 0, 0, 10);
        expect(ranges, [range((0, 0), (2, 0)), range((2, 0), (5, 0))]);
        xterm.dispose();
      });
    });

    group('updateLinkWithRelativeCwd', () {
      test('is null without a cwd', () {
        expect(updateLinkWithRelativeCwd(null, 'foo', p.posix), isNull);
        expect(updateLinkWithRelativeCwd('', 'foo', p.posix), isNull);
      });
      test('resolves a file name against the cwd', () {
        expect(updateLinkWithRelativeCwd('/home/common', 'foo', p.posix), [
          '/home/common/foo',
        ]);
      });
      test('prefers the cwd plus the link, then drops common folders', () {
        expect(
          updateLinkWithRelativeCwd('/home/common', 'common/file', p.posix),
          ['/home/common/common/file', '/home/common/file'],
        );
      });
      test('uses the Windows separator', () {
        expect(updateLinkWithRelativeCwd(r'C:\a\b', r'c\d', p.windows), [
          r'C:\a\b\c\d',
        ]);
      });
    });
  });
}

Future<void> _write(Terminal xterm, String data) {
  final written = Completer<void>();
  xterm.write(data, written.complete);
  return written.future;
}

const String testWideChar = '文';
const String testNullChar = 'C';

List<IBufferLine> createBufferLineArray(
  List<({String text, int width})> lines,
) {
  final result = <IBufferLine>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    result.add(TestBufferLine(l.text, l.width, i + 1 != lines.length));
  }
  return result;
}

class TestBufferLine implements IBufferLine {
  TestBufferLine(this._text, this.length, this.isWrapped);

  final String _text;

  @override
  final int length;

  @override
  final bool isWrapped;

  String _charAt(int i) => i < _text.length ? _text[i] : '';

  @override
  IBufferCell? getCell(int x, [IBufferCell? cell]) {
    // Create a fake line of cells and use that to resolve the width
    final cells = <String>[];
    var wideNullCellOffset =
        0; // There is no null 0 width char after a wide char
    const emojiOffset = 0; // Skip chars as emoji are multiple characters
    for (var i = 0; i <= x - wideNullCellOffset + emojiOffset; i++) {
      var char = _charAt(i);
      if (char == '\ud83d') {
        // Make "🙂"
        char += '\ude42';
      }
      cells.add(char);
      if (_charAt(i) == testWideChar ||
          (char.isNotEmpty && char.codeUnitAt(0) > 255)) {
        // Skip the next character as it's width is 0
        cells.add(testNullChar);
        wideNullCellOffset++;
      }
    }
    return _TestBufferCell(x >= cells.length ? '' : cells[x]);
  }

  @override
  String translateToString([
    bool? trimRight,
    int? startColumn,
    int? endColumn,
  ]) {
    throw UnimplementedError('Method not implemented.');
  }
}

class _TestBufferCell implements IBufferCell {
  _TestBufferCell(this._chars);

  final String _chars;

  @override
  String getChars() => _chars;

  @override
  int getWidth() {
    switch (_chars) {
      case testWideChar:
        return 2;
      case testNullChar:
        return 0;
      default:
        // Naive measurement, assume anything our of ascii in tests are wide
        // ('' is NaN in JavaScript, which is not > 255.)
        if (_chars.isNotEmpty && _chars.codeUnitAt(0) > 255) {
          return 2;
        }
        return 1;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
