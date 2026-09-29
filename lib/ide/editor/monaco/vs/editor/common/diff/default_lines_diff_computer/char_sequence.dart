// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/ide/editor/monaco/LICENSE.txt.
// Ported from defaultLinesDiffComputer/{lineSequence,linesSliceCharSequence}.ts.

import '../../core/position.dart';
import '../../core/range.dart';
import 'algorithms.dart';

class LineSequence implements DiffSequence {
  const LineSequence(this.hashes, this.lines);
  final List<int> hashes;
  final List<String> lines;
  @override
  int get length => hashes.length;
  @override
  int getElement(int index) => hashes[index];
  @override
  bool isStronglyEqual(int first, int second) => lines[first] == lines[second];
  String getText(OffsetRange range) =>
      lines.sublist(range.start, range.endExclusive).join('\n');
  @override
  int getBoundaryScore(int offset) {
    int indent(String text) {
      var i = 0;
      while (i < text.length &&
          (text.codeUnitAt(i) == 32 || text.codeUnitAt(i) == 9)) {
        i++;
      }
      return i;
    }

    return 1000 -
        (offset == 0 ? 0 : indent(lines[offset - 1])) -
        (offset == length ? 0 : indent(lines[offset]));
  }
}

/// UTF-16 code units and synthetic LF between editor lines, just as upstream.
class LinesSliceCharSequence implements DiffSequence {
  LinesSliceCharSequence(
    this.lines,
    this.range,
    this.considerWhitespaceChanges,
  ) {
    firstElementOffsetByLine.add(0);
    for (
      var lineNumber = range.startLineNumber;
      lineNumber <= range.endLineNumber;
      lineNumber++
    ) {
      var line = lines[lineNumber - 1];
      var start = 0;
      if (lineNumber == range.startLineNumber && range.startColumn > 1) {
        start = range.startColumn - 1;
        line = line.substring(start);
      }
      lineStartOffsets.add(start);
      var trimmed = 0;
      if (!considerWhitespaceChanges) {
        final withoutLeading = line.trimLeft();
        trimmed = line.length - withoutLeading.length;
        line = withoutLeading.trimRight();
      }
      trimmedWsLengths.add(trimmed);
      final count = lineNumber == range.endLineNumber
          ? (range.endColumn - 1 - start - trimmed).clamp(0, line.length)
          : line.length;
      elements.addAll(line.codeUnits.take(count));
      if (lineNumber < range.endLineNumber) {
        elements.add(10);
        firstElementOffsetByLine.add(elements.length);
      }
    }
  }
  final List<String> lines;
  final Range range;
  final bool considerWhitespaceChanges;
  final List<int> elements = [];
  final List<int> firstElementOffsetByLine = [];
  final List<int> lineStartOffsets = [];
  final List<int> trimmedWsLengths = [];

  @override
  int get length => elements.length;
  @override
  int getElement(int index) => elements[index];
  @override
  bool isStronglyEqual(int first, int second) =>
      elements[first] == elements[second];
  String getText(OffsetRange range) =>
      String.fromCharCodes(elements.sublist(range.start, range.endExclusive));

  Position translateOffset(int offset, {bool preferLeft = false}) {
    var low = 0;
    var high = firstElementOffsetByLine.length;
    while (low + 1 < high) {
      final mid = (low + high) ~/ 2;
      if (firstElementOffsetByLine[mid] <= offset) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final lineOffset = offset - firstElementOffsetByLine[low];
    return Position(
      range.startLineNumber + low,
      1 +
          lineStartOffsets[low] +
          lineOffset +
          (lineOffset == 0 && preferLeft ? 0 : trimmedWsLengths[low]),
    );
  }

  Range translateRange(OffsetRange range) {
    final start = translateOffset(range.start);
    final end = translateOffset(range.endExclusive, preferLeft: true);
    return Range.fromPositions(end.isBefore(start) ? end : start, end);
  }

  OffsetRange? findWordContaining(int offset, {bool subword = false}) {
    if (offset < 0 || offset >= length || !_isWord(elements[offset])) {
      return null;
    }
    var start = offset;
    while (start > 0 &&
        _isWord(elements[start - 1]) &&
        (!subword || !_isUpper(elements[start]))) {
      start--;
    }
    var end = offset;
    while (end < length &&
        _isWord(elements[end]) &&
        (!subword || !_isUpper(elements[end]) || end == offset)) {
      end++;
    }
    return OffsetRange(start, end);
  }

  int countLinesIn(OffsetRange range) =>
      translateOffset(range.endExclusive).lineNumber -
      translateOffset(range.start).lineNumber;

  OffsetRange extendToFullLines(OffsetRange range) {
    var start = 0;
    var end = length;
    for (final offset in firstElementOffsetByLine) {
      if (offset <= range.start) start = offset;
      if (offset >= range.endExclusive) {
        end = offset;
        break;
      }
    }
    return OffsetRange(start, end);
  }

  @override
  int getBoundaryScore(int offset) {
    final previous = _category(offset > 0 ? elements[offset - 1] : -1);
    final next = _category(offset < length ? elements[offset] : -1);
    if (previous == 7 && next == 8) return 0; // never break CRLF
    if (previous == 8) return 150;
    final values = [0, 0, 0, 10, 2, 30, 3, 10, 10];
    return (previous != next ? 10 + (previous == 0 && next == 1 ? 1 : 0) : 0) +
        values[previous] +
        values[next];
  }
}

bool _isUpper(int code) => code >= 65 && code <= 90;
bool _isWord(int code) =>
    code >= 97 && code <= 122 || _isUpper(code) || code >= 48 && code <= 57;
int _category(int code) {
  if (code == 10) return 8;
  if (code == 13) return 7;
  if (code == 32 || code == 9) return 6;
  if (code >= 97 && code <= 122) return 0;
  if (_isUpper(code)) return 1;
  if (code >= 48 && code <= 57) return 2;
  if (code == -1) return 3;
  if (code == 44 || code == 59) return 5;
  return 4;
}
