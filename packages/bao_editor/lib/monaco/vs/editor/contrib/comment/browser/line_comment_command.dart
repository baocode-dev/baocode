/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/contrib/comment/browser/lineCommentCommand.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971. Implements the local
// CursorCommand contract; comment tokens come from one resolved language
// configuration (no embedded-language lookup per line).

import '../../../common/commands/cursor_command.dart';
import '../../../common/core/position.dart';
import '../../../common/core/range.dart';
import '../../../common/core/selection.dart';
import '../../../common/cursor/cursor_common.dart';
import '../../../common/languages/language_configuration_registry.dart';
import 'block_comment_command.dart';

class LinePreflightData {
  LinePreflightData(this.commentStr, this.commentStrLength);

  bool ignore = false;
  final String commentStr;
  int commentStrOffset = 0;
  int commentStrLength;
}

class PreflightData {
  const PreflightData(this.shouldRemoveComments, this.lines);

  final bool shouldRemoveComments;
  final List<LinePreflightData> lines;
}

enum LineCommentType { toggle, forceAdd, forceRemove }

class LineCommentCommand extends CursorCommand {
  LineCommentCommand(
    this._comments,
    this._selection,
    this._indentSize,
    this._type,
    this._insertSpace,
    this._ignoreEmptyLines, {
    this.ignoreFirstLine = false,
  });

  final CommentsConfiguration? _comments;
  final Selection _selection;
  final int _indentSize;
  final LineCommentType _type;
  final bool _insertSpace;
  final bool _ignoreEmptyLines;
  final bool ignoreFirstLine;
  Selection? _trackedSelection;
  int _deltaColumn = 0;
  bool _moveEndPositionDown = false;

  /// Analyze lines and decide which lines are relevant and what the toggle
  /// should do. Also builds up offsets and lengths for the edits.
  static PreflightData analyzeLines(
    LineCommentType type,
    bool insertSpace,
    ICursorSimpleModel model,
    List<LinePreflightData> lines,
    int startLineNumber,
    bool ignoreEmptyLines,
    bool ignoreFirstLine,
    bool lineCommentNoIndent,
  ) {
    var onlyWhitespaceLines = true;
    var shouldRemoveComments = type != LineCommentType.forceAdd;
    for (var i = 0; i < lines.length; i++) {
      final lineData = lines[i];
      final lineNumber = startLineNumber + i;
      if (lineNumber == startLineNumber && ignoreFirstLine) {
        // first line ignored
        lineData.ignore = true;
        continue;
      }
      final lineContent = model.getLineContent(lineNumber);
      final lineContentStartOffset = firstNonWhitespaceIndex(lineContent);
      if (lineContentStartOffset == -1) {
        // Empty or whitespace only line
        lineData.ignore = ignoreEmptyLines;
        lineData.commentStrOffset = lineCommentNoIndent
            ? 0
            : lineContent.length;
        continue;
      }
      onlyWhitespaceLines = false;
      final offset = lineCommentNoIndent ? 0 : lineContentStartOffset;
      lineData.ignore = false;
      lineData.commentStrOffset = offset;
      if (shouldRemoveComments &&
          !BlockCommentCommand.haystackHasNeedleAtOffset(
            lineContent,
            lineData.commentStr,
            offset,
          )) {
        if (type == LineCommentType.toggle) {
          // Every line so far has been a line comment, but this one is not
          shouldRemoveComments = false;
        } else if (type == LineCommentType.forceRemove) {
          lineData.ignore = true;
        }
      }
      if (shouldRemoveComments && insertSpace) {
        // Remove a following space if present
        final commentStrEndOffset =
            lineContentStartOffset + lineData.commentStrLength;
        if (commentStrEndOffset < lineContent.length &&
            lineContent.codeUnitAt(commentStrEndOffset) == 0x20) {
          lineData.commentStrLength += 1;
        }
      }
    }
    if (type == LineCommentType.toggle && onlyWhitespaceLines) {
      // For only whitespace lines, we insert comments
      shouldRemoveComments = false;
      // Also, no longer ignore them
      for (final line in lines) {
        line.ignore = false;
      }
    }
    return PreflightData(shouldRemoveComments, lines);
  }

  PreflightData? _gatherPreflightData(
    ICursorSimpleModel model,
    int startLineNumber,
    int endLineNumber,
  ) {
    final commentStr = _comments?.lineCommentToken;
    if (commentStr == null || commentStr.isEmpty) {
      // Mode does not support line comments
      return null;
    }
    final lines = [
      for (var i = 0; i < endLineNumber - startLineNumber + 1; i++)
        LinePreflightData(commentStr, commentStr.length),
    ];
    return analyzeLines(
      _type,
      _insertSpace,
      model,
      lines,
      startLineNumber,
      _ignoreEmptyLines,
      ignoreFirstLine,
      _comments?.lineCommentNoIndent ?? false,
    );
  }

  List<CursorCommandEdit> _executeLineComments(
    ICursorSimpleModel model,
    PreflightData data,
    Selection s,
  ) {
    List<CursorCommandEdit> ops;
    if (data.shouldRemoveComments) {
      ops = createRemoveLineCommentsOperations(data.lines, s.startLineNumber);
    } else {
      normalizeInsertionPoint(
        model,
        data.lines,
        s.startLineNumber,
        _indentSize,
      );
      ops = _createAddLineCommentsOperations(data.lines, s.startLineNumber);
    }
    final cursorPosition = Position(s.positionLineNumber, s.positionColumn);
    for (final op in ops) {
      if (op.range.isEmpty() &&
          op.range.getStartPosition().equals(cursorPosition)) {
        final lineContent = model.getLineContent(cursorPosition.lineNumber);
        if (lineContent.length + 1 == cursorPosition.column) {
          _deltaColumn = op.text.length;
        }
      }
    }
    _trackedSelection = s;
    return ops;
  }

  List<CursorCommandEdit>? _attemptRemoveBlockComment(
    ICursorSimpleModel model,
    Selection s,
    String startToken,
    String endToken,
  ) {
    var startLineNumber = s.startLineNumber;
    var endLineNumber = s.endLineNumber;
    final firstNonWhitespace = model.getLineFirstNonWhitespaceColumn(
      s.startLineNumber,
    );
    final startTokenAllowedBeforeColumn =
        endToken.length +
        (firstNonWhitespace > s.startColumn
            ? firstNonWhitespace
            : s.startColumn);
    var startTokenIndex = jsLastIndexOf(
      model.getLineContent(startLineNumber),
      startToken,
      startTokenAllowedBeforeColumn - 1,
    );
    var endTokenIndex = jsIndexOf(
      model.getLineContent(endLineNumber),
      endToken,
      s.endColumn - 1 - startToken.length,
    );
    if (startTokenIndex != -1 && endTokenIndex == -1) {
      endTokenIndex = jsIndexOf(
        model.getLineContent(startLineNumber),
        endToken,
        startTokenIndex + startToken.length,
      );
      endLineNumber = startLineNumber;
    }
    if (startTokenIndex == -1 && endTokenIndex != -1) {
      startTokenIndex = jsLastIndexOf(
        model.getLineContent(endLineNumber),
        startToken,
        endTokenIndex,
      );
      startLineNumber = endLineNumber;
    }
    if (s.isEmpty() && (startTokenIndex == -1 || endTokenIndex == -1)) {
      startTokenIndex = model
          .getLineContent(startLineNumber)
          .indexOf(startToken);
      if (startTokenIndex != -1) {
        endTokenIndex = jsIndexOf(
          model.getLineContent(startLineNumber),
          endToken,
          startTokenIndex + startToken.length,
        );
      }
    }
    // We have to adjust to possible inner white space.
    // For Space after startToken, add Space to startToken - range math will
    // work out.
    final startLine = model.getLineContent(startLineNumber);
    if (startTokenIndex != -1 &&
        startTokenIndex + startToken.length < startLine.length &&
        startLine.codeUnitAt(startTokenIndex + startToken.length) == 0x20) {
      startToken += ' ';
    }
    // For Space before endToken, add Space before endToken and shift index
    // one left.
    final endLine = model.getLineContent(endLineNumber);
    if (endTokenIndex > 0 && endLine.codeUnitAt(endTokenIndex - 1) == 0x20) {
      endToken = ' $endToken';
      endTokenIndex -= 1;
    }
    if (startTokenIndex != -1 && endTokenIndex != -1) {
      return BlockCommentCommand.createRemoveBlockCommentOperations(
        Range(
          startLineNumber,
          startTokenIndex + startToken.length + 1,
          endLineNumber,
          endTokenIndex + 1,
        ),
        startToken,
        endToken,
      );
    }
    return null;
  }

  /// Given an unsuccessful analysis, delegate to the block comment command.
  List<CursorCommandEdit> _executeBlockComment(
    ICursorSimpleModel model,
    Selection s,
  ) {
    final startToken = _comments?.blockCommentStartToken;
    final endToken = _comments?.blockCommentEndToken;
    if (startToken == null ||
        endToken == null ||
        startToken.isEmpty ||
        endToken.isEmpty) {
      // Mode does not support block comments
      _trackedSelection = s;
      return const [];
    }
    var ops = _attemptRemoveBlockComment(model, s, startToken, endToken);
    if (ops == null) {
      if (s.isEmpty()) {
        final lineContent = model.getLineContent(s.startLineNumber);
        var firstNonWhitespace = firstNonWhitespaceIndex(lineContent);
        if (firstNonWhitespace == -1) {
          // Line is empty or contains only whitespace
          firstNonWhitespace = lineContent.length;
        }
        ops = BlockCommentCommand.createAddBlockCommentOperations(
          Range(
            s.startLineNumber,
            firstNonWhitespace + 1,
            s.startLineNumber,
            lineContent.length + 1,
          ),
          startToken,
          endToken,
          _insertSpace,
        );
      } else {
        ops = BlockCommentCommand.createAddBlockCommentOperations(
          Range(
            s.startLineNumber,
            model.getLineFirstNonWhitespaceColumn(s.startLineNumber),
            s.endLineNumber,
            model.getLineMaxColumn(s.endLineNumber),
          ),
          startToken,
          endToken,
          _insertSpace,
        );
      }
      if (ops.length == 1) {
        // Leave cursor after token and Space
        _deltaColumn = startToken.length + 1;
      }
    }
    _trackedSelection = s;
    return ops;
  }

  @override
  Selection? get selectionToTrack => _trackedSelection;

  @override
  List<CursorCommandEdit> getEditOperations(ICursorSimpleModel model) {
    var s = _selection;
    _moveEndPositionDown = false;
    _deltaColumn = 0;
    if (s.startLineNumber == s.endLineNumber && ignoreFirstLine) {
      _trackedSelection = s;
      return [
        CursorCommandEdit(
          Range(
            s.startLineNumber,
            model.getLineMaxColumn(s.startLineNumber),
            s.startLineNumber + 1,
            1,
          ),
          s.startLineNumber == model.getLineCount() ? '' : '\n',
        ),
      ];
    }
    if (s.startLineNumber < s.endLineNumber && s.endColumn == 1) {
      _moveEndPositionDown = true;
      s = s.setEndPosition(
        s.endLineNumber - 1,
        model.getLineMaxColumn(s.endLineNumber - 1),
      );
    }
    final data = _gatherPreflightData(
      model,
      s.startLineNumber,
      s.endLineNumber,
    );
    if (data != null) return _executeLineComments(model, data, s);
    return _executeBlockComment(model, s);
  }

  @override
  Selection computeCursorState(
    ICursorSimpleModel model,
    CursorStateComputerData helper,
  ) {
    var result = helper.getTrackedSelection();
    if (_moveEndPositionDown) {
      result = result.setEndPosition(result.endLineNumber + 1, 1);
    }
    return Selection(
      result.selectionStartLineNumber,
      result.selectionStartColumn + _deltaColumn,
      result.positionLineNumber,
      result.positionColumn + _deltaColumn,
    );
  }

  /// Generate edit operations in the remove line comment case.
  static List<CursorCommandEdit> createRemoveLineCommentsOperations(
    List<LinePreflightData> lines,
    int startLineNumber,
  ) => [
    for (var i = 0; i < lines.length; i++)
      if (!lines[i].ignore)
        CursorCommandEdit(
          Range(
            startLineNumber + i,
            lines[i].commentStrOffset + 1,
            startLineNumber + i,
            lines[i].commentStrOffset + lines[i].commentStrLength + 1,
          ),
          '',
        ),
  ];

  /// Generate edit operations in the add line comment case.
  List<CursorCommandEdit> _createAddLineCommentsOperations(
    List<LinePreflightData> lines,
    int startLineNumber,
  ) {
    final afterCommentStr = _insertSpace ? ' ' : '';
    return [
      for (var i = 0; i < lines.length; i++)
        if (!lines[i].ignore)
          CursorCommandEdit(
            Range(
              startLineNumber + i,
              lines[i].commentStrOffset + 1,
              startLineNumber + i,
              lines[i].commentStrOffset + 1,
            ),
            lines[i].commentStr + afterCommentStr,
          ),
    ];
  }

  static int _nextVisibleColumn(
    int currentVisibleColumn,
    int indentSize,
    bool isTab,
    int columnSize,
  ) {
    if (isTab) {
      return currentVisibleColumn +
          (indentSize - (currentVisibleColumn % indentSize));
    }
    return currentVisibleColumn + columnSize;
  }

  /// Adjust insertion points to have them vertically aligned in the add line
  /// comment case.
  static void normalizeInsertionPoint(
    ICursorSimpleModel model,
    List<LinePreflightData> lines,
    int startLineNumber,
    int indentSize,
  ) {
    const maxSafeSmallInteger = 1 << 30;
    var minVisibleColumn = maxSafeSmallInteger;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].ignore) continue;
      final lineContent = model.getLineContent(startLineNumber + i);
      var currentVisibleColumn = 0;
      for (
        var j = 0;
        currentVisibleColumn < minVisibleColumn &&
            j < lines[i].commentStrOffset;
        j++
      ) {
        currentVisibleColumn = _nextVisibleColumn(
          currentVisibleColumn,
          indentSize,
          lineContent.codeUnitAt(j) == 0x09,
          1,
        );
      }
      if (currentVisibleColumn < minVisibleColumn) {
        minVisibleColumn = currentVisibleColumn;
      }
    }
    minVisibleColumn = (minVisibleColumn ~/ indentSize) * indentSize;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].ignore) continue;
      final lineContent = model.getLineContent(startLineNumber + i);
      var currentVisibleColumn = 0;
      var j = 0;
      for (
        ;
        currentVisibleColumn < minVisibleColumn &&
            j < lines[i].commentStrOffset;
        j++
      ) {
        currentVisibleColumn = _nextVisibleColumn(
          currentVisibleColumn,
          indentSize,
          lineContent.codeUnitAt(j) == 0x09,
          1,
        );
      }
      lines[i].commentStrOffset = currentVisibleColumn > minVisibleColumn
          ? j - 1
          : j;
    }
  }
}
