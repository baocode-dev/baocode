import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/edits/text_edit.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/position.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/range.dart';

Range _range(int sl, int sc, int el, int ec) => Range(sl, sc, el, ec);

void _expectRange(Range actual, Range expected) {
  expect(actual.equalsRange(expected), isTrue, reason: '$actual != $expected');
}

// Adapted from upstream textEdit.test.ts "inverse" seeded round-trip suite.
// Offsets are UTF-16 code units, as in upstream's PositionOffsetTransformer.
Position _positionAt(String source, int offset) {
  var line = 1;
  var column = 1;
  for (var i = 0; i < offset; i++) {
    if (source.codeUnitAt(i) == 10) {
      line++;
      column = 1;
    } else {
      column++;
    }
  }
  return Position(line, column);
}

void main() {
  group('TextEdit', () {
    test('upstream inverse round-trip across 20 seeded parallel edit sets', () {
      const alphabet = 'abcdefgh ABCDEFGH';
      const inserted = 'abc\n XY';
      for (var seed = 0; seed < 20; seed++) {
        final random = Random(seed);
        final source = List.generate(
          10,
          (_) => List.generate(
            random.nextInt(10),
            (_) => alphabet[random.nextInt(alphabet.length)],
          ).join(),
        ).join('\n');
        final count = random.nextInt(4) + 1;
        final offsets = List.generate(
          2 * count,
          (_) => random.nextInt(source.length + 1),
        )..sort();
        final edits = TextEdit([
          for (var i = 0; i < count; i++)
            TextReplacement(
              Range.fromPositions(
                _positionAt(source, offsets[2 * i]),
                _positionAt(source, offsets[2 * i + 1]),
              ),
              List.generate(
                random.nextInt(7),
                (_) => inserted[random.nextInt(inserted.length)],
              ).join(),
            ),
        ]).normalize();
        final edited = edits.applyToString(source);
        expect(
          edits.inverse(source).applyToString(edited),
          source,
          reason: 'seed $seed',
        );
      }
    });

    test(
      'factory edits apply at one-based positions, including CRLF and UTF-16',
      () {
        expect(
          TextEdit.insert(const Position(1, 2), '😀').applyToString('a\r\nb'),
          'a😀\r\nb',
        );
        expect(
          TextEdit.delete(_range(1, 2, 2, 1)).applyToString('a\r\nb'),
          'ab',
        );
        expect(
          TextEdit.replace(_range(1, 2, 1, 4), 'z').applyToString('a😀b'),
          'azb',
        );
        final edit = TextEdit.insert(const Position(1, 2), '\r\n🐱');
        _expectRange(edit.getNewRanges().single, _range(1, 2, 2, 3));
        final edited = edit.applyToString('a😀\r\nb');
        expect(edit.inverse('a😀\r\nb').applyToString(edited), 'a😀\r\nb');
      },
    );

    test(
      'maps start/end affinity and positions replaced within multiline edit',
      () {
        final edit = TextEdit.replace(_range(1, 2, 2, 3), 'X\nYZ');
        expect(
          Position.equalsPositions(
            edit.mapPosition(const Position(1, 2)) as Position,
            const Position(1, 2),
          ),
          isTrue,
        );
        _expectRange(
          edit.mapPosition(const Position(2, 1)) as Range,
          _range(1, 2, 2, 3),
        );
        expect(
          Position.equalsPositions(
            edit.mapPosition(const Position(2, 3)) as Position,
            const Position(2, 5),
          ),
          isTrue,
        );
        expect(
          Position.equalsPositions(
            edit.mapPosition(const Position(2, 4)) as Position,
            const Position(2, 6),
          ),
          isTrue,
        );
        // Upstream mapPosition adds the inserted last-line length when mapping
        // columns beyond a multiline replacement, even if the end column > 1.
        _expectRange(edit.mapRange(_range(2, 1, 2, 4)), _range(1, 2, 2, 6));
      },
    );

    test('maps later edits with their updated columns and undo maps back', () {
      final edit = TextEdit([
        TextReplacement(_range(1, 2, 1, 3), 'XYZ'),
        TextReplacement(_range(1, 5, 1, 6), 'Q'),
      ]);
      expect(edit.applyToString('abcdef'), 'aXYZcdQf');
      _expectRange(edit.getNewRanges()[0], _range(1, 2, 1, 5));
      _expectRange(edit.getNewRanges()[1], _range(1, 7, 1, 8));
      expect(
        Position.equalsPositions(
          edit.mapPosition(const Position(1, 6)) as Position,
          const Position(1, 8),
        ),
        isTrue,
      );
      _expectRange(
        edit.inverseMapPosition(const Position(1, 3), 'abcdef') as Range,
        _range(1, 2, 1, 3),
      );
      _expectRange(
        edit.inverseMapRange(_range(1, 3, 1, 4), 'abcdef'),
        _range(1, 2, 1, 3),
      );
    });

    test('normalizes touching edits, removes no-ops, rejects overlap', () {
      final edits = TextEdit([
        TextReplacement(_range(1, 1, 1, 1), ''),
        TextReplacement(_range(1, 2, 1, 3), 'X'),
        TextReplacement(_range(1, 3, 1, 4), 'Y'),
      ]);
      final normalized = edits.normalize();
      expect(normalized.replacements.length, 1);
      _expectRange(normalized.replacements.single.range, _range(1, 2, 1, 4));
      expect(normalized.replacements.single.text, 'XY');
      expect(normalized.applyToString('abcd'), edits.applyToString('abcd'));
      expect(
        () => TextEdit([
          TextReplacement(_range(1, 2, 1, 4), 'a'),
          TextReplacement(_range(1, 3, 1, 5), 'b'),
        ]),
        throwsArgumentError,
      );
    });

    test('sorts copies, joins replacements preserving the source gap', () {
      final first = TextReplacement(_range(1, 2, 1, 3), 'X');
      final second = TextReplacement(_range(2, 1, 2, 2), 'Y');
      final input = [second, first];
      final edit = TextEdit.fromParallelReplacementsUnsorted(input);
      expect(identical(input.first, second), isTrue);
      final joined = edit.toReplacement('abc\ndef');
      expect(joined.text, 'Xc\nY');
      expect(
        joined.toEdit().applyToString('abc\ndef'),
        edit.applyToString('abc\ndef'),
      );
      expect(edit.equals(TextEdit([first, second])), isTrue);
      expect(first.toSingleEditOperation().text, 'X');
      expect(first.extendToCoverRange(_range(1, 1, 1, 4), 'abc').text, 'aXc');
      expect(
        () => TextReplacement.joinReplacements([], 'abc'),
        throwsArgumentError,
      );
    });
  });
}
