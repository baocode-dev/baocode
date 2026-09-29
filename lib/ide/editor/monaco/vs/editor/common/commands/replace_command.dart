/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/editor/common/commands/replaceCommand.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971.

import '../core/edit_operation.dart';
import '../core/range.dart';
import '../core/selection.dart';
import '../model/piece_tree_text_buffer/piece_tree_text_buffer.dart';
import 'text_command.dart';

/// Replaces a range and leaves the caret after the inserted text.
class ReplaceCommand extends TextCommand {
  ReplaceCommand(this.range, this.text, {this.insertsAutoWhitespace = false});

  final Range range;
  final String text;
  // Metadata for callers; auto-whitespace trimming is not supported here.
  final bool insertsAutoWhitespace;

  @override
  List<ISingleEditOperation> getEditOperations(PieceTreeTextBuffer model) => [
    EditOperation.replace(range, text),
  ];

  @override
  Selection computeCursorState(CommandCursorState state) =>
      Selection.fromPositions(state.inverseEditRanges.single.getEndPosition());
}

/// Replaces a range and selects the inserted text (always left-to-right).
class ReplaceCommandThatSelectsText extends ReplaceCommand {
  ReplaceCommandThatSelectsText(super.range, super.text);

  @override
  Selection computeCursorState(CommandCursorState state) => Selection.fromRange(
    state.inverseEditRanges.single,
    SelectionDirection.ltr,
  );
}

/// Replaces a range and leaves the caret at the beginning of the result.
class ReplaceCommandWithoutChangingPosition extends ReplaceCommand {
  ReplaceCommandWithoutChangingPosition(
    super.range,
    super.text, {
    super.insertsAutoWhitespace,
  });

  @override
  Selection computeCursorState(CommandCursorState state) =>
      Selection.fromPositions(
        state.inverseEditRanges.single.getStartPosition(),
      );
}

/// Positions the caret relative to the end of the inserted text.
/// Like upstream, the resulting position is NOT clamped to the document.
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
  Selection computeCursorState(CommandCursorState state) =>
      Selection.fromPositions(
        state.inverseEditRanges.single.getEndPosition().delta(
          lineNumberDeltaOffset,
          columnDeltaOffset,
        ),
      );
}
