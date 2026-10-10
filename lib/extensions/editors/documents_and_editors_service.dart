/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The documents and editors one extension host is told about: the app's
// [ExtensionDocumentRegistry], its [TextEditorHost], the decoration types
// its editors paint with, and the shared [DocumentsAndEditorsState].
//
// Upstream this is `MainThreadDocumentsAndEditors`'s constructor
// parameters (`IModelService`, `ICodeEditorService`, `IEditorService`,
// `ICodeEditorService`); BaoCode passes the app's objects instead, once per
// extension host (the state outlives a session; the actors are rebuilt for
// one).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadDocumentsAndEditors.ts
// (the constructor, `_toModelAddData`, `_toTextEditorAddData`).
//
// Deviations:
// - Who owns what is explicit here: the workbench constructs the service
//   from its own objects and adds `documentsAndEditorsCustomers` to the
//   session's customers; the app reports document events through
//   [state] (an [ExtensionDocumentSync]).

import 'package:bao_editor/monaco/flutter/editor_decoration_types.dart'
    show EditorDecorationTypeRegistry;

import 'document_registry.dart';
import 'documents_and_editors.dart';
import 'editor_ports.dart';

/// The app's documents and editors as the extension host sees them.
final class DocumentsAndEditorsService {
  DocumentsAndEditorsService({
    required this.documents,
    required this.editors,
    this.decorations,
  }) : state = DocumentsAndEditorsState(
         documents: documents,
         editors: editors,
         decorations: decorations,
       );

  /// The app's open documents.
  final ExtensionDocumentRegistry documents;

  /// The app's editors.
  final TextEditorHost editors;

  /// The decoration types the editors paint extension decorations with,
  /// when the app has a registry for them.
  final EditorDecorationTypeRegistry? decorations;

  /// The state every document/editor actor of a session reads. This is
  /// also the app's [ExtensionDocumentSync]: the workspace reports its
  /// documents (open, change, save, dirty, close) through it.
  final DocumentsAndEditorsState state;

  void dispose() => state.dispose();
}
