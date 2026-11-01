import 'dart:convert';
import 'dart:math';

import 'package:bao_remote/src/review/line_diff.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _bytes(String text) => utf8.encode(text);

String? _merged(String mine, String base, String theirs) =>
    switch (merge3(_bytes(mine), _bytes(base), _bytes(theirs))) {
      final merged? => utf8.decode(merged),
      null => null,
    };

/// [a] with [hunks] applied: [b], if they are right.
List<String> _apply(List<String> a, List<String> b, List<LineHunk> hunks) {
  final out = <String>[];
  var at = 0;
  for (final hunk in hunks) {
    out
      ..addAll(a.sublist(at, hunk.aStart))
      ..addAll(b.sublist(hunk.bStart, hunk.bEnd));
    at = hunk.aEnd;
  }
  return out..addAll(a.sublist(at));
}

void main() {
  test('counts the lines added and removed', () {
    expect(lineCounts(_bytes('1\n2\n3\n'), _bytes('1\ntwo\n3\n4\n')), (
      added: 2,
      removed: 1,
    ));
    expect(lineCounts(null, _bytes('a\nb')), (added: 2, removed: 0));
    expect(lineCounts(_bytes('a\n'), null), (added: 0, removed: 1));
    expect(lineCounts(_bytes('same\n'), _bytes('same\n')), (
      added: 0,
      removed: 0,
    ));
    // A line break added to the last line changes it.
    expect(lineCounts(_bytes('a'), _bytes('a\n')), (added: 1, removed: 1));
    expect(lineCounts([0, 1, 2], _bytes('a\n')), isNull);
  });

  test('its stretches turn one text into the other', () {
    final random = Random(7);
    List<String> text() => [
      for (var i = random.nextInt(40); i > 0; i--) '${random.nextInt(6)}\n',
    ];
    for (var round = 0; round < 500; round++) {
      final a = text();
      final b = text();
      final hunks = diffLines(a, b);
      expect(_apply(a, b, hunks), b, reason: '$a -> $b: $hunks');
      for (final hunk in hunks) {
        expect(hunk.aEnd > hunk.aStart || hunk.bEnd > hunk.bStart, isTrue);
      }
    }
  });

  test('past its limit, what lies between is one stretch', () {
    final a = [for (var i = 0; i < 50; i++) 'a$i\n'];
    final b = [for (var i = 0; i < 50; i++) 'b$i\n'];
    final hunks = diffLines(
      ['x\n', ...a, 'y\n'],
      ['x\n', ...b, 'y\n'],
      maxEdits: 10,
    );
    expect(hunks.single.toString(), 'LineHunk(1-51, 1-51)');
  });

  test('merges changes to different lines, as Git does', () {
    const base = '1\n2\n3\n4\n5\n6\n';
    expect(
      _merged('one\n2\n3\n4\n5\n6\n', base, '1\n2\n3\n4\n5\nsix\n'),
      'one\n2\n3\n4\n5\nsix\n',
    );
    // The same change on both sides is taken once.
    expect(
      _merged('1\n2\nthree\n4\n5\n6\n', base, '1\n2\nthree\n4\n5\n6\n'),
      '1\n2\nthree\n4\n5\n6\n',
    );
    // Lines next to each other.
    expect(
      _merged('1\nTWO\n3\n4\n5\n6\n', base, '1\n2\nTHREE\n4\n5\n6\n'),
      '1\nTWO\nTHREE\n4\n5\n6\n',
    );
    // Lines put in and taken out.
    expect(
      _merged('0\n1\n2\n3\n4\n5\n6\n', base, '1\n2\n3\n4\n6\n'),
      '0\n1\n2\n3\n4\n6\n',
    );
    // An agent's change taken back out of what changed since.
    expect(
      _merged('one\n2\n3\n4\nfive\n6\n', '1\n2\n3\n4\nfive\n6\n', base),
      'one\n2\n3\n4\n5\n6\n',
    );
  });

  test('does not merge changes to the same lines, or binary files', () {
    const base = '1\n2\n3\n';
    expect(_merged('1\ntwo\n3\n', base, '1\nTWO\n3\n'), isNull);
    // Lines put in at the same place.
    expect(_merged('1\nx\n2\n3\n', base, '1\ny\n2\n3\n'), isNull);
    expect(_merged('1\nx\n2\n3\n', base, '1\nTWO\n3\n'), isNull);
    expect(merge3([0, 1], _bytes(base), _bytes(base)), isNull);
  });

  test('keeps bytes and line endings as they are', () {
    final base = [...latin1.encode('a\r\nb\r\n'), 0xff, 0x0a];
    final mine = [...latin1.encode('A\r\nb\r\n'), 0xff, 0x0a];
    expect(merge3(mine, base, base), mine);
  });
}
