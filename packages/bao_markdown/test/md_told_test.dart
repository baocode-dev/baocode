import 'dart:math' as math;

import 'package:bao_markdown/bao_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

final _a = MdAtoms.encode('file {"path":"a"}');
final _b = MdAtoms.encode('pasted 1');

/// Where each offset of [told] is in the text.
List<int> _sources(MdTold told) => [
  for (var at = 0; at <= told.text.length; at++) told.toSource(at),
];

void main() {
  test('each atom is told as one character, the rest as it is', () {
    expect(MdTold.of('plain 文本 \u{1F600}').text, 'plain 文本 \u{1F600}');
    expect(MdTold.of('see $_a and$_b.').text, 'see ￼ and￼.');
    // Marks that make no atom are text.
    expect(MdTold.of('a ${MdAtoms.open} b').text, 'a ${MdAtoms.open} b');
  });

  test('an offset told goes back to the text, and the text\'s to it', () {
    final source = 'x$_a$_b 看\n$_a';
    for (final start in [0, 17]) {
      final told = MdTold.of(source, start: start);
      // Each told offset to the text and back.
      for (var at = 0; at <= told.text.length; at++) {
        expect(told.toTold(told.toSource(at)), at, reason: 'told $at');
      }
      // Each of the text's: back to itself between atoms; inside one, to
      // the atom's start.
      final atoms = MdAtoms.parse(source);
      for (var offset = 0; offset <= source.length; offset++) {
        final inside = atoms
            .where((run) => offset > run.start && offset < run.end)
            .firstOrNull;
        final back = told.toSource(told.toTold(start + offset)) - start;
        expect(back, inside?.start ?? offset, reason: 'text $offset');
      }
    }
  });

  test(
    'edited as an input method edits it, as told anew of the text edited',
    () {
      final random = math.Random(169);
      const pieces = ['a', 'bc', ' ', '中文', '\u{1F600}', '\n'];
      String piece() => random.nextInt(4) == 0
          ? (random.nextBool() ? _a : _b)
          : pieces[random.nextInt(pieces.length)];
      for (var round = 0; round < 500; round++) {
        final source = List.generate(random.nextInt(10), (_) => piece()).join();
        final start = random.nextInt(3) * 10;
        final told = MdTold.of(source, start: start);
        final from = random.nextInt(told.text.length + 1);
        final to = from + random.nextInt(told.text.length - from + 1);
        final inserted = ['', 'z', '你好', '\n'][random.nextInt(4)];
        final edited = told.edited(from, to, inserted);
        final anew = MdTold.of(
          source.replaceRange(
            told.toSource(from) - start,
            told.toSource(to) - start,
            inserted,
          ),
          start: start,
        );
        final what = '"$source" $from-$to "$inserted"';
        expect(edited.text, anew.text, reason: what);
        expect(_sources(edited), _sources(anew), reason: what);
      }
    },
  );

  test('an edit out of step with what was told leaves the text', () {
    final told = MdTold.of('ab$_a');
    expect(told.edited(5, 9, 'x').text, told.text);
  });
}
