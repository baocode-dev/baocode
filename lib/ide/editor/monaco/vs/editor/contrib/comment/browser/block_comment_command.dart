/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/contrib/comment/browser/blockCommentCommand.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971. Implements the local
// CursorCommand contract; the comment tokens come from the caller's resolved
// language configuration instead of a per-position language lookup.

import '../../../common/commands/cursor_command.dart';
import '../../../common/core/range.dart';
import '../../../common/core/selection.dart';
import '../../../common/cursor/cursor_common.dart';
import '../../../common/languages/language_configuration_registry.dart';

class BlockCommentCommand extends CursorCommand {
  BlockCommentCommand(this._selection, this._insertSpace, this._comments);

  final Selection _selection;
  final bool _insertSpace;
  final CommentsConfiguration? _comments;
  String? _usedEndToken;

  static bool haystackHasNeedleAtOffset(
    String haystack,
    String needle,
    int offset,
  ) {
    if (offset < 0) return false;
    final needleLength = needle.length;
    if (offset + needleLength > haystack.length) return false;
    for (var i = 0; i < needleLength; i++) {
      final codeA = haystack.codeUnitAt(offset + i);
      final codeB = needle.codeUnitAt(i);
      if (codeA == codeB) continue;
      if (codeA >= 0x41 && codeA <= 0x5A && codeA + 32 == codeB) {
        // codeA is upper-case variant of codeB
        continue;
      }
      if (codeB >= 0x41 && codeB <= 0x5A && codeB + 32 == codeA) {
        // codeB is upper-case variant of codeA
        continue;
      }
      return false;
    }
    return true;
  }

  List<CursorCommandEdit> _createOperationsForBlockComment(
    Range selection,
    String startToken,
    String endToken,
    bool insertSpace,
    ICursorSimpleModel model,
  ) {
    final startLineNumber = selection.startLineNumber;
    final startColumn = selection.startColumn;
    final endLineNumber = selection.endLineNumber;
    final endColumn = selection.endColumn;
    final startLineText = model.getLineContent(startLineNumber);
    final endLineText = model.getLineContent(endLineNumber);
    var startTokenIndex = _lastIndexOf(
      startLineText,
      startToken,
      startColumn - 1 + startToken.length,
    );
    var endTokenIndex = _indexOf(
      endLineText,
      endToken,
      endColumn - 1 - endToken.length,
    );
    if (startTokenIndex != -1 && endTokenIndex != -1) {
      if (startLineNumber == endLineNumber) {
        final lineBetweenTokens =
            startTokenIndex + startToken.length <= endTokenIndex
            ? startLineText.substring(
                startTokenIndex + startToken.length,
                endTokenIndex,
              )
            : '';
        if (lineBetweenTokens.contains(endToken)) {
          // force to add a block comment
          startTokenIndex = -1;
          endTokenIndex = -1;
        }
      } else {
        final startLineAfterStartToken = startLineText.substring(
          startTokenIndex + startToken.length,
        );
        final endLineBeforeEndToken = endLineText.substring(0, endTokenIndex);
        if (startLineAfterStartToken.contains(endToken) ||
            endLineBeforeEndToken.contains(endToken)) {
          // force to add a block comment
          startTokenIndex = -1;
          endTokenIndex = -1;
        }
      }
    }
    List<CursorCommandEdit> ops;
    if (startTokenIndex != -1 && endTokenIndex != -1) {
      // Consider spaces as part of the comment tokens
      if (insertSpace &&
          startTokenIndex + startToken.length < startLineText.length &&
          startLineText.codeUnitAt(startTokenIndex + startToken.length) ==
              0x20) {
        // Pretend the start token contains a trailing space
        startToken = '$startToken ';
      }
      if (insertSpace &&
          endTokenIndex > 0 &&
          endLineText.codeUnitAt(endTokenIndex - 1) == 0x20) {
        // Pretend the end token contains a leading space
        endToken = ' $endToken';
        endTokenIndex -= 1;
      }
      ops = createRemoveBlockCommentOperations(
        Range(
          startLineNumber,
          startTokenIndex + startToken.length + 1,
          endLineNumber,
          endTokenIndex + 1,
        ),
        startToken,
        endToken,
      );
    } else {
      ops = createAddBlockCommentOperations(
        selection,
        startToken,
        endToken,
        _insertSpace,
      );
      _usedEndToken = ops.length == 1 ? endToken : null;
    }
    return ops;
  }

  static List<CursorCommandEdit> createRemoveBlockCommentOperations(
    Range r,
    String startToken,
    String endToken,
  ) {
    if (!Range.isEmptyRange(r)) {
      return [
        // Remove block comment start
        CursorCommandEdit(
          Range(
            r.startLineNumber,
            r.startColumn - startToken.length,
            r.startLineNumber,
            r.startColumn,
          ),
          '',
        ),
        // Remove block comment end
        CursorCommandEdit(
          Range(
            r.endLineNumber,
            r.endColumn,
            r.endLineNumber,
            r.endColumn + endToken.length,
          ),
          '',
        ),
      ];
    }
    // Remove both continuously
    return [
      CursorCommandEdit(
        Range(
          r.startLineNumber,
          r.startColumn - startToken.length,
          r.endLineNumber,
          r.endColumn + endToken.length,
        ),
        '',
      ),
    ];
  }

  static List<CursorCommandEdit> createAddBlockCommentOperations(
    Range r,
    String startToken,
    String endToken,
    bool insertSpace,
  ) {
    if (!Range.isEmptyRange(r)) {
      return [
        // Insert block comment start
        CursorCommandEdit(
          Range(
            r.startLineNumber,
            r.startColumn,
            r.startLineNumber,
            r.startColumn,
          ),
          startToken + (insertSpace ? ' ' : ''),
        ),
        // Insert block comment end
        CursorCommandEdit(
          Range(r.endLineNumber, r.endColumn, r.endLineNumber, r.endColumn),
          (insertSpace ? ' ' : '') + endToken,
        ),
      ];
    }
    // Insert both continuously
    return [
      CursorCommandEdit(
        Range(r.startLineNumber, r.startColumn, r.endLineNumber, r.endColumn),
        '$startToken  $endToken',
      ),
    ];
  }

  @override
  List<CursorCommandEdit> getEditOperations(ICursorSimpleModel model) {
    final config = _comments;
    final start = config?.blockCommentStartToken;
    final end = config?.blockCommentEndToken;
    if (start == null || end == null || start.isEmpty || end.isEmpty) {
      // Mode does not support block comments
      return const [];
    }
    return _createOperationsForBlockComment(
      _selection,
      start,
      end,
      _insertSpace,
      model,
    );
  }

  @override
  Selection? get selectionToTrack => _selection;

  @override
  Selection computeCursorState(
    ICursorSimpleModel model,
    CursorStateComputerData helper,
  ) {
    final inverseEditOperations = helper.getInverseEditOperations();
    if (inverseEditOperations.isEmpty) return helper.getTrackedSelection();
    if (inverseEditOperations.length == 2) {
      final startTokenEditOperation = inverseEditOperations[0];
      final endTokenEditOperation = inverseEditOperations[1];
      return Selection(
        startTokenEditOperation.endLineNumber,
        startTokenEditOperation.endColumn,
        endTokenEditOperation.startLineNumber,
        endTokenEditOperation.startColumn,
      );
    }
    final srcRange = inverseEditOperations[0];
    // minus 1 space before endToken
    final deltaColumn = _usedEndToken != null ? -_usedEndToken!.length - 1 : 0;
    return Selection(
      srcRange.endLineNumber,
      srcRange.endColumn + deltaColumn,
      srcRange.endLineNumber,
      srcRange.endColumn + deltaColumn,
    );
  }
}

/// JS String.prototype.lastIndexOf(search, position) semantics.
int _lastIndexOf(String text, String search, int position) {
  if (position < 0) position = 0;
  final start = position > text.length - search.length
      ? text.length - search.length
      : position;
  if (start < 0) return -1;
  return text.lastIndexOf(search, start);
}

/// JS String.prototype.indexOf(search, position) semantics.
int _indexOf(String text, String search, int position) {
  if (position < 0) position = 0;
  if (position > text.length) return search.isEmpty ? text.length : -1;
  return text.indexOf(search, position);
}

int jsLastIndexOf(String text, String search, int position) =>
    _lastIndexOf(text, search, position);

int jsIndexOf(String text, String search, int position) =>
    _indexOf(text, search, position);
