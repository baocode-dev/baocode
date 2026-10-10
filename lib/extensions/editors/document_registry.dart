/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The open documents the extension host knows, each as an
// [ExtHostDocumentMirror], and the [LanguageFeatureDocuments] the language
// feature registry resolves providers through.
//
// This plays `IModelService`'s part for the extension host plus the open
// document set `MainThreadDocumentAndEditorStateComputer` computes: a
// document is in it while the app has its text open and it is not too
// large to sync (`shouldSynchronizeModel`), and it is new to the extension
// host while this registry says so.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/common/services/modelService.ts (`IModelService`),
// src/vs/workbench/api/browser/mainThreadDocumentsAndEditors.ts
// (`DocumentAndEditorState.compute`, `diffSets`,
// `shouldSynchronizeModel`).
//
// Deviations:
// - Documents are addressed by their absolute path for `file:` URIs (the
//   app's own model); [ExtensionDocumentRegistry.pathForUri] also answers
//   for other schemes whose document is open (an `untitled:` one), so a
//   provider finds that document's text too.
// - The set is not derived by diffing snapshots: the app's sync port tells
//   the registry what opened and closed, and the registry answers the
//   delta.

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/vs/base/common/platform.dart' as platform;
import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:flutter/foundation.dart';

import '../documents/ext_host_document_mirror.dart';
import '../documents/model_changed_event.dart';
import '../language/language_feature_document.dart';
import '../language/registry_language_features.dart'
    show LanguageFeatureDocuments;

export '../language/language_feature_document.dart'
    show LanguageFeatureDocument;

/// The key a document is stored under: its absolute path for a `file:`
/// URI, its own address otherwise.
String documentKeyOf(VsUri uri) => uri.scheme == 'file'
    ? uri.fsPath(windows: platform.isWindows)
    : uri.toString();

/// Everything the extension host knows about one open document.
class OpenDocument {
  OpenDocument({
    required this.key,
    required this.uri,
    required this.model,
    required this.mirror,
    this.isUntitled = false,
    this.encoding = 'utf8',
    // A named parameter cannot be private.
    // ignore: prefer_initializing_formals
    this.isDirty = false,
  });

  /// The key in [ExtensionDocumentRegistry].
  final String key;

  /// The URI the extension host sees.
  final VsUri uri;

  /// The app's document.
  final EditorDocumentModel model;

  final ExtHostDocumentMirror mirror;

  /// A new file, not saved anywhere yet.
  final bool isUntitled;

  /// The encoding id (`utf8`, `utf8bom`, …).
  String encoding;

  /// Whether the text differs from the file's (untitled documents count
  /// as dirty, as VS Code's do).
  bool isDirty;

  /// Whether the extension host has this document
  /// (`TextDocument.isClosed` is false). A document that is too large to
  /// sync never is.
  bool get isOpen => announced && mirror.isSynchronized;

  /// Set when `$acceptDocumentsAndEditorsDelta` announced this document.
  bool announced = false;

  /// The document a language feature provider sees.
  ExtHostDocumentMirror get document => mirror;

  /// `IModelAddedData` for `$acceptDocumentsAndEditorsDelta`.
  Map<String, Object?> toModelAddedData() => mirror
      .toModelAddedData(isDirty: isDirty, encoding: encoding)
      .toJson();

  /// The document's text without a leading U+FEFF, on one line, for the
  /// first-line language association.
  String get firstLine {
    final text = mirror.rawText;
    final start = text.startsWith('﻿') ? 1 : 0;
    final end = text.indexOf(RegExp(r'\r\n|\r|\n'), start);
    return text.substring(start, end < 0 ? text.length : end);
  }
}

/// What changed in the registry, as
/// `$acceptDocumentsAndEditorsDelta`'s `addedDocuments`/`removedDocuments`.
class DocumentsDelta {
  const DocumentsDelta({this.added = const [], this.removed = const []});

  final List<OpenDocument> added;
  final List<VsUri> removed;

  bool get isEmpty => added.isEmpty && removed.isEmpty;
}

/// The app's open documents the extension host is told about, and the
/// [LanguageFeatureDocuments] language providers resolve against.
///
/// The app's sync port calls [open], [close], [acceptModelChanges],
/// [markSaved], [markDirty] and [markEncoding]; every one of them bumps
/// [version], which [ExtensionDocumentsAndEditors] listens to in order to
/// send the delta and the document events.
final class ExtensionDocumentRegistry extends ChangeNotifier
    implements LanguageFeatureDocuments {
  final Map<String, OpenDocument> _byKey = {};
  final Map<EditorDocumentModel, String> _keyByModel = {};

  /// The language id the user picked for a document, which wins over the
  /// one its file name gives (`ExtHostDocuments.$acceptModelLanguageChanged`).
  final Map<String, String> _userLanguage = {};

  int _version = 0;

  /// Bumped by every text change, save, language change and open/close.
  int get version => _version;

  List<OpenDocument> get documents => List.unmodifiable(_byKey.values);

  bool contains(String key) => _byKey.containsKey(key);

  OpenDocument? operator [](String key) => _byKey[key];

  OpenDocument? byUri(VsUri uri) => _byKey[documentKeyOf(uri)];

  /// The key of the document [model] belongs to, if it is registered.
  String? keyOfModel(EditorDocumentModel model) => _keyByModel[model];

  /// Registers [key]'s open document. When one is already known under
  /// [key], it is returned as it is (its mirror keeps its version).
  OpenDocument open(
    String key, {
    required VsUri uri,
    required String text,
    required EditorDocumentModel model,
    required String languageId,
    bool isUntitled = false,
    bool isDirty = false,
    String encoding = 'utf8',
    String defaultEol = '\n',
  }) {
    final existing = _byKey[key];
    if (existing != null) {
      _keyByModel[model] = key;
      return existing;
    }
    final document = OpenDocument(
      key: key,
      uri: uri,
      model: model,
      mirror: ExtHostDocumentMirror(
        uri: uri,
        languageId: languageId,
        text: text,
        defaultEol: defaultEol,
      ),
      isUntitled: isUntitled,
      encoding: encoding,
      isDirty: isDirty,
    );
    _byKey[key] = document;
    _keyByModel[model] = key;
    return document;
  }

  /// An untitled document's text is replaced (`$tryCreateDocument` with
  /// content, or an untitled file opened again with other content).
  ModelChangedEvent? reset(OpenDocument document, String text) {
    final event = document.mirror.reset(text);
    _version++;
    return event;
  }

  /// Forgets [key]. Answers the URI to tell the extension host about when
  /// it knew the document, else null.
  VsUri? close(String key) {
    final document = _byKey.remove(key);
    if (document == null) return null;
    _keyByModel.remove(document.model);
    _userLanguage.remove(key);
    _version++;
    return document.announced ? document.uri : null;
  }

  /// The language id of the open document [key], if it is known.
  String? languageIdOf(String key) =>
      _byKey[key]?.mirror.languageId ?? _userLanguage[key];

  /// The user changed [key]'s language id
  /// (`MainThreadLanguages.$changeLanguage`).
  void changeLanguage(String key, String languageId) {
    _userLanguage[key] = languageId;
    final document = _byKey[key];
    if (document == null) return;
    document.mirror.languageId = languageId;
    _version++;
    notifyListeners();
  }

  /// Applies the app's raw text changes to [document]'s mirror, giving the
  /// event to send as `$acceptModelChanged`.
  ModelChangedEvent? acceptModelChanges(
    OpenDocument document,
    Iterable<RawContentChange> changes, {
    bool isUndoing = false,
    bool isRedoing = false,
  }) {
    final event = document.mirror.acceptRawChanges(
      changes,
      isUndoing: isUndoing,
      isRedoing: isRedoing,
    );
    if (event != null) _version++;
    return event;
  }

  void markSaveStarted(OpenDocument document) {}

  /// The document was saved: `$acceptModelSaved` (and the dirty state).
  void markSaved(OpenDocument document) {
    if (!document.isDirty) return;
    document.isDirty = false;
    _version++;
  }

  void markDirty(OpenDocument document, bool isDirty) {
    if (document.isDirty == isDirty) return;
    document.isDirty = isDirty;
    _version++;
  }

  void markEncoding(OpenDocument document, String encoding) {
    if (document.encoding == encoding) return;
    document.encoding = encoding;
    _version++;
  }

  /// `shouldSynchronizeModel`: whether a document of this text is synced.
  static bool isSynchronized(OpenDocument document) =>
      document.mirror.isSynchronized;

  // --- LanguageFeatureDocuments

  @override
  LanguageFeatureDocument? documentForPath(String path) =>
      _byKey[path]?.document;

  @override
  LanguageFeatureDocument? documentForUri(VsUri uri) =>
      _byKey[documentKeyOf(uri)]?.document;

  @override
  VsUri uriForPath(String path) =>
      VsUri.file(path, windows: platform.isWindows);

  @override
  String? pathForUri(VsUri uri) {
    if (uri.scheme == 'file') return uri.fsPath(windows: platform.isWindows);
    final key = documentKeyOf(uri);
    return _byKey.containsKey(key) ? key : null;
  }

}
