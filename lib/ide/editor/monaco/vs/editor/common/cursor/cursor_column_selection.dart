/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/cursor/cursorColumnSelection.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971. Works on model lines (there is
// no view model / wrapped-line projection); results are Selections instead of
// SingleCursorStates. columnSelectUp/Down take the page size explicitly.

import '../core/position.dart';
import '../core/selection.dart';
import 'cursor_common.dart';

class ColumnSelectResult {
  const ColumnSelectResult(
    this.selections,
    this.reversed,
    this.fromLineNumber,
    this.fromVisualColumn,
    this.toLineNumber,
    this.toVisualColumn,
  );

  final List<Selection> selections;
  final bool reversed;
  final int fromLineNumber;
  final int fromVisualColumn;
  final int toLineNumber;
  final int toVisualColumn;
}

abstract final class ColumnSelection {
  static ColumnSelectResult columnSelect(
    CursorConfiguration config,
    ICursorSimpleModel model,
    int fromLineNumber,
    int fromVisibleColumn,
    int toLineNumber,
    int toVisibleColumn,
  ) {
    final lineCount = (toLineNumber - fromLineNumber).abs() + 1;
    final reversed = fromLineNumber > toLineNumber;
    final isRTL = fromVisibleColumn > toVisibleColumn;
    final isLTR = fromVisibleColumn < toVisibleColumn;
    final result = <Selection>[];
    for (var i = 0; i < lineCount; i++) {
      final lineNumber = fromLineNumber + (reversed ? -i : i);
      final startColumn = config.columnFromVisibleColumn(
        model,
        lineNumber,
        fromVisibleColumn,
      );
      final endColumn = config.columnFromVisibleColumn(
        model,
        lineNumber,
        toVisibleColumn,
      );
      final visibleStartColumn = config.visibleColumnFromColumn(
        model,
        Position(lineNumber, startColumn),
      );
      final visibleEndColumn = config.visibleColumnFromColumn(
        model,
        Position(lineNumber, endColumn),
      );
      if (isLTR) {
        if (visibleStartColumn > toVisibleColumn) continue;
        if (visibleEndColumn < fromVisibleColumn) continue;
      }
      if (isRTL) {
        if (visibleEndColumn > fromVisibleColumn) continue;
        if (visibleStartColumn < toVisibleColumn) continue;
      }
      result.add(Selection(lineNumber, startColumn, lineNumber, endColumn));
    }
    if (result.isEmpty) {
      // We are after all the lines, so add cursor at the end of each line
      for (var i = 0; i < lineCount; i++) {
        final lineNumber = fromLineNumber + (reversed ? -i : i);
        final maxColumn = model.getLineMaxColumn(lineNumber);
        result.add(Selection(lineNumber, maxColumn, lineNumber, maxColumn));
      }
    }
    return ColumnSelectResult(
      result,
      reversed,
      fromLineNumber,
      fromVisibleColumn,
      toLineNumber,
      toVisibleColumn,
    );
  }

  static ColumnSelectResult columnSelectLeft(
    CursorConfiguration config,
    ICursorSimpleModel model,
    ColumnSelectResult prev,
  ) {
    var toVisualColumn = prev.toVisualColumn;
    if (toVisualColumn > 0) toVisualColumn--;
    return columnSelect(
      config,
      model,
      prev.fromLineNumber,
      prev.fromVisualColumn,
      prev.toLineNumber,
      toVisualColumn,
    );
  }

  static ColumnSelectResult columnSelectRight(
    CursorConfiguration config,
    ICursorSimpleModel model,
    ColumnSelectResult prev,
  ) {
    var maxVisualColumn = 0;
    final minLine = prev.fromLineNumber < prev.toLineNumber
        ? prev.fromLineNumber
        : prev.toLineNumber;
    final maxLine = prev.fromLineNumber < prev.toLineNumber
        ? prev.toLineNumber
        : prev.fromLineNumber;
    for (var lineNumber = minLine; lineNumber <= maxLine; lineNumber++) {
      final visual = config.visibleColumnFromColumn(
        model,
        Position(lineNumber, model.getLineMaxColumn(lineNumber)),
      );
      if (visual > maxVisualColumn) maxVisualColumn = visual;
    }
    var toVisualColumn = prev.toVisualColumn;
    if (toVisualColumn < maxVisualColumn) toVisualColumn++;
    return columnSelect(
      config,
      model,
      prev.fromLineNumber,
      prev.fromVisualColumn,
      prev.toLineNumber,
      toVisualColumn,
    );
  }

  static ColumnSelectResult columnSelectUp(
    CursorConfiguration config,
    ICursorSimpleModel model,
    ColumnSelectResult prev, [
    int linesCount = 1,
  ]) {
    final toLineNumber = prev.toLineNumber - linesCount < 1
        ? 1
        : prev.toLineNumber - linesCount;
    return columnSelect(
      config,
      model,
      prev.fromLineNumber,
      prev.fromVisualColumn,
      toLineNumber,
      prev.toVisualColumn,
    );
  }

  static ColumnSelectResult columnSelectDown(
    CursorConfiguration config,
    ICursorSimpleModel model,
    ColumnSelectResult prev, [
    int linesCount = 1,
  ]) {
    final lineCount = model.getLineCount();
    final toLineNumber = prev.toLineNumber + linesCount > lineCount
        ? lineCount
        : prev.toLineNumber + linesCount;
    return columnSelect(
      config,
      model,
      prev.fromLineNumber,
      prev.fromVisualColumn,
      toLineNumber,
      prev.toVisualColumn,
    );
  }
}
