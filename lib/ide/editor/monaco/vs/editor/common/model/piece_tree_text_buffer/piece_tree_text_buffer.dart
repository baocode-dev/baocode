/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Port of VS Code pieceTreeTextBuffer.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971.
// Optional findMatchesLineByLine is deferred: it needs textModelSearch's
// SearchData/Searcher, which is not part of this port.

import '../../core/misc/eol_counter.dart';
import '../../core/position.dart';
import '../../core/range.dart';
import '../../core/text_change.dart';
import 'piece_tree_base.dart' as tree;
import 'piece_tree_text_buffer_builder.dart' as builder;

enum EndOfLinePreference { textDefined, lf, crlf }

class SingleEditOperationIdentifier {
  const SingleEditOperationIdentifier(this.major, this.minor);
  final int major;
  final int minor;
}

class ValidAnnotatedEditOperation {
  const ValidAnnotatedEditOperation(
    this.identifier,
    this.range,
    this.text, {
    this.forceMoveMarkers = false,
    this.isAutoWhitespaceEdit = false,
    this.isTracked = false,
  });

  final SingleEditOperationIdentifier? identifier;
  final Range range;
  final String? text;
  final bool forceMoveMarkers;
  final bool isAutoWhitespaceEdit;
  final bool isTracked;
}

class ValidEditOperation {
  const ValidEditOperation(
    this.identifier,
    this.range,
    this.text,
    this.textChange,
  );
  final SingleEditOperationIdentifier? identifier;
  final Range range;
  final String text;
  final TextChange textChange;
}

class InternalModelContentChange {
  const InternalModelContentChange(
    this.range,
    this.rangeLength,
    this.text,
    this.rangeOffset,
    this.forceMoveMarkers,
  );
  final Range range;
  final int rangeLength;
  final String text;
  final int rangeOffset;
  final bool forceMoveMarkers;
}

class ApplyEditsResult {
  const ApplyEditsResult(
    this.reverseEdits,
    this.changes,
    this.trimAutoWhitespaceLineNumbers,
  );
  final List<ValidEditOperation>? reverseEdits;
  final List<InternalModelContentChange> changes;
  final List<int>? trimAutoWhitespaceLineNumbers;
}

class _ValidatedEditOperation {
  _ValidatedEditOperation(
    this.sortIndex,
    this.identifier,
    this.range,
    this.rangeOffset,
    this.rangeLength,
    this.text,
    this.eolCount,
    this.firstLineLength,
    this.lastLineLength,
    this.forceMoveMarkers,
    this.isAutoWhitespaceEdit,
  );

  final int sortIndex;
  final SingleEditOperationIdentifier? identifier;
  final Range range;
  final int rangeOffset;
  final int rangeLength;
  final String text;
  final int eolCount;
  final int firstLineLength;
  final int lastLineLength;
  final bool forceMoveMarkers;
  final bool isAutoWhitespaceEdit;
}

class _ReverseEdit {
  const _ReverseEdit(this.sortIndex, this.operation);
  final int sortIndex;
  final ValidEditOperation operation;
}

class _AutoWhitespaceCandidate {
  const _AutoWhitespaceCandidate(this.lineNumber, this.oldContent);
  final int lineNumber;
  final String oldContent;
}

class PieceTreeTextBuffer {
  PieceTreeTextBuffer(
    List<tree.StringBuffer> chunks,
    this._bom,
    String eol,
    this._mightContainRTL,
    this._mightContainUnusualLineTerminators,
    bool isBasicASCII,
    bool eolNormalized,
  ) : _mightContainNonBasicASCII = !isBasicASCII,
      _pieceTree = tree.PieceTreeBase(chunks, eol, eolNormalized);

  final tree.PieceTreeBase _pieceTree;
  final String _bom;
  bool _mightContainRTL;
  bool _mightContainUnusualLineTerminators;
  bool _mightContainNonBasicASCII;
  final List<void Function()> _listeners = [];

  /// Register a content-change listener. The returned callback unsubscribes.
  void Function() onDidChangeContent(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void dispose() => _listeners.clear();

  bool equals(PieceTreeTextBuffer other) =>
      _bom == other._bom &&
      getEOL() == other.getEOL() &&
      _pieceTree.equal(other._pieceTree);
  bool mightContainRTL() => _mightContainRTL;
  bool mightContainUnusualLineTerminators() =>
      _mightContainUnusualLineTerminators;
  void resetMightContainUnusualLineTerminators() =>
      _mightContainUnusualLineTerminators = false;
  bool mightContainNonBasicASCII() => _mightContainNonBasicASCII;

  /// Recalculate flags after the Flutter bridge makes a raw tree edit.
  /// Regular [applyEdits] keeps these flags up to date without a full scan.
  void refreshContentFlags() {
    final value = getValue();
    _mightContainNonBasicASCII = !builder.isBasicASCII(value);
    _mightContainRTL = builder.containsRTL(value);
    _mightContainUnusualLineTerminators = builder
        .containsUnusualLineTerminators(value);
  }

  String getBOM() => _bom;
  String getEOL() => _pieceTree.getEOL();
  tree.PieceTreeSnapshot createSnapshot(bool preserveBOM) =>
      _pieceTree.createSnapshot(preserveBOM ? _bom : '');
  int getOffsetAt(int lineNumber, int column) =>
      _pieceTree.getOffsetAt(lineNumber, column);
  Position getPositionAt(int offset) => _pieceTree.getPositionAt(offset);
  Range getRangeAt(int start, int length) {
    final first = getPositionAt(start);
    final last = getPositionAt(start + length);
    return Range(first.lineNumber, first.column, last.lineNumber, last.column);
  }

  /// Returns buffer content, without its BOM (which belongs to the snapshot).
  String getValue() => _pieceTree.getLinesRawContent();

  String getValueInRange(
    Range range, [
    EndOfLinePreference eol = EndOfLinePreference.textDefined,
  ]) => range.isEmpty()
      ? ''
      : _pieceTree.getValueInRange(range, _getEndOfLine(eol));

  int getValueLengthInRange(
    Range range, [
    EndOfLinePreference eol = EndOfLinePreference.textDefined,
  ]) {
    if (range.isEmpty()) return 0;
    if (range.isSingleLine()) return range.endColumn - range.startColumn;
    final startOffset = getOffsetAt(range.startLineNumber, range.startColumn);
    final endOffset = getOffsetAt(range.endLineNumber, range.endColumn);
    final delta = _getEndOfLine(eol).length - getEOL().length;
    return endOffset -
        startOffset +
        delta * (range.endLineNumber - range.startLineNumber);
  }

  int getCharacterCountInRange(
    Range range, [
    EndOfLinePreference eol = EndOfLinePreference.textDefined,
  ]) {
    if (!_mightContainNonBasicASCII) return getValueLengthInRange(range, eol);
    var result = 0;
    for (
      var line = range.startLineNumber;
      line <= range.endLineNumber;
      line++
    ) {
      final content = getLineContent(line);
      final start = line == range.startLineNumber ? range.startColumn - 1 : 0;
      final end = line == range.endLineNumber
          ? range.endColumn - 1
          : content.length;
      for (var offset = start; offset < end; offset++) {
        if (content.codeUnitAt(offset) >= 0xd800 &&
            content.codeUnitAt(offset) <= 0xdbff) {
          offset++;
        }
        result++;
      }
    }
    return result +
        _getEndOfLine(eol).length *
            (range.endLineNumber - range.startLineNumber);
  }

  String getNearestChunk(int offset) => _pieceTree.getNearestChunk(offset);
  int getLength() => _pieceTree.getLength();
  int getLineCount() => _pieceTree.getLineCount();
  List<String> getLinesContent() => _pieceTree.getLinesContent();
  String getLineContent(int lineNumber) =>
      _pieceTree.getLineContent(lineNumber);
  int getLineCharCode(int lineNumber, int index) =>
      _pieceTree.getLineCharCode(lineNumber, index);
  int getCharCode(int offset) => _pieceTree.getCharCode(offset);
  int getLineLength(int lineNumber) => _pieceTree.getLineLength(lineNumber);
  int getLineMinColumn(int lineNumber) => 1;
  int getLineMaxColumn(int lineNumber) => getLineLength(lineNumber) + 1;
  static int _firstNonWhitespaceIndex(String content) {
    for (var i = 0; i < content.length; i++) {
      final code = content.codeUnitAt(i);
      if (code != 32 && code != 9) return i;
    }
    return -1;
  }

  int getLineFirstNonWhitespaceColumn(int lineNumber) {
    final index = _firstNonWhitespaceIndex(getLineContent(lineNumber));
    return index == -1 ? 0 : index + 1;
  }

  int getLineLastNonWhitespaceColumn(int lineNumber) {
    final content = getLineContent(lineNumber);
    for (var index = content.length - 1; index >= 0; index--) {
      final code = content.codeUnitAt(index);
      if (code != 32 && code != 9) return index + 2;
    }
    return 0;
  }

  String _getEndOfLine(EndOfLinePreference eol) => switch (eol) {
    EndOfLinePreference.lf => '\n',
    EndOfLinePreference.crlf => '\r\n',
    EndOfLinePreference.textDefined => getEOL(),
  };
  void setEOL(String eol) => _pieceTree.setEOL(eol);
  tree.PieceTreeBase getPieceTree() => _pieceTree;

  ApplyEditsResult applyEdits(
    List<ValidAnnotatedEditOperation> rawOperations, [
    bool recordTrimAutoWhitespace = false,
    bool computeUndoEdits = false,
  ]) {
    var mightContainRTL = _mightContainRTL;
    var mightContainUnusual = _mightContainUnusualLineTerminators;
    var mightContainNonBasicASCII = _mightContainNonBasicASCII;
    var canReduceOperations = true;
    var operations = <_ValidatedEditOperation>[];

    for (var i = 0; i < rawOperations.length; i++) {
      final op = rawOperations[i];
      if (op.isTracked) canReduceOperations = false;
      final rawText = op.text ?? '';
      if (rawText.isNotEmpty) {
        var nonAscii = true;
        if (!mightContainNonBasicASCII) {
          nonAscii = !builder.isBasicASCII(rawText);
          mightContainNonBasicASCII = nonAscii;
        }
        if (!mightContainRTL && nonAscii) {
          mightContainRTL = builder.containsRTL(rawText);
        }
        if (!mightContainUnusual && nonAscii) {
          mightContainUnusual = builder.containsUnusualLineTerminators(rawText);
        }
      }
      var text = '';
      var eolCount = 0;
      var firstLineLength = 0;
      var lastLineLength = 0;
      if (rawText.isNotEmpty) {
        final (count, first, last, strEOL) = countEOL(rawText);
        eolCount = count;
        firstLineLength = first;
        lastLineLength = last;
        final expected = getEOL() == '\r\n' ? StringEOL.crlf : StringEOL.lf;
        text = strEOL == StringEOL.unknown || strEOL == expected
            ? rawText
            : rawText.replaceAll(RegExp(r'\r\n|\r|\n'), getEOL());
      }
      operations.add(
        _ValidatedEditOperation(
          i,
          op.identifier,
          op.range,
          getOffsetAt(op.range.startLineNumber, op.range.startColumn),
          getValueLengthInRange(op.range),
          text,
          eolCount,
          firstLineLength,
          lastLineLength,
          op.forceMoveMarkers,
          op.isAutoWhitespaceEdit,
        ),
      );
    }
    operations.sort(_sortOpsAscending);
    var hasTouchingRanges = false;
    for (var i = 0; i + 1 < operations.length; i++) {
      final previousEnd = operations[i].range.getEndPosition();
      final nextStart = operations[i + 1].range.getStartPosition();
      if (nextStart.isBeforeOrEqual(previousEnd)) {
        if (nextStart.isBefore(previousEnd)) {
          throw StateError('Overlapping ranges are not allowed!');
        }
        hasTouchingRanges = true;
      }
    }
    if (canReduceOperations) operations = _reduceOperations(operations);
    final reverseRanges = computeUndoEdits || recordTrimAutoWhitespace
        ? _getInverseEditRanges(operations)
        : <Range>[];
    final candidates = <_AutoWhitespaceCandidate>[];
    if (recordTrimAutoWhitespace) {
      for (var i = 0; i < operations.length; i++) {
        final op = operations[i];
        if (!op.isAutoWhitespaceEdit || !op.range.isEmpty()) continue;
        final reverseRange = reverseRanges[i];
        for (
          var line = reverseRange.startLineNumber;
          line <= reverseRange.endLineNumber;
          line++
        ) {
          var oldContent = '';
          if (line == reverseRange.startLineNumber) {
            oldContent = getLineContent(op.range.startLineNumber);
            if (_firstNonWhitespaceIndex(oldContent) != -1) continue;
          }
          candidates.add(_AutoWhitespaceCandidate(line, oldContent));
        }
      }
    }

    List<ValidEditOperation>? reverseOperations;
    if (computeUndoEdits) {
      var delta = 0;
      final reverse = <_ReverseEdit>[];
      for (var i = 0; i < operations.length; i++) {
        final op = operations[i];
        final oldText = getValueInRange(op.range);
        final reverseOffset = op.rangeOffset + delta;
        delta += op.text.length - oldText.length;
        reverse.add(
          _ReverseEdit(
            op.sortIndex,
            ValidEditOperation(
              op.identifier,
              reverseRanges[i],
              oldText,
              TextChange(op.rangeOffset, oldText, reverseOffset, op.text),
            ),
          ),
        );
      }
      if (!hasTouchingRanges) {
        reverse.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
      }
      reverseOperations = [for (final edit in reverse) edit.operation];
    }

    _mightContainRTL = mightContainRTL;
    _mightContainUnusualLineTerminators = mightContainUnusual;
    _mightContainNonBasicASCII = mightContainNonBasicASCII;
    final changes = _doApplyEdits(operations);
    List<int>? trimAutoWhitespaceLineNumbers;
    if (recordTrimAutoWhitespace && candidates.isNotEmpty) {
      candidates.sort((a, b) => b.lineNumber.compareTo(a.lineNumber));
      trimAutoWhitespaceLineNumbers = [];
      for (var i = 0; i < candidates.length; i++) {
        final candidate = candidates[i];
        if (i > 0 && candidates[i - 1].lineNumber == candidate.lineNumber) {
          continue;
        }
        final content = getLineContent(candidate.lineNumber);
        if (content.isNotEmpty &&
            content != candidate.oldContent &&
            _firstNonWhitespaceIndex(content) == -1) {
          trimAutoWhitespaceLineNumbers.add(candidate.lineNumber);
        }
      }
    }
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
    return ApplyEditsResult(
      reverseOperations,
      changes,
      trimAutoWhitespaceLineNumbers,
    );
  }

  List<_ValidatedEditOperation> _reduceOperations(
    List<_ValidatedEditOperation> operations,
  ) {
    if (operations.length < 1000) return operations;
    final first = operations.first.range;
    final last = operations.last.range;
    final range = Range(
      first.startLineNumber,
      first.startColumn,
      last.endLineNumber,
      last.endColumn,
    );
    var line = first.startLineNumber;
    var column = first.startColumn;
    final output = <String>[];
    var forceMoveMarkers = false;
    for (final op in operations) {
      forceMoveMarkers |= op.forceMoveMarkers;
      output.add(
        getValueInRange(
          Range(line, column, op.range.startLineNumber, op.range.startColumn),
        ),
      );
      if (op.text.isNotEmpty) output.add(op.text);
      line = op.range.endLineNumber;
      column = op.range.endColumn;
    }
    final text = output.join();
    final (count, firstLength, lastLength, _) = countEOL(text);
    return [
      _ValidatedEditOperation(
        0,
        operations.first.identifier,
        range,
        getOffsetAt(range.startLineNumber, range.startColumn),
        getValueLengthInRange(range),
        text,
        count,
        firstLength,
        lastLength,
        forceMoveMarkers,
        false,
      ),
    ];
  }

  List<InternalModelContentChange> _doApplyEdits(
    List<_ValidatedEditOperation> operations,
  ) {
    operations.sort(_sortOpsDescending);
    final changes = <InternalModelContentChange>[];
    for (final op in operations) {
      if (op.range.isEmpty() && op.text.isEmpty) continue;
      _pieceTree.delete(op.rangeOffset, op.rangeLength);
      if (op.text.isNotEmpty) _pieceTree.insert(op.rangeOffset, op.text, true);
      changes.add(
        InternalModelContentChange(
          op.range,
          op.rangeLength,
          op.text,
          op.rangeOffset,
          op.forceMoveMarkers,
        ),
      );
    }
    return changes;
  }

  static Range getInverseEditRange(Range range, String text) {
    final (count, firstLength, lastLength, _) = countEOL(text);
    return count == 0
        ? Range(
            range.startLineNumber,
            range.startColumn,
            range.startLineNumber,
            range.startColumn + firstLength,
          )
        : Range(
            range.startLineNumber,
            range.startColumn,
            range.startLineNumber + count,
            lastLength + 1,
          );
  }

  static List<Range> _getInverseEditRanges(
    List<_ValidatedEditOperation> operations,
  ) {
    final result = <Range>[];
    _ValidatedEditOperation? previous;
    var previousEndLine = 0;
    var previousEndColumn = 0;
    for (final op in operations) {
      late int startLine;
      late int startColumn;
      if (previous == null) {
        startLine = op.range.startLineNumber;
        startColumn = op.range.startColumn;
      } else if (previous.range.endLineNumber == op.range.startLineNumber) {
        startLine = previousEndLine;
        startColumn =
            previousEndColumn + op.range.startColumn - previous.range.endColumn;
      } else {
        startLine =
            previousEndLine +
            op.range.startLineNumber -
            previous.range.endLineNumber;
        startColumn = op.range.startColumn;
      }
      final range = op.eolCount == 0
          ? Range(
              startLine,
              startColumn,
              startLine,
              startColumn + op.firstLineLength,
            )
          : Range(
              startLine,
              startColumn,
              startLine + op.eolCount,
              op.lastLineLength + 1,
            );
      result.add(range);
      previousEndLine = range.endLineNumber;
      previousEndColumn = range.endColumn;
      previous = op;
    }
    return result;
  }

  static int _sortOpsAscending(
    _ValidatedEditOperation a,
    _ValidatedEditOperation b,
  ) {
    final result = Range.compareRangesUsingEnds(a.range, b.range);
    return result == 0 ? a.sortIndex - b.sortIndex : result;
  }

  static int _sortOpsDescending(
    _ValidatedEditOperation a,
    _ValidatedEditOperation b,
  ) {
    final result = Range.compareRangesUsingEnds(a.range, b.range);
    return result == 0 ? b.sortIndex - a.sortIndex : -result;
  }
}
