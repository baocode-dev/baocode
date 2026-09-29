// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
// Ported from VS Code src/vs/editor/common/core/position.ts.

/// A serializable one-based position in the editor.
abstract interface class IPosition {
  int get lineNumber;
  int get column;
}

class Position implements IPosition {
  const Position(this.lineNumber, this.column);

  @override
  final int lineNumber;
  @override
  final int column;

  // `with` is a Dart keyword; this corresponds to Position.with in TypeScript.
  Position withPosition([int? newLineNumber, int? newColumn]) {
    final line = newLineNumber ?? lineNumber;
    final col = newColumn ?? column;
    return line == lineNumber && col == column ? this : Position(line, col);
  }

  Position delta([int deltaLineNumber = 0, int deltaColumn = 0]) {
    final line = lineNumber + deltaLineNumber;
    final col = column + deltaColumn;
    return withPosition(line < 1 ? 1 : line, col < 1 ? 1 : col);
  }

  bool equals(IPosition other) => equalsPositions(this, other);

  static bool equalsPositions(IPosition? a, IPosition? b) =>
      identical(a, b) ||
      (a != null &&
          b != null &&
          a.lineNumber == b.lineNumber &&
          a.column == b.column);

  bool isBefore(IPosition other) => isBeforePositions(this, other);

  static bool isBeforePositions(IPosition a, IPosition b) =>
      a.lineNumber < b.lineNumber ||
      (a.lineNumber == b.lineNumber && a.column < b.column);

  bool isBeforeOrEqual(IPosition other) =>
      isBeforeOrEqualPositions(this, other);

  static bool isBeforeOrEqualPositions(IPosition a, IPosition b) =>
      a.lineNumber < b.lineNumber ||
      (a.lineNumber == b.lineNumber && a.column <= b.column);

  static int compare(IPosition a, IPosition b) {
    final aLine = a.lineNumber.toSigned(32);
    final bLine = b.lineNumber.toSigned(32);
    return aLine == bLine
        ? a.column.toSigned(32) - b.column.toSigned(32)
        : aLine - bLine;
  }

  Position clone() => Position(lineNumber, column);

  @override
  String toString() => '($lineNumber,$column)';

  static Position lift(IPosition position) =>
      Position(position.lineNumber, position.column);

  static bool isIPosition(Object? value) =>
      value is IPosition ||
      (value is Map && value['lineNumber'] is num && value['column'] is num);

  Map<String, int> toJson() => {'lineNumber': lineNumber, 'column': column};
}
