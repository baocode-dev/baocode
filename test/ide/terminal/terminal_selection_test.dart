// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/browser/services/SelectionService.test.ts
// (c58ea36), with mouse-driven cases added.

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/terminal_mouse.dart';
import 'package:baocode/ide/terminal/terminal_selection.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/buffer_line.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/cell_data.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/types.dart';
import 'package:baocode/ide/terminal/xterm/common/event.dart';

import 'xterm/common/test_utils.dart';

class _DataCoreService extends MockCoreService {
  final List<String> data = [];

  @override
  void triggerDataEvent(String data, [bool? wasUserInput]) {
    this.data.add(data);
  }
}

IBufferLine stringToRow(String text) {
  final result = BufferLine(text.length);
  for (var i = 0; i < text.length; i++) {
    result.setCell(i, createCellData(0, text[i], 1));
  }
  return result;
}

IBufferLine stringArrayToRow(List<String> chars) {
  final line = BufferLine(chars.length);
  for (var i = 0; i < chars.length; i++) {
    line.setCell(i, createCellData(0, chars[i], 1));
  }
  return line;
}

IBufferLine charDataToRow(List<CharData> data) {
  final line = BufferLine(data.length);
  for (var i = 0; i < data.length; i++) {
    line.setCell(i, CellData.fromCharData(data[i]));
  }
  return line;
}

void main() {
  late IBuffer buffer;
  late MockBufferService bufferService;
  late MockOptionsService optionsService;
  late MockMouseStateService mouseStateService;
  late _DataCoreService coreService;
  late TerminalSelection selectionService;

  TerminalSelection create([TargetPlatform platform = TargetPlatform.linux]) =>
      TerminalSelection(
        bufferService: bufferService,
        coreService: coreService,
        optionsService: optionsService,
        mouseStateService: mouseStateService,
        platform: platform,
      );

  setUp(() {
    optionsService = MockOptionsService();
    mouseStateService = MockMouseStateService();
    bufferService = MockBufferService(20, 20, optionsService);
    buffer = bufferService.buffer;
    coreService = _DataCoreService();
    selectionService = create();
  });

  tearDown(() => selectionService.dispose());

  group('_selectWordAt', () {
    test('should expand selection for normal width chars', () {
      buffer.lines.set(0, stringToRow('foo bar'));
      selectionService.selectWordAt([0, 0]);
      expect(selectionService.selectionText, 'foo');
      selectionService.selectWordAt([1, 0]);
      expect(selectionService.selectionText, 'foo');
      selectionService.selectWordAt([2, 0]);
      expect(selectionService.selectionText, 'foo');
      selectionService.selectWordAt([3, 0]);
      expect(selectionService.selectionText, ' ');
      selectionService.selectWordAt([4, 0]);
      expect(selectionService.selectionText, 'bar');
      selectionService.selectWordAt([5, 0]);
      expect(selectionService.selectionText, 'bar');
      selectionService.selectWordAt([6, 0]);
      expect(selectionService.selectionText, 'bar');
    });

    test('should expand selection for whitespace', () {
      buffer.lines.set(0, stringToRow('a   b'));
      selectionService.selectWordAt([0, 0]);
      expect(selectionService.selectionText, 'a');
      selectionService.selectWordAt([1, 0]);
      expect(selectionService.selectionText, '   ');
      selectionService.selectWordAt([2, 0]);
      expect(selectionService.selectionText, '   ');
      selectionService.selectWordAt([3, 0]);
      expect(selectionService.selectionText, '   ');
      selectionService.selectWordAt([4, 0]);
      expect(selectionService.selectionText, 'b');
    });

    test('should expand selection for wide characters', () {
      // Wide characters use a special format
      buffer.lines.set(
        0,
        charDataToRow([
          (0, '中', 2, '中'.codeUnitAt(0)),
          (0, '', 0, 0),
          (0, '文', 2, '文'.codeUnitAt(0)),
          (0, '', 0, 0),
          (0, ' ', 1, ' '.codeUnitAt(0)),
          (0, 'a', 1, 'a'.codeUnitAt(0)),
          (0, '中', 2, '中'.codeUnitAt(0)),
          (0, '', 0, 0),
          (0, '文', 2, '文'.codeUnitAt(0)),
          (0, '', 0, 0),
          (0, 'b', 1, 'b'.codeUnitAt(0)),
          (0, ' ', 1, ' '.codeUnitAt(0)),
          (0, 'f', 1, 'f'.codeUnitAt(0)),
          (0, 'o', 1, 'o'.codeUnitAt(0)),
          (0, 'o', 1, 'o'.codeUnitAt(0)),
        ]),
      );
      // Ensure wide characters take up 2 columns
      for (final x in [0, 1, 2, 3]) {
        selectionService.selectWordAt([x, 0]);
        expect(selectionService.selectionText, '中文', reason: 'x = $x');
      }
      selectionService.selectWordAt([4, 0]);
      expect(selectionService.selectionText, ' ');
      // Ensure wide characters work when wrapped in normal width characters
      for (final x in [5, 6, 7, 8, 9, 10]) {
        selectionService.selectWordAt([x, 0]);
        expect(selectionService.selectionText, 'a中文b', reason: 'x = $x');
      }
      selectionService.selectWordAt([11, 0]);
      expect(selectionService.selectionText, ' ');
      // Ensure normal width characters work fine in a line containing wide
      // characters
      for (final x in [12, 13, 14]) {
        selectionService.selectWordAt([x, 0]);
        expect(selectionService.selectionText, 'foo', reason: 'x = $x');
      }
    });

    test('should select up to non-path characters that are commonly adjacent '
        'to paths', () {
      buffer.lines.set(0, stringToRow('(cd)[ef]{gh}\'ij"'));
      const expected = [
        '(cd', 'cd', 'cd', 'cd)', //
        '[ef', 'ef', 'ef', 'ef]',
        '{gh', 'gh', 'gh', 'gh}',
        '\'ij', 'ij', 'ij', 'ij"',
      ];
      for (var x = 0; x < expected.length; x++) {
        selectionService.selectWordAt([x, 0]);
        expect(selectionService.selectionText, expected[x], reason: 'x = $x');
      }
    });

    test('should expand upwards or downards for wrapped lines', () {
      buffer.lines.set(0, stringToRow('                 foo'));
      buffer.lines.set(1, stringToRow('bar                 '));
      buffer.lines.get(1)!.isWrapped = true;
      selectionService.selectWordAt([1, 1]);
      expect(selectionService.selectionText, 'foobar');
      selectionService.model.clearSelection();
      selectionService.selectWordAt([18, 0]);
      expect(selectionService.selectionText, 'foobar');
    });

    test('should expand both upwards and downwards for word wrapped over many '
        'lines', () {
      const expectedText =
          'fooaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbccccccccccccccccccccbar';
      buffer.lines.set(0, stringToRow('                 foo'));
      buffer.lines.set(1, stringToRow('aaaaaaaaaaaaaaaaaaaa'));
      buffer.lines.set(2, stringToRow('bbbbbbbbbbbbbbbbbbbb'));
      buffer.lines.set(3, stringToRow('cccccccccccccccccccc'));
      buffer.lines.set(4, stringToRow('bar                 '));
      for (final y in [1, 2, 3, 4]) {
        buffer.lines.get(y)!.isWrapped = true;
      }
      for (final coords in [
        [18, 0],
        [10, 1],
        [10, 2],
        [10, 3],
        [1, 4],
      ]) {
        selectionService.model.clearSelection();
        selectionService.selectWordAt(coords);
        expect(selectionService.selectionText, expectedText);
      }
    });

    group('emoji', () {
      test('should treat a single emoji as a word when wrapped in spaces', () {
        // The a is here to prevent the space being trimmed in selectionText
        buffer.lines.set(0, stringToRow(' ⚽ a'));
        selectionService.selectWordAt([0, 0]);
        expect(selectionService.selectionText, ' ');
        selectionService.selectWordAt([1, 0]);
        expect(selectionService.selectionText, '⚽');
        selectionService.selectWordAt([2, 0]);
        expect(selectionService.selectionText, ' ');
      });

      test('should treat multiple emojis as a word when wrapped in spaces', () {
        buffer.lines.set(0, stringToRow(' ⚽⚽ a'));
        selectionService.selectWordAt([0, 0]);
        expect(selectionService.selectionText, ' ');
        selectionService.selectWordAt([1, 0]);
        expect(selectionService.selectionText, '⚽⚽');
        selectionService.selectWordAt([2, 0]);
        expect(selectionService.selectionText, '⚽⚽');
        selectionService.selectWordAt([3, 0]);
        expect(selectionService.selectionText, ' ');
      });

      test('should treat emojis using the zero-width-joiner as a single '
          'word', () {
        // Note that the first 3 emojis include the invisible ZWJ char
        buffer.lines.set(
          0,
          stringArrayToRow([' ', '👨‍', '👩‍', '👧‍', '👦', ' ', 'a']),
        );
        selectionService.selectWordAt([0, 0]);
        expect(selectionService.selectionText, ' ');
        // ZWJ emojis do not combine in the terminal so the family emoji used
        // here consumed 4 cells. The selection text should retain ZWJ chars
        // despite not combining on the terminal
        for (final x in [1, 2, 3, 4]) {
          selectionService.selectWordAt([x, 0]);
          expect(
            selectionService.selectionText,
            '👨‍👩‍👧‍👦',
            reason: 'x = $x',
          );
        }
        selectionService.selectWordAt([5, 0]);
        expect(selectionService.selectionText, ' ');
      });

      test('should treat emojis and characters joined together as a word', () {
        buffer.lines.set(0, stringToRow(' ⚽ab cd⚽ ef⚽gh'));
        const expected = [
          ' ', '⚽ab', '⚽ab', '⚽ab', ' ', //
          'cd⚽', 'cd⚽', 'cd⚽', ' ',
          'ef⚽gh', 'ef⚽gh', 'ef⚽gh', 'ef⚽gh', 'ef⚽gh',
        ];
        for (var x = 0; x < expected.length; x++) {
          selectionService.selectWordAt([x, 0]);
          expect(selectionService.selectionText, expected[x], reason: 'x=$x');
        }
      });

      test('should treat complex emojis and characters joined together as a '
          'word', () {
        // This emoji is the flag for England and is made up of: 1F3F4 E0067
        // E0062 E0065 E006E E0067 E007F
        const flag =
            '\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}';
        buffer.lines.set(
          0,
          stringArrayToRow([
            ' ', flag, 'a', 'b', ' ', 'c', 'd', flag, //
            ' ', 'e', 'f', flag, 'g', 'h', ' ', 'a',
          ]),
        );
        const expected = [
          ' ', '${flag}ab', '${flag}ab', '${flag}ab', ' ', //
          'cd$flag', 'cd$flag', 'cd$flag', ' ',
          'ef${flag}gh', 'ef${flag}gh', 'ef${flag}gh', 'ef${flag}gh',
          'ef${flag}gh',
        ];
        for (var x = 0; x < expected.length; x++) {
          selectionService.selectWordAt([x, 0]);
          expect(selectionService.selectionText, expected[x], reason: 'x=$x');
        }
      });
    });
  });

  group('_selectLineAt', () {
    test('should select the entire line', () {
      buffer.lines.set(0, stringToRow('foo bar'));
      selectionService.selectLineAt(0);
      expect(
        selectionService.selectionText,
        'foo bar',
        reason: 'The selected text is correct',
      );
      expect(selectionService.model.selectionStart, [0, 0]);
      expect(selectionService.model.selectionEnd, isNull);
      expect(selectionService.model.selectionStartLength, 20);
      expect(selectionService.model.finalSelectionStart, [0, 0]);
      expect(selectionService.model.finalSelectionEnd, [
        bufferService.cols,
        0,
      ], reason: 'The actual selection spans the entire column');
    });

    test('should select the entire wrapped line', () {
      buffer.lines.set(0, stringToRow('foo'));
      final line2 = stringToRow('bar');
      line2.isWrapped = true;
      buffer.lines.set(1, line2);
      selectionService.selectLineAt(0);
      expect(
        selectionService.selectionText,
        'foobar',
        reason: 'The selected text is correct',
      );
      expect(selectionService.model.selectionStart, [0, 0]);
      expect(selectionService.model.selectionEnd, isNull);
      expect(selectionService.model.selectionStartLength, 40);
      expect(selectionService.model.finalSelectionStart, [0, 0]);
      expect(selectionService.model.finalSelectionEnd, [
        bufferService.cols,
        1,
      ], reason: 'The actual selection spans the entire column');
    });
  });

  group('selectAll', () {
    test('should select the entire buffer, beyond the viewport', () {
      bufferService.resize(20, 5);
      for (var i = 0; i < 5; i++) {
        buffer.lines.set(i, stringToRow('${i + 1}'));
      }
      selectionService.selectAll();
      expect(selectionService.selectionText, '1\n2\n3\n4\n5');
    });
  });

  group('selectLines', () {
    test('should select a single line', () {
      buffer.lines.length = 3;
      for (var i = 0; i < 3; i++) {
        buffer.lines.set(i, stringToRow('${i + 1}'));
      }
      selectionService.selectLines(1, 1);
      expect(selectionService.model.finalSelectionStart, [0, 1]);
      expect(selectionService.model.finalSelectionEnd, [bufferService.cols, 1]);
    });

    test('should select multiple lines', () {
      buffer.lines.length = 5;
      for (var i = 0; i < 5; i++) {
        buffer.lines.set(i, stringToRow('${i + 1}'));
      }
      selectionService.selectLines(1, 3);
      expect(selectionService.model.finalSelectionStart, [0, 1]);
      expect(selectionService.model.finalSelectionEnd, [bufferService.cols, 3]);
    });

    test('should select the to the start when requesting a negative row', () {
      buffer.lines.length = 2;
      buffer.lines.set(0, stringToRow('1'));
      buffer.lines.set(1, stringToRow('2'));
      selectionService.selectLines(-1, 0);
      expect(selectionService.model.finalSelectionStart, [0, 0]);
      expect(selectionService.model.finalSelectionEnd, [bufferService.cols, 0]);
    });

    test('should select the to the end when requesting beyond the final '
        'row', () {
      buffer.lines.length = 2;
      buffer.lines.set(0, stringToRow('1'));
      buffer.lines.set(1, stringToRow('2'));
      selectionService.selectLines(1, 2);
      expect(selectionService.model.finalSelectionStart, [0, 1]);
      expect(selectionService.model.finalSelectionEnd, [bufferService.cols, 1]);
    });
  });

  group('hasSelection', () {
    test('should return whether there is a selection', () {
      selectionService.model.selectionStart = [0, 0];
      selectionService.model.selectionStartLength = 0;
      expect(selectionService.hasSelection, isFalse);
      selectionService.model.selectionEnd = [0, 0];
      expect(selectionService.hasSelection, isFalse);
      selectionService.model.selectionEnd = [1, 0];
      expect(selectionService.hasSelection, isTrue);
      selectionService.model.selectionEnd = [0, 1];
      expect(selectionService.hasSelection, isTrue);
      selectionService.model.selectionEnd = [1, 1];
      expect(selectionService.hasSelection, isTrue);
    });
  });

  group('column selection', () {
    test('should select a column of text', () {
      buffer.lines.length = 3;
      buffer.lines.set(0, stringToRow('abcdefghij'));
      buffer.lines.set(1, stringToRow('klmnopqrst'));
      buffer.lines.set(2, stringToRow('uvwxyz'));

      selectionService.selectionMode = SelectionMode.column;
      selectionService.model.selectionStart = [2, 0];
      selectionService.model.selectionEnd = [4, 2];

      expect(selectionService.selectionText, 'cd\nmn\nwx');
    });

    test('should select a column of text without chopping up double width '
        'characters', () {
      buffer.lines.length = 3;
      buffer.lines.set(0, stringToRow('a'));
      buffer.lines.set(1, stringToRow('語'));
      buffer.lines.set(2, stringToRow('b'));

      selectionService.selectionMode = SelectionMode.column;
      selectionService.model.selectionStart = [0, 0];
      selectionService.model.selectionEnd = [1, 2];

      expect(selectionService.selectionText, 'a\n語\nb');
    });

    test('should select a column of text with single character emojis', () {
      buffer.lines.length = 3;
      buffer.lines.set(0, stringToRow('a'));
      buffer.lines.set(1, stringToRow('☃'));
      buffer.lines.set(2, stringToRow('c'));

      selectionService.selectionMode = SelectionMode.column;
      selectionService.model.selectionStart = [0, 0];
      selectionService.model.selectionEnd = [1, 2];

      expect(selectionService.selectionText, 'a\n☃\nc');
    });

    test('should select a column of text with double character emojis', () {
      buffer.lines.length = 3;
      buffer.lines.set(0, stringToRow('a '));
      buffer.lines.set(1, stringArrayToRow(['😁', ' ']));
      buffer.lines.set(2, stringToRow('c '));

      selectionService.selectionMode = SelectionMode.column;
      selectionService.model.selectionStart = [0, 0];
      selectionService.model.selectionEnd = [1, 2];

      expect(selectionService.selectionText, 'a\n😁\nc');
    });
  });

  group('_areCoordsInSelection', () {
    test('should return whether coords are in the selection', () {
      bool inSelection(List<int> coords) =>
          selectionService.areCoordsInSelection(coords, [2, 0], [2, 1]);
      expect(inSelection([0, 0]), isFalse);
      expect(inSelection([1, 0]), isFalse);
      expect(inSelection([2, 0]), isTrue);
      expect(inSelection([10, 0]), isTrue);
      expect(inSelection([0, 1]), isTrue);
      expect(inSelection([1, 1]), isTrue);
      expect(inSelection([2, 1]), isFalse);
    });
  });

  group('shouldForceSelection', () {
    TerminalMouseEvent ev({bool altKey = false}) => TerminalMouseEvent(
      type: TerminalMouseEventType.mouseDown,
      position: Offset.zero,
      altKey: altKey,
    );

    test('should force selection without alt when mouseEventsRequireAlt is '
        'enabled', () {
      optionsService.options.mouseEventsRequireAlt = true;
      mouseStateService.areMouseEventsActive = true;
      expect(selectionService.shouldForceSelection(ev()), isTrue);
      expect(selectionService.shouldForceSelection(ev(altKey: true)), isFalse);
    });

    test('should take precedence over macOptionClickForcesSelection', () {
      optionsService.options.mouseEventsRequireAlt = true;
      optionsService.options.macOptionClickForcesSelection = true;
      mouseStateService.areMouseEventsActive = true;
      expect(selectionService.shouldForceSelection(ev(altKey: true)), isFalse);
    });
  });

  group('mouse', () {
    const cell = Size(10, 20);
    var time = Duration.zero;

    setUp(() {
      selectionService.cellSize = cell;
      time = Duration.zero;
    });

    /// The center of cell ([col], [row]).
    Offset at(int col, int row) =>
        Offset((col + 0.5) * cell.width, (row + 0.5) * cell.height);

    /// The left edge of cell ([col], [row]): a selection ends at the cell
    /// edge nearest to the pointer.
    Offset edge(int col, int row) =>
        Offset(col * cell.width, (row + 0.5) * cell.height);

    TerminalMouseEvent ev(
      TerminalMouseEventType type,
      Offset position, {
      int detail = 1,
      bool altKey = false,
      bool shiftKey = false,
    }) {
      time += const Duration(milliseconds: 10);
      return TerminalMouseEvent(
        type: type,
        position: position,
        buttons: type == TerminalMouseEventType.mouseUp ? 0 : 1,
        detail: detail,
        altKey: altKey,
        shiftKey: shiftKey,
        timeStamp: time,
      );
    }

    void click(
      Offset position, {
      int detail = 1,
      bool altKey = false,
      bool shiftKey = false,
    }) {
      selectionService.handleMouseDown(
        ev(
          TerminalMouseEventType.mouseDown,
          position,
          detail: detail,
          altKey: altKey,
          shiftKey: shiftKey,
        ),
      );
      selectionService.handleMouseUp(
        ev(TerminalMouseEventType.mouseUp, position, altKey: altKey),
      );
    }

    void drag(Offset from, Offset to, {bool altKey = false}) {
      selectionService.handleMouseDown(
        ev(TerminalMouseEventType.mouseDown, from, altKey: altKey),
      );
      expect(
        selectionService.handleMouseMove(
          ev(TerminalMouseEventType.mouseMove, to, altKey: altKey),
        ),
        isTrue,
      );
      selectionService.handleMouseUp(
        ev(TerminalMouseEventType.mouseUp, to, altKey: altKey),
      );
    }

    test('drag selects from cell edge to cell edge', () {
      buffer.lines.set(0, stringToRow('foo bar'));
      var changes = 0;
      selectionService.onSelectionChange((_) => changes++);
      drag(at(0, 0), edge(3, 0));
      expect(selectionService.selectionText, 'foo');
      expect(selectionService.selectionStart, [0, 0]);
      expect(selectionService.selectionEnd, [3, 0]);
      expect(changes, 1);
      expect(selectionService.isSelecting, isFalse);
      // A move without a button down is not a selection.
      expect(
        selectionService.handleMouseMove(
          ev(TerminalMouseEventType.mouseMove, at(5, 0)),
        ),
        isFalse,
      );
    });

    test('a single click clears the selection', () {
      buffer.lines.set(0, stringToRow('foo bar'));
      drag(at(0, 0), edge(3, 0));
      expect(selectionService.hasSelection, isTrue);
      click(at(5, 0));
      expect(selectionService.hasSelection, isFalse);
    });

    test('double click selects a word, triple click the line', () {
      buffer.lines.set(0, stringToRow('foo bar baz'));
      click(at(5, 0), detail: 2);
      expect(selectionService.selectionText, 'bar');
      expect(selectionService.selectionMode, SelectionMode.word);
      click(at(5, 0), detail: 3);
      expect(selectionService.selectionText, 'foo bar baz');
      expect(selectionService.selectionMode, SelectionMode.line);
    });

    test('double click drag extends by words', () {
      buffer.lines.set(0, stringToRow('foo bar baz'));
      selectionService.handleMouseDown(
        ev(TerminalMouseEventType.mouseDown, at(1, 0), detail: 2),
      );
      selectionService.handleMouseMove(
        ev(TerminalMouseEventType.mouseMove, at(5, 0)),
      );
      selectionService.handleMouseUp(
        ev(TerminalMouseEventType.mouseUp, at(5, 0)),
      );
      expect(selectionService.selectionText, 'foo bar');
    });

    test('triple click drag extends by lines', () {
      buffer.lines.set(0, stringToRow('one'));
      buffer.lines.set(1, stringToRow('two'));
      buffer.lines.set(2, stringToRow('three'));
      selectionService.handleMouseDown(
        ev(TerminalMouseEventType.mouseDown, at(1, 0), detail: 3),
      );
      selectionService.handleMouseMove(
        ev(TerminalMouseEventType.mouseMove, at(0, 1)),
      );
      selectionService.handleMouseUp(
        ev(TerminalMouseEventType.mouseUp, at(0, 1)),
      );
      expect(selectionService.selectionText, 'one\ntwo');
    });

    test('double click selects wide characters whole', () {
      buffer.lines.set(
        0,
        charDataToRow([
          (0, 'a', 1, 'a'.codeUnitAt(0)),
          (0, '中', 2, '中'.codeUnitAt(0)),
          (0, '', 0, 0),
          (0, '文', 2, '文'.codeUnitAt(0)),
          (0, '', 0, 0),
          (0, ' ', 1, ' '.codeUnitAt(0)),
          (0, 'b', 1, 'b'.codeUnitAt(0)),
        ]),
      );
      // The second half of 中.
      click(at(2, 0), detail: 2);
      expect(selectionService.selectionText, 'a中文');
      expect(selectionService.selectionStart, [0, 0]);
      expect(selectionService.selectionEnd, [5, 0]);
    });

    test('drag onto a wide character covers it', () {
      buffer.lines.set(
        0,
        charDataToRow([
          (0, 'a', 1, 'a'.codeUnitAt(0)),
          (0, '中', 2, '中'.codeUnitAt(0)),
          (0, '', 0, 0),
          (0, 'b', 1, 'b'.codeUnitAt(0)),
        ]),
      );
      // To the left half of the second cell of 中.
      drag(at(0, 0), Offset(2.2 * cell.width, 10));
      expect(selectionService.selectionText, 'a中');
    });

    test('drag across a wrapped line joins it', () {
      buffer.lines.set(0, stringToRow('aaaaaaaaaaaaaaaaaaaa'));
      final wrapped = stringToRow('bbb');
      wrapped.isWrapped = true;
      buffer.lines.set(1, wrapped);
      buffer.lines.set(2, stringToRow('ccc'));
      drag(at(15, 0), edge(3, 2));
      expect(selectionService.selectionText, 'aaaaabbb\nccc');
    });

    test('shift click extends the selection', () {
      buffer.lines.set(0, stringToRow('foo bar baz'));
      drag(at(0, 0), edge(3, 0));
      click(edge(7, 0), shiftKey: true);
      expect(selectionService.selectionText, 'foo bar');
    });

    test('alt drag makes a column selection off macOS', () {
      buffer.lines.set(0, stringToRow('abcdefghij'));
      buffer.lines.set(1, stringToRow('klmnopqrst'));
      buffer.lines.set(2, stringToRow('uvwxyz'));
      drag(at(2, 0), edge(4, 2), altKey: true);
      expect(selectionService.isColumnSelectMode, isTrue);
      expect(selectionService.selectionText, 'cd\nmn\nwx');
    });

    test('alt drag on macOS needs macOptionClickForcesSelection off', () {
      selectionService.dispose();
      selectionService = create(TargetPlatform.macOS)..cellSize = cell;
      expect(selectionService.shouldColumnSelect(altKey: true), isTrue);
      optionsService.options.macOptionClickForcesSelection = true;
      expect(selectionService.shouldColumnSelect(altKey: true), isFalse);
    });

    test('alt click moves the cursor', () {
      buffer.lines.set(0, stringToRow('echo hello'));
      click(at(5, 0), altKey: true);
      expect(coreService.data, ['\x1b[C' * 5]);
    });

    test('alt click does not move the cursor when disabled', () {
      optionsService.options.altClickMovesCursor = false;
      buffer.lines.set(0, stringToRow('echo hello'));
      click(at(5, 0), altKey: true);
      expect(coreService.data, isEmpty);
    });

    test('Linux mouse selections become the primary selection', () {
      buffer.lines.set(0, stringToRow('foo bar'));
      final selections = <String>[];
      selectionService.onLinuxMouseSelection(selections.add);
      drag(at(0, 0), edge(3, 0));
      expect(selections.last, 'foo');
    });

    test('a disabled selection needs a forcing modifier', () {
      buffer.lines.set(0, stringToRow('foo bar'));
      selectionService.disable();
      selectionService.handleMouseDown(
        ev(TerminalMouseEventType.mouseDown, at(0, 0)),
      );
      expect(
        selectionService.handleMouseMove(
          ev(TerminalMouseEventType.mouseMove, edge(3, 0)),
        ),
        isFalse,
      );
      expect(selectionService.hasSelection, isFalse);
      // Shift forces the selection off macOS.
      selectionService.handleMouseDown(
        ev(TerminalMouseEventType.mouseDown, at(0, 0), shiftKey: true),
      );
      selectionService.handleMouseMove(
        ev(TerminalMouseEventType.mouseMove, edge(3, 0)),
      );
      selectionService.handleMouseUp(
        ev(TerminalMouseEventType.mouseUp, edge(3, 0)),
      );
      expect(selectionService.selectionText, 'foo');
    });

    test('right click selects the word unless in the selection', () {
      buffer.lines.set(0, stringToRow('foo bar baz'));
      selectionService.rightClickSelect(
        TerminalMouseEvent(
          type: TerminalMouseEventType.mouseDown,
          position: at(5, 0),
          button: 2,
        ),
      );
      expect(selectionService.selectionText, 'bar');
      selectionService.rightClickSelect(
        TerminalMouseEvent(
          type: TerminalMouseEventType.mouseDown,
          position: at(4, 0),
          button: 2,
        ),
      );
      expect(selectionService.selectionText, 'bar');
    });

    testWidgets('dragging below the viewport scrolls', (tester) async {
      final amounts = <int>[];
      selectionService.onRequestScrollLines((e) => amounts.add(e.amount));
      buffer.lines.set(0, stringToRow('foo'));
      selectionService.handleMouseDown(
        ev(TerminalMouseEventType.mouseDown, at(0, 0)),
      );
      // 10 pixels below the 20 rows.
      selectionService.handleMouseMove(
        ev(TerminalMouseEventType.mouseMove, Offset(5, 20 * cell.height + 10)),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(amounts, [4, 4]);
      selectionService.handleMouseUp(
        ev(TerminalMouseEventType.mouseUp, at(0, 0)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(amounts, hasLength(2));
    });

    test('user input clears the selection', () {
      final core = CoreServiceWithInput();
      selectionService.dispose();
      selectionService = TerminalSelection(
        bufferService: bufferService,
        coreService: core,
        optionsService: optionsService,
        mouseStateService: mouseStateService,
        platform: TargetPlatform.linux,
      );
      buffer.lines.set(0, stringToRow('foo bar'));
      selectionService.selectAll();
      expect(selectionService.hasSelection, isTrue);
      core.userInput();
      expect(selectionService.hasSelection, isFalse);
    });

    test('selection text uses CRLF on Windows', () {
      selectionService.dispose();
      selectionService = create(TargetPlatform.windows);
      buffer.lines.set(0, stringToRow('a'));
      buffer.lines.set(1, stringToRow('b'));
      selectionService.selectLines(0, 1);
      expect(selectionService.selectionText, 'a\r\nb');
    });
  });
}

/// A core service whose user input can be fired.
class CoreServiceWithInput extends MockCoreService {
  final Emitter<void> _onUserInput = Emitter<void>();

  @override
  IEvent<void> get onUserInput => _onUserInput.event;

  void userInput() => _onUserInput.fire(null);
}
