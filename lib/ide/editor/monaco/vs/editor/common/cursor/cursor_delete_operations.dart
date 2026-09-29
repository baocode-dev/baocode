/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/cursor/cursorDeleteOperations.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971.
// Deviation: the character to the left/right is supplied by the caller
// ([PositionStep]); the Flutter controller deletes whole pinned graphemes
// (keeping CRLF atomic) where upstream's getLeftDeleteOffset deletes code
// points of combining sequences.

import '../commands/cursor_command.dart';
import '../core/cursor_columns.dart';
import '../core/position.dart';
import '../core/range.dart';
import '../core/selection.dart';
import 'cursor_common.dart';

typedef PositionStep = Position Function(Position position);

class DeleteResult {
  const DeleteResult(this.shouldPushStackElementBefore, this.commands);

  final bool shouldPushStackElementBefore;
  final List<CursorCommand?> commands;
}

abstract final class DeleteOperations {
  static DeleteResult deleteRight(
    EditOperationType prevEditOperationType,
    CursorConfiguration config,
    ICursorSimpleModel model,
    List<Selection> selections,
    PositionStep right,
  ) {
    final commands = <CursorCommand?>[];
    var shouldPushStackElementBefore =
        prevEditOperationType != EditOperationType.deletingRight;
    for (final selection in selections) {
      final deleteSelection = _getDeleteRightRange(
        selection,
        model,
        config,
        right,
      );
      if (deleteSelection.isEmpty()) {
        // Probably at end of file => ignore
        commands.add(null);
        continue;
      }
      if (deleteSelection.startLineNumber != deleteSelection.endLineNumber) {
        shouldPushStackElementBefore = true;
      }
      commands.add(ReplaceCommand(deleteSelection, ''));
    }
    return DeleteResult(shouldPushStackElementBefore, commands);
  }

  static Range _getDeleteRightRange(
    Selection selection,
    ICursorSimpleModel model,
    CursorConfiguration config,
    PositionStep right,
  ) {
    if (!selection.isEmpty()) return selection;
    final position = selection.getPosition();
    final rightOfPosition = right(position);
    if (config.trimWhitespaceOnDelete &&
        rightOfPosition.lineNumber != position.lineNumber) {
      final currentLineHasContent =
          model.getLineFirstNonWhitespaceColumn(position.lineNumber) > 0;
      final firstNonWhitespaceColumn = model.getLineFirstNonWhitespaceColumn(
        rightOfPosition.lineNumber,
      );
      if (currentLineHasContent && firstNonWhitespaceColumn > 0) {
        return Range(
          rightOfPosition.lineNumber,
          firstNonWhitespaceColumn,
          position.lineNumber,
          position.column,
        );
      }
    }
    return Range.fromPositions(position, rightOfPosition);
  }

  static bool isAutoClosingPairDelete(
    CursorConfiguration config,
    ICursorSimpleModel model,
    List<Selection> selections,
    List<Range> autoClosedCharacters,
  ) {
    if (config.language == null) return false;
    if (config.autoClosingBrackets == AutoClosingStrategy.never &&
        config.autoClosingQuotes == AutoClosingStrategy.never) {
      return false;
    }
    if (config.autoClosingDelete == AutoClosingEditStrategy.never) {
      return false;
    }
    final autoClosingPairsOpen =
        config.autoClosingPairs.autoClosingPairsOpenByEnd;
    for (final selection in selections) {
      final position = selection.getPosition();
      if (!selection.isEmpty()) return false;
      final lineText = model.getLineContent(position.lineNumber);
      if (position.column < 2 || position.column >= lineText.length + 1) {
        return false;
      }
      final character = lineText[position.column - 2];
      final candidates = autoClosingPairsOpen[character];
      if (candidates == null) return false;
      if (isQuote(character)) {
        if (config.autoClosingQuotes == AutoClosingStrategy.never) return false;
      } else {
        if (config.autoClosingBrackets == AutoClosingStrategy.never) {
          return false;
        }
      }
      final afterCharacter = lineText[position.column - 1];
      var foundAutoClosingPair = false;
      for (final candidate in candidates) {
        if (candidate.open == character && candidate.close == afterCharacter) {
          foundAutoClosingPair = true;
        }
      }
      if (!foundAutoClosingPair) return false;
      // Must delete the pair only if it was automatically inserted by the editor
      if (config.autoClosingDelete == AutoClosingEditStrategy.auto) {
        var found = false;
        for (final autoClosed in autoClosedCharacters) {
          if (position.lineNumber == autoClosed.startLineNumber &&
              position.column == autoClosed.startColumn) {
            found = true;
            break;
          }
        }
        if (!found) return false;
      }
    }
    return true;
  }

  static DeleteResult deleteLeft(
    EditOperationType prevEditOperationType,
    CursorConfiguration config,
    ICursorSimpleModel model,
    List<Selection> selections,
    List<Range> autoClosedCharacters,
    PositionStep left,
  ) {
    if (isAutoClosingPairDelete(
      config,
      model,
      selections,
      autoClosedCharacters,
    )) {
      return DeleteResult(true, [
        for (final selection in selections)
          ReplaceCommand(
            Range(
              selection.positionLineNumber,
              selection.positionColumn - 1,
              selection.positionLineNumber,
              selection.positionColumn + 1,
            ),
            '',
          ),
      ]);
    }
    final commands = <CursorCommand?>[];
    var shouldPushStackElementBefore =
        prevEditOperationType != EditOperationType.deletingLeft;
    for (final selection in selections) {
      final deleteRange = _getDeleteLeftRange(selection, model, config, left);
      // Ignore empty delete ranges, as they have no effect. They happen if
      // the cursor is at the beginning of the file.
      if (deleteRange.isEmpty()) {
        commands.add(null);
        continue;
      }
      if (deleteRange.startLineNumber != deleteRange.endLineNumber) {
        shouldPushStackElementBefore = true;
      }
      commands.add(ReplaceCommand(deleteRange, ''));
    }
    return DeleteResult(shouldPushStackElementBefore, commands);
  }

  static Range _getDeleteLeftRange(
    Selection selection,
    ICursorSimpleModel model,
    CursorConfiguration config,
    PositionStep left,
  ) {
    if (!selection.isEmpty()) return selection;
    final position = selection.getPosition();
    // Unindent when using tab stops and cursor is within indentation
    if (config.useTabStops && position.column > 1) {
      final lineContent = model.getLineContent(position.lineNumber);
      final firstNonWhitespace = firstNonWhitespaceIndex(lineContent);
      final lastIndentationColumn = firstNonWhitespace == -1
          ? lineContent.length + 1
          : firstNonWhitespace + 1;
      if (position.column <= lastIndentationColumn) {
        final fromVisibleColumn = config.visibleColumnFromColumn(
          model,
          position,
        );
        final toVisibleColumn = CursorColumns.prevIndentTabStop(
          fromVisibleColumn,
          config.indentSize,
        );
        final toColumn = config.columnFromVisibleColumn(
          model,
          position.lineNumber,
          toVisibleColumn,
        );
        return Range(
          position.lineNumber,
          toColumn,
          position.lineNumber,
          position.column,
        );
      }
    }
    return Range.fromPositions(left(position), position);
  }

  /// Ranges removed by a cut; an empty selection cuts its whole line.
  static List<Range?> cut(
    CursorConfiguration config,
    ICursorSimpleModel model,
    List<Selection> selections,
  ) {
    final result = List<Range?>.filled(selections.length, null);
    Range? lastCutRange;
    final order = List<int>.generate(selections.length, (i) => i)
      ..sort(
        (a, b) => Position.compare(
          selections[a].getStartPosition(),
          selections[b].getEndPosition(),
        ),
      );
    for (final i in order) {
      final selection = selections[i];
      if (selection.isEmpty()) {
        if (!config.emptySelectionClipboard) continue;
        // This is a full line cut
        final position = selection.getPosition();
        Range deleteSelection;
        if (position.lineNumber < model.getLineCount()) {
          // Cutting a line in the middle of the model
          deleteSelection = Range(
            position.lineNumber,
            1,
            position.lineNumber + 1,
            1,
          );
        } else if (position.lineNumber > 1 &&
            lastCutRange?.endLineNumber != position.lineNumber) {
          // Cutting the last line & there are more than 1 lines in the model
          deleteSelection = Range(
            position.lineNumber - 1,
            model.getLineMaxColumn(position.lineNumber - 1),
            position.lineNumber,
            model.getLineMaxColumn(position.lineNumber),
          );
        } else {
          // Cutting the single line that the model contains
          deleteSelection = Range(
            position.lineNumber,
            1,
            position.lineNumber,
            model.getLineMaxColumn(position.lineNumber),
          );
        }
        lastCutRange = deleteSelection;
        if (!deleteSelection.isEmpty()) result[i] = deleteSelection;
      } else {
        result[i] = selection;
      }
    }
    return result;
  }
}
