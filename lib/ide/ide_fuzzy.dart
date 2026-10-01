import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// A fuzzy match: higher [score] is better; [positions] are the matched
/// UTF-16 indices in the target, ascending.
class IdeFuzzyMatch {
  const IdeFuzzyMatch(this.score, this.positions);

  final int score;
  final List<int> positions;
}

bool _isSeparator(int unit) =>
    unit == 0x2f || // /
    unit == 0x5c || // \
    unit == 0x5f || // _
    unit == 0x2d || // -
    unit == 0x2e || // .
    unit == 0x20 || // space
    unit == 0x3a; // :

bool _isUpper(int unit) => unit >= 0x41 && unit <= 0x5a;
bool _isLower(int unit) => unit >= 0x61 && unit <= 0x7a;
int _lower(int unit) => _isUpper(unit) ? unit + 0x20 : unit;

Int32List _scores = Int32List(1024);
Int32List _back = Int32List(1024);

/// Scores [query] as an in-order (not necessarily contiguous) subsequence of
/// [target], ignoring case. Word starts, camelCase humps, consecutive runs and
/// exact case score higher, similar in spirit to VS Code's `fuzzyScore`.
/// Returns null when [query] is not a subsequence of [target].
IdeFuzzyMatch? ideFuzzyMatch(String query, String target) {
  final n = query.length;
  final m = target.length;
  if (n == 0) return const IdeFuzzyMatch(0, []);
  if (n > m) return null;

  // Cheap rejection before the quadratic pass.
  var qi = 0;
  for (var j = 0; j < m && qi < n; j++) {
    if (_lower(target.codeUnitAt(j)) == _lower(query.codeUnitAt(qi))) qi++;
  }
  if (qi < n) return null;

  const impossible = -0x3fffffff;
  // The tables are reused across calls: Quick Open scores thousands of
  // paths per key.
  if (_scores.length < n * m) {
    _scores = Int32List(n * m * 2);
    _back = Int32List(n * m * 2);
  }
  final scores = _scores..fillRange(0, n * m, impossible);
  final back = _back..fillRange(0, n * m, -1);

  int bonusAt(int j) {
    if (j == 0) return 8;
    final previous = target.codeUnitAt(j - 1);
    if (_isSeparator(previous)) return 7;
    final current = target.codeUnitAt(j);
    if (_isUpper(current) && _isLower(previous)) return 6;
    return 0;
  }

  for (var i = 0; i < n; i++) {
    final q = query.codeUnitAt(i);
    final ql = _lower(q);
    // Best score in row i-1 at columns < j-1, and where it was.
    var bestPrevious = impossible;
    var bestPreviousAt = -1;
    for (var j = i; j < m; j++) {
      if (i > 0 && j >= 2) {
        final candidate = scores[(i - 1) * m + j - 2];
        if (candidate > bestPrevious) {
          bestPrevious = candidate;
          bestPreviousAt = j - 2;
        }
      }
      final t = target.codeUnitAt(j);
      if (_lower(t) != ql) continue;
      final base = 1 + bonusAt(j) + (t == q ? 1 : 0);
      if (i == 0) {
        // Prefer earlier starts slightly.
        scores[j] = base - (j > 20 ? 5 : j ~/ 4);
        continue;
      }
      var best = impossible;
      var from = -1;
      if (j >= 1) {
        final consecutive = scores[(i - 1) * m + j - 1];
        if (consecutive > impossible) {
          best = consecutive + base + 6;
          from = j - 1;
        }
      }
      if (bestPrevious > impossible && bestPrevious + base - 1 > best) {
        best = bestPrevious + base - 1;
        from = bestPreviousAt;
      }
      if (from >= 0) {
        scores[i * m + j] = best;
        back[i * m + j] = from;
      }
    }
  }

  var bestScore = impossible;
  var end = -1;
  for (var j = n - 1; j < m; j++) {
    final score = scores[(n - 1) * m + j];
    if (score > bestScore) {
      bestScore = score;
      end = j;
    }
  }
  if (end < 0) return null;
  final positions = List<int>.filled(n, 0);
  var j = end;
  for (var i = n - 1; i >= 0; i--) {
    positions[i] = j;
    j = back[i * m + j];
  }
  return IdeFuzzyMatch(bestScore, positions);
}

/// [text] with the characters at [positions] drawn in [highlight].
class IdeHighlightedText extends StatelessWidget {
  const IdeHighlightedText(
    this.text, {
    super.key,
    this.positions = const [],
    required this.style,
    required this.highlight,
    this.offset = 0,
  });

  final String text;

  /// Indices into a longer string whose [offset] is this text's start.
  final List<int> positions;
  final int offset;
  final TextStyle style;
  final TextStyle highlight;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: style,
        children: ideHighlightSpans(text, positions, highlight, offset: offset),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Spans of [text] with the characters at [positions] (indices into a string
/// in which [text] starts at [offset]) drawn in [highlight].
List<TextSpan> ideHighlightSpans(
  String text,
  List<int> positions,
  TextStyle highlight, {
  int offset = 0,
  TextStyle? style,
}) {
  final marked = <int>{
    for (final position in positions)
      if (position >= offset && position < offset + text.length)
        position - offset,
  };
  if (marked.isEmpty) return [TextSpan(text: text, style: style)];
  final spans = <TextSpan>[];
  var start = 0;
  while (start < text.length) {
    final on = marked.contains(start);
    var end = start + 1;
    while (end < text.length && marked.contains(end) == on) {
      end++;
    }
    spans.add(
      TextSpan(
        text: text.substring(start, end),
        style: on ? (style?.merge(highlight) ?? highlight) : style,
      ),
    );
    start = end;
  }
  return spans;
}
