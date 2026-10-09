// The actors' RPC surface: the methods the extension host calls on
// `MainThreadDocuments` and `MainThreadTextEditors`, driven with the exact
// JSON `extHostDocuments.ts`, `extHostDocumentData.ts` and
// `extHostTextEditor.ts` send, through their generated actors.


import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/editors/documents_and_editors.dart';
import 'package:baocode/extensions/main_thread/main_thread_documents.dart';
import 'package:baocode/extensions/main_thread/main_thread_text_editors.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/scripted_rpc.dart';
import 'fake_editor_host.dart';

/// Lets the actors' RPC messages (which the in-memory protocol delivers in
/// a microtask) arrive.
Future<void> pump() => Future<void>.delayed(Duration.zero);

/// The `ExtHost...` proxy calls a [ScriptedRpc] recorded, in order.
List<(String, List<Object?>)> callsToHost(ScriptedRpc rpc) => [
  for (final call in rpc.calls)
    if (call.$1.startsWith('ExtHost')) call,
];

/// A [DocumentsPort] that opens documents the way the app does.
final class FakeDocumentsPort implements DocumentsPort {
  FakeDocumentsPort(this.fixture);

  final FakeDocumentsAndEditors fixture;
  final created = <Map<String, Object?>>[];
  final saved = <VsUri>[];
  final opened = <VsUri>[];

  @override
  Future<VsUri> openDocument(VsUri uri, {String? encoding}) async {
    opened.add(uri);
    final path = uri.fsPath();
    final text = 'let a = 1;\n';
    fixture
      ..open(path, text)
      ..workbench.openEditor(path, text: text);
    fixture.state.editorsChanged();
    return uri;
  }

  @override
  Future<VsUri> createUntitled({
    String? languageId,
    String? content,
    String? encoding,
  }) async {
    created.add({
      'language': languageId,
      'content': content,
      'encoding': encoding,
    });
    fixture
      ..openUntitled('Untitled-1', content ?? '')
      ..workbench.openUntitled('Untitled-1', text: content ?? '');
    fixture.state.editorsChanged();
    return VsUri('untitled', path: 'Untitled-1');
  }

  @override
  Future<bool> saveDocument(VsUri uri) async {
    saved.add(uri);
    fixture.save(uri.fsPath());
    return true;
  }
}

void main() {
  late FakeDocumentsAndEditors fixture;
  late ScriptedRpc rpc;

  setUp(() {
    fixture = FakeDocumentsAndEditors();
    rpc = ScriptedRpc();
  });

  tearDown(() {
    rpc.dispose();
    fixture.dispose();
  });

  test(r'$acceptModelChanged carries the change the app made', () async {
    fixture.open('/p/a.dart', 'let a = 1;\n');
    final actor = MainThreadDocuments(
      state: fixture.state,
      documents: FakeDocumentsPort(fixture),
      rpc: rpc.protocol,
    );
    addTearDown(actor.dispose);
    rpc.calls.clear();

    fixture
        .modelOf('/p/a.dart')
        .applyOffsetEdits([const EditorOffsetEdit(4, 5, 'b')]);
    await pump();

    // The change, then the document turning dirty (`ModelTracker` and
    // `onDidChangeDirty` upstream).
    expect(callsToHost(rpc).map((c) => c.$1), [
      r'ExtHostDocuments.$acceptModelChanged',
      r'ExtHostDocuments.$acceptDirtyStateChanged',
    ]);
    final (_, args) = callsToHost(rpc).first;
    expect(args[0], VsUri.file('/p/a.dart').toJson());
    expect(args[1], {
      'changes': [
        {
          'range': Range(1, 5, 1, 6).toJson(),
          'rangeOffset': 4,
          'rangeLength': 1,
          'text': 'b',
        },
      ],
      'eol': '\n',
      'versionId': 2,
      'isUndoing': false,
      'isRedoing': false,
      'isFlush': false,
      'isEolChange': false,
    });
    expect(args[2], true, reason: 'the document is dirty now');
  });

  test('an undo reaches the host as isUndoing', () async {
    fixture.open('/p/a.dart', 'a');
    final actor = MainThreadDocuments(
      state: fixture.state,
      documents: FakeDocumentsPort(fixture),
      rpc: rpc.protocol,
    );
    addTearDown(actor.dispose);
    final model = fixture.modelOf('/p/a.dart');
    model.applyOffsetEdits([const EditorOffsetEdit(0, 1, 'b')]);
    await pump();
    rpc.calls.clear();

    model.undo();
    await pump();

    // The undo, then the document clean again (back at its saved text).
    expect(callsToHost(rpc).last.$1, r'ExtHostDocuments.$acceptDirtyStateChanged');
    expect(callsToHost(rpc).last.$2[1], false);
    final args = callsToHost(rpc).first.$2;
    final event = (args[1]! as Map).cast<String, Object?>();
    expect(event['isUndoing'], true);
    expect(event['isRedoing'], false);
  });

  test(r'$acceptModelSaved and $acceptDirtyStateChanged follow a save',
      () async {
    fixture.open('/p/a.dart', 'a');
    final actor = MainThreadDocuments(
      state: fixture.state,
      documents: FakeDocumentsPort(fixture),
      rpc: rpc.protocol,
    );
    addTearDown(actor.dispose);
    fixture.modelOf('/p/a.dart').applyOffsetEdits([
      const EditorOffsetEdit(0, 1, 'b'),
    ]);
    await pump();
    rpc.calls.clear();

    fixture.save('/p/a.dart');
    await pump();

    expect(callsToHost(rpc).map((call) => call.$1), [
      r'ExtHostDocuments.$acceptDirtyStateChanged',
      r'ExtHostDocuments.$acceptModelSaved',
    ]);
    expect(callsToHost(rpc).last.$2, [VsUri.file('/p/a.dart').toJson()]);
  });

  test(r'$acceptModelLanguageChanged follows the app', () async {
    fixture.open('/p/a.dart', 'a');
    final actor = MainThreadDocuments(
      state: fixture.state,
      documents: FakeDocumentsPort(fixture),
      rpc: rpc.protocol,
    );
    addTearDown(actor.dispose);
    rpc.calls.clear();

    fixture.state.languageChanged('/p/a.dart', 'dart');
    await pump();

    expect(
      callsToHost(rpc).single.$1,
      r'ExtHostDocuments.$acceptModelLanguageChanged',
    );
    expect(callsToHost(rpc).single.$2, [
      VsUri.file('/p/a.dart').toJson(),
      'dart',
    ]);
  });

  test(r'$tryOpenDocument opens the file and answers its uri', () async {
    final port = FakeDocumentsPort(fixture);
    final actor = MainThreadDocuments(
      state: fixture.state,
      documents: port,
      rpc: rpc.protocol,
    );
    addTearDown(actor.dispose);

    final rpcActor = MainThreadDocumentsActor(actor);
    final answer = await rpcActor.invoke(r'$tryOpenDocument', [
      VsUri.file('/p/a.dart'),
      null,
    ]);

    expect(port.opened, [VsUri.file('/p/a.dart')]);
    expect(answer, VsUri.file('/p/a.dart'));
  });

  test(r'$tryOpenDocument rejects a document the app did not open', () async {
    final actor = MainThreadDocuments(
      state: fixture.state,
      documents: _NoOpenPort(),
      rpc: rpc.protocol,
    );
    addTearDown(actor.dispose);
    final rpcActor = MainThreadDocumentsActor(actor);

    await expectLater(
      rpcActor.invoke(r'$tryOpenDocument', [VsUri.file('/p/none.dart'), null]),
      throwsA(isA<RpcRemoteError>()),
    );
  });

  test(r'$tryCreateDocument asks the app for the untitled document', () async {
    final port = FakeDocumentsPort(fixture);
    final actor = MainThreadDocuments(
      state: fixture.state,
      documents: port,
      rpc: rpc.protocol,
    );
    addTearDown(actor.dispose);
    final rpcActor = MainThreadDocumentsActor(actor);

    final answer = await rpcActor.invoke(r'$tryCreateDocument', [
      {'language': 'dart', 'content': 'void main() {}'},
    ]);

    expect(port.created.single, {
      'language': 'dart',
      'content': 'void main() {}',
      'encoding': null,
    });
    expect(answer, VsUri('untitled', path: 'Untitled-1'));
  });

  test(r'$trySaveDocument answers whether the app saved it', () async {
    final port = FakeDocumentsPort(fixture);
    final actor = MainThreadDocuments(
      state: fixture.state,
      documents: port,
      rpc: rpc.protocol,
    );
    addTearDown(actor.dispose);
    final rpcActor = MainThreadDocumentsActor(actor);

    await port.openDocument(VsUri.file('/p/a.dart'));
    expect(
      await rpcActor.invoke(r'$trySaveDocument', [VsUri.file('/p/a.dart')]),
      true,
    );
    expect(port.saved, [VsUri.file('/p/a.dart')]);
  });

  test(r'$trySetSelections maps model coordinates to editor ones', () async {
    fixture.open('/p/a.dart', '﻿let a = 1;\n');
    final editor = fixture.workbench.openEditor(
      '/p/a.dart',
      text: '﻿let a = 1;\n',
    );
    fixture.state.editorsChanged();
    final actor = MainThreadTextEditors(state: fixture.state, rpc: rpc.protocol);
    addTearDown(actor.dispose);
    final rpcActor = MainThreadTextEditorsActor(actor);

    await rpcActor.invoke(r'$trySetSelections', [
      'editor:/p/a.dart',
      [
        {
          'selectionStartLineNumber': 1,
          'selectionStartColumn': 1,
          'positionLineNumber': 1,
          'positionColumn': 4,
        },
      ],
    ]);

    // The BOM shifts the model's column 1 to the editor's column 2.
    final selection = editor.selections.single;
    expect(selection.anchorColumn, 2);
    expect(selection.activeColumn, 5);
  });

  test(r'$trySetOptions passes the tab size and detects indentation',
      () async {
    fixture.open('/p/a.dart', 'a');
    final editor = fixture.workbench.openEditor('/p/a.dart', text: 'a');
    fixture.state.editorsChanged();
    final actor = MainThreadTextEditors(state: fixture.state, rpc: rpc.protocol);
    addTearDown(actor.dispose);
    final rpcActor = MainThreadTextEditorsActor(actor);

    await rpcActor.invoke(r'$trySetOptions', [
      'editor:/p/a.dart',
      {'tabSize': 2, 'insertSpaces': false, 'cursorStyle': 2, 'lineNumbers': 0},
    ]);

    expect(editor.optionUpdates.single, {
      'tabSize': 2,
      'insertSpaces': false,
      'cursorStyle': 2,
      'lineNumbers': 0,
    });

    await rpcActor.invoke(r'$trySetOptions', [
      'editor:/p/a.dart',
      {'tabSize': 'auto', 'insertSpaces': 'auto'},
    ]);
    expect(editor.optionUpdates.last, {'detectIndentation': true});
  });

  test(r'$tryRevealRange maps the range and passes the reveal type', () async {
    fixture.open('/p/a.dart', 'one\ntwo\n');
    final editor = fixture.workbench.openEditor('/p/a.dart', text: 'one\ntwo\n');
    fixture.state.editorsChanged();
    final actor = MainThreadTextEditors(state: fixture.state, rpc: rpc.protocol);
    addTearDown(actor.dispose);
    final rpcActor = MainThreadTextEditorsActor(actor);

    await rpcActor.invoke(r'$tryRevealRange', [
      'editor:/p/a.dart',
      Range(2, 1, 2, 4).toJson(),
      TextEditorRevealType.atTop,
    ]);

    expect(
      editor.revealed.single.$1.equalsRange(Range(2, 1, 2, 4)),
      true,
      reason: '${editor.revealed.single.$1}',
    );
    expect(editor.revealed.single.$2, TextEditorRevealType.atTop);
  });

  test(r'$tryApplyEdits maps model ranges to editor ones and back', () async {
    fixture.open('/p/a.dart', 'one\ntwo\n');
    final editor = fixture.workbench.openEditor('/p/a.dart', text: 'one\ntwo\n');
    fixture.state.editorsChanged();
    final actor = MainThreadTextEditors(state: fixture.state, rpc: rpc.protocol);
    addTearDown(actor.dispose);
    final rpcActor = MainThreadTextEditorsActor(actor);

    final applied = await rpcActor.invoke(r'$tryApplyEdits', [
      'editor:/p/a.dart',
      fixture.versionOf('/p/a.dart'),
      [
        {
          'range': Range(1, 1, 1, 4).toJson(),
          'text': 'uno',
          'forceMoveMarkers': false,
        },
      ],
      {'undoStopBefore': true, 'undoStopAfter': true},
    ]);

    expect(applied, true);
    expect(fixture.modelOf('/p/a.dart').text, 'uno\ntwo\n');
    expect(editor.appliedEdits.single.text, 'uno');
  });

  test(r'$tryApplyEdits refuses a stale model version', () async {
    fixture.open('/p/a.dart', 'one\n');
    final editor = fixture.workbench.openEditor('/p/a.dart', text: 'one\n');
    fixture.state.editorsChanged();
    final actor = MainThreadTextEditors(state: fixture.state, rpc: rpc.protocol);
    addTearDown(actor.dispose);
    final rpcActor = MainThreadTextEditorsActor(actor);

    final applied = await rpcActor.invoke(r'$tryApplyEdits', [
      'editor:/p/a.dart',
      fixture.versionOf('/p/a.dart') + 1,
      [
        {
          'range': Range(1, 1, 1, 2).toJson(),
          'text': 'x',
          'forceMoveMarkers': false,
        },
      ],
      <String, Object?>{},
    ]);

    expect(applied, false);
    expect(editor.appliedEdits, isEmpty);
  });

  test(r'$tryInsertSnippet gives the editor the snippet', () async {
    fixture.open('/p/a.dart', 'a\n');
    final editor = fixture.workbench.openEditor('/p/a.dart', text: 'a\n');
    fixture.state.editorsChanged();
    final actor = MainThreadTextEditors(state: fixture.state, rpc: rpc.protocol);
    addTearDown(actor.dispose);
    final rpcActor = MainThreadTextEditorsActor(actor);

    await rpcActor.invoke(r'$tryInsertSnippet', [
      'editor:/p/a.dart',
      fixture.versionOf('/p/a.dart'),
      'for (\${1:i} = 0; \$2; \$3) {\n\t\$0\n}',
      [Range(1, 1, 1, 2).toJson()],
      {'undoStopBefore': true, 'undoStopAfter': true},
    ]);

    // The editor runs it as a snippet (its tab stops and placeholders).
    expect(editor.inserted.single.text, 'for (\${1:i} = 0; \$2; \$3) {\n\t\$0\n}');
  });

  test(r'$tryShowTextDocument opens the document and answers the editor id',
      () async {
    fixture
      ..open('/p/a.dart', 'a')
      ..workbench.openEditor('/p/a.dart', text: 'a');
    fixture.state.editorsChanged();
    final actor = MainThreadTextEditors(state: fixture.state, rpc: rpc.protocol);
    addTearDown(actor.dispose);
    final rpcActor = MainThreadTextEditorsActor(actor);

    final id = await rpcActor.invoke(r'$tryShowTextDocument', [
      VsUri.file('/p/a.dart'),
      {'preserveFocus': false, 'preview': false},
    ]);

    expect(id, 'editor:/p/a.dart');
  });

  test('a decoration type and its ranges reach the editor', () async {
    fixture.dispose();
    fixture = FakeDocumentsAndEditors(withDecorations: true);
    fixture
      ..open('/p/a.dart', 'one\ntwo\n')
      ..workbench.openEditor('/p/a.dart', text: 'one\ntwo\n');
    final editor = fixture.workbench.editors['editor:/p/a.dart']!;
    editor.decorationTypes = fixture.decorations!;
    fixture.state.editorsChanged();
    final actor = MainThreadTextEditors(state: fixture.state, rpc: rpc.protocol);
    addTearDown(actor.dispose);
    final rpcActor = MainThreadTextEditorsActor(actor);

    await rpcActor.invoke(r'$registerTextEditorDecorationType', [
      {'value': 'baocode.test'},
      'myType',
      {'backgroundColor': '#ff0000', 'isWholeLine': false},
    ]);
    await rpcActor.invoke(r'$trySetDecorations', [
      'editor:/p/a.dart',
      'myType',
      [
        {'range': Range(2, 1, 2, 4).toJson()},
      ],
    ]);

    // The type is registered under its instance-prefixed key.
    final key = '${fixture.state.instanceId}-myType';
    expect(editor.decorations!.typeKeys, contains(key));

    await rpcActor.invoke(r'$removeTextEditorDecorationType', ['myType']);
    expect(editor.decorations!.typeKeys, isNot(contains(key)));
  });

  test(r'$getDiffInformation answers no changes', () async {
    fixture.open('/p/a.dart', 'a');
    fixture.workbench.openEditor('/p/a.dart', text: 'a');
    fixture.state.editorsChanged();
    final actor = MainThreadTextEditors(state: fixture.state, rpc: rpc.protocol);
    addTearDown(actor.dispose);
    final rpcActor = MainThreadTextEditorsActor(actor);

    expect(
      await rpcActor.invoke(r'$getDiffInformation', ['editor:/p/a.dart']),
      <Object?>[],
    );
  });

  test('a call for an unknown editor rejects, as upstream does', () async {
    final actor = MainThreadTextEditors(state: fixture.state, rpc: rpc.protocol);
    addTearDown(actor.dispose);
    final rpcActor = MainThreadTextEditorsActor(actor);

    await expectLater(
      rpcActor.invoke(r'$trySetSelections', ['nope', <Object?>[]]),
      throwsA(isA<RpcRemoteError>()),
    );
  });
}

/// A port that never opens anything (the app's editor is elsewhere).
final class _NoOpenPort implements DocumentsPort {
  @override
  Future<VsUri> openDocument(VsUri uri, {String? encoding}) async => uri;

  @override
  Future<VsUri> createUntitled({
    String? languageId,
    String? content,
    String? encoding,
  }) async => VsUri('untitled', path: 'Untitled-1');

  @override
  Future<bool> saveDocument(VsUri uri) async => false;
}
