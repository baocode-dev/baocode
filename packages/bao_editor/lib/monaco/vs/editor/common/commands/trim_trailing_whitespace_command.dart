/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Text-only path of VS Code src/vs/editor/common/commands/
// trimTrailingWhitespaceCommand.ts at 6a598d4a13031703d483d103c1d934a36ad27971.
// Token-aware trimming (trimInRegexesAndStrings=false) needs Monaco tokens
// and is deliberately not exposed. Whitespace classification follows the
// piece-tree model's space/tab indentation, not language-specific tokens.

import '../core/edit_operation.dart';
import '../core/position.dart';
import '../core/range.dart';
import '../core/selection.dart';
import '../model/piece_tree_text_buffer/piece_tree_text_buffer.dart';
import 'text_command.dart';

/// Generate trailing-space/tab deletions while preserving text at/after a caret.
/// A caret at the end of a line prevents trimming on that line entirely.
List<ISingleEditOperation> trimTrailingWhitespace(
  PieceTreeTextBuffer model,
  List<Position> cursors,
) {
  final sorted = List<Position>.of(cursors)..sort(Position.compare);
  final edits = <ISingleEditOperation>[];
  var cursorIndex = 0;
  for (var line = 1; line <= model.getLineCount(); line++) {
    final content = model.getLineContent(line);
    final maxColumn = content.length + 1;
    while (cursorIndex < sorted.length &&
        sorted[cursorIndex].lineNumber < line) {
      cursorIndex++;
    }
    var minColumn = 0;
    while (cursorIndex < sorted.length &&
        sorted[cursorIndex].lineNumber == line) {
      minColumn = sorted[cursorIndex++].column;
    }
    if (content.isEmpty || minColumn >= maxColumn) continue;
    var last = content.length - 1;
    while (last >= 0 &&
        (content.codeUnitAt(last) == 32 || content.codeUnitAt(last) == 9)) {
      last--;
    }
    final from = (last + 2).clamp(1, maxColumn);
    if (from == maxColumn) continue;
    final first = minColumn > from ? minColumn : from;
    edits.add(EditOperation.delete(Range(line, first, line, maxColumn)));
  }
  return edits;
}

class TrimTrailingWhitespaceCommand extends TextCommand {
  TrimTrailingWhitespaceCommand(this.selection, this.cursors);

  final Selection selection;
  final List<Position> cursors;

  @override
  Selection? get selectionToTrack => selection;

  @override
  List<ISingleEditOperation> getEditOperations(PieceTreeTextBuffer model) =>
      trimTrailingWhitespace(model, cursors);

  @override
  Selection computeCursorState(CommandCursorState state) =>
      state.trackedSelection!;
}
