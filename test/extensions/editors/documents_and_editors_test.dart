// The documents and editors state: the deltas it sends
// (`$acceptDocumentsAndEditorsDelta`), what an editor's properties are
// (`$acceptEditorPropertiesChanged`), its column
// (`$acceptEditorPositionData`), and the document events
// (`$acceptModelChanged` and its `isUndoing`/`isRedoing`,
// `$acceptDirtyStateChanged`, `$acceptModelSaved`,
// `$acceptEncodingChanged`, `$acceptModelLanguageChanged`).

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/documents/model_changed_event.dart';
import 'package:baocode/extensions/editors/document_registry.dart';
import 'package:baocode/extensions/editors/editor_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_editor_host.dart';

void main() {
  late FakeDocumentsAndEditors fixture;
  late DeltaRecorder recorder;

  setUp(() {
    fixture = FakeDocumentsAndEditors();
    recorder = DeltaRecorder(fixture.state);
  });

  tearDown(() {
    recorder.dispose();
    fixture.dispose();
  });

  test('a document and its editor are announced once, with their state', () {
    fixture.open('/p/a.dart', 'void main() {}\n');
    fixture.workbench.openEditor(
      '/p/a.dart',
      text: 'void main() {}\n',
    );
    fixture.state.editorsChanged();

    expect(recorder.addedDocuments, hasLength(1));
    final document = recorder.addedDocuments.single;
    expect(document['uri'], VsUri.file('/p/a.dart').toJson());
    expect(document['lines'], ['void main() {}', '']);
    expect(document['EOL'], '\n');
    expect(document['languageId'], 'plaintext');
    expect(document['isDirty'], false);
    expect(document['versionId'], 1);

    expect(recorder.addedEditors, hasLength(1));
    final editor = recorder.addedEditors.single;
    expect(editor['id'], 'editor:/p/a.dart');
    expect(editor['documentUri'], VsUri.file('/p/a.dart').toJson());
    expect(editor['editorPosition'], 1);
    expect((editor['selections'] as List).single, {
      'selectionStartLineNumber': 1,
      'selectionStartColumn': 1,
      'positionLineNumber': 1,
      'positionColumn': 1,
    });
    expect(editor['options'], {
      'tabSize': 4,
      'indentSize': 4,
      'insertSpaces': true,
      'cursorStyle': EditorCursorStyle.line,
      'lineNumbers': EditorLineNumbers.on,
    });
    expect(editor['visibleRanges'], [Range(1, 1, 40, 1).toJson()]);
  });

  test('a document too large to sync is never announced', () {
    final huge = 'a' * (50 * 1024 * 1024 + 1);
    fixture.open('/p/huge.txt', huge);
    fixture.workbench.openEditor('/p/huge.txt', text: huge);
    fixture.state.editorsChanged();

    expect(recorder.addedDocuments, isEmpty);
    expect(recorder.addedEditors, isEmpty);
    expect(fixture.documents['/p/huge.txt']?.isOpen, false);
  });

  test('the active editor is announced and the old one is not', () {
    fixture.open('/p/a.dart', 'a');
    fixture.open('/p/b.dart', 'b');
    fixture.workbench
      ..openEditor('/p/a.dart', text: 'a')
      ..openEditor('/p/b.dart', text: 'b');
    fixture.state.editorsChanged();
    final first = recorder.activeEditors.last;
    expect(first, 'editor:/p/b.dart');

    fixture.workbench.selectEditor('editor:/p/a.dart');
    fixture.state.editorsChanged();
    expect(recorder.activeEditors.last, 'editor:/p/a.dart');
  });

  test('closing an editor and its document sends removedEditors and '
      'removedDocuments', () {
    fixture.open('/p/a.dart', 'a');
    fixture.workbench.openEditor('/p/a.dart', text: 'a');
    fixture.state.editorsChanged();
    recorder.deltas.clear();

    fixture.workbench.closeEditor('editor:/p/a.dart');
    fixture.state.closeDocument('/p/a.dart', fixture.workbench.models['/p/a.dart']!);

    expect(recorder.removedEditors, ['editor:/p/a.dart']);
    expect(recorder.removedDocuments, [VsUri.file('/p/a.dart').toJson()]);
    expect(fixture.documents.documents, isEmpty);
  });

  test('an editor\'s changed selections, options and visible ranges are '
      'sent as a delta', () {
    fixture.open('/p/a.dart', 'a');
    final editor = fixture.workbench.openEditor('/p/a.dart', text: 'a');
    fixture.state.editorsChanged();
    recorder.properties.clear();

    editor.selections = const [
      EditorSelectionValue(
        anchorLine: 1,
        anchorColumn: 1,
        activeLine: 1,
        activeColumn: 3,
      ),
    ];
    fixture.state.editorStateChanged('editor:/p/a.dart', selectionChangeSource: 'mouse');

    expect(recorder.properties, hasLength(1));
    final (id, delta) = recorder.properties.single;
    expect(id, 'editor:/p/a.dart');
    expect(delta['selections'], {
      'selections': [
        {
          'selectionStartLineNumber': 1,
          'selectionStartColumn': 1,
          'positionLineNumber': 1,
          'positionColumn': 3,
        },
      ],
      'source': 'mouse',
    });
    expect(delta.containsKey('options'), false);
    expect(delta.containsKey('visibleRanges'), false);

    // Nothing changed: no second delta.
    fixture.state.editorStateChanged('editor:/p/a.dart');
    expect(recorder.properties, hasLength(1));

    editor.visibleRanges = [Range(10, 1, 50, 1)];
    fixture.state.editorStateChanged('editor:/p/a.dart');
    expect(recorder.properties, hasLength(2));
    expect(
      recorder.properties.last.$2['visibleRanges'],
      [Range(10, 1, 50, 1).toJson()],
    );
  });

  test('the editor position data follows the editor\'s column', () {
    fixture.open('/p/a.dart', 'a');
    fixture.workbench.openEditor('/p/a.dart', text: 'a');
    fixture.state.editorsChanged();

    expect(recorder.positions.last, {'editor:/p/a.dart': 1});
  });

  test('applying edits through the editor checks the model version and '
      'maps coordinates', () {
    fixture.open('/p/a.dart', 'one\ntwo\n');
    final editor = fixture.workbench.openEditor('/p/a.dart', text: 'one\ntwo\n');
    fixture.state.editorsChanged();
    final model = fixture.workbench.models['/p/a.dart']!;
    final version = fixture.versionOf('/p/a.dart');

    final applied = fixture.state.applyEdits(
      'editor:/p/a.dart',
      version + 1,
      [(range: Range(1, 1, 1, 4), text: 'uno')],
      (undoStopBefore: false, undoStopAfter: false, eol: null),
    );
    expect(applied, false, reason: 'a stale version must not apply');
    expect(editor.appliedEdits, isEmpty);

    final ok = fixture.state.applyEdits(
      'editor:/p/a.dart',
      version,
      [(range: Range(1, 1, 1, 4), text: 'uno')],
      (undoStopBefore: true, undoStopAfter: true, eol: null),
    );
    expect(ok, true);
    expect(model.text, 'uno\ntwo\n');
    expect(editor.appliedEdits.single.text, 'uno');
  });

  test('inserting a snippet replaces whole ranges', () {
    fixture.open('/p/a.dart', 'a\nb\n');
    final editor = fixture.workbench.openEditor('/p/a.dart', text: 'a\nb\n');
    fixture.state.editorsChanged();
    final inserted = fixture.state.insertSnippet(
      'editor:/p/a.dart',
      fixture.versionOf('/p/a.dart'),
      'snippet',
      [Range(1, 1, 1, 2), Range(2, 1, 2, 2)],
      undoStopBefore: false,
      undoStopAfter: false,
    );
    expect(inserted, true);
    expect(editor.inserted.single.text, 'snippet');
    expect(editor.inserted.single.ranges, hasLength(2));
  });

  test('a document change sends the model event with its dirty state', () {
    fixture.open('/p/a.dart', 'one\n');
    final events = <(OpenDocument, ModelChangedEvent, bool)>[];
    final subscription = fixture.state.modelChanges.listen(events.add);
    addTearDown(subscription.cancel);
    final model = fixture.workbench.models['/p/a.dart']!;

    model.applyOffsetEdits([EditorOffsetEdit(0, 3, 'uno')]);

    expect(events, hasLength(1));
    final (document, event, isDirty) = events.single;
    expect(document.key, '/p/a.dart');
    expect(event.changes.single.text, 'uno');
    expect(event.changes.single.rangeOffset, 0);
    expect(isDirty, true);
    expect(document.isDirty, true);
  });

  test('an undo and a redo carry their flags', () {
    fixture.open('/p/a.dart', 'one\n');
    final model = fixture.workbench.models['/p/a.dart']!;
    final events = <ModelChangedEvent>[];
    final subscription = fixture.state.modelChanges.listen((e) => events.add(e.$2));
    addTearDown(subscription.cancel);

    model.applyOffsetEdits([EditorOffsetEdit(0, 3, 'uno')]);
    expect(model.undo(), true);
    expect(model.redo(), true);

    expect(events.map((e) => (e.isUndoing, e.isRedoing)), [
      (false, false),
      (true, false),
      (false, true),
    ]);
  });

  test('the save, dirty and encoding events follow the app', () {
    fixture.open('/p/a.dart', 'one\n');
    final saved = <VsUri>[];
    final dirty = <(VsUri, bool)>[];
    final encodings = <(VsUri, String)>[];
    final events = [
      fixture.state.saved.listen(saved.add),
      fixture.state.dirtyChanges.listen(dirty.add),
      fixture.state.encodingChanges.listen(encodings.add),
    ];
    addTearDown(() {
      for (final event in events) {
        event.cancel();
      }
    });
    final model = fixture.workbench.models['/p/a.dart']!;

    model.applyOffsetEdits([EditorOffsetEdit(0, 3, 'uno')]);
    fixture.state.saveDocument('/p/a.dart', model, 'uno\n');
    fixture.state.encodingChanged('/p/a.dart', model, 'utf16le');

    expect(saved, [VsUri.file('/p/a.dart')]);
    expect(dirty, [
      (VsUri.file('/p/a.dart'), true),
      (VsUri.file('/p/a.dart'), false),
    ]);
    expect(encodings, [(VsUri.file('/p/a.dart'), 'utf16le')]);
  });

  test('a document\'s language change is sent', () {
    fixture.open('/p/a.dart', 'a');
    final changes = <(VsUri, String)>[];
    final subscription = fixture.state.languageChanges.listen(changes.add);
    addTearDown(subscription.cancel);

    fixture.state.languageChanged('/p/a.dart', 'json');

    expect(changes, [(VsUri.file('/p/a.dart'), 'json')]);
    expect(fixture.documents['/p/a.dart']?.mirror.languageId, 'json');
  });

  test('a decoration type registered with the host is applied to an editor',
      () {
    fixture.dispose();
    fixture = FakeDocumentsAndEditors(withDecorations: true);
    recorder.dispose();
    recorder = DeltaRecorder(fixture.state);
    fixture.open('/p/a.dart', 'one\ntwo\n');
    final editor = fixture.workbench.openEditor('/p/a.dart', text: 'one\ntwo\n');
    editor.decorationTypes = fixture.decorations!;
    fixture.state.editorsChanged();

    fixture.state.registerDecorationType('baocode.test', 'k', {
      'backgroundColor': '#ff0000',
    });
    fixture.state.setDecorations('editor:/p/a.dart', 'k', [
      {
        'range': Range(1, 1, 1, 4).toJson(),
        'hoverMessage': {'value': 'hi'},
      },
    ]);

    expect(editor.decorations!.typeKeys, contains('k'));
  });

  test('the app\'s reports open and close documents on the host', () {
    fixture.state
      ..openDocument(
        '/p/a.dart',
        fixture.workbench.models.putIfAbsent(
          '/p/a.dart',
          () => EditorDocumentModel('a'),
        ),
        text: 'a',
        isUntitled: false,
        languageId: 'dart',
      )
      ..notifyListeners();
    expect(fixture.documents['/p/a.dart']?.mirror.languageId, 'dart');
    expect(recorder.addedDocuments, hasLength(1));

    fixture.state.closeDocument(
      '/p/a.dart',
      fixture.workbench.models['/p/a.dart']!,
    );
    expect(recorder.removedDocuments, hasLength(1));
  });
}
