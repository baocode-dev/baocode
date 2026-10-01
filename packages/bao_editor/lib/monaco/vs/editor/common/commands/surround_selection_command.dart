/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/editor/common/commands/surroundSelectionCommand.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971. Composition handling
// (CompositionSurroundSelectionCommand) is not part of this subset.

import '../core/edit_operation.dart';
import '../core/position.dart';
import '../core/range.dart';
import '../core/selection.dart';
import '../model/piece_tree_text_buffer/piece_tree_text_buffer.dart';
import 'text_command.dart';

class SurroundSelectionCommand extends TextCommand {
  SurroundSelectionCommand(
    this.selection,
    this.charBeforeSelection,
    this.charAfterSelection,
  ) {
    if (charBeforeSelection.contains(RegExp(r'\r|\n')) ||
        charAfterSelection.contains(RegExp(r'\r|\n'))) {
      throw ArgumentError('Surround delimiters must be single-line');
    }
  }

  final Selection selection;
  final String charBeforeSelection;
  final String charAfterSelection;

  @override
  List<ISingleEditOperation> getEditOperations(PieceTreeTextBuffer model) => [
    EditOperation.insert(selection.getStartPosition(), charBeforeSelection),
    // Upstream sends null for the empty suffix because the tracked operation
    // builder otherwise drops it, breaking cursor-state computation.
    EditOperation.replace(
      Range.fromPositions(selection.getEndPosition()),
      charAfterSelection.isEmpty ? null : charAfterSelection,
    ),
  ];

  @override
  Selection computeCursorState(CommandCursorState state) {
    final ranges = state.inverseEditRanges;
    if (ranges.length == 1) {
      if (charBeforeSelection.isEmpty) {
        return Selection.fromPositions(
          selection.getStartPosition(),
          ranges.single.getStartPosition(),
        );
      }
      final cursor = ranges.single.getEndPosition();
      return Selection.fromPositions(
        cursor,
        Position(
          selection.endLineNumber,
          selection.endColumn + charBeforeSelection.length,
        ),
      );
    }
    return Selection(
      ranges[0].endLineNumber,
      ranges[0].endColumn,
      ranges[1].endLineNumber,
      ranges[1].endColumn - charAfterSelection.length,
    );
  }
}
