/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/core/textChange.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971.
// The binary helpers here replace the upstream buffer/stringBuilder imports.

import 'dart:typed_data';

String _escapeNewLine(String text) =>
    text.replaceAll('\n', r'\n').replaceAll('\r', r'\r');

/// Positions and lengths are UTF-16 code-unit offsets, as in the editor model.
class TextChange {
  const TextChange(
    this.oldPosition,
    this.oldText,
    this.newPosition,
    this.newText,
  );

  final int oldPosition;
  final String oldText;
  final int newPosition;
  final String newText;

  int get oldLength => oldText.length;
  int get oldEnd => oldPosition + oldLength;
  int get newLength => newText.length;
  int get newEnd => newPosition + newLength;

  @override
  String toString() {
    if (oldText.isEmpty) {
      return '(insert@$oldPosition "${_escapeNewLine(newText)}")';
    }
    if (newText.isEmpty) {
      return '(delete@$oldPosition "${_escapeNewLine(oldText)}")';
    }
    return '(replace@$oldPosition "${_escapeNewLine(oldText)}" with "${_escapeNewLine(newText)}")';
  }

  int writeSize() => 16 + 2 * (oldLength + newLength);

  /// Writes the upstream format: big-endian uint32 positions/lengths and
  /// little-endian UTF-16 code units. Returns the offset after the record.
  int write(Uint8List bytes, int offset) {
    _writeUint32(bytes, oldPosition, offset);
    _writeUint32(bytes, newPosition, offset + 4);
    offset = _writeString(bytes, oldText, offset + 8);
    return _writeString(bytes, newText, offset);
  }

  /// Reads one record into [dest] and returns the offset after it.
  static int read(Uint8List bytes, int offset, List<TextChange> dest) {
    final oldPosition = _readUint32(bytes, offset);
    final newPosition = _readUint32(bytes, offset + 4);
    final (oldText, nextOffset) = _readString(bytes, offset + 8);
    final (newText, endOffset) = _readString(bytes, nextOffset);
    dest.add(TextChange(oldPosition, oldText, newPosition, newText));
    return endOffset;
  }
}

void _writeUint32(Uint8List bytes, int value, int offset) {
  // Match the unsigned bit shifts in VS Code's writeUInt32BE.
  bytes[offset] = (value >> 24) & 0xff;
  bytes[offset + 1] = (value >> 16) & 0xff;
  bytes[offset + 2] = (value >> 8) & 0xff;
  bytes[offset + 3] = value & 0xff;
}

int _readUint32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

int _writeString(Uint8List bytes, String text, int offset) {
  _writeUint32(bytes, text.length, offset);
  offset += 4;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    bytes[offset++] = unit & 0xff;
    bytes[offset++] = unit >> 8;
  }
  return offset;
}

(String, int) _readString(Uint8List bytes, int offset) {
  final length = _readUint32(bytes, offset);
  offset += 4;
  final units = List<int>.generate(
    length,
    (i) => bytes[offset + 2 * i] | (bytes[offset + 2 * i + 1] << 8),
  );
  return (String.fromCharCodes(units), offset + 2 * length);
}

/// Combines consecutive batches of edits into changes against the first text.
/// Input changes must be ordered and use their respective old/new coordinates.
List<TextChange> compressConsecutiveTextChanges(
  List<TextChange>? prevEdits,
  List<TextChange> currEdits,
) {
  if (prevEdits == null || prevEdits.isEmpty) {
    return currEdits;
  }
  return _TextChangeCompressor(prevEdits, currEdits).compress();
}

class _TextChangeCompressor {
  _TextChangeCompressor(this._prevEdits, this._currEdits);

  final List<TextChange> _prevEdits;
  final List<TextChange> _currEdits;
  final List<TextChange> _result = [];
  int _prevDeltaOffset = 0;
  int _currDeltaOffset = 0;

  List<TextChange> compress() {
    var prevIndex = 0;
    var currIndex = 0;
    TextChange? prevEdit = _getPrev(prevIndex);
    TextChange? currEdit = _getCurr(currIndex);

    while (prevIndex < _prevEdits.length || currIndex < _currEdits.length) {
      if (prevEdit == null) {
        _acceptCurr(currEdit!);
        currEdit = _getCurr(++currIndex);
        continue;
      }
      if (currEdit == null) {
        _acceptPrev(prevEdit);
        prevEdit = _getPrev(++prevIndex);
        continue;
      }
      if (currEdit.oldEnd <= prevEdit.newPosition) {
        _acceptCurr(currEdit);
        currEdit = _getCurr(++currIndex);
        continue;
      }
      if (prevEdit.newEnd <= currEdit.oldPosition) {
        _acceptPrev(prevEdit);
        prevEdit = _getPrev(++prevIndex);
        continue;
      }
      if (currEdit.oldPosition < prevEdit.newPosition) {
        final (first, second) = _splitCurr(
          currEdit,
          prevEdit.newPosition - currEdit.oldPosition,
        );
        _acceptCurr(first);
        currEdit = second;
        continue;
      }
      if (prevEdit.newPosition < currEdit.oldPosition) {
        final (first, second) = _splitPrev(
          prevEdit,
          currEdit.oldPosition - prevEdit.newPosition,
        );
        _acceptPrev(first);
        prevEdit = second;
        continue;
      }

      // Here currEdit.oldPosition == prevEdit.newPosition.
      late TextChange mergePrev;
      late TextChange mergeCurr;
      if (currEdit.oldEnd == prevEdit.newEnd) {
        mergePrev = prevEdit;
        mergeCurr = currEdit;
        prevEdit = _getPrev(++prevIndex);
        currEdit = _getCurr(++currIndex);
      } else if (currEdit.oldEnd < prevEdit.newEnd) {
        final (first, second) = _splitPrev(prevEdit, currEdit.oldLength);
        mergePrev = first;
        mergeCurr = currEdit;
        prevEdit = second;
        currEdit = _getCurr(++currIndex);
      } else {
        final (first, second) = _splitCurr(currEdit, prevEdit.newLength);
        mergePrev = prevEdit;
        mergeCurr = first;
        prevEdit = _getPrev(++prevIndex);
        currEdit = second;
      }
      _result.add(
        TextChange(
          mergePrev.oldPosition,
          mergePrev.oldText,
          mergeCurr.newPosition,
          mergeCurr.newText,
        ),
      );
      _prevDeltaOffset += mergePrev.newLength - mergePrev.oldLength;
      _currDeltaOffset += mergeCurr.newLength - mergeCurr.oldLength;
    }
    return _removeNoOps(_merge(_result));
  }

  void _acceptCurr(TextChange edit) {
    _result.add(
      TextChange(
        edit.oldPosition - _prevDeltaOffset,
        edit.oldText,
        edit.newPosition,
        edit.newText,
      ),
    );
    _currDeltaOffset += edit.newLength - edit.oldLength;
  }

  void _acceptPrev(TextChange edit) {
    _result.add(
      TextChange(
        edit.oldPosition,
        edit.oldText,
        edit.newPosition + _currDeltaOffset,
        edit.newText,
      ),
    );
    _prevDeltaOffset += edit.newLength - edit.oldLength;
  }

  TextChange? _getPrev(int index) =>
      index < _prevEdits.length ? _prevEdits[index] : null;
  TextChange? _getCurr(int index) =>
      index < _currEdits.length ? _currEdits[index] : null;

  static (TextChange, TextChange) _splitPrev(TextChange edit, int offset) {
    final preText = edit.newText.substring(0, offset);
    final postText = edit.newText.substring(offset);
    return (
      TextChange(edit.oldPosition, edit.oldText, edit.newPosition, preText),
      TextChange(edit.oldEnd, '', edit.newPosition + offset, postText),
    );
  }

  static (TextChange, TextChange) _splitCurr(TextChange edit, int offset) {
    final preText = edit.oldText.substring(0, offset);
    final postText = edit.oldText.substring(offset);
    return (
      TextChange(edit.oldPosition, preText, edit.newPosition, edit.newText),
      TextChange(edit.oldPosition + offset, postText, edit.newEnd, ''),
    );
  }

  static List<TextChange> _merge(List<TextChange> edits) {
    if (edits.isEmpty) return edits;
    final result = <TextChange>[];
    var prev = edits.first;
    for (var i = 1; i < edits.length; i++) {
      final curr = edits[i];
      if (prev.oldEnd == curr.oldPosition) {
        prev = TextChange(
          prev.oldPosition,
          prev.oldText + curr.oldText,
          prev.newPosition,
          prev.newText + curr.newText,
        );
      } else {
        result.add(prev);
        prev = curr;
      }
    }
    result.add(prev);
    return result;
  }

  static List<TextChange> _removeNoOps(List<TextChange> edits) =>
      edits.where((edit) => edit.oldText != edit.newText).toList();
}
