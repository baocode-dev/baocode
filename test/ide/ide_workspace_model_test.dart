import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:path/path.dart' as p;

import 'workbench/fake_files.dart';

class _FakeIdeFileService with ReadWriteOnlyFiles implements IdeFileService {
  _FakeIdeFileService(this.contents);

  final Map<String, String> contents;
  final List<String> reads = [];
  final List<({String path, String text, String? expectedText})> writes = [];
  final Completer<void> writeStarted = Completer<void>();
  Completer<void>? writeGate;

  @override
  Future<List<IdeFile>> list(String directory) async => [
    for (final path in contents.keys)
      if (p.dirname(path) == directory)
        IdeFile(path, p.basename(path), isDirectory: false),
  ];

  @override
  Future<String> read(String path, {bool force = false}) async {
    reads.add(path);
    return contents[path] ?? (throw StateError('Missing test file: $path'));
  }

  @override
  Future<void> write(String path, String text, {String? expectedText}) async {
    writes.add((path: path, text: text, expectedText: expectedText));
    if (!writeStarted.isCompleted) writeStarted.complete();
    if (writeGate case final gate?) await gate.future;
    if (contents[path] != expectedText) throw IdeFileConflictException(path);
    contents[path] = text;
  }
}

void main() {
  final root = p.join(p.separator, 'virtual-project');
  final first = p.join(root, 'first.txt');
  final second = p.join(root, 'second.txt');

  test(
    'open retains the exact BOM, mixed endings, and initial baseline',
    () async {
      const original = '﻿one\r\ntwo\rthree\n';
      final files = _FakeIdeFileService({first: original});
      final workspace = IdeWorkspace(root, files: files);
      addTearDown(workspace.dispose);

      await workspace.open(first);
      final doc = workspace.active!;
      expect(doc.path, first);
      expect(doc.name, 'first.txt');
      expect(doc.text, original);
      expect(doc.model.text, original);
      expect(doc.model.snapshot.text, original);
      expect(doc.model.snapshot.newlineLengths, [2, 1, 1, 0]);
      expect(doc.savedText, original);
      expect(doc.model.savedText, original);
      expect(doc.dirty, isFalse);

      await workspace.open(first);
      expect(workspace.documents, hasLength(1));
      expect(workspace.active, same(doc));
      expect(files.reads, [first]);
    },
  );

  test(
    'tabs keep independent models, text, baselines, and selection',
    () async {
      final files = _FakeIdeFileService({first: 'one\r\n', second: 'two\n'});
      final workspace = IdeWorkspace(root, files: files);
      addTearDown(workspace.dispose);

      await workspace.open(first);
      final firstDoc = workspace.active!;
      await workspace.open(second);
      final secondDoc = workspace.active!;
      expect(firstDoc.model, isNot(same(secondDoc.model)));

      workspace.edit(first, 'ONE\r\n');
      expect(firstDoc.model.text, 'ONE\r\n');
      expect(firstDoc.savedText, 'one\r\n');
      expect(firstDoc.dirty, isTrue);
      expect(secondDoc.text, 'two\n');
      expect(secondDoc.dirty, isFalse);

      secondDoc.model.applyEdit(Range(1, 1, 1, 4), 'TWO');
      expect(secondDoc.text, 'TWO\n');
      expect(secondDoc.dirty, isTrue);
      expect(firstDoc.text, 'ONE\r\n');
      expect(secondDoc.model.undo(), isTrue);
      expect(secondDoc.text, 'two\n');
      expect(secondDoc.dirty, isFalse);
      expect(firstDoc.dirty, isTrue);

      workspace.select(first);
      expect(workspace.active, same(firstDoc));
      workspace.select(second);
      expect(workspace.active, same(secondDoc));
      expect(workspace.documents, [firstDoc, secondDoc]);
    },
  );

  test(
    'successful save updates baseline; a conflict preserves dirty text',
    () async {
      const original = '﻿one\r\ntwo\rthree\n';
      const saved = '﻿ONE\r\ntwo\rthree\n';
      const edited = '﻿ONE\r\ntwo\rTHREE\n';
      final files = _FakeIdeFileService({first: original});
      final workspace = IdeWorkspace(root, files: files);
      addTearDown(workspace.dispose);

      await workspace.open(first);
      final doc = workspace.active!;
      workspace.edit(first, saved);
      expect(doc.dirty, isTrue);
      await workspace.save(doc);
      expect(files.writes.single, (
        path: first,
        text: saved,
        expectedText: original,
      ));
      expect(files.contents[first], saved);
      expect(doc.savedText, saved);
      expect(doc.model.savedText, saved);
      expect(doc.dirty, isFalse);

      files.contents[first] = 'changed outside the workspace';
      doc.model.applyEdit(Range(3, 1, 3, 6), 'THREE');
      expect(doc.text, edited);
      await expectLater(
        workspace.save(doc),
        throwsA(
          isA<IdeFileConflictException>().having(
            (error) => error.path,
            'path',
            first,
          ),
        ),
      );
      expect(files.writes.last.expectedText, saved);
      expect(files.contents[first], 'changed outside the workspace');
      expect(doc.savedText, saved);
      expect(doc.dirty, isTrue);

      files.contents[first] = saved;
      await workspace.save(doc);
      expect(files.writes.last, (
        path: first,
        text: edited,
        expectedText: saved,
      ));
      expect(doc.savedText, edited);
      expect(doc.dirty, isFalse);
    },
  );

  test(
    'async save marks its captured text, not a later edit, as saved',
    () async {
      final files = _FakeIdeFileService({first: 'old'});
      final workspace = IdeWorkspace(root, files: files);
      addTearDown(workspace.dispose);
      await workspace.open(first);
      final doc = workspace.active!;

      workspace.edit(first, 'saved');
      final gate = files.writeGate = Completer<void>();
      final save = workspace.save(doc);
      await files.writeStarted.future;
      expect(files.writes.single, (
        path: first,
        text: 'saved',
        expectedText: 'old',
      ));
      workspace.edit(first, 'saved again');
      expect(doc.savedText, 'old');
      gate.complete();
      await save;

      expect(files.contents[first], 'saved');
      expect(doc.text, 'saved again');
      expect(doc.model.text, 'saved again');
      expect(doc.savedText, 'saved');
      expect(doc.model.savedText, 'saved');
      expect(doc.dirty, isTrue);
      await workspace.save(doc);
      expect(files.writes.last, (
        path: first,
        text: 'saved again',
        expectedText: 'saved',
      ));
      expect(doc.dirty, isFalse);
    },
  );

  test(
    'close releases a tab, ignores stale edits and saves, and reopens clean',
    () async {
      final files = _FakeIdeFileService({first: 'one', second: 'two'});
      final workspace = IdeWorkspace(root, files: files);
      addTearDown(workspace.dispose);
      await workspace.open(first);
      final closed = workspace.active!;
      await workspace.open(second);
      final survivor = workspace.active!;

      workspace.edit(first, 'unsaved');
      workspace.select(first);
      workspace.close(closed);
      expect(workspace.documents, [survivor]);
      expect(workspace.active, same(survivor));
      workspace.edit(first, 'stale');
      await workspace.save(closed);
      expect(files.writes, isEmpty);
      expect(closed.text, 'unsaved');

      await workspace.open(first);
      expect(workspace.active, isNot(same(closed)));
      expect(workspace.active!.model, isNot(same(closed.model)));
      expect(workspace.active!.text, 'one');
      expect(workspace.active!.dirty, isFalse);
      expect(files.reads, [first, second, first]);
    },
  );

  test(
    'workspace model edits and history notify and update dirty state',
    () async {
      final files = _FakeIdeFileService({first: 'hello\r\n', second: 'other'});
      final workspace = IdeWorkspace(root, files: files);
      addTearDown(workspace.dispose);
      await workspace.open(first);
      final doc = workspace.active!;
      await workspace.open(second);
      final active = workspace.active!;
      var notifications = 0;
      workspace.addListener(() => notifications++);

      workspace.applyEdits(first, [
        EditorDocumentEdit(Range(1, 1, 1, 6), 'HELLO'),
      ]);
      expect(doc.text, 'HELLO\r\n');
      expect(doc.savedText, 'hello\r\n');
      expect(doc.dirty, isTrue);
      expect(workspace.active, same(active));
      expect(notifications, 1);

      workspace.applyEdits(first, [
        EditorDocumentEdit(Range(1, 1, 1, 6), 'HELLO'),
      ]);
      workspace.applyEdits(first, []);
      workspace.applyEdits(p.join(root, 'missing.txt'), [
        EditorDocumentEdit(Range(1, 1, 1, 1), '!'),
      ]);
      expect(notifications, 1);
      expect(doc.model.canUndo, isTrue);

      expect(workspace.undo(first), isTrue);
      expect(doc.text, 'hello\r\n');
      expect(doc.dirty, isFalse);
      expect(notifications, 2);
      expect(workspace.undo(first), isFalse);
      expect(workspace.undo(p.join(root, 'missing.txt')), isFalse);
      expect(notifications, 2);

      expect(workspace.redo(first), isTrue);
      expect(doc.text, 'HELLO\r\n');
      expect(doc.dirty, isTrue);
      expect(notifications, 3);
      expect(workspace.redo(first), isFalse);
      expect(workspace.redo(p.join(root, 'missing.txt')), isFalse);
      expect(notifications, 3);
      expect(files.writes, isEmpty);
    },
  );

  test(
    'no-op edits do not notify, dirty a document, or alter its history',
    () async {
      final files = _FakeIdeFileService({first: 'abc\r\n'});
      final workspace = IdeWorkspace(root, files: files);
      addTearDown(workspace.dispose);
      await workspace.open(first);
      final doc = workspace.active!;
      var notifications = 0;
      workspace.addListener(() => notifications++);

      workspace.edit(first, doc.text);
      doc.text = doc.text;
      doc.model.applyEdit(Range(1, 1, 1, 1), '');
      workspace.edit(second, 'missing');
      expect(notifications, 0);
      expect(doc.model.canUndo, isFalse);
      expect(doc.text, 'abc\r\n');
      expect(doc.dirty, isFalse);
      expect(files.writes, isEmpty);

      workspace.edit(first, 'abcd\r\n');
      expect(notifications, 1);
      expect(doc.dirty, isTrue);
      workspace.edit(first, 'abcd\r\n');
      doc.model.replaceText('abcd\r\n');
      expect(notifications, 1);
      expect(doc.model.canUndo, isFalse);
      doc.model.applyEdit(Range(1, 5, 1, 5), '!');
      expect(doc.text, 'abcd!\r\n');
      expect(doc.model.canUndo, isTrue);
      workspace.edit(first, doc.text);
      doc.text = doc.text;
      expect(notifications, 1);
      expect(doc.model.canUndo, isTrue);
      expect(doc.model.undo(), isTrue);
      expect(doc.text, 'abcd\r\n');
      expect(doc.savedText, 'abc\r\n');
      expect(doc.dirty, isTrue);
    },
  );
}
