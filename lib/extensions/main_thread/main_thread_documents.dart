/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The document actor: opening a file without showing it (any scheme),
// creating an untitled document, saving one, and the document events
// (`$acceptModelChanged`, `$acceptDirtyStateChanged`, `$acceptModelSaved`,
// `$acceptEncodingChanged`, `$acceptModelLanguageChanged`).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadDocuments.ts
// (`MainThreadDocuments.$trySaveDocument`/`$tryOpenDocument` with its
// scheme switch and 50 MB check, `$tryCreateDocument`/`_doCreateUntitled`/
// `_handleAsResourceInput`/`_handleUntitledScheme`,
// `handleModelAdded`/`handleModelRemoved`/`_onModelModeChanged`, and its
// `ModelTracker`, which sends the change events this actor sends from the
// app's reports instead).
//
// Deviations:
// - `BoundModelReferenceCollection` (the 3-minute/80 MB/50-reference cache
//   of opened models) is not ported: BaoCode's workspace already releases a
//   document when its last tab closes.
// - `$tryOpenDocument`'s `untitled:` branch does not check whether the file
//   exists (BaoCode's untitled documents are named, not pathed).
// - Opening a document with another encoding than its open model's raises,
//   as upstream does when the model cannot be re-resolved; BaoCode has no
//   per-document encoding switch yet.
// - `$tryDecodeUriAsText` and the other encoding methods upstream added are
//   not in the 1.135.0 protocol this host was generated from.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../editors/document_registry.dart';
import '../editors/documents_and_editors.dart';
import 'main_thread_context.dart';

/// Opening, creating and saving documents, for [MainThreadDocuments].
abstract interface class DocumentsPort {
  /// `$tryOpenDocument`: opens [uri]'s document without showing it and
  /// answers the URI it really opened. [encoding] asks for a different
  /// decoding than the file's.
  Future<VsUri> openDocument(VsUri uri, {String? encoding});

  /// `$tryCreateDocument`: a new, untitled document with [content] in
  /// [languageId]; its URI.
  Future<VsUri> createUntitled({
    String? languageId,
    String? content,
    String? encoding,
  });

  /// `$trySaveDocument`: whether the document was saved.
  Future<bool> saveDocument(VsUri uri);
}

final class MainThreadDocuments extends MainThreadDocumentsUnsupported {
  MainThreadDocuments({
    required this.state,
    required this.documents,
    required RpcProtocol rpc,
  }) {
    final proxy = ExtHostDocumentsProxy(rpc);
    _subscriptions
      ..add(
        state.modelChanges.listen((event) {
          unawaited(
            proxy.$acceptModelChanged(
              event.$1.uri,
              event.$2.toJson(),
              event.$3,
            ),
          );
        }),
      )
      ..add(
        state.dirtyChanges.listen((event) {
          unawaited(proxy.$acceptDirtyStateChanged(event.$1, event.$2));
        }),
      )
      ..add(
        state.saved.listen((uri) {
          unawaited(proxy.$acceptModelSaved(uri));
        }),
      )
      ..add(
        state.encodingChanges.listen((event) {
          unawaited(proxy.$acceptEncodingChanged(event.$1, event.$2));
        }),
      )
      ..add(
        state.languageChanges.listen((event) {
          unawaited(proxy.$acceptModelLanguageChanged(event.$1, event.$2));
        }),
      );
  }

  final DocumentsAndEditorsState state;
  final DocumentsPort documents;

  final _subscriptions = <StreamSubscription<Object?>>[];

  /// `MainThreadDocuments.onIsCaughtUpWithContentChanges`: whether the
  /// extension host has every change of [uri]'s document. BaoCode
  /// delivers the app's changes to the host in the same turn, so it does.
  bool isCaughtUpWithContentChanges(VsUri uri) => true;

  // --- from the extension host

  @override
  Future<bool> $trySaveDocument(VsUri uri) => documents.saveDocument(uri);

  @override
  Future<VsUri> $tryOpenDocument(
    VsUri uri,
    Map<String, Object?>? options,
  ) async {
    if (uri.path.isEmpty && uri.authority.isEmpty) {
      throw RpcRemoteError(
        name: 'Error',
        message: 'Invalid uri. Scheme and authority or path must be set.',
      );
    }
    final VsUri opened;
    try {
      opened = await documents.openDocument(
        uri,
        encoding: options?['encoding'] as String?,
      );
    } on Object catch (error) {
      throw RpcRemoteError(
        name: 'Error',
        message: 'cannot open ${uri.toString()}. Detail: $error',
      );
    }
    if (!_uriEqual(opened, uri)) {
      throw RpcRemoteError(
        name: 'Error',
        message:
            'cannot open ${uri.toString()}. Detail: Actual document opened '
            'as ${opened.toString()}',
      );
    }
    if (!state.documents.contains(documentKeyOf(opened))) {
      throw RpcRemoteError(
        name: 'Error',
        message:
            'cannot open ${uri.toString()}. Detail: Files above 50MB cannot '
            'be synchronized with extensions.',
      );
    }
    return opened;
  }

  @override
  Future<VsUri> $tryCreateDocument(Map<String, Object?>? options) =>
      documents.createUntitled(
        languageId: options?['language'] as String?,
        content: options?['content'] as String?,
        encoding: options?['encoding'] as String?,
      );

  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  static bool _uriEqual(VsUri a, VsUri b) =>
      a.scheme == b.scheme && a.authority == b.authority && a.path == b.path;
}

/// The actor of `MainContext.mainThreadDocuments`, sharing one
/// [MainThreadDocuments] with [MainThreadDocumentsAndEditors].
RpcActor mainThreadDocumentsActor(MainThreadContext context) =>
    MainThreadDocumentsActor(
      MainThreadDocuments(
        state: context.service<DocumentsAndEditorsState>(),
        documents: context.service<DocumentsPort>(),
        rpc: context.rpc,
      ),
    );
