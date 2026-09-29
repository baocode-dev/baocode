import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/flutter/document_snapshot.dart';
import 'package:monad/ide/editor/monaco/flutter/selection_adapter.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/position.dart';

void main() {
  group('DocumentSnapshot', () {
    test('indexes mixed newlines, empty lines, and trailing lines', () {
      final snapshot = DocumentSnapshot('ab\r\nc\rd\n');
      expect(snapshot.text, 'ab\r\nc\rd\n');
      expect(snapshot.lineCount, 4);
      expect(snapshot.lineStarts, [0, 4, 6, 8]);
      expect(snapshot.contentEnds, [2, 5, 7, 8]);
      expect(snapshot.newlineLengths, [2, 1, 1, 0]);

      final empty = DocumentSnapshot('');
      expect(empty.lineCount, 1);
      expect(empty.lineStarts, [0]);
      expect(empty.contentEnds, [0]);
      expect(empty.newlineLengths, [0]);

      final adjacent = DocumentSnapshot('\r\n\n\r');
      expect(adjacent.lineStarts, [0, 2, 3, 4]);
      expect(adjacent.contentEnds, [0, 2, 3, 4]);
      expect(adjacent.newlineLengths, [2, 1, 1, 0]);
    });

    test('exposes immutable line geometry', () {
      final snapshot = DocumentSnapshot('a\r\nb');
      expect(() => snapshot.lineStarts[0] = 10, throwsUnsupportedError);
      expect(() => snapshot.contentEnds.add(10), throwsUnsupportedError);
      expect(() => snapshot.newlineLengths[0] = 0, throwsUnsupportedError);
      expect(snapshot.lineStarts, [0, 3]);
      expect(snapshot.contentEnds, [1, 4]);
      expect(snapshot.newlineLengths, [2, 0]);
    });

    test('agrees with selection adapter for every offset in varied text', () {
      final samples = <String>[
        '',
        'abc',
        '\r',
        '\n',
        '\r\n',
        '\r\n\r\n',
        'a\r\nb\rc\nd\n',
        '\r\n\n\r',
        'a😀b\r\n😀\rc\n',
      ];
      final random = Random(137);
      const pieces = ['a', '😀', '\r', '\n', '\r\n', ''];
      for (var sample = 0; sample < 80; sample++) {
        samples.add(
          List.generate(
            40,
            (_) => pieces[random.nextInt(pieces.length)],
          ).join(),
        );
      }

      for (final text in samples) {
        final snapshot = DocumentSnapshot(text);
        for (var offset = -3; offset <= text.length + 3; offset++) {
          final actual = snapshot.positionAtOffset(offset);
          expect(
            actual.equals(positionAtOffset(text, offset)),
            isTrue,
            reason: 'Text: $text, offset: $offset',
          );

          final clamped = offset < 0
              ? 0
              : (offset > text.length ? text.length : offset);
          final insideCrLf =
              clamped > 0 &&
              clamped < text.length &&
              text.codeUnitAt(clamped - 1) == 0x0D &&
              text.codeUnitAt(clamped) == 0x0A;
          expect(
            snapshot.offsetAtPosition(actual),
            insideCrLf ? clamped - 1 : clamped,
            reason: 'Roundtrip text: $text, offset: $offset',
          );
        }
      }
    });

    test('counts UTF-16 code units for positions and clamps coordinates', () {
      final snapshot = DocumentSnapshot('a😀\r\n\nZ\r');
      expect(snapshot.lineStarts, [0, 5, 6, 8]);
      expect(snapshot.contentEnds, [3, 5, 7, 8]);
      expect(snapshot.newlineLengths, [2, 1, 1, 0]);
      expect(snapshot.positionAtOffset(2).equals(const Position(1, 3)), isTrue);
      expect(snapshot.positionAtOffset(3).equals(const Position(1, 4)), isTrue);
      expect(snapshot.positionAtOffset(4).equals(const Position(1, 4)), isTrue);
      expect(snapshot.positionAtOffset(5).equals(const Position(2, 1)), isTrue);
      expect(snapshot.positionAtOffset(8).equals(const Position(4, 1)), isTrue);
      expect(snapshot.offsetAtPosition(const Position(1, 3)), 2);
      expect(snapshot.offsetAtPosition(const Position(1, 4)), 3);
      expect(snapshot.offsetAtPosition(const Position(1, 999)), 3);
      expect(snapshot.offsetAtPosition(const Position(2, 999)), 5);
      expect(snapshot.offsetAtPosition(const Position(3, 2)), 7);
      expect(snapshot.offsetAtPosition(const Position(4, 999)), 8);
      expect(snapshot.offsetAtPosition(const Position(-5, -5)), 0);
      expect(snapshot.offsetAtPosition(const Position(999, -5)), 8);
      expect(snapshot.offsetAtPosition(const Position(999, 999)), 8);
    });

    test('supports indexed lookups deep in a large document', () {
      final snapshot = DocumentSnapshot('${'ab\r\n' * 20000}z😀');
      expect(snapshot.lineCount, 20001);
      expect(snapshot.lineStarts.length, snapshot.lineCount);
      expect(snapshot.contentEnds.length, snapshot.lineCount);
      expect(snapshot.newlineLengths.length, snapshot.lineCount);
      for (final line in [0, 1, 9999, 19999]) {
        expect(snapshot.lineStarts[line], line * 4);
        expect(snapshot.contentEnds[line], line * 4 + 2);
        expect(snapshot.newlineLengths[line], 2);
        expect(
          snapshot.positionAtOffset(line * 4 + 3).equals(Position(line + 1, 3)),
          isTrue,
        );
      }
      expect(snapshot.lineStarts.last, 80000);
      expect(snapshot.contentEnds.last, 80003);
      expect(snapshot.newlineLengths.last, 0);
      expect(snapshot.offsetAtPosition(const Position(20001, 4)), 80003);
      expect(
        snapshot.positionAtOffset(80002).equals(const Position(20001, 3)),
        isTrue,
      );
    });
  });
}
