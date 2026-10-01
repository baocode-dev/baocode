// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the VS Code project root.
// Scoped port of VS Code src/vs/editor/common/core/edits/textEdit.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971.
//
// This string-backed port covers ordered parallel replacements, normalization,
// application, inverse, position/range mapping, and replacement helpers. The
// upstream AbstractText/StringEdit integration, compose, trimming helpers and
// rich debug formatting are not ported; they need additional core abstractions.

import '../edit_operation.dart';
import '../position.dart';
import '../range.dart';

class TextEdit {
  TextEdit(List<TextReplacement> replacements)
    : replacements = List.unmodifiable(replacements) {
    for (var i = 1; i < replacements.length; i++) {
      if (!replacements[i - 1].range.getEndPosition().isBeforeOrEqual(
        replacements[i].range.getStartPosition(),
      )) {
        throw ArgumentError.value(
          replacements,
          'replacements',
          'Overlapping or unsorted edits',
        );
      }
    }
  }

  final List<TextReplacement> replacements;

  static TextEdit replace(Range range, String text) =>
      TextEdit([TextReplacement(range, text)]);

  static TextEdit delete(Range range) => replace(range, '');

  static TextEdit insert(Position position, String text) =>
      replace(Range.fromPositions(position), text);

  static TextEdit fromParallelReplacementsUnsorted(
    List<TextReplacement> replacements,
  ) => TextEdit(
    [...replacements]
      ..sort((a, b) => Range.compareRangesUsingStarts(a.range, b.range)),
  );

  /// Join touching edits and discard edits that change nothing.
  TextEdit normalize() {
    final result = <TextReplacement>[];
    for (final replacement in replacements) {
      if (result.isNotEmpty &&
          result.last.range.getEndPosition().equals(
            replacement.range.getStartPosition(),
          )) {
        final last = result.removeLast();
        result.add(
          TextReplacement(
            last.range.plusRange(replacement.range),
            last.text + replacement.text,
          ),
        );
      } else if (!replacement.isEmpty) {
        result.add(replacement);
      }
    }
    return TextEdit(result);
  }

  /// Returns a [Position] outside an edit, or the inserted [Range] inside it.
  /// At an edit's start the position stays before the insertion; at its end it
  /// moves after the insertion, matching the upstream boundary affinity.
  Object mapPosition(Position position) {
    var lineDelta = 0;
    var curLine = 0;
    var columnDeltaInCurLine = 0;
    for (final replacement in replacements) {
      final start = replacement.range.getStartPosition();
      if (position.isBeforeOrEqual(start)) break;
      final end = replacement.range.getEndPosition();
      final length = _TextLength.ofText(replacement.text);
      if (position.isBefore(end)) {
        final mappedStart = Position(
          start.lineNumber + lineDelta,
          start.column +
              (start.lineNumber + lineDelta == curLine
                  ? columnDeltaInCurLine
                  : 0),
        );
        return _rangeFromPositions(mappedStart, length.addTo(mappedStart));
      }
      if (start.lineNumber + lineDelta != curLine) columnDeltaInCurLine = 0;
      lineDelta +=
          length.lines -
          (replacement.range.endLineNumber - replacement.range.startLineNumber);
      if (length.lines == 0) {
        columnDeltaInCurLine +=
            length.columns -
            (end.lineNumber != start.lineNumber
                ? end.column - 1
                : end.column - start.column);
      } else {
        columnDeltaInCurLine = length.columns;
      }
      curLine = end.lineNumber + lineDelta;
    }
    return Position(
      position.lineNumber + lineDelta,
      position.column +
          (position.lineNumber + lineDelta == curLine
              ? columnDeltaInCurLine
              : 0),
    );
  }

  Range mapRange(Range range) {
    final start = mapPosition(range.getStartPosition());
    final end = mapPosition(range.getEndPosition());
    return _rangeFromPositions(
      start is Position ? start : (start as Range).getStartPosition(),
      end is Position ? end : (end as Range).getEndPosition(),
    );
  }

  Object inverseMapPosition(Position position, String original) =>
      inverse(original).mapPosition(position);

  Range inverseMapRange(Range range, String original) =>
      inverse(original).mapRange(range);

  String applyToString(String value) {
    final text = _StringText(value);
    final result = StringBuffer();
    var lastEnd = const Position(1, 1);
    for (final replacement in replacements) {
      result.write(
        text.ofRange(
          _rangeFromPositions(lastEnd, replacement.range.getStartPosition()),
        ),
      );
      result.write(replacement.text);
      lastEnd = replacement.range.getEndPosition();
    }
    result.write(text.ofRange(_rangeFromPositions(lastEnd, text.endPosition)));
    return result.toString();
  }

  TextEdit inverse(String original) {
    final text = _StringText(original);
    final newRanges = getNewRanges();
    return TextEdit([
      for (var i = 0; i < replacements.length; i++)
        TextReplacement(newRanges[i], text.ofRange(replacements[i].range)),
    ]);
  }

  List<Range> getNewRanges() {
    final ranges = <Range>[];
    var previousEndLine = 0;
    var lineOffset = 0;
    var columnOffset = 0;
    for (final replacement in replacements) {
      final length = _TextLength.ofText(replacement.text);
      final start = Position(
        replacement.range.startLineNumber + lineOffset,
        replacement.range.startColumn +
            (replacement.range.startLineNumber == previousEndLine
                ? columnOffset
                : 0),
      );
      final newRange = _rangeFromPositions(start, length.addTo(start));
      ranges.add(newRange);
      lineOffset = newRange.endLineNumber - replacement.range.endLineNumber;
      columnOffset = newRange.endColumn - replacement.range.endColumn;
      previousEndLine = replacement.range.endLineNumber;
    }
    return ranges;
  }

  TextReplacement toReplacement(String original) =>
      TextReplacement.joinReplacements(replacements, original);

  bool equals(TextEdit other) =>
      replacements.length == other.replacements.length &&
      List.generate(
        replacements.length,
        (i) => i,
      ).every((i) => replacements[i].equals(other.replacements[i]));
}

class TextReplacement {
  const TextReplacement(this.range, this.text);

  final Range range;
  final String text;

  static TextReplacement delete(Range range) => TextReplacement(range, '');

  static TextReplacement joinReplacements(
    List<TextReplacement> replacements,
    String original,
  ) {
    if (replacements.isEmpty) throw ArgumentError('No replacements to join');
    if (replacements.length == 1) return replacements.single;
    final source = _StringText(original);
    final value = StringBuffer();
    for (var i = 0; i < replacements.length; i++) {
      value.write(replacements[i].text);
      if (i + 1 < replacements.length) {
        value.write(
          source.ofRange(
            _rangeFromPositions(
              replacements[i].range.getEndPosition(),
              replacements[i + 1].range.getStartPosition(),
            ),
          ),
        );
      }
    }
    return TextReplacement(
      _rangeFromPositions(
        replacements.first.range.getStartPosition(),
        replacements.last.range.getEndPosition(),
      ),
      value.toString(),
    );
  }

  bool get isEmpty => range.isEmpty() && text.isEmpty;

  bool equals(TextReplacement other) =>
      range.equalsRange(other.range) && text == other.text;

  ISingleEditOperation toSingleEditOperation() =>
      SingleEditOperation(range, text);

  TextEdit toEdit() => TextEdit([this]);

  TextReplacement extendToCoverRange(Range other, String original) {
    if (range.containsRange(other)) return this;
    final combined = range.plusRange(other);
    final source = _StringText(original);
    return TextReplacement(
      combined,
      source.ofRange(
            _rangeFromPositions(
              combined.getStartPosition(),
              range.getStartPosition(),
            ),
          ) +
          text +
          source.ofRange(
            _rangeFromPositions(
              range.getEndPosition(),
              combined.getEndPosition(),
            ),
          ),
    );
  }

  @override
  String toString() =>
      '(${range.startLineNumber},${range.startColumn} -> '
      '${range.endLineNumber},${range.endColumn}): "$text"';
}

Range _rangeFromPositions(Position start, Position end) {
  if (!start.isBeforeOrEqual(end)) {
    throw ArgumentError('Range start must be before end');
  }
  return Range.fromPositions(start, end);
}

// Corresponds to the ofText/addToPosition part of upstream TextLength. Dart's
// string indices count UTF-16 code units, just like VS Code's text offsets.
class _TextLength {
  const _TextLength(this.lines, this.columns);

  final int lines;
  final int columns;

  static _TextLength ofText(String text) {
    final lastNewline = text.lastIndexOf('\n');
    if (lastNewline < 0) return _TextLength(0, text.length);
    var lines = 0;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) lines++;
    }
    return _TextLength(lines, text.length - lastNewline - 1);
  }

  Position addTo(Position position) => lines == 0
      ? Position(position.lineNumber, position.column + columns)
      : Position(position.lineNumber + lines, columns + 1);
}

// StringText/PositionOffsetTransformer's range lookup, kept private until
// those upstream abstractions are ported. Clamp invalid positions just as the
// upstream transformer does, excluding CR immediately before LF from columns.
class _StringText {
  _StringText(this.value) {
    lineStarts.add(0);
    for (var i = 0; i < value.length; i++) {
      if (value.codeUnitAt(i) == 10) {
        lineEnds.add(i > 0 && value.codeUnitAt(i - 1) == 13 ? i - 1 : i);
        lineStarts.add(i + 1);
      }
    }
    lineEnds.add(value.length);
  }

  final String value;
  final List<int> lineStarts = [];
  final List<int> lineEnds = [];

  Position get endPosition =>
      Position(lineStarts.length, value.length - lineStarts.last + 1);

  int _offset(Position position) {
    if (position.lineNumber < 1) return 0;
    if (position.lineNumber > lineStarts.length) return value.length;
    final index = position.lineNumber - 1;
    return lineStarts[index] +
        (position.column - 1).clamp(0, lineEnds[index] - lineStarts[index]);
  }

  String ofRange(Range range) => value.substring(
    _offset(range.getStartPosition()),
    _offset(range.getEndPosition()),
  );
}
