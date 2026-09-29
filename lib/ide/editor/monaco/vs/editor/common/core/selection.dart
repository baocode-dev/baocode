// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
// Ported from VS Code src/vs/editor/common/core/selection.ts.

import 'position.dart';
import 'range.dart';

abstract interface class ISelection {
  int get selectionStartLineNumber;
  int get selectionStartColumn;
  int get positionLineNumber;
  int get positionColumn;
}

enum SelectionDirection { ltr, rtl }

/// A range with an anchor and an active position.
class Selection extends Range implements ISelection {
  Selection(
    this.selectionStartLineNumber,
    this.selectionStartColumn,
    this.positionLineNumber,
    this.positionColumn,
  ) : super(
        selectionStartLineNumber,
        selectionStartColumn,
        positionLineNumber,
        positionColumn,
      );

  @override
  final int selectionStartLineNumber;
  @override
  final int selectionStartColumn;
  @override
  final int positionLineNumber;
  @override
  final int positionColumn;

  @override
  String toString() =>
      '[$selectionStartLineNumber,$selectionStartColumn -> $positionLineNumber,$positionColumn]';

  bool equalsSelection(ISelection other) => selectionsEqual(this, other);

  static bool selectionsEqual(ISelection a, ISelection b) =>
      a.selectionStartLineNumber == b.selectionStartLineNumber &&
      a.selectionStartColumn == b.selectionStartColumn &&
      a.positionLineNumber == b.positionLineNumber &&
      a.positionColumn == b.positionColumn;

  SelectionDirection getDirection() =>
      selectionStartLineNumber == startLineNumber &&
          selectionStartColumn == startColumn
      ? SelectionDirection.ltr
      : SelectionDirection.rtl;

  @override
  Selection setEndPosition(int line, int column) =>
      getDirection() == SelectionDirection.ltr
      ? Selection(startLineNumber, startColumn, line, column)
      : Selection(line, column, startLineNumber, startColumn);

  Position getPosition() => Position(positionLineNumber, positionColumn);

  Position getSelectionStart() =>
      Position(selectionStartLineNumber, selectionStartColumn);

  @override
  Selection setStartPosition(int line, int column) =>
      getDirection() == SelectionDirection.ltr
      ? Selection(line, column, endLineNumber, endColumn)
      : Selection(endLineNumber, endColumn, line, column);

  static Selection fromPositions(IPosition start, [IPosition? end]) {
    final last = end ?? start;
    return Selection(
      start.lineNumber,
      start.column,
      last.lineNumber,
      last.column,
    );
  }

  static Selection fromRange(Range range, SelectionDirection direction) =>
      direction == SelectionDirection.ltr
      ? Selection(
          range.startLineNumber,
          range.startColumn,
          range.endLineNumber,
          range.endColumn,
        )
      : Selection(
          range.endLineNumber,
          range.endColumn,
          range.startLineNumber,
          range.startColumn,
        );

  static Selection liftSelection(ISelection selection) => Selection(
    selection.selectionStartLineNumber,
    selection.selectionStartColumn,
    selection.positionLineNumber,
    selection.positionColumn,
  );

  static bool selectionsArrEqual(List<ISelection>? a, List<ISelection>? b) {
    if (a == null || b == null) return a == null && b == null;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!selectionsEqual(a[i], b[i])) return false;
    }
    return true;
  }

  static bool isISelection(Object? value) =>
      value is ISelection ||
      (value is Map &&
          value['selectionStartLineNumber'] is num &&
          value['selectionStartColumn'] is num &&
          value['positionLineNumber'] is num &&
          value['positionColumn'] is num);

  static Selection createWithDirection(
    int startLineNumber,
    int startColumn,
    int endLineNumber,
    int endColumn,
    SelectionDirection direction,
  ) => direction == SelectionDirection.ltr
      ? Selection(startLineNumber, startColumn, endLineNumber, endColumn)
      : Selection(endLineNumber, endColumn, startLineNumber, startColumn);

  @override
  Map<String, int> toJson() => {
    ...super.toJson(),
    'selectionStartLineNumber': selectionStartLineNumber,
    'selectionStartColumn': selectionStartColumn,
    'positionLineNumber': positionLineNumber,
    'positionColumn': positionColumn,
  };
}
