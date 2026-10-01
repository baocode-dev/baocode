// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/monaco/LICENSE.txt.
// Ported from src/vs/editor/common/diff/defaultLinesDiffComputer/defaultLinesDiffComputer.ts.

import 'dart:math' as math;

import '../../core/range.dart';
import '../range_mapping.dart';
import 'algorithms.dart';
import 'char_sequence.dart';
import 'heuristics.dart';

class LinesDiffComputerOptions {
  const LinesDiffComputerOptions({
    this.ignoreTrimWhitespace = false,
    this.maxComputationTimeMs = 0,
    this.computeMoves = false,
    this.extendToSubwords = false,
  });
  final bool ignoreTrimWhitespace;

  /// Zero disables the timeout, as in VS Code.
  final int maxComputationTimeMs;
  final bool computeMoves;
  final bool extendToSubwords;
}

class LinesDiff {
  const LinesDiff(this.changes, this.moves, this.hitTimeout);
  final List<DetailedLineRangeMapping> changes;
  final List<MovedText> moves;
  final bool hitTimeout;
}

class MovedText {
  const MovedText(this.lineRangeMapping, this.changes);
  final LineRangeMapping lineRangeMapping;
  final List<DetailedLineRangeMapping> changes;
  MovedText flip() => MovedText(
    lineRangeMapping.flip(),
    changes.map((change) => change.flip()).toList(),
  );
}

class DefaultLinesDiffComputer {
  LinesDiff computeDiff(
    List<String> originalLines,
    List<String> modifiedLines,
    LinesDiffComputerOptions options,
  ) {
    if (originalLines.isEmpty || modifiedLines.isEmpty) {
      throw ArgumentError('Monaco requires at least one line per document');
    }
    if (originalLines.length <= 1 &&
        _equalLines(originalLines, modifiedLines)) {
      return const LinesDiff([], [], false);
    }
    if (originalLines.length == 1 && originalLines.first.isEmpty ||
        modifiedLines.length == 1 && modifiedLines.first.isEmpty) {
      return LinesDiff(
        [
          DetailedLineRangeMapping(
            LineRange(1, originalLines.length + 1),
            LineRange(1, modifiedLines.length + 1),
            [
              RangeMapping(
                Range(
                  1,
                  1,
                  originalLines.length,
                  originalLines.last.length + 1,
                ),
                Range(
                  1,
                  1,
                  modifiedLines.length,
                  modifiedLines.last.length + 1,
                ),
              ),
            ],
          ),
        ],
        [],
        false,
      );
    }
    final timeout = DiffTimeout(options.maxComputationTimeMs);
    final considerWhitespace = !options.ignoreTrimWhitespace;
    final hashes = <String, int>{};
    int hash(String line) =>
        hashes.putIfAbsent(line.trim(), () => hashes.length);
    final originalHashes = originalLines.map(hash).toList();
    final modifiedHashes = modifiedLines.map(hash).toList();
    final first = LineSequence(originalHashes, originalLines);
    final second = LineSequence(modifiedHashes, modifiedLines);
    final lineDiff = first.length + second.length < 1700
        ? dynamicProgrammingDiff(
            first,
            second,
            timeout,
            equalityScore: (i, j) => originalLines[i] == modifiedLines[j]
                ? modifiedLines[j].isEmpty
                      ? 0.1
                      : 1 + math.log(1 + modifiedLines[j].length)
                : 0.99,
          )
        : myersDiff(first, second, timeout);
    var lineAlignments = optimizeSequenceDiffs(first, second, lineDiff.diffs);
    lineAlignments = removeVeryShortMatchingLines(first, lineAlignments);
    final alignments = <RangeMapping>[];
    var hitTimeout = lineDiff.hitTimeout;
    var previousOriginal = 0;
    var previousModified = 0;

    void scanEqualLines(int count) {
      if (!considerWhitespace) return;
      for (var i = 0; i < count; i++) {
        final a = previousOriginal + i;
        final b = previousModified + i;
        if (originalLines[a] != modifiedLines[b]) {
          final refined = _refine(
            originalLines,
            modifiedLines,
            SequenceDiff(OffsetRange(a, a + 1), OffsetRange(b, b + 1)),
            timeout,
            considerWhitespace,
            options,
          );
          alignments.addAll(refined.diffs);
          hitTimeout |= refined.hitTimeout;
        }
      }
    }

    for (final line in lineAlignments) {
      if (line.seq1Range.start - previousOriginal !=
          line.seq2Range.start - previousModified) {
        throw StateError('Unaligned line diff');
      }
      scanEqualLines(line.seq1Range.start - previousOriginal);
      previousOriginal = line.seq1Range.endExclusive;
      previousModified = line.seq2Range.endExclusive;
      final refined = _refine(
        originalLines,
        modifiedLines,
        line,
        timeout,
        considerWhitespace,
        options,
      );
      alignments.addAll(refined.diffs);
      hitTimeout |= refined.hitTimeout;
    }
    scanEqualLines(originalLines.length - previousOriginal);
    final changes = lineRangeMappingFromRangeMappings(
      alignments,
      originalLines,
      modifiedLines,
    );
    final moves = options.computeMoves && timeout.isValid
        ? _computeMoves(
            changes,
            originalLines,
            modifiedLines,
            timeout,
            considerWhitespace,
            options,
          )
        : <MovedText>[];
    for (final change in changes) {
      for (final inner in change.innerChanges!) {
        for (final position in [
          inner.originalRange.getStartPosition(),
          inner.originalRange.getEndPosition(),
        ]) {
          if (position.lineNumber < 1 ||
              position.lineNumber > originalLines.length ||
              position.column < 1 ||
              position.column >
                  originalLines[position.lineNumber - 1].length + 1) {
            throw StateError('Invalid original diff range: $inner');
          }
        }
        for (final position in [
          inner.modifiedRange.getStartPosition(),
          inner.modifiedRange.getEndPosition(),
        ]) {
          if (position.lineNumber < 1 ||
              position.lineNumber > modifiedLines.length ||
              position.column < 1 ||
              position.column >
                  modifiedLines[position.lineNumber - 1].length + 1) {
            throw StateError('Invalid modified diff range: $inner');
          }
        }
      }
    }
    return LinesDiff(changes, moves, hitTimeout);
  }

  _Refinement _refine(
    List<String> original,
    List<String> modified,
    SequenceDiff diff,
    DiffTimeout timeout,
    bool considerWhitespace,
    LinesDiffComputerOptions options,
  ) {
    final mapping = LineRangeMapping(
      LineRange(diff.seq1Range.start + 1, diff.seq1Range.endExclusive + 1),
      LineRange(diff.seq2Range.start + 1, diff.seq2Range.endExclusive + 1),
    ).toRangeMapping2(original, modified);
    final first = LinesSliceCharSequence(
      original,
      mapping.originalRange,
      considerWhitespace,
    );
    final second = LinesSliceCharSequence(
      modified,
      mapping.modifiedRange,
      considerWhitespace,
    );
    final characterDiff = first.length + second.length < 500
        ? dynamicProgrammingDiff(first, second, timeout)
        : myersDiff(first, second, timeout);
    var diffs = optimizeSequenceDiffs(first, second, characterDiff.diffs);
    diffs = extendDiffsToEntireWordIfAppropriate(first, second, diffs);
    if (options.extendToSubwords) {
      diffs = extendDiffsToEntireWordIfAppropriate(
        first,
        second,
        diffs,
        subword: true,
      );
    }
    diffs = removeShortMatches(diffs);
    diffs = removeVeryShortMatchingText(first, second, diffs);
    return _Refinement([
      for (final change in diffs)
        RangeMapping(
          first.translateRange(change.seq1Range),
          second.translateRange(change.seq2Range),
        ),
    ], characterDiff.hitTimeout);
  }

  /// The simple deletion/insertion move matcher from computeMovedLines.ts.
  /// The more involved three-line hash matcher and extension for unchanged moves
  /// are not included in this initial port.
  List<MovedText> _computeMoves(
    List<DetailedLineRangeMapping> changes,
    List<String> original,
    List<String> modified,
    DiffTimeout timeout,
    bool considerWhitespace,
    LinesDiffComputerOptions options,
  ) {
    final insertions = [
      for (final change in changes)
        if (change.original.isEmpty && change.modified.length >= 3) change,
    ];
    final moves = <MovedText>[];
    for (final deletion in changes) {
      if (!deletion.modified.isEmpty || deletion.original.length < 3) continue;
      DetailedLineRangeMapping? best;
      var highest = -1.0;
      for (final insertion in insertions) {
        final similarity = _fragmentSimilarity(
          deletion.original,
          original,
          insertion.modified,
          modified,
        );
        if (similarity > highest) {
          highest = similarity;
          best = insertion;
        }
      }
      if (highest > 0.90 && best != null) {
        insertions.remove(best);
        final mapping = LineRangeMapping(deletion.original, best.modified);
        final refined = _refine(
          original,
          modified,
          SequenceDiff(
            OffsetRange(
              mapping.original.startLineNumber - 1,
              mapping.original.endLineNumberExclusive - 1,
            ),
            OffsetRange(
              mapping.modified.startLineNumber - 1,
              mapping.modified.endLineNumberExclusive - 1,
            ),
          ),
          timeout,
          considerWhitespace,
          options,
        );
        final inner = lineRangeMappingFromRangeMappings(
          refined.diffs,
          original,
          modified,
          dontAssertStartLine: true,
        );
        final lines = original
            .sublist(
              deletion.original.startLineNumber - 1,
              deletion.original.endLineNumberExclusive - 1,
            )
            .map((line) => line.trim())
            .toList();
        if (lines.join('\n').length >= 15 &&
            lines.where((line) => line.length >= 2).length >= 2) {
          moves.add(MovedText(mapping, inner));
        }
      }
      if (!timeout.isValid) break;
    }
    return moves;
  }
}

bool _equalLines(List<String> first, List<String> second) {
  if (first.length != second.length) return false;
  for (var i = 0; i < first.length; i++) {
    if (first[i] != second[i]) return false;
  }
  return true;
}

/// Same line/character histogram and >0.90 threshold as upstream.
double _fragmentSimilarity(
  LineRange a,
  List<String> original,
  LineRange b,
  List<String> modified,
) {
  Map<int, int> histogram(LineRange range, List<String> lines) {
    final counts = <int, int>{};
    for (
      var i = range.startLineNumber - 1;
      i < range.endLineNumberExclusive - 1;
      i++
    ) {
      for (final code in [...lines[i].codeUnits, 10]) {
        counts[code] = (counts[code] ?? 0) + 1;
      }
    }
    return counts;
  }

  final first = histogram(a, original);
  final second = histogram(b, modified);
  final total =
      first.values.fold<int>(0, (sum, n) => sum + n) +
      second.values.fold<int>(0, (sum, n) => sum + n);
  if (total == 0) return 0;
  var difference = 0;
  for (final key in {...first.keys, ...second.keys}) {
    difference += ((first[key] ?? 0) - (second[key] ?? 0)).abs();
  }
  return 1 - difference / total;
}

class _Refinement {
  const _Refinement(this.diffs, this.hitTimeout);
  final List<RangeMapping> diffs;
  final bool hitTimeout;
}
