/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The editor actor: showing, hiding, revealing in and editing through a
// text editor, its selections and options, and the decorations an
// extension sets on it.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadEditors.ts
// (`MainThreadTextEditors.$tryShowTextDocument`, `$tryShowEditor`,
// `$tryHideEditor`, `$trySetSelections`, `$trySetDecorations`,
// `$trySetDecorationsFast`, `$tryRevealRange`, `$trySetOptions`,
// `$tryApplyEdits`, `$tryInsertSnippet`, `$getDiffInformation`,
// `$registerTextEditorDecorationType`, `$removeTextEditorDecorationType`),
// src/vs/workbench/api/browser/mainThreadEditor.ts
// (`MainThreadTextEditor.setSelections`/`setConfiguration`/`applyEdits`/
// `insertSnippet`/`revealRange`/`setDecorations`/`setDecorationsFast`).
//
// Deviations:
// - `$getDiffInformation` answers an empty list (BaoCode's editor has no
//   quick-diff model); `$acceptEditorDiffInformation` is never sent.
// - A decoration type's key is prefixed with this actor's instance id, as
//   upstream does, so two hosts never collide.
// - `$tryShowTextDocument` with `position` (an `EditorGroupColumn`) clamps
//   to the one group the app has.

import 'dart:async';

import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_exthost/bao_exthost.dart';

import '../editors/documents_and_editors.dart';
import '../editors/editor_ports.dart';
import 'main_thread_context.dart';

final class MainThreadTextEditors extends MainThreadTextEditorsUnsupported {
  MainThreadTextEditors({required this.state, required RpcProtocol rpc});

  final DocumentsAndEditorsState state;

  /// `TextEditor($id)`.
  Never _noEditor(String id) => throw RpcRemoteError(
    name: 'Error',
    message: 'TextEditor($id)',
  );

  /// `$registerTextEditorDecorationType`.
  @override
  void $registerTextEditorDecorationType(
    Map<String, Object?> extensionId,
    String key,
    Map<String, Object?> options,
  ) {
    _registeredDecorationTypes.add(key);
    state.registerDecorationType(
      '${extensionId['value'] ?? extensionId['id']}',
      _key(key),
      options,
    );
  }

  @override
  void $removeTextEditorDecorationType(String key) {
    _registeredDecorationTypes.remove(key);
    state.removeDecorationType(_key(key));
  }

  /// The host's decoration types, removed with it.
  final Set<String> _registeredDecorationTypes = {};

  @override
  Future<void> $trySetDecorations(
    String id,
    String key,
    List<Map<String, Object?>> ranges,
  ) {
    if (state.editor(id) == null) _noEditor(id);
    state.setDecorations(id, _key(key), ranges);
    return Future.value();
  }

  @override
  Future<void> $trySetDecorationsFast(
    String id,
    String key,
    List<num> ranges,
  ) {
    if (state.editor(id) == null) _noEditor(id);
    state.setDecorationsFast(id, _key(key), ranges);
    return Future.value();
  }

  @override
  Future<void> $trySetSelections(
    String id,
    List<Map<String, Object?>> selections,
  ) {
    if (state.editor(id) == null) _noEditor(id);
    state.setSelections(id, [
      for (final selection in selections)
        EditorSelectionValue.fromJson(selection),
    ]);
    return Future.value();
  }

  @override
  Future<void> $tryRevealRange(
    String id,
    Map<String, Object?> range,
    int revealType,
  ) {
    if (state.editor(id) == null) _noEditor(id);
    state.revealRange(id, _range(range), revealType);
    return Future.value();
  }

  @override
  Future<void> $trySetOptions(String id, Map<String, Object?> options) {
    final editor = state.editor(id);
    if (editor == null) _noEditor(id);
    final tabSize = options['tabSize'];
    final insertSpaces = options['insertSpaces'];
    state.setOptions(
      id,
      tabSize: tabSize is num ? tabSize.toInt() : null,
      indentSize: (options['indentSize'] as num?)?.toInt(),
      insertSpaces: insertSpaces is bool ? insertSpaces : null,
      cursorStyle: (options['cursorStyle'] as num?)?.toInt(),
      lineNumbers: (options['lineNumbers'] as num?)?.toInt(),
      tabSizeAuto: tabSize == 'auto',
      insertSpacesAuto: insertSpaces == 'auto',
    );
    return Future.value();
  }

  @override
  Future<bool> $tryApplyEdits(
    String id,
    num modelVersionId,
    List<Map<String, Object?>> edits,
    Map<String, Object?> opts,
  ) async {
    if (state.editor(id) == null) _noEditor(id);
    return state.applyEdits(
      id,
      modelVersionId.toInt(),
      [
        for (final edit in edits)
          (range: _range(edit['range']! as Map), text: edit['text'] as String?),
      ],
      (
        undoStopBefore: opts['undoStopBefore'] == true,
        undoStopAfter: opts['undoStopAfter'] == true,
        eol: opts['setEndOfLine'] as String?,
      ),
    );
  }

  @override
  Future<bool> $tryInsertSnippet(
    String id,
    num modelVersionId,
    String template,
    List<Map<String, Object?>> selections,
    Map<String, Object?> opts,
  ) async {
    if (state.editor(id) == null) _noEditor(id);
    return state.insertSnippet(
      id,
      modelVersionId.toInt(),
      template,
      [for (final selection in selections) _range(selection)],
      undoStopBefore: opts['undoStopBefore'] == true,
      undoStopAfter: opts['undoStopAfter'] == true,
    );
  }

  @override
  Future<List<Map<String, Object?>>> $getDiffInformation(String id) async {
    if (state.editor(id) == null) _noEditor(id);
    // No diff editor and no quick-diff model in BaoCode's editor yet, so
    // there are no line changes to report.
    return const [];
  }

  @override
  Future<String?> $tryShowTextDocument(
    VsUri resource,
    Map<String, Object?> options,
  ) async {
    final path = state.documents.pathForUri(resource);
    if (path == null) return null;
    final position = (options['position'] as num?)?.toInt();
    final id = await state.editors.showTextDocument(
      path,
      column: position,
      preserveFocus: options['preserveFocus'] == true,
      // `ITextDocumentShowOptions.pinned` is `!preview`.
      preview: options['pinned'] == false,
    );
    // `selection` is an `IRange` of the model: selected, and revealed
    // (`TextEditorRevealType.InCenterIfOutsideViewport`).
    if (id == null) return null;
    if (options['selection'] case final Map<Object?, Object?> range) {
      final selection = _range(range);
      state.setSelections(id, [
        EditorSelectionValue(
          anchorLine: selection.startLineNumber,
          anchorColumn: selection.startColumn,
          activeLine: selection.endLineNumber,
          activeColumn: selection.endColumn,
        ),
      ]);
      state.revealRange(
        id,
        selection,
        TextEditorRevealType.inCenterIfOutsideViewport,
      );
    }
    return id;
  }

  @override
  Future<void> $tryShowEditor(String id, num position) async {
    if (state.editor(id) == null) return;
    await state.editors.showEditor(id, column: position.toInt());
  }

  @override
  Future<void> $tryHideEditor(String id) async {
    if (state.editor(id) == null) return;
    await state.editors.hideEditor(id);
  }

  /// The host is gone: its decoration types go with it.
  void dispose() {
    for (final key in _registeredDecorationTypes) {
      state.removeDecorationType(_key(key));
    }
    _registeredDecorationTypes.clear();
  }

  /// Upstream prefixes a decoration type's key with the actor instance's
  /// id, so a second host's types never collide with the first's.
  String _key(String key) => '${state.instanceId}-$key';

  static Range _range(Map<Object?, Object?> range) => Range(
    range['startLineNumber']! as int,
    range['startColumn']! as int,
    range['endLineNumber']! as int,
    range['endColumn']! as int,
  );
}

/// The actor of `MainContext.mainThreadTextEditors`.
RpcActor mainThreadTextEditorsActor(MainThreadContext context) =>
    MainThreadTextEditorsActor(
      MainThreadTextEditors(
        state: context.service<DocumentsAndEditorsState>(),
        rpc: context.rpc,
      ),
    );
