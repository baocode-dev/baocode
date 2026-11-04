import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// One stretch where two texts differ: lines [aStart, aEnd) of the first
/// in place of lines [bStart, bEnd) of the second.
class LineHunk {
  const LineHunk(this.aStart, this.aEnd, this.bStart, this.bEnd);

  final int aStart;
  final int aEnd;
  final int bStart;
  final int bEnd;

  @override
  String toString() => 'LineHunk($aStart-$aEnd, $bStart-$bEnd)';
}

/// Whether [bytes] are not text: a NUL in the first 8000, as Git tells.
bool isBinary(List<int> bytes) {
  final end = math.min(bytes.length, 8000);
  for (var i = 0; i < end; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}

/// [bytes] in lines, each with its line break (the last may have none):
/// byte for byte, whatever the encoding (a byte a character).
List<String> linesOf(List<int> bytes) {
  final text = latin1.decode(bytes);
  final lines = <String>[];
  var start = 0;
  while (start < text.length) {
    final end = text.indexOf('\n', start);
    if (end < 0) {
      lines.add(text.substring(start));
      break;
    }
    lines.add(text.substring(start, end + 1));
    start = end + 1;
  }
  return lines;
}

/// Where [a] and [b] differ, in order: Myers' diff, past the lines both
/// begin and end with. Past [maxEdits] lines added and removed, all of
/// what lies between those is one stretch.
List<LineHunk> diffLines(
  List<String> a,
  List<String> b, {
  int maxEdits = 2000,
}) {
  var start = 0;
  while (start < a.length && start < b.length && a[start] == b[start]) {
    start++;
  }
  var aEnd = a.length;
  var bEnd = b.length;
  while (aEnd > start && bEnd > start && a[aEnd - 1] == b[bEnd - 1]) {
    aEnd--;
    bEnd--;
  }
  if (start == aEnd && start == bEnd) return const [];
  if (start == aEnd || start == bEnd) {
    return [LineHunk(start, aEnd, start, bEnd)];
  }
  // Lines as numbers: compared a great many times.
  final ids = <String, int>{};
  final xs = Int32List(aEnd - start);
  final ys = Int32List(bEnd - start);
  for (var i = 0; i < xs.length; i++) {
    xs[i] = ids.putIfAbsent(a[start + i], () => ids.length);
  }
  for (var i = 0; i < ys.length; i++) {
    ys[i] = ids.putIfAbsent(b[start + i], () => ids.length);
  }
  final hunks = _myers(xs, ys, maxEdits);
  if (hunks == null) return [LineHunk(start, aEnd, start, bEnd)];
  return [
    for (final hunk in hunks)
      LineHunk(
        hunk.aStart + start,
        hunk.aEnd + start,
        hunk.bStart + start,
        hunk.bEnd + start,
      ),
  ];
}

/// The stretches where [a] and [b] differ; null past [maxEdits].
List<LineHunk>? _myers(Int32List a, Int32List b, int maxEdits) {
  final n = a.length;
  final m = b.length;
  final limit = math.min(maxEdits, n + m);
  final offset = limit + 1;
  final v = Int32List(2 * limit + 3);
  // What v was after each round, for k from -d to d.
  final trace = <Int32List>[];
  int? found;
  for (var d = 0; d <= limit && found == null; d++) {
    for (var k = -d; k <= d; k += 2) {
      var x = k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])
          ? v[offset + k + 1]
          : v[offset + k - 1] + 1;
      var y = x - k;
      while (x < n && y < m && a[x] == b[y]) {
        x++;
        y++;
      }
      v[offset + k] = x;
      if (x >= n && y >= m) {
        found = d;
        break;
      }
    }
    if (found == null) trace.add(v.sublist(offset - d, offset + d + 1));
  }
  if (found == null) return null;
  // The lines both have (of a, of b), back from the end.
  final matchedA = <int>[];
  final matchedB = <int>[];
  var x = n;
  var y = m;
  void snake(int toX, int toY) {
    while (x > toX && y > toY) {
      x--;
      y--;
      matchedA.add(x);
      matchedB.add(y);
    }
  }

  for (var d = found; d > 0; d--) {
    final last = trace[d - 1];
    int at(int k) => last[k + d - 1];
    final k = x - y;
    final down = k == -d || (k != d && at(k - 1) < at(k + 1));
    final previousK = down ? k + 1 : k - 1;
    final previousX = at(previousK);
    // Where the edit of this round left it, before its snake.
    final editX = down ? previousX : previousX + 1;
    snake(editX, editX - k);
    x = previousX;
    y = previousX - previousK;
  }
  snake(0, 0);
  final hunks = <LineHunk>[];
  var i = 0;
  var j = 0;
  for (var at = matchedA.length - 1; at >= 0; at--) {
    final nextA = matchedA[at];
    final nextB = matchedB[at];
    if (nextA > i || nextB > j) hunks.add(LineHunk(i, nextA, j, nextB));
    i = nextA + 1;
    j = nextB + 1;
  }
  if (i < n || j < m) hunks.add(LineHunk(i, n, j, m));
  return hunks;
}

/// Lines added and removed from [from] to [to] (null: no file); null
/// where either is binary.
({int added, int removed})? lineCounts(List<int>? from, List<int>? to) {
  if ((from != null && isBinary(from)) || (to != null && isBinary(to))) {
    return null;
  }
  var added = 0;
  var removed = 0;
  for (final hunk in diffLines(
    from == null ? const [] : linesOf(from),
    to == null ? const [] : linesOf(to),
  )) {
    removed += hunk.aEnd - hunk.aStart;
    added += hunk.bEnd - hunk.bStart;
  }
  return (added: added, removed: removed);
}

/// [mine] with the change from [base] to [theirs] carried over, as
/// `git merge-file` merges but for changes to lines next to each other,
/// which it carries over; null where the two change the same lines
/// differently, or put lines in at the same place, or where any is
/// binary.
Uint8List? merge3(List<int> mine, List<int> base, List<int> theirs) {
  if (isBinary(mine) || isBinary(base) || isBinary(theirs)) return null;
  final baseLines = linesOf(base);
  final sides = [linesOf(mine), linesOf(theirs)];
  final all =
      [
        for (final (side, lines) in sides.indexed)
          for (final hunk in diffLines(baseLines, lines))
            (side: side, hunk: hunk),
      ]..sort((x, y) {
        final byStart = x.hunk.aStart.compareTo(y.hunk.aStart);
        return byStart != 0 ? byStart : x.hunk.aEnd.compareTo(y.hunk.aEnd);
      });
  final out = <String>[];
  var position = 0;
  var i = 0;
  while (i < all.length) {
    final start = all[i].hunk.aStart;
    var end = all[i].hunk.aEnd;
    final group = [all[i++]];
    // Those that overlap it go with it; those that only touch it too,
    // where lines are put in there (the two sides' order is not known).
    bool joins(LineHunk next) =>
        next.aStart < end ||
        (next.aStart == end && (next.aStart == next.aEnd || start == end));
    while (i < all.length && joins(all[i].hunk)) {
      end = math.max(end, all[i].hunk.aEnd);
      group.add(all[i++]);
    }
    out.addAll(baseLines.sublist(position, start));
    List<String> region(int side) {
      final hunks = [
        for (final entry in group)
          if (entry.side == side) entry.hunk,
      ];
      if (hunks.isEmpty) return baseLines.sublist(start, end);
      final lines = sides[side];
      return lines.sublist(
        hunks.first.bStart - (hunks.first.aStart - start),
        hunks.last.bEnd + (end - hunks.last.aEnd),
      );
    }

    final changed = {for (final entry in group) entry.side};
    if (changed.length == 1) {
      out.addAll(region(changed.single));
    } else {
      final ours = region(0);
      final other = region(1);
      if (!_sameLines(ours, other)) return null;
      out.addAll(ours);
    }
    position = end;
  }
  out.addAll(baseLines.sublist(position));
  return latin1.encode(out.join());
}

bool _sameLines(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
