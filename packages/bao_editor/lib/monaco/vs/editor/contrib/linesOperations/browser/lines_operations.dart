/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Adapted from VS Code src/vs/editor/contrib/linesOperations/browser/
// {linesOperations,moveLinesCommand,copyLinesCommand}.ts and
// common/cursor/cursorMoveCommands.ts (expandLineSelection) at
// 6a598d4a13031703d483d103c1d934a36ad27971. `joinLines` ports
// `JoinLinesAction.run`; `CopyLineDownCommand` is `CopyLinesCommand`
// copying an empty selection's line down (for `DuplicateSelectionAction`).
//
// Deviations:
// - Every operation returns all edits plus the post-edit selections (like
//   `editor.executeEdits(edits, cursorState)`), instead of per-cursor
//   ICommands with tracked selections.
// - Move/copy lines first merge selections that touch the same lines into
//   blocks (upstream runs one command per selection and drops conflicting
//   ones); moveLines does not re-indent the moved lines with indentation
//   rules (upstream `editor.autoIndent: full` + indentRules).
// - Edits join lines with '\n'; the executor converts it to the document EOL.

import '../../../common/commands/cursor_command.dart';
import '../../../common/core/range.dart';
import '../../../common/core/selection.dart';
import '../../../common/cursor/cursor_common.dart';

class LinesEditResult {
  const LinesEditResult(this.edits, this.selections);

  /// Edits in pre-edit coordinates.
  final List<CursorCommandEdit> edits;

  /// Resulting selections in post-edit coordinates (columns are clamped by
  /// the executor), primary first.
  final List<Selection> selections;
}

class _Block {
  _Block(this.start, this.end, this.members);

  int start;
  int end;
  final List<int> members;
}

/// Groups selection line spans (a selection ending at column 1 of a later
/// line excludes that line) into sorted blocks. Blocks merge when they
/// overlap, or also when adjacent if [mergeAdjacent].
List<_Block> _blocks(
  List<Selection> selections, {
  required bool mergeAdjacent,
}) {
  final spans = <_Block>[];
  for (var i = 0; i < selections.length; i++) {
    final s = selections[i];
    var end = s.endLineNumber;
    if (s.startLineNumber < s.endLineNumber && s.endColumn == 1) end--;
    spans.add(_Block(s.startLineNumber, end, [i]));
  }
  spans.sort((a, b) => a.start.compareTo(b.start));
  final result = <_Block>[];
  for (final span in spans) {
    final last = result.isEmpty ? null : result.last;
    if (last != null &&
        (mergeAdjacent ? last.end + 1 >= span.start : last.end >= span.start)) {
      if (span.end > last.end) last.end = span.end;
      last.members.addAll(span.members);
    } else {
      result.add(span);
    }
  }
  return result;
}

String _linesText(ICursorSimpleModel model, int start, int end) =>
    [for (var line = start; line <= end; line++) model.getLineContent(line)]
        .join('\n');

Selection _shift(Selection s, int lines) => Selection(
  s.selectionStartLineNumber + lines,
  s.selectionStartColumn,
  s.positionLineNumber + lines,
  s.positionColumn,
);

abstract final class LinesOperations {
  /// editor.action.moveLinesUpAction / moveLinesDownAction.
  static LinesEditResult moveLines(
    ICursorSimpleModel model,
    List<Selection> selections, {
    required bool down,
  }) {
    final lineCount = model.getLineCount();
    final edits = <CursorCommandEdit>[];
    final result = List<Selection>.of(selections);
    for (final block in _blocks(selections, mergeAdjacent: true)) {
      if (down ? block.end >= lineCount : block.start <= 1) continue;
      if (down) {
        final moving = block.end + 1;
        edits
          ..add(
            CursorCommandEdit(
              Range(block.start, 1, block.start, 1),
              '${model.getLineContent(moving)}\n',
            ),
          )
          ..add(
            CursorCommandEdit(
              Range(
                block.end,
                model.getLineMaxColumn(block.end),
                moving,
                model.getLineMaxColumn(moving),
              ),
              '',
            ),
          );
      } else {
        final moving = block.start - 1;
        edits
          ..add(CursorCommandEdit(Range(moving, 1, block.start, 1), ''))
          ..add(
            CursorCommandEdit(
              Range(
                block.end,
                model.getLineMaxColumn(block.end),
                block.end,
                model.getLineMaxColumn(block.end),
              ),
              '\n${model.getLineContent(moving)}',
            ),
          );
      }
      for (final i in block.members) {
        result[i] = _shift(selections[i], down ? 1 : -1);
      }
    }
    return LinesEditResult(edits, result);
  }

  /// editor.action.copyLinesUpAction / copyLinesDownAction.
  static LinesEditResult copyLines(
    ICursorSimpleModel model,
    List<Selection> selections, {
    required bool down,
  }) {
    final edits = <CursorCommandEdit>[];
    final result = List<Selection>.of(selections);
    var inserted = 0;
    for (final block in _blocks(selections, mergeAdjacent: false)) {
      final text = _linesText(model, block.start, block.end);
      final count = block.end - block.start + 1;
      if (down) {
        edits.add(
          CursorCommandEdit(Range(block.start, 1, block.start, 1), '$text\n'),
        );
      } else {
        final maxColumn = model.getLineMaxColumn(block.end);
        edits.add(
          CursorCommandEdit(
            Range(block.end, maxColumn, block.end, maxColumn),
            '\n$text',
          ),
        );
      }
      for (final i in block.members) {
        result[i] = _shift(selections[i], inserted + (down ? count : 0));
      }
      inserted += count;
    }
    return LinesEditResult(edits, result);
  }

  /// editor.action.deleteLines.
  static LinesEditResult? deleteLines(
    ICursorSimpleModel model,
    List<Selection> selections,
  ) {
    if (model.getLineCount() == 1 && model.getLineMaxColumn(1) == 1) {
      // Model is empty
      return null;
    }
    final ops =
        [
          for (final s in selections)
            (
              start: s.startLineNumber,
              end: s.startLineNumber < s.endLineNumber && s.endColumn == 1
                  ? s.endLineNumber - 1
                  : s.endLineNumber,
              positionColumn: s.positionColumn,
            ),
        ]..sort(
          (a, b) => a.start == b.start
              ? a.end.compareTo(b.end)
              : a.start.compareTo(b.start),
        );
    // Merge delete operations which are adjacent or overlapping
    final merged = <({int start, int end, int positionColumn})>[];
    var previous = ops.first;
    for (var i = 1; i < ops.length; i++) {
      if (previous.end + 1 >= ops[i].start) {
        previous = (
          start: previous.start,
          end: ops[i].end,
          positionColumn: previous.positionColumn,
        );
      } else {
        merged.add(previous);
        previous = ops[i];
      }
    }
    merged.add(previous);
    var linesDeleted = 0;
    final edits = <CursorCommandEdit>[];
    final cursorState = <Selection>[];
    for (final op in merged) {
      var startLineNumber = op.start;
      var endLineNumber = op.end;
      var startColumn = 1;
      var endColumn = model.getLineMaxColumn(endLineNumber);
      if (endLineNumber < model.getLineCount()) {
        endLineNumber += 1;
        endColumn = 1;
      } else if (startLineNumber > 1) {
        startLineNumber -= 1;
        startColumn = model.getLineMaxColumn(startLineNumber);
      }
      edits.add(
        CursorCommandEdit(
          Range(startLineNumber, startColumn, endLineNumber, endColumn),
          '',
        ),
      );
      cursorState.add(
        Selection(
          startLineNumber - linesDeleted,
          op.positionColumn,
          startLineNumber - linesDeleted,
          op.positionColumn,
        ),
      );
      linesDeleted += op.end - op.start + 1;
    }
    return LinesEditResult(edits, cursorState);
  }

  /// editor.action.joinLines: joins each selection's lines (an empty or
  /// one-line selection's line with the next) into one, separated by a
  /// space, without the joined lines' indentation. [selections] are primary
  /// first; the result's selections are too.
  static LinesEditResult? joinLines(
    ICursorSimpleModel model,
    List<Selection> selections,
  ) {
    if (selections.isEmpty) return null;
    var primaryCursor = selections.first;
    final sorted = [...selections]..sort(Range.compareRangesUsingStarts);
    final reducedSelections = <Selection>[];
    var previousValue = sorted.first;
    for (final currentValue in sorted.skip(1)) {
      if (previousValue.isEmpty()) {
        if (previousValue.endLineNumber == currentValue.startLineNumber) {
          if (primaryCursor.equalsSelection(previousValue)) {
            primaryCursor = currentValue;
          }
          previousValue = currentValue;
        } else if (currentValue.startLineNumber >
            previousValue.endLineNumber + 1) {
          reducedSelections.add(previousValue);
          previousValue = currentValue;
        } else {
          previousValue = Selection(
            previousValue.startLineNumber,
            previousValue.startColumn,
            currentValue.endLineNumber,
            currentValue.endColumn,
          );
        }
      } else if (currentValue.startLineNumber > previousValue.endLineNumber) {
        reducedSelections.add(previousValue);
        previousValue = currentValue;
      } else {
        previousValue = Selection(
          previousValue.startLineNumber,
          previousValue.startColumn,
          currentValue.endLineNumber,
          currentValue.endColumn,
        );
      }
    }
    reducedSelections.add(previousValue);

    final edits = <CursorCommandEdit>[];
    final endCursorState = <Selection>[];
    var endPrimaryCursor = primaryCursor;
    var lineOffset = 0;
    for (final selection in reducedSelections) {
      final startLineNumber = selection.startLineNumber;
      const startColumn = 1;
      var columnDeltaOffset = 0;
      int endLineNumber;
      int endColumn;
      final selectionEndPositionOffset =
          model.getLineMaxColumn(selection.endLineNumber) -
          1 -
          selection.endColumn;
      if (selection.isEmpty() ||
          selection.startLineNumber == selection.endLineNumber) {
        final position = selection.getStartPosition();
        if (position.lineNumber < model.getLineCount()) {
          endLineNumber = startLineNumber + 1;
          endColumn = model.getLineMaxColumn(endLineNumber);
        } else {
          endLineNumber = position.lineNumber;
          endColumn = model.getLineMaxColumn(position.lineNumber);
        }
      } else {
        endLineNumber = selection.endLineNumber;
        endColumn = model.getLineMaxColumn(endLineNumber);
      }

      var trimmedLinesContent = model.getLineContent(startLineNumber);
      for (var i = startLineNumber + 1; i <= endLineNumber; i++) {
        final lineText = model.getLineContent(i);
        final firstNonWhitespaceIdx = model.getLineFirstNonWhitespaceColumn(i);
        if (firstNonWhitespaceIdx >= 1) {
          var insertSpace = trimmedLinesContent.isNotEmpty;
          if (insertSpace &&
              (trimmedLinesContent.endsWith(' ') ||
                  trimmedLinesContent.endsWith('\t'))) {
            insertSpace = false;
            trimmedLinesContent = trimmedLinesContent.replaceAll(
              _trailingWhitespace,
              ' ',
            );
          }
          final lineTextWithoutIndent = lineText.substring(
            firstNonWhitespaceIdx - 1,
          );
          trimmedLinesContent +=
              (insertSpace ? ' ' : '') + lineTextWithoutIndent;
          columnDeltaOffset = insertSpace
              ? lineTextWithoutIndent.length + 1
              : lineTextWithoutIndent.length;
        } else {
          columnDeltaOffset = 0;
        }
      }

      final deleteSelection = Range(
        startLineNumber,
        startColumn,
        endLineNumber,
        endColumn,
      );
      if (!deleteSelection.isEmpty()) {
        edits.add(CursorCommandEdit(deleteSelection, trimmedLinesContent));
        final Selection resultSelection;
        if (selection.isEmpty()) {
          final column = trimmedLinesContent.length - columnDeltaOffset + 1;
          resultSelection = Selection(
            deleteSelection.startLineNumber - lineOffset,
            column,
            startLineNumber - lineOffset,
            column,
          );
        } else if (selection.startLineNumber == selection.endLineNumber) {
          resultSelection = Selection(
            selection.startLineNumber - lineOffset,
            selection.startColumn,
            selection.endLineNumber - lineOffset,
            selection.endColumn,
          );
        } else {
          resultSelection = Selection(
            selection.startLineNumber - lineOffset,
            selection.startColumn,
            selection.startLineNumber - lineOffset,
            trimmedLinesContent.length - selectionEndPositionOffset,
          );
        }
        if (Range.intersectTwoRanges(deleteSelection, primaryCursor) != null) {
          endPrimaryCursor = resultSelection;
        } else {
          endCursorState.add(resultSelection);
        }
      }
      lineOffset +=
          deleteSelection.endLineNumber - deleteSelection.startLineNumber;
    }
    if (edits.isEmpty) return null;
    return LinesEditResult(edits, [endPrimaryCursor, ...endCursorState]);
  }

  static final _trailingWhitespace = RegExp(r'[\s\uFEFF\xA0]+$');

  /// expandLineSelection: select the full lines of each selection, then one
  /// more line on every repeat.
  static List<Selection> expandLineSelection(
    ICursorSimpleModel model,
    List<Selection> selections,
  ) {
    final lineCount = model.getLineCount();
    return [
      for (final s in selections)
        s.endLineNumber == lineCount
            ? Selection(
                s.startLineNumber,
                1,
                lineCount,
                model.getLineMaxColumn(lineCount),
              )
            : Selection(s.startLineNumber, 1, s.endLineNumber + 1, 1),
    ];
  }

  /// editor.action.deleteAllLeft: deletes from each cursor to the start of
  /// its line (or the selection).
  static List<Range> deleteAllLeftRanges(
    ICursorSimpleModel model,
    List<Selection> selections,
  ) => [
    for (final s in selections)
      if (!s.isEmpty())
        s
      else if (s.positionColumn > 1)
        Range(s.positionLineNumber, 1, s.positionLineNumber, s.positionColumn)
      else if (s.positionLineNumber > 1)
        Range(
          s.positionLineNumber - 1,
          model.getLineMaxColumn(s.positionLineNumber - 1),
          s.positionLineNumber,
          1,
        ),
  ];

  /// editor.action.deleteAllRight.
  static List<Range> deleteAllRightRanges(
    ICursorSimpleModel model,
    List<Selection> selections,
  ) => [
    for (final s in selections)
      if (!s.isEmpty())
        s
      else if (s.positionColumn < model.getLineMaxColumn(s.positionLineNumber))
        Range(
          s.positionLineNumber,
          s.positionColumn,
          s.positionLineNumber,
          model.getLineMaxColumn(s.positionLineNumber),
        )
      else if (s.positionLineNumber < model.getLineCount())
        Range(
          s.positionLineNumber,
          s.positionColumn,
          s.positionLineNumber + 1,
          1,
        ),
  ];
}

/// `CopyLinesCommand` copying down for the empty [selection]: inserts a copy
/// of its line above it; the cursor keeps its column on the lower copy.
class CopyLineDownCommand extends CursorCommand {
  CopyLineDownCommand(this.selection);

  final Selection selection;

  @override
  List<CursorCommandEdit> getEditOperations(ICursorSimpleModel model) {
    final line = selection.positionLineNumber;
    return [
      CursorCommandEdit(
        Range(line, 1, line, 1),
        '${model.getLineContent(line)}\n',
      ),
    ];
  }

  @override
  Selection computeCursorState(
    ICursorSimpleModel model,
    CursorStateComputerData helper,
  ) {
    final line = helper.getInverseEditOperations().first.endLineNumber;
    final column = selection.positionColumn;
    return Selection(line, column, line, column);
  }
}
