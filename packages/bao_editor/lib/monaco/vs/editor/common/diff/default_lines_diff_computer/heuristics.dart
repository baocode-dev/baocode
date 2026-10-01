// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/monaco/LICENSE.txt.
// Port of the sequence-shifting and short-match heuristics in
// defaultLinesDiffComputer/heuristicSequenceOptimizations.ts.

import 'dart:math' as math;

import 'algorithms.dart';
import 'char_sequence.dart';

List<SequenceDiff> optimizeSequenceDiffs(
  DiffSequence first,
  DiffSequence second,
  List<SequenceDiff> diffs,
) {
  var result = _joinByShifting(first, second, diffs);
  result = _joinByShifting(first, second, result);
  for (var i = 0; i < result.length; i++) {
    final previous = i > 0 ? result[i - 1] : null;
    final next = i + 1 < result.length ? result[i + 1] : null;
    final diff = result[i];
    final valid1 = OffsetRange(
      previous == null ? 0 : previous.seq1Range.endExclusive + 1,
      next == null ? first.length : next.seq1Range.start - 1,
    );
    final valid2 = OffsetRange(
      previous == null ? 0 : previous.seq2Range.endExclusive + 1,
      next == null ? second.length : next.seq2Range.start - 1,
    );
    if (diff.seq1Range.isEmpty) {
      result[i] = _shift(diff, first, second, valid1, valid2);
    } else if (diff.seq2Range.isEmpty) {
      result[i] = _shift(diff.swap(), second, first, valid2, valid1).swap();
    }
  }
  return result;
}

List<SequenceDiff> _joinByShifting(
  DiffSequence first,
  DiffSequence second,
  List<SequenceDiff> diffs,
) {
  if (diffs.isEmpty) return diffs;
  final left = <SequenceDiff>[diffs.first];
  for (final change in diffs.skip(1)) {
    final previous = left.last;
    var current = change;
    if (current.seq1Range.isEmpty || current.seq2Range.isEmpty) {
      final distance =
          current.seq1Range.start - previous.seq1Range.endExclusive;
      var shift = 1;
      while (shift <= distance &&
          first.getElement(current.seq1Range.start - shift) ==
              first.getElement(current.seq1Range.endExclusive - shift) &&
          second.getElement(current.seq2Range.start - shift) ==
              second.getElement(current.seq2Range.endExclusive - shift)) {
        shift++;
      }
      shift--;
      if (shift == distance) {
        left[left.length - 1] = SequenceDiff(
          OffsetRange(
            previous.seq1Range.start,
            current.seq1Range.endExclusive - distance,
          ),
          OffsetRange(
            previous.seq2Range.start,
            current.seq2Range.endExclusive - distance,
          ),
        );
        continue;
      }
      current = current.delta(-shift);
    }
    left.add(current);
  }
  final right = <SequenceDiff>[];
  for (var i = 0; i < left.length - 1; i++) {
    final next = left[i + 1];
    var current = left[i];
    if (current.seq1Range.isEmpty || current.seq2Range.isEmpty) {
      final distance = next.seq1Range.start - current.seq1Range.endExclusive;
      var shift = 0;
      while (shift < distance &&
          first.isStronglyEqual(
            current.seq1Range.start + shift,
            current.seq1Range.endExclusive + shift,
          ) &&
          second.isStronglyEqual(
            current.seq2Range.start + shift,
            current.seq2Range.endExclusive + shift,
          )) {
        shift++;
      }
      if (shift == distance) {
        left[i + 1] = SequenceDiff(
          OffsetRange(
            current.seq1Range.start + distance,
            next.seq1Range.endExclusive,
          ),
          OffsetRange(
            current.seq2Range.start + distance,
            next.seq2Range.endExclusive,
          ),
        );
        continue;
      }
      current = current.delta(shift);
    }
    right.add(current);
  }
  right.add(left.last);
  return right;
}

SequenceDiff _shift(
  SequenceDiff diff,
  DiffSequence first,
  DiffSequence second,
  OffsetRange valid1,
  OffsetRange valid2,
) {
  var before = 1;
  while (diff.seq1Range.start - before >= valid1.start &&
      diff.seq2Range.start - before >= valid2.start &&
      second.isStronglyEqual(
        diff.seq2Range.start - before,
        diff.seq2Range.endExclusive - before,
      ) &&
      before < 100) {
    before++;
  }
  before--;
  var after = 0;
  while (diff.seq1Range.start + after < valid1.endExclusive &&
      diff.seq2Range.endExclusive + after < valid2.endExclusive &&
      second.isStronglyEqual(
        diff.seq2Range.start + after,
        diff.seq2Range.endExclusive + after,
      ) &&
      after < 100) {
    after++;
  }
  var best = 0;
  var bestScore = -1;
  for (var delta = -before; delta <= after; delta++) {
    final score =
        first.getBoundaryScore(diff.seq1Range.start + delta) +
        second.getBoundaryScore(diff.seq2Range.start + delta) +
        second.getBoundaryScore(diff.seq2Range.endExclusive + delta);
    if (score > bestScore) {
      bestScore = score;
      best = delta;
    }
  }
  return diff.delta(best);
}

List<SequenceDiff> removeShortMatches(List<SequenceDiff> diffs) {
  final result = <SequenceDiff>[];
  for (final diff in diffs) {
    if (result.isNotEmpty &&
        (diff.seq1Range.start - result.last.seq1Range.endExclusive <= 2 ||
            diff.seq2Range.start - result.last.seq2Range.endExclusive <= 2)) {
      result[result.length - 1] = result.last.join(diff);
    } else {
      result.add(diff);
    }
  }
  return result;
}

List<SequenceDiff> removeVeryShortMatchingLines(
  LineSequence sequence,
  List<SequenceDiff> diffs,
) {
  for (var round = 0; round < 11 && diffs.length > 1; round++) {
    var changed = false;
    final result = <SequenceDiff>[diffs.first];
    for (final current in diffs.skip(1)) {
      final previous = result.last;
      final text = sequence.getText(
        OffsetRange(previous.seq1Range.endExclusive, current.seq1Range.start),
      );
      if (text.replaceAll(RegExp(r'\s'), '').length <= 4 &&
          (previous.seq1Range.length + previous.seq2Range.length > 5 ||
              current.seq1Range.length + current.seq2Range.length > 5)) {
        result[result.length - 1] = previous.join(current);
        changed = true;
      } else {
        result.add(current);
      }
    }
    diffs = result;
    if (!changed) break;
  }
  return diffs;
}

/// Match upstream's heuristic of not splitting partial words into tiny changes.
List<SequenceDiff> extendDiffsToEntireWordIfAppropriate(
  LinesSliceCharSequence first,
  LinesSliceCharSequence second,
  List<SequenceDiff> diffs, {
  bool subword = false,
}) {
  final equalMappings = SequenceDiff.invert(diffs, first.length);
  final additional = <SequenceDiff>[];
  var last1 = 0;
  var last2 = 0;
  void scan(int offset1, int offset2, SequenceDiff equal) {
    if (offset1 < last1 || offset2 < last2) return;
    final word1 = first.findWordContaining(offset1, subword: subword);
    final word2 = second.findWordContaining(offset2, subword: subword);
    if (word1 == null || word2 == null) return;
    var word = SequenceDiff(word1, word2);
    final intersect = word.intersect(equal);
    if (intersect == null) return;
    var equalCount = intersect.seq1Range.length + intersect.seq2Range.length;
    while (equalMappings.isNotEmpty) {
      final next = equalMappings.first;
      if (!(next.seq1Range.start < word.seq1Range.endExclusive &&
              word.seq1Range.start < next.seq1Range.endExclusive) &&
          !(next.seq2Range.start < word.seq2Range.endExclusive &&
              word.seq2Range.start < next.seq2Range.endExclusive)) {
        break;
      }
      final nextWord1 = first.findWordContaining(
        next.seq1Range.start,
        subword: subword,
      );
      final nextWord2 = second.findWordContaining(
        next.seq2Range.start,
        subword: subword,
      );
      if (nextWord1 == null || nextWord2 == null) break;
      final nextWord = SequenceDiff(nextWord1, nextWord2);
      final nextEqual = nextWord.intersect(next);
      if (nextEqual == null) break;
      equalCount += nextEqual.seq1Range.length + nextEqual.seq2Range.length;
      word = word.join(nextWord);
      if (word.seq1Range.endExclusive >= next.seq1Range.endExclusive) {
        equalMappings.removeAt(0);
      } else {
        break;
      }
    }
    if (equalCount <
        (word.seq1Range.length + word.seq2Range.length) *
            (subword ? 1 : 2 / 3)) {
      additional.add(word);
    }
    last1 = word.seq1Range.endExclusive;
    last2 = word.seq2Range.endExclusive;
  }

  while (equalMappings.isNotEmpty) {
    final equal = equalMappings.removeAt(0);
    if (equal.seq1Range.isEmpty) continue;
    scan(equal.seq1Range.start, equal.seq2Range.start, equal);
    scan(
      equal.seq1Range.endExclusive - 1,
      equal.seq2Range.endExclusive - 1,
      equal,
    );
  }
  final sorted = [...diffs, ...additional]
    ..sort((a, b) => a.seq1Range.start.compareTo(b.seq1Range.start));
  final result = <SequenceDiff>[];
  for (final diff in sorted) {
    if (result.isNotEmpty &&
        result.last.seq1Range.endExclusive >= diff.seq1Range.start) {
      result[result.length - 1] = result.last.join(diff);
    } else {
      result.add(diff);
    }
  }
  return result;
}

List<SequenceDiff> removeVeryShortMatchingText(
  LinesSliceCharSequence first,
  LinesSliceCharSequence second,
  List<SequenceDiff> diffs,
) {
  for (var round = 0; round < 11 && diffs.length > 1; round++) {
    var changed = false;
    final result = <SequenceDiff>[diffs.first];
    for (final current in diffs.skip(1)) {
      final previous = result.last;
      final unchanged = OffsetRange(
        previous.seq1Range.endExclusive,
        current.seq1Range.start,
      );
      if (first.countLinesIn(unchanged) <= 5 && unchanged.length <= 500) {
        final text = first.getText(unchanged).trim();
        if (text.length <= 20 && !text.contains(RegExp(r'\r|\n'))) {
          const maxScore = 130.0;
          double score(SequenceDiff diff) {
            double cap(int lines, int size) =>
                math.min(lines * 40 + size, maxScore).toDouble();
            final a = cap(
              first.countLinesIn(diff.seq1Range),
              diff.seq1Range.length,
            );
            final b = cap(
              second.countLinesIn(diff.seq2Range),
              diff.seq2Range.length,
            );
            return math
                .pow(math.pow(a, 1.5) + math.pow(b, 1.5), 1.5)
                .toDouble();
          }

          if (score(previous) + score(current) >
              math.pow(math.pow(maxScore, 1.5), 1.5) * 1.3) {
            result[result.length - 1] = previous.join(current);
            changed = true;
            continue;
          }
        }
      }
      result.add(current);
    }
    diffs = result;
    if (!changed) break;
  }
  // The remaining upstream suffix/prefix expansion heuristic is not ported.
  return diffs;
}
