import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/base/common/strings_cursor.dart'
    as strings;
import 'package:baocode/ide/editor/monaco/vs/editor/common/core/cursor_columns.dart';

void main() {
  group('CursorColumns tab stops (upstream cases)', () {
    test('next and indent stops', () {
      for (final size in [1, 2, 4]) {
        for (var position = 0; position <= 8; position++) {
          final expected = (position ~/ size + 1) * size;
          expect(CursorColumns.nextRenderTabStop(position, size), expected);
          expect(CursorColumns.nextIndentTabStop(position, size), expected);
        }
      }
    });

    test('previous stops use the preceding boundary', () {
      for (final size in [1, 2, 4]) {
        for (var position = 0; position <= 9; position++) {
          final expected = position == 0 ? 0 : ((position - 1) ~/ size) * size;
          expect(CursorColumns.prevRenderTabStop(position, size), expected);
          expect(CursorColumns.prevIndentTabStop(position, size), expected);
        }
      }
    });

    test('visible columns account for tabs and clamp the prefix', () {
      const text = '\t  \tx\t';
      final visible = [0, 4, 5, 6, 8, 9, 12];
      for (var column = 1; column <= text.length + 1; column++) {
        expect(
          CursorColumns.visibleColumnFromColumn(text, column, 4),
          visible[column - 1],
        );
      }
      expect(CursorColumns.visibleColumnFromColumn(text, -1, 4), 0);
      expect(CursorColumns.visibleColumnFromColumn(text, 99, 4), 12);
      expect(CursorColumns.toStatusbarColumn(text, 7, 4), 13);
    });

    test('visible-to-column picks the nearer end and earlier on ties', () {
      const text = '\t\tvar';
      final expected = [1, 1, 1, 2, 2, 2, 2, 3, 3, 4, 5, 6, 6];
      for (var visible = 0; visible < expected.length; visible++) {
        expect(
          CursorColumns.columnFromVisibleColumn(text, visible, 4),
          expected[visible],
        );
      }
      expect(CursorColumns.columnFromVisibleColumn(text, -1, 4), 1);
      expect(CursorColumns.columnFromVisibleColumn('', 8, 4), 1);
    });
  });

  group('CursorColumns UTF-16 and graphemes', () {
    test('CJK full width and halfwidth Katakana', () {
      expect(CursorColumns.visibleColumnFromColumn('A何B', 4, 4), 4);
      expect(CursorColumns.columnFromVisibleColumn('A何B', 2, 4), 2);
      expect(CursorColumns.columnFromVisibleColumn('A何B', 3, 4), 3);
      expect(CursorColumns.toStatusbarColumn('A何B', 4, 4), 4);
      expect(strings.isFullWidthCharacter(0xFF21), isTrue);
      expect(strings.isFullWidthCharacter(0xFF76), isFalse);
      expect(CursorColumns.visibleColumnFromColumn('ｶ', 2, 4), 1);
    });

    test('emoji widths and imprecise classification match VS Code', () {
      expect(CursorColumns.visibleColumnFromColumn('🎈x', 3, 4), 2);
      expect(CursorColumns.visibleColumnFromColumn('🎈x', 4, 4), 3);
      expect(CursorColumns.columnFromVisibleColumn('🎈x', 1, 4), 1);
      expect(CursorColumns.columnFromVisibleColumn('🎈x', 2, 4), 3);
      expect(CursorColumns.toStatusbarColumn('🎈x', 3, 4), 2);
      // A prefix containing only the high surrogate has width one, but
      // the complete U+1F4DA emoji is counted as two visible cells.
      expect(strings.isEmojiImprecise(0x1F4DA), isTrue);
      expect(CursorColumns.visibleColumnFromColumn('📚az', 2, 4), 1);
      expect(CursorColumns.visibleColumnFromColumn('📚az', 3, 4), 2);
      expect(CursorColumns.visibleColumnFromColumn('📚az', 5, 4), 4);
    });

    test('half-surrogate prefix is not counted as a complete emoji', () {
      const text = '🎈a';
      expect(text.length, 3);
      expect(strings.getNextCodePoint(text, text.length, 0), 0x1F388);
      expect(strings.getNextCodePoint(text, 1, 0), text.codeUnitAt(0));
      expect(CursorColumns.visibleColumnFromColumn(text, 2, 4), 1);
      expect(CursorColumns.visibleColumnFromColumn(text, 3, 4), 2);
      expect(CursorColumns.toStatusbarColumn(text, 2, 4), 2);
      expect(CursorColumns.toStatusbarColumn(text, 3, 4), 2);
      expect(CursorColumns.columnFromVisibleColumn(text, 2, 4), 3);
    });

    test(
      'combining accents form one visible grapheme, not one status unit',
      () {
        const text = 'éx';
        expect(CursorColumns.visibleColumnFromColumn(text, 2, 4), 1);
        expect(CursorColumns.visibleColumnFromColumn(text, 3, 4), 1);
        expect(CursorColumns.visibleColumnFromColumn(text, 4, 4), 2);
        expect(CursorColumns.columnFromVisibleColumn(text, 1, 4), 3);
        expect(CursorColumns.toStatusbarColumn(text, 3, 4), 3);
        expect(CursorColumns.toStatusbarColumn(text, 4, 4), 4);
      },
    );

    test('ZWJ emoji and modifiers follow the leading code point', () {
      const text = '👩‍💻!';
      expect(
        CursorColumns.visibleColumnFromColumn(text, text.length + 1, 4),
        3,
      );
      expect(CursorColumns.columnFromVisibleColumn(text, 2, 4), text.length);
      expect(CursorColumns.toStatusbarColumn(text, text.length + 1, 4), 5);
      const modifier = '👍🏽';
      expect(CursorColumns.visibleColumnFromColumn(modifier, 5, 4), 2);
      expect(CursorColumns.toStatusbarColumn(modifier, 5, 4), 3);
    });

    test('upstream merges consecutive regional indicators without pairing', () {
      const flags = '🇺🇸🇨🇦';
      final graphemes = strings.GraphemeIterator(flags);
      expect(graphemes.nextGraphemeLength(), 8);
      expect(graphemes.eol(), isTrue);
      expect(CursorColumns.visibleColumnFromColumn(flags, 9, 4), 2);
      expect(CursorColumns.toStatusbarColumn(flags, 9, 4), 5);
    });

    test('iterators use UTF-16 offsets and upstream grapheme boundaries', () {
      final codePoints = strings.CodePointIterator('é🎈');
      expect(codePoints.nextCodePoint(), 'e'.codeUnitAt(0));
      expect(codePoints.offset, 1);
      expect(codePoints.nextCodePoint(), 0x301);
      expect(codePoints.nextCodePoint(), 0x1F388);
      expect(codePoints.offset, 4);
      expect(codePoints.eol(), isTrue);
      expect(codePoints.prevCodePoint(), 0x1F388);
      expect(codePoints.offset, 2);
      final graphemes = strings.GraphemeIterator('é🎈');
      expect(graphemes.nextGraphemeLength(), 2);
      expect(graphemes.offset, 2);
      expect(graphemes.nextGraphemeLength(), 2);
      expect(graphemes.eol(), isTrue);
      expect(graphemes.prevGraphemeLength(), 2);
      expect(graphemes.prevGraphemeLength(), 2);
    });
  });
}
