/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What the app's workspace tells the extension host about its documents:
// which opened, what text they have now, which became dirty, which saved,
// and which closed. This replaces the LSP document sync
// (`LanguageDocumentSync`), and it gets the app's document model itself
// (not just path and text) so the mirror can map the raw text's mixed line
// breaks and BOM, and so undo/redo arrive as
// `$acceptModelChanged`'s `isUndoing`/`isRedoing`.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadDocumentsAndEditors.ts
// (`MainThreadDocumentAndEditorStateComputer`'s model tracking and
// `MainThreadDocumentsAndEditors._onDelta`) and
// src/vs/workbench/api/browser/mainThreadDocuments.ts (`ModelTracker`,
// which listens to `IModelService.onModelAdded`/`onModelRemoved`/
// `onModelLanguageChanged` and `ITextFileService.files.onDidSave`/
// `onDidChangeDirty`/`onDidChangeEncoding`).
//
// Deviations:
// - The app calls in; this port does not observe the editor. The app's
//   `EditorDocumentModel.changes` event carries the changes and the model's
//   `lastChangeWasUndo`/`lastChangeWasRedo` (added to bao_editor for this)
//   carry the undo/redo flag.
// - Tabs share one model (`IdeDocument`), so a path is opened once and
//   closed when its last tab goes, as the app's workspace does for its
//   language features.
// - The app has one encoding per file and no per-document encoding switch
//   yet, so [encodingChanged] is called by the app when it learns one.

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';

/// A document change as the app reports it: the mirror needs the changes
/// and whether they were an undo or a redo. `bao_editor`'s
/// `EditorContentChangeEvent` plus `isUndoing`/`isRedoing`.
typedef EditorContentChangeEventLike = ({
  int version,
  List<EditorContentChange> changes,
  bool isUndoing,
  bool isRedoing,
});

/// The app's documents as the extension host sees them. The workspace
/// holds one of these (`IdeWorkspace.extensionDocuments`).
abstract class ExtensionDocumentSync {
  /// [path]'s [model] is open, with this text as it is now.
  void openDocument(
    String path,
    EditorDocumentModel model, {
    required String text,
    required bool isUntitled,
    required String languageId,
    bool isDirty = false,
    String encoding = 'utf8',
  });

  /// [path]'s text changed: [event] is [EditorDocumentModel.changes]'
  /// event, whose `version` is the model's and whose `isUndoing`/
  /// `isRedoing` carry whether the change is an undo or a redo.
  void changeDocument(
    String path,
    EditorDocumentModel model,
    EditorContentChangeEventLike event,
  );

  /// [path] was saved.
  void saveDocument(String path, EditorDocumentModel model, String text);

  /// [path]'s unsaved state changed.
  void dirtyStateChanged(String path, EditorDocumentModel model, bool isDirty);

  /// [path]'s encoding changed.
  void encodingChanged(String path, EditorDocumentModel model, String encoding);

  /// [path] closed (its last tab went).
  void closeDocument(String path, EditorDocumentModel model);
}
