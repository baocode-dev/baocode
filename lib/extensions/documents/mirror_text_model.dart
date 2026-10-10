/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The extension host's copy of a document: lines plus one EOL, updated by
// the main thread's change events. BaoCode uses it to check what the
// extension host will see (tests, diagnostics); the real one lives in the
// extension host (`ExtHostDocumentData extends MirrorTextModel`).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/common/model/mirrorTextModel.ts (`MirrorTextModel`).
//
// Deviations:
// - Adds `offsetAt`/`positionAt` from extHostDocumentData.ts (via the same
//   prefix sums) for checks.

import 'dart:typed_data';

import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_editor/monaco/vs/editor/common/model/prefix_sum_computer.dart';
import 'package:bao_exthost/bao_exthost.dart' show VsUri;

import 'end_of_line.dart';
import 'model_changed_event.dart';

class MirrorTextModel {
  MirrorTextModel(this._uri, List<String> lines, this._eol, this._versionId)
    : _lines = List.of(lines);

  final VsUri _uri;
  final List<String> _lines;
  String _eol;
  int _versionId;
  PrefixSumComputer? _lineStarts;
  String? _cachedTextValue;

  VsUri get uri => _uri;
  int get version => _versionId;
  String get eol => _eol;
  List<String> get lines => List.unmodifiable(_lines);

  void dispose() => _lines.clear();

  String getText() => _cachedTextValue ??= _lines.join(_eol);

  void onEvents(ModelChangedEvent e) {
    if (e.eol.isNotEmpty && e.eol != _eol) {
      _eol = e.eol;
      _lineStarts = null;
    }

    // Update my lines
    for (final change in e.changes) {
      _acceptDeleteRange(change.range);
      _acceptInsertText(
        Position(change.range.startLineNumber, change.range.startColumn),
        change.text,
      );
    }

    _versionId = e.versionId;
    _cachedTextValue = null;
  }

  void _ensureLineStarts() {
    if (_lineStarts == null) {
      final eolLength = _eol.length;
      final values = Uint32List(_lines.length);
      for (var i = 0; i < _lines.length; i++) {
        values[i] = _lines[i].length + eolLength;
      }
      _lineStarts = PrefixSumComputer(values);
    }
  }

  /// `ExtHostDocumentData._offsetAt` for a valid [position].
  int offsetAt(IPosition position) {
    _ensureLineStarts();
    return (_lineStarts!.getPrefixSum(position.lineNumber - 2) ?? 0) +
        position.column -
        1;
  }

  /// `ExtHostDocumentData._positionAt`.
  Position positionAt(int offset) {
    _ensureLineStarts();
    final out = _lineStarts!.getIndexOf(offset < 0 ? 0 : offset);
    final lineLength = _lines[out.index].length;
    final remainder = out.remainder.toInt();
    return Position(
      out.index + 1,
      (remainder < lineLength ? remainder : lineLength) + 1,
    );
  }

  /// All changes to a line's text go through this method
  void _setLineText(int lineIndex, String newValue) {
    _lines[lineIndex] = newValue;
    // update prefix sum
    _lineStarts?.setValue(lineIndex, _lines[lineIndex].length + _eol.length);
  }

  void _acceptDeleteRange(IRange range) {
    if (range.startLineNumber == range.endLineNumber) {
      if (range.startColumn == range.endColumn) {
        // Nothing to delete
        return;
      }
      // Delete text on the affected line
      final line = _lines[range.startLineNumber - 1];
      _setLineText(
        range.startLineNumber - 1,
        line.substring(0, range.startColumn - 1) +
            line.substring(range.endColumn - 1),
      );
      return;
    }

    // Take remaining text on last line and append it to remaining text on first line
    _setLineText(
      range.startLineNumber - 1,
      _lines[range.startLineNumber - 1].substring(0, range.startColumn - 1) +
          _lines[range.endLineNumber - 1].substring(range.endColumn - 1),
    );

    // Delete middle lines
    _lines.removeRange(range.startLineNumber, range.endLineNumber);
    // update prefix sum
    _lineStarts?.removeValues(
      range.startLineNumber,
      range.endLineNumber - range.startLineNumber,
    );
  }

  void _acceptInsertText(Position position, String insertText) {
    if (insertText.isEmpty) {
      // Nothing to insert
      return;
    }
    final insertLines = splitLines(insertText);
    final line = _lines[position.lineNumber - 1];
    if (insertLines.length == 1) {
      // Inserting text on one line
      _setLineText(
        position.lineNumber - 1,
        line.substring(0, position.column - 1) +
            insertLines[0] +
            line.substring(position.column - 1),
      );
      return;
    }

    // Append overflowing text from first line to the end of text to insert
    insertLines[insertLines.length - 1] += line.substring(position.column - 1);

    // Delete overflowing text from first line and insert text on first line
    _setLineText(
      position.lineNumber - 1,
      line.substring(0, position.column - 1) + insertLines[0],
    );

    // Insert new lines & store lengths
    final newLengths = Uint32List(insertLines.length - 1);
    for (var i = 1; i < insertLines.length; i++) {
      newLengths[i - 1] = insertLines[i].length + _eol.length;
    }
    _lines.insertAll(position.lineNumber, insertLines.skip(1));

    // update prefix sum
    _lineStarts?.insertValues(position.lineNumber, newLengths);
  }
}
