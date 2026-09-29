import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/commands/replace_command.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/commands/shift_command.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/commands/surround_selection_command.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/commands/trim_trailing_whitespace_command.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/position.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/range.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/selection.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/model/piece_tree_text_buffer/piece_tree_text_buffer.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/model/piece_tree_text_buffer/piece_tree_text_buffer_builder.dart';

PieceTreeTextBuffer buffer(String value) {
  final builder = PieceTreeTextBufferBuilder()..acceptChunk(value);
  return builder.finish().create(DefaultEndOfLine.lf);
}

void expectSelection(
  Selection actual,
  int anchorLine,
  int anchorColumn,
  int activeLine,
  int activeColumn,
) {
  expect(
    actual.equalsSelection(
      Selection(anchorLine, anchorColumn, activeLine, activeColumn),
    ),
    isTrue,
    reason: '$actual',
  );
}

void main() {
  group('replaceCommand.ts subset', () {
    test('replaces across CRLF, keeps UTF-16 caret and exposes undo', () {
      final model = buffer('a😀\r\nlast');
      final result = ReplaceCommand(
        Range(1, 2, 2, 3),
        '🌍\nnew',
      ).execute(model);
      expect(model.getValue(), 'a🌍\r\nnewst');
      expectSelection(result.selection, 2, 4, 2, 4);
      expect(result.undoEdits.single.text, '😀\r\nla');
      model.applyEdits([
        for (final edit in result.undoEdits)
          ValidAnnotatedEditOperation(null, edit.range, edit.text),
      ]);
      expect(model.getValue(), 'a😀\r\nlast');
    });

    test('selects inserted text or leaves caret at replacement start', () {
      final selected = buffer('abcdef');
      final result = ReplaceCommandThatSelectsText(
        Range(1, 2, 1, 5),
        'XY',
      ).execute(selected);
      expect(selected.getValue(), 'aXYef');
      expectSelection(result.selection, 1, 2, 1, 4);
      final start = ReplaceCommandWithoutChangingPosition(
        Range(1, 2, 1, 4),
        '',
      ).execute(selected);
      expect(selected.getValue(), 'aef');
      expectSelection(start.selection, 1, 2, 1, 2);
    });

    test('applies offset cursor state and does not notify on no-op', () {
      final model = buffer('ab');
      final result = ReplaceCommandWithOffsetCursorState(
        Range(1, 2, 1, 2),
        'XY',
        0,
        -1,
      ).execute(model);
      expect(model.getValue(), 'aXYb');
      expectSelection(result.selection, 1, 3, 1, 3);
      var changes = 0;
      model.onDidChangeContent(() => changes++);
      expectSelection(
        ReplaceCommand(Range(1, 1, 1, 1), '').execute(model).selection,
        1,
        1,
        1,
        1,
      );
      expect(changes, 0);
      expect(
        () => ReplaceCommand(Range(9, 1, 9, 1), 'bad').execute(model),
        throwsRangeError,
      );
      expect(model.getValue(), 'aXYb');
    });
  });

  group('surroundSelectionCommand.ts subset', () {
    test('wraps multiline and reversed selections without replacing text', () {
      final model = buffer('hello\nworld');
      final result = SurroundSelectionCommand(
        Selection(2, 4, 1, 2),
        '[',
        ']',
      ).execute(model);
      expect(model.getValue(), 'h[ello\nwor]ld');
      expectSelection(result.selection, 1, 3, 2, 4);
      expect(result.undoEdits, hasLength(2));
    });

    test('empty suffix and empty selection remain valid', () {
      final model = buffer('ab');
      final result = SurroundSelectionCommand(
        Selection(1, 2, 1, 3),
        '(',
        '',
      ).execute(model);
      expect(model.getValue(), 'a(b');
      expectSelection(result.selection, 1, 3, 1, 4);
      final caret = buffer('ab');
      final wrapped = SurroundSelectionCommand(
        Selection(1, 2, 1, 2),
        '(',
        ')',
      ).execute(caret);
      expect(caret.getValue(), 'a()b');
      expectSelection(wrapped.selection, 1, 3, 1, 3);
    });

    test('suffix-only delimiters leave selection before the suffix', () {
      final model = buffer('abc');
      final result = SurroundSelectionCommand(
        Selection(1, 2, 1, 3),
        '',
        ')',
      ).execute(model);
      expect(model.getValue(), 'ab)c');
      expectSelection(result.selection, 1, 2, 1, 3);
      final empty = SurroundSelectionCommand(
        Selection(1, 2, 1, 3),
        '',
        '',
      ).execute(model);
      expect(model.getValue(), 'ab)c');
      expectSelection(empty.selection, 1, 2, 1, 3);
    });
  });

  group('trimTrailingWhitespaceCommand.ts text-only path', () {
    test(
      'skips cursor-at-end, protects suffix from cursor and tracks selection',
      () {
        final model = buffer('first  \nsecond \nthird\t \n \t');
        final cursors = [const Position(2, 8), const Position(1, 6)];
        final operations = trimTrailingWhitespace(model, cursors);
        expect(operations.map((e) => e.range.toString()).toList(), [
          '[1,6 -> 1,8]',
          '[3,6 -> 3,8]',
          '[4,1 -> 4,3]',
        ]);
        expect(cursors, [const Position(2, 8), const Position(1, 6)]);
        final result = TrimTrailingWhitespaceCommand(
          Selection(3, 1, 1, 2),
          cursors,
        ).execute(model);
        expect(model.getValue(), 'first\nsecond \nthird\n');
        expectSelection(result.selection, 3, 1, 1, 2);
        expect(result.undoEdits, hasLength(3));
      },
    );

    test('does not change model on clean lines', () {
      final model = buffer('one\ntwo');
      var notifications = 0;
      model.onDidChangeContent(() => notifications++);
      final result = TrimTrailingWhitespaceCommand(
        Selection(1, 2, 1, 2),
        [],
      ).execute(model);
      expectSelection(result.selection, 1, 2, 1, 2);
      expect(result.undoEdits, isEmpty);
      expect(notifications, 0);
    });
  });

  group('shiftCommand.ts text-only path', () {
    const spaces = ShiftCommandOptions(
      isUnshift: false,
      tabSize: 4,
      indentSize: 4,
      insertSpaces: true,
      useTabStops: false,
    );
    const unshift = ShiftCommandOptions(
      isUnshift: true,
      tabSize: 4,
      indentSize: 4,
      insertSpaces: true,
      useTabStops: false,
    );
    test(
      'shifts selected lines but not final line when selection ends at 1',
      () {
        final model = buffer('a\nb\nc');
        final result = ShiftCommand(
          Selection(1, 1, 3, 1),
          spaces,
        ).execute(model);
        expect(model.getValue(), '    a\n    b\nc');
        expectSelection(result.selection, 1, 1, 3, 1);
        expect(result.undoEdits, hasLength(2));
        ShiftCommand(Selection(1, 1, 3, 1), unshift).execute(model);
        expect(model.getValue(), 'a\nb\nc');
      },
    );

    test('unshifts to first tab and moves caret on whitespace-only line', () {
      final model = buffer(' \t  x\n');
      ShiftCommand(Selection(1, 5, 1, 5), unshift).execute(model);
      expect(model.getValue(), '  x\n');
      final blank = buffer('');
      final result = ShiftCommand(Selection(1, 1, 1, 1), spaces).execute(blank);
      expect(blank.getValue(), '    ');
      expectSelection(result.selection, 1, 5, 1, 5);
    });

    test('tab stops use visible widths for spaces and tabs', () {
      const indent = ShiftCommandOptions(
        isUnshift: false,
        tabSize: 4,
        indentSize: 2,
        insertSpaces: true,
        useTabStops: true,
      );
      const outdent = ShiftCommandOptions(
        isUnshift: true,
        tabSize: 4,
        indentSize: 2,
        insertSpaces: true,
        useTabStops: true,
      );
      final model = buffer('\tx\n   y\n');
      final command = ShiftCommand(Selection(1, 1, 3, 1), indent);
      expect(model.getLineContent(1), '\tx');
      expect(ShiftCommand.shiftIndent('\tx', 2, 4, 2, true), '      ');
      expect(command.getEditOperations(model).map((e) => e.text).toList(), [
        '      ',
        '    ',
      ]);
      command.execute(model);
      expect(model.getValue(), '      x\n    y\n');
      ShiftCommand(Selection(1, 1, 3, 1), outdent).execute(model);
      expect(model.getValue(), '    x\n  y\n');
      expect(ShiftCommand.shiftIndent('\tx', 2, 4, 2, false), '\t\t');
      expect(ShiftCommand.unshiftIndent('\tx', 2, 4, 2, false), '');
    });

    test('reversed selection remains reversed and empty lines are omitted', () {
      final model = buffer('a\n\nb');
      final result = ShiftCommand(Selection(3, 2, 1, 2), spaces).execute(model);
      expect(model.getValue(), '    a\n\n    b');
      expect(result.selection.getDirection(), SelectionDirection.rtl);
      expectSelection(result.selection, 3, 6, 1, 6);
    });
  });
}
