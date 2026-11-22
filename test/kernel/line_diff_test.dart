import 'package:baocode/chat/chat_models.dart' show DiffLineType;
import 'package:baocode/kernel/line_diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int count(String before, String after, DiffLineType type) =>
      lineDiff(before, after).where((line) => line.type == type).length;

  test('a line changed in a long file is one line, not the file', () {
    final before = [for (var i = 0; i < 3000; i++) 'line $i'].join('\n');
    final after = before.replaceFirst('line 1500\n', 'line 1500!\n');
    final lines = lineDiff(before, after);
    expect(count(before, after, DiffLineType.added), 1);
    expect(count(before, after, DiffLineType.removed), 1);
    final added = lines.singleWhere((l) => l.type == DiffLineType.added);
    expect((added.lineNumber, added.text), (1501, 'line 1500!'));
    expect(lines.last.lineNumber, 3000);
  });

  test('lines put in and taken out, numbered as in their text', () {
    final lines = lineDiff('a\nb\nc\nd', 'a\nx\nc\nd\ne');
    expect(
      [for (final l in lines) (l.type, l.lineNumber, l.text)],
      [
        (DiffLineType.context, 1, 'a'),
        (DiffLineType.removed, 2, 'b'),
        (DiffLineType.added, 2, 'x'),
        (DiffLineType.context, 3, 'c'),
        (DiffLineType.context, 4, 'd'),
        (DiffLineType.added, 5, 'e'),
      ],
    );
  });

  test('a new file is all added', () {
    expect(count('', 'a\nb', DiffLineType.added), 2);
    expect(count('', 'a\nb', DiffLineType.removed), 0);
  });
}
