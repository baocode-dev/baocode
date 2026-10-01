// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/ide/editor/monaco/LICENSE.txt.
// Ported from src/vs/editor/common/diff/rangeMapping.ts (pinned VS Code).

import '../core/position.dart';
import '../core/range.dart';

/// One-based, half-open line interval. See upstream core/ranges/lineRange.ts.
class LineRange {
  LineRange(this.startLineNumber, this.endLineNumberExclusive) {
    if (startLineNumber > endLineNumberExclusive) {
      throw ArgumentError('Invalid line range: $this');
    }
  }

  final int startLineNumber;
  final int endLineNumberExclusive;

  int get length => endLineNumberExclusive - startLineNumber;
  bool get isEmpty => length == 0;

  LineRange join(LineRange other) => LineRange(
    startLineNumber < other.startLineNumber
        ? startLineNumber
        : other.startLineNumber,
    endLineNumberExclusive > other.endLineNumberExclusive
        ? endLineNumberExclusive
        : other.endLineNumberExclusive,
  );

  LineRange? intersect(LineRange other) {
    final start = startLineNumber > other.startLineNumber
        ? startLineNumber
        : other.startLineNumber;
    final end = endLineNumberExclusive < other.endLineNumberExclusive
        ? endLineNumberExclusive
        : other.endLineNumberExclusive;
    return start <= end ? LineRange(start, end) : null;
  }

  bool intersectsOrTouches(LineRange other) =>
      startLineNumber <= other.endLineNumberExclusive &&
      other.startLineNumber <= endLineNumberExclusive;

  @override
  String toString() => '[$startLineNumber,$endLineNumberExclusive)';
}

/// Maps a line range in the original document to the modified document.
class LineRangeMapping {
  const LineRangeMapping(this.original, this.modified);

  final LineRange original;
  final LineRange modified;

  static List<LineRangeMapping> inverse(
    List<LineRangeMapping> mappings,
    int originalLineCount,
    int modifiedLineCount,
  ) {
    final result = <LineRangeMapping>[];
    var originalEnd = 1;
    var modifiedEnd = 1;
    for (final mapping in mappings) {
      if (mapping.modified.startLineNumber > modifiedEnd) {
        result.add(
          LineRangeMapping(
            LineRange(originalEnd, mapping.original.startLineNumber),
            LineRange(modifiedEnd, mapping.modified.startLineNumber),
          ),
        );
      }
      originalEnd = mapping.original.endLineNumberExclusive;
      modifiedEnd = mapping.modified.endLineNumberExclusive;
    }
    if (modifiedEnd <= modifiedLineCount) {
      result.add(
        LineRangeMapping(
          LineRange(originalEnd, originalLineCount + 1),
          LineRange(modifiedEnd, modifiedLineCount + 1),
        ),
      );
    }
    return result;
  }

  static List<LineRangeMapping> clip(
    List<LineRangeMapping> mappings,
    LineRange originalRange,
    LineRange modifiedRange,
  ) => [
    for (final mapping in mappings)
      if (mapping.original.intersect(originalRange)
          case final LineRange original)
        if (!original.isEmpty)
          if (mapping.modified.intersect(modifiedRange)
              case final LineRange modified)
            if (!modified.isEmpty) LineRangeMapping(original, modified),
  ];

  LineRangeMapping flip() => LineRangeMapping(modified, original);
  LineRangeMapping join(LineRangeMapping other) => LineRangeMapping(
    original.join(other.original),
    modified.join(other.modified),
  );
  int get changedLineCount =>
      original.length > modified.length ? original.length : modified.length;

  /// Uses concrete line lengths rather than upstream's MAX_SAFE_INTEGER sentinel.
  /// Assumes neither input document is an empty array (Monaco represents empty as ['']).
  RangeMapping toRangeMapping2(
    List<String> originalLines,
    List<String> modifiedLines,
  ) {
    if (original.endLineNumberExclusive <= originalLines.length &&
        modified.endLineNumberExclusive <= modifiedLines.length) {
      return RangeMapping(
        Range(original.startLineNumber, 1, original.endLineNumberExclusive, 1),
        Range(modified.startLineNumber, 1, modified.endLineNumberExclusive, 1),
      );
    }
    if (!original.isEmpty && !modified.isEmpty) {
      return RangeMapping(
        Range.fromPositions(
          Position(original.startLineNumber, 1),
          _normalize(
            Position(original.endLineNumberExclusive - 1, 0x7fffffff),
            originalLines,
          ),
        ),
        Range.fromPositions(
          Position(modified.startLineNumber, 1),
          _normalize(
            Position(modified.endLineNumberExclusive - 1, 0x7fffffff),
            modifiedLines,
          ),
        ),
      );
    }
    if (original.startLineNumber > 1 && modified.startLineNumber > 1) {
      return RangeMapping(
        Range.fromPositions(
          _normalize(
            Position(original.startLineNumber - 1, 0x7fffffff),
            originalLines,
          ),
          _normalize(
            Position(original.endLineNumberExclusive - 1, 0x7fffffff),
            originalLines,
          ),
        ),
        Range.fromPositions(
          _normalize(
            Position(modified.startLineNumber - 1, 0x7fffffff),
            modifiedLines,
          ),
          _normalize(
            Position(modified.endLineNumberExclusive - 1, 0x7fffffff),
            modifiedLines,
          ),
        ),
      );
    }
    throw StateError('Invalid diff: $this');
  }

  @override
  String toString() => '{$original->$modified}';
}

Position _normalize(Position position, List<String> lines) {
  if (position.lineNumber < 1) return const Position(1, 1);
  if (position.lineNumber > lines.length) {
    return Position(lines.length, lines.last.length + 1);
  }
  final maxColumn = lines[position.lineNumber - 1].length + 1;
  return Position(
    position.lineNumber,
    position.column > maxColumn ? maxColumn : position.column,
  );
}

class DetailedLineRangeMapping extends LineRangeMapping {
  const DetailedLineRangeMapping(
    super.original,
    super.modified,
    this.innerChanges,
  );

  /// Null when not computed; otherwise nonempty character-level mappings.
  final List<RangeMapping>? innerChanges;

  @override
  DetailedLineRangeMapping flip() => DetailedLineRangeMapping(
    modified,
    original,
    innerChanges?.map((change) => change.flip()).toList(),
  );

  DetailedLineRangeMapping withInnerChangesFromLineRanges(
    List<String> originalLines,
    List<String> modifiedLines,
  ) => DetailedLineRangeMapping(original, modified, [
    toRangeMapping2(originalLines, modifiedLines),
  ]);
}

class RangeMapping {
  const RangeMapping(this.originalRange, this.modifiedRange);
  final Range originalRange;
  final Range modifiedRange;

  RangeMapping flip() => RangeMapping(modifiedRange, originalRange);
  RangeMapping join(RangeMapping other) => RangeMapping(
    originalRange.plusRange(other.originalRange),
    modifiedRange.plusRange(other.modifiedRange),
  );

  static void assertSorted(List<RangeMapping> mappings) {
    for (var i = 1; i < mappings.length; i++) {
      if (!mappings[i - 1].originalRange.getEndPosition().isBeforeOrEqual(
            mappings[i].originalRange.getStartPosition(),
          ) ||
          !mappings[i - 1].modifiedRange.getEndPosition().isBeforeOrEqual(
            mappings[i].modifiedRange.getStartPosition(),
          )) {
        throw StateError('Range mappings must be sorted');
      }
    }
  }

  @override
  String toString() => '{$originalRange->$modifiedRange}';
}

/// Port of getLineRangeMapping: a trailing newline is not a change to the next line,
/// and a change starting after the last character does not affect its first line.
DetailedLineRangeMapping getLineRangeMapping(
  RangeMapping mapping,
  List<String> original,
  List<String> modified,
) {
  final orig = mapping.originalRange;
  final mod = mapping.modifiedRange;
  var startDelta = 0;
  var endDelta = 0;
  if (mod.endColumn == 1 &&
      orig.endColumn == 1 &&
      orig.startLineNumber <= orig.endLineNumber &&
      mod.startLineNumber <= mod.endLineNumber) {
    endDelta = -1;
  }
  if (mod.startColumn - 1 >= modified[mod.startLineNumber - 1].length &&
      orig.startColumn - 1 >= original[orig.startLineNumber - 1].length &&
      orig.startLineNumber <= orig.endLineNumber + endDelta &&
      mod.startLineNumber <= mod.endLineNumber + endDelta) {
    startDelta = 1;
  }
  return DetailedLineRangeMapping(
    LineRange(
      orig.startLineNumber + startDelta,
      orig.endLineNumber + 1 + endDelta,
    ),
    LineRange(
      mod.startLineNumber + startDelta,
      mod.endLineNumber + 1 + endDelta,
    ),
    [mapping],
  );
}

/// Groups touching character edits into detailed line changes, as in rangeMapping.ts.
List<DetailedLineRangeMapping> lineRangeMappingFromRangeMappings(
  List<RangeMapping> alignments,
  List<String> original,
  List<String> modified, {
  bool dontAssertStartLine = false,
}) {
  final result = <DetailedLineRangeMapping>[];
  for (final alignment in alignments) {
    final next = getLineRangeMapping(alignment, original, modified);
    if (result.isNotEmpty &&
        (result.last.original.intersectsOrTouches(next.original) ||
            result.last.modified.intersectsOrTouches(next.modified))) {
      final previous = result.removeLast();
      result.add(
        DetailedLineRangeMapping(
          previous.original.join(next.original),
          previous.modified.join(next.modified),
          [...previous.innerChanges!, alignment],
        ),
      );
    } else {
      result.add(next);
    }
  }
  if (!dontAssertStartLine && result.isNotEmpty) {
    if (result.first.original.startLineNumber !=
            result.first.modified.startLineNumber ||
        original.length + 1 - result.last.original.endLineNumberExclusive !=
            modified.length + 1 - result.last.modified.endLineNumberExclusive) {
      throw StateError('Unaligned line changes');
    }
  }
  for (var i = 1; i < result.length; i++) {
    final previous = result[i - 1];
    final current = result[i];
    if (current.original.startLineNumber -
                previous.original.endLineNumberExclusive !=
            current.modified.startLineNumber -
                previous.modified.endLineNumberExclusive ||
        current.original.startLineNumber <=
            previous.original.endLineNumberExclusive ||
        current.modified.startLineNumber <=
            previous.modified.endLineNumberExclusive) {
      throw StateError('Line changes must be ordered and separated');
    }
  }
  return result;
}
