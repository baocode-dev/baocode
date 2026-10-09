/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The `MainContext` actors of the documents/editors/languages area, for an
// `ExtensionHostService`'s `customers` map.
//
// Upstream these are separate `extHostCustomer` classes
// (mainThreadDocumentsAndEditors.ts registering mainThreadDocuments and
// mainThreadTextEditors, mainThreadDocumentContentProviders.ts,
// mainThreadBulkEdits.ts, mainThreadEditorTabs.ts, mainThreadLanguages.ts,
// mainThreadEditorInsets.ts); this is their one entry point, as the area's
// brief asks.
//
// Deviations:
// - `mainThreadEditorInsets` is unsupported (a webview; the goal section
//   五.15), so its two methods reject as `RpcUnsupported` and the parity
//   report counts them.
// - `mainThreadDocumentsAndEditors` has no identifier upstream, so it is
//   not a customer; its two actors are, and they share the session's state
//   through `services[DocumentsAndEditorsService]`.

import 'package:bao_exthost/bao_exthost.dart';

import 'main_thread_bulk_edits.dart';
import 'main_thread_context.dart';
import 'main_thread_document_content_providers.dart';
import 'main_thread_documents_and_editors.dart';
import 'main_thread_editor_insets.dart';
import 'main_thread_editor_tabs.dart';
import 'main_thread_languages.dart';
import '../workbench/save_participants.dart';

/// Every actor of this area, by `MainContext` id. Add to the `customers` of
/// the workbench's `ExtensionHostService`, with these services:
///
/// - `DocumentsAndEditorsService` (required): the app's documents, editors and the
///   state built on them ([DocumentsAndEditorsService]).
/// - `DocumentsPort` (required): opening, creating and saving documents.
/// - `WorkspaceEditApplier` (optional): applying a `workspace.applyEdit`;
///   without one every workspace edit reports "not applied".
/// - `LanguageRegistry` (required): the language ids and associations.
/// - `LanguageStatusService` (required): `window.createLanguageStatusItem`.
/// - `EditorTabsHost` (required): the app's tab strip.
/// - `TextContentProvidersPort` (optional): virtual documents' texts.
/// - `LanguageTokensPort` (optional): `languages.getTokenTypeAtPosition`.
/// - `ExtensionHostLog` (optional): where a dropped workspace edit is
///   reported.
final Map<int, MainThreadCustomer> documentsAndEditorsCustomers = {
  MainContext.mainThreadDocuments.nid: (context) {
    // `SaveParticipant` (mainThreadSaveParticipant.ts): the extensions'
    // onWillSaveTextDocument run on each save while the host does.
    context.maybeService<ExtensionSaveParticipants>()?.connect(context);
    return documentsActorFor(context);
  },
  MainContext.mainThreadTextEditors.nid: textEditorsActorFor,
  MainContext.mainThreadDocumentContentProviders.nid:
      mainThreadDocumentContentProvidersActor,
  MainContext.mainThreadEditorTabs.nid: mainThreadEditorTabsActor,
  MainContext.mainThreadLanguages.nid: mainThreadLanguagesActor,
  MainContext.mainThreadBulkEdits.nid: mainThreadBulkEditsActor,
  MainContext.mainThreadEditorInsets.nid: (_) => mainThreadEditorInsetsActor(),
};
