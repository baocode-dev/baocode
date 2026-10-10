/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A resource whose text an extension provides (`registerTextDocumentContentProvider`):
// opening one asks the extension, and its `onDidChange` replaces the text
// of an open document of that scheme.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadDocumentContentProviders.ts
// (`MainThreadDocumentContentProviders.$registerTextContentProvider`,
// `$unregisterTextContentProvider`, `$onVirtualDocumentChange` with its
// per-model cancellation).
//
// Deviations:
// - The app's tab is what opens the resource (a `git:`-like scheme); the
//   provider's text arrives before it ([TextContentProvidersPort.open]).
// - `$onVirtualDocumentChange` replaces the document's whole text (the
//   app's model has no `computeMoreMinimalEdits` yet), as one edit.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../editors/document_registry.dart';
import '../editors/documents_and_editors_service.dart';
import 'main_thread_context.dart';

/// How a scheme's texts are provided, and an open one updated.
abstract interface class TextContentProvidersPort {
  /// `registerTextModelContentProvider(scheme, provider)`: from now on
  /// [provide] answers a resource of [scheme]; the returned function stops
  /// that.
  void Function() register(String scheme, TextContentProvider provide);

  /// The text provider registered for [uri]'s scheme has an updated text:
  /// replace what is open for [uri] with [value].
  Future<void> updateVirtualDocument(VsUri uri, String value);
}

/// `resolveTextContent`: the text of [uri], or null when there is none.
typedef TextContentProvider = Future<String?> Function(VsUri uri);

/// The actor and the providers it registered.
final class MainThreadDocumentContentProviders
    extends MainThreadDocumentContentProvidersUnsupported {
  MainThreadDocumentContentProviders({
    required this.providers,
    required RpcProtocol rpc,
    required this.openDocuments,
  }) {
    _proxy = ExtHostDocumentContentProvidersProxy(rpc);
  }

  final TextContentProvidersPort providers;
  late final ExtHostDocumentContentProvidersProxy _proxy;

  /// The URIs of the app's open documents, for
  /// `$onVirtualDocumentChange`.
  final List<VsUri> Function() openDocuments;

  final Map<num, void Function()> _registrations = {};

  @override
  void $registerTextContentProvider(num handle, String scheme) {
    _registrations.remove(handle)?.call();
    _registrations[handle] = providers.register(
      scheme,
      (uri) => _proxy.$provideTextDocumentContent(handle, uri),
    );
  }

  @override
  void $unregisterTextContentProvider(num handle) =>
      _registrations.remove(handle)?.call();

  @override
  Future<void> $onVirtualDocumentChange(VsUri uri, String value) async {
    if (!openDocuments().any(
      (open) => documentKeyOf(open) == documentKeyOf(uri),
    )) {
      return;
    }
    await providers.updateVirtualDocument(uri, value);
  }

  void dispose() {
    for (final registration in _registrations.values) {
      registration();
    }
    _registrations.clear();
  }
}

/// What the workbench answers for one provider.
RpcActor mainThreadDocumentContentProvidersActor(MainThreadContext context) {
  final state = context.service<DocumentsAndEditorsService>().state;
  return MainThreadDocumentContentProvidersActor(
    MainThreadDocumentContentProviders(
      providers: context.service<TextContentProvidersPort>(),
      rpc: context.rpc,
      openDocuments: () => [
        for (final document in state.documents.documents) document.uri,
      ],
    ),
  );
}
