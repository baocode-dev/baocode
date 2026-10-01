import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_editor/monaco/vs/editor/common/model/piece_tree_text_buffer/piece_tree_base.dart'
    as tree;
import 'package:bao_editor/monaco/vs/editor/common/model/piece_tree_text_buffer/rb_tree_base.dart'
    as rb;

List<int> referenceStarts(String text) {
  final result = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 13) {
      if (i + 1 < text.length && text.codeUnitAt(i + 1) == 10) i++;
      result.add(i + 1);
    } else if (text.codeUnitAt(i) == 10) {
      result.add(i + 1);
    }
  }
  return result;
}

(String, String) referenceLine(String text, List<int> starts, int index) {
  final raw = text.substring(
    starts[index],
    index + 1 < starts.length ? starts[index + 1] : text.length,
  );
  return (raw, raw.replaceFirst(RegExp(r'\r\n$|\r$|\n$'), ''));
}

(int, int) verifyTree(tree.PieceTreeBase buffer, rb.TreeNode node) {
  if (identical(node, rb.sentinel)) return (0, 0);
  expect(
    node.color == rb.NodeColor.red &&
        (node.left.color == rb.NodeColor.red ||
            node.right.color == rb.NodeColor.red),
    isFalse,
  );
  if (!identical(node.left, rb.sentinel)) {
    expect(identical(node.left.parent, node), isTrue);
  }
  if (!identical(node.right, rb.sentinel)) {
    expect(identical(node.right.parent, node), isTrue);
  }
  final left = verifyTree(buffer, node.left);
  final right = verifyTree(buffer, node.right);
  expect(left.$1, right.$1, reason: 'red-black height');
  expect(node.sizeLeft, left.$2);
  expect(node.lfLeft, _countBreaks(node.left));
  final piece = node.piece!;
  final value = buffer.getPieceContent(piece);
  expect(value.length, piece.length);
  expect(referenceStarts(value), piece.lineStarts);
  expect(piece.lineFeedCnt, piece.lineStarts.length - 1);
  return (
    left.$1 + (node.color == rb.NodeColor.black ? 1 : 0),
    left.$2 + piece.length + right.$2,
  );
}

int _countBreaks(rb.TreeNode node) => identical(node, rb.sentinel)
    ? 0
    : node.lfLeft + node.piece!.lineFeedCnt + _countBreaks(node.right);

void verify(tree.PieceTreeBase buffer, String expected) {
  expect(buffer.getLinesRawContent(), expected);
  expect(buffer.getLength(), expected.length);
  final starts = referenceStarts(expected);
  final pieces = <String>[];
  buffer.iterate(buffer.root, (node) {
    if (!identical(node, rb.sentinel)) {
      pieces.add(
        '${buffer.getPieceContent(node.piece!).codeUnits}:${node.piece!.lineFeedCnt}',
      );
    }
    return true;
  });
  expect(
    buffer.getLineCount(),
    starts.length,
    reason: 'document ${expected.codeUnits}, pieces $pieces',
  );
  if (!identical(buffer.root, rb.sentinel)) {
    expect(buffer.root.color, rb.NodeColor.black);
    expect(identical(buffer.root.parent, rb.sentinel), isTrue);
  }
  expect(verifyTree(buffer, buffer.root).$2, expected.length);
  String? previous;
  buffer.iterate(buffer.root, (node) {
    if (identical(node, rb.sentinel)) return true;
    final content = buffer.getPieceContent(node.piece!);
    expect(content, isNotEmpty);
    if (previous != null) {
      expect(
        previous!.endsWith('\r') && content.startsWith('\n'),
        isFalse,
        reason: 'CRLF must not straddle pieces',
      );
    }
    previous = content;
    return true;
  });
  for (var i = 0; i < starts.length; i++) {
    final (raw, line) = referenceLine(expected, starts, i);
    expect(buffer.getOffsetAt(i + 1, 1), starts[i]);
    expect(
      buffer.getLineRawContent(i + 1),
      raw,
      reason: 'document "$expected", line ${i + 1}',
    );
    expect(buffer.getLineContent(i + 1), line);
    expect(buffer.getLineLength(i + 1), line.length);
  }
  expect(buffer.getLinesContent(), [
    for (var i = 0; i < starts.length; i++)
      referenceLine(expected, starts, i).$2,
  ]);
  for (var offset = 0; offset <= expected.length; offset++) {
    final position = buffer.getPositionAt(offset);
    final line = starts.lastIndexWhere((value) => value <= offset);
    expect(position.lineNumber, line + 1, reason: 'offset $offset');
    expect(
      position.column,
      offset - starts[line] + 1,
      reason: 'offset $offset',
    );
    expect(buffer.getOffsetAt(position.lineNumber, position.column), offset);
    if (offset < expected.length) {
      expect(buffer.getCharCode(offset), expected.codeUnitAt(offset));
    }
  }
  expect(
    buffer.getValueInRange(
      Range(1, 1, starts.length, expected.length - starts.last + 1),
    ),
    expected,
  );
}

void main() {
  test('line starts classify CR, LF, CRLF, ASCII and UTF-16', () {
    final scratch = <int>[44];
    final result = tree.createLineStarts(scratch, 'a\r\nb\rc\n😀\t');
    expect(result.lineStarts, [0, 3, 5, 7]);
    expect((result.cr, result.lf, result.crlf), (1, 1, 1));
    expect(result.isBasicASCII, isFalse);
    expect(scratch, isEmpty);
    expect(tree.createLineStartsFast('😀\r\n'), [0, 4]);
  });

  test('original chunks joining CRLF, snapshots, normalized EOL', () {
    final buffer = tree.PieceTreeBase(
      [
        tree.StringBuffer('abc\r', tree.createLineStartsFast('abc\r')),
        tree.StringBuffer('\n😀\n', tree.createLineStartsFast('\n😀\n')),
      ],
      '\n',
      false,
    );
    verify(buffer, 'abc\r\n😀\n');
    final snapshot = buffer.createSnapshot('﻿');
    buffer.insert(1, '\n');
    verify(buffer, 'a\nbc\r\n😀\n');
    final parts = <String>[];
    String? part;
    while ((part = snapshot.read()) != null) {
      parts.add(part!);
    }
    expect(parts.join(), '﻿abc\r\n😀\n');
    buffer.setEOL('\r\n');
    verify(buffer, 'a\r\nbc\r\n😀\r\n');
    expect(buffer.getEOL(), '\r\n');
    expect(buffer.getValueInRange(Range(1, 1, 4, 1), '\n'), 'a\nbc\n😀\n');
  });

  test('split and join at every CRLF boundary, delete whole tree', () {
    for (final value in ['', 'a\r\nb', '\r', '\n', '\r\n', '😀\r\nX']) {
      for (var offset = 0; offset <= value.length; offset++) {
        final buffer = tree.PieceTreeBase(
          [tree.StringBuffer(value, tree.createLineStartsFast(value))],
          '\n',
          false,
        );
        buffer.insert(offset, '\r\n😀');
        final changed =
            '${value.substring(0, offset)}\r\n😀${value.substring(offset)}';
        verify(buffer, changed);
        buffer.delete(offset, '\r\n😀'.length);
        verify(buffer, value);
        buffer.delete(0, buffer.getLength());
        verify(buffer, '');
      }
    }
  });

  test('seeded edits retain text, lines and red-black metadata', () {
    const alphabet = ['a', 'xyz', '\r', '\n', '\r\n', '😀', '界', '\t', ''];
    for (var seed = 0; seed < 8; seed++) {
      final random = Random(seed + 2026);
      final buffer = tree.PieceTreeBase([], '\n', false);
      var reference = '';
      final operations = <String>[];
      for (var step = 0; step < 350; step++) {
        if (reference.isEmpty || random.nextBool()) {
          final offset = random.nextInt(reference.length + 1);
          final value = alphabet[random.nextInt(alphabet.length)];
          operations.add('insert $offset ${value.codeUnits}');
          buffer.insert(offset, value);
          reference =
              reference.substring(0, offset) +
              value +
              reference.substring(offset);
        } else {
          final offset = random.nextInt(reference.length);
          final count = random.nextInt(reference.length - offset + 1);
          operations.add('delete $offset $count');
          buffer.delete(offset, count);
          reference =
              reference.substring(0, offset) +
              reference.substring(offset + count);
        }
        expect(
          buffer.getLineCount(),
          referenceStarts(reference).length,
          reason:
              'seed $seed step $step recent '
              '${operations.skip(max(0, operations.length - 12)).toList()}',
        );
        verify(buffer, reference);
      }
    }
  });

  test('append CRLF across edits on shared buffer', () {
    final buffer = tree.PieceTreeBase([], '\n', false);
    buffer.insert(0, '\r');
    verify(buffer, '\r');
    buffer.insert(1, '\n');
    verify(buffer, '\r\n');
  });

  test('successive edge inserts and single-node deletes exercise rotations', () {
    final buffer = tree.PieceTreeBase([], '\n', false);
    var reference = '';
    for (var i = 0; i < 240; i++) {
      final value = i.isEven ? 'x' : '\n';
      final offset = i % 3 == 0 ? 0 : reference.length;
      buffer.insert(offset, value);
      reference =
          '${reference.substring(0, offset)}$value${reference.substring(offset)}';
    }
    verify(buffer, reference);
    for (var i = 0; i < 200; i++) {
      final offset = i.isEven ? 0 : reference.length - 1;
      buffer.delete(offset, 1);
      reference =
          '${reference.substring(0, offset)}${reference.substring(offset + 1)}';
      if (i % 20 == 0) verify(buffer, reference);
    }
    verify(buffer, reference);
  });

  test('repeated long-line edits share original cursors and change buffer', () {
    final original = '${'a' * 130000}\r\n${'z' * 30000}';
    final originalChunk = tree.StringBuffer(
      original,
      tree.createLineStartsFast(original),
    );
    final buffer = tree.PieceTreeBase([originalChunk], '\n', false);
    var expected = original;
    final random = Random(4511);
    tree.StringBuffer? changeBuffer;
    for (var i = 0; i < 480; i++) {
      // Repeated splits of the same very long original line must retain
      // cursors into its backing chunk, not copy/reindex each long fragment.
      final offset = 55000 + random.nextInt(300);
      if (i.isEven) {
        final text = i % 6 == 0 ? '\r\n😀' : 'q';
        buffer.insert(offset, text);
        expected =
            '${expected.substring(0, offset)}$text${expected.substring(offset)}';
        final at = buffer.nodeAt(offset + text.length - 1)!.node.piece!;
        if (at.bufferIndex == 0) {
          changeBuffer ??= at.backingBuffer;
          expect(identical(at.backingBuffer, changeBuffer), isTrue);
        }
      } else {
        final count = 1 + random.nextInt(3);
        buffer.delete(offset, count);
        expected =
            '${expected.substring(0, offset)}${expected.substring(offset + count)}';
      }
      if (i % 48 == 0) {
        expect(buffer.getLinesRawContent().codeUnits, expected.codeUnits);
        expect(buffer.getLineCount(), referenceStarts(expected).length);
        expect(buffer.getLength(), expected.length);
        final first = buffer.nodeAt(0)!.node.piece!;
        expect(first.bufferIndex, 1);
        expect(identical(first.backingBuffer, originalChunk), isFalse);
        // The created tree uses the same underlying text/line-start list.
        expect(first.backingBuffer!.buffer, original);
        expect(
          identical(first.backingBuffer!.lineStarts, originalChunk.lineStarts),
          isTrue,
        );
      }
    }
    expect(changeBuffer, isNotNull);
    expect(buffer.getLinesRawContent().codeUnits, expected.codeUnits);
    expect(buffer.getLength(), expected.length);
    expect(buffer.getLineCount(), referenceStarts(expected).length);
    expect(verifyTree(buffer, buffer.root).$2, expected.length);
  });

  test('large insert splits at CR and high surrogate', () {
    final value = '${'a' * 65534}\r\n${'b' * 65532}😀tail';
    final buffer = tree.PieceTreeBase([], '\n', false);
    buffer.insert(0, value);
    expect(buffer.getLinesRawContent(), value);
    expect(buffer.getLineCount(), 2);
    verifyTree(buffer, buffer.root);
    buffer.delete(65530, 12);
    verifyTree(buffer, buffer.root);
    expect(buffer.getLength(), value.length - 12);
  });
}
