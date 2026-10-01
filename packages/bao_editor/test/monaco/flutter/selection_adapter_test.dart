import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/selection_adapter.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/selection.dart';

void main() {
  group('positionAtOffset', () {
    test('clamps offsets in empty and single-line text', () {
      expect(positionAtOffset('', -1).equals(const Position(1, 1)), isTrue);
      expect(positionAtOffset('', 10).equals(const Position(1, 1)), isTrue);
      expect(positionAtOffset('abc', -10).equals(const Position(1, 1)), isTrue);
      expect(positionAtOffset('abc', 0).equals(const Position(1, 1)), isTrue);
      expect(positionAtOffset('abc', 2).equals(const Position(1, 3)), isTrue);
      expect(positionAtOffset('abc', 99).equals(const Position(1, 4)), isTrue);
    });

    test('keeps CRLF together and counts lone CR and LF as newlines', () {
      const text = 'ab\r\nc\rd\n';
      final positions = <Position>[
        const Position(1, 1), // Before a.
        const Position(1, 2),
        const Position(1, 3), // Before CR.
        const Position(1, 3), // Between CR and LF.
        const Position(2, 1), // After CRLF.
        const Position(2, 2), // Before lone CR.
        const Position(3, 1), // After lone CR.
        const Position(3, 2), // Before lone LF.
        const Position(4, 1), // After trailing LF.
      ];
      for (var offset = 0; offset < positions.length; offset++) {
        expect(
          positionAtOffset(text, offset).equals(positions[offset]),
          isTrue,
          reason: 'Offset $offset',
        );
      }
      expect(positionAtOffset(text, 999).equals(const Position(4, 1)), isTrue);
      expect(
        positionAtOffset('\r\n\r\n', 3).equals(const Position(2, 1)),
        isTrue,
      );
      expect(
        positionAtOffset('\r\n\r\n', 4).equals(const Position(3, 1)),
        isTrue,
      );
      expect(positionAtOffset('\na', 1).equals(const Position(2, 1)), isTrue);
    });

    test('counts surrogate pairs as two UTF-16 columns', () {
      const text = 'a😀b';
      expect(text.length, 4);
      for (var offset = 0; offset <= text.length; offset++) {
        expect(
          positionAtOffset(text, offset).equals(Position(1, offset + 1)),
          isTrue,
          reason: 'Offset $offset, including inside the surrogate pair',
        );
      }
    });
  });

  group('editorSelectionOf', () {
    test('reuses matching snapshots and ignores stale snapshots', () {
      const value = TextEditingValue(
        text: 'a\nb',
        selection: TextSelection.collapsed(offset: 3),
      );
      for (final snapshot in [
        DocumentSnapshot(value.text),
        DocumentSnapshot('stale'),
      ]) {
        final result = editorSelectionOf(value, snapshot: snapshot);
        expect(result.caret.equals(const Position(2, 2)), isTrue);
        expect(result.range.isEmpty(), isTrue);
      }
    });

    test('uses the extent as caret and normalizes a forward range', () {
      final selection = editorSelectionOf(
        const TextEditingValue(
          text: 'ab\r\nc\rd\n',
          selection: TextSelection(baseOffset: 1, extentOffset: 7),
        ),
      );
      expect(selection.caret.equals(const Position(3, 2)), isTrue);
      expect(selection.range.equalsRange(Range(1, 2, 3, 2)), isTrue);
    });

    test('keeps a reversed selection caret at the extent', () {
      final selection = editorSelectionOf(
        const TextEditingValue(
          text: 'ab\r\nc\rd\n',
          selection: TextSelection(baseOffset: 7, extentOffset: 1),
        ),
      );
      expect(selection.caret.equals(const Position(1, 2)), isTrue);
      expect(selection.range.equalsRange(Range(1, 2, 3, 2)), isTrue);
      expect(selection.range.getDirection(), SelectionDirection.rtl);
    });

    test('collapses CRLF interior offsets to the preceding line end', () {
      final selection = editorSelectionOf(
        const TextEditingValue(
          text: 'a\r\nb',
          selection: TextSelection(baseOffset: 2, extentOffset: 3),
        ),
      );
      expect(selection.caret.equals(const Position(2, 1)), isTrue);
      expect(selection.range.equalsRange(Range(1, 2, 2, 1)), isTrue);
    });

    test('supports a collapsed caret within a surrogate pair', () {
      final selection = editorSelectionOf(
        const TextEditingValue(
          text: 'a😀b',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      expect(selection.caret.equals(const Position(1, 3)), isTrue);
      expect(selection.range.equalsRange(Range(1, 3, 1, 3)), isTrue);
    });

    test('falls back to (1,1) for invalid selections', () {
      for (final invalidSelection in [
        const TextSelection(baseOffset: -1, extentOffset: -1),
        const TextSelection(baseOffset: -1, extentOffset: 2),
      ]) {
        final selection = editorSelectionOf(
          TextEditingValue(text: 'abc', selection: invalidSelection),
        );
        expect(selection.caret.equals(const Position(1, 1)), isTrue);
        expect(selection.range.equalsRange(Range(1, 1, 1, 1)), isTrue);
      }
    });

    test('clamps out-of-bounds offsets before normalizing', () {
      final selection = editorSelectionOf(
        const TextEditingValue(
          text: 'a\n',
          selection: TextSelection(baseOffset: 99, extentOffset: 0),
        ),
      );
      expect(selection.caret.equals(const Position(1, 1)), isTrue);
      expect(selection.range.equalsRange(Range(1, 1, 2, 1)), isTrue);
    });
  });
}
