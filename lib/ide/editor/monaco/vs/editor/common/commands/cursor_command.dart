/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Local adapter for the ICommand / IEditOperationBuilder /
// ICursorStateComputerData contract in VS Code
// src/vs/editor/common/editorCommon.ts, plus the ReplaceCommand family from
// src/vs/editor/common/commands/replaceCommand.ts and
// surroundSelectionCommand.ts, at 6a598d4a13031703d483d103c1d934a36ad27971.
//
// Unlike text_command.dart (which executes against a piece-tree buffer),
// these commands only describe edits over an [ICursorSimpleModel]; the
// Flutter controller executes all cursors' commands as one batch. There is no
// marker layer: a tracked selection is mapped through the batch by offsets,
// approximating upstream's tracked-range stickiness (see the executor).
// Edit text uses '\n'; the executor converts it to the document EOL, as the
// upstream text model does.

import '../core/position.dart';
import '../core/range.dart';
import '../core/selection.dart';
import '../cursor/cursor_common.dart';

/// One replacement, in pre-edit coordinates.
class CursorCommandEdit {
  const CursorCommandEdit(this.range, this.text);

  final Range range;
  final String text;
}

/// Post-edit data a command uses to compute its resulting selection.
abstract interface class CursorStateComputerData {
  /// The post-edit ranges of the command's own edits, in the order they were
  /// returned by [CursorCommand.getEditOperations].
  List<Range> getInverseEditOperations();

  /// [CursorCommand.selectionToTrack] mapped through every edit of the batch.
  Selection getTrackedSelection();
}

abstract class CursorCommand {
  List<CursorCommandEdit> getEditOperations(ICursorSimpleModel model);

  /// Upstream `builder.trackSelection(selection, trackPreviousOnEmpty)`.
  Selection? get selectionToTrack => null;

  /// For an empty tracked selection: true keeps it before text inserted at
  /// it, false moves it after; null uses upstream's default (before only at
  /// the end of a line).
  bool? get trackPreviousOnEmpty => null;

  /// [model] is the post-edit document.
  Selection computeCursorState(
    ICursorSimpleModel model,
    CursorStateComputerData helper,
  );
}

class ReplaceCommand extends CursorCommand {
  ReplaceCommand(this.range, this.text, {this.insertsAutoWhitespace = false});

  final Range range;
  final String text;
  final bool insertsAutoWhitespace;

  @override
  List<CursorCommandEdit> getEditOperations(ICursorSimpleModel model) => [
    CursorCommandEdit(range, text),
  ];

  @override
  Selection computeCursorState(
    ICursorSimpleModel model,
    CursorStateComputerData helper,
  ) {
    final srcRange = helper.getInverseEditOperations().first;
    return Selection(
      srcRange.endLineNumber,
      srcRange.endColumn,
      srcRange.endLineNumber,
      srcRange.endColumn,
    );
  }
}

class ReplaceCommandWithoutChangingPosition extends ReplaceCommand {
  ReplaceCommandWithoutChangingPosition(
    super.range,
    super.text, {
    super.insertsAutoWhitespace,
  });

  @override
  Selection computeCursorState(
    ICursorSimpleModel model,
    CursorStateComputerData helper,
  ) {
    final srcRange = helper.getInverseEditOperations().first;
    return Selection(
      srcRange.startLineNumber,
      srcRange.startColumn,
      srcRange.startLineNumber,
      srcRange.startColumn,
    );
  }
}

class ReplaceCommandWithOffsetCursorState extends ReplaceCommand {
  ReplaceCommandWithOffsetCursorState(
    super.range,
    super.text,
    this.lineNumberDeltaOffset,
    this.columnDeltaOffset, {
    super.insertsAutoWhitespace,
  });

  final int lineNumberDeltaOffset;
  final int columnDeltaOffset;

  @override
  Selection computeCursorState(
    ICursorSimpleModel model,
    CursorStateComputerData helper,
  ) {
    final srcRange = helper.getInverseEditOperations().first;
    final line = srcRange.endLineNumber + lineNumberDeltaOffset;
    final column = srcRange.endColumn + columnDeltaOffset;
    return Selection(line, column, line, column);
  }
}

class ReplaceCommandThatSelectsText extends ReplaceCommand {
  ReplaceCommandThatSelectsText(super.range, super.text);

  @override
  Selection computeCursorState(
    ICursorSimpleModel model,
    CursorStateComputerData helper,
  ) {
    final srcRange = helper.getInverseEditOperations().first;
    return Selection.fromRange(srcRange, SelectionDirection.ltr);
  }
}

class ReplaceCommandThatPreservesSelection extends ReplaceCommand {
  ReplaceCommandThatPreservesSelection(
    super.range,
    super.text,
    this.initialSelection,
  );

  final Selection initialSelection;

  @override
  Selection? get selectionToTrack => initialSelection;

  @override
  Selection computeCursorState(
    ICursorSimpleModel model,
    CursorStateComputerData helper,
  ) => helper.getTrackedSelection();
}

/// Keeps a selection unchanged (tracked through other cursors' edits).
class NoopCursorCommand extends CursorCommand {
  NoopCursorCommand(this.selection);

  final Selection selection;

  @override
  List<CursorCommandEdit> getEditOperations(ICursorSimpleModel model) =>
      const [];

  @override
  Selection? get selectionToTrack => selection;

  @override
  Selection computeCursorState(
    ICursorSimpleModel model,
    CursorStateComputerData helper,
  ) => helper.getTrackedSelection();
}

/// surroundSelectionCommand.ts: wraps [selection] with [charBeforeSelection]
/// and [charAfterSelection], keeping the inner text selected.
class SurroundSelectionCursorCommand extends CursorCommand {
  SurroundSelectionCursorCommand(
    this.selection,
    this.charBeforeSelection,
    this.charAfterSelection,
  );

  final Selection selection;
  final String charBeforeSelection;
  final String charAfterSelection;

  @override
  List<CursorCommandEdit> getEditOperations(ICursorSimpleModel model) => [
    CursorCommandEdit(
      Range(
        selection.startLineNumber,
        selection.startColumn,
        selection.startLineNumber,
        selection.startColumn,
      ),
      charBeforeSelection,
    ),
    CursorCommandEdit(
      Range(
        selection.endLineNumber,
        selection.endColumn,
        selection.endLineNumber,
        selection.endColumn,
      ),
      charAfterSelection,
    ),
  ];

  @override
  Selection computeCursorState(
    ICursorSimpleModel model,
    CursorStateComputerData helper,
  ) {
    final ops = helper.getInverseEditOperations();
    final firstOperationRange = ops[0];
    final secondOperationRange = ops[1];
    return Selection(
      firstOperationRange.endLineNumber,
      firstOperationRange.endColumn,
      secondOperationRange.endLineNumber,
      secondOperationRange.endColumn - charAfterSelection.length,
    );
  }
}

/// Moves the cursor without editing, to [position]'s post-edit location.
Position clampPosition(ICursorSimpleModel model, Position position) {
  final line = position.lineNumber.clamp(1, model.getLineCount());
  return Position(
    line,
    position.column.clamp(
      model.getLineMinColumn(line),
      model.getLineMaxColumn(line),
    ),
  );
}
