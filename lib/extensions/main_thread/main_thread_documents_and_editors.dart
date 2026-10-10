/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What the extension host is told about documents and editors: the state
// (fed by the app), the deltas it becomes, and the two actors on it:
// [MainThreadDocuments] and [MainThreadTextEditors].
//
// Upstream this is `MainThreadDocumentsAndEditors`, an `extHostCustomer`
// with no `MainContext` identifier of its own; it computes the state and
// constructs the two actors above from the same services. BaoCode's
// [DocumentsAndEditorsState] is that state, and this class is what pushes
// it over the wire and builds the two actors for a session.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadDocumentsAndEditors.ts
// (`MainThreadDocumentsAndEditors`, `_onDelta`), mainThreadEditors.ts
// (`$acceptEditorPositionData`, `handleTextEditorAdded`).
//
// Deviations:
// - Upstream also sends `$acceptEditorDiffInformation`; BaoCode's editor has
//   no quick-diff model yet, so it is not sent (the extension's
//   `TextEditor.diffInformation` stays undefined) and `$getDiffInformation`
//   answers an empty list.
// - Upstream has no `MainContext` id; here the two actors are built by the
//   `mainThreadDocuments` and `mainThreadTextEditors` customers, which both
//   go through [SessionDocumentsAndEditors] so they share one state.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../editors/documents_and_editors_service.dart';
import 'main_thread_context.dart';
import 'main_thread_documents.dart';
import 'main_thread_text_editors.dart';

/// The session's actors: one [MainThreadDocuments] and one
/// [MainThreadTextEditors], made from the workbench's [DocumentsAndEditorsService]
/// service, pushing its state to the session's RPC.
final class SessionDocumentsAndEditors {
  SessionDocumentsAndEditors(this.context) {
    final service = context.service<DocumentsAndEditorsService>();
    final rpc = context.rpc;
    final deltaProxy = ExtHostDocumentsAndEditorsProxy(rpc);
    final editorProxy = ExtHostEditorsProxy(rpc);
    _subscriptions
      ..add(
        service.state.deltas.listen((delta) {
          unawaited(deltaProxy.$acceptDocumentsAndEditorsDelta(delta));
        }),
      )
      ..add(
        service.state.propertiesChanged.listen((event) {
          unawaited(
            editorProxy.$acceptEditorPropertiesChanged(event.$1, event.$2),
          );
        }),
      )
      ..add(
        service.state.positionsChanged.listen((data) {
          unawaited(editorProxy.$acceptEditorPositionData(data));
        }),
      );
    documents = MainThreadDocuments(
      state: service.state,
      documents: context.service<DocumentsPort>(),
      rpc: rpc,
    );
    textEditors = MainThreadTextEditors(state: service.state, rpc: rpc);
    // A new host knows nothing: everything open is announced to it.
    service.state.resendAll();
  }

  final MainThreadContext context;
  final _subscriptions = <StreamSubscription<Object?>>[];
  late final MainThreadDocuments documents;
  late final MainThreadTextEditors textEditors;

  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    documents.dispose();
    textEditors.dispose();
  }
}

/// The session's one [SessionDocumentsAndEditors]; the two customers below
/// share it.
SessionDocumentsAndEditors _sessionOf(MainThreadContext context) {
  if (context.maybeService<SessionDocumentsAndEditors>() case final made?) {
    return made;
  }
  final made = SessionDocumentsAndEditors(context);
  context.services[SessionDocumentsAndEditors] = made;
  context.onDispose(made.dispose);
  return made;
}

/// The workbench's `mainThreadDocuments` customer.
RpcActor documentsActorFor(MainThreadContext context) =>
    MainThreadDocumentsActor(_sessionOf(context).documents);

/// The workbench's `mainThreadTextEditors` customer.
RpcActor textEditorsActorFor(MainThreadContext context) =>
    MainThreadTextEditorsActor(_sessionOf(context).textEditors);
