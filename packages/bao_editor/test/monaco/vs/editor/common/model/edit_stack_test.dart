import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/core/range.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/core/selection.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/model/edit_stack.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/model/text_model.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/text_model_events.dart';
import 'package:baocode/ide/editor/monaco/vs/platform/undo_redo/common/undo_redo_service.dart';

TextModel document(String resource, String text, UndoRedoService history) {
  final model = TextModel(text);
  model.bindUndoRedo(Uri.parse(resource), history);
  return model;
}

TextModelEditOperation replace(Range range, String text) =>
    TextModelEditOperation(range, text);

void main() {
  test('typing compresses edits and restores directional selections', () {
    final history = UndoRedoService();
    final uri = Uri.parse('file:///typing');
    final model = document('$uri', 'a', history);
    final before = [Selection(1, 2, 1, 1)];
    final middle = [Selection(1, 3, 1, 3)];
    final after = [Selection(1, 4, 1, 2)];
    final observedVersions = <(int, int)>[];
    model.onDidChangeContent((event) {
      observedVersions.add((event.versionId, model.getAlternativeVersionId()));
    });
    model.pushEditOperations(before, [replace(Range(1, 2, 1, 2), 'b')], (
      reverse,
    ) {
      expect(reverse.single.textChange.newText, 'b');
      return middle;
    });
    model.pushEditOperations(middle, [
      replace(Range(1, 3, 1, 3), 'c'),
    ], (_) => after);
    expect(model.getValue(), 'abc');
    expect(history.getElements(uri).past, hasLength(1));
    final entry = history.getLastElement(uri)! as SingleModelEditStackElement;
    expect(entry.data.changes.single.newText, 'bc');
    expect((entry.data.beforeVersionId, entry.data.afterVersionId), (1, 3));
    model.undo();
    expect(model.getValue(), 'a');
    expect((model.getVersionId(), model.getAlternativeVersionId()), (4, 1));
    expect(model.cursorState!.single.equalsSelection(before.single), isTrue);
    model.redo();
    expect(model.getValue(), 'abc');
    expect((model.getVersionId(), model.getAlternativeVersionId()), (5, 3));
    expect(model.cursorState!.single.equalsSelection(after.single), isTrue);
    expect(observedVersions, [(2, 2), (3, 3), (4, 1), (5, 3)]);
    model.dispose();
  });

  test('boundaries and reopening control batching', () {
    final history = UndoRedoService();
    final uri = Uri.parse('file:///boundaries');
    final model = document('$uri', 'a', history);
    model.pushEditOperations(null, [replace(Range(1, 2, 1, 2), 'b')], null);
    model.pushStackElement();
    model.pushEditOperations(null, [replace(Range(1, 3, 1, 3), 'c')], null);
    expect(history.getElements(uri).past, hasLength(2));
    model.popStackElement();
    model.pushEditOperations(null, [replace(Range(1, 4, 1, 4), 'd')], null);
    expect(history.getElements(uri).past, hasLength(2));
    model.undo();
    expect(model.getValue(), 'ab');
    model.undo();
    expect(model.getValue(), 'a');
    model.dispose();
  });

  test('grouped resources restore each model and emit model events', () {
    final history = UndoRedoService();
    final left = document('file:///left', 'L', history);
    final right = document('file:///right', 'R', history);
    final group = UndoRedoGroup();
    final leftEvents = <ModelContentChangedEvent>[];
    final rightEvents = <ModelContentChangedEvent>[];
    left.onDidChangeContent(leftEvents.add);
    right.onDidChangeContent(rightEvents.add);
    left.pushEditOperations(
      null,
      [replace(Range(1, 2, 1, 2), '1')],
      null,
      group: group,
    );
    right.pushEditOperations(
      null,
      [replace(Range(1, 2, 1, 2), '2')],
      null,
      group: group,
    );
    left.undo();
    expect((left.getValue(), right.getValue()), ('L', 'R'));
    expect(
      (left.getAlternativeVersionId(), right.getAlternativeVersionId()),
      (1, 1),
    );
    expect(leftEvents.last.isUndoing, isTrue);
    expect(rightEvents.last.isUndoing, isTrue);
    right.redo();
    expect((left.getValue(), right.getValue()), ('L1', 'R2'));
    expect(leftEvents.last.isRedoing, isTrue);
    expect(rightEvents.last.isRedoing, isTrue);
    left.dispose();
    right.dispose();
  });

  test(
    'UTF-16 disjoint edits round trip with decorations and event ranges',
    () {
      final history = UndoRedoService();
      final model = document('file:///multi', '😀ab\ncd', history);
      final id = model.deltaDecorations([], [
        ModelDeltaDecoration(Range(2, 1, 2, 3)),
      ]).single;
      final events = <ModelContentChangedEvent>[];
      model.onDidChangeContent(events.add);
      model.pushEditOperations(null, [
        replace(Range(2, 1, 2, 3), 'Q'),
        replace(Range(1, 3, 1, 4), 'xyz'),
      ], null);
      expect(model.getValue(), '😀xyzb\nQ');
      model.undo();
      expect(model.getValue(), '😀ab\ncd');
      expect(events.last.isUndoing, isTrue);
      expect(events.last.isFlush, isFalse);
      final restored = model.getDecorationRange(id)!;
      expect(
        (
          restored.startLineNumber,
          restored.startColumn,
          restored.endLineNumber,
          restored.endColumn,
        ),
        (2, 1, 2, 3),
      );
      model.redo();
      expect(model.getValue(), '😀xyzb\nQ');
      expect(events.last.isRedoing, isTrue);
      final redone = model.getDecorationRange(id)!;
      expect(
        (
          redone.startLineNumber,
          redone.startColumn,
          redone.endLineNumber,
          redone.endColumn,
        ),
        (2, 1, 2, 2),
      );
      model.dispose();
    },
  );

  test('long mixed batch survives compression and model restoration', () {
    final history = UndoRedoService();
    final model = document('file:///stress', 'abcdef', history);
    var expected = model.getValue();
    var seed = 12345;
    for (var index = 0; index < 80; index++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final offset = seed % (expected.length + 1);
      final end = index % 3 == 0 && offset < expected.length
          ? offset + 1
          : offset;
      final inserted = index % 4 == 0
          ? ''
          : String.fromCharCode(65 + index % 26);
      model.pushEditOperations(null, [
        replace(Range(1, offset + 1, 1, end + 1), inserted),
      ], null);
      expected = expected.replaceRange(offset, end, inserted);
      expect(model.getValue(), expected);
    }
    model.undo();
    expect(model.getValue(), 'abcdef');
    expect(model.getAlternativeVersionId(), 1);
    model.redo();
    expect(model.getValue(), expected);
    model.dispose();
  });

  test('EOL conversion has its own boundary and restores metadata', () {
    final history = UndoRedoService();
    final model = document('file:///eol', 'a\nb', history);
    final events = <ModelContentChangedEvent>[];
    model.onDidChangeContent(events.add);
    model.pushEditOperations(null, [replace(Range(2, 2, 2, 2), 'c')], null);
    model.pushEOL(EndOfLineSequence.crlf);
    expect(history.getElements(Uri.parse('file:///eol')).past, hasLength(2));
    expect(model.getValue(), 'a\r\nbc');
    expect(model.getAlternativeVersionId(), 3);
    model.undo();
    expect(model.getValue(), 'a\nbc');
    expect(model.getAlternativeVersionId(), 2);
    expect(events.last.isEolChange, isTrue);
    expect(events.last.isUndoing, isTrue);
    model.undo();
    expect(model.getValue(), 'a\nb');
    expect(model.getAlternativeVersionId(), 1);
    model.redo();
    model.redo();
    expect(model.getValue(), 'a\r\nbc');
    expect(model.getAlternativeVersionId(), 3);
    model.dispose();
  });

  test('CRLF text changes restore through ranges without splitting CRLF', () {
    final history = UndoRedoService();
    final model = document('file:///crlf', 'a\r\nb', history);
    model.pushEditOperations(null, [replace(Range(2, 1, 2, 2), 'x\ny')], null);
    expect(model.getValue(), 'a\r\nx\r\ny');
    model.undo();
    expect(model.getValue(), 'a\r\nb');
    model.redo();
    expect(model.getValue(), 'a\r\nx\r\ny');
    model.dispose();
  });

  test('model BOM metadata and normalized mixed endings survive edits', () {
    final history = UndoRedoService();
    final model = document('file:///bom', '﻿a\r\nb\nc', history);
    expect(model.getValue(), 'a\nb\nc');
    expect(model.getValue(EndOfLinePreference.textDefined, true), '﻿a\nb\nc');
    model.pushEditOperations(null, [replace(Range(2, 2, 2, 2), '!')], null);
    model.undo();
    expect(model.getValue(EndOfLinePreference.textDefined, true), '﻿a\nb\nc');
    model.redo();
    expect(model.getValue(EndOfLinePreference.textDefined, true), '﻿a\nb!\nc');
    model.dispose();
  });

  test('redo fork and resource ownership isolate documents', () {
    final history = UndoRedoService();
    final same = Uri.parse('file:///same');
    final first = document('$same', 'a', history);
    final other = document('file:///other', 'x', history);
    expect(() => document('$same', 'not the same', history), throwsStateError);
    first.pushEditOperations(null, [replace(Range(1, 2, 1, 2), 'b')], null);
    other.pushEditOperations(null, [replace(Range(1, 2, 1, 2), 'y')], null);
    first.undo();
    expect(other.getValue(), 'xy');
    first.pushEditOperations(null, [replace(Range(1, 2, 1, 2), 'z')], null);
    expect(first.getValue(), 'az');
    expect(first.canRedo(), isFalse);
    first.dispose();
    expect(history.canUndo(same), isFalse);
    expect(history.canUndo(Uri.parse('file:///other')), isTrue);
    final replacement = document('$same', 'new', history);
    replacement.dispose();
    other.dispose();
  });

  test('rejects overlap and stale model versions without moving history', () {
    final history = UndoRedoService();
    final uri = Uri.parse('file:///invalid');
    final model = document('$uri', 'abc', history);
    expect(
      () => model.pushEditOperations(null, [
        replace(Range(1, 1, 1, 3), 'x'),
        replace(Range(1, 2, 1, 4), 'y'),
      ], null),
      throwsStateError,
    );
    expect(model.canUndo(), isFalse);
    model.pushEditOperations(null, [replace(Range(1, 2, 1, 3), 'z')], null);
    model.applyEdits([replace(Range(1, 2, 1, 3), 'q')]);
    expect(() => history.undo(uri), throwsStateError);
    expect(history.canUndo(uri), isTrue);
    expect(history.canRedo(uri), isFalse);
    expect(model.getValue(), 'aqc');
    model.dispose();
  });

  test('direct edits do not compress into an older bound entry', () {
    final history = UndoRedoService();
    final uri = Uri.parse('file:///external');
    final model = document('$uri', 'a', history);
    model.pushEditOperations(null, [replace(Range(1, 2, 1, 2), 'b')], null);
    model.applyEdits([replace(Range(1, 3, 1, 3), 'c')]);
    model.pushEditOperations(null, [replace(Range(1, 4, 1, 4), 'd')], null);
    expect(history.getElements(uri).past, hasLength(2));
    model.undo();
    expect(model.getValue(), 'abc');
    expect(() => model.undo(), throwsStateError);
    expect(model.getValue(), 'abc');
    model.dispose();
  });

  test('setValue flushes history; disposal clears only its resource', () {
    final history = UndoRedoService();
    final uri = Uri.parse('file:///reset');
    final model = document('$uri', 'abc', history);
    final other = document('file:///unaffected', 'x', history);
    model.pushEditOperations(null, [replace(Range(1, 4, 1, 4), 'd')], null);
    other.pushEditOperations(null, [replace(Range(1, 2, 1, 2), 'y')], null);
    final flushes = <ModelContentChangedEvent>[];
    model.onDidChangeContent(flushes.add);
    model.setValue('fresh');
    expect(flushes.last.isFlush, isTrue);
    expect(model.canUndo(), isFalse);
    expect(model.canRedo(), isFalse);
    model.pushEditOperations(null, [replace(Range(1, 6, 1, 6), '!')], null);
    model.dispose();
    expect(history.canUndo(uri), isFalse);
    expect(other.canUndo(), isTrue);
    other.dispose();
  });

  test('bound model preserves auto-whitespace trimming in forward edits', () {
    final history = UndoRedoService();
    final model = document('file:///trim', '', history);
    model.pushEditOperations(null, [
      TextModelEditOperation(
        Range(1, 1, 1, 1),
        '  ',
        isAutoWhitespaceEdit: true,
      ),
    ], null);
    model.pushEditOperations(null, [
      replace(Range(1, 3, 1, 3), '\nnext'),
    ], null);
    expect(model.getValue(), '\nnext');
    model.undo();
    expect(model.getValue(), '');
    model.dispose();
  });
}
