import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/flutter/editor_document_model.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/core/position.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/core/range.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/model/search/piece_tree_search.dart';

void main() {
  group('EditorDocumentModel', () {
    test(
      'retains exact mixed line endings through a multiline edit and undo',
      () {
        const original = 'one\r\ntwo\rthree\n';
        final model = EditorDocumentModel(original);
        expect(model.text, original);
        expect(model.snapshot.lineStarts, [0, 5, 9, 15]);
        expect(model.snapshot.newlineLengths, [2, 1, 1, 0]);
        expect(model.savedText, original);
        expect(model.isDirty, false);

        model.applyEdit(Range(2, 2, 3, 3), 'Z');
        expect(model.text, 'one\r\ntZree\n');
        expect(model.snapshot.lineCount, 3);
        expect(model.isDirty, true);
        expect(model.undo(), true);
        expect(model.text, original);
        expect(model.isDirty, false);
        expect(model.redo(), true);
        expect(model.text, 'one\r\ntZree\n');
      },
    );

    test('canonicalizes reversed ranges and restores deleted newlines', () {
      final model = EditorDocumentModel('alpha\nbeta');
      model.applyEdit(Range(2, 3, 1, 3), 'X\nY');
      expect(model.text, 'alX\nYta');
      expect(model.undo(), true);
      expect(model.text, 'alpha\nbeta');
      expect(model.redo(), true);
      expect(model.text, 'alX\nYta');
    });

    test('groups unordered disjoint edits in one reversible step', () {
      final model = EditorDocumentModel('hello\nworld\nend');
      model.applyEdits([
        EditorDocumentEdit(Range(2, 1, 2, 6), 'Dart'),
        EditorDocumentEdit(Range(1, 1, 1, 6), 'hi'),
      ]);
      expect(model.text, 'hi\nDart\nend');
      expect(model.undo(), true);
      expect(model.text, 'hello\nworld\nend');
      expect(model.canUndo, false);
      expect(model.redo(), true);
      expect(model.text, 'hi\nDart\nend');
      expect(model.canRedo, false);

      model.applyEdit(Range(3, 1, 3, 4), 'last');
      expect(model.text, 'hi\nDart\nlast');
      expect(model.undo(), true);
      expect(model.canRedo, true);
      model.applyEdit(Range(1, 1, 1, 3), 'hey');
      expect(model.canRedo, false);
      expect(model.redo(), false);
    });

    test('keeps mixed inserted endings instead of applying dominant EOL', () {
      final model = EditorDocumentModel('a\r\nb\r\nc');
      model.applyEdit(Range(2, 2, 2, 2), '\nX\rY\r\n');
      expect(model.text, 'a\r\nb\nX\rY\r\n\r\nc');
      expect(model.undo(), true);
      expect(model.text, 'a\r\nb\r\nc');
      expect(model.redo(), true);
      expect(model.text, 'a\r\nb\nX\rY\r\n\r\nc');
    });

    test('undoes an insertion that forms a CRLF across its boundary', () {
      final model = EditorDocumentModel('a\nb');
      model.applyEdit(Range(1, 2, 1, 2), '\r');
      expect(model.text, 'a\r\nb');
      // No range can select only the CR in a CRLF; history retains raw offsets.
      expect(model.positionAtOffset(2).equals(const Position(1, 2)), true);
      expect(model.undo(), true);
      expect(model.text, 'a\nb');
      expect(model.redo(), true);
      expect(model.text, 'a\r\nb');
    });

    test('groups touching edits with mixed EOL and reverses them exactly', () {
      final model = EditorDocumentModel('ab\r\ncd');
      model.applyEdits([
        EditorDocumentEdit(Range(1, 2, 1, 3), '\n'),
        EditorDocumentEdit(Range(1, 3, 2, 1), '\r'),
      ]);
      expect(model.text, 'a\n\rcd');
      expect(model.undo(), true);
      expect(model.text, 'ab\r\ncd');
      expect(model.redo(), true);
      expect(model.text, 'a\n\rcd');
    });

    test('handles an empty document and a BOM-only document', () {
      final empty = EditorDocumentModel('');
      expect(empty.snapshot.lineCount, 1);
      empty.applyEdit(Range(1, 1, 1, 1), 'x');
      expect(empty.text, 'x');
      expect(empty.undo(), true);
      expect(empty.text, '');

      final bomOnly = EditorDocumentModel('﻿');
      expect(bomOnly.text, '﻿');
      bomOnly.applyEdit(Range(1, 2, 1, 2), 'x');
      expect(bomOnly.text, '﻿x');
      expect(bomOnly.undo(), true);
      expect(bomOnly.text, '﻿');
    });

    test('preserves and edits a decoded BOM as part of the raw text', () {
      const original = '﻿alpha\r\nbeta\n';
      final model = EditorDocumentModel(original);
      expect(model.text, original);
      expect(model.snapshot.lineStarts, [0, 8, 13]);
      expect(model.offsetAtPosition(const Position(1, 2)), 1);
      expect(model.positionAtOffset(1).equals(const Position(1, 2)), true);
      expect(model.isDirty, false);

      model.applyEdit(Range(1, 2, 1, 7), 'ALPHA');
      expect(model.text, '﻿ALPHA\r\nbeta\n');
      model.markSaved();
      expect(model.isDirty, false);
      expect(model.savedText, '﻿ALPHA\r\nbeta\n');
      expect(model.undo(), true);
      expect(model.text, original);
      expect(model.isDirty, true);
      expect(model.redo(), true);
      expect(model.isDirty, false);

      model.applyEdit(Range(1, 1, 1, 2), '');
      expect(model.text, 'ALPHA\r\nbeta\n');
      expect(model.undo(), true);
      expect(model.text, '﻿ALPHA\r\nbeta\n');
    });

    test('allows a saved baseline captured before a later edit', () {
      final model = EditorDocumentModel('old');
      model.applyEdit(Range(1, 1, 1, 4), 'saved');
      model.applyEdit(Range(1, 6, 1, 6), '!');
      model.markSaved('saved');
      expect(model.isDirty, true);
      expect(model.undo(), true);
      expect(model.text, 'saved');
      expect(model.isDirty, false);
    });

    test('counts emoji in UTF-16 code units when replacing across lines', () {
      final model = EditorDocumentModel('a😀\r\n😀b');
      expect(model.offsetAtPosition(const Position(1, 4)), 3);
      expect(model.positionAtOffset(2).equals(const Position(1, 3)), true);
      expect(model.positionAtOffset(4).equals(const Position(1, 4)), true);
      expect(model.offsetAtPosition(const Position(2, 3)), 7);
      model.applyEdit(Range(1, 2, 2, 3), '🌍');
      expect(model.text, 'a🌍b');
      expect(model.snapshot.lineCount, 1);
      expect(model.undo(), true);
      expect(model.text, 'a😀\r\n😀b');
    });

    test(
      'syncs Flutter whole-text updates without keeping stale undo history',
      () {
        final model = EditorDocumentModel('a\n😀');
        model.applyEdit(Range(1, 2, 1, 2), 'b');
        expect(model.canUndo, true);
        model.replaceText('a\r\n😀');
        expect(model.text, 'a\r\n😀');
        expect(model.canUndo, false);
        expect(model.canRedo, false);
        model.replaceText('a\r😀');
        expect(model.text, 'a\r😀');
        expect(model.isDirty, true);
      },
    );

    test('updates Unicode and RTL metadata after raw mixed-EOL edits', () {
      final model = EditorDocumentModel('a\r\nb\r\n');
      expect(model.mightContainNonBasicASCII, false);
      expect(model.mightContainRTL, false);
      model.applyEdit(Range(1, 1, 1, 1), '😀\nא');
      expect(model.mightContainNonBasicASCII, true);
      expect(model.mightContainRTL, true);
      expect(model.undo(), true);
      expect(model.mightContainNonBasicASCII, false);
      expect(model.mightContainRTL, false);
    });

    test('searches the current document after incremental edits', () {
      final model = EditorDocumentModel('one\r\ntwo\none');
      expect(model.findMatches(const SearchParams('one')), hasLength(2));
      model.applyEdit(Range(2, 1, 2, 4), 'one');
      final results = model.findMatches(const SearchParams('one'));
      expect(results.map((match) => match.range.startLineNumber), [1, 2, 3]);
      expect(model.findMatches(const SearchParams('missing')), isEmpty);
      expect(
        model
            .findNextMatch(const SearchParams('one'), const Position(2, 4))!
            .range
            .startLineNumber,
        3,
      );
      expect(
        model
            .findPreviousMatch(const SearchParams('one'), const Position(1, 1))!
            .range
            .startLineNumber,
        3,
      );
      model.applyEdit(Range(3, 1, 3, 4), 'three');
      expect(
        model
            .findPreviousMatch(const SearchParams('one'), const Position(1, 1))!
            .range
            .startLineNumber,
        2,
      );
    });

    test('directional search includes raw BOM and UTF-16 columns', () {
      final model = EditorDocumentModel('﻿😀 a\r\n😀 a');
      final next = model.findNextMatch(
        const SearchParams('😀'),
        const Position(1, 1),
      )!;
      expect(next.range.getStartPosition().equals(const Position(1, 2)), true);
      expect(next.range.getEndPosition().equals(const Position(1, 4)), true);
      final previous = model.findPreviousMatch(
        const SearchParams('😀'),
        const Position(1, 1),
      )!;
      expect(
        previous.range.getStartPosition().equals(const Position(2, 1)),
        true,
      );
      expect(model.text, '﻿😀 a\r\n😀 a');
    });

    test('keeps independent instances and their history isolated', () {
      final first = EditorDocumentModel('same\n');
      final second = EditorDocumentModel('same\n');
      first.applyEdit(Range(1, 1, 1, 5), 'changed');
      expect(first.text, 'changed\n');
      expect(second.text, 'same\n');
      expect(second.canUndo, false);
      second.applyEdit(Range(2, 1, 2, 1), 'tail');
      expect(first.text, 'changed\n');
      expect(second.text, 'same\ntail');
      first.undo();
      expect(first.text, 'same\n');
      expect(second.text, 'same\ntail');
    });

    test('rejects overlaps before making any changes', () {
      final model = EditorDocumentModel('abcd');
      expect(
        () => model.applyEdits([
          EditorDocumentEdit(Range(1, 1, 1, 3), 'A'),
          EditorDocumentEdit(Range(1, 2, 1, 4), 'B'),
        ]),
        throwsStateError,
      );
      expect(model.text, 'abcd');
      expect(model.canUndo, false);
      expect(model.undo(), false);
    });

    test('clamps invalid coordinates and ignores exact no-ops', () {
      final model = EditorDocumentModel('ab\r\nc');
      expect(model.offsetAtPosition(const Position(1, 999)), 2);
      expect(model.positionAtOffset(3).equals(const Position(1, 3)), true);
      model.applyEdit(Range(-1, -1, 1, 1), '');
      expect(model.canUndo, false);
      model.applyEdit(Range(1, 999, 1, 999), '!');
      expect(model.text, 'ab!\r\nc');
      expect(model.undo(), true);
      expect(model.text, 'ab\r\nc');
      model.applyEdit(Range(999, 999, 999, 999), '!');
      expect(model.text, 'ab\r\nc!');
      expect(model.undo(), true);
      expect(model.text, 'ab\r\nc');
    });

    test(
      'round-trips varied ranges and newlines through repeated undo/redo',
      () {
        final random = Random(3891);
        const fragments = ['a', '😀', '\n', '\r', '\r\n', 'Z\n\rY', ''];
        var expected = '﻿a\r\nb\rc\n';
        final model = EditorDocumentModel(expected);
        final states = <String>[expected];
        for (var i = 0; i < 100; i++) {
          final before = model.snapshot;
          final first = random.nextInt(expected.length + 1);
          final second = random.nextInt(expected.length + 1);
          final low = first < second ? first : second;
          final high = first > second ? first : second;
          final start = before.positionAtOffset(low);
          final end = before.positionAtOffset(high);
          final startOffset = before.offsetAtPosition(start);
          final endOffset = before.offsetAtPosition(end);
          final replacement = fragments[random.nextInt(fragments.length)];
          model.applyEdit(Range.fromPositions(start, end), replacement);
          final next =
              expected.substring(0, startOffset) +
              replacement +
              expected.substring(endOffset);
          if (next != expected) states.add(next);
          expected = next;
          expect(model.text, expected, reason: 'edit $i');
        }
        for (var i = states.length - 2; i >= 0; i--) {
          expect(model.undo(), true, reason: 'undo $i');
          expect(model.text, states[i], reason: 'undo $i');
        }
        expect(model.undo(), false);
        for (var i = 1; i < states.length; i++) {
          expect(model.redo(), true, reason: 'redo $i');
          expect(model.text, states[i], reason: 'redo $i');
        }
        expect(model.redo(), false);
      },
    );
  });
}
