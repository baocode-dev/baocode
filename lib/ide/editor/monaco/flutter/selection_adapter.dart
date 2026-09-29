import 'package:flutter/services.dart';

import 'document_snapshot.dart';
import '../vs/editor/common/core/position.dart';
import '../vs/editor/common/core/selection.dart';

/// Converts a Flutter UTF-16 code-unit offset to a one-based editor position.
///
/// Out-of-bounds offsets are clamped to the text. An offset between the CR
/// and LF of a CRLF pair belongs to the preceding line's end column.
Position positionAtOffset(String text, int offset) {
  final end = offset < 0 ? 0 : (offset > text.length ? text.length : offset);
  var line = 1;
  var column = 1;
  var index = 0;

  while (index < end) {
    final codeUnit = text.codeUnitAt(index);
    if (codeUnit == 0x0D) {
      if (index + 1 < text.length && text.codeUnitAt(index + 1) == 0x0A) {
        if (index + 1 == end) break;
        index += 2;
      } else {
        index++;
      }
      line++;
      column = 1;
    } else if (codeUnit == 0x0A) {
      index++;
      line++;
      column = 1;
    } else {
      index++;
      column++;
    }
  }

  return Position(line, column);
}

/// Converts a Flutter selection to its caret and oriented editor range.
///
/// The caret follows the selection's extent (including reversed selections).
/// An invalid selection, such as Flutter's default -1 offsets, collapses at
/// the start of the document.
({Position caret, Selection range}) editorSelectionOf(
  TextEditingValue value, {
  DocumentSnapshot? snapshot,
}) {
  if (!value.selection.isValid) {
    const start = Position(1, 1);
    return (caret: start, range: Selection.fromPositions(start));
  }

  final document = snapshot?.text == value.text
      ? snapshot!
      : DocumentSnapshot(value.text);
  final base = document.positionAtOffset(value.selection.baseOffset);
  final caret = document.positionAtOffset(value.selection.extentOffset);
  return (caret: caret, range: Selection.fromPositions(base, caret));
}
