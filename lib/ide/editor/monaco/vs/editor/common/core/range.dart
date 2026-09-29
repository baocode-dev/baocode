// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
// Ported from VS Code src/vs/editor/common/core/range.ts.

import 'position.dart';

/// A serializable one-based range in the editor.
abstract interface class IRange {
  int get startLineNumber;
  int get startColumn;
  int get endLineNumber;
  int get endColumn;
}

/// A range whose start is always before or equal to its end.
class Range implements IRange {
  Range(int startLine, int startCol, int endLine, int endCol)
    : startLineNumber =
          startLine > endLine || (startLine == endLine && startCol > endCol)
          ? endLine
          : startLine,
      startColumn =
          startLine > endLine || (startLine == endLine && startCol > endCol)
          ? endCol
          : startCol,
      endLineNumber =
          startLine > endLine || (startLine == endLine && startCol > endCol)
          ? startLine
          : endLine,
      endColumn =
          startLine > endLine || (startLine == endLine && startCol > endCol)
          ? startCol
          : endCol;

  @override
  final int startLineNumber;
  @override
  final int startColumn;
  @override
  final int endLineNumber;
  @override
  final int endColumn;

  bool isEmpty() => isEmptyRange(this);

  static bool isEmptyRange(IRange range) =>
      range.startLineNumber == range.endLineNumber &&
      range.startColumn == range.endColumn;

  bool containsPosition(IPosition position) =>
      containsPositionInRange(this, position);

  static bool containsPositionInRange(IRange range, IPosition position) {
    if (position.lineNumber < range.startLineNumber ||
        position.lineNumber > range.endLineNumber) {
      return false;
    }
    if (position.lineNumber == range.startLineNumber &&
        position.column < range.startColumn) {
      return false;
    }
    if (position.lineNumber == range.endLineNumber &&
        position.column > range.endColumn) {
      return false;
    }
    return true;
  }

  static bool strictContainsPosition(IRange range, IPosition position) {
    if (position.lineNumber < range.startLineNumber ||
        position.lineNumber > range.endLineNumber) {
      return false;
    }
    if (position.lineNumber == range.startLineNumber &&
        position.column <= range.startColumn) {
      return false;
    }
    if (position.lineNumber == range.endLineNumber &&
        position.column >= range.endColumn) {
      return false;
    }
    return true;
  }

  bool containsRange(IRange range) => containsRangeInRange(this, range);

  static bool containsRangeInRange(IRange range, IRange other) {
    if (other.startLineNumber < range.startLineNumber ||
        other.endLineNumber < range.startLineNumber) {
      return false;
    }
    if (other.startLineNumber > range.endLineNumber ||
        other.endLineNumber > range.endLineNumber) {
      return false;
    }
    if (other.startLineNumber == range.startLineNumber &&
        other.startColumn < range.startColumn) {
      return false;
    }
    if (other.endLineNumber == range.endLineNumber &&
        other.endColumn > range.endColumn) {
      return false;
    }
    return true;
  }

  bool strictContainsRange(IRange range) =>
      strictContainsRangeInRange(this, range);

  static bool strictContainsRangeInRange(IRange range, IRange other) {
    if (other.startLineNumber < range.startLineNumber ||
        other.endLineNumber < range.startLineNumber) {
      return false;
    }
    if (other.startLineNumber > range.endLineNumber ||
        other.endLineNumber > range.endLineNumber) {
      return false;
    }
    if (other.startLineNumber == range.startLineNumber &&
        other.startColumn <= range.startColumn) {
      return false;
    }
    if (other.endLineNumber == range.endLineNumber &&
        other.endColumn >= range.endColumn) {
      return false;
    }
    return true;
  }

  Range plusRange(IRange range) => plusRanges(this, range);

  static Range plusRanges(IRange a, IRange b) {
    final startLine = b.startLineNumber < a.startLineNumber
        ? b.startLineNumber
        : a.startLineNumber;
    final startCol = b.startLineNumber < a.startLineNumber
        ? b.startColumn
        : b.startLineNumber == a.startLineNumber
        ? (b.startColumn < a.startColumn ? b.startColumn : a.startColumn)
        : a.startColumn;
    final endLine = b.endLineNumber > a.endLineNumber
        ? b.endLineNumber
        : a.endLineNumber;
    final endCol = b.endLineNumber > a.endLineNumber
        ? b.endColumn
        : b.endLineNumber == a.endLineNumber
        ? (b.endColumn > a.endColumn ? b.endColumn : a.endColumn)
        : a.endColumn;
    return Range(startLine, startCol, endLine, endCol);
  }

  Range? intersectRanges(IRange range) => intersectTwoRanges(this, range);

  static Range? intersectTwoRanges(IRange a, IRange b) {
    var startLine = a.startLineNumber;
    var startCol = a.startColumn;
    var endLine = a.endLineNumber;
    var endCol = a.endColumn;

    if (startLine < b.startLineNumber) {
      startLine = b.startLineNumber;
      startCol = b.startColumn;
    } else if (startLine == b.startLineNumber && startCol < b.startColumn) {
      startCol = b.startColumn;
    }
    if (endLine > b.endLineNumber) {
      endLine = b.endLineNumber;
      endCol = b.endColumn;
    } else if (endLine == b.endLineNumber && endCol > b.endColumn) {
      endCol = b.endColumn;
    }
    if (startLine > endLine || (startLine == endLine && startCol > endCol)) {
      return null;
    }
    return Range(startLine, startCol, endLine, endCol);
  }

  bool equalsRange(IRange? other) => equalsRanges(this, other);

  static bool equalsRanges(IRange? a, IRange? b) =>
      identical(a, b) ||
      (a != null &&
          b != null &&
          a.startLineNumber == b.startLineNumber &&
          a.startColumn == b.startColumn &&
          a.endLineNumber == b.endLineNumber &&
          a.endColumn == b.endColumn);

  Position getEndPosition() => endPositionOf(this);

  static Position endPositionOf(IRange range) =>
      Position(range.endLineNumber, range.endColumn);

  Position getStartPosition() => startPositionOf(this);

  static Position startPositionOf(IRange range) =>
      Position(range.startLineNumber, range.startColumn);

  @override
  String toString() =>
      '[$startLineNumber,$startColumn -> $endLineNumber,$endColumn]';

  Range setEndPosition(int line, int column) =>
      Range(startLineNumber, startColumn, line, column);

  Range setStartPosition(int line, int column) =>
      Range(line, column, endLineNumber, endColumn);

  Range collapseToStart() => collapseRangeToStart(this);

  static Range collapseRangeToStart(IRange range) => Range(
    range.startLineNumber,
    range.startColumn,
    range.startLineNumber,
    range.startColumn,
  );

  Range collapseToEnd() => collapseRangeToEnd(this);

  static Range collapseRangeToEnd(IRange range) => Range(
    range.endLineNumber,
    range.endColumn,
    range.endLineNumber,
    range.endColumn,
  );

  Range delta(int lineCount) => Range(
    startLineNumber + lineCount,
    startColumn,
    endLineNumber + lineCount,
    endColumn,
  );

  bool isSingleLine() => startLineNumber == endLineNumber;

  static Range fromPositions(IPosition start, [IPosition? end]) {
    final last = end ?? start;
    return Range(start.lineNumber, start.column, last.lineNumber, last.column);
  }

  static Range? lift(IRange? range) => range == null
      ? null
      : Range(
          range.startLineNumber,
          range.startColumn,
          range.endLineNumber,
          range.endColumn,
        );

  static bool isIRange(Object? value) =>
      value is IRange ||
      (value is Map &&
          value['startLineNumber'] is num &&
          value['startColumn'] is num &&
          value['endLineNumber'] is num &&
          value['endColumn'] is num);

  static bool areIntersectingOrTouching(IRange a, IRange b) {
    if (a.endLineNumber < b.startLineNumber ||
        (a.endLineNumber == b.startLineNumber && a.endColumn < b.startColumn)) {
      return false;
    }
    if (b.endLineNumber < a.startLineNumber ||
        (b.endLineNumber == a.startLineNumber && b.endColumn < a.startColumn)) {
      return false;
    }
    return true;
  }

  // Upstream uses <= here: ranges meeting at an endpoint do not intersect.
  static bool areIntersecting(IRange a, IRange b) {
    if (a.endLineNumber < b.startLineNumber ||
        (a.endLineNumber == b.startLineNumber &&
            a.endColumn <= b.startColumn)) {
      return false;
    }
    if (b.endLineNumber < a.startLineNumber ||
        (b.endLineNumber == a.startLineNumber &&
            b.endColumn <= a.startColumn)) {
      return false;
    }
    return true;
  }

  static bool areOnlyIntersecting(IRange a, IRange b) {
    if (a.endLineNumber < b.startLineNumber - 1 ||
        (a.endLineNumber == b.startLineNumber &&
            a.endColumn < b.startColumn - 1)) {
      return false;
    }
    if (b.endLineNumber < a.startLineNumber - 1 ||
        (b.endLineNumber == a.startLineNumber &&
            b.endColumn < a.startColumn - 1)) {
      return false;
    }
    return true;
  }

  static int compareRangesUsingStarts(IRange? a, IRange? b) {
    if (a != null && b != null) {
      final aStartLine = a.startLineNumber.toSigned(32);
      final bStartLine = b.startLineNumber.toSigned(32);
      if (aStartLine == bStartLine) {
        final aStartCol = a.startColumn.toSigned(32);
        final bStartCol = b.startColumn.toSigned(32);
        if (aStartCol == bStartCol) {
          final aEndLine = a.endLineNumber.toSigned(32);
          final bEndLine = b.endLineNumber.toSigned(32);
          if (aEndLine == bEndLine) {
            return a.endColumn.toSigned(32) - b.endColumn.toSigned(32);
          }
          return aEndLine - bEndLine;
        }
        return aStartCol - bStartCol;
      }
      return aStartLine - bStartLine;
    }
    return (a == null ? 0 : 1) - (b == null ? 0 : 1);
  }

  static int compareRangesUsingEnds(IRange a, IRange b) {
    if (a.endLineNumber == b.endLineNumber) {
      if (a.endColumn == b.endColumn) {
        if (a.startLineNumber == b.startLineNumber) {
          return a.startColumn - b.startColumn;
        }
        return a.startLineNumber - b.startLineNumber;
      }
      return a.endColumn - b.endColumn;
    }
    return a.endLineNumber - b.endLineNumber;
  }

  static bool spansMultipleLines(IRange range) =>
      range.endLineNumber > range.startLineNumber;

  Map<String, int> toJson() => {
    'startLineNumber': startLineNumber,
    'startColumn': startColumn,
    'endLineNumber': endLineNumber,
    'endColumn': endColumn,
  };
}
