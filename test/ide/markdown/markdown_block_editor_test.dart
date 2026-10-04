import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:baocode/ide/markdown/markdown_block_editor.dart';
import 'package:baocode/ide/markdown/markdown_blocks.dart';
import 'package:baocode/ide/markdown/markdown_document.dart';
import 'package:flutter_test/flutter_test.dart';

/// An edit of [model]'s block [index] (empty lines aside).
MarkdownBlockEdit editBlock(
  EditorDocumentModel model,
  int index, {
  void Function()? onConflict,
}) {
  final source = MarkdownSource(model.text);
  final block = source.blocks[index];
  return MarkdownBlockEdit(
    model,
    start: source.lines.starts[block.start],
    end: source.lines.ends[block.end - 1],
    onConflict: onConflict,
  );
}

void main() {
  test('only the block changes, byte for byte, as one undo step', () {
    const text = '# Title\r\n\r\nOne\r\ntwo\r\n\r\n- a\r\n- b';
    final model = EditorDocumentModel(text);
    final edit = editBlock(model, 1);
    // The field has LF line breaks; the document keeps its CRLF.
    expect(edit.text, 'One\ntwo');
    expect(edit.commit('One\ntwo\nthree'), isTrue);
    expect(model.text, '# Title\r\n\r\nOne\r\ntwo\r\nthree\r\n\r\n- a\r\n- b');
    expect(model.undo(), isTrue);
    expect(model.text, text);
    expect(model.redo(), isTrue);
    expect(model.text, contains('three'));
  });

  test('the last block, with no line break after it', () {
    final model = EditorDocumentModel('a\n\n- x\n- y');
    expect(editBlock(model, 1).commit('- x\n- y\n- z'), isTrue);
    expect(model.text, 'a\n\n- x\n- y\n- z');
  });

  test('lone CR line breaks are kept', () {
    final model = EditorDocumentModel('a\rb\r\rc');
    expect(editBlock(model, 0).commit('a\nB'), isTrue);
    expect(model.text, 'a\rB\r\rc');
  });

  test('the same text makes no edit', () {
    final model = EditorDocumentModel('a\r\nb\r\n\r\nc');
    final version = model.version;
    expect(editBlock(model, 0).commit('a\nb'), isFalse);
    expect(model.version, version);
    expect(model.canUndo, isFalse);
  });

  test('a block emptied goes with its line', () {
    final model = EditorDocumentModel('a\n\nb\n\nc');
    expect(editBlock(model, 1).commit(''), isTrue);
    expect(model.text, 'a\n\n\nc');
  });

  test('edits elsewhere move the block along', () {
    final model = EditorDocumentModel('a\n\nb\n\nc');
    final edit = editBlock(model, 1);
    model.applyOffsetEdits([const EditorOffsetEdit(0, 1, 'first')]);
    model.applyOffsetEdits([
      EditorOffsetEdit(model.text.length, model.text.length, '!'),
    ]);
    expect(edit.conflicted, isFalse);
    expect(edit.commit('B'), isTrue);
    expect(model.text, 'first\n\nB\n\nc!');
  });

  test('a change to the block, or touching it, ends the edit unapplied', () {
    final model = EditorDocumentModel('a\n\nb\n\nc');
    var conflicts = 0;
    final edit = editBlock(model, 1, onConflict: () => conflicts++);
    model.applyOffsetEdits([const EditorOffsetEdit(3, 4, 'B')]);
    expect(edit.conflicted, isTrue);
    expect(conflicts, 1);
    expect(edit.commit('mine'), isFalse);
    expect(model.text, 'a\n\nB\n\nc');

    // Reloaded from disk (the whole text replaced) over the block.
    final reloaded = EditorDocumentModel('a\n\nb\n\nc');
    final other = editBlock(reloaded, 1);
    reloaded.replaceText('a\n\nchanged\n\nc');
    expect(other.conflicted, isTrue);
    // Reloaded elsewhere only: the edit goes on.
    final elsewhere = EditorDocumentModel('a\n\nb\n\nc');
    final third = editBlock(elsewhere, 1);
    elsewhere.replaceText('a\n\nb\n\nc and more');
    expect(third.conflicted, isFalse);
    expect(third.commit('B'), isTrue);
    expect(elsewhere.text, 'a\n\nB\n\nc and more');
  });

  test('a new block at the end, apart from the last', () {
    for (final (text, expected) in [
      ('', 'new'),
      ('a', 'a\n\nnew'),
      ('a\n', 'a\n\nnew'),
      ('a\n\n', 'a\n\nnew'),
      ('a\r\n', 'a\r\n\r\nnew'),
    ]) {
      final model = EditorDocumentModel(text);
      final edit = MarkdownBlockEdit(
        model,
        start: text.length,
        end: text.length,
        prefix: MarkdownBlockEdit.newBlockPrefix(text),
      );
      expect(edit.commit('new'), isTrue);
      expect(model.text, expected);
    }
    final model = EditorDocumentModel('a');
    final empty = MarkdownBlockEdit(
      model,
      start: 1,
      end: 1,
      prefix: MarkdownBlockEdit.newBlockPrefix('a'),
    );
    expect(empty.commit('  \n'), isFalse);
    expect(model.text, 'a');
  });

  test('task boxes tick and untick, by the order of their lines', () {
    const text =
        '- [ ] one\n'
        '- [x] two\n'
        '  ```\n'
        '  - [ ] in code\n'
        '  ```\n'
        '  - [X] nested\n'
        '> - [ ] quoted';
    final model = EditorDocumentModel(text);
    final source = MarkdownSource(text);
    expect(source.blocks.map((b) => b.kind), [
      MarkdownBlockKind.list,
      MarkdownBlockKind.quote,
    ]);
    final marks = [
      ...source.taskMarks(source.blocks[0]),
      ...source.taskMarks(source.blocks[1]),
    ];
    expect([for (final mark in marks) text[mark]], [' ', 'x', 'X', ' ']);
    toggleMarkdownTask(model, marks[0]);
    toggleMarkdownTask(model, marks[2]);
    expect(
      model.text,
      text.replaceFirst('[ ] one', '[x] one').replaceFirst('[X]', '[ ]'),
    );
    expect(model.undo(), isTrue);
    expect(model.text, text.replaceFirst('[ ] one', '[x] one'));
    // What is no box's mark is left alone.
    toggleMarkdownTask(model, 0);
    expect(model.text, text.replaceFirst('[ ] one', '[x] one'));
  });
}
