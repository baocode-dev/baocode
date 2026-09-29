// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/ide/editor/monaco/LICENSE.txt.
// Cases adapted from pinned VS Code defaultLinesDiffComputer.test.ts,
// rangeMapping.ts, and the advanced diffing fixture families.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/range.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/diff/default_lines_diff_computer/algorithms.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/diff/default_lines_diff_computer/char_sequence.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/diff/default_lines_diff_computer/default_lines_diff_computer.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/diff/range_mapping.dart';

void main() {
  final computer = DefaultLinesDiffComputer();
  LinesDiff diff(
    List<String> a,
    List<String> b, {
    bool moves = false,
    bool ignoreWhitespace = false,
    int timeout = 0,
  }) => computer.computeDiff(
    a,
    b,
    LinesDiffComputerOptions(
      computeMoves: moves,
      ignoreTrimWhitespace: ignoreWhitespace,
      maxComputationTimeMs: timeout,
    ),
  );

  group('upstream sequence and range mapping', () {
    test('line-range mapping, deletion (upstream Simple)', () {
      final mapping = getLineRangeMapping(
        RangeMapping(Range(2, 1, 3, 1), Range(2, 1, 2, 1)),
        ['const abc = "helloworld".split("");', '', ''],
        ['const asciiLower = "helloworld".split("");', ''],
      );
      expect(mapping.toString(), '{[2,3)->[2,2)}');
    });

    test('line-range mapping, insertion of empty lines', () {
      final mapping = getLineRangeMapping(
        RangeMapping(Range(2, 1, 2, 1), Range(2, 1, 4, 1)),
        ['', ''],
        ['', '', '', ''],
      );
      expect(mapping.toString(), '{[2,2)->[2,4)}');
    });

    test(
      'inverse and clip preserve the upstream half-open line boundaries',
      () {
        final mappings = [LineRangeMapping(LineRange(3, 5), LineRange(3, 6))];
        final unchanged = LineRangeMapping.inverse(mappings, 7, 8);
        expect(unchanged.map((m) => m.toString()), [
          '{[1,3)->[1,3)}',
          '{[5,8)->[6,9)}',
        ]);
        expect(
          LineRangeMapping.clip(
            mappings,
            LineRange(4, 7),
            LineRange(4, 5),
          ).single.toString(),
          '{[4,5)->[4,5)}',
        );
      },
    );

    test('line character offsets and full-line expansion (upstream)', () {
      final sequence = LinesSliceCharSequence(
        [
          'line1: foo',
          'line2: fizzbuzz',
          'line3: barr',
          'line4: hello world',
          'line5: bazz',
        ],
        Range(2, 1, 5, 1),
        true,
      );
      expect(sequence.translateOffset(0).toString(), '(2,1)');
      expect(sequence.translateOffset(16).toString(), '(3,1)');
      expect(sequence.translateOffset(45).toString(), '(4,18)');
      expect(
        sequence.getText(sequence.extendToFullLines(OffsetRange(20, 25))),
        'line3: barr\n',
      );
    });

    test('do not split a CRLF code-unit pair', () {
      final sequence = LinesSliceCharSequence(
        ['a\r\nb'],
        Range(1, 1, 1, 5),
        true,
      );
      expect(sequence.getBoundaryScore(2), 0);
      expect(sequence.translateOffset(3).toString(), '(1,4)');
    });
  });

  group('default lines diff', () {
    test('identical and empty documents', () {
      expect(diff([''], ['']).changes, isEmpty);
      expect(diff(['one'], ['one']).changes, isEmpty);
      final replacement = diff([''], ['added']);
      expect(replacement.changes.single.original.toString(), '[1,2)');
      expect(replacement.changes.single.modified.toString(), '[1,2)');
      expect(
        replacement.changes.single.innerChanges!.single.modifiedRange.endColumn,
        6,
      );
    });

    test('insert a line between unchanged neighbors', () {
      final result = diff(['before', 'after'], ['before', 'inserted', 'after']);
      expect(result.changes, hasLength(1));
      expect(result.changes.single.original.toString(), '[2,2)');
      expect(result.changes.single.modified.toString(), '[2,3)');
      expect(result.changes.single.innerChanges, isNotEmpty);
    });

    test('insert or delete lines at document boundaries', () {
      final added = diff(['first'], ['first', 'new last']);
      expect(added.changes.single.original.toString(), '[2,2)');
      expect(added.changes.single.modified.toString(), '[2,3)');
      final removed = diff(['old first', 'last'], ['last']);
      expect(removed.changes.single.original.toString(), '[1,2)');
      expect(removed.changes.single.modified.toString(), '[1,1)');
    });

    test('delete a middle line', () {
      final result = diff(['before', 'deleted', 'after'], ['before', 'after']);
      expect(result.changes, hasLength(1));
      expect(result.changes.single.original.toString(), '[2,3)');
      expect(result.changes.single.modified.toString(), '[2,2)');
    });

    test('character-level refinement uses UTF-16 columns', () {
      final result = diff(
        ['before', 'hello world', 'after'],
        ['before', 'hello earth', 'after'],
      );
      final inner = result.changes.single.innerChanges!;
      expect(inner, isNotEmpty);
      expect(inner.first.originalRange.startLineNumber, 2);
      expect(inner.first.originalRange.startColumn, greaterThan(1));
      expect(inner.first.modifiedRange.startLineNumber, 2);
      final emoji = diff(['a😀z'], ['a😀x']).changes.single.innerChanges!;
      expect(emoji.single.originalRange.startColumn, 4);
    });

    test('ignore trimmed whitespace but not internal edits', () {
      expect(
        diff(['  hello  '], ['hello'], ignoreWhitespace: true).changes,
        isEmpty,
      );
      expect(diff(['  hello  '], ['hello']).changes, isNotEmpty);
      expect(
        diff(['a b'], ['a  b'], ignoreWhitespace: true).changes,
        isNotEmpty,
      );
    });

    test('simple three-line move is detected, not removed from changes', () {
      const moved = ['long first line', 'long second line', 'long third line'];
      const stationary = [
        'other line one',
        'other line two',
        'other line three',
        'other line four',
        'other line five',
      ];
      final result = diff(
        ['start', ...moved, ...stationary, 'end'],
        ['start', ...stationary, ...moved, 'end'],
        moves: true,
      );
      expect(result.changes, isNotEmpty);
      expect(result.moves, hasLength(1));
      expect(result.moves.single.lineRangeMapping.original.length, 3);
      expect(result.moves.single.lineRangeMapping.modified.length, 3);
      expect(result.moves.single.changes, isEmpty);
    });

    test('moved text retains a character-level edit inside the move', () {
      const moved = ['long first line', 'long second line', 'long third line'];
      const stationary = [
        'other line one',
        'other line two',
        'other line three',
        'other line four',
        'other line five',
      ];
      final result = diff(
        ['start', ...moved, ...stationary, 'end'],
        [
          'start',
          ...stationary,
          'long first line',
          'long second line',
          'long third lime',
          'end',
        ],
        moves: true,
      );
      expect(result.moves, hasLength(1));
      final changed = result.moves.single.changes;
      expect(changed, hasLength(1));
      expect(changed.single.original.startLineNumber, 4);
      expect(changed.single.modified.startLineNumber, 9);
      expect(changed.single.innerChanges, isNotEmpty);
    });

    test('character mappings reconstruct edited documents', () {
      final random = Random(1901);
      const vocabulary = ['ab', 'xyz', '  ', 'a b', 'ab\r', '😀', 'a', ''];
      for (var iteration = 0; iteration < 180; iteration++) {
        final original = List.generate(
          1 + random.nextInt(7),
          (_) => vocabulary[random.nextInt(vocabulary.length)],
        );
        final modified = List.of(original);
        for (var edit = 0; edit < 3; edit++) {
          final at = random.nextInt(modified.length + 1);
          switch (random.nextInt(3)) {
            case 0:
              modified.insert(
                at,
                vocabulary[random.nextInt(vocabulary.length)],
              );
            case 1:
              if (modified.length > 1 && at < modified.length) {
                modified.removeAt(at);
              }
            default:
              if (at < modified.length) {
                modified[at] = vocabulary[random.nextInt(vocabulary.length)];
              }
          }
        }
        final result = diff(original, modified);
        final before = List<int>.of(original.join('\n').codeUnits);
        final after = modified.join('\n').codeUnits;
        int offset(List<String> lines, int line, int column) {
          var count = column - 1;
          for (var i = 0; i < line - 1; i++) {
            count += lines[i].length + 1;
          }
          return count;
        }

        final edits = [
          for (final change in result.changes) ...change.innerChanges!,
        ];
        for (final mapping in edits.reversed) {
          final start = offset(
            original,
            mapping.originalRange.startLineNumber,
            mapping.originalRange.startColumn,
          );
          final end = offset(
            original,
            mapping.originalRange.endLineNumber,
            mapping.originalRange.endColumn,
          );
          final modStart = offset(
            modified,
            mapping.modifiedRange.startLineNumber,
            mapping.modifiedRange.startColumn,
          );
          final modEnd = offset(
            modified,
            mapping.modifiedRange.endLineNumber,
            mapping.modifiedRange.endColumn,
          );
          before.replaceRange(start, end, after.sublist(modStart, modEnd));
        }
        expect(
          before,
          after,
          reason: 'iteration $iteration: $original -> $modified',
        );
      }
    });

    test('large-file Myers completes for a small change', () {
      final original = List.generate(900, (i) => 'unique line $i');
      final modified = [...original]..[450] = 'replacement at line 450';
      final result = diff(original, modified);
      expect(result.hitTimeout, isFalse);
      expect(result.changes, hasLength(1));
      expect(result.changes.single.original.startLineNumber, 451);
    });

    test('large-file Myers pass respects deadline', () {
      final first = List.generate(1400, (i) => 'original $i');
      final second = List.generate(1400, (i) => 'modified $i');
      final result = diff(first, second, timeout: 1);
      expect(result.hitTimeout, isTrue);
      expect(result.changes, isNotEmpty);
    });
  });
}
