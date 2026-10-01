import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/core/range.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/model/piece_tree_text_buffer/piece_tree_text_buffer.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/model/piece_tree_text_buffer/piece_tree_text_buffer_builder.dart';

PieceTreeTextBuffer _buffer(String text, {bool normalizeEOL = true}) {
  final builder = PieceTreeTextBufferBuilder()..acceptChunk(text);
  return builder.finish(normalizeEOL).create(DefaultEndOfLine.lf);
}

ValidAnnotatedEditOperation _edit(
  Range range,
  String? text, {
  bool autoWhitespace = false,
  bool tracked = false,
}) => ValidAnnotatedEditOperation(
  null,
  range,
  text,
  isAutoWhitespaceEdit: autoWhitespace,
  isTracked: tracked,
);

String _readSnapshot(PieceTreeTextBuffer buffer, bool preserveBOM) {
  final snapshot = buffer.createSnapshot(preserveBOM);
  final chunks = <String>[];
  while (true) {
    final chunk = snapshot.read();
    if (chunk == null) break;
    chunks.add(chunk);
  }
  return chunks.join();
}

void main() {
  test('reads content, lines, ranges, positions and snapshots', () {
    final buffer = _buffer('ab\r\ncd\r\nef');
    expect(buffer.getEOL(), '\r\n');
    expect(buffer.getValue(), 'ab\r\ncd\r\nef');
    expect(buffer.getLength(), 10);
    expect(buffer.getLineCount(), 3);
    expect(buffer.getLinesContent(), ['ab', 'cd', 'ef']);
    expect(buffer.getLineContent(2), 'cd');
    expect(buffer.getLineCharCode(2, 1), 'd'.codeUnitAt(0));
    expect(buffer.getOffsetAt(2, 2), 5);
    expect(buffer.getPositionAt(5).toString(), '(2,2)');
    expect(buffer.getRangeAt(4, 2).toString(), '[2,1 -> 2,3]');
    expect(buffer.getValueInRange(Range(1, 2, 3, 2)), 'b\r\ncd\r\ne');
    expect(
      buffer.getValueInRange(Range(1, 2, 3, 2), EndOfLinePreference.lf),
      'b\ncd\ne',
    );
    expect(buffer.getValueLengthInRange(Range(1, 2, 3, 2)), 8);
    expect(
      buffer.getValueLengthInRange(Range(1, 2, 3, 2), EndOfLinePreference.lf),
      6,
    );
    final snapshot = buffer.createSnapshot(false);
    buffer.applyEdits([_edit(Range(1, 1, 1, 2), 'z')]);
    expect(buffer.getValue(), 'zb\r\ncd\r\nef');
    expect(snapshot.read(), 'ab\r\ncd\r\nef');
    expect(snapshot.read(), isNull);
  });

  test('applies sorted edits bottom-to-top and creates reversible edits', () {
    final buffer = _buffer('hello\nworld');
    var notifications = 0;
    final unsubscribe = buffer.onDidChangeContent(() => notifications++);
    final result = buffer.applyEdits(
      [_edit(Range(2, 1, 2, 6), 'Dart'), _edit(Range(1, 1, 1, 6), 'hi')],
      false,
      true,
    );
    expect(buffer.getValue(), 'hi\nDart');
    expect(result.changes.map((e) => e.rangeOffset).toList(), [6, 0]);
    expect(result.changes.map((e) => e.text).toList(), ['Dart', 'hi']);
    // For non-touching edits VS Code restores the input order of inverse edits.
    expect(result.reverseEdits!.map((e) => e.text).toList(), [
      'world',
      'hello',
    ]);
    expect(result.reverseEdits!.map((e) => e.textChange.newPosition).toList(), [
      3,
      0,
    ]);
    expect(notifications, 1);
    buffer.applyEdits([
      for (final reverse in result.reverseEdits!)
        _edit(reverse.range, reverse.text),
    ]);
    expect(buffer.getValue(), 'hello\nworld');
    expect(notifications, 2);
    unsubscribe();
    buffer.applyEdits([]);
    expect(notifications, 2);
  });

  test('touching edits retain undo order and overlapping edits throw', () {
    final buffer = _buffer('abcd');
    final result = buffer.applyEdits(
      [_edit(Range(1, 2, 1, 3), 'X'), _edit(Range(1, 3, 1, 4), 'YZ')],
      false,
      true,
    );
    expect(buffer.getValue(), 'aXYZd');
    expect(result.reverseEdits!.map((e) => e.text).toList(), ['b', 'c']);
    buffer.applyEdits([
      for (final reverse in result.reverseEdits!)
        _edit(reverse.range, reverse.text),
    ]);
    expect(buffer.getValue(), 'abcd');
    expect(
      () => buffer.applyEdits([
        _edit(Range(1, 1, 1, 3), 'A'),
        _edit(Range(1, 2, 1, 4), 'B'),
      ]),
      throwsStateError,
    );
  });

  test('normalizes edits and handles multiline inverse ranges and no-ops', () {
    final buffer = _buffer('a\r\nb');
    final edit = buffer.applyEdits(
      [_edit(Range(1, 2, 2, 1), '\nnew\n'), _edit(Range(2, 2, 2, 2), null)],
      false,
      true,
    );
    expect(buffer.getValue(), 'a\r\nnew\r\nb');
    expect(edit.changes.length, 1);
    expect(edit.changes.single.text, '\r\nnew\r\n');
    expect(edit.reverseEdits!.first.text, '\r\n');
    expect(edit.reverseEdits!.first.range.toString(), '[1,2 -> 3,1]');
    buffer.applyEdits([
      _edit(edit.reverseEdits!.first.range, edit.reverseEdits!.first.text),
    ]);
    expect(buffer.getValue(), 'a\r\nb');
  });

  test('tracks inserted whitespace and optimistic character flags', () {
    final buffer = _buffer('');
    expect(buffer.mightContainRTL(), false);
    expect(buffer.mightContainNonBasicASCII(), false);
    final result = buffer.applyEdits(
      [_edit(Range(1, 1, 1, 1), '  ', autoWhitespace: true)],
      true,
      false,
    );
    expect(result.trimAutoWhitespaceLineNumbers, [1]);
    buffer.applyEdits([_edit(Range(1, 3, 1, 3), 'אב 😀')]);
    expect(buffer.mightContainRTL(), true);
    expect(buffer.mightContainUnusualLineTerminators(), true);
    expect(buffer.mightContainNonBasicASCII(), true);
    expect(
      buffer.getCharacterCountInRange(
        Range(1, 1, 1, buffer.getLineMaxColumn(1)),
      ),
      6,
    );
    buffer.resetMightContainUnusualLineTerminators();
    expect(buffer.mightContainUnusualLineTerminators(), false);
    final indented = _buffer(' \t x\t');
    expect(indented.getLineFirstNonWhitespaceColumn(1), 3);
    expect(indented.getLineLastNonWhitespaceColumn(1), 5);
  });

  test('setEOL normalizes and equals observes BOM and EOL', () {
    final buffer = _buffer('a\nb');
    expect(buffer.equals(_buffer('a\nb')), true);
    buffer.setEOL('\r\n');
    expect(buffer.getValue(), 'a\r\nb');
    expect(buffer.getEOL(), '\r\n');
    expect(buffer.equals(_buffer('a\nb')), false);
    expect(buffer.equals(_buffer('a\r\nb')), true);
  });

  test('snapshot BOM is optional and builder selects majority EOL', () {
    final builder = PieceTreeTextBufferBuilder()
      ..acceptChunk('﻿one\r')
      ..acceptChunk('\ntwo\r')
      ..acceptChunk('\nthree\n');
    final factory = builder.finish();
    expect(factory.getFirstLineText(30), 'one');
    final buffer = factory.create(DefaultEndOfLine.lf);
    expect(buffer.getEOL(), '\r\n');
    expect(buffer.getBOM(), '﻿');
    expect(buffer.getValue(), 'one\r\ntwo\r\nthree\r\n');
    expect(_readSnapshot(buffer, true), '﻿one\r\ntwo\r\nthree\r\n');
    expect(_readSnapshot(buffer, false), buffer.getValue());
    expect(buffer.equals(_buffer('one\r\ntwo\r\nthree\r\n')), false);
  });

  test(
    'builder handles empty, BOM-only, split CRLF, trailing CR and EOL defaults',
    () {
      expect(
        PieceTreeTextBufferBuilder()
            .finish()
            .create(DefaultEndOfLine.crlf)
            .getEOL(),
        '\r\n',
      );
      final bom = PieceTreeTextBufferBuilder()..acceptChunk('﻿');
      expect(bom.finish().create(DefaultEndOfLine.lf).getBOM(), '﻿');
      final split = PieceTreeTextBufferBuilder()
        ..acceptChunk('a\r')
        ..acceptChunk('\nb\r');
      final buffer = split.finish(false).create(DefaultEndOfLine.lf);
      expect(buffer.getValue(), 'a\r\nb\r');
      expect(buffer.getLineCount(), 3);
      expect(buffer.getEOL(), '\r\n');
      expect(buffer.getLinesContent(), ['a', 'b', '']);
      final pureCr = PieceTreeTextBufferBuilder()..acceptChunk('a\rb\r');
      expect(
        pureCr.finish().create(DefaultEndOfLine.lf).getValue(),
        'a\r\nb\r\n',
      );
      final singleCr = PieceTreeTextBufferBuilder()..acceptChunk('\r');
      expect(singleCr.finish().create(DefaultEndOfLine.lf).getValue(), '\r\n');
      final twoBoms = PieceTreeTextBufferBuilder()
        ..acceptChunk('﻿')
        ..acceptChunk('﻿x');
      final twoBomsBuffer = twoBoms.finish().create(DefaultEndOfLine.lf);
      expect(twoBomsBuffer.getBOM(), '﻿');
      expect(twoBomsBuffer.getValue(), '﻿x');
    },
  );

  test('builder preserves UTF-16 surrogate pairs across chunk boundaries', () {
    final builder = PieceTreeTextBufferBuilder()
      ..acceptChunk('x\ud83d')
      ..acceptChunk('\ude00y');
    final buffer = builder.finish().create(DefaultEndOfLine.lf);
    expect(buffer.getValue(), 'x😀y');
    expect(buffer.getLength(), 4);
    expect(buffer.mightContainNonBasicASCII(), true);
    expect(buffer.getCharacterCountInRange(Range(1, 1, 1, 5)), 3);
    final loneSurrogate = PieceTreeTextBufferBuilder()..acceptChunk('\ud83d');
    final lone = loneSurrogate.finish().create(DefaultEndOfLine.lf);
    expect(lone.getLength(), 1);
    expect(lone.mightContainNonBasicASCII(), true);
  });
}
