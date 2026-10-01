import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';

/// Shrinks [edits] (disjoint, sorted, against [text]) to the changes they
/// actually make, so formatting keeps cursors and undo small: a line diff
/// (Myers) inside each edit, then common prefix/suffix trimming, in the
/// spirit of upstream `EditorWorker.computeMoreMinimalEdits`. Edits that
/// change nothing disappear.
List<EditorOffsetEdit> minimalOffsetEdits(
  String text,
  List<EditorOffsetEdit> edits,
) {
  final result = <EditorOffsetEdit>[];
  for (final edit in edits) {
    final old = text.substring(edit.start, edit.end);
    if (old == edit.text) continue;
    final a = _lines(old);
    final b = _lines(edit.text);
    final hunks = (a.length > 1 || b.length > 1) ? _diffLines(a, b) : null;
    if (hunks == null) {
      _addTrimmed(result, edit.start, old, edit.text);
      continue;
    }
    final starts = <int>[0];
    for (final line in a) {
      starts.add(starts.last + line.length);
    }
    for (final (aStart, aEnd, bStart, bEnd) in hunks) {
      if (aEnd - aStart == bEnd - bStart) {
        // Line for line (reindenting, spacing): one small edit per line.
        for (var i = 0; i < aEnd - aStart; i++) {
          _addTrimmed(
            result,
            edit.start + starts[aStart + i],
            a[aStart + i],
            b[bStart + i],
          );
        }
        continue;
      }
      _addTrimmed(
        result,
        edit.start + starts[aStart],
        old.substring(starts[aStart], starts[aEnd]),
        b.sublist(bStart, bEnd).join(),
      );
    }
  }
  return result;
}

void _addTrimmed(
  List<EditorOffsetEdit> out,
  int start,
  String old,
  String next,
) {
  var prefix = 0;
  final limit = math.min(old.length, next.length);
  while (prefix < limit && old.codeUnitAt(prefix) == next.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < limit - prefix &&
      old.codeUnitAt(old.length - 1 - suffix) ==
          next.codeUnitAt(next.length - 1 - suffix)) {
    suffix++;
  }
  // Do not split a CRLF or a surrogate pair.
  bool splits(String s, int i) {
    if (i <= 0 || i >= s.length) return false;
    final before = s.codeUnitAt(i - 1);
    final after = s.codeUnitAt(i);
    return (before == 0x0D && after == 0x0A) ||
        (before >= 0xD800 && before <= 0xDBFF);
  }

  while (prefix > 0 && (splits(old, prefix) || splits(next, prefix))) {
    prefix--;
  }
  while (suffix > 0 &&
      (splits(old, old.length - suffix) ||
          splits(next, next.length - suffix))) {
    suffix--;
  }
  if (prefix == old.length && prefix == next.length) return;
  out.add(
    EditorOffsetEdit(
      start + prefix,
      start + old.length - suffix,
      next.substring(prefix, next.length - suffix),
    ),
  );
}

/// Lines with their terminators, so joining them gives [text] back.
List<String> _lines(String text) {
  final lines = <String>[];
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit == 0x0A ||
        (unit == 0x0D &&
            (i + 1 >= text.length || text.codeUnitAt(i + 1) != 0x0A))) {
      lines.add(text.substring(start, i + 1));
      start = i + 1;
    }
  }
  if (start < text.length || lines.isEmpty) lines.add(text.substring(start));
  return lines;
}

/// Changed line hunks `(aStart, aEnd, bStart, bEnd)` between [a] and [b]
/// (Myers' greedy diff); null when they differ too much to bother.
List<(int, int, int, int)>? _diffLines(
  List<String> a,
  List<String> b, {
  int maxD = 400,
}) {
  // Common prefix and suffix first: formatting usually touches little.
  var head = 0;
  while (head < a.length && head < b.length && a[head] == b[head]) {
    head++;
  }
  var tail = 0;
  while (tail < a.length - head &&
      tail < b.length - head &&
      a[a.length - 1 - tail] == b[b.length - 1 - tail]) {
    tail++;
  }
  final n = a.length - head - tail;
  final m = b.length - head - tail;
  if (n == 0 && m == 0) return const [];
  if (n + m > 40000) return null;
  String av(int i) => a[head + i];
  String bv(int i) => b[head + i];
  final max = n + m;
  final offset = max + 1;
  final v = Int32List(2 * max + 3);
  final trace = <Int32List>[];
  int? found;
  for (var d = 0; d <= math.min(max, maxD) && found == null; d++) {
    for (var k = -d; k <= d; k += 2) {
      var x = (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]))
          ? v[offset + k + 1]
          : v[offset + k - 1] + 1;
      var y = x - k;
      while (x < n && y < m && av(x) == bv(y)) {
        x++;
        y++;
      }
      v[offset + k] = x;
      if (x >= n && y >= m) {
        found = d;
        break;
      }
    }
    trace.add(Int32List.fromList(v.sublist(offset - d, offset + d + 1)));
  }
  if (found == null) return null;
  final matches = <(int, int)>[];
  var x = n;
  var y = m;
  for (var d = found; d > 0; d--) {
    final previous = trace[d - 1];
    int at(int k) => previous[k + d - 1];
    final k = x - y;
    final prevK = (k == -d || (k != d && at(k - 1) < at(k + 1)))
        ? k + 1
        : k - 1;
    final prevX = at(prevK);
    final prevY = prevX - prevK;
    final midX = prevK == k + 1 ? prevX : prevX + 1;
    final midY = midX - k;
    while (x > midX && y > midY) {
      x--;
      y--;
      matches.add((x, y));
    }
    x = prevX;
    y = prevY;
  }
  while (x > 0 && y > 0) {
    x--;
    y--;
    matches.add((x, y));
  }
  final hunks = <(int, int, int, int)>[];
  var ai = 0;
  var bi = 0;
  for (final (mx, my) in matches.reversed) {
    if (mx > ai || my > bi) {
      hunks.add((head + ai, head + mx, head + bi, head + my));
    }
    ai = mx + 1;
    bi = my + 1;
  }
  if (ai < n || bi < m) hunks.add((head + ai, head + n, head + bi, head + m));
  return hunks;
}
