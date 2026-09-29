/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Text-only subset of VS Code src/vs/editor/common/commands/shiftCommand.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971. The upstream autoIndent /
// enter-action tokenization branch and tracked marker affinities are omitted.

import '../core/cursor_columns.dart';
import '../core/edit_operation.dart';
import '../core/range.dart';
import '../core/selection.dart';
import '../model/piece_tree_text_buffer/piece_tree_text_buffer.dart';
import '../cursor/cursor_common.dart';
import 'cursor_command.dart';
import 'text_command.dart';

class ShiftCommandOptions {
  const ShiftCommandOptions({
    required this.isUnshift,
    required this.tabSize,
    required this.indentSize,
    required this.insertSpaces,
    required this.useTabStops,
  }) : assert(tabSize > 0),
       assert(indentSize > 0);

  final bool isUnshift;
  final int tabSize;
  final int indentSize;
  final bool insertSpaces;
  final bool useTabStops;
}

class ShiftCommand extends TextCommand {
  ShiftCommand(this.selection, this.options) {
    if (options.tabSize <= 0 || options.indentSize <= 0) {
      throw ArgumentError('tabSize and indentSize must be positive');
    }
  }

  final Selection selection;
  final ShiftCommandOptions options;
  int? _startColumnToPreserve;
  bool _caretOnWhitespaceOnlyLine = false;

  static String shiftIndent(
    String line,
    int column,
    int tabSize,
    int indentSize,
    bool insertSpaces,
  ) {
    final visible = CursorColumns.visibleColumnFromColumn(
      line,
      column,
      tabSize,
    );
    final width = insertSpaces ? indentSize : tabSize;
    final stop = CursorColumns.nextRenderTabStop(visible, width);
    return (insertSpaces ? ' ' * indentSize : '\t') * (stop ~/ width);
  }

  static String unshiftIndent(
    String line,
    int column,
    int tabSize,
    int indentSize,
    bool insertSpaces,
  ) {
    final visible = CursorColumns.visibleColumnFromColumn(
      line,
      column,
      tabSize,
    );
    final width = insertSpaces ? indentSize : tabSize;
    final stop = CursorColumns.prevRenderTabStop(visible, width);
    return (insertSpaces ? ' ' * indentSize : '\t') * (stop ~/ width);
  }

  @override
  Selection? get selectionToTrack => selection;

  @override
  List<ISingleEditOperation> getEditOperations(PieceTreeTextBuffer model) => [
    for (final (range, text) in computeEdits(model.getLineContent))
      EditOperation.replace(range, text),
  ];

  /// The edits for any document whose lines [getLineContent] returns. Every
  /// range is within one line. Also records the state used by
  /// [computeCursorState].
  List<(Range, String)> computeEdits(String Function(int) getLineContent) {
    _startColumnToPreserve = null;
    _caretOnWhitespaceOnlyLine = false;
    final firstLine = selection.startLineNumber;
    var lastLine = selection.endLineNumber;
    if (lastLine != firstLine && selection.endColumn == 1) lastLine--;
    final indentEmptyLines = firstLine == lastLine;
    final edits = <(Range, String)>[];
    for (var line = firstLine; line <= lastLine; line++) {
      final content = getLineContent(line);
      var indentEnd = 0;
      while (indentEnd < content.length &&
          (content.codeUnitAt(indentEnd) == 32 ||
              content.codeUnitAt(indentEnd) == 9)) {
        indentEnd++;
      }
      if (options.isUnshift && indentEnd == 0) continue;
      if (!indentEmptyLines && !options.isUnshift && content.isEmpty) continue;
      final whitespaceOnly = indentEnd == content.length;
      if (selection.isEmpty() &&
          line == firstLine &&
          whitespaceOnly &&
          (options.useTabStops || (!options.isUnshift && content.isEmpty))) {
        _caretOnWhitespaceOnlyLine = true;
      }
      late Range range;
      late String text;
      if (options.useTabStops) {
        range = Range(line, 1, line, indentEnd + 1);
        text = options.isUnshift
            ? unshiftIndent(
                content,
                indentEnd + 1,
                options.tabSize,
                options.indentSize,
                options.insertSpaces,
              )
            : shiftIndent(
                content,
                indentEnd + 1,
                options.tabSize,
                options.indentSize,
                options.insertSpaces,
              );
      } else if (options.isUnshift) {
        var removal = indentEnd < options.indentSize
            ? indentEnd
            : options.indentSize;
        for (var i = 0; i < removal; i++) {
          if (content.codeUnitAt(i) == 9) {
            removal = i + 1;
            break;
          }
        }
        range = Range(line, 1, line, removal + 1);
        text = '';
      } else {
        range = Range(line, 1, line, 1);
        text = options.insertSpaces ? ' ' * options.indentSize : '\t';
      }
      if (line == firstLine &&
          !selection.isEmpty() &&
          selection.startColumn <= range.endColumn) {
        _startColumnToPreserve = selection.startColumn;
      }
      if (content.substring(range.startColumn - 1, range.endColumn - 1) !=
          text) {
        edits.add((range, text));
      }
    }
    return edits;
  }

  @override
  Selection computeCursorState(CommandCursorState state) {
    var tracked = state.trackedSelection!;
    if (state.inverseEditRanges.isEmpty) return tracked;
    if (_caretOnWhitespaceOnlyLine) {
      // For indentation on a whitespace-only line, upstream uses the end of
      // the last tracked edit rather than its original caret marker.
      return Selection.fromPositions(
        state.inverseEditRanges.last.getEndPosition(),
      );
    }
    final startColumn = _startColumnToPreserve;
    if (startColumn != null && tracked.startColumn < startColumn) {
      tracked = tracked.getDirection() == SelectionDirection.ltr
          ? Selection(
              tracked.startLineNumber,
              startColumn,
              tracked.endLineNumber,
              tracked.endColumn,
            )
          : Selection(
              tracked.endLineNumber,
              tracked.endColumn,
              tracked.startLineNumber,
              startColumn,
            );
    }
    return tracked;
  }
}

/// [ShiftCommand] for the cursor-command executor (see cursor_command.dart).
class ShiftCursorCommand extends CursorCommand {
  ShiftCursorCommand(Selection selection, ShiftCommandOptions options)
    : _command = ShiftCommand(selection, options);

  final ShiftCommand _command;

  @override
  Selection? get selectionToTrack => _command.selection;

  @override
  List<CursorCommandEdit> getEditOperations(ICursorSimpleModel model) => [
    for (final (range, text) in _command.computeEdits(model.getLineContent))
      CursorCommandEdit(range, text),
  ];

  @override
  Selection computeCursorState(
    ICursorSimpleModel model,
    CursorStateComputerData helper,
  ) => _command.computeCursorState(
    CommandCursorState(
      helper.getInverseEditOperations(),
      helper.getTrackedSelection(),
    ),
  );
}
