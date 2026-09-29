/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Adapted from VS Code src/vs/editor/contrib/linesOperations/browser/
// {linesOperations,moveLinesCommand,copyLinesCommand}.ts and
// common/cursor/cursorMoveCommands.ts (expandLineSelection) at
// 6a598d4a13031703d483d103c1d934a36ad27971.
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
