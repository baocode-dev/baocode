// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/monaco/LICENSE.txt.
// Ported from defaultLinesDiffComputer/algorithms/{diffAlgorithm,
// dynamicProgrammingDiffing,myersDiffAlgorithm}.ts (pinned VS Code).

import 'dart:math' as math;

class OffsetRange {
  OffsetRange(this.start, this.endExclusive) {
    if (start > endExclusive) {
      throw ArgumentError('Invalid offset range: $this');
    }
  }
  final int start;
  final int endExclusive;
  int get length => endExclusive - start;
  bool get isEmpty => start == endExclusive;
  OffsetRange delta(int amount) =>
      OffsetRange(start + amount, endExclusive + amount);
  OffsetRange deltaStart(int amount) =>
      OffsetRange(start + amount, endExclusive);
  OffsetRange deltaEnd(int amount) => OffsetRange(start, endExclusive + amount);
  OffsetRange join(OffsetRange other) => OffsetRange(
    math.min(start, other.start),
    math.max(endExclusive, other.endExclusive),
  );
  OffsetRange? intersect(OffsetRange other) {
    final a = math.max(start, other.start);
    final b = math.min(endExclusive, other.endExclusive);
    return a <= b ? OffsetRange(a, b) : null;
  }

  bool intersectsOrTouches(OffsetRange other) =>
      start <= other.endExclusive && other.start <= endExclusive;
  @override
  String toString() => '[$start,$endExclusive)';
}

class SequenceDiff {
  const SequenceDiff(this.seq1Range, this.seq2Range);
  final OffsetRange seq1Range;
  final OffsetRange seq2Range;
  SequenceDiff swap() => SequenceDiff(seq2Range, seq1Range);
  SequenceDiff delta(int amount) =>
      SequenceDiff(seq1Range.delta(amount), seq2Range.delta(amount));
  SequenceDiff join(SequenceDiff other) => SequenceDiff(
    seq1Range.join(other.seq1Range),
    seq2Range.join(other.seq2Range),
  );
  SequenceDiff? intersect(SequenceDiff other) {
    final first = seq1Range.intersect(other.seq1Range);
    final second = seq2Range.intersect(other.seq2Range);
    return first == null || second == null ? null : SequenceDiff(first, second);
  }

  static List<SequenceDiff> invert(
    List<SequenceDiff> changes,
    int firstLength,
  ) {
    final result = <SequenceDiff>[];
    var start1 = 0;
    var start2 = 0;
    for (final change in changes) {
      result.add(
        SequenceDiff(
          OffsetRange(start1, change.seq1Range.start),
          OffsetRange(start2, change.seq2Range.start),
        ),
      );
      start1 = change.seq1Range.endExclusive;
      start2 = change.seq2Range.endExclusive;
    }
    result.add(
      SequenceDiff(
        OffsetRange(start1, firstLength),
        OffsetRange(start2, firstLength + start2 - start1),
      ),
    );
    return result;
  }
}

abstract class DiffSequence {
  int get length;
  int getElement(int offset);
  bool isStronglyEqual(int offset1, int offset2);
  int getBoundaryScore(int offset);
}

class DiffAlgorithmResult {
  const DiffAlgorithmResult(this.diffs, this.hitTimeout);
  final List<SequenceDiff> diffs;
  final bool hitTimeout;
  static DiffAlgorithmResult trivial(
    DiffSequence a,
    DiffSequence b, {
    bool timedOut = false,
  }) => DiffAlgorithmResult([
    SequenceDiff(OffsetRange(0, a.length), OffsetRange(0, b.length)),
  ], timedOut);
}

/// A single deadline shared by the line and character diff passes.
class DiffTimeout {
  DiffTimeout(int maxComputationTimeMs)
    : _deadline = maxComputationTimeMs == 0
          ? null
          : DateTime.now().millisecondsSinceEpoch + maxComputationTimeMs {
    if (maxComputationTimeMs < 0) {
      throw ArgumentError.value(maxComputationTimeMs);
    }
  }
  final int? _deadline;
  bool get isValid =>
      _deadline == null || DateTime.now().millisecondsSinceEpoch < _deadline;
}

/// Score-weighted LCS, including upstream's preference for consecutive diagonals.
DiffAlgorithmResult dynamicProgrammingDiff(
  DiffSequence first,
  DiffSequence second,
  DiffTimeout timeout, {
  double Function(int, int)? equalityScore,
}) {
  if (first.length == 0 || second.length == 0) {
    return DiffAlgorithmResult.trivial(first, second);
  }
  final score = List.generate(
    first.length,
    (_) => List<double>.filled(second.length, 0),
  );
  final direction = List.generate(
    first.length,
    (_) => List<int>.filled(second.length, 0),
  );
  final lengths = List.generate(
    first.length,
    (_) => List<int>.filled(second.length, 0),
  );
  for (var i = 0; i < first.length; i++) {
    for (var j = 0; j < second.length; j++) {
      if (!timeout.isValid) {
        return DiffAlgorithmResult.trivial(first, second, timedOut: true);
      }
      final horizontal = i == 0 ? 0.0 : score[i - 1][j];
      final vertical = j == 0 ? 0.0 : score[i][j - 1];
      var diagonal = -1.0;
      if (first.getElement(i) == second.getElement(j)) {
        diagonal = i == 0 || j == 0 ? 0 : score[i - 1][j - 1];
        if (i > 0 && j > 0 && direction[i - 1][j - 1] == 3) {
          diagonal += lengths[i - 1][j - 1];
        }
        diagonal += equalityScore?.call(i, j) ?? 1;
      }
      final value = math.max(math.max(horizontal, vertical), diagonal);
      if (value == diagonal) {
        lengths[i][j] = (i > 0 && j > 0 ? lengths[i - 1][j - 1] : 0) + 1;
        direction[i][j] = 3;
      } else if (value == horizontal) {
        direction[i][j] = 1;
      } else {
        direction[i][j] = 2;
      }
      score[i][j] = value;
    }
  }
  final result = <SequenceDiff>[];
  var last1 = first.length;
  var last2 = second.length;
  void report(int i, int j) {
    if (i + 1 != last1 || j + 1 != last2) {
      result.add(
        SequenceDiff(OffsetRange(i + 1, last1), OffsetRange(j + 1, last2)),
      );
    }
    last1 = i;
    last2 = j;
  }

  var i = first.length - 1;
  var j = second.length - 1;
  while (i >= 0 && j >= 0) {
    switch (direction[i][j]) {
      case 3:
        report(i, j);
        i--;
        j--;
      case 1:
        i--;
      default:
        j--;
    }
  }
  report(-1, -1);
  return DiffAlgorithmResult(result.reversed.toList(), false);
}

class _Snake {
  const _Snake(this.previous, this.x, this.y, this.length);
  final _Snake? previous;
  final int x;
  final int y;
  final int length;
}

/// Myers O(ND) algorithm, with upstream's diagonal bounds and timeout fallback.
DiffAlgorithmResult myersDiff(
  DiffSequence first,
  DiffSequence second,
  DiffTimeout timeout,
) {
  if (first.length == 0 || second.length == 0) {
    return DiffAlgorithmResult.trivial(first, second);
  }
  int snake(int x, int y) {
    while (x < first.length &&
        y < second.length &&
        first.getElement(x) == second.getElement(y)) {
      x++;
      y++;
    }
    return x;
  }

  final furthest = <int, int>{0: snake(0, 0)};
  final paths = <int, _Snake?>{
    0: furthest[0] == 0 ? null : _Snake(null, 0, 0, furthest[0]!),
  };
  var d = 0;
  var finalK = 0;
  var finished = false;
  while (!finished) {
    d++;
    if (!timeout.isValid) {
      return DiffAlgorithmResult.trivial(first, second, timedOut: true);
    }
    final lower = -math.min(d, second.length + d % 2);
    final upper = math.min(d, first.length + d % 2);
    for (var k = lower; k <= upper; k += 2) {
      final fromTop = k == upper ? -1 : (furthest[k + 1] ?? 0);
      final fromLeft = k == lower ? -1 : (furthest[k - 1] ?? 0) + 1;
      final x = math.min(math.max(fromTop, fromLeft), first.length);
      final y = x - k;
      if (x < 0 || y < 0 || y > second.length) continue;
      final endX = snake(x, y);
      furthest[k] = endX;
      final previous = x == fromTop ? paths[k + 1] : paths[k - 1];
      paths[k] = endX != x ? _Snake(previous, x, y, endX - x) : previous;
      if (endX == first.length && endX - k == second.length) {
        finalK = k;
        finished = true;
        break;
      }
    }
  }
  final result = <SequenceDiff>[];
  var lastX = first.length;
  var lastY = second.length;
  var path = paths[finalK];
  while (true) {
    final endX = path == null ? 0 : path.x + path.length;
    final endY = path == null ? 0 : path.y + path.length;
    if (endX != lastX || endY != lastY) {
      result.add(
        SequenceDiff(OffsetRange(endX, lastX), OffsetRange(endY, lastY)),
      );
    }
    if (path == null) break;
    lastX = path.x;
    lastY = path.y;
    path = path.previous;
  }
  return DiffAlgorithmResult(result.reversed.toList(), false);
}
