/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Local adapter for the command contract in VS Code editorCommon.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971. This is NOT a port of
// IEditOperationBuilder, ICursorStateComputerData, or TextModel markers.

import '../core/edit_operation.dart';
import '../core/range.dart';
import '../core/selection.dart';
import '../model/piece_tree_text_buffer/piece_tree_text_buffer.dart';

/// The edits are in pre-edit coordinates; the selection is in post-edit coordinates.
class TextCommandResult {
  const TextCommandResult(this.operations, this.selection, this.undoEdits);

  final List<ISingleEditOperation> operations;
  final Selection selection;
  final List<ValidEditOperation> undoEdits;
}

class CommandCursorState {
  const CommandCursorState(this.inverseEditRanges, this.trackedSelection);

  /// The replacement spans in the edited document, in command edit order.
  final List<Range> inverseEditRanges;
  final Selection? trackedSelection;
}

/// Runs a command against a piece-tree document. Commands are single-use only
/// in upstream Monaco; here they are stateless and may be reused.
abstract class TextCommand {
  List<ISingleEditOperation> getEditOperations(PieceTreeTextBuffer model);

  /// Only used by commands that must retain their selection across edits.
  Selection? get selectionToTrack => null;

  Selection computeCursorState(CommandCursorState state);

  TextCommandResult execute(PieceTreeTextBuffer model) {
    final requested = getEditOperations(model);
    final operations = requested
        .where(
          (op) =>
              !Range.isEmptyRange(op.range) || (op.text?.isNotEmpty ?? false),
        )
        .toList();
    final selection = selectionToTrack;
    final anchor = selection == null
        ? null
        : model.getOffsetAt(
            selection.selectionStartLineNumber,
            selection.selectionStartColumn,
          );
    final active = selection == null
        ? null
        : model.getOffsetAt(
            selection.positionLineNumber,
            selection.positionColumn,
          );

    // No edits must not emit a buffer change event or create an undo entry.
    if (operations.isEmpty) {
      return TextCommandResult(
        operations,
        computeCursorState(
          CommandCursorState([
            for (final op in requested) Range.lift(op.range)!,
          ], selection),
        ),
        const [],
      );
    }
    for (final op in operations) {
      final range = op.range;
      for (final position in [
        Range.startPositionOf(range),
        Range.endPositionOf(range),
      ]) {
        if (position.lineNumber < 1 ||
            position.lineNumber > model.getLineCount() ||
            position.column < 1 ||
            position.column > model.getLineMaxColumn(position.lineNumber)) {
          throw RangeError('Edit position outside document: $position');
        }
      }
    }
    final result = model.applyEdits(
      [
        for (final op in operations)
          ValidAnnotatedEditOperation(
            null,
            Range.lift(op.range)!,
            op.text,
            forceMoveMarkers: op.forceMoveMarkers ?? false,
            isTracked: true,
          ),
      ],
      false,
      true,
    );
    final undoEdits = result.reverseEdits!;
    final changes = result.changes.toList()
      ..sort((a, b) => a.rangeOffset.compareTo(b.rangeOffset));
    int move(int offset, {required bool preferEnd}) {
      var delta = 0;
      for (final change in changes) {
        final start = change.rangeOffset;
        final end = start + change.rangeLength;
        if (offset < start || (offset == start && !preferEnd)) break;
        if (offset <= end) {
          return start + delta + (preferEnd ? change.text.length : 0);
        }
        delta += change.text.length - change.rangeLength;
      }
      return offset + delta;
    }

    Selection? tracked;
    if (selection != null) {
      // Nonempty selections stay anchored at an insertion boundary; a caret
      // moves after inserted text. This is an offset-based approximation of
      // upstream tracked selections (there is no marker layer in this port).
      final collapsed = selection.isEmpty();
      final start = anchor! <= active! ? anchor : active;
      final end = anchor <= active ? active : anchor;
      final mappedStart = model.getPositionAt(
        move(start, preferEnd: collapsed),
      );
      final mappedEnd = model.getPositionAt(move(end, preferEnd: true));
      tracked = Selection.fromPositions(
        anchor <= active ? mappedStart : mappedEnd,
        anchor <= active ? mappedEnd : mappedStart,
      );
    }
    // For touching operations applyEdits returns inverse edits in position
    // order. Their identifiers are null; these commands emit them in order.
    return TextCommandResult(
      operations,
      computeCursorState(
        CommandCursorState([for (final op in undoEdits) op.range], tracked),
      ),
      undoEdits,
    );
  }
}
