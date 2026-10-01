import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/selection.dart';

class _SelectionData implements ISelection {
  const _SelectionData(
    this.selectionStartLineNumber,
    this.selectionStartColumn,
    this.positionLineNumber,
    this.positionColumn,
  );

  @override
  final int selectionStartLineNumber;
  @override
  final int selectionStartColumn;
  @override
  final int positionLineNumber;
  @override
  final int positionColumn;
}

void main() {
  group('Editor Core - Selection (VS Code selection.ts)', () {
    test(
      'forward selection retains anchor and caret at normalized endpoints',
      () {
        final selection = Selection(2, 3, 4, 5);
        expect(selection.getDirection(), SelectionDirection.ltr);
        expect(selection.startLineNumber, 2);
        expect(selection.startColumn, 3);
        expect(selection.endLineNumber, 4);
        expect(selection.endColumn, 5);
        expect(selection.selectionStartLineNumber, 2);
        expect(selection.selectionStartColumn, 3);
        expect(selection.positionLineNumber, 4);
        expect(selection.positionColumn, 5);
        expect(
          selection.getSelectionStart().equals(const Position(2, 3)),
          isTrue,
        );
        expect(selection.getPosition().equals(const Position(4, 5)), isTrue);
        expect(selection.toString(), '[2,3 -> 4,5]');
      },
    );

    test('backward selection normalizes range but not anchor or caret', () {
      // The constructor delegates normalization to Range; source coordinates
      // remain unchanged, so selection direction is independent of range order.
      for (final selection in [Selection(4, 5, 2, 3), Selection(2, 8, 2, 3)]) {
        expect(selection.getDirection(), SelectionDirection.rtl);
        expect(
          selection.getSelectionStart().equals(selection.getEndPosition()),
          isTrue,
        );
        expect(
          selection.getPosition().equals(selection.getStartPosition()),
          isTrue,
        );
      }
      final backward = Selection(4, 5, 2, 3);
      expect(backward.equalsRange(Range(2, 3, 4, 5)), isTrue);
      expect(backward.selectionStartLineNumber, 4);
      expect(backward.selectionStartColumn, 5);
      expect(backward.positionLineNumber, 2);
      expect(backward.positionColumn, 3);
      expect(backward.toString(), '[4,5 -> 2,3]');
      final sameLine = Selection(2, 8, 2, 3);
      expect(sameLine.equalsRange(Range(2, 3, 2, 8)), isTrue);
      expect(sameLine.toString(), '[2,8 -> 2,3]');
    });

    test('empty selection is LTR even when made with RTL direction', () {
      final empty = Selection(3, 7, 3, 7);
      expect(empty.isEmpty(), isTrue);
      expect(empty.getDirection(), SelectionDirection.ltr);
      expect(empty.getSelectionStart().equals(const Position(3, 7)), isTrue);
      expect(empty.getPosition().equals(const Position(3, 7)), isTrue);
      expect(
        Selection.createWithDirection(
          3,
          7,
          3,
          7,
          SelectionDirection.rtl,
        ).getDirection(),
        SelectionDirection.ltr,
      );
    });

    test('selection equality differs from range equality', () {
      final forward = Selection(2, 3, 4, 5);
      final backward = Selection(4, 5, 2, 3);
      expect(forward.equalsRange(backward), isTrue);
      expect(forward.equalsSelection(backward), isFalse);
      expect(Selection.selectionsEqual(forward, backward), isFalse);
      expect(forward.equalsSelection(const _SelectionData(2, 3, 4, 5)), isTrue);
      expect(
        Selection.selectionsEqual(backward, const _SelectionData(4, 5, 2, 3)),
        isTrue,
      );
      expect(forward.equalsSelection(Selection(2, 3, 4, 6)), isFalse);
      expect(forward.equalsSelection(Selection(2, 4, 4, 5)), isFalse);
      expect(forward.equalsSelection(Selection(3, 3, 4, 5)), isFalse);
      expect(forward.equalsSelection(Selection(2, 3, 3, 5)), isFalse);
    });

    test('setStartPosition and setEndPosition retain forward orientation', () {
      final forward = Selection(2, 3, 4, 5);
      final newStart = forward.setStartPosition(1, 2);
      final newEnd = forward.setEndPosition(5, 6);
      expect(newStart, isA<Selection>());
      expect(newStart.equalsSelection(Selection(1, 2, 4, 5)), isTrue);
      expect(newEnd.equalsSelection(Selection(2, 3, 5, 6)), isTrue);
      expect(newStart.getDirection(), SelectionDirection.ltr);
      expect(newEnd.getDirection(), SelectionDirection.ltr);
      expect(forward.equalsSelection(Selection(2, 3, 4, 5)), isTrue);
    });

    test('setStartPosition and setEndPosition retain backward orientation', () {
      final backward = Selection(4, 5, 2, 3);
      final newStart = backward.setStartPosition(1, 2);
      final newEnd = backward.setEndPosition(5, 6);
      expect(newStart, isA<Selection>());
      expect(newStart.equalsSelection(Selection(4, 5, 1, 2)), isTrue);
      expect(newEnd.equalsSelection(Selection(5, 6, 2, 3)), isTrue);
      expect(newStart.getDirection(), SelectionDirection.rtl);
      expect(newEnd.getDirection(), SelectionDirection.rtl);
      expect(backward.equalsSelection(Selection(4, 5, 2, 3)), isTrue);
    });

    test('setters use range endpoints even if new endpoint crosses over', () {
      // Source setters choose the new anchor/caret based on the *old*
      // direction. The resulting direction follows the normalized new range.
      final flippedEnd = Selection(2, 3, 4, 5).setEndPosition(1, 2);
      expect(flippedEnd.equalsSelection(Selection(2, 3, 1, 2)), isTrue);
      expect(flippedEnd.getDirection(), SelectionDirection.rtl);
      final flippedStart = Selection(4, 5, 2, 3).setStartPosition(5, 6);
      expect(flippedStart.equalsSelection(Selection(4, 5, 5, 6)), isTrue);
      expect(flippedStart.getDirection(), SelectionDirection.ltr);
    });

    test('fromPositions defaults end to start and retains reversed order', () {
      final collapsed = Selection.fromPositions(const Position(2, 3));
      expect(collapsed.equalsSelection(Selection(2, 3, 2, 3)), isTrue);
      expect(collapsed.isEmpty(), isTrue);
      expect(
        Selection.fromPositions(
          const Position(2, 3),
          const Position(4, 5),
        ).equalsSelection(Selection(2, 3, 4, 5)),
        isTrue,
      );
      final reversed = Selection.fromPositions(
        const Position(4, 5),
        const Position(2, 3),
      );
      expect(reversed.equalsSelection(Selection(4, 5, 2, 3)), isTrue);
      expect(reversed.getDirection(), SelectionDirection.rtl);
      expect(reversed.equalsRange(Range(2, 3, 4, 5)), isTrue);
    });

    test('fromRange and createWithDirection use normalized endpoints', () {
      final range = Range(4, 5, 2, 3);
      for (final direction in SelectionDirection.values) {
        final expected = direction == SelectionDirection.ltr
            ? Selection(2, 3, 4, 5)
            : Selection(4, 5, 2, 3);
        final fromRange = Selection.fromRange(range, direction);
        final created = Selection.createWithDirection(2, 3, 4, 5, direction);
        expect(fromRange.equalsSelection(expected), isTrue);
        expect(created.equalsSelection(expected), isTrue);
        expect(fromRange.getDirection(), direction);
        expect(created.getDirection(), direction);
      }
    });

    test('liftSelection copies all four selection coordinates', () {
      const data = _SelectionData(4, 5, 2, 3);
      final lifted = Selection.liftSelection(data);
      expect(lifted.equalsSelection(Selection(4, 5, 2, 3)), isTrue);
      expect(lifted.getDirection(), SelectionDirection.rtl);
      final original = Selection(4, 5, 2, 3);
      final copy = Selection.liftSelection(original);
      expect(copy, isNot(same(original)));
      expect(copy.equalsSelection(original), isTrue);
    });

    test('selectionsArrEqual handles null, length, order and orientation', () {
      final first = Selection(2, 3, 4, 5);
      final second = Selection(6, 1, 6, 4);
      expect(Selection.selectionsArrEqual(null, null), isTrue);
      expect(Selection.selectionsArrEqual(null, <ISelection>[]), isFalse);
      expect(Selection.selectionsArrEqual(<ISelection>[], null), isFalse);
      expect(
        Selection.selectionsArrEqual(<ISelection>[], <ISelection>[]),
        isTrue,
      );
      expect(Selection.selectionsArrEqual([first], [first, second]), isFalse);
      expect(
        Selection.selectionsArrEqual([first, second], [second, first]),
        isFalse,
      );
      expect(
        Selection.selectionsArrEqual(
          [first, second],
          [const _SelectionData(2, 3, 4, 5), const _SelectionData(6, 1, 6, 4)],
        ),
        isTrue,
      );
      expect(
        Selection.selectionsArrEqual([first], [Selection(4, 5, 2, 3)]),
        isFalse,
      );
    });

    test('isISelection recognizes interfaces and numeric coordinate maps', () {
      expect(Selection.isISelection(Selection(2, 3, 4, 5)), isTrue);
      expect(Selection.isISelection(const _SelectionData(2, 3, 4, 5)), isTrue);
      expect(
        Selection.isISelection({
          'selectionStartLineNumber': 2,
          'selectionStartColumn': 3,
          'positionLineNumber': 4,
          'positionColumn': 5,
        }),
        isTrue,
      );
      expect(
        Selection.isISelection({
          'selectionStartLineNumber': 2.0,
          'selectionStartColumn': 3,
          'positionLineNumber': 4,
          'positionColumn': 5.0,
        }),
        isTrue,
      );
      expect(
        Selection.isISelection({
          'selectionStartLineNumber': 2,
          'selectionStartColumn': '3',
          'positionLineNumber': 4,
          'positionColumn': 5,
        }),
        isFalse,
      );
      expect(
        Selection.isISelection({
          'selectionStartLineNumber': 2,
          'selectionStartColumn': 3,
          'positionLineNumber': 4,
        }),
        isFalse,
      );
      expect(Selection.isISelection(Range(2, 3, 4, 5)), isFalse);
      expect(Selection.isISelection(null), isFalse);
    });

    test('toJson contains normalized range plus anchor and caret', () {
      final forward = Selection(2, 3, 4, 5);
      final backward = Selection(4, 5, 2, 3);
      for (final (selection, expected) in [
        (
          forward,
          <String, int>{
            'startLineNumber': 2,
            'startColumn': 3,
            'endLineNumber': 4,
            'endColumn': 5,
            'selectionStartLineNumber': 2,
            'selectionStartColumn': 3,
            'positionLineNumber': 4,
            'positionColumn': 5,
          },
        ),
        (
          backward,
          <String, int>{
            'startLineNumber': 2,
            'startColumn': 3,
            'endLineNumber': 4,
            'endColumn': 5,
            'selectionStartLineNumber': 4,
            'selectionStartColumn': 5,
            'positionLineNumber': 2,
            'positionColumn': 3,
          },
        ),
      ]) {
        expect(selection.toJson(), expected);
        expect(jsonDecode(jsonEncode(selection.toJson())), expected);
      }
    });
  });
}
