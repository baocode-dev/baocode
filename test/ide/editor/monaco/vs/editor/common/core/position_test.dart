import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/position.dart';

class _PositionData implements IPosition {
  const _PositionData(this.lineNumber, this.column);

  @override
  final int lineNumber;
  @override
  final int column;
}

void main() {
  group('Editor Core - Position', () {
    test('coordinates, string and clone', () {
      const p = Position(2, 3);
      expect(p.lineNumber, 2);
      expect(p.column, 3);
      expect(p.toString(), '(2,3)');
      final copy = p.clone();
      expect(copy, isNot(same(p)));
      expect(copy.equals(p), isTrue);
    });

    test('withPosition retains identity or changes selected coordinates', () {
      const p = Position(3, 4);
      expect(p.withPosition(), same(p));
      expect(p.withPosition(3, 4), same(p));
      expect(p.withPosition(5).equals(const Position(5, 4)), isTrue);
      expect(p.withPosition(null, 6).equals(const Position(3, 6)), isTrue);
      expect(p.withPosition(1, 2).equals(const Position(1, 2)), isTrue);
    });

    test('delta changes coordinates independently and clamps to one', () {
      const p = Position(3, 4);
      expect(p.delta(), same(p));
      expect(p.delta(1, -2).equals(const Position(4, 2)), isTrue);
      expect(p.delta(-100, -100).equals(const Position(1, 1)), isTrue);
      expect(p.delta(0, 2).equals(const Position(3, 6)), isTrue);
    });

    test('equality uses coordinates, including null static operands', () {
      const p = Position(2, 3);
      expect(p.equals(const _PositionData(2, 3)), isTrue);
      expect(p.equals(const Position(2, 4)), isFalse);
      expect(Position.equalsPositions(p, const _PositionData(3, 3)), isFalse);
      expect(Position.equalsPositions(null, null), isTrue);
      expect(Position.equalsPositions(p, null), isFalse);
      expect(Position.equalsPositions(null, p), isFalse);
    });

    test('ordering and comparison use line then column', () {
      const before = Position(2, 10);
      const laterLine = Position(3, 1);
      const laterColumn = Position(2, 11);
      expect(before.isBefore(laterLine), isTrue);
      expect(before.isBefore(laterColumn), isTrue);
      expect(laterLine.isBefore(before), isFalse);
      expect(before.isBefore(const Position(2, 10)), isFalse);
      expect(before.isBeforeOrEqual(const Position(2, 10)), isTrue);
      expect(Position.isBeforePositions(before, laterLine), isTrue);
      expect(Position.isBeforeOrEqualPositions(laterColumn, before), isFalse);
      expect(Position.compare(before, laterLine), lessThan(0));
      expect(Position.compare(laterLine, before), greaterThan(0));
      expect(Position.compare(before, laterColumn), lessThan(0));
      expect(Position.compare(before, const _PositionData(2, 10)), 0);
      final positions = [laterLine, laterColumn, before]
        ..sort(Position.compare);
      expect(positions, [before, laterColumn, laterLine]);
    });

    test('lift and structural interface checks', () {
      const p = Position(4, 5);
      final lifted = Position.lift(const _PositionData(4, 5));
      expect(lifted, isA<Position>());
      expect(lifted.equals(p), isTrue);
      expect(lifted, isNot(same(p)));
      expect(Position.isIPosition(p), isTrue);
      expect(Position.isIPosition(const _PositionData(4, 5)), isTrue);
      expect(Position.isIPosition({'lineNumber': 4, 'column': 5}), isTrue);
      expect(Position.isIPosition({'lineNumber': 4.0, 'column': 5.0}), isTrue);
      expect(Position.isIPosition({'lineNumber': '4', 'column': 5}), isFalse);
      expect(Position.isIPosition({'lineNumber': 4}), isFalse);
      expect(Position.isIPosition(null), isFalse);
    });

    test('toJson exposes one-based coordinates', () {
      const p = Position(4, 5);
      expect(p.toJson(), {'lineNumber': 4, 'column': 5});
      expect(jsonDecode(jsonEncode(p.toJson())), {
        'lineNumber': 4,
        'column': 5,
      });
    });
  });
}
