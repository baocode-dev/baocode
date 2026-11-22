import 'dart:math' as math;

import '../chat/chat_models.dart' show DiffLine, DiffLineType;

/// [before] to [after], line by line: kept lines as context, numbered as
/// in the text they are from. The lines alike at either end are kept as
/// they are; past a size, all of what is between of one replaced by the
/// other.
List<DiffLine> lineDiff(String before, String after) {
  List<String> split(String text) => text.isEmpty ? [] : text.split('\n');
  final a = split(before);
  final b = split(after);
  // Alike at the start and at the end: an edit to a long file is often a
  // few lines in it.
  var start = 0;
  while (start < a.length && start < b.length && a[start] == b[start]) {
    start++;
  }
  var end = 0;
  while (end < a.length - start &&
      end < b.length - start &&
      a[a.length - 1 - end] == b[b.length - 1 - end]) {
    end++;
  }
  final aEnd = a.length - end;
  final bEnd = b.length - end;
  final n = aEnd - start;
  final m = bEnd - start;
  // The longest common subsequence of what is between, from the end.
  final common = n * m <= 250000
      ? List.generate(n + 1, (_) => List.filled(m + 1, 0))
      : null;
  if (common != null) {
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        common[i][j] = a[start + i] == b[start + j]
            ? common[i + 1][j + 1] + 1
            : math.max(common[i + 1][j], common[i][j + 1]);
      }
    }
  }
  final lines = <DiffLine>[
    for (var k = 0; k < start; k++) DiffLine(DiffLineType.context, k + 1, b[k]),
  ];
  var i = 0;
  var j = 0;
  while (i < n || j < m) {
    if (common != null && i < n && j < m && a[start + i] == b[start + j]) {
      lines.add(DiffLine(DiffLineType.context, start + j + 1, b[start + j]));
      i++;
      j++;
    } else if (i < n &&
        (j == m || common == null || common[i + 1][j] >= common[i][j + 1])) {
      lines.add(DiffLine(DiffLineType.removed, start + i + 1, a[start + i]));
      i++;
    } else {
      lines.add(DiffLine(DiffLineType.added, start + j + 1, b[start + j]));
      j++;
    }
  }
  for (var k = bEnd; k < b.length; k++) {
    lines.add(DiffLine(DiffLineType.context, k + 1, b[k]));
  }
  return lines;
}
