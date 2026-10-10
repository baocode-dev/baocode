// The extension host's documents on an [IdeWorkspace]: opening one without
// a tab (`workspace.openTextDocument`), new untitled ones, saving, the
// virtual documents of `TextDocumentContentProvider`s, and applying a
// `workspace.applyEdit`.
//
// Follows VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadDocuments.ts (`$tryOpenDocument`'s
// scheme switch), mainThreadDocumentContentProviders.ts and
// src/vs/workbench/contrib/bulkEdit/browser/bulkEditService.ts,
// bulkTextEdits.ts (the version check: a document that changed since the
// edit was computed fails it) and bulkFileEdits.ts (create, rename, copy,
// delete and their options).
//
// Deviations:
// - Documents opened without a tab stay open until the workspace closes or
//   [IdeDocumentsPort.trim] lets the oldest clean ones go (upstream's
//   `BoundModelReferenceCollection` keeps them three minutes).
// - A refactoring's `needsConfirmation` edits are applied without the
//   refactoring preview, which BaoCode does not have.
// - A text edit to a file with no tab opens a tab for it, unsaved, so the
//   change can be seen and undone (as BaoCode's own rename does), unless
//   `files.refactoring.autoSave` saves it (a refactoring of several files).

import 'dart:async';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/vs/editor/contrib/snippet/browser/snippet_parser.dart';
import 'package:bao_exthost/bao_exthost.dart' show VsUri;

import '../../ide/file_service.dart';
import '../../ide/ide_workspace.dart';
import '../editors/document_registry.dart';
import '../editors/documents_and_editors.dart';
import '../main_thread/main_thread_bulk_edits.dart';
import '../main_thread/main_thread_document_content_providers.dart';
import '../main_thread/main_thread_documents.dart';

/// [DocumentsPort] and [TextContentProvidersPort] on an [IdeWorkspace].
final class IdeDocumentsPort
    implements DocumentsPort, TextContentProvidersPort {
  IdeDocumentsPort({
    required this.workspace,
    required this.state,
    required this.languageIdFor,
    this.maxBackground = 30,
  });

  final IdeWorkspace workspace;
  final DocumentsAndEditorsState state;

  /// The language id a document of a path or URI opens as.
  final String Function(String path) languageIdFor;

  /// How many documents opened without a tab are kept open.
  final int maxBackground;

  final Map<String, TextContentProvider> _providers = {};

  /// The virtual documents open, by URI string, with their models.
  final Map<String, EditorDocumentModel> _virtual = {};

  @override
  Future<VsUri> openDocument(VsUri uri, {String? encoding}) async {
    switch (uri.scheme) {
      case 'file':
        final path = uri.fsPath();
        await workspace.openBackground(path);
        trim();
        return VsUri.file(workspace.paths.normalize(path));
      case 'untitled':
        final open = workspace.documents.any(
          (d) => d.isUntitled && d.path == uri.path,
        );
        if (!open) throw StateError('No untitled document ${uri.path}');
        return uri;
      default:
        return _openVirtual(uri);
    }
  }

  /// Lets the oldest clean documents opened without a tab go, past
  /// [maxBackground].
  void trim() {
    final paths = workspace.backgroundPaths;
    var excess = paths.length - maxBackground;
    for (final path in paths) {
      if (excess <= 0) break;
      final model = workspace.modelOf(path);
      if (model == null || model.isDirty) continue;
      if (workspace.documents.any((d) => identical(d.model, model))) continue;
      workspace.closeBackground(path);
      excess--;
    }
  }

  Future<VsUri> _openVirtual(VsUri uri) async {
    final key = uri.toString();
    if (_virtual.containsKey(key)) return uri;
    final provider = _providers[uri.scheme];
    if (provider == null) {
      throw StateError('Unable to resolve resource $uri');
    }
    final text = await provider(uri);
    if (text == null) throw StateError('Unable to resolve resource $uri');
    if (_virtual.containsKey(key)) return uri;
    final model = EditorDocumentModel(text);
    _virtual[key] = model;
    state.openResource(
      uri,
      model,
      text: text,
      languageId: languageIdFor(uri.path),
    );
    return uri;
  }

  @override
  Future<VsUri> createUntitled({
    String? languageId,
    String? content,
    String? encoding,
  }) async {
    final doc = workspace.newUntitled();
    if (content != null && content.isNotEmpty) {
      doc.model.applyOffsetEdits([EditorOffsetEdit(0, 0, content)]);
      workspace.notifyDocumentChanged(doc);
    }
    if (languageId != null) state.languageChanged(doc.path, languageId);
    return VsUri('untitled', path: doc.path);
  }

  @override
  Future<bool> saveDocument(VsUri uri) async {
    if (uri.scheme == 'untitled') {
      final doc = workspace.documents
          .where((d) => d.isUntitled && d.path == uri.path)
          .firstOrNull;
      return doc != null && await workspace.saveAs(doc) != null;
    }
    if (uri.scheme != 'file') return false;
    final path = workspace.paths.normalize(uri.fsPath());
    final doc = workspace.documents
        .where((d) => d.isFile && d.path == path)
        .firstOrNull;
    if (doc != null) {
      await workspace.save(doc);
      return true;
    }
    if (workspace.backgroundPaths.contains(path)) {
      await workspace.saveBackground(path);
      return true;
    }
    return false;
  }

  // --- TextContentProvidersPort

  @override
  void Function() register(String scheme, TextContentProvider provide) {
    _providers[scheme] = provide;
    return () {
      if (identical(_providers[scheme], provide)) _providers.remove(scheme);
    };
  }

  /// The text of [uri] from its scheme's content provider (as open, when
  /// it is); null when no provider has the scheme.
  Future<String?> readVirtual(VsUri uri) async {
    if (_virtual[uri.toString()] case final open?) return open.text;
    final provider = _providers[uri.scheme];
    return provider == null ? null : provider(uri);
  }

  @override
  Future<void> updateVirtualDocument(VsUri uri, String value) async {
    final model = _virtual[uri.toString()];
    if (model == null || model.text == value) return;
    model.replaceText(value);
  }

  /// Closes the virtual documents (the session ended).
  void dispose() {
    for (final MapEntry(key: key, value: model) in _virtual.entries) {
      state.closeDocument(key, model);
      model.dispose();
    }
    _virtual.clear();
    _providers.clear();
  }
}

/// `IBulkEditService` on an [IdeWorkspace]: text edits go to the documents'
/// models (through the editor on screen, which maps its carets), file
/// edits to its files.
final class IdeWorkspaceEditApplier implements WorkspaceEditApplier {
  IdeWorkspaceEditApplier({
    required this.workspace,
    required this.state,
    this.refactoringAutoSave = _autoSave,
  });

  final IdeWorkspace workspace;
  final DocumentsAndEditorsState state;

  /// `files.refactoring.autoSave`.
  final bool Function() refactoringAutoSave;

  static bool _autoSave() => true;

  @override
  Future<bool> apply(
    WorkspaceEditDataList edit, {
    int? undoRedoGroupId,
    bool? isRefactoring,
  }) async {
    final textEdits = <String, List<WorkspaceTextEditData>>{};
    final opened = <String>{};
    // `BulkEditService` groups consecutive edits of one kind and runs the
    // groups in order.
    Future<bool> flushText() async {
      if (textEdits.isEmpty) return true;
      final ok = await _applyText(textEdits, opened);
      textEdits.clear();
      return ok;
    }

    for (final entry in edit.edits) {
      switch (entry) {
        case WorkspaceEditText(:final edit):
          (textEdits[documentKeyOf(edit.uri)] ??= []).add(edit);
        case WorkspaceEditFile(:final edit):
          if (!await flushText()) return false;
          if (!await _applyFile(edit)) return false;
      }
    }
    if (!await flushText()) return false;

    // `respectAutoSaveConfig`: a refactoring of several files saves them;
    // otherwise a file the edit opened shows in a tab, unsaved.
    final saveAll =
        (isRefactoring ?? false) && refactoringAutoSave() && opened.length > 1;
    final previous = workspace.active?.key;
    for (final path in opened) {
      if (saveAll) {
        await workspace.saveBackground(path);
      } else if (workspace.modelOf(path)?.isDirty ?? false) {
        await workspace.open(path);
      }
    }
    if (!saveAll && previous != null) workspace.select(previous);
    return true;
  }

  Future<bool> _applyText(
    Map<String, List<WorkspaceTextEditData>> byKey,
    Set<String> opened,
  ) async {
    final planned =
        <(String, EditorDocumentModel, List<EditorOffsetEdit>, String?)>[];
    for (final MapEntry(key: key, value: edits) in byKey.entries) {
      final uri = edits.first.uri;
      EditorDocumentModel? model;
      String? path;
      if (uri.scheme == 'file') {
        path = workspace.paths.normalize(uri.fsPath());
        model = workspace.modelOf(path);
        if (model == null) {
          try {
            model = await workspace.openBackground(path);
          } on IdeFileNotFoundException {
            return false;
          }
          opened.add(path);
        }
      } else if (uri.scheme == 'untitled') {
        model = workspace.documents
            .where((d) => d.isUntitled && d.path == uri.path)
            .firstOrNull
            ?.model;
      }
      if (model == null) return false;
      final document = state.documents[key];
      // `BulkTextEdits._validateBeforePrepare`: the document must be at
      // the version the edit was computed for.
      for (final edit in edits) {
        final version = edit.versionId;
        if (version != null &&
            document != null &&
            document.mirror.versionId != version) {
          return false;
        }
      }
      final snapshot = model.snapshot;
      final offsets = <EditorOffsetEdit>[];
      String? snippet;
      for (final edit in edits) {
        final range = document == null
            ? edit.range
            : document.mirror.toEditorRange(
                document.mirror.validateModelRange(edit.range),
              );
        final start = snapshot.offsetAtPosition(range.getStartPosition());
        final end = snapshot.offsetAtPosition(range.getEndPosition());
        if (edit.insertAsSnippet && edits.length == 1) {
          snippet = edit.text;
          offsets.add(EditorOffsetEdit(start, end, ''));
          continue;
        }
        offsets.add(
          EditorOffsetEdit(
            start,
            end,
            edit.insertAsSnippet
                ? SnippetParser.asInsertText(edit.text)
                : edit.text,
          ),
        );
      }
      planned.add((path ?? key, model, offsets, snippet));
    }
    for (final (path, model, offsets, snippet) in planned) {
      _applyTo(path, model, offsets, snippet);
    }
    return true;
  }

  /// Edits in [model]'s own coordinates (a save participant's), through
  /// the editor on screen when it shows [model].
  void applyEditorEdits(
    String path,
    EditorDocumentModel model,
    List<EditorOffsetEdit> offsets,
  ) => _applyTo(path, model, offsets, null);

  void _applyTo(
    String path,
    EditorDocumentModel model,
    List<EditorOffsetEdit> offsets,
    String? snippet,
  ) {
    final view = workspace.editorViews.active;
    if (view != null && identical(view.controller.document, model)) {
      final controller = view.controller;
      if (snippet != null && offsets.length == 1) {
        final edit = offsets.single;
        controller.select(edit.start, edit.end);
        controller.insertSnippet(snippet);
        return;
      }
      try {
        controller.applyEdits(offsets);
      } on StateError {
        // Overlapping edits: none applied.
      }
      return;
    }
    model.closeUndoGroup();
    try {
      model.applyOffsetEdits(offsets);
    } on StateError {
      return;
    }
    model.closeUndoGroup();
    for (final doc in workspace.documents) {
      if (identical(doc.model, model)) {
        workspace.notifyDocumentChanged(doc);
        break;
      }
    }
  }

  Future<bool> _applyFile(WorkspaceFileEditData edit) async {
    final files = workspace.files;
    String pathOf(VsUri uri) => workspace.paths.normalize(uri.fsPath());
    try {
      if (edit.isCreate) {
        final path = pathOf(edit.newResource!);
        try {
          await files.create(path, directory: edit.folder);
        } on IdeFileExistsException {
          if (edit.ignoreIfExists) return true;
          if (!edit.overwrite) return false;
        }
        if (edit.contents case final contents?) {
          await files.writeBytes(path, contents);
        } else if (edit.overwrite && !edit.folder) {
          await files.write(path, '');
        }
        return true;
      }
      if (edit.isRename) {
        final from = pathOf(edit.oldResource!);
        final to = pathOf(edit.newResource!);
        if (edit.copy) {
          await files.copy(from, to);
        } else {
          await files.rename(from, to);
          workspace.moved(from, to);
        }
        return true;
      }
      if (edit.isDelete) {
        final path = pathOf(edit.oldResource!);
        try {
          await files.delete(path);
        } on IdeFileNotFoundException {
          if (!edit.ignoreIfNotExists) return false;
        }
        workspace.deleted(path);
        return true;
      }
    } on IdeFileExistsException {
      return edit.ignoreIfExists;
    } on Object {
      return false;
    }
    return true;
  }
}
