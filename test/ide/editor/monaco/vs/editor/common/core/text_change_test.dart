import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/text_change.dart';

// Mirrors the deterministic compression cases in VS Code's textChange.test.ts.
typedef _Edit = (int offset, int length, String text);

String _apply(String content, List<_Edit> edits) {
  for (final edit in edits.reversed) {
    content =
        content.substring(0, edit.$1) +
        edit.$3 +
        content.substring(edit.$1 + edit.$2);
  }
  return content;
}

List<TextChange> _changes(String content, List<_Edit> edits) {
  final changes = <TextChange>[];
  var delta = 0;
  for (final edit in edits) {
    final position = edit.$1 + delta;
    final oldText = content.substring(position, position + edit.$2);
    content =
        content.substring(0, position) +
        edit.$3 +
        content.substring(position + edit.$2);
    changes.add(TextChange(edit.$1, oldText, position, edit.$3));
    delta += edit.$3.length - edit.$2;
  }
  return changes;
}

void _checkCompression(String initial, List<_Edit> first, List<_Edit> second) {
  final middle = _apply(initial, first);
  final expected = _apply(middle, second);
  final changes = compressConsecutiveTextChanges(
    _changes(initial, first),
    _changes(middle, second),
  );
  expect(
    _apply(initial, [
      for (final c in changes) (c.oldPosition, c.oldLength, c.newText),
    ]),
    expected,
  );
  expect(
    _apply(expected, [
      for (final c in changes) (c.newPosition, c.newLength, c.oldText),
    ]),
    initial,
  );
}

void main() {
  test('exposes UTF-16 lengths/ends and upstream debug strings', () {
    final replacement = TextChange(4, '😀\r\n', 7, '🐱\n');
    expect(replacement.oldLength, 4);
    expect(replacement.oldEnd, 8);
    expect(replacement.newLength, 3);
    expect(replacement.newEnd, 10);
    expect(replacement.toString(), r'(replace@4 "😀\r\n" with "🐱\n")');
    expect(TextChange(2, '', 2, '\r\n').toString(), r'(insert@2 "\r\n")');
    expect(TextChange(2, 'a\nb', 2, '').toString(), r'(delete@2 "a\nb")');
    expect(TextChange(2, '', 2, '').toString(), '(insert@2 "")');
  });

  test('writes upstream mixed-endian UTF-16 format with a nonzero offset', () {
    const change = TextChange(0x12345678, 'A😀', 0x90abcdef, '﻿');
    final bytes = Uint8List(change.writeSize() + 2);
    expect(change.writeSize(), 24);
    expect(change.write(bytes, 2), bytes.length);
    expect(bytes, [
      0, 0, // offset prefix
      0x12, 0x34, 0x56, 0x78, // old position BE
      0x90, 0xab, 0xcd, 0xef, // new position BE
      0, 0, 0, 3, // old length (UTF-16 code units) BE
      0x41, 0, 0x3d, 0xd8, 0, 0xde, // A, surrogate pair LE
      0, 0, 0, 1, // new length BE
      0xff, 0xfe, // BOM preserved as content
    ]);
    final result = <TextChange>[];
    expect(TextChange.read(bytes, 2, result), bytes.length);
    expect(result.single.oldPosition, change.oldPosition);
    expect(result.single.oldText, change.oldText);
    expect(result.single.newPosition, change.newPosition);
    expect(result.single.newText, change.newText);
  });

  test('round-trips multiple records, including BOM and empty strings', () {
    final changes = [
      const TextChange(428, '﻿', 428, ''), // upstream #118041
      const TextChange(429, '', 428, '\r\n😀'),
    ];
    final bytes = Uint8List(changes.fold<int>(0, (n, c) => n + c.writeSize()));
    var offset = 0;
    for (final change in changes) {
      offset = change.write(bytes, offset);
    }
    expect(offset, bytes.length);
    final actual = <TextChange>[];
    offset = TextChange.read(bytes, 0, actual);
    offset = TextChange.read(bytes, offset, actual);
    expect(offset, bytes.length);
    for (var i = 0; i < changes.length; i++) {
      expect(actual[i].toString(), changes[i].toString());
      expect(actual[i].newPosition, changes[i].newPosition);
    }
  });

  test('returns the current list unchanged if there are no prior edits', () {
    final edits = [const TextChange(0, '', 0, 'x')];
    expect(compressConsecutiveTextChanges(null, edits), same(edits));
    expect(compressConsecutiveTextChanges([], edits), same(edits));
  });

  test('compresses adjacent insertions and undoes a no-op', () {
    final adjacent = compressConsecutiveTextChanges(
      [const TextChange(0, '', 0, 'h')],
      [const TextChange(1, '', 1, 'e')],
    );
    expect(adjacent.map((c) => c.toString()).toList(), ['(insert@0 "he")']);
    expect(
      compressConsecutiveTextChanges(
        [const TextChange(0, '', 0, 'x')],
        [const TextChange(0, 'x', 0, '')],
      ),
      isEmpty,
    );
  });

  test('matches upstream deterministic compression/undo scenarios', () {
    _checkCompression('', [(0, 0, 'h')], [(1, 0, 'e')]);
    _checkCompression('|', [(0, 0, 'h')], [(2, 0, 'e')]);
    _checkCompression(
      'abcdefghij',
      [(0, 3, 'qh'), (5, 0, '1'), (8, 2, 'X')],
      [(1, 0, 'Z'), (3, 3, 'Y')],
    );
    _checkCompression('kxm', [(0, 1, 'tod_neu')], [(1, 2, 'sag_e')]);
    _checkCompression('kpb_r_v', [(5, 2, 'a_jvf_l')], [(10, 2, 'w')]);
    _checkCompression('slu_w', [(4, 1, '_wfw')], [(3, 5, '')]);
    _checkCompression('_e', [(2, 0, 'zo_b')], [(1, 3, 'tra')]);
    _checkCompression('ssn_', [(0, 2, 'tat_nwe')], [(2, 6, 'jm')]);
    _checkCompression('kl_nru', [(4, 1, '')], [(1, 4, '__ut')]);
    _checkCompression('a😀b\r\n', [(1, 2, '🐱')], [(1, 2, 'z')]);
  });

  test('seeded edits round-trip through compression and undo', () {
    final random = Random(6);
    const replacements = ['', 'x', '\r', '\n', '\r\n', '😀'];
    for (var i = 0; i < 300; i++) {
      final initial = List.generate(
        random.nextInt(12),
        (_) => random.nextBool() ? 'a' : 'b',
      ).join();
      final firstOffset = random.nextInt(initial.length + 1);
      final first = <_Edit>[
        (
          firstOffset,
          random.nextInt(initial.length - firstOffset + 1),
          replacements[random.nextInt(replacements.length)],
        ),
      ];
      final middle = _apply(initial, first);
      final secondOffset = random.nextInt(middle.length + 1);
      final second = <_Edit>[
        (
          secondOffset,
          random.nextInt(middle.length - secondOffset + 1),
          replacements[random.nextInt(replacements.length)],
        ),
      ];
      _checkCompression(initial, first, second);
    }
  });
}
