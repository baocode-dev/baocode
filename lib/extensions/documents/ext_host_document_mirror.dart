/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What the extension host sees of a BaoCode document, and the mapping
// between the two.
//
// BaoCode's editor ([EditorDocumentModel]) keeps a file's exact text: mixed
// CR/LF/CRLF line breaks and a leading U+FEFF. VS Code's text model, which
// the extension host mirrors, has no BOM in its text and one EOL for all
// lines. [ExtHostDocumentMirror] is that model's view of the raw text:
//
// - Lines are the same on both sides (both break at CRLF, lone CR and lone
//   LF), so a line number never changes; a column only differs on line 1,
//   where the model has no BOM. Editor coordinates (one-based over the raw
//   text, as [EditorDocumentModel] and [DocumentSnapshot] count) map to model
//   coordinates (one-based over the model text, what the protocol carries)
//   by that shift alone.
// - The model EOL is chosen once, like `createTextBufferFactory`: CRLF when
//   CRLF and lone CR are more than half of all breaks, LF otherwise, the
//   default EOL without breaks. Every raw break reads as that EOL.
// - Raw edits ([acceptRawChanges]) become `IModelContentChange`s against the
//   model text, with offsets/lengths in model code units and a strictly
//   increasing version. Edits that leave the model text unchanged (turning
//   CR+LF into CRLF, touching the BOM) emit nothing.
// - Model edits from the extension host ([toEditorEdits]) become raw edits:
//   inserted line breaks take the file's dominant break kind (upstream
//   inserts the model EOL), and seams where a CR would meet an LF and merge
//   into one break are written as CRLF so that the model text comes out as
//   the extension asked.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/common/model/textModel.ts (`_validateRange` with
// `StringOffsetValidationType.SurrogatePairs`, `_validatePosition`,
// `setValue`/`setEOL` flush and EOL-change events,
// `_MODEL_SYNC_LIMIT`/`isTooLargeForSyncing`),
// src/vs/workbench/api/browser/mainThreadDocumentsAndEditors.ts
// (`_toModelAddedData`), src/vs/workbench/api/browser/mainThreadDocuments.ts
// (`ModelTracker`: one `$acceptModelChanged` per content change).
//
// Deviations:
// - The BOM is whatever U+FEFF starts the raw text right now (upstream
//   strips it once when the model is created): deleting or typing a leading
//   U+FEFF changes nothing the extension host sees. An extension inserting
//   U+FEFF at the very start of a document without one gets it read as a
//   BOM (as VS Code would after a reload).
// - A raw edit that joins a lone CR to a lone LF (deleting what was between
//   them) is written by [toEditorEdits] as CRLF+LF in place of CR+LF, the
//   only case where a line break the extension did not touch changes kind.
// - `isTooLargeForSyncing` is decided once, from the model length at
//   creation, like upstream's constructor.

import 'dart:typed_data';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_editor/monaco/vs/editor/common/model/prefix_sum_computer.dart';
import 'package:bao_exthost/bao_exthost.dart' show VsUri;

import '../language/language_feature_document.dart';
import 'end_of_line.dart';
import 'model_changed_event.dart';

/// A raw-text replacement in zero-based raw lines and UTF-16 characters (the
/// shape of [EditorContentChange]): [text] replaces the range in the text the
/// event's previous changes left.
class RawContentChange {
  const RawContentChange({
    required this.startLine,
    required this.startCharacter,
    required this.endLine,
    required this.endCharacter,
    required this.text,
  });

  factory RawContentChange.fromEditor(EditorContentChange change) =>
      RawContentChange(
        startLine: change.startLine,
        startCharacter: change.startCharacter,
        endLine: change.endLine,
        endCharacter: change.endCharacter,
        text: change.text,
      );

  final int startLine;
  final int startCharacter;
  final int endLine;
  final int endCharacter;
  final String text;
}

/// An edit in model coordinates, as the extension host sends them
/// (`ISingleEditOperation`, a `TextEdit` of a workspace edit). A null [text]
/// deletes.
class ModelTextEdit {
  const ModelTextEdit(this.range, this.text);

  final IRange range;
  final String? text;
}

class ExtHostDocumentMirror implements LanguageFeatureDocument {
  /// The model of [text] (the raw editor text) at [versionId]. [defaultEol]
  /// (`files.eol`) applies when the text has no line break.
  ExtHostDocumentMirror({
    required this.uri,
    required this.languageId,
    required String text,
    String defaultEol = '\n',
    int versionId = 1,
  }) : _defaultEol = defaultEol == '\r\n' ? '\r\n' : '\n',
       // A named parameter cannot be private.
       // ignore: prefer_initializing_formals
       _versionId = versionId {
    _load(text);
    isTooLargeForSyncing = isModelTooLargeForSyncing(_modelLength);
  }

  @override
  final VsUri uri;

  @override
  String languageId;

  final String _defaultEol;

  /// Raw line contents (line 0 keeps the BOM) and the break after each
  /// (`''` after the last line).
  late List<String> _lines;
  late List<String> _breaks;
  late LineBreakCounts _counts;
  late String _eol;
  late bool _hasBom;

  /// Model line lengths plus the EOL length, like `MirrorTextModel`.
  late PrefixSumComputer _modelLineStarts;

  /// Raw line lengths plus their break lengths.
  late PrefixSumComputer _rawLineStarts;

  int _versionId;
  String? _cachedModelText;

  /// `TextModel.isTooLargeForSyncing`: such a document is never sent to the
  /// extension host (`shouldSynchronizeModel`).
  late final bool isTooLargeForSyncing;

  @override
  bool get isSynchronized => !isTooLargeForSyncing;

  /// The model version: increases with every emitted event.
  @override
  int get versionId => _versionId;

  /// The model EOL (`\n` or `\r\n`).
  String get eol => _eol;

  /// Whether the raw text starts with U+FEFF (which the model omits).
  bool get hasBom => _hasBom;

  @override
  int get lineCount => _lines.length;

  /// The model's lines (`ITextModel.getLinesContent`).
  List<String> get modelLines => [
    for (var i = 0; i < _lines.length; i++) _modelLine(i),
  ];

  /// `ITextModel.getValue()`.
  String get modelText => _cachedModelText ??= modelLines.join(_eol);

  /// The raw text this mirror tracks (for checks; the editor owns it).
  String get rawText {
    final buffer = StringBuffer();
    for (var i = 0; i < _lines.length; i++) {
      buffer
        ..write(_lines[i])
        ..write(_breaks[i]);
    }
    return buffer.toString();
  }

  /// The line break kind BaoCode writes for line breaks the extension
  /// inserts: the file's most frequent kind (see [LineBreakCounts.dominant]).
  String get rawInsertEol => _counts.dominant(_eol);

  @override
  String getLineContent(int lineNumber) => _modelLine(lineNumber - 1);

  /// `IModelAddedData` for `$acceptDocumentsAndEditorsDelta`.
  ModelAddedData toModelAddedData({
    bool isDirty = false,
    String encoding = 'utf8',
  }) => ModelAddedData(
    uri: uri,
    versionId: _versionId,
    lines: modelLines,
    eol: _eol,
    languageId: languageId,
    isDirty: isDirty,
    encoding: encoding,
  );

  // --- coordinates

  @override
  Position toModelPosition(IPosition editorPosition) {
    final line = editorPosition.lineNumber;
    if (line == 1 && _hasBom) {
      return Position(
        1,
        editorPosition.column > 1 ? editorPosition.column - 1 : 1,
      );
    }
    return Position(line, editorPosition.column);
  }

  @override
  Position toEditorPosition(IPosition modelPosition) {
    final line = modelPosition.lineNumber;
    if (line == 1 && _hasBom) return Position(1, modelPosition.column + 1);
    return Position(line, modelPosition.column);
  }

  Range toModelRange(IRange editorRange) => Range.fromPositions(
    toModelPosition(Range.startPositionOf(editorRange)),
    toModelPosition(Range.endPositionOf(editorRange)),
  );

  Range toEditorRange(IRange modelRange) => Range.fromPositions(
    toEditorPosition(Range.startPositionOf(modelRange)),
    toEditorPosition(Range.endPositionOf(modelRange)),
  );

  /// The model offset of a model position (`ExtHostDocumentData.offsetAt`
  /// for a valid position).
  int modelOffsetAt(IPosition modelPosition) {
    final position = validateModelPosition(modelPosition);
    return _modelOffset(position.lineNumber - 1, position.column - 1);
  }

  /// The model position of a model offset (`positionAt`).
  Position modelPositionAt(int offset) =>
      _positionAt(_modelLineStarts, offset, _modelLineLength);

  /// The raw offset of an editor position.
  int rawOffsetAt(IPosition editorPosition) {
    final line = (editorPosition.lineNumber - 1).clamp(0, _lines.length - 1);
    final column = (editorPosition.column - 1).clamp(0, _lines[line].length);
    return (_rawLineStarts.getPrefixSum(line - 1) ?? 0) + column;
  }

  /// The editor position of a raw offset; an offset between a CR and its LF
  /// maps to the end of that line.
  Position editorPositionAt(int offset) =>
      _positionAt(_rawLineStarts, offset, (i) => _lines[i].length);

  /// Raw offset to model offset.
  int toModelOffset(int rawOffset) =>
      modelOffsetAt(toModelPosition(editorPositionAt(rawOffset)));

  /// Model offset to raw offset.
  int toRawOffset(int modelOffset) =>
      rawOffsetAt(toEditorPosition(modelPositionAt(modelOffset)));

  Position _positionAt(
    PrefixSumComputer sums,
    int offset,
    int Function(int line) lineLength,
  ) {
    final out = sums.getIndexOf(offset < 0 ? 0 : offset);
    final length = lineLength(out.index);
    final remainder = out.remainder.toInt();
    return Position(
      out.index + 1,
      (remainder < length ? remainder : length) + 1,
    );
  }

  /// `TextModel._validatePosition` (surrogate pairs are not checked).
  Position validateModelPosition(IPosition position) {
    final lineCount = _lines.length;
    if (position.lineNumber < 1) return const Position(1, 1);
    if (position.lineNumber > lineCount) {
      return Position(lineCount, _modelLineLength(lineCount - 1) + 1);
    }
    final maxColumn = _modelLineLength(position.lineNumber - 1) + 1;
    if (position.column < 1) return Position(position.lineNumber, 1);
    if (position.column > maxColumn) {
      return Position(position.lineNumber, maxColumn);
    }
    return Position(position.lineNumber, position.column);
  }

  /// `TextModel._validateRange` with `StringOffsetValidationType
  /// .SurrogatePairs`, as edits are validated: a boundary inside a surrogate
  /// pair widens over it (an empty range moves before it).
  Range validateModelRange(IRange range) {
    final start = validateModelPosition(Range.startPositionOf(range));
    final end = validateModelPosition(Range.endPositionOf(range));
    final startLineNumber = start.lineNumber;
    final startColumn = start.column;
    final endLineNumber = end.lineNumber;
    final endColumn = end.column;

    bool isHigh(int line, int column) {
      if (column <= 1) return false;
      final code = _modelLine(line - 1).codeUnitAt(column - 2);
      return code >= 0xD800 && code <= 0xDBFF;
    }

    final startInsideSurrogatePair = isHigh(startLineNumber, startColumn);
    final endInsideSurrogatePair = isHigh(endLineNumber, endColumn);
    if (!startInsideSurrogatePair && !endInsideSurrogatePair) {
      return Range(startLineNumber, startColumn, endLineNumber, endColumn);
    }
    if (startLineNumber == endLineNumber && startColumn == endColumn) {
      // do not expand a collapsed range, simply move it to a valid location
      return Range(
        startLineNumber,
        startColumn - 1,
        endLineNumber,
        endColumn - 1,
      );
    }
    if (startInsideSurrogatePair && endInsideSurrogatePair) {
      // expand range at both ends
      return Range(
        startLineNumber,
        startColumn - 1,
        endLineNumber,
        endColumn + 1,
      );
    }
    if (startInsideSurrogatePair) {
      // only expand range at the start
      return Range(startLineNumber, startColumn - 1, endLineNumber, endColumn);
    }
    // only expand range at the end
    return Range(startLineNumber, startColumn, endLineNumber, endColumn + 1);
  }

  // --- raw text to model events

  /// Applies one editor mutation (changes in order, each against the text
  /// the previous left) and returns the model event to send, or null when
  /// the model text did not change.
  ModelChangedEvent? acceptRawChanges(
    Iterable<RawContentChange> changes, {
    bool isUndoing = false,
    bool isRedoing = false,
  }) {
    final out = <ModelContentChange>[];
    for (final change in changes) {
      final modelChange = _acceptRawChange(change);
      if (modelChange != null) out.add(modelChange);
    }
    if (out.isEmpty) return null;
    _versionId++;
    return ModelChangedEvent(
      changes: out,
      eol: _eol,
      versionId: _versionId,
      isUndoing: isUndoing,
      isRedoing: isRedoing,
    );
  }

  /// [acceptRawChanges] for an [EditorDocumentModel.changes] event.
  ModelChangedEvent? acceptEditorEvent(
    EditorContentChangeEvent event, {
    bool isUndoing = false,
    bool isRedoing = false,
  }) => acceptRawChanges(
    event.changes.map(RawContentChange.fromEditor),
    isUndoing: isUndoing,
    isRedoing: isRedoing,
  );

  /// `TextModel.setValue`: the document now reads [text] (reloaded from
  /// disk); the EOL is chosen afresh. A flush event.
  ModelChangedEvent reset(String text) {
    final oldRange = _fullModelRange();
    final oldLength = _modelLength;
    _load(text);
    _versionId++;
    return ModelChangedEvent(
      changes: [
        ModelContentChange(
          range: oldRange,
          rangeOffset: 0,
          rangeLength: oldLength,
          text: modelText,
        ),
      ],
      eol: _eol,
      versionId: _versionId,
      isFlush: true,
    );
  }

  /// `TextModel.setEOL`: the model now uses [eol]; null when it already
  /// does. Make the raw text match with [rawEditsForEol].
  ModelChangedEvent? setEol(String eol) {
    final newEol = eol == '\r\n' ? '\r\n' : '\n';
    if (newEol == _eol) return null;
    final oldRange = _fullModelRange();
    final oldLength = _modelLength;
    _eol = newEol;
    _cachedModelText = null;
    _modelLineStarts = _buildModelLineStarts();
    _versionId++;
    return ModelChangedEvent(
      changes: [
        ModelContentChange(
          range: oldRange,
          rangeOffset: 0,
          rangeLength: oldLength,
          text: modelText,
        ),
      ],
      eol: _eol,
      versionId: _versionId,
      isEolChange: true,
    );
  }

  /// Raw edits that turn every line break into [eol] (for an extension's
  /// `setEndOfLine`); their changes come back as no-ops.
  List<EditorDocumentEdit> rawEditsForEol(String eol) => [
    for (var i = 0; i < _lines.length - 1; i++)
      if (_breaks[i] != eol)
        EditorDocumentEdit(Range(i + 1, _lines[i].length + 1, i + 2, 1), eol),
  ];

  ModelContentChange? _acceptRawChange(RawContentChange change) {
    // Clamp like the editor's snapshot.
    final lastLine = _lines.length - 1;
    var sl = change.startLine.clamp(0, lastLine);
    var sc = change.startCharacter.clamp(0, _lines[sl].length);
    var el = change.endLine.clamp(0, lastLine);
    var ec = change.endCharacter.clamp(0, _lines[el].length);
    if (el < sl || (el == sl && ec < sc)) {
      el = sl;
      ec = sc;
    }
    var prefix = '';
    var suffix = '';

    // Widen the replaced range so that neither of its ends can join a CR
    // and an LF into one break or split one: take in a lone CR before it
    // and a lone LF after it. Its ends are then break boundaries before and
    // after the change.
    final leftExtended = sc == 0 && sl > 0 && _breaks[sl - 1] == '\r';
    if (leftExtended) {
      sl--;
      sc = _lines[sl].length;
      prefix = '\r';
    }
    final rightExtended = ec == _lines[el].length && _breaks[el] == '\n';
    if (rightExtended) {
      el++;
      ec = 0;
      suffix = '\n';
    }

    // At the start of the text, take in whatever U+FEFF reads as the BOM
    // before or after the change.
    final atStart = sl == 0 && sc == 0;
    if (atStart) {
      if (_hasBom && el == 0 && ec == 0) {
        ec = 1;
        suffix = utf8BomCharacter;
      }
      if (prefix.isEmpty &&
          change.text.isEmpty &&
          suffix.isEmpty &&
          ec < _lines[el].length &&
          _lines[el].codeUnitAt(ec) == 0xFEFF) {
        ec++;
        suffix = utf8BomCharacter;
      }
    }
    final replacement = prefix + change.text + suffix;

    final startLine = sl;
    final startColumn = _toModelColumn(sl, sc);
    final endLine = el;
    final endColumn = _toModelColumn(el, ec);
    final startOffset = _modelOffset(startLine, startColumn);
    final endOffset = _modelOffset(endLine, endColumn);
    final newText = normalizeEol(
      atStart && replacement.startsWith(utf8BomCharacter)
          ? replacement.substring(1)
          : replacement,
      _eol,
    );

    // Give back what the widening took in when it reads the same.
    var trimStart = 0;
    var trimEnd = 0;
    if (leftExtended) trimStart = _eol.length;
    if (rightExtended &&
        endOffset - startOffset - trimStart >= _eol.length &&
        newText.length - trimStart >= _eol.length) {
      trimEnd = _eol.length;
    }
    final rangeStartLine = trimStart > 0 ? startLine + 1 : startLine;
    final rangeStartColumn = trimStart > 0 ? 0 : startColumn;
    final rangeEndLine = trimEnd > 0 ? endLine - 1 : endLine;
    final rangeEndColumn = trimEnd > 0
        ? _modelLineLength(endLine - 1)
        : endColumn;
    final rangeOffset = startOffset + trimStart;
    final rangeLength = endOffset - trimEnd - rangeOffset;
    final text = newText.substring(trimStart, newText.length - trimEnd);
    final unchanged =
        rangeLength == text.length &&
        (rangeLength == 0 ||
            _modelTextBetween(
                  rangeStartLine,
                  rangeStartColumn,
                  rangeEndLine,
                  rangeEndColumn,
                ) ==
                text);

    _replaceRaw(sl, sc, el, ec, replacement);

    if (unchanged) return null;
    return ModelContentChange(
      range: Range(
        rangeStartLine + 1,
        rangeStartColumn + 1,
        rangeEndLine + 1,
        rangeEndColumn + 1,
      ),
      rangeOffset: rangeOffset,
      rangeLength: rangeLength,
      text: text,
    );
  }

  /// Replaces raw [sl]:[sc]-[el]:[ec] (zero-based, both ends at break
  /// boundaries) with [replacement].
  void _replaceRaw(int sl, int sc, int el, int ec, String replacement) {
    final head = _lines[sl].substring(0, sc);
    final tail = _lines[el].substring(ec);
    final tailBreak = _breaks[el];
    for (var i = sl; i < el; i++) {
      _counts.count(_breaks[i], -1);
    }
    final newLines = <String>[];
    final newBreaks = <String>[];
    _split(head + replacement + tail, newLines, newBreaks);
    newBreaks[newBreaks.length - 1] = tailBreak;
    for (var i = 0; i < newBreaks.length - 1; i++) {
      _counts.count(newBreaks[i]);
    }
    _lines.replaceRange(sl, el + 1, newLines);
    _breaks.replaceRange(sl, el + 1, newBreaks);
    _hasBom = _lines[0].startsWith(utf8BomCharacter);
    _cachedModelText = null;

    final modelValues = Uint32List(newLines.length);
    final rawValues = Uint32List(newLines.length);
    for (var i = 0; i < newLines.length; i++) {
      modelValues[i] = _modelLineLength(sl + i) + _eol.length;
      rawValues[i] = newLines[i].length + newBreaks[i].length;
    }
    final removed = el - sl + 1;
    _modelLineStarts
      ..removeValues(sl, removed)
      ..insertValues(sl, modelValues);
    _rawLineStarts
      ..removeValues(sl, removed)
      ..insertValues(sl, rawValues);
  }

  // --- model edits to raw edits

  /// The raw edits (editor coordinates) that make the model read as if
  /// [edits] (model coordinates, applied simultaneously, like
  /// `pushEditOperations`) had been applied with the model EOL. Apply them
  /// with [EditorDocumentModel.applyEdits]; their changes flow back through
  /// [acceptRawChanges]. Overlapping edits throw [ArgumentError].
  List<EditorDocumentEdit> toEditorEdits(List<ModelTextEdit> edits) {
    final insertEol = rawInsertEol;
    final raw = <_RawEdit>[];
    for (var i = 0; i < edits.length; i++) {
      final range = validateModelRange(edits[i].range);
      final sl = range.startLineNumber - 1;
      final el = range.endLineNumber - 1;
      raw.add(
        _RawEdit(
          sl,
          range.startColumn - 1 + (sl == 0 && _hasBom ? 1 : 0),
          el,
          range.endColumn - 1 + (el == 0 && _hasBom ? 1 : 0),
          normalizeEol(edits[i].text ?? '', insertEol),
          i,
        ),
      );
    }
    raw.sort((a, b) {
      final start = _compare(a.sl, a.sc, b.sl, b.sc);
      if (start != 0) return start;
      final end = _compare(a.el, a.ec, b.el, b.ec);
      return end != 0 ? end : a.index.compareTo(b.index);
    });

    // Touching edits become one, so every seam below sits between an edit
    // and unchanged raw text.
    final merged = <_RawEdit>[];
    for (final edit in raw) {
      if (merged.isEmpty) {
        merged.add(edit);
        continue;
      }
      final previous = merged.last;
      final order = _compare(edit.sl, edit.sc, previous.el, previous.ec);
      if (order < 0) {
        throw ArgumentError('Overlapping ranges are not allowed!');
      }
      if (order == 0) {
        previous
          ..el = edit.el
          ..ec = edit.ec
          ..text = previous.text + edit.text;
      } else {
        merged.add(edit);
      }
    }

    final result = <EditorDocumentEdit>[];
    for (final edit in merged) {
      final crBefore =
          edit.sc == 0 && edit.sl > 0 && _breaks[edit.sl - 1] == '\r';
      final lfAfter =
          edit.ec == _lines[edit.el].length && _breaks[edit.el] == '\n';
      if (edit.text.isNotEmpty) {
        // An inserted LF after a lone CR, or an inserted CR before a lone
        // LF, would merge with it: write that break as CRLF.
        if (crBefore && edit.text.startsWith('\n')) {
          edit.text = '\r${edit.text}';
        }
        if (lfAfter && edit.text.endsWith('\r')) edit.text = '${edit.text}\n';
      } else if (crBefore && lfAfter) {
        // Deleting everything between a lone CR and a lone LF would merge
        // them: turn the CR into CRLF.
        final line = edit.sl - 1;
        edit
          ..sl = line
          ..sc = _lines[line].length
          ..text = '\r\n';
      }
      if (edit.sl == edit.el && edit.sc == edit.ec && edit.text.isEmpty) {
        continue;
      }
      result.add(
        EditorDocumentEdit(
          Range(edit.sl + 1, edit.sc + 1, edit.el + 1, edit.ec + 1),
          edit.text,
        ),
      );
    }
    return result;
  }

  // --- internals

  void _load(String text) {
    _lines = <String>[];
    _breaks = <String>[];
    _split(text, _lines, _breaks);
    _counts = LineBreakCounts();
    for (var i = 0; i < _breaks.length - 1; i++) {
      _counts.count(_breaks[i]);
    }
    _eol = _counts.modelEol(_defaultEol);
    _hasBom = _lines[0].startsWith(utf8BomCharacter);
    _cachedModelText = null;
    _modelLineStarts = _buildModelLineStarts();
    final rawValues = Uint32List(_lines.length);
    for (var i = 0; i < _lines.length; i++) {
      rawValues[i] = _lines[i].length + _breaks[i].length;
    }
    _rawLineStarts = PrefixSumComputer(rawValues);
  }

  PrefixSumComputer _buildModelLineStarts() {
    final values = Uint32List(_lines.length);
    for (var i = 0; i < _lines.length; i++) {
      values[i] = _modelLineLength(i) + _eol.length;
    }
    return PrefixSumComputer(values);
  }

  /// Splits [text] into line contents and the break after each (the last
  /// gets `''`).
  static void _split(String text, List<String> lines, List<String> breaks) {
    var start = 0;
    for (final match in lineBreakPattern.allMatches(text)) {
      lines.add(text.substring(start, match.start));
      breaks.add(match[0]!);
      start = match.end;
    }
    lines.add(text.substring(start));
    breaks.add('');
  }

  String _modelLine(int line) =>
      line == 0 && _hasBom ? _lines[0].substring(1) : _lines[line];

  int _modelLineLength(int line) =>
      _lines[line].length - (line == 0 && _hasBom ? 1 : 0);

  int _toModelColumn(int line, int rawColumn) =>
      line == 0 && _hasBom ? (rawColumn > 0 ? rawColumn - 1 : 0) : rawColumn;

  /// Model offset of zero-based [line] and [column].
  int _modelOffset(int line, int column) =>
      (_modelLineStarts.getPrefixSum(line - 1) ?? 0) + column;

  int get _modelLength => _modelLineStarts.getTotalSum() - _eol.length;

  String _modelTextBetween(int sl, int sc, int el, int ec) {
    if (sl == el) return _modelLine(sl).substring(sc, ec);
    final buffer = StringBuffer(_modelLine(sl).substring(sc));
    for (var i = sl + 1; i < el; i++) {
      buffer
        ..write(_eol)
        ..write(_modelLine(i));
    }
    buffer
      ..write(_eol)
      ..write(_modelLine(el).substring(0, ec));
    return buffer.toString();
  }

  Range _fullModelRange() {
    final last = _lines.length - 1;
    return Range(1, 1, last + 1, _modelLineLength(last) + 1);
  }

  static int _compare(int l1, int c1, int l2, int c2) =>
      l1 != l2 ? l1.compareTo(l2) : c1.compareTo(c2);
}

class _RawEdit {
  _RawEdit(this.sl, this.sc, this.el, this.ec, this.text, this.index);

  int sl;
  int sc;
  int el;
  int ec;
  String text;
  final int index;
}
