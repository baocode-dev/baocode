// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/InputHandler.test.ts (c58ea36).
//
// `TestInputHandler` reads the title stacks straight off `InputHandler`
// (public there). Upstream's "big chunks" test monkeypatches
// `_parser.parse`; here the handler gets a recording parser instead.
// `assert.deepEqual` of color events, link data and extended attributes
// compares their fields. The async handler tests' `console.log` data listener
// is a no-op (it only echoed the terminal's replies).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/attribute_data.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/buffer_line.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/cell_data.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/constants.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/types.dart';
import 'package:baocode/ide/terminal/xterm/common/data/charsets.dart';
import 'package:baocode/ide/terminal/xterm/common/input_handler.dart';
import 'package:baocode/ide/terminal/xterm/common/parser/escape_sequence_parser.dart';
import 'package:baocode/ide/terminal/xterm/common/parser/params.dart';
import 'package:baocode/ide/terminal/xterm/common/services/buffer_service.dart';
import 'package:baocode/ide/terminal/xterm/common/services/charset_service.dart';
import 'package:baocode/ide/terminal/xterm/common/services/core_service.dart';
import 'package:baocode/ide/terminal/xterm/common/services/osc_link_service.dart';
import 'package:baocode/ide/terminal/xterm/common/services/services.dart';
import 'package:baocode/ide/terminal/xterm/common/types.dart';
import 'package:baocode/ide/terminal/xterm/typings/xterm.dart'
    show IFunctionIdentifier;

import 'test_utils.dart';

List<int> getCursor(IBufferService bufferService) {
  return <int>[bufferService.buffer.x, bufferService.buffer.y];
}

List<String> getLines(IBufferService bufferService, [int? limit]) {
  limit ??= bufferService.rows;
  final res = <String>[];
  for (var i = 0; i < limit; ++i) {
    final line = bufferService.buffer.lines.get(i);
    if (line != null) {
      res.add(line.translateToString(true));
    }
  }
  return res;
}

class TestInputHandler extends InputHandler {
  TestInputHandler(
    super.bufferService,
    super.charsetService,
    super.coreService,
    super.logService,
    super.optionsService,
    super.oscLinkService,
    super.mouseStateService,
    super.unicodeService, [
    super.parser,
  ]);

  IAttributeData get curAttrData => getAttrData();

  /// Promise based parse call to await the full resolve of given input data.
  /// This is useful to test async handlers in inputhandler directly.
  Future<void> parseP(Object data) async {
    Future<bool>? result;
    bool? prev;
    while ((result = parse(data, prev)) != null) {
      prev = await result;
    }
  }
}

/// Stands in for upstream's replacement of `_parser.parse`.
class _RecordingParser extends EscapeSequenceParser {
  final List<List<int>> calls = <List<int>>[];

  @override
  Future<bool>? parse(Uint32List data, int length, [bool? promiseResult]) {
    calls.add(<int>[data.length, length]);
    return null;
  }
}

/// A color request as upstream's object literal: only the keys it has.
Map<String, Object?> _colorRequest(IColorRequest request) {
  return switch (request) {
    IColorReportRequest() => <String, Object?>{
      'type': request.type,
      'index': request.index,
    },
    IColorSetRequest() => <String, Object?>{
      'type': request.type,
      'index': request.index,
      'color': request.color,
    },
    IColorRestoreRequest() => <String, Object?>{
      'type': request.type,
      if (request.index != null) 'index': request.index,
    },
  };
}

List<List<Map<String, Object?>>> _colorEvents(List<IColorEvent> stack) {
  return <List<Map<String, Object?>>>[
    for (final event in stack)
      <Map<String, Object?>>[
        for (final request in event) _colorRequest(request),
      ],
  ];
}

Map<String, Object?> _extendedFields(IExtendedAttrs ext) {
  return <String, Object?>{
    'ext': ext.ext,
    'urlId': ext.urlId,
    'underlineStyle': ext.underlineStyle,
    'underlineColor': ext.underlineColor,
    'underlineVariantOffset': ext.underlineVariantOffset,
    'payload': ext.payload,
  };
}

void main() {
  group('InputHandler', () {
    late IBufferService bufferService;
    late ICoreService coreService;
    late MockOptionsService optionsService;
    late IOscLinkService oscLinkService;
    late TestInputHandler inputHandler;

    setUp(() {
      optionsService = MockOptionsService();
      bufferService = BufferService(optionsService, MockLogService());
      bufferService.resize(80, 30);
      coreService = CoreService(
        bufferService,
        MockLogService(),
        optionsService,
      );
      oscLinkService = OscLinkService(bufferService);

      inputHandler = TestInputHandler(
        bufferService,
        MockCharsetService(),
        coreService,
        MockLogService(),
        optionsService,
        oscLinkService,
        MockMouseStateService(),
        MockUnicodeService(),
      );
    });

    group('SL/SR/DECIC/DECDC', () {
      setUp(() {
        bufferService.resize(5, 5);
        optionsService.options.scrollback = 1;
        bufferService.reset();
      });
      test('SL (scrollLeft)', () async {
        await inputHandler.parseP('12345' * 6);
        await inputHandler.parseP('\x1b[ @');
        expect(getLines(bufferService, 6), <String>[
          '12345',
          '2345',
          '2345',
          '2345',
          '2345',
          '2345',
        ]);
        await inputHandler.parseP('\x1b[0 @');
        expect(getLines(bufferService, 6), <String>[
          '12345',
          '345',
          '345',
          '345',
          '345',
          '345',
        ]);
        await inputHandler.parseP('\x1b[2 @');
        expect(getLines(bufferService, 6), <String>[
          '12345',
          '5',
          '5',
          '5',
          '5',
          '5',
        ]);
      });
      test('SR (scrollRight)', () async {
        await inputHandler.parseP('12345' * 6);
        await inputHandler.parseP('\x1b[ A');
        expect(getLines(bufferService, 6), <String>[
          '12345',
          ' 1234',
          ' 1234',
          ' 1234',
          ' 1234',
          ' 1234',
        ]);
        await inputHandler.parseP('\x1b[0 A');
        expect(getLines(bufferService, 6), <String>[
          '12345',
          '  123',
          '  123',
          '  123',
          '  123',
          '  123',
        ]);
        await inputHandler.parseP('\x1b[2 A');
        expect(getLines(bufferService, 6), <String>[
          '12345',
          '    1',
          '    1',
          '    1',
          '    1',
          '    1',
        ]);
      });
      test('insertColumns (DECIC)', () async {
        await inputHandler.parseP('12345' * 6);
        await inputHandler.parseP('\x1b[3;3H');
        await inputHandler.parseP("\x1b['}");
        expect(getLines(bufferService, 6), <String>[
          '12345',
          '12 34',
          '12 34',
          '12 34',
          '12 34',
          '12 34',
        ]);
        bufferService.reset();
        await inputHandler.parseP('12345' * 6);
        await inputHandler.parseP('\x1b[3;3H');
        await inputHandler.parseP("\x1b[1'}");
        expect(getLines(bufferService, 6), <String>[
          '12345',
          '12 34',
          '12 34',
          '12 34',
          '12 34',
          '12 34',
        ]);
        bufferService.reset();
        await inputHandler.parseP('12345' * 6);
        await inputHandler.parseP('\x1b[3;3H');
        await inputHandler.parseP("\x1b[2'}");
        expect(getLines(bufferService, 6), <String>[
          '12345',
          '12  3',
          '12  3',
          '12  3',
          '12  3',
          '12  3',
        ]);
      });
      test('deleteColumns (DECDC)', () async {
        await inputHandler.parseP('12345' * 6);
        await inputHandler.parseP('\x1b[3;3H');
        await inputHandler.parseP("\x1b['~");
        expect(getLines(bufferService, 6), <String>[
          '12345',
          '1245',
          '1245',
          '1245',
          '1245',
          '1245',
        ]);
        bufferService.reset();
        await inputHandler.parseP('12345' * 6);
        await inputHandler.parseP('\x1b[3;3H');
        await inputHandler.parseP("\x1b[1'~");
        expect(getLines(bufferService, 6), <String>[
          '12345',
          '1245',
          '1245',
          '1245',
          '1245',
          '1245',
        ]);
        bufferService.reset();
        await inputHandler.parseP('12345' * 6);
        await inputHandler.parseP('\x1b[3;3H');
        await inputHandler.parseP("\x1b[2'~");
        expect(getLines(bufferService, 6), <String>[
          '12345',
          '125',
          '125',
          '125',
          '125',
          '125',
        ]);
      });
    });

    group('BS with reverseWraparound set/unset', () {
      const ttyBS = '\x08 \x08'; // tty ICANON sends <BS SP BS> on pressing BS
      setUp(() {
        bufferService.resize(5, 5);
        optionsService.options.scrollback = 1;
        bufferService.reset();
      });
      group('reverseWraparound set', () {
        test('should not reverse outside of scroll margins', () async {
          // prepare buffer content
          await inputHandler.parseP('#####abcdefghijklmnopqrstuvwxy');
          expect(getLines(bufferService, 6), <String>[
            '#####',
            'abcde',
            'fghij',
            'klmno',
            'pqrst',
            'uvwxy',
          ]);
          expect(bufferService.buffers.active.ydisp, 1);
          expect(bufferService.buffers.active.x, 5);
          expect(bufferService.buffers.active.y, 4);
          await inputHandler.parseP(ttyBS * 100);
          expect(getLines(bufferService, 6), <String>[
            '#####',
            'abcde',
            'fghij',
            'klmno',
            'pqrst',
            '    y',
          ]);

          await inputHandler.parseP('\x1b[?45h');
          await inputHandler.parseP('uvwxy');

          // set top/bottom to 1/3 (0-based)
          await inputHandler.parseP('\x1b[2;4r');
          // place cursor below scroll bottom
          bufferService.buffers.active.x = 5;
          bufferService.buffers.active.y = 4;
          await inputHandler.parseP(ttyBS * 100);
          expect(getLines(bufferService, 6), <String>[
            '#####',
            'abcde',
            'fghij',
            'klmno',
            'pqrst',
            '     ',
          ]);

          await inputHandler.parseP('uvwxy');
          // place cursor within scroll margins
          bufferService.buffers.active.x = 5;
          bufferService.buffers.active.y = 3;
          await inputHandler.parseP(ttyBS * 100);
          expect(getLines(bufferService, 6), <String>[
            '#####',
            'abcde',
            '     ',
            '     ',
            '     ',
            'uvwxy',
          ]);
          expect(bufferService.buffers.active.x, 0);
          expect(
            bufferService.buffers.active.y,
            bufferService.buffers.active.scrollTop,
          ); // stops at 0, scrollTop

          await inputHandler.parseP('fghijklmnopqrst');
          // place cursor above scroll top
          bufferService.buffers.active.x = 5;
          bufferService.buffers.active.y = 0;
          await inputHandler.parseP(ttyBS * 100);
          expect(getLines(bufferService, 6), <String>[
            '#####',
            '     ',
            'fghij',
            'klmno',
            'pqrst',
            'uvwxy',
          ]);
        });
      });
    });

    test('save and restore cursor', () {
      bufferService.buffer.x = 1;
      bufferService.buffer.y = 2;
      bufferService.buffer.ybase = 0;
      inputHandler.curAttrData.fg = 3;
      // Save cursor position
      inputHandler.saveCursor();
      expect(bufferService.buffer.x, 1);
      expect(bufferService.buffer.y, 2);
      expect(inputHandler.curAttrData.fg, 3);
      // Change cursor position
      bufferService.buffer.x = 10;
      bufferService.buffer.y = 20;
      inputHandler.curAttrData.fg = 30;
      // Restore cursor position
      inputHandler.restoreCursor();
      expect(bufferService.buffer.x, 1);
      expect(bufferService.buffer.y, 2);
      expect(inputHandler.curAttrData.fg, 3);
    });
    group('DECSC/DECRC - save and restore cursor', () {
      test('should save and restore origin mode', () async {
        expect(coreService.decPrivateModes.origin, false);
        await inputHandler.parseP('\x1b[?6h');
        expect(coreService.decPrivateModes.origin, true);
        await inputHandler.parseP('\x1b7');
        await inputHandler.parseP('\x1b[?6l');
        expect(coreService.decPrivateModes.origin, false);
        await inputHandler.parseP('\x1b8');
        expect(coreService.decPrivateModes.origin, true);
      });
      test('should save and restore wraparound mode', () async {
        expect(coreService.decPrivateModes.wraparound, true);
        await inputHandler.parseP('\x1b[?7l');
        expect(coreService.decPrivateModes.wraparound, false);
        await inputHandler.parseP('\x1b7');
        await inputHandler.parseP('\x1b[?7h');
        expect(coreService.decPrivateModes.wraparound, true);
        await inputHandler.parseP('\x1b8');
        expect(coreService.decPrivateModes.wraparound, false);
      });
    });
    group('setCursorStyle', () {
      test('should call Terminal.setOption with correct params', () {
        inputHandler.setCursorStyle(Params.fromArray(<Object>[0]));
        expect(coreService.decPrivateModes.cursorStyle, isNull);
        expect(coreService.decPrivateModes.cursorBlink, isNull);

        optionsService.options = cloneDefaultOptions();
        inputHandler.setCursorStyle(Params.fromArray(<Object>[1]));
        expect(coreService.decPrivateModes.cursorStyle, 'block');
        expect(coreService.decPrivateModes.cursorBlink, true);

        optionsService.options = cloneDefaultOptions();
        inputHandler.setCursorStyle(Params.fromArray(<Object>[2]));
        expect(coreService.decPrivateModes.cursorStyle, 'block');
        expect(coreService.decPrivateModes.cursorBlink, false);

        optionsService.options = cloneDefaultOptions();
        inputHandler.setCursorStyle(Params.fromArray(<Object>[3]));
        expect(coreService.decPrivateModes.cursorStyle, 'underline');
        expect(coreService.decPrivateModes.cursorBlink, true);

        optionsService.options = cloneDefaultOptions();
        inputHandler.setCursorStyle(Params.fromArray(<Object>[4]));
        expect(coreService.decPrivateModes.cursorStyle, 'underline');
        expect(coreService.decPrivateModes.cursorBlink, false);

        optionsService.options = cloneDefaultOptions();
        inputHandler.setCursorStyle(Params.fromArray(<Object>[5]));
        expect(coreService.decPrivateModes.cursorStyle, 'bar');
        expect(coreService.decPrivateModes.cursorBlink, true);

        optionsService.options = cloneDefaultOptions();
        inputHandler.setCursorStyle(Params.fromArray(<Object>[6]));
        expect(coreService.decPrivateModes.cursorStyle, 'bar');
        expect(coreService.decPrivateModes.cursorBlink, false);
      });
    });
    group('setMode', () {
      test('should toggle bracketedPasteMode', () {
        final coreService = MockCoreService();
        final inputHandler = TestInputHandler(
          MockBufferService(80, 30),
          MockCharsetService(),
          coreService,
          MockLogService(),
          MockOptionsService(),
          MockOscLinkService(),
          MockMouseStateService(),
          MockUnicodeService(),
        );
        // Set bracketed paste mode
        inputHandler.setModePrivate(Params.fromArray(<Object>[2004]));
        expect(coreService.decPrivateModes.bracketedPasteMode, true);
        // Reset bracketed paste mode
        inputHandler.resetModePrivate(Params.fromArray(<Object>[2004]));
        expect(coreService.decPrivateModes.bracketedPasteMode, false);
      });
      test('should toggle colorSchemeUpdates (DECSET 2031)', () {
        final coreService = MockCoreService();
        final optionsService = MockOptionsService();
        final inputHandler = TestInputHandler(
          MockBufferService(80, 30),
          MockCharsetService(),
          coreService,
          MockLogService(),
          optionsService,
          MockOscLinkService(),
          MockMouseStateService(),
          MockUnicodeService(),
        );
        // Set color scheme updates mode (default colorSchemeQuery=true)
        inputHandler.setModePrivate(Params.fromArray(<Object>[2031]));
        expect(coreService.decPrivateModes.colorSchemeUpdates, true);
        // Reset color scheme updates mode
        inputHandler.resetModePrivate(Params.fromArray(<Object>[2031]));
        expect(coreService.decPrivateModes.colorSchemeUpdates, false);
      });
      test('should not toggle colorSchemeUpdates when colorSchemeQuery is disabled', () {
        final coreService = MockCoreService();
        final optionsService = MockOptionsService();
        optionsService.rawOptions.vtExtensions = IVtExtensions(
          colorSchemeQuery: false,
        );
        final inputHandler = TestInputHandler(
          MockBufferService(80, 30),
          MockCharsetService(),
          coreService,
          MockLogService(),
          optionsService,
          MockOscLinkService(),
          MockMouseStateService(),
          MockUnicodeService(),
        );
        // Attempt to set color scheme updates mode
        inputHandler.setModePrivate(Params.fromArray(<Object>[2031]));
        expect(coreService.decPrivateModes.colorSchemeUpdates, false);
      });
    });
    group('regression tests', () {
      List<String> termContent(IBufferService bufferService, bool trim) {
        final result = <String>[];
        for (var i = 0; i < bufferService.rows; ++i) {
          result.add(
            bufferService.buffer.lines.get(i)!.translateToString(trim),
          );
        }
        return result;
      }

      test('insertChars', () async {
        final bufferService = MockBufferService(80, 30);
        final inputHandler = TestInputHandler(
          bufferService,
          MockCharsetService(),
          MockCoreService(),
          MockLogService(),
          MockOptionsService(),
          MockOscLinkService(),
          MockMouseStateService(),
          MockUnicodeService(),
        );

        // insert some data in first and second line
        await inputHandler.parseP('a' * (bufferService.cols - 10));
        await inputHandler.parseP('1234567890');
        await inputHandler.parseP('a' * (bufferService.cols - 10));
        await inputHandler.parseP('1234567890');
        final IBufferLine line1 = bufferService.buffer.lines.get(0)!;
        expect(
          line1.translateToString(false),
          '${'a' * (bufferService.cols - 10)}1234567890',
        );

        // insert one char from params = [0]
        bufferService.buffer.y = 0;
        bufferService.buffer.x = 70;
        inputHandler.insertChars(Params.fromArray(<Object>[0]));
        expect(
          line1.translateToString(false),
          '${'a' * (bufferService.cols - 10)} 123456789',
        );

        // insert one char from params = [1]
        bufferService.buffer.y = 0;
        bufferService.buffer.x = 70;
        inputHandler.insertChars(Params.fromArray(<Object>[1]));
        expect(
          line1.translateToString(false),
          '${'a' * (bufferService.cols - 10)}  12345678',
        );

        // insert two chars from params = [2]
        bufferService.buffer.y = 0;
        bufferService.buffer.x = 70;
        inputHandler.insertChars(Params.fromArray(<Object>[2]));
        expect(
          line1.translateToString(false),
          '${'a' * (bufferService.cols - 10)}    123456',
        );

        // insert 10 chars from params = [10]
        bufferService.buffer.y = 0;
        bufferService.buffer.x = 70;
        inputHandler.insertChars(Params.fromArray(<Object>[10]));
        expect(
          line1.translateToString(false),
          '${'a' * (bufferService.cols - 10)}          ',
        );
        expect(line1.translateToString(true), 'a' * (bufferService.cols - 10));
      });
      test('deleteChars', () async {
        final bufferService = MockBufferService(80, 30);
        final inputHandler = TestInputHandler(
          bufferService,
          MockCharsetService(),
          MockCoreService(),
          MockLogService(),
          MockOptionsService(),
          MockOscLinkService(),
          MockMouseStateService(),
          MockUnicodeService(),
        );

        // insert some data in first and second line
        await inputHandler.parseP('a' * (bufferService.cols - 10));
        await inputHandler.parseP('1234567890');
        await inputHandler.parseP('a' * (bufferService.cols - 10));
        await inputHandler.parseP('1234567890');
        final IBufferLine line1 = bufferService.buffer.lines.get(0)!;
        expect(
          line1.translateToString(false),
          '${'a' * (bufferService.cols - 10)}1234567890',
        );

        // delete one char from params = [0]
        bufferService.buffer.y = 0;
        bufferService.buffer.x = 70;
        inputHandler.deleteChars(Params.fromArray(<Object>[0]));
        expect(
          line1.translateToString(false),
          '${'a' * (bufferService.cols - 10)}234567890 ',
        );
        expect(
          line1.translateToString(true),
          '${'a' * (bufferService.cols - 10)}234567890',
        );

        // insert one char from params = [1]
        bufferService.buffer.y = 0;
        bufferService.buffer.x = 70;
        inputHandler.deleteChars(Params.fromArray(<Object>[1]));
        expect(
          line1.translateToString(false),
          '${'a' * (bufferService.cols - 10)}34567890  ',
        );
        expect(
          line1.translateToString(true),
          '${'a' * (bufferService.cols - 10)}34567890',
        );

        // insert two chars from params = [2]
        bufferService.buffer.y = 0;
        bufferService.buffer.x = 70;
        inputHandler.deleteChars(Params.fromArray(<Object>[2]));
        expect(
          line1.translateToString(false),
          '${'a' * (bufferService.cols - 10)}567890    ',
        );
        expect(
          line1.translateToString(true),
          '${'a' * (bufferService.cols - 10)}567890',
        );

        // insert 10 chars from params = [10]
        bufferService.buffer.y = 0;
        bufferService.buffer.x = 70;
        inputHandler.deleteChars(Params.fromArray(<Object>[10]));
        expect(
          line1.translateToString(false),
          '${'a' * (bufferService.cols - 10)}          ',
        );
        expect(line1.translateToString(true), 'a' * (bufferService.cols - 10));
      });
      test('eraseInLine', () async {
        final bufferService = MockBufferService(80, 30);
        final inputHandler = TestInputHandler(
          bufferService,
          MockCharsetService(),
          MockCoreService(),
          MockLogService(),
          MockOptionsService(),
          MockOscLinkService(),
          MockMouseStateService(),
          MockUnicodeService(),
        );

        // fill 6 lines to test 3 different states
        await inputHandler.parseP('a' * bufferService.cols);
        await inputHandler.parseP('a' * bufferService.cols);
        await inputHandler.parseP('a' * bufferService.cols);

        // params[0] - right erase
        bufferService.buffer.y = 0;
        bufferService.buffer.x = 70;
        inputHandler.eraseInLine(Params.fromArray(<Object>[0]));
        expect(
          bufferService.buffer.lines.get(0)!.translateToString(false),
          '${'a' * 70}          ',
        );

        // params[1] - left erase
        bufferService.buffer.y = 1;
        bufferService.buffer.x = 70;
        inputHandler.eraseInLine(Params.fromArray(<Object>[1]));
        expect(
          bufferService.buffer.lines.get(1)!.translateToString(false),
          '${' ' * 70} aaaaaaaaa',
        );

        // params[1] - left erase
        bufferService.buffer.y = 2;
        bufferService.buffer.x = 70;
        inputHandler.eraseInLine(Params.fromArray(<Object>[2]));
        expect(
          bufferService.buffer.lines.get(2)!.translateToString(false),
          ' ' * bufferService.cols,
        );
      });
      test('eraseInLine reflow', () async {
        final bufferService = MockBufferService(80, 30);
        final inputHandler = TestInputHandler(
          bufferService,
          MockCharsetService(),
          MockCoreService(),
          MockLogService(),
          MockOptionsService(),
          MockOscLinkService(),
          MockMouseStateService(),
          MockUnicodeService(),
        );

        Future<void> resetToBaseState() async {
          // reset and add a wrapped line
          bufferService.buffer.y = 0;
          bufferService.buffer.x = 0;
          await inputHandler.parseP('a' * bufferService.cols); // line 0
          await inputHandler.parseP(
            'a' * (bufferService.cols + 9),
          ); // line 1 and 2
          for (var i = 3; i < bufferService.rows; ++i) {
            await inputHandler.parseP('a' * bufferService.cols);
          }

          // confirm precondition that line 2 is wrapped
          expect(bufferService.buffer.lines.get(2)!.isWrapped, true);
        }

        // params[0] - erase from the cursor through the end of the row.
        await resetToBaseState();
        bufferService.buffer.y = 2;
        bufferService.buffer.x = 40;
        inputHandler.eraseInLine(Params.fromArray(<Object>[0]));
        expect(bufferService.buffer.lines.get(2)!.isWrapped, true);
        bufferService.buffer.y = 2;
        bufferService.buffer.x = 0;
        inputHandler.eraseInLine(Params.fromArray(<Object>[0]));
        expect(bufferService.buffer.lines.get(2)!.isWrapped, false);

        // params[1] - erase from the beginning of the line through the cursor
        await resetToBaseState();
        bufferService.buffer.y = 2;
        bufferService.buffer.x = 40;
        inputHandler.eraseInLine(Params.fromArray(<Object>[1]));
        expect(bufferService.buffer.lines.get(2)!.isWrapped, true);

        // params[2] - erase complete line
        await resetToBaseState();
        bufferService.buffer.y = 2;
        bufferService.buffer.x = 40;
        inputHandler.eraseInLine(Params.fromArray(<Object>[2]));
        expect(bufferService.buffer.lines.get(2)!.isWrapped, false);
      });
      test('ED2 with scrollOnEraseInDisplay turned on', () async {
        final inputHandler = TestInputHandler(
          bufferService,
          MockCharsetService(),
          MockCoreService(),
          MockLogService(),
          MockOptionsService(ITerminalOptions(scrollOnEraseInDisplay: true)),
          MockOscLinkService(),
          MockMouseStateService(),
          MockUnicodeService(),
        );
        final aLine = 'a' * bufferService.cols;
        // add 2 full lines of text.
        await inputHandler.parseP(aLine);
        await inputHandler.parseP(aLine);

        inputHandler.eraseInDisplay(Params.fromArray(<Object>[2]));
        // those 2 lines should have been pushed to scrollback.
        expect(bufferService.rows + 2, bufferService.buffer.lines.length);
        expect(bufferService.buffer.ybase, 2);
        expect(bufferService.buffer.lines.get(0)?.translateToString(), aLine);
        expect(bufferService.buffer.lines.get(1)?.translateToString(), aLine);

        // Move to last line and add more text.
        bufferService.buffer.y = bufferService.rows - 1;
        bufferService.buffer.x = 0;
        await inputHandler.parseP(aLine);
        inputHandler.eraseInDisplay(Params.fromArray(<Object>[2]));
        // Screen should have been scrolled by a full screen size.
        expect(bufferService.rows * 2 + 2, bufferService.buffer.lines.length);
      });
      test('eraseInDisplay', () async {
        final bufferService = MockBufferService(80, 7);
        final inputHandler = TestInputHandler(
          bufferService,
          MockCharsetService(),
          MockCoreService(),
          MockLogService(),
          MockOptionsService(),
          MockOscLinkService(),
          MockMouseStateService(),
          MockUnicodeService(),
        );

        // fill display with a's
        for (var i = 0; i < bufferService.rows; ++i) {
          await inputHandler.parseP('a' * bufferService.cols);
        }

        // params [0] - right and below erase
        bufferService.buffer.y = 5;
        bufferService.buffer.x = 40;
        inputHandler.eraseInDisplay(Params.fromArray(<Object>[0]));
        expect(termContent(bufferService, false), <String>[
          'a' * bufferService.cols,
          'a' * bufferService.cols,
          'a' * bufferService.cols,
          'a' * bufferService.cols,
          'a' * bufferService.cols,
          ('a' * 40) + (' ' * (bufferService.cols - 40)),
          ' ' * bufferService.cols,
        ]);
        expect(termContent(bufferService, true), <String>[
          'a' * bufferService.cols,
          'a' * bufferService.cols,
          'a' * bufferService.cols,
          'a' * bufferService.cols,
          'a' * bufferService.cols,
          'a' * 40,
          '',
        ]);

        // reset
        bufferService.buffer.y = 0;
        bufferService.buffer.x = 0;
        for (var i = 0; i < bufferService.rows; ++i) {
          await inputHandler.parseP('a' * bufferService.cols);
        }

        // params [1] - left and above
        bufferService.buffer.y = 5;
        bufferService.buffer.x = 40;
        inputHandler.eraseInDisplay(Params.fromArray(<Object>[1]));
        expect(termContent(bufferService, false), <String>[
          ' ' * bufferService.cols,
          ' ' * bufferService.cols,
          ' ' * bufferService.cols,
          ' ' * bufferService.cols,
          ' ' * bufferService.cols,
          (' ' * 41) + ('a' * (bufferService.cols - 41)),
          'a' * bufferService.cols,
        ]);
        expect(termContent(bufferService, true), <String>[
          '',
          '',
          '',
          '',
          '',
          (' ' * 41) + ('a' * (bufferService.cols - 41)),
          'a' * bufferService.cols,
        ]);

        // reset
        bufferService.buffer.y = 0;
        bufferService.buffer.x = 0;
        for (var i = 0; i < bufferService.rows; ++i) {
          await inputHandler.parseP('a' * bufferService.cols);
        }

        // params [2] - whole screen
        bufferService.buffer.y = 5;
        bufferService.buffer.x = 40;
        inputHandler.eraseInDisplay(Params.fromArray(<Object>[2]));
        expect(termContent(bufferService, false), <String>[
          ' ' * bufferService.cols,
          ' ' * bufferService.cols,
          ' ' * bufferService.cols,
          ' ' * bufferService.cols,
          ' ' * bufferService.cols,
          ' ' * bufferService.cols,
          ' ' * bufferService.cols,
        ]);
        expect(termContent(bufferService, true), <String>[
          '',
          '',
          '',
          '',
          '',
          '',
          '',
        ]);

        // reset and add a wrapped line
        bufferService.buffer.y = 0;
        bufferService.buffer.x = 0;
        await inputHandler.parseP('a' * bufferService.cols); // line 0
        await inputHandler.parseP(
          'a' * (bufferService.cols + 9),
        ); // line 1 and 2
        for (var i = 3; i < bufferService.rows; ++i) {
          await inputHandler.parseP('a' * bufferService.cols);
        }

        // params[1] left and above with wrap
        // confirm precondition that line 2 is wrapped
        expect(bufferService.buffer.lines.get(2)!.isWrapped, true);
        bufferService.buffer.y = 2;
        bufferService.buffer.x = 40;
        inputHandler.eraseInDisplay(Params.fromArray(<Object>[1]));
        expect(bufferService.buffer.lines.get(2)!.isWrapped, false);

        // reset and add a wrapped line
        bufferService.buffer.y = 0;
        bufferService.buffer.x = 0;
        await inputHandler.parseP('a' * bufferService.cols); // line 0
        await inputHandler.parseP(
          'a' * (bufferService.cols + 9),
        ); // line 1 and 2
        for (var i = 3; i < bufferService.rows; ++i) {
          await inputHandler.parseP('a' * bufferService.cols);
        }

        // params[1] left and above with wrap
        // confirm precondition that line 2 is wrapped
        expect(bufferService.buffer.lines.get(2)!.isWrapped, true);
        bufferService.buffer.y = 1;
        bufferService.buffer.x = 90; // Cursor is beyond last column
        inputHandler.eraseInDisplay(Params.fromArray(<Object>[1]));
        expect(bufferService.buffer.lines.get(2)!.isWrapped, false);
      });
    });
    group('print', () {
      test('should not cause an infinite loop (regression test)', () {
        final container = Uint32List(10);
        container[0] = 0x200B;
        final lineCountBefore = bufferService.buffer.lines.length;
        inputHandler.print(container, 0, 1);
        expect(bufferService.buffer.y, 0);
        expect(bufferService.buffer.lines.length, lineCountBefore);
      });
      test('should join combining characters in a single print', () async {
        await inputHandler.parseP('e\u0301');
        expect(
          bufferService.buffer.translateBufferLineToString(0, true),
          'e\u0301',
        );
        expect(bufferService.buffer.x, 1);
      });
      test(
        'should join combining characters split across parse calls',
        () async {
          await inputHandler.parseP('e');
          await inputHandler.parseP('\u0301');
          expect(
            bufferService.buffer.translateBufferLineToString(0, true),
            'e\u0301',
          );
          expect(bufferService.buffer.x, 1);
        },
      );
      test('should repeat preceding grapheme cluster via REP', () async {
        await inputHandler.parseP('e\u0301\x1b[2b');
        expect(
          bufferService.buffer.translateBufferLineToString(0, true),
          'e\u0301e\u0301e\u0301',
        );
        expect(bufferService.buffer.x, 3);
      });
      test('should not repeat when REP has no preceding join state', () async {
        await inputHandler.parseP('\x1b[2b');
        expect(bufferService.buffer.translateBufferLineToString(0, true), '');
        expect(bufferService.buffer.x, 0);
      });
      test('should not repeat after an intervening escape sequence', () async {
        await inputHandler.parseP('a\x1b[0m\x1b[2b');
        expect(bufferService.buffer.translateBufferLineToString(0, true), 'a');
        expect(bufferService.buffer.x, 1);
      });
      test('should clear cells to the right on early wrap-around', () async {
        bufferService.resize(5, 5);
        optionsService.options.scrollback = 1;
        await inputHandler.parseP('12345');
        bufferService.buffer.x = 0;
        await inputHandler.parseP('￥￥￥');
        expect(getLines(bufferService, 2), <String>['￥￥', '￥']);
      });
      test('should strip soft hyphens (U+00AD)', () async {
        await inputHandler.parseP('Soft\xadhy\xadphen');
        expect(
          bufferService.buffer.translateBufferLineToString(0, true),
          'Softhyphen',
        );
        expect(bufferService.buffer.x, 10);
      });
    });

    group('ISO-2022 character sets', () {
      late CharsetService charsetService;

      setUp(() {
        charsetService = CharsetService();
        inputHandler = TestInputHandler(
          bufferService,
          charsetService,
          coreService,
          MockLogService(),
          optionsService,
          oscLinkService,
          MockMouseStateService(),
          MockUnicodeService(),
        );
      });

      test('should map G0 line drawing via ESC ( 0', () async {
        await inputHandler.parseP('\x1b(0q\x1b(Bq');
        expect(
          bufferService.buffer.translateBufferLineToString(0, true),
          '\u2500q',
        );
      });

      test('should map G1 line drawing after ESC ) 0 and SO', () async {
        await inputHandler.parseP('\x1b)0\x0eq\x0f\x1b(Bq');
        expect(
          bufferService.buffer.translateBufferLineToString(0, true),
          '\u2500q',
        );
      });

      test('should restore charset and glevel on ESC 7 / ESC 8', () async {
        await inputHandler.parseP('\x1b)0\x0e');
        expect(charsetService.glevel, 1);
        expect(charsetService.charset, same(charsets['0']));
        await inputHandler.parseP('\x1b7');
        await inputHandler.parseP('\x0f\x1b(B');
        expect(charsetService.glevel, 0);
        expect(charsetService.charset, isNull);
        await inputHandler.parseP('\x1b8');
        expect(charsetService.glevel, 1);
        expect(charsetService.charset, same(charsets['0']));
        await inputHandler.parseP('q');
        expect(
          bufferService.buffer.translateBufferLineToString(0, true),
          '\u2500',
        );
      });
    });

    group('alt screen', () {
      late IBufferService bufferService;
      late TestInputHandler handler;

      setUp(() {
        bufferService = MockBufferService(80, 30);
        handler = TestInputHandler(
          bufferService,
          MockCharsetService(),
          MockCoreService(),
          MockLogService(),
          MockOptionsService(),
          MockOscLinkService(),
          MockMouseStateService(),
          MockUnicodeService(),
        );
      });
      test('should handle DECSET/DECRST 47 (alt screen buffer)', () async {
        await handler.parseP('\x1b[?47h\r\n\x1b[31mJUNK\x1b[?47lTEST');
        expect(bufferService.buffer.translateBufferLineToString(0, true), '');
        expect(
          bufferService.buffer.translateBufferLineToString(1, true),
          '    TEST',
        );
        // Text color of 'TEST' should be red
        expect(
          bufferService.buffer.lines
              .get(1)!
              .loadCell(4, CellData())
              .getFgColor(),
          1,
        );
      });
      test('should handle DECSET/DECRST 1047 (alt screen buffer)', () async {
        await handler.parseP('\x1b[?1047h\r\n\x1b[31mJUNK\x1b[?1047lTEST');
        expect(bufferService.buffer.translateBufferLineToString(0, true), '');
        expect(
          bufferService.buffer.translateBufferLineToString(1, true),
          '    TEST',
        );
        // Text color of 'TEST' should be red
        expect(
          bufferService.buffer.lines
              .get(1)!
              .loadCell(4, CellData())
              .getFgColor(),
          1,
        );
      });
      test('should handle DECSET/DECRST 1048 (alt screen cursor)', () async {
        await handler.parseP('\x1b[?1048h\r\n\x1b[31mJUNK\x1b[?1048lTEST');
        expect(
          bufferService.buffer.translateBufferLineToString(0, true),
          'TEST',
        );
        expect(
          bufferService.buffer.translateBufferLineToString(1, true),
          'JUNK',
        );
        // Text color of 'TEST' should be default
        expect(
          bufferService.buffer.lines.get(0)!.loadCell(0, CellData()).fg,
          defaultAttrData.fg,
        );
        // Text color of 'JUNK' should be red
        expect(
          bufferService.buffer.lines
              .get(1)!
              .loadCell(0, CellData())
              .getFgColor(),
          1,
        );
      });
      test(
        'should handle DECSET/DECRST 1049 (alt screen buffer+cursor)',
        () async {
          await handler.parseP('\x1b[?1049h\r\n\x1b[31mJUNK\x1b[?1049lTEST');
          expect(
            bufferService.buffer.translateBufferLineToString(0, true),
            'TEST',
          );
          expect(bufferService.buffer.translateBufferLineToString(1, true), '');
          // Text color of 'TEST' should be default
          expect(
            bufferService.buffer.lines.get(0)!.loadCell(0, CellData()).fg,
            defaultAttrData.fg,
          );
        },
      );
      test('should handle DECSET/DECRST 1049 - maintains saved cursor for alt buffer', () async {
        await handler.parseP('\x1b[?1049h\r\n\x1b[31m\x1b[s\x1b[?1049lTEST');
        expect(
          bufferService.buffer.translateBufferLineToString(0, true),
          'TEST',
        );
        // Text color of 'TEST' should be default
        expect(
          bufferService.buffer.lines.get(0)!.loadCell(0, CellData()).fg,
          defaultAttrData.fg,
        );
        await handler.parseP('\x1b[?1049h\x1b[uTEST');
        expect(
          bufferService.buffer.translateBufferLineToString(1, true),
          'TEST',
        );
        // Text color of 'TEST' should be red
        expect(
          bufferService.buffer.lines
              .get(1)!
              .loadCell(0, CellData())
              .getFgColor(),
          1,
        );
      });
      test('should handle DECSET/DECRST 1049 - clears alt buffer with erase attributes', () async {
        await handler.parseP('\x1b[42m\x1b[?1049h');
        // Buffer should be filled with green background
        expect(
          bufferService.buffer.lines
              .get(20)!
              .loadCell(10, CellData())
              .getBgColor(),
          2,
        );
      });
    });

    group('text attributes', () {
      test('bold', () async {
        await inputHandler.parseP('\x1b[1m');
        expect(inputHandler.curAttrData.isBold() != 0, true);
        await inputHandler.parseP('\x1b[22m');
        expect(inputHandler.curAttrData.isBold() != 0, false);
      });
      test('dim', () async {
        await inputHandler.parseP('\x1b[2m');
        expect(inputHandler.curAttrData.isDim() != 0, true);
        await inputHandler.parseP('\x1b[22m');
        expect(inputHandler.curAttrData.isDim() != 0, false);
      });
      test('SGR 221 resets bold only (kitty)', () async {
        await inputHandler.parseP('\x1b[1;2m');
        expect(inputHandler.curAttrData.isBold() != 0, true);
        expect(inputHandler.curAttrData.isDim() != 0, true);
        await inputHandler.parseP('\x1b[221m');
        expect(inputHandler.curAttrData.isBold() != 0, false);
        expect(inputHandler.curAttrData.isDim() != 0, true);
      });
      test('SGR 222 resets faint only (kitty)', () async {
        await inputHandler.parseP('\x1b[1;2m');
        expect(inputHandler.curAttrData.isBold() != 0, true);
        expect(inputHandler.curAttrData.isDim() != 0, true);
        await inputHandler.parseP('\x1b[222m');
        expect(inputHandler.curAttrData.isBold() != 0, true);
        expect(inputHandler.curAttrData.isDim() != 0, false);
      });
      test('italic', () async {
        await inputHandler.parseP('\x1b[3m');
        expect(inputHandler.curAttrData.isItalic() != 0, true);
        await inputHandler.parseP('\x1b[23m');
        expect(inputHandler.curAttrData.isItalic() != 0, false);
      });
      test('underline', () async {
        await inputHandler.parseP('\x1b[4m');
        expect(inputHandler.curAttrData.isUnderline() != 0, true);
        await inputHandler.parseP('\x1b[24m');
        expect(inputHandler.curAttrData.isUnderline() != 0, false);
      });
      test('blink', () async {
        await inputHandler.parseP('\x1b[5m');
        expect(inputHandler.curAttrData.isBlink() != 0, true);
        await inputHandler.parseP('\x1b[25m');
        expect(inputHandler.curAttrData.isBlink() != 0, false);
      });
      test('inverse', () async {
        await inputHandler.parseP('\x1b[7m');
        expect(inputHandler.curAttrData.isInverse() != 0, true);
        await inputHandler.parseP('\x1b[27m');
        expect(inputHandler.curAttrData.isInverse() != 0, false);
      });
      test('invisible', () async {
        await inputHandler.parseP('\x1b[8m');
        expect(inputHandler.curAttrData.isInvisible() != 0, true);
        await inputHandler.parseP('\x1b[28m');
        expect(inputHandler.curAttrData.isInvisible() != 0, false);
      });
      test('strikethrough', () async {
        await inputHandler.parseP('\x1b[9m');
        expect(inputHandler.curAttrData.isStrikethrough() != 0, true);
        await inputHandler.parseP('\x1b[29m');
        expect(inputHandler.curAttrData.isStrikethrough() != 0, false);
      });
      test('colormode palette 16', () async {
        expect(inputHandler.curAttrData.getFgColorMode(), 0); // DEFAULT
        expect(inputHandler.curAttrData.getBgColorMode(), 0); // DEFAULT
        // lower 8 colors
        for (var i = 0; i < 8; ++i) {
          await inputHandler.parseP('\x1b[${i + 30};${i + 40}m');
          expect(inputHandler.curAttrData.getFgColorMode(), Attributes.cmP16);
          expect(inputHandler.curAttrData.getFgColor(), i);
          expect(inputHandler.curAttrData.getBgColorMode(), Attributes.cmP16);
          expect(inputHandler.curAttrData.getBgColor(), i);
        }
        // reset to DEFAULT
        await inputHandler.parseP('\x1b[39;49m');
        expect(inputHandler.curAttrData.getFgColorMode(), 0);
        expect(inputHandler.curAttrData.getBgColorMode(), 0);
      });
      test('colormode palette 256', () async {
        expect(inputHandler.curAttrData.getFgColorMode(), 0); // DEFAULT
        expect(inputHandler.curAttrData.getBgColorMode(), 0); // DEFAULT
        // lower 8 colors
        for (var i = 0; i < 256; ++i) {
          await inputHandler.parseP('\x1b[38;5;$i;48;5;${i}m');
          expect(inputHandler.curAttrData.getFgColorMode(), Attributes.cmP256);
          expect(inputHandler.curAttrData.getFgColor(), i);
          expect(inputHandler.curAttrData.getBgColorMode(), Attributes.cmP256);
          expect(inputHandler.curAttrData.getBgColor(), i);
        }
        // reset to DEFAULT
        await inputHandler.parseP('\x1b[39;49m');
        expect(inputHandler.curAttrData.getFgColorMode(), 0);
        expect(inputHandler.curAttrData.getFgColor(), -1);
        expect(inputHandler.curAttrData.getBgColorMode(), 0);
        expect(inputHandler.curAttrData.getBgColor(), -1);
      });
      test('colormode RGB', () async {
        expect(inputHandler.curAttrData.getFgColorMode(), 0); // DEFAULT
        expect(inputHandler.curAttrData.getBgColorMode(), 0); // DEFAULT
        await inputHandler.parseP('\x1b[38;2;1;2;3;48;2;4;5;6m');
        expect(inputHandler.curAttrData.getFgColorMode(), Attributes.cmRgb);
        expect(inputHandler.curAttrData.getFgColor(), 1 << 16 | 2 << 8 | 3);
        expect(
          AttributeData.toColorRGB(inputHandler.curAttrData.getFgColor()),
          <int>[1, 2, 3],
        );
        expect(inputHandler.curAttrData.getBgColorMode(), Attributes.cmRgb);
        expect(
          AttributeData.toColorRGB(inputHandler.curAttrData.getBgColor()),
          <int>[4, 5, 6],
        );
        // reset to DEFAULT
        await inputHandler.parseP('\x1b[39;49m');
        expect(inputHandler.curAttrData.getFgColorMode(), 0);
        expect(inputHandler.curAttrData.getFgColor(), -1);
        expect(inputHandler.curAttrData.getBgColorMode(), 0);
        expect(inputHandler.curAttrData.getBgColor(), -1);
      });
      test('colormode transition RGB to 256', () async {
        // enter RGB for FG and BG
        await inputHandler.parseP('\x1b[38;2;1;2;3;48;2;4;5;6m');
        // enter 256 for FG and BG
        await inputHandler.parseP('\x1b[38;5;255;48;5;255m');
        expect(inputHandler.curAttrData.getFgColorMode(), Attributes.cmP256);
        expect(inputHandler.curAttrData.getFgColor(), 255);
        expect(inputHandler.curAttrData.getBgColorMode(), Attributes.cmP256);
        expect(inputHandler.curAttrData.getBgColor(), 255);
      });
      test('colormode transition RGB to 16', () async {
        // enter RGB for FG and BG
        await inputHandler.parseP('\x1b[38;2;1;2;3;48;2;4;5;6m');
        // enter 16 for FG and BG
        await inputHandler.parseP('\x1b[37;47m');
        expect(inputHandler.curAttrData.getFgColorMode(), Attributes.cmP16);
        expect(inputHandler.curAttrData.getFgColor(), 7);
        expect(inputHandler.curAttrData.getBgColorMode(), Attributes.cmP16);
        expect(inputHandler.curAttrData.getBgColor(), 7);
      });
      test('colormode transition 16 to 256', () async {
        // enter 16 for FG and BG
        await inputHandler.parseP('\x1b[37;47m');
        // enter 256 for FG and BG
        await inputHandler.parseP('\x1b[38;5;255;48;5;255m');
        expect(inputHandler.curAttrData.getFgColorMode(), Attributes.cmP256);
        expect(inputHandler.curAttrData.getFgColor(), 255);
        expect(inputHandler.curAttrData.getBgColorMode(), Attributes.cmP256);
        expect(inputHandler.curAttrData.getBgColor(), 255);
      });
      test('colormode transition 256 to 16', () async {
        // enter 256 for FG and BG
        await inputHandler.parseP('\x1b[38;5;255;48;5;255m');
        // enter 16 for FG and BG
        await inputHandler.parseP('\x1b[37;47m');
        expect(inputHandler.curAttrData.getFgColorMode(), Attributes.cmP16);
        expect(inputHandler.curAttrData.getFgColor(), 7);
        expect(inputHandler.curAttrData.getBgColorMode(), Attributes.cmP16);
        expect(inputHandler.curAttrData.getBgColor(), 7);
      });
      test('should zero missing RGB values', () async {
        await inputHandler.parseP('\x1b[38;2;1;2;3m');
        await inputHandler.parseP('\x1b[38;2;5m');
        expect(
          AttributeData.toColorRGB(inputHandler.curAttrData.getFgColor()),
          <int>[5, 0, 0],
        );
      });
    });
    group('colon notation', () {
      late TestInputHandler inputHandler2;
      setUp(() {
        inputHandler2 = TestInputHandler(
          bufferService,
          MockCharsetService(),
          coreService,
          MockLogService(),
          optionsService,
          MockOscLinkService(),
          MockMouseStateService(),
          MockUnicodeService(),
        );
      });
      group('should equal to semicolon', () {
        test('CSI 38:2::50:100:150 m', () async {
          inputHandler.curAttrData.fg = 0xFFFFFFFF;
          inputHandler2.curAttrData.fg = 0xFFFFFFFF;
          await inputHandler2.parseP('\x1b[38;2;50;100;150m');
          await inputHandler.parseP('\x1b[38:2::50:100:150m');
          expect(
            inputHandler2.curAttrData.fg & 0xFFFFFF,
            50 << 16 | 100 << 8 | 150,
          );
          expect(inputHandler.curAttrData.fg, inputHandler2.curAttrData.fg);
        });
        test('CSI 38:2::50:100: m', () async {
          inputHandler.curAttrData.fg = 0xFFFFFFFF;
          inputHandler2.curAttrData.fg = 0xFFFFFFFF;
          await inputHandler2.parseP('\x1b[38;2;50;100;m');
          await inputHandler.parseP('\x1b[38:2::50:100:m');
          expect(
            inputHandler2.curAttrData.fg & 0xFFFFFF,
            50 << 16 | 100 << 8 | 0,
          );
          expect(inputHandler.curAttrData.fg, inputHandler2.curAttrData.fg);
        });
        test('CSI 38:2::50:: m', () async {
          inputHandler.curAttrData.fg = 0xFFFFFFFF;
          inputHandler2.curAttrData.fg = 0xFFFFFFFF;
          await inputHandler2.parseP('\x1b[38;2;50;;m');
          await inputHandler.parseP('\x1b[38:2::50::m');
          expect(
            inputHandler2.curAttrData.fg & 0xFFFFFF,
            50 << 16 | 0 << 8 | 0,
          );
          expect(inputHandler.curAttrData.fg, inputHandler2.curAttrData.fg);
        });
        test('CSI 38:2:::: m', () async {
          inputHandler.curAttrData.fg = 0xFFFFFFFF;
          inputHandler2.curAttrData.fg = 0xFFFFFFFF;
          await inputHandler2.parseP('\x1b[38;2;;;m');
          await inputHandler.parseP('\x1b[38:2::::m');
          expect(inputHandler2.curAttrData.fg & 0xFFFFFF, 0 << 16 | 0 << 8 | 0);
          expect(inputHandler.curAttrData.fg, inputHandler2.curAttrData.fg);
        });
        test('CSI 38;2::50:100:150 m', () async {
          inputHandler.curAttrData.fg = 0xFFFFFFFF;
          inputHandler2.curAttrData.fg = 0xFFFFFFFF;
          await inputHandler2.parseP('\x1b[38;2;50;100;150m');
          await inputHandler.parseP('\x1b[38;2::50:100:150m');
          expect(
            inputHandler2.curAttrData.fg & 0xFFFFFF,
            50 << 16 | 100 << 8 | 150,
          );
          expect(inputHandler.curAttrData.fg, inputHandler2.curAttrData.fg);
        });
        test('CSI 38;2;50:100:150 m', () async {
          inputHandler.curAttrData.fg = 0xFFFFFFFF;
          inputHandler2.curAttrData.fg = 0xFFFFFFFF;
          await inputHandler2.parseP('\x1b[38;2;50;100;150m');
          await inputHandler.parseP('\x1b[38;2;50:100:150m');
          expect(
            inputHandler2.curAttrData.fg & 0xFFFFFF,
            50 << 16 | 100 << 8 | 150,
          );
          expect(inputHandler.curAttrData.fg, inputHandler2.curAttrData.fg);
        });
        test('CSI 38;2;50;100:150 m', () async {
          inputHandler.curAttrData.fg = 0xFFFFFFFF;
          inputHandler2.curAttrData.fg = 0xFFFFFFFF;
          await inputHandler2.parseP('\x1b[38;2;50;100;150m');
          await inputHandler.parseP('\x1b[38;2;50;100:150m');
          expect(
            inputHandler2.curAttrData.fg & 0xFFFFFF,
            50 << 16 | 100 << 8 | 150,
          );
          expect(inputHandler.curAttrData.fg, inputHandler2.curAttrData.fg);
        });
        test('CSI 38:5:50 m', () async {
          inputHandler.curAttrData.fg = 0xFFFFFFFF;
          inputHandler2.curAttrData.fg = 0xFFFFFFFF;
          await inputHandler2.parseP('\x1b[38;5;50m');
          await inputHandler.parseP('\x1b[38:5:50m');
          expect(inputHandler2.curAttrData.fg & 0xFF, 50);
          expect(inputHandler.curAttrData.fg, inputHandler2.curAttrData.fg);
        });
        test('CSI 38:5: m', () async {
          inputHandler.curAttrData.fg = 0xFFFFFFFF;
          inputHandler2.curAttrData.fg = 0xFFFFFFFF;
          await inputHandler2.parseP('\x1b[38;5;m');
          await inputHandler.parseP('\x1b[38:5:m');
          expect(inputHandler2.curAttrData.fg & 0xFF, 0);
          expect(inputHandler.curAttrData.fg, inputHandler2.curAttrData.fg);
        });
        test('CSI 38;5:50 m', () async {
          inputHandler.curAttrData.fg = 0xFFFFFFFF;
          inputHandler2.curAttrData.fg = 0xFFFFFFFF;
          await inputHandler2.parseP('\x1b[38;5;50m');
          await inputHandler.parseP('\x1b[38;5:50m');
          expect(inputHandler2.curAttrData.fg & 0xFF, 50);
          expect(inputHandler.curAttrData.fg, inputHandler2.curAttrData.fg);
        });
      });
      group('should fill early sequence end with default of 0', () {
        test('CSI 38:2 m', () async {
          inputHandler.curAttrData.fg = 0xFFFFFFFF;
          inputHandler2.curAttrData.fg = 0xFFFFFFFF;
          await inputHandler2.parseP('\x1b[38;2m');
          await inputHandler.parseP('\x1b[38:2m');
          expect(inputHandler2.curAttrData.fg & 0xFFFFFF, 0 << 16 | 0 << 8 | 0);
          expect(inputHandler.curAttrData.fg, inputHandler2.curAttrData.fg);
        });
        test('CSI 38:5 m', () async {
          inputHandler.curAttrData.fg = 0xFFFFFFFF;
          inputHandler2.curAttrData.fg = 0xFFFFFFFF;
          await inputHandler2.parseP('\x1b[38;5m');
          await inputHandler.parseP('\x1b[38:5m');
          expect(inputHandler2.curAttrData.fg & 0xFF, 0);
          expect(inputHandler.curAttrData.fg, inputHandler2.curAttrData.fg);
        });
      });
      group('should not interfere with leading/following SGR attrs', () {
        test('CSI 1 ; 38:2::50:100:150 ; 4 m', () async {
          await inputHandler2.parseP('\x1b[1;38;2;50;100;150;4m');
          await inputHandler.parseP('\x1b[1;38:2::50:100:150;4m');
          expect(inputHandler2.curAttrData.isBold() != 0, true);
          expect(inputHandler2.curAttrData.isUnderline() != 0, true);
          expect(
            inputHandler2.curAttrData.fg & 0xFFFFFF,
            50 << 16 | 100 << 8 | 150,
          );
          expect(inputHandler.curAttrData.fg, inputHandler2.curAttrData.fg);
        });
        test('CSI 1 ; 38:2::50:100: ; 4 m', () async {
          await inputHandler2.parseP('\x1b[1;38;2;50;100;;4m');
          await inputHandler.parseP('\x1b[1;38:2::50:100:;4m');
          expect(inputHandler2.curAttrData.isBold() != 0, true);
          expect(inputHandler2.curAttrData.isUnderline() != 0, true);
          expect(
            inputHandler2.curAttrData.fg & 0xFFFFFF,
            50 << 16 | 100 << 8 | 0,
          );
          expect(inputHandler.curAttrData.fg, inputHandler2.curAttrData.fg);
        });
        test('CSI 1 ; 38:2::50:100 ; 4 m', () async {
          await inputHandler2.parseP('\x1b[1;38;2;50;100;;4m');
          await inputHandler.parseP('\x1b[1;38:2::50:100;4m');
          expect(inputHandler2.curAttrData.isBold() != 0, true);
          expect(inputHandler2.curAttrData.isUnderline() != 0, true);
          expect(
            inputHandler2.curAttrData.fg & 0xFFFFFF,
            50 << 16 | 100 << 8 | 0,
          );
          expect(inputHandler.curAttrData.fg, inputHandler2.curAttrData.fg);
        });
        test('CSI 1 ; 38:2:: ; 4 m', () async {
          await inputHandler2.parseP('\x1b[1;38;2;;;;4m');
          await inputHandler.parseP('\x1b[1;38:2::;4m');
          expect(inputHandler2.curAttrData.isBold() != 0, true);
          expect(inputHandler2.curAttrData.isUnderline() != 0, true);
          expect(inputHandler2.curAttrData.fg & 0xFFFFFF, 0);
          expect(inputHandler.curAttrData.fg, inputHandler2.curAttrData.fg);
        });
        test('CSI 1 ; 38;2:: ; 4 m', () async {
          await inputHandler2.parseP('\x1b[1;38;2;;;;4m');
          await inputHandler.parseP('\x1b[1;38;2::;4m');
          expect(inputHandler2.curAttrData.isBold() != 0, true);
          expect(inputHandler2.curAttrData.isUnderline() != 0, true);
          expect(inputHandler2.curAttrData.fg & 0xFFFFFF, 0);
          expect(inputHandler.curAttrData.fg, inputHandler2.curAttrData.fg);
        });
      });
    });
    group('cursor positioning', () {
      setUp(() {
        bufferService.resize(10, 10);
      });
      test('cursor forward (CUF)', () async {
        await inputHandler.parseP('\x1b[C');
        expect(getCursor(bufferService), <int>[1, 0]);
        await inputHandler.parseP('\x1b[1C');
        expect(getCursor(bufferService), <int>[2, 0]);
        await inputHandler.parseP('\x1b[4C');
        expect(getCursor(bufferService), <int>[6, 0]);
        await inputHandler.parseP('\x1b[100C');
        expect(getCursor(bufferService), <int>[9, 0]);
        // should not change y
        bufferService.buffer.x = 8;
        bufferService.buffer.y = 4;
        await inputHandler.parseP('\x1b[C');
        expect(getCursor(bufferService), <int>[9, 4]);
      });
      test('cursor backward (CUB)', () async {
        await inputHandler.parseP('\x1b[D');
        expect(getCursor(bufferService), <int>[0, 0]);
        await inputHandler.parseP('\x1b[1D');
        expect(getCursor(bufferService), <int>[0, 0]);
        // place cursor at end of first line
        await inputHandler.parseP('\x1b[100C');
        await inputHandler.parseP('\x1b[D');
        expect(getCursor(bufferService), <int>[8, 0]);
        await inputHandler.parseP('\x1b[1D');
        expect(getCursor(bufferService), <int>[7, 0]);
        await inputHandler.parseP('\x1b[4D');
        expect(getCursor(bufferService), <int>[3, 0]);
        await inputHandler.parseP('\x1b[100D');
        expect(getCursor(bufferService), <int>[0, 0]);
        // should not change y
        bufferService.buffer.x = 4;
        bufferService.buffer.y = 4;
        await inputHandler.parseP('\x1b[D');
        expect(getCursor(bufferService), <int>[3, 4]);
      });
      test('cursor down (CUD)', () async {
        await inputHandler.parseP('\x1b[B');
        expect(getCursor(bufferService), <int>[0, 1]);
        await inputHandler.parseP('\x1b[1B');
        expect(getCursor(bufferService), <int>[0, 2]);
        await inputHandler.parseP('\x1b[4B');
        expect(getCursor(bufferService), <int>[0, 6]);
        await inputHandler.parseP('\x1b[100B');
        expect(getCursor(bufferService), <int>[0, 9]);
        // should not change x
        bufferService.buffer.x = 8;
        bufferService.buffer.y = 0;
        await inputHandler.parseP('\x1b[B');
        expect(getCursor(bufferService), <int>[8, 1]);
      });
      test('cursor up (CUU)', () async {
        await inputHandler.parseP('\x1b[A');
        expect(getCursor(bufferService), <int>[0, 0]);
        await inputHandler.parseP('\x1b[1A');
        expect(getCursor(bufferService), <int>[0, 0]);
        // place cursor at beginning of last row
        await inputHandler.parseP('\x1b[100B');
        await inputHandler.parseP('\x1b[A');
        expect(getCursor(bufferService), <int>[0, 8]);
        await inputHandler.parseP('\x1b[1A');
        expect(getCursor(bufferService), <int>[0, 7]);
        await inputHandler.parseP('\x1b[4A');
        expect(getCursor(bufferService), <int>[0, 3]);
        await inputHandler.parseP('\x1b[100A');
        expect(getCursor(bufferService), <int>[0, 0]);
        // should not change x
        bufferService.buffer.x = 8;
        bufferService.buffer.y = 9;
        await inputHandler.parseP('\x1b[A');
        expect(getCursor(bufferService), <int>[8, 8]);
      });
      test('cursor next line (CNL)', () async {
        await inputHandler.parseP('\x1b[E');
        expect(getCursor(bufferService), <int>[0, 1]);
        await inputHandler.parseP('\x1b[1E');
        expect(getCursor(bufferService), <int>[0, 2]);
        await inputHandler.parseP('\x1b[4E');
        expect(getCursor(bufferService), <int>[0, 6]);
        await inputHandler.parseP('\x1b[100E');
        expect(getCursor(bufferService), <int>[0, 9]);
        // should reset x to zero
        bufferService.buffer.x = 8;
        bufferService.buffer.y = 0;
        await inputHandler.parseP('\x1b[E');
        expect(getCursor(bufferService), <int>[0, 1]);
      });
      test('cursor previous line (CPL)', () async {
        await inputHandler.parseP('\x1b[F');
        expect(getCursor(bufferService), <int>[0, 0]);
        await inputHandler.parseP('\x1b[1F');
        expect(getCursor(bufferService), <int>[0, 0]);
        // place cursor at beginning of last row
        await inputHandler.parseP('\x1b[100E');
        await inputHandler.parseP('\x1b[F');
        expect(getCursor(bufferService), <int>[0, 8]);
        await inputHandler.parseP('\x1b[1F');
        expect(getCursor(bufferService), <int>[0, 7]);
        await inputHandler.parseP('\x1b[4F');
        expect(getCursor(bufferService), <int>[0, 3]);
        await inputHandler.parseP('\x1b[100F');
        expect(getCursor(bufferService), <int>[0, 0]);
        // should reset x to zero
        bufferService.buffer.x = 8;
        bufferService.buffer.y = 9;
        await inputHandler.parseP('\x1b[F');
        expect(getCursor(bufferService), <int>[0, 8]);
      });
      test('cursor character absolute (CHA)', () async {
        await inputHandler.parseP('\x1b[G');
        expect(getCursor(bufferService), <int>[0, 0]);
        await inputHandler.parseP('\x1b[1G');
        expect(getCursor(bufferService), <int>[0, 0]);
        await inputHandler.parseP('\x1b[2G');
        expect(getCursor(bufferService), <int>[1, 0]);
        await inputHandler.parseP('\x1b[5G');
        expect(getCursor(bufferService), <int>[4, 0]);
        await inputHandler.parseP('\x1b[100G');
        expect(getCursor(bufferService), <int>[9, 0]);
      });
      test('cursor position (CUP)', () async {
        bufferService.buffer.x = 5;
        bufferService.buffer.y = 5;
        await inputHandler.parseP('\x1b[H');
        expect(getCursor(bufferService), <int>[0, 0]);
        bufferService.buffer.x = 5;
        bufferService.buffer.y = 5;
        await inputHandler.parseP('\x1b[1H');
        expect(getCursor(bufferService), <int>[0, 0]);
        bufferService.buffer.x = 5;
        bufferService.buffer.y = 5;
        await inputHandler.parseP('\x1b[1;1H');
        expect(getCursor(bufferService), <int>[0, 0]);
        bufferService.buffer.x = 5;
        bufferService.buffer.y = 5;
        await inputHandler.parseP('\x1b[8H');
        expect(getCursor(bufferService), <int>[0, 7]);
        bufferService.buffer.x = 5;
        bufferService.buffer.y = 5;
        await inputHandler.parseP('\x1b[;8H');
        expect(getCursor(bufferService), <int>[7, 0]);
        bufferService.buffer.x = 5;
        bufferService.buffer.y = 5;
        await inputHandler.parseP('\x1b[100;100H');
        expect(getCursor(bufferService), <int>[9, 9]);
      });
      test('cursor position (CUP) with DECOM and scroll margins', () async {
        await inputHandler.parseP('\x1b[?6h\x1b[2;3r\x1b[1;1H');
        expect(getCursor(bufferService), <int>[0, 1]);
        await inputHandler.parseP('X');
        expect(getLines(bufferService, 3)[1], 'X');
        await inputHandler.parseP('\x1b[2;1H');
        expect(getCursor(bufferService), <int>[0, 2]);
        await inputHandler.parseP('\x1b[10;10H');
        expect(getCursor(bufferService), <int>[9, 2]);
        await inputHandler.parseP('\x1b[?6l');
        await inputHandler.parseP('\x1b[2;1H');
        expect(getCursor(bufferService), <int>[0, 1]);
      });
      test('horizontal position absolute (HPA)', () async {
        await inputHandler.parseP('\x1b[`');
        expect(getCursor(bufferService), <int>[0, 0]);
        await inputHandler.parseP('\x1b[1`');
        expect(getCursor(bufferService), <int>[0, 0]);
        await inputHandler.parseP('\x1b[2`');
        expect(getCursor(bufferService), <int>[1, 0]);
        await inputHandler.parseP('\x1b[5`');
        expect(getCursor(bufferService), <int>[4, 0]);
        await inputHandler.parseP('\x1b[100`');
        expect(getCursor(bufferService), <int>[9, 0]);
      });
      test('horizontal position relative (HPR)', () async {
        await inputHandler.parseP('\x1b[a');
        expect(getCursor(bufferService), <int>[1, 0]);
        await inputHandler.parseP('\x1b[1a');
        expect(getCursor(bufferService), <int>[2, 0]);
        await inputHandler.parseP('\x1b[4a');
        expect(getCursor(bufferService), <int>[6, 0]);
        await inputHandler.parseP('\x1b[100a');
        expect(getCursor(bufferService), <int>[9, 0]);
        // should not change y
        bufferService.buffer.x = 8;
        bufferService.buffer.y = 4;
        await inputHandler.parseP('\x1b[a');
        expect(getCursor(bufferService), <int>[9, 4]);
      });
      test('vertical position absolute (VPA)', () async {
        await inputHandler.parseP('\x1b[d');
        expect(getCursor(bufferService), <int>[0, 0]);
        await inputHandler.parseP('\x1b[1d');
        expect(getCursor(bufferService), <int>[0, 0]);
        await inputHandler.parseP('\x1b[2d');
        expect(getCursor(bufferService), <int>[0, 1]);
        await inputHandler.parseP('\x1b[5d');
        expect(getCursor(bufferService), <int>[0, 4]);
        await inputHandler.parseP('\x1b[100d');
        expect(getCursor(bufferService), <int>[0, 9]);
        // should not change x
        bufferService.buffer.x = 8;
        bufferService.buffer.y = 4;
        await inputHandler.parseP('\x1b[d');
        expect(getCursor(bufferService), <int>[8, 0]);
      });
      test('vertical position relative (VPR)', () async {
        await inputHandler.parseP('\x1b[e');
        expect(getCursor(bufferService), <int>[0, 1]);
        await inputHandler.parseP('\x1b[1e');
        expect(getCursor(bufferService), <int>[0, 2]);
        await inputHandler.parseP('\x1b[4e');
        expect(getCursor(bufferService), <int>[0, 6]);
        await inputHandler.parseP('\x1b[100e');
        expect(getCursor(bufferService), <int>[0, 9]);
        // should not change x
        bufferService.buffer.x = 8;
        bufferService.buffer.y = 4;
        await inputHandler.parseP('\x1b[e');
        expect(getCursor(bufferService), <int>[8, 5]);
      });
      group('should clamp cursor into addressable range', () {
        test('CUF', () async {
          bufferService.buffer.x = 10000;
          bufferService.buffer.y = 10000;
          await inputHandler.parseP('\x1b[C');
          expect(getCursor(bufferService), <int>[9, 9]);
          bufferService.buffer.x = -10000;
          bufferService.buffer.y = -10000;
          await inputHandler.parseP('\x1b[C');
          expect(getCursor(bufferService), <int>[1, 0]);
        });
        test('CUB', () async {
          bufferService.buffer.x = 10000;
          bufferService.buffer.y = 10000;
          await inputHandler.parseP('\x1b[D');
          expect(getCursor(bufferService), <int>[8, 9]);
          bufferService.buffer.x = -10000;
          bufferService.buffer.y = -10000;
          await inputHandler.parseP('\x1b[D');
          expect(getCursor(bufferService), <int>[0, 0]);
        });
        test('CUD', () async {
          bufferService.buffer.x = 10000;
          bufferService.buffer.y = 10000;
          await inputHandler.parseP('\x1b[B');
          expect(getCursor(bufferService), <int>[9, 9]);
          bufferService.buffer.x = -10000;
          bufferService.buffer.y = -10000;
          await inputHandler.parseP('\x1b[B');
          expect(getCursor(bufferService), <int>[0, 1]);
        });
        test('CUU', () async {
          bufferService.buffer.x = 10000;
          bufferService.buffer.y = 10000;
          await inputHandler.parseP('\x1b[A');
          expect(getCursor(bufferService), <int>[9, 8]);
          bufferService.buffer.x = -10000;
          bufferService.buffer.y = -10000;
          await inputHandler.parseP('\x1b[A');
          expect(getCursor(bufferService), <int>[0, 0]);
        });
        test('CNL', () async {
          bufferService.buffer.x = 10000;
          bufferService.buffer.y = 10000;
          await inputHandler.parseP('\x1b[E');
          expect(getCursor(bufferService), <int>[0, 9]);
          bufferService.buffer.x = -10000;
          bufferService.buffer.y = -10000;
          await inputHandler.parseP('\x1b[E');
          expect(getCursor(bufferService), <int>[0, 1]);
        });
        test('CPL', () async {
          bufferService.buffer.x = 10000;
          bufferService.buffer.y = 10000;
          await inputHandler.parseP('\x1b[F');
          expect(getCursor(bufferService), <int>[0, 8]);
          bufferService.buffer.x = -10000;
          bufferService.buffer.y = -10000;
          await inputHandler.parseP('\x1b[F');
          expect(getCursor(bufferService), <int>[0, 0]);
        });
        test('CHA', () async {
          bufferService.buffer.x = 10000;
          bufferService.buffer.y = 10000;
          await inputHandler.parseP('\x1b[5G');
          expect(getCursor(bufferService), <int>[4, 9]);
          bufferService.buffer.x = -10000;
          bufferService.buffer.y = -10000;
          await inputHandler.parseP('\x1b[5G');
          expect(getCursor(bufferService), <int>[4, 0]);
        });
        test('CUP', () async {
          bufferService.buffer.x = 10000;
          bufferService.buffer.y = 10000;
          await inputHandler.parseP('\x1b[5;5H');
          expect(getCursor(bufferService), <int>[4, 4]);
          bufferService.buffer.x = -10000;
          bufferService.buffer.y = -10000;
          await inputHandler.parseP('\x1b[5;5H');
          expect(getCursor(bufferService), <int>[4, 4]);
        });
        test('HPA', () async {
          bufferService.buffer.x = 10000;
          bufferService.buffer.y = 10000;
          await inputHandler.parseP('\x1b[5`');
          expect(getCursor(bufferService), <int>[4, 9]);
          bufferService.buffer.x = -10000;
          bufferService.buffer.y = -10000;
          await inputHandler.parseP('\x1b[5`');
          expect(getCursor(bufferService), <int>[4, 0]);
        });
        test('HPR', () async {
          bufferService.buffer.x = 10000;
          bufferService.buffer.y = 10000;
          await inputHandler.parseP('\x1b[a');
          expect(getCursor(bufferService), <int>[9, 9]);
          bufferService.buffer.x = -10000;
          bufferService.buffer.y = -10000;
          await inputHandler.parseP('\x1b[a');
          expect(getCursor(bufferService), <int>[1, 0]);
        });
        test('VPA', () async {
          bufferService.buffer.x = 10000;
          bufferService.buffer.y = 10000;
          await inputHandler.parseP('\x1b[5d');
          expect(getCursor(bufferService), <int>[9, 4]);
          bufferService.buffer.x = -10000;
          bufferService.buffer.y = -10000;
          await inputHandler.parseP('\x1b[5d');
          expect(getCursor(bufferService), <int>[0, 4]);
        });
        test('VPR', () async {
          bufferService.buffer.x = 10000;
          bufferService.buffer.y = 10000;
          await inputHandler.parseP('\x1b[e');
          expect(getCursor(bufferService), <int>[9, 9]);
          bufferService.buffer.x = -10000;
          bufferService.buffer.y = -10000;
          await inputHandler.parseP('\x1b[e');
          expect(getCursor(bufferService), <int>[0, 1]);
        });
        test('DCH', () async {
          bufferService.buffer.x = 10000;
          bufferService.buffer.y = 10000;
          await inputHandler.parseP('\x1b[P');
          expect(getCursor(bufferService), <int>[9, 9]);
          bufferService.buffer.x = -10000;
          bufferService.buffer.y = -10000;
          await inputHandler.parseP('\x1b[P');
          expect(getCursor(bufferService), <int>[0, 0]);
        });
        test('DCH - should delete last cell', () async {
          await inputHandler.parseP('0123456789\x1b[P');
          expect(
            bufferService.buffer.lines.get(0)!.translateToString(false),
            '012345678 ',
          );
        });
        test('ECH', () async {
          bufferService.buffer.x = 10000;
          bufferService.buffer.y = 10000;
          await inputHandler.parseP('\x1b[X');
          expect(getCursor(bufferService), <int>[9, 9]);
          bufferService.buffer.x = -10000;
          bufferService.buffer.y = -10000;
          await inputHandler.parseP('\x1b[X');
          expect(getCursor(bufferService), <int>[0, 0]);
        });
        test('ECH - should delete last cell', () async {
          await inputHandler.parseP('0123456789\x1b[X');
          expect(
            bufferService.buffer.lines.get(0)!.translateToString(false),
            '012345678 ',
          );
        });
        test('ICH', () async {
          bufferService.buffer.x = 10000;
          bufferService.buffer.y = 10000;
          await inputHandler.parseP('\x1b[@');
          expect(getCursor(bufferService), <int>[9, 9]);
          bufferService.buffer.x = -10000;
          bufferService.buffer.y = -10000;
          await inputHandler.parseP('\x1b[@');
          expect(getCursor(bufferService), <int>[0, 0]);
        });
        test('ICH - should delete last cell', () async {
          await inputHandler.parseP('0123456789\x1b[@');
          expect(
            bufferService.buffer.lines.get(0)!.translateToString(false),
            '012345678 ',
          );
        });
      });
    });
    group('DECSTBM - scroll margins', () {
      setUp(() {
        bufferService.resize(10, 10);
      });
      test('should default to whole viewport', () async {
        await inputHandler.parseP('\x1b[r');
        expect(bufferService.buffer.scrollTop, 0);
        expect(bufferService.buffer.scrollBottom, 9);
        await inputHandler.parseP('\x1b[3;7r');
        expect(bufferService.buffer.scrollTop, 2);
        expect(bufferService.buffer.scrollBottom, 6);
        await inputHandler.parseP('\x1b[0;0r');
        expect(bufferService.buffer.scrollTop, 0);
        expect(bufferService.buffer.scrollBottom, 9);
      });
      test('should clamp bottom', () async {
        await inputHandler.parseP('\x1b[3;1000r');
        expect(bufferService.buffer.scrollTop, 2);
        expect(bufferService.buffer.scrollBottom, 9);
      });
      test('should only apply for top < bottom', () async {
        await inputHandler.parseP('\x1b[7;2r');
        expect(bufferService.buffer.scrollTop, 0);
        expect(bufferService.buffer.scrollBottom, 9);
      });
      test('should home cursor', () async {
        bufferService.buffer.x = 10000;
        bufferService.buffer.y = 10000;
        await inputHandler.parseP('\x1b[2;7r');
        expect(getCursor(bufferService), <int>[0, 0]);
      });
    });
    group('scroll margins', () {
      setUp(() {
        bufferService.resize(10, 10);
      });
      test('scrollUp', () async {
        await inputHandler.parseP(
          '0\r\n1\r\n2\r\n3\r\n4\r\n5\r\n6\r\n7\r\n8\r\n9\x1b[2;4r\x1b[2Sm',
        );
        expect(getLines(bufferService), <String>[
          'm',
          '3',
          '',
          '',
          '4',
          '5',
          '6',
          '7',
          '8',
          '9',
        ]);
      });
      test('scrollDown', () async {
        await inputHandler.parseP(
          '0\r\n1\r\n2\r\n3\r\n4\r\n5\r\n6\r\n7\r\n8\r\n9\x1b[2;4r\x1b[2Tm',
        );
        expect(getLines(bufferService), <String>[
          'm',
          '',
          '',
          '1',
          '4',
          '5',
          '6',
          '7',
          '8',
          '9',
        ]);
      });
      test('insertLines - out of margins', () async {
        await inputHandler.parseP(
          '0\r\n1\r\n2\r\n3\r\n4\r\n5\r\n6\r\n7\r\n8\r\n9\x1b[3;6r',
        );
        expect(bufferService.buffer.scrollTop, 2);
        expect(bufferService.buffer.scrollBottom, 5);
        await inputHandler.parseP('\x1b[2Lm');
        expect(getLines(bufferService), <String>[
          'm',
          '1',
          '2',
          '3',
          '4',
          '5',
          '6',
          '7',
          '8',
          '9',
        ]);
        await inputHandler.parseP('\x1b[2H\x1b[2Ln');
        expect(getLines(bufferService), <String>[
          'm',
          'n',
          '2',
          '3',
          '4',
          '5',
          '6',
          '7',
          '8',
          '9',
        ]);
        // skip below scrollbottom
        await inputHandler.parseP('\x1b[7H\x1b[2Lo');
        expect(getLines(bufferService), <String>[
          'm',
          'n',
          '2',
          '3',
          '4',
          '5',
          'o',
          '7',
          '8',
          '9',
        ]);
        await inputHandler.parseP('\x1b[8H\x1b[2Lp');
        expect(getLines(bufferService), <String>[
          'm',
          'n',
          '2',
          '3',
          '4',
          '5',
          'o',
          'p',
          '8',
          '9',
        ]);
        await inputHandler.parseP('\x1b[100H\x1b[2Lq');
        expect(getLines(bufferService), <String>[
          'm',
          'n',
          '2',
          '3',
          '4',
          '5',
          'o',
          'p',
          '8',
          'q',
        ]);
      });
      test('insertLines - within margins', () async {
        await inputHandler.parseP(
          '0\r\n1\r\n2\r\n3\r\n4\r\n5\r\n6\r\n7\r\n8\r\n9\x1b[3;6r',
        );
        expect(bufferService.buffer.scrollTop, 2);
        expect(bufferService.buffer.scrollBottom, 5);
        await inputHandler.parseP('\x1b[3H\x1b[2Lm');
        expect(getLines(bufferService), <String>[
          '0',
          '1',
          'm',
          '',
          '2',
          '3',
          '6',
          '7',
          '8',
          '9',
        ]);
        await inputHandler.parseP('\x1b[6H\x1b[2Ln');
        expect(getLines(bufferService), <String>[
          '0',
          '1',
          'm',
          '',
          '2',
          'n',
          '6',
          '7',
          '8',
          '9',
        ]);
      });
      test('deleteLines - out of margins', () async {
        await inputHandler.parseP(
          '0\r\n1\r\n2\r\n3\r\n4\r\n5\r\n6\r\n7\r\n8\r\n9\x1b[3;6r',
        );
        expect(bufferService.buffer.scrollTop, 2);
        expect(bufferService.buffer.scrollBottom, 5);
        await inputHandler.parseP('\x1b[2Mm');
        expect(getLines(bufferService), <String>[
          'm',
          '1',
          '2',
          '3',
          '4',
          '5',
          '6',
          '7',
          '8',
          '9',
        ]);
        await inputHandler.parseP('\x1b[2H\x1b[2Mn');
        expect(getLines(bufferService), <String>[
          'm',
          'n',
          '2',
          '3',
          '4',
          '5',
          '6',
          '7',
          '8',
          '9',
        ]);
        // skip below scrollbottom
        await inputHandler.parseP('\x1b[7H\x1b[2Mo');
        expect(getLines(bufferService), <String>[
          'm',
          'n',
          '2',
          '3',
          '4',
          '5',
          'o',
          '7',
          '8',
          '9',
        ]);
        await inputHandler.parseP('\x1b[8H\x1b[2Mp');
        expect(getLines(bufferService), <String>[
          'm',
          'n',
          '2',
          '3',
          '4',
          '5',
          'o',
          'p',
          '8',
          '9',
        ]);
        await inputHandler.parseP('\x1b[100H\x1b[2Mq');
        expect(getLines(bufferService), <String>[
          'm',
          'n',
          '2',
          '3',
          '4',
          '5',
          'o',
          'p',
          '8',
          'q',
        ]);
      });
      test('deleteLines - within margins', () async {
        await inputHandler.parseP(
          '0\r\n1\r\n2\r\n3\r\n4\r\n5\r\n6\r\n7\r\n8\r\n9\x1b[3;6r',
        );
        expect(bufferService.buffer.scrollTop, 2);
        expect(bufferService.buffer.scrollBottom, 5);
        await inputHandler.parseP('\x1b[6H\x1b[2Mm');
        expect(getLines(bufferService), <String>[
          '0',
          '1',
          '2',
          '3',
          '4',
          'm',
          '6',
          '7',
          '8',
          '9',
        ]);
        await inputHandler.parseP('\x1b[3H\x1b[2Mn');
        expect(getLines(bufferService), <String>[
          '0',
          '1',
          'n',
          'm',
          '',
          '',
          '6',
          '7',
          '8',
          '9',
        ]);
      });
    });
    test('should parse big chunks in smaller subchunks', () async {
      // max single chunk size is hardcoded as 131072
      bufferService.resize(10, 10);
      final parser = _RecordingParser();
      inputHandler = TestInputHandler(
        bufferService,
        MockCharsetService(),
        coreService,
        MockLogService(),
        optionsService,
        oscLinkService,
        MockMouseStateService(),
        MockUnicodeService(),
        parser,
      );
      final calls = parser.calls;
      await inputHandler.parseP('12345');
      await inputHandler.parseP('a' * 10000);
      await inputHandler.parseP('a' * 200000);
      await inputHandler.parseP('a' * 300000);
      expect(calls, <List<int>>[
        <int>[4096, 5],
        <int>[10000, 10000],
        <int>[131072, 131072],
        <int>[131072, 200000 - 131072],
        <int>[131072, 131072],
        <int>[131072, 131072],
        <int>[131072, 300000 - 131072 - 131072],
      ]);
    });
    group('windowOptions', () {
      test('all should be disabled by default and not report', () async {
        bufferService.resize(10, 10);
        final stack = <String>[];
        coreService.onData((data) => stack.add(data));
        await inputHandler.parseP('\x1b[14t');
        await inputHandler.parseP('\x1b[16t');
        await inputHandler.parseP('\x1b[18t');
        await inputHandler.parseP('\x1b[20t');
        await inputHandler.parseP('\x1b[21t');
        expect(stack, <String>[]);
      });
      test('14 - GetWinSizePixels', () async {
        bufferService.resize(10, 10);
        optionsService.options.windowOptions.getWinSizePixels = true;
        final stack = <String>[];
        coreService.onData((data) => stack.add(data));
        await inputHandler.parseP('\x1b[14t');
        // does not report in test terminal due to missing renderer
        expect(stack, <String>[]);
      });
      test('16 - GetCellSizePixels', () async {
        bufferService.resize(10, 10);
        optionsService.options.windowOptions.getCellSizePixels = true;
        final stack = <String>[];
        coreService.onData((data) => stack.add(data));
        await inputHandler.parseP('\x1b[16t');
        // does not report in test terminal due to missing renderer
        expect(stack, <String>[]);
      });
      test('18 - GetWinSizeChars', () async {
        bufferService.resize(10, 10);
        optionsService.options.windowOptions.getWinSizeChars = true;
        final stack = <String>[];
        coreService.onData((data) => stack.add(data));
        await inputHandler.parseP('\x1b[18t');
        expect(stack, <String>['\x1b[8;10;10t']);
        bufferService.resize(50, 20);
        await inputHandler.parseP('\x1b[18t');
        expect(stack, <String>['\x1b[8;10;10t', '\x1b[8;20;50t']);
      });
      test('22/23 - PushTitle/PopTitle', () async {
        bufferService.resize(10, 10);
        optionsService.options.windowOptions.pushTitle = true;
        optionsService.options.windowOptions.popTitle = true;
        final stack = <String>[];
        inputHandler.onTitleChange((data) => stack.add(data));
        await inputHandler.parseP('\x1b]0;1\x07');
        await inputHandler.parseP('\x1b[22t');
        await inputHandler.parseP('\x1b]0;2\x07');
        await inputHandler.parseP('\x1b[22t');
        await inputHandler.parseP('\x1b]0;3\x07');
        await inputHandler.parseP('\x1b[22t');
        expect(inputHandler.windowTitleStack, <String>['1', '2', '3']);
        expect(inputHandler.iconNameStack, <String>['1', '2', '3']);
        expect(stack, <String>['1', '2', '3']);
        await inputHandler.parseP('\x1b[23t');
        await inputHandler.parseP('\x1b[23t');
        await inputHandler.parseP('\x1b[23t');
        await inputHandler.parseP('\x1b[23t'); // one more to test "overflow"
        expect(inputHandler.windowTitleStack, <String>[]);
        expect(inputHandler.iconNameStack, <String>[]);
        expect(stack, <String>['1', '2', '3', '3', '2', '1']);
      });
      test('22/23 - PushTitle/PopTitle with ;1', () async {
        bufferService.resize(10, 10);
        optionsService.options.windowOptions.pushTitle = true;
        optionsService.options.windowOptions.popTitle = true;
        final stack = <String>[];
        inputHandler.onTitleChange((data) => stack.add(data));
        await inputHandler.parseP('\x1b]0;1\x07');
        await inputHandler.parseP('\x1b[22;1t');
        await inputHandler.parseP('\x1b]0;2\x07');
        await inputHandler.parseP('\x1b[22;1t');
        await inputHandler.parseP('\x1b]0;3\x07');
        await inputHandler.parseP('\x1b[22;1t');
        expect(inputHandler.windowTitleStack, <String>[]);
        expect(inputHandler.iconNameStack, <String>['1', '2', '3']);
        expect(stack, <String>['1', '2', '3']);
        await inputHandler.parseP('\x1b[23;1t');
        await inputHandler.parseP('\x1b[23;1t');
        await inputHandler.parseP('\x1b[23;1t');
        await inputHandler.parseP('\x1b[23;1t'); // one more to test "overflow"
        expect(inputHandler.windowTitleStack, <String>[]);
        expect(inputHandler.iconNameStack, <String>[]);
        expect(stack, <String>['1', '2', '3']);
      });
      test('22/23 - PushTitle/PopTitle with ;2', () async {
        bufferService.resize(10, 10);
        optionsService.options.windowOptions.pushTitle = true;
        optionsService.options.windowOptions.popTitle = true;
        final stack = <String>[];
        inputHandler.onTitleChange((data) => stack.add(data));
        await inputHandler.parseP('\x1b]0;1\x07');
        await inputHandler.parseP('\x1b[22;2t');
        await inputHandler.parseP('\x1b]0;2\x07');
        await inputHandler.parseP('\x1b[22;2t');
        await inputHandler.parseP('\x1b]0;3\x07');
        await inputHandler.parseP('\x1b[22;2t');
        expect(inputHandler.windowTitleStack, <String>['1', '2', '3']);
        expect(inputHandler.iconNameStack, <String>[]);
        expect(stack, <String>['1', '2', '3']);
        await inputHandler.parseP('\x1b[23;2t');
        await inputHandler.parseP('\x1b[23;2t');
        await inputHandler.parseP('\x1b[23;2t');
        await inputHandler.parseP('\x1b[23;2t'); // one more to test "overflow"
        expect(inputHandler.windowTitleStack, <String>[]);
        expect(inputHandler.iconNameStack, <String>[]);
        expect(stack, <String>['1', '2', '3', '3', '2', '1']);
      });
      test(
        'DECCOLM - should only work with "SetWinLines" (24) enabled',
        () async {
          // disabled
          bufferService.resize(10, 10);
          await inputHandler.parseP('\x1b[?3l');
          expect(bufferService.cols, 10);
          await inputHandler.parseP('\x1b[?3h');
          expect(bufferService.cols, 10);
          // enabled
          inputHandler.reset();
          optionsService.options.windowOptions.setWinLines = true;
          await inputHandler.parseP('\x1b[?3l');
          expect(bufferService.cols, 80);
          await inputHandler.parseP('\x1b[?3h');
          expect(bufferService.cols, 132);
        },
      );
    });
    group('XTVERSION (CSI > q, CSI > 0 q)', () {
      test('should report xterm.js version', () async {
        final stack = <String>[];
        coreService.onData((data) => stack.add(data));
        await inputHandler.parseP('\x1b[>q');
        expect(stack.length, 1);
        expect(
          stack[0],
          matches(
            RegExp(r'^\x1bP>\|xterm\.js\(\d+\.\d+\.\d+(-beta\.\d+)?\)\x1b\\'),
          ),
        );
      });
      test('should report xterm.js version for CSI > 0 q', () async {
        final stack = <String>[];
        coreService.onData((data) => stack.add(data));
        await inputHandler.parseP('\x1b[>0q');
        expect(stack.length, 1);
        expect(
          stack[0],
          matches(
            RegExp(r'^\x1bP>\|xterm\.js\(\d+\.\d+\.\d+(-beta\.\d+)?\)\x1b\\'),
          ),
        );
      });
      test('should not report for CSI > 1 q', () async {
        final stack = <String>[];
        coreService.onData((data) => stack.add(data));
        await inputHandler.parseP('\x1b[>1q');
        expect(stack.length, 0);
      });
    });
    group('should correctly reset cells taken by wide chars', () {
      setUp(() async {
        bufferService.resize(10, 5);
        optionsService.options.scrollback = 1;
        await inputHandler.parseP('￥￥￥￥￥￥￥￥￥￥￥￥￥￥￥￥￥￥￥￥');
      });
      test('print', () async {
        await inputHandler.parseP('\x1b[H#');
        expect(getLines(bufferService), <String>[
          '# ￥￥￥￥',
          '￥￥￥￥￥',
          '￥￥￥￥￥',
          '￥￥￥￥￥',
          '',
        ]);
        await inputHandler.parseP('\x1b[1;6H######');
        expect(getLines(bufferService), <String>[
          '# ￥ #####',
          '# ￥￥￥￥',
          '￥￥￥￥￥',
          '￥￥￥￥￥',
          '',
        ]);
        await inputHandler.parseP('#');
        expect(getLines(bufferService), <String>[
          '# ￥ #####',
          '##￥￥￥￥',
          '￥￥￥￥￥',
          '￥￥￥￥￥',
          '',
        ]);
        await inputHandler.parseP('#');
        expect(getLines(bufferService), <String>[
          '# ￥ #####',
          '### ￥￥￥',
          '￥￥￥￥￥',
          '￥￥￥￥￥',
          '',
        ]);
        await inputHandler.parseP('\x1b[3;9H#');
        expect(getLines(bufferService), <String>[
          '# ￥ #####',
          '### ￥￥￥',
          '￥￥￥￥#',
          '￥￥￥￥￥',
          '',
        ]);
        await inputHandler.parseP('#');
        expect(getLines(bufferService), <String>[
          '# ￥ #####',
          '### ￥￥￥',
          '￥￥￥￥##',
          '￥￥￥￥￥',
          '',
        ]);
        await inputHandler.parseP('#');
        expect(getLines(bufferService), <String>[
          '# ￥ #####',
          '### ￥￥￥',
          '￥￥￥￥##',
          '# ￥￥￥￥',
          '',
        ]);
        await inputHandler.parseP('\x1b[4;10H#');
        expect(getLines(bufferService), <String>[
          '# ￥ #####',
          '### ￥￥￥',
          '￥￥￥￥##',
          '# ￥￥￥ #',
          '',
        ]);
      });
      test('EL', () async {
        await inputHandler.parseP('\x1b[1;6H\x1b[K#');
        expect(getLines(bufferService), <String>[
          '￥￥ #',
          '￥￥￥￥￥',
          '￥￥￥￥￥',
          '￥￥￥￥￥',
          '',
        ]);
        await inputHandler.parseP('\x1b[2;5H\x1b[1K');
        expect(getLines(bufferService), <String>[
          '￥￥ #',
          '      ￥￥',
          '￥￥￥￥￥',
          '￥￥￥￥￥',
          '',
        ]);
        await inputHandler.parseP('\x1b[3;6H\x1b[1K');
        expect(getLines(bufferService), <String>[
          '￥￥ #',
          '      ￥￥',
          '      ￥￥',
          '￥￥￥￥￥',
          '',
        ]);
      });
      test('ICH', () async {
        await inputHandler.parseP('\x1b[1;6H\x1b[@');
        expect(getLines(bufferService), <String>[
          '￥￥   ￥',
          '￥￥￥￥￥',
          '￥￥￥￥￥',
          '￥￥￥￥￥',
          '',
        ]);
        await inputHandler.parseP('\x1b[2;4H\x1b[2@');
        expect(getLines(bufferService), <String>[
          '￥￥   ￥',
          '￥    ￥￥',
          '￥￥￥￥￥',
          '￥￥￥￥￥',
          '',
        ]);
        await inputHandler.parseP('\x1b[3;4H\x1b[3@');
        expect(getLines(bufferService), <String>[
          '￥￥   ￥',
          '￥    ￥￥',
          '￥     ￥',
          '￥￥￥￥￥',
          '',
        ]);
        await inputHandler.parseP('\x1b[4;4H\x1b[4@');
        expect(getLines(bufferService), <String>[
          '￥￥   ￥',
          '￥    ￥￥',
          '￥     ￥',
          '￥      ￥',
          '',
        ]);
      });
      test('DCH', () async {
        await inputHandler.parseP('\x1b[1;6H\x1b[P');
        expect(getLines(bufferService), <String>[
          '￥￥ ￥￥',
          '￥￥￥￥￥',
          '￥￥￥￥￥',
          '￥￥￥￥￥',
          '',
        ]);
        await inputHandler.parseP('\x1b[2;6H\x1b[2P');
        expect(getLines(bufferService), <String>[
          '￥￥ ￥￥',
          '￥￥  ￥',
          '￥￥￥￥￥',
          '￥￥￥￥￥',
          '',
        ]);
        await inputHandler.parseP('\x1b[3;6H\x1b[3P');
        expect(getLines(bufferService), <String>[
          '￥￥ ￥￥',
          '￥￥  ￥',
          '￥￥ ￥',
          '￥￥￥￥￥',
          '',
        ]);
      });
      test('ECH', () async {
        await inputHandler.parseP('\x1b[1;6H\x1b[X');
        expect(getLines(bufferService), <String>[
          '￥￥  ￥￥',
          '￥￥￥￥￥',
          '￥￥￥￥￥',
          '￥￥￥￥￥',
          '',
        ]);
        await inputHandler.parseP('\x1b[2;6H\x1b[2X');
        expect(getLines(bufferService), <String>[
          '￥￥  ￥￥',
          '￥￥    ￥',
          '￥￥￥￥￥',
          '￥￥￥￥￥',
          '',
        ]);
        await inputHandler.parseP('\x1b[3;6H\x1b[3X');
        expect(getLines(bufferService), <String>[
          '￥￥  ￥￥',
          '￥￥    ￥',
          '￥￥    ￥',
          '￥￥￥￥￥',
          '',
        ]);
      });
    });

    group('BS with reverseWraparound set/unset', () {
      const ttyBS = '\x08 \x08'; // tty ICANON sends <BS SP BS> on pressing BS
      setUp(() {
        bufferService.resize(5, 5);
        optionsService.options.scrollback = 1;
      });
      group('reverseWraparound unset (default)', () {
        test('cannot delete last cell', () async {
          await inputHandler.parseP('12345');
          await inputHandler.parseP(ttyBS);
          expect(getLines(bufferService, 1), <String>['123 5']);
          await inputHandler.parseP(ttyBS * 10);
          expect(getLines(bufferService, 1), <String>['    5']);
        });
        test('cannot access prev line', () async {
          await inputHandler.parseP('12345' * 2);
          await inputHandler.parseP(ttyBS);
          expect(getLines(bufferService, 2), <String>['12345', '123 5']);
          await inputHandler.parseP(ttyBS * 10);
          expect(getLines(bufferService, 2), <String>['12345', '    5']);
        });
      });
      group('reverseWraparound set', () {
        test('can delete last cell', () async {
          await inputHandler.parseP('\x1b[?45h');
          await inputHandler.parseP('12345');
          await inputHandler.parseP(ttyBS);
          expect(getLines(bufferService, 1), <String>['1234 ']);
          await inputHandler.parseP(ttyBS * 7);
          expect(getLines(bufferService, 1), <String>['     ']);
        });
        test('can access prev line if wrapped', () async {
          await inputHandler.parseP('\x1b[?45h');
          await inputHandler.parseP('12345' * 2);
          await inputHandler.parseP(ttyBS);
          expect(getLines(bufferService, 2), <String>['12345', '1234 ']);
          await inputHandler.parseP(ttyBS * 7);
          expect(getLines(bufferService, 2), <String>['12   ', '     ']);
        });
        test('should lift isWrapped', () async {
          await inputHandler.parseP('\x1b[?45h');
          await inputHandler.parseP('12345' * 2);
          expect(bufferService.buffer.lines.get(1)?.isWrapped, true);
          await inputHandler.parseP(ttyBS * 7);
          expect(bufferService.buffer.lines.get(1)?.isWrapped, false);
        });
        test('stops at hard NLs', () async {
          await inputHandler.parseP('\x1b[?45h');
          await inputHandler.parseP('12345\r\n');
          await inputHandler.parseP('12345' * 2);
          await inputHandler.parseP(ttyBS * 50);
          expect(getLines(bufferService, 3), <String>[
            '12345',
            '     ',
            '     ',
          ]);
          expect(bufferService.buffer.x, 0);
          expect(bufferService.buffer.y, 1);
        });
        test('handles wide chars correctly', () async {
          await inputHandler.parseP('\x1b[?45h');
          await inputHandler.parseP('￥￥￥');
          expect(getLines(bufferService, 2), <String>['￥￥', '￥']);
          await inputHandler.parseP(ttyBS);
          expect(getLines(bufferService, 2), <String>['￥￥', '  ']);
          expect(bufferService.buffer.x, 1);
          await inputHandler.parseP(ttyBS);
          expect(getLines(bufferService, 2), <String>['￥￥', '  ']);
          expect(bufferService.buffer.x, 0);
          await inputHandler.parseP(ttyBS);
          expect(getLines(bufferService, 2), <String>['￥  ', '  ']);
          expect(
            bufferService.buffer.x,
            3,
          ); // x=4 skipped due to early wrap-around
          await inputHandler.parseP(ttyBS);
          expect(getLines(bufferService, 2), <String>['￥  ', '  ']);
          expect(bufferService.buffer.x, 2);
          await inputHandler.parseP(ttyBS);
          expect(getLines(bufferService, 2), <String>['    ', '  ']);
          expect(bufferService.buffer.x, 1);
          await inputHandler.parseP(ttyBS);
          expect(getLines(bufferService, 2), <String>['    ', '  ']);
          expect(bufferService.buffer.x, 0);
        });
      });
    });

    group('reset text attributes (SGR 0)', () {
      test('resets all attributes if there is no url', () async {
        await inputHandler.parseP('\x1b[30m\x1b[40m\x1b[4m');
        expect(inputHandler.curAttrData.fg, isNot(0));
        expect(inputHandler.curAttrData.bg, isNot(0));
        expect(inputHandler.curAttrData.extended.isEmpty(), isFalse);

        await inputHandler.parseP('\x1b[m');
        expect(inputHandler.curAttrData.fg, 0);
        expect(inputHandler.curAttrData.bg, 0);
        expect(inputHandler.curAttrData.extended.isEmpty(), isTrue);
      });

      test('resets all attributes except for the url', () async {
        await inputHandler.parseP('\x1b[30m\x1b[40m\x1b[4m');
        await inputHandler.parseP('\x1b]8;;http://example.com\x1b\\');
        expect(inputHandler.curAttrData.fg, isNot(0));
        expect(inputHandler.curAttrData.bg, isNot(0));
        expect(inputHandler.curAttrData.extended.ext, isNot(0));
        final urlId = inputHandler.curAttrData.extended.urlId;
        expect(urlId, isNot(0));

        await inputHandler.parseP('\x1b[m');
        expect(inputHandler.curAttrData.fg, 0);
        expect(inputHandler.curAttrData.bg, BgFlags.hasExtended);
        final expectedExtended = ExtendedAttrs();
        expectedExtended.urlId = urlId;
        expect(
          _extendedFields(inputHandler.curAttrData.extended),
          _extendedFields(expectedExtended),
        );
      });
    });

    group('extended underline style support (SGR 4)', () {
      setUp(() {
        bufferService.resize(10, 5);
      });
      test('4 | 24', () async {
        await inputHandler.parseP('\x1b[4m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.single,
        );
        await inputHandler.parseP('\x1b[24m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.none,
        );
      });
      test('21 | 24', () async {
        await inputHandler.parseP('\x1b[21m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.double,
        );
        await inputHandler.parseP('\x1b[24m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.none,
        );
      });
      test('4:1 | 4:0', () async {
        await inputHandler.parseP('\x1b[4:1m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.single,
        );
        await inputHandler.parseP('\x1b[4:0m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.none,
        );
        await inputHandler.parseP('\x1b[4:1m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.single,
        );
        await inputHandler.parseP('\x1b[24m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.none,
        );
      });
      test('4:2 | 4:0', () async {
        await inputHandler.parseP('\x1b[4:2m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.double,
        );
        await inputHandler.parseP('\x1b[4:0m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.none,
        );
        await inputHandler.parseP('\x1b[4:2m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.double,
        );
        await inputHandler.parseP('\x1b[24m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.none,
        );
      });
      test('4:3 | 4:0', () async {
        await inputHandler.parseP('\x1b[4:3m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.curly,
        );
        await inputHandler.parseP('\x1b[4:0m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.none,
        );
        await inputHandler.parseP('\x1b[4:3m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.curly,
        );
        await inputHandler.parseP('\x1b[24m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.none,
        );
      });
      test('4:4 | 4:0', () async {
        await inputHandler.parseP('\x1b[4:4m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.dotted,
        );
        await inputHandler.parseP('\x1b[4:0m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.none,
        );
        await inputHandler.parseP('\x1b[4:4m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.dotted,
        );
        await inputHandler.parseP('\x1b[24m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.none,
        );
      });
      test('4:5 | 4:0', () async {
        await inputHandler.parseP('\x1b[4:5m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.dashed,
        );
        await inputHandler.parseP('\x1b[4:0m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.none,
        );
        await inputHandler.parseP('\x1b[4:5m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.dashed,
        );
        await inputHandler.parseP('\x1b[24m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.none,
        );
      });
      test('4:x --> 4 should revert to single underline', () async {
        await inputHandler.parseP('\x1b[4:5m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.dashed,
        );
        await inputHandler.parseP('\x1b[4m');
        expect(
          inputHandler.curAttrData.getUnderlineStyle(),
          UnderlineStyle.single,
        );
      });
    });
    group('underline colors (SGR 58 & SGR 59)', () {
      setUp(() {
        bufferService.resize(10, 5);
      });
      test('defaults to FG color', () async {
        for (final s in <String>[
          '',
          '\x1b[30m',
          '\x1b[38;510m',
          '\x1b[38;2;1;2;3m',
        ]) {
          await inputHandler.parseP(s);
          expect(
            inputHandler.curAttrData.getUnderlineColor(),
            inputHandler.curAttrData.getFgColor(),
          );
          expect(
            inputHandler.curAttrData.getUnderlineColorMode(),
            inputHandler.curAttrData.getFgColorMode(),
          );
          expect(
            inputHandler.curAttrData.isUnderlineColorRGB(),
            inputHandler.curAttrData.isFgRGB(),
          );
          expect(
            inputHandler.curAttrData.isUnderlineColorPalette(),
            inputHandler.curAttrData.isFgPalette(),
          );
          expect(
            inputHandler.curAttrData.isUnderlineColorDefault(),
            inputHandler.curAttrData.isFgDefault(),
          );
        }
      });
      test('correctly sets P256/RGB colors', () async {
        await inputHandler.parseP('\x1b[4m');
        await inputHandler.parseP('\x1b[58;5;123m');
        expect(inputHandler.curAttrData.getUnderlineColor(), 123);
        expect(
          inputHandler.curAttrData.getUnderlineColorMode(),
          Attributes.cmP256,
        );
        expect(inputHandler.curAttrData.isUnderlineColorRGB(), false);
        expect(inputHandler.curAttrData.isUnderlineColorPalette(), true);
        expect(inputHandler.curAttrData.isUnderlineColorDefault(), false);
        await inputHandler.parseP('\x1b[58;2::1:2:3m');
        expect(
          inputHandler.curAttrData.getUnderlineColor(),
          (1 << 16) | (2 << 8) | 3,
        );
        expect(
          inputHandler.curAttrData.getUnderlineColorMode(),
          Attributes.cmRgb,
        );
        expect(inputHandler.curAttrData.isUnderlineColorRGB(), true);
        expect(inputHandler.curAttrData.isUnderlineColorPalette(), false);
        expect(inputHandler.curAttrData.isUnderlineColorDefault(), false);
      });
      test('P256/RGB persistence', () async {
        final cell = CellData();
        await inputHandler.parseP('\x1b[4m');
        await inputHandler.parseP('\x1b[58;5;123m');
        expect(inputHandler.curAttrData.getUnderlineColor(), 123);
        expect(
          inputHandler.curAttrData.getUnderlineColorMode(),
          Attributes.cmP256,
        );
        expect(inputHandler.curAttrData.isUnderlineColorRGB(), false);
        expect(inputHandler.curAttrData.isUnderlineColorPalette(), true);
        expect(inputHandler.curAttrData.isUnderlineColorDefault(), false);
        await inputHandler.parseP('ab');
        bufferService.buffer.lines.get(0)!.loadCell(1, cell);
        expect(cell.getUnderlineColor(), 123);
        expect(cell.getUnderlineColorMode(), Attributes.cmP256);
        expect(cell.isUnderlineColorRGB(), false);
        expect(cell.isUnderlineColorPalette(), true);
        expect(cell.isUnderlineColorDefault(), false);

        await inputHandler.parseP('\x1b[4:0m');
        expect(
          inputHandler.curAttrData.getUnderlineColor(),
          inputHandler.curAttrData.getFgColor(),
        );
        expect(
          inputHandler.curAttrData.getUnderlineColorMode(),
          inputHandler.curAttrData.getFgColorMode(),
        );
        expect(
          inputHandler.curAttrData.isUnderlineColorRGB(),
          inputHandler.curAttrData.isFgRGB(),
        );
        expect(
          inputHandler.curAttrData.isUnderlineColorPalette(),
          inputHandler.curAttrData.isFgPalette(),
        );
        expect(
          inputHandler.curAttrData.isUnderlineColorDefault(),
          inputHandler.curAttrData.isFgDefault(),
        );
        await inputHandler.parseP('a');
        bufferService.buffer.lines.get(0)!.loadCell(1, cell);
        expect(cell.getUnderlineColor(), 123);
        expect(cell.getUnderlineColorMode(), Attributes.cmP256);
        expect(cell.isUnderlineColorRGB(), false);
        expect(cell.isUnderlineColorPalette(), true);
        expect(cell.isUnderlineColorDefault(), false);
        bufferService.buffer.lines.get(0)!.loadCell(2, cell);
        expect(cell.getUnderlineColor(), inputHandler.curAttrData.getFgColor());
        expect(
          cell.getUnderlineColorMode(),
          inputHandler.curAttrData.getFgColorMode(),
        );
        expect(cell.isUnderlineColorRGB(), inputHandler.curAttrData.isFgRGB());
        expect(
          cell.isUnderlineColorPalette(),
          inputHandler.curAttrData.isFgPalette(),
        );
        expect(
          cell.isUnderlineColorDefault(),
          inputHandler.curAttrData.isFgDefault(),
        );

        await inputHandler.parseP('\x1b[4m');
        await inputHandler.parseP('\x1b[58;2::1:2:3m');
        expect(
          inputHandler.curAttrData.getUnderlineColor(),
          (1 << 16) | (2 << 8) | 3,
        );
        expect(
          inputHandler.curAttrData.getUnderlineColorMode(),
          Attributes.cmRgb,
        );
        expect(inputHandler.curAttrData.isUnderlineColorRGB(), true);
        expect(inputHandler.curAttrData.isUnderlineColorPalette(), false);
        expect(inputHandler.curAttrData.isUnderlineColorDefault(), false);
        await inputHandler.parseP('a');
        await inputHandler.parseP('\x1b[24m');
        bufferService.buffer.lines.get(0)!.loadCell(1, cell);
        expect(cell.getUnderlineColor(), 123);
        expect(cell.getUnderlineColorMode(), Attributes.cmP256);
        expect(cell.isUnderlineColorRGB(), false);
        expect(cell.isUnderlineColorPalette(), true);
        expect(cell.isUnderlineColorDefault(), false);
        bufferService.buffer.lines.get(0)!.loadCell(3, cell);
        expect(cell.getUnderlineColor(), (1 << 16) | (2 << 8) | 3);
        expect(cell.getUnderlineColorMode(), Attributes.cmRgb);
        expect(cell.isUnderlineColorRGB(), true);
        expect(cell.isUnderlineColorPalette(), false);
        expect(cell.isUnderlineColorDefault(), false);

        // eAttrs in buffer pos 0 and 1 should be the same object
        expect(
          extendedAttributes(bufferService.buffer.lines.get(0)!, 0),
          same(extendedAttributes(bufferService.buffer.lines.get(0)!, 1)),
        );
        // should not have written eAttr for pos 2 in the buffer
        expect(
          extendedAttributes(bufferService.buffer.lines.get(0)!, 2),
          isNull,
        );
        // eAttrs in buffer pos 1 and pos 3 must be different objs
        expect(
          extendedAttributes(bufferService.buffer.lines.get(0)!, 1),
          isNot(
            same(extendedAttributes(bufferService.buffer.lines.get(0)!, 3)),
          ),
        );
      });
    });
    group('DECSTR', () {
      setUp(() async {
        bufferService.resize(10, 5);
        optionsService.options.scrollback = 1;
        await inputHandler.parseP('01234567890123');
      });
      test('should reset IRM', () async {
        await inputHandler.parseP('\x1b[4h');
        expect(coreService.modes.insertMode, true);
        await inputHandler.parseP('\x1b[!p');
        expect(coreService.modes.insertMode, false);
      });
      test('should reset cursor visibility', () async {
        await inputHandler.parseP('\x1b[?25l');
        expect(coreService.isCursorHidden, true);
        await inputHandler.parseP('\x1b[!p');
        expect(coreService.isCursorHidden, false);
      });
      test('should reset scroll margins', () async {
        await inputHandler.parseP('\x1b[2;4r');
        expect(bufferService.buffer.scrollTop, 1);
        expect(bufferService.buffer.scrollBottom, 3);
        await inputHandler.parseP('\x1b[!p');
        expect(bufferService.buffer.scrollTop, 0);
        expect(bufferService.buffer.scrollBottom, bufferService.rows - 1);
      });
      test('should reset text attributes', () async {
        await inputHandler.parseP('\x1b[1;2;32;43m');
        expect(inputHandler.curAttrData.isBold() != 0, true);
        await inputHandler.parseP('\x1b[!p');
        expect(inputHandler.curAttrData.isBold() != 0, false);
        expect(inputHandler.curAttrData.fg, 0);
        expect(inputHandler.curAttrData.bg, 0);
      });
      test('should reset DECSC data', () async {
        await inputHandler.parseP('\x1b7');
        expect(bufferService.buffer.savedX, 4);
        expect(bufferService.buffer.savedY, 1);
        await inputHandler.parseP('\x1b[!p');
        expect(bufferService.buffer.savedX, 0);
        expect(bufferService.buffer.savedY, 0);
      });
      test('should reset DECOM', () async {
        await inputHandler.parseP('\x1b[?6h');
        expect(coreService.decPrivateModes.origin, true);
        await inputHandler.parseP('\x1b[!p');
        expect(coreService.decPrivateModes.origin, false);
      });
    });
    group('OSC', () {
      test('4: query color events', () async {
        final stack = <IColorEvent>[];
        inputHandler.onColor((ev) => stack.add(ev));
        // single color query
        await inputHandler.parseP('\x1b]4;0;?\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{'type': ColorRequestType.report, 'index': 0},
          ],
        ]);
        stack.clear();
        await inputHandler.parseP('\x1b]4;123;?\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{'type': ColorRequestType.report, 'index': 123},
          ],
        ]);
        stack.clear();
        // multiple queries
        await inputHandler.parseP('\x1b]4;0;?;123;?\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{'type': ColorRequestType.report, 'index': 0},
            <String, Object?>{'type': ColorRequestType.report, 'index': 123},
          ],
        ]);
        stack.clear();
      });
      test('4: set color events', () async {
        final stack = <IColorEvent>[];
        inputHandler.onColor((ev) => stack.add(ev));
        // single color query
        await inputHandler.parseP('\x1b]4;0;rgb:01/02/03\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.set,
              'index': 0,
              'color': <int>[1, 2, 3],
            },
          ],
        ]);
        stack.clear();
        await inputHandler.parseP('\x1b]4;123;#aabbcc\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.set,
              'index': 123,
              'color': <int>[170, 187, 204],
            },
          ],
        ]);
        stack.clear();
        // multiple queries
        await inputHandler.parseP('\x1b]4;0;rgb:aa/bb/cc;123;#001122\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.set,
              'index': 0,
              'color': <int>[170, 187, 204],
            },
            <String, Object?>{
              'type': ColorRequestType.set,
              'index': 123,
              'color': <int>[0, 17, 34],
            },
          ],
        ]);
        stack.clear();
      });
      test('4: should ignore invalid values', () async {
        final stack = <IColorEvent>[];
        inputHandler.onColor((ev) => stack.add(ev));
        await inputHandler.parseP(
          '\x1b]4;0;rgb:aa/bb/cc;45;rgb:1/22/333;123;#001122\x07',
        );
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.set,
              'index': 0,
              'color': <int>[170, 187, 204],
            },
            <String, Object?>{
              'type': ColorRequestType.set,
              'index': 123,
              'color': <int>[0, 17, 34],
            },
          ],
        ]);
        stack.clear();
      });
      test('8: hyperlink with id', () async {
        await inputHandler.parseP('\x1b]8;id=100;http://localhost:3000\x07');
        expect(inputHandler.curAttrData.extended.urlId, isNot(0));
        final linkData = oscLinkService.getLinkData(
          inputHandler.curAttrData.extended.urlId,
        );
        expect(linkData?.id, '100');
        expect(linkData?.uri, 'http://localhost:3000');
        await inputHandler.parseP('\x1b]8;;\x07');
        expect(inputHandler.curAttrData.extended.urlId, 0);
      });
      test('8: hyperlink with semi-colon', () async {
        await inputHandler.parseP('\x1b]8;;http://localhost:3000;abc=def\x07');
        expect(inputHandler.curAttrData.extended.urlId, isNot(0));
        final linkData = oscLinkService.getLinkData(
          inputHandler.curAttrData.extended.urlId,
        );
        expect(linkData, isNotNull);
        expect(linkData!.id, isNull);
        expect(linkData.uri, 'http://localhost:3000;abc=def');
        await inputHandler.parseP('\x1b]8;;\x07');
        expect(inputHandler.curAttrData.extended.urlId, 0);
      });
      test('104: restore events', () async {
        final stack = <IColorEvent>[];
        inputHandler.onColor((ev) => stack.add(ev));
        await inputHandler.parseP('\x1b]104;0\x07\x1b]104;43\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{'type': ColorRequestType.restore, 'index': 0},
          ],
          <Object>[
            <String, Object?>{'type': ColorRequestType.restore, 'index': 43},
          ],
        ]);
        stack.clear();
        // multiple in one command
        await inputHandler.parseP('\x1b]104;0;43\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{'type': ColorRequestType.restore, 'index': 0},
            <String, Object?>{'type': ColorRequestType.restore, 'index': 43},
          ],
        ]);
        stack.clear();
        // full ANSI table restore
        await inputHandler.parseP('\x1b]104\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{'type': ColorRequestType.restore},
          ],
        ]);
      });

      test('10: FG set & query events', () async {
        final stack = <IColorEvent>[];
        inputHandler.onColor((ev) => stack.add(ev));
        // single foreground query --> color undefined
        await inputHandler.parseP('\x1b]10;?\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.report,
              'index': SpecialColorIndex.foreground,
            },
          ],
        ]);
        stack.clear();
        // OSC with multiple values maps to OSC 10 & OSC 11 & OSC 12
        await inputHandler.parseP('\x1b]10;?;?;?;?\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.report,
              'index': SpecialColorIndex.foreground,
            },
          ],
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.report,
              'index': SpecialColorIndex.background,
            },
          ],
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.report,
              'index': SpecialColorIndex.cursor,
            },
          ],
        ]);
        stack.clear();
        // set foreground color events
        await inputHandler.parseP('\x1b]10;rgb:01/02/03\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.set,
              'index': SpecialColorIndex.foreground,
              'color': <int>[1, 2, 3],
            },
          ],
        ]);
        stack.clear();
        await inputHandler.parseP('\x1b]10;#aabbcc\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.set,
              'index': SpecialColorIndex.foreground,
              'color': <int>[170, 187, 204],
            },
          ],
        ]);
        stack.clear();
        // set FG, BG and cursor color at once
        await inputHandler.parseP(
          '\x1b]10;rgb:aa/bb/cc;#001122;rgb:12/34/56\x07',
        );
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.set,
              'index': SpecialColorIndex.foreground,
              'color': <int>[170, 187, 204],
            },
          ],
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.set,
              'index': SpecialColorIndex.background,
              'color': <int>[0, 17, 34],
            },
          ],
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.set,
              'index': SpecialColorIndex.cursor,
              'color': <int>[18, 52, 86],
            },
          ],
        ]);
      });
      test('110: restore FG color', () async {
        final stack = <IColorEvent>[];
        inputHandler.onColor((ev) => stack.add(ev));
        await inputHandler.parseP('\x1b]110\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.restore,
              'index': SpecialColorIndex.foreground,
            },
          ],
        ]);
      });
      test('11: BG set & query events', () async {
        final stack = <IColorEvent>[];
        inputHandler.onColor((ev) => stack.add(ev));
        // single background query --> color undefined
        await inputHandler.parseP('\x1b]11;?\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.report,
              'index': SpecialColorIndex.background,
            },
          ],
        ]);
        stack.clear();
        // OSC 11 with multiple values creates only BG and cursor event
        await inputHandler.parseP('\x1b]11;?;?;?;?\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.report,
              'index': SpecialColorIndex.background,
            },
          ],
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.report,
              'index': SpecialColorIndex.cursor,
            },
          ],
        ]);
        stack.clear();
        // set background color events
        await inputHandler.parseP('\x1b]11;rgb:01/02/03\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.set,
              'index': SpecialColorIndex.background,
              'color': <int>[1, 2, 3],
            },
          ],
        ]);
        stack.clear();
        await inputHandler.parseP('\x1b]11;#aabbcc\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.set,
              'index': SpecialColorIndex.background,
              'color': <int>[170, 187, 204],
            },
          ],
        ]);
        stack.clear();
        // set BG and cursor color at once
        await inputHandler.parseP('\x1b]11;#001122;rgb:12/34/56\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.set,
              'index': SpecialColorIndex.background,
              'color': <int>[0, 17, 34],
            },
          ],
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.set,
              'index': SpecialColorIndex.cursor,
              'color': <int>[18, 52, 86],
            },
          ],
        ]);
      });
      test('111: restore BG color', () async {
        final stack = <IColorEvent>[];
        inputHandler.onColor((ev) => stack.add(ev));
        await inputHandler.parseP('\x1b]111\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.restore,
              'index': SpecialColorIndex.background,
            },
          ],
        ]);
      });
      test('12: cursor color set & query events', () async {
        final stack = <IColorEvent>[];
        inputHandler.onColor((ev) => stack.add(ev));
        // single cursor query --> color undefined
        await inputHandler.parseP('\x1b]12;?\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.report,
              'index': SpecialColorIndex.cursor,
            },
          ],
        ]);
        stack.clear();
        // OSC 12 with multiple values creates only cursor event
        await inputHandler.parseP('\x1b]12;?;?;?;?\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.report,
              'index': SpecialColorIndex.cursor,
            },
          ],
        ]);
        stack.clear();
        // set cursor color events
        await inputHandler.parseP('\x1b]12;rgb:01/02/03\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.set,
              'index': SpecialColorIndex.cursor,
              'color': <int>[1, 2, 3],
            },
          ],
        ]);
        stack.clear();
        await inputHandler.parseP('\x1b]12;#aabbcc\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.set,
              'index': SpecialColorIndex.cursor,
              'color': <int>[170, 187, 204],
            },
          ],
        ]);
      });
      test('112: restore cursor color', () async {
        final stack = <IColorEvent>[];
        inputHandler.onColor((ev) => stack.add(ev));
        await inputHandler.parseP('\x1b]112\x07');
        expect(_colorEvents(stack), <Object>[
          <Object>[
            <String, Object?>{
              'type': ColorRequestType.restore,
              'index': SpecialColorIndex.cursor,
            },
          ],
        ]);
      });
    });

    // issue #3362 and #2979
    group('EL/ED cursor at buffer.cols', () {
      setUp(() {
        bufferService.resize(10, 5);
      });
      group('cursor should stay at cols / does not overflow', () {
        test('EL0', () async {
          await inputHandler.parseP('##########\x1b[0K');
          expect(bufferService.buffer.x, 10);
          expect(getLines(bufferService), <String>['#' * 10, '', '', '', '']);
        });
        test('EL1', () async {
          await inputHandler.parseP('##########\x1b[1K');
          expect(bufferService.buffer.x, 10);
          expect(getLines(bufferService), <String>['', '', '', '', '']);
        });
        test('EL2', () async {
          await inputHandler.parseP('##########\x1b[2K');
          expect(bufferService.buffer.x, 10);
          expect(getLines(bufferService), <String>['', '', '', '', '']);
        });
        test('ED0', () async {
          await inputHandler.parseP('##########\x1b[0J');
          expect(bufferService.buffer.x, 10);
          expect(getLines(bufferService), <String>['#' * 10, '', '', '', '']);
        });
        test('ED1', () async {
          await inputHandler.parseP('##########\x1b[1J');
          expect(bufferService.buffer.x, 10);
          expect(getLines(bufferService), <String>['', '', '', '', '']);
        });
        test('ED2', () async {
          await inputHandler.parseP('##########\x1b[2J');
          expect(bufferService.buffer.x, 10);
          expect(getLines(bufferService), <String>['', '', '', '', '']);
        });
        test('ED3', () async {
          await inputHandler.parseP('##########\x1b[3J');
          expect(bufferService.buffer.x, 10);
          expect(getLines(bufferService), <String>['#' * 10, '', '', '', '']);
        });
      });
      group('following sequence keeps working', () {
        // sequences to test (cursor related ones)
        const seqs = <String>[
          /* ICH */ '\x1b[10@',
          /* SL */ '\x1b[10 @',
          /* CUU */ '\x1b[10A',
          /* SR */ '\x1b[10 A',
          /* CUD */ '\x1b[10B',
          /* CUF */ '\x1b[10C',
          /* CUB */ '\x1b[10D',
          /* CNL */ '\x1b[10E',
          /* CPL */ '\x1b[10F',
          /* CHA */ '\x1b[10G',
          /* CUP */ '\x1b[10;10H',
          /* CHT */ '\x1b[10I',
          /* IL */ '\x1b[10L',
          /* DL */ '\x1b[10M',
          /* DCH */ '\x1b[10P',
          /* SU */ '\x1b[10S',
          /* SD */ '\x1b[10T',
          /* ECH */ '\x1b[10X',
          /* CBT */ '\x1b[10Z',
          /* HPA */ '\x1b[10`',
          /* HPR */ '\x1b[10a',
          /* REP */ '\x1b[10b',
          /* VPA */ '\x1b[10d',
          /* VPR */ '\x1b[10e',
          /* HVP */ '\x1b[10;10f',
          /* TBC */ '\x1b[0g',
          /* SCOSC */ '\x1b[s',
          /* DECIC */ "\x1b[10'}",
          /* DECDC */ "\x1b[10'~",
        ];
        test('cursor never advances beyond cols', () async {
          for (final seq in seqs) {
            await inputHandler.parseP('##########\x1b[2J$seq');
            expect(bufferService.buffer.x <= bufferService.cols, true);
            inputHandler.reset();
            bufferService.reset();
          }
        });
      });
    });

    group('ED3 - erase saved lines', () {
      setUp(() {
        bufferService.resize(10, 5);
      });
      test('should stop locking the viewport when the scrollback the user scrolled into is erased', () async {
        for (var i = 0; i < 20; ++i) {
          await inputHandler.parseP('old $i\r\n');
        }
        bufferService.scrollLines(-5);
        expect(bufferService.isUserScrolling, true);

        await inputHandler.parseP('\x1b[3J');

        expect(bufferService.isUserScrolling, false);
        expect(bufferService.buffer.ybase, 0);
        expect(bufferService.buffer.ydisp, 0);

        for (var i = 0; i < 20; ++i) {
          await inputHandler.parseP('new $i\r\n');
        }

        expect(bufferService.buffer.ydisp, bufferService.buffer.ybase);
      });
      test('should not reset the scroll position when erasing scrollback on a resized alt buffer', () async {
        bufferService.resize(10, 50);
        bufferService.resize(10, 5);
        for (var i = 0; i < 20; ++i) {
          await inputHandler.parseP('old $i\r\n');
        }
        bufferService.scrollLines(-5);
        final ydisp = bufferService.buffer.ydisp;

        await inputHandler.parseP('\x1b[?1049h');
        for (var i = 0; i < 20; ++i) {
          await inputHandler.parseP('new $i\r\n');
        }
        await inputHandler.parseP('\x1b[3J\x1b[?1049l');

        expect(bufferService.isUserScrolling, true);
        expect(bufferService.buffer.ydisp, ydisp);

        await inputHandler.parseP('more\r\n');

        expect(bufferService.isUserScrolling, true);
        expect(bufferService.buffer.ydisp, ydisp);
      });
    });

    group('DECSCA and DECSED/DECSEL', () {
      test('default is unprotected', () async {
        await inputHandler.parseP('some text');
        await inputHandler.parseP('\x1b[?2K');
        expect(getLines(bufferService, 2), <String>['', '']);
        await inputHandler.parseP('some text');
        await inputHandler.parseP('\x1b[?2J');
        expect(getLines(bufferService, 2), <String>['', '']);
      });
      test('DECSCA 1 with DECSEL', () async {
        await inputHandler.parseP('###\x1b[1"qlineerase\x1b[0"q***');
        await inputHandler.parseP('\x1b[?2K');
        expect(getLines(bufferService, 2), <String>['   lineerase', '']);
        // normal EL works as before
        await inputHandler.parseP('\x1b[2K');
        expect(getLines(bufferService, 2), <String>['', '']);
      });
      test('DECSCA 1 with DECSED', () async {
        await inputHandler.parseP('###\x1b[1"qdisplayerase\x1b[0"q***');
        await inputHandler.parseP('\x1b[?2J');
        expect(getLines(bufferService, 2), <String>['   displayerase', '']);
        // normal ED works as before
        await inputHandler.parseP('\x1b[2J');
        expect(getLines(bufferService, 2), <String>['', '']);
      });
      test('DECRQSS reports correct DECSCA state', () async {
        final sendStack = <String>[];
        coreService.onData((d) => sendStack.add(d));
        // DCS $ q " q ST
        await inputHandler.parseP('\x1bP\$q"q\x1b\\');
        // default - DECSCA unset (0 or 2)
        expect(sendStack.removeLast(), '\x1bP1\$r0"q\x1b\\');
        // DECSCA 1 - protected set
        await inputHandler.parseP('###\x1b[1"q');
        await inputHandler.parseP('\x1bP\$q"q\x1b\\');
        expect(sendStack.removeLast(), '\x1bP1\$r1"q\x1b\\');
        // DECSCA 2 - protected reset (same as 0)
        await inputHandler.parseP('###\x1b[2"q');
        await inputHandler.parseP('\x1bP\$q"q\x1b\\');
        expect(
          sendStack.removeLast(),
          '\x1bP1\$r0"q\x1b\\',
        ); // reported as DECSCA 0
      });
    });
    group('DECRQM', () {
      final reportStack = <String>[];
      setUp(() {
        reportStack.clear();
        coreService.onData((data) => reportStack.add(data));
      });
      test('ANSI 2 (keyboard action mode)', () async {
        await inputHandler.parseP('\x1b[2\$p');
        expect(reportStack.removeLast(), '\x1b[2;4\$y'); // always reset
      });
      test('ANSI 4 (insert mode)', () async {
        await inputHandler.parseP('\x1b[4\$p');
        expect(reportStack.removeLast(), '\x1b[4;2\$y'); // reset by default
        await inputHandler.parseP('\x1b[4h');
        await inputHandler.parseP('\x1b[4\$p');
        expect(reportStack.removeLast(), '\x1b[4;1\$y'); // now active
        await inputHandler.parseP('\x1b[4l');
        await inputHandler.parseP('\x1b[4\$p');
        expect(reportStack.removeLast(), '\x1b[4;2\$y'); // again reset
      });
      test('ANSI 12 (send/receive)', () async {
        await inputHandler.parseP('\x1b[12\$p');
        expect(reportStack.removeLast(), '\x1b[12;3\$y'); // always set
      });
      test('ANSI 20 (newline mode)', () async {
        await inputHandler.parseP('\x1b[20\$p');
        expect(reportStack.removeLast(), '\x1b[20;2\$y'); // reset by default
        await inputHandler.parseP('\x1b[20h');
        await inputHandler.parseP('\x1b[20\$p');
        expect(reportStack.removeLast(), '\x1b[20;1\$y'); // now active
        await inputHandler.parseP('\x1b[20l');
        await inputHandler.parseP('\x1b[20\$p');
        expect(reportStack.removeLast(), '\x1b[20;2\$y'); // again reset
      });
      test('ANSI unknown', () async {
        await inputHandler.parseP('\x1b[1234\$p');
        expect(reportStack.removeLast(), '\x1b[1234;0\$y'); // not recognized
      });
      test('DEC privates with set/reset semantic', () async {
        // initially reset
        const reset = <int>[
          1,
          6,
          9,
          45,
          66,
          1000,
          1002,
          1003,
          1004,
          1006,
          1016,
          47,
          1047,
          1049,
          2004,
          2026,
        ];
        for (final mode in reset) {
          await inputHandler.parseP('\x1b[?$mode\$p');
          expect(reportStack.removeLast(), '\x1b[?$mode;2\$y'); // initial reset
          await inputHandler.parseP('\x1b[?${mode}h');
          await inputHandler.parseP('\x1b[?$mode\$p');
          expect(reportStack.removeLast(), '\x1b[?$mode;1\$y'); // now active
          await inputHandler.parseP('\x1b[?${mode}l');
          await inputHandler.parseP('\x1b[?$mode\$p');
          expect(reportStack.removeLast(), '\x1b[?$mode;2\$y'); // again reset
        }
        // initially set
        const set = <int>[7, 25];
        for (final mode in set) {
          await inputHandler.parseP('\x1b[?$mode\$p');
          expect(reportStack.removeLast(), '\x1b[?$mode;1\$y'); // initial set
          await inputHandler.parseP('\x1b[?${mode}l');
          await inputHandler.parseP('\x1b[?$mode\$p');
          expect(reportStack.removeLast(), '\x1b[?$mode;2\$y'); // now inactive
          await inputHandler.parseP('\x1b[?${mode}h');
          await inputHandler.parseP('\x1b[?$mode\$p');
          expect(reportStack.removeLast(), '\x1b[?$mode;1\$y'); // again set
        }
      });
      test('DEC privates quirks', () async {
        // Cursor blink
        const mode = 12;
        await inputHandler.parseP('\x1b[?$mode\$p');
        expect(reportStack.removeLast(), '\x1b[?$mode;2\$y'); // initial reset
        await inputHandler.parseP('\x1b[?${mode}h');
        await inputHandler.parseP('\x1b[?$mode\$p');
        expect(reportStack.removeLast(), '\x1b[?$mode;2\$y'); // still reset

        optionsService.options.quirks.allowSetCursorBlink = true;
        await inputHandler.parseP('\x1b[?${mode}h');
        await inputHandler.parseP('\x1b[?$mode\$p');
        expect(reportStack.removeLast(), '\x1b[?$mode;1\$y'); // now active
        await inputHandler.parseP('\x1b[?${mode}l');
        await inputHandler.parseP('\x1b[?$mode\$p');
        expect(reportStack.removeLast(), '\x1b[?$mode;2\$y'); // now inactive
      });
      test('DEC privates perma modes', () async {
        // [mode number, state value]
        const perma = <List<int>>[
          <int>[3, 0],
          <int>[8, 3],
          <int>[67, 4],
          <int>[1005, 4],
          <int>[1015, 4],
          <int>[1048, 1],
        ];
        for (final [mode, value] in perma) {
          await inputHandler.parseP('\x1b[?$mode\$p');
          expect(reportStack.removeLast(), '\x1b[?$mode;$value\$y');
        }
      });
    });

    group('InputHandler - kitty keyboard', () {
      late IBufferService bufferService;
      late ICoreService coreService;
      late MockOptionsService optionsService;
      late TestInputHandler inputHandler;

      setUp(() {
        optionsService = MockOptionsService(
          ITerminalOptions(vtExtensions: IVtExtensions(kittyKeyboard: true)),
        );
        bufferService = BufferService(optionsService, MockLogService());
        bufferService.resize(80, 30);
        coreService = CoreService(
          bufferService,
          MockLogService(),
          optionsService,
        );
        inputHandler = TestInputHandler(
          bufferService,
          MockCharsetService(),
          coreService,
          MockLogService(),
          optionsService,
          MockOscLinkService(),
          MockMouseStateService(),
          MockUnicodeService(),
        );
      });

      group('stack limit', () {
        test(
          'should evict oldest entry when stack exceeds 16 entries',
          () async {
            for (var i = 1; i <= 20; i++) {
              await inputHandler.parseP('\x1b[>${i}u');
            }
            expect(coreService.kittyKeyboard.mainStack.length, 16);
            expect(coreService.kittyKeyboard.mainStack[0], 4);
          },
        );
      });

      group('buffer switch', () {
        test(
          'should maintain separate flags for main and alt screens',
          () async {
            await inputHandler.parseP('\x1b[>5u');
            expect(coreService.kittyKeyboard.flags, 5);
            await inputHandler.parseP('\x1b[?1049h');
            expect(coreService.kittyKeyboard.flags, 0);
            expect(coreService.kittyKeyboard.mainFlags, 5);
            await inputHandler.parseP('\x1b[>7u');
            expect(coreService.kittyKeyboard.flags, 7);
            await inputHandler.parseP('\x1b[?1049l');
            expect(coreService.kittyKeyboard.flags, 5);
            expect(coreService.kittyKeyboard.altFlags, 7);
          },
        );
      });

      group('pop reset', () {
        test('should reset flags to 0 when stack is emptied', () async {
          await inputHandler.parseP('\x1b[>5u');
          expect(coreService.kittyKeyboard.flags, 5);
          await inputHandler.parseP('\x1b[<10u');
          expect(coreService.kittyKeyboard.flags, 0);
        });
      });
    });

    group('InputHandler - async handlers', () {
      late IBufferService bufferService;
      late ICoreService coreService;
      late MockOptionsService optionsService;
      late TestInputHandler inputHandler;

      setUp(() {
        optionsService = MockOptionsService();
        bufferService = BufferService(optionsService, MockLogService());
        bufferService.resize(80, 30);
        coreService = CoreService(
          bufferService,
          MockLogService(),
          optionsService,
        );
        // Upstream logs the replies to the console.
        coreService.onData((data) {});

        inputHandler = TestInputHandler(
          bufferService,
          MockCharsetService(),
          coreService,
          MockLogService(),
          optionsService,
          MockOscLinkService(),
          MockMouseStateService(),
          MockUnicodeService(),
        );
      });

      test('async CUP with CPR check', () async {
        final cup = <List<Object>>[];
        final cpr = <List<int>>[];
        inputHandler.registerCsiHandler(IFunctionIdentifier(final_: 'H'), (
          params,
        ) async {
          cup.add(params.toArray());
          await Future<void>.value();
          // late call of real repositioning
          return inputHandler.cursorPosition(params);
        });
        coreService.onData((data) {
          final m = RegExp(r'\x1b\[(.*?);(.*?)R').firstMatch(data);
          if (m != null) {
            cpr.add(<int>[int.parse(m[1]!), int.parse(m[2]!)]);
          }
        });
        await inputHandler.parseP('aaa\x1b[3;4H\x1b[6nbbb\x1b[6;8H\x1b[6n');
        expect(cup, cpr);
      });
      test('async OSC between', () async {
        inputHandler.registerOscHandler(1000, (data) async {
          await Future<void>.value();
          expect(getLines(bufferService, 2), <String>['hello world!', '']);
          expect(data, 'some data');
          return true;
        });
        await inputHandler.parseP(
          'hello world!\r\n\x1b]1000;some data\x07second line',
        );
        expect(getLines(bufferService, 2), <String>[
          'hello world!',
          'second line',
        ]);
      });
      test('async DCS between', () async {
        inputHandler.registerDcsHandler(IFunctionIdentifier(final_: 'a'), (
          data,
          params,
        ) async {
          await Future<void>.value();
          expect(getLines(bufferService, 2), <String>['hello world!', '']);
          expect(data, 'some data');
          expect(params.toArray(), <Object>[1, 2]);
          return true;
        });
        await inputHandler.parseP(
          'hello world!\r\n\x1bP1;2asome data\x1b\\second line',
        );
        expect(getLines(bufferService, 2), <String>[
          'hello world!',
          'second line',
        ]);
      });
    });
  });
}
