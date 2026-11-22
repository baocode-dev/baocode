import 'dart:math' as math;

import '../chat/chat_models.dart' show DiffLine, DiffLineType;

/// [before] to [after], line by line: kept lines as context, numbered as
/// in the text they are from. Past a size, all of one replaced by the
/// other.
List<DiffLine> lineDiff(String before, String after) {
  List<String> split(String text) => text.isEmpty ? [] : text.split('\n');
  final a = split(before);
  final b = split(after);
  // The longest common subsequence, from the end.
  final common = a.length * b.length <= 250000
      ? List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0))
      : null;
  if (common != null) {
    for (var i = a.length - 1; i >= 0; i--) {
      for (var j = b.length - 1; j >= 0; j--) {
        common[i][j] = a[i] == b[j]
            ? common[i + 1][j + 1] + 1
            : math.max(common[i + 1][j], common[i][j + 1]);
      }
    }
  }
  final lines = <DiffLine>[];
  var i = 0;
  var j = 0;
  while (i < a.length || j < b.length) {
    if (common != null && i < a.length && j < b.length && a[i] == b[j]) {
      lines.add(DiffLine(DiffLineType.context, j + 1, b[j]));
      i++;
      j++;
    } else if (i < a.length &&
        (j == b.length ||
            common == null ||
            common[i + 1][j] >= common[i][j + 1])) {
      lines.add(DiffLine(DiffLineType.removed, i + 1, a[i]));
      i++;
    } else {
      lines.add(DiffLine(DiffLineType.added, j + 1, b[j]));
      j++;
    }
  }
  return lines;
}
