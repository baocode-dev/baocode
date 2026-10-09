/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The extension host's view of BaoCode's open documents and editors, kept
// from the app's own state: which documents are open (and which are too
// large to sync), which editors show them, which one is active, and what
// each editor's selections, visible ranges, options and column are.
//
// This is `MainThreadDocumentsAndEditors` and its
// `MainThreadDocumentAndEditorStateComputer` without the services they
// read: the app's [ExtensionDocumentSync] reports the documents and a
// [TextEditorHost] the editors, so the state is the open documents plus
// the host's editor list.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadDocumentsAndEditors.ts
// (`DocumentAndEditorState`, `DocumentAndEditorState.compute`,
// `TextEditorSnapshot`, `_onDelta`, `_toModelAddData`,
// `_toTextEditorAddData`, `_findEditorPosition`, `getEditor`),
// src/vs/workbench/api/browser/mainThreadEditor.ts
// (`MainThreadTextEditorProperties.readFromEditor`/`generateDelta`,
// `MainThreadTextEditor.setSelections`/`setConfiguration`/`applyEdits`/
// `insertSnippet`/`revealRange`/`setDecorations`/`setDecorationsFast`),
// src/vs/workbench/api/browser/mainThreadEditors.ts
// (`handleTextEditorAdded`/`Removed`, `_updateActiveAndVisibleTextEditors`,
// `_getTextEditorPositionData`), and mainThreadDocuments.ts
// (`ModelTracker`, `_shouldHandleFileEvent`).
//
// Deviations:
// - The app has one editor group, so an editor's group id is 0 and its
//   column its index + 1 (the `EditorGroupColumn` conversions are the
//   identity); a tab moved between groups is not moved.
// - Selections and ranges cross between editor coordinates (raw text, with
//   a leading U+FEFF and mixed line breaks) and model coordinates through
//   the document's mirror.
// - Decorations go through bao_editor's [EditorDecorationsController] when
//   [TextEditorUi.decorations] answers one; otherwise they are dropped.
// - Diff information (`$getDiffInformation`) answers an empty list: the
//   app has no quick-diff model in the editor yet.

import 'dart:async';

import 'package:bao_editor/monaco/flutter/editor_decoration_types.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import '../documents/ext_host_document_mirror.dart';
import '../documents/model_changed_event.dart';
import 'document_registry.dart';
import 'editor_ports.dart';
import 'extension_document_sync.dart';

/// `TextEditorRevealType`.
abstract final class TextEditorRevealType {
  static const int defaultReveal = 0;
  static const int inCenter = 1;
  static const int inCenterIfOutsideViewport = 2;
  static const int atTop = 3;
}

/// The state one editor is in, as `MainThreadTextEditorProperties`: what
/// `$acceptDocumentsAndEditorsDelta`'s `addedEditors` and
/// `$acceptEditorPropertiesChanged` carry.
class TextEditorProperties {
  const TextEditorProperties({
    required this.selections,
    required this.options,
    required this.visibleRanges,
  });

  final List<EditorSelectionValue> selections;
  final EditorOptions options;
  final List<Range> visibleRanges;

  /// `_toTextEditorAddData`'s three members.
  Map<String, Object?> toJson() => {
    'options': options.toJson(),
    'selections': [for (final selection in selections) selection.toJson()],
    'visibleRanges': [for (final range in visibleRanges) range.toJson()],
  };
}

/// One editor the extension host knows: its id, the document it shows
/// (which does not change while the id lives) and the app's editor state.
class TextEditorEntry {
  TextEditorEntry({
    required this.id,
    required this.document,
    required this.ui,
  });

  final String id;
  final OpenDocument document;
  final TextEditorUi ui;

  /// What was last sent, for [generateDelta].
  TextEditorProperties? properties;

  /// The tab this editor is in, as the host's tab model names it.
  String? tabId;

  /// `MainThreadTextEditorProperties.readFromEditor`.
  TextEditorProperties readProperties() => TextEditorProperties(
    selections: ui.selections,
    options: ui.options,
    visibleRanges: ui.visibleRanges,
  );

  /// `MainThreadTextEditorProperties.generateDelta`: only what changed,
  /// everything the first time, null when nothing did.
  Map<String, Object?>? generateDelta(
    TextEditorProperties? previous, {
    String? selectionChangeSource,
  }) {
    final current = readProperties();
    final delta = <String, Object?>{};
    if (previous == null ||
        !_selectionsEqual(previous.selections, current.selections)) {
      delta['selections'] = {
        'selections': [for (final s in current.selections) s.toJson()],
        'source': ?selectionChangeSource,
      };
    }
    if (previous == null || !previous.options.equals(current.options)) {
      delta['options'] = current.options.toJson();
    }
    if (previous == null ||
        !_rangesEqual(previous.visibleRanges, current.visibleRanges)) {
      delta['visibleRanges'] = [
        for (final range in current.visibleRanges) range.toJson(),
      ];
    }
    properties = current;
    return delta.isEmpty ? null : delta;
  }

  static bool _selectionsEqual(
    List<EditorSelectionValue> a,
    List<EditorSelectionValue> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!a[i].equals(b[i])) return false;
    }
    return true;
  }

  static bool _rangesEqual(List<Range> a, List<Range> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!a[i].equalsRange(b[i])) return false;
    }
    return true;
  }
}

/// The app's document-change event, bounded here so `bao_editor`'s
/// `isUndoing`/`isRedoing` hooks are visible to callers.
typedef DocumentContentChangeEvent = ({
  int version,
  List<EditorContentChange> changes,
  bool isUndoing,
  bool isRedoing,
});

/// Everything the extension host knows about documents and editors, and
/// every effect `MainThreadDocumentsAndEditors`, `MainThreadDocuments` and
/// `MainThreadTextEditors` produce. The actors forward these; the app
/// drives the input through [ExtensionDocumentSync] and by changing the
/// editors it was given.
final class DocumentsAndEditorsState extends ChangeNotifier
    implements ExtensionDocumentSync {
  DocumentsAndEditorsState({
    required this.documents,
    required this.editors,
    this.decorations,
  }) {
    documents.addListener(_documentsChanged);
    editors.addListener(_editorsChanged);
    _syncEditors();
  }

  /// The open documents.
  final ExtensionDocumentRegistry documents;

  /// The workbench's open editors.
  final TextEditorHost editors;

  /// The workbench's decoration types, when the editors can paint them.
  final EditorDecorationTypeRegistry? decorations;

  final Map<String, TextEditorEntry> _entries = {};

  /// The active editor's id, or null.
  String? activeEditorId;

  bool _disposed = false;

  /// `MainThreadTextEditors.INSTANCE_COUNT`: the id every decoration type
  /// key of this host is prefixed with, so two hosts never collide.
  static int instanceCount = 0;
  final String instanceId = '${++instanceCount}';

  // --- effects

  /// `$acceptDocumentsAndEditorsDelta`'s argument.
  final _deltas = StreamController<Map<String, Object?>>.broadcast(sync: true);

  /// `$acceptEditorPropertiesChanged`'s `(id, props)`.
  final _properties = StreamController<(String, Map<String, Object?>)>.broadcast(
    sync: true,
  );

  /// `$acceptEditorPositionData`'s argument.
  final _positions = StreamController<Map<String, Object?>>.broadcast(sync: true);

  /// `$acceptModelChanged`'s `(document, event, isDirty)`.
  final _modelChanges =
      StreamController<(OpenDocument, ModelChangedEvent, bool)>.broadcast(
        sync: true,
      );

  /// `$acceptDirtyStateChanged`'s `(uri, isDirty)`.
  final _dirtyChanges = StreamController<(VsUri, bool)>.broadcast(sync: true);

  /// `$acceptModelSaved`'s uri.
  final _saved = StreamController<VsUri>.broadcast(sync: true);

  /// `$acceptEncodingChanged`'s `(uri, encoding)`.
  final _encodingChanges = StreamController<(VsUri, String)>.broadcast(
    sync: true,
  );

  /// `$acceptModelLanguageChanged`'s `(uri, languageId)`.
  final _languageChanges = StreamController<(VsUri, String)>.broadcast(
    sync: true,
  );

  Stream<Map<String, Object?>> get deltas => _deltas.stream;
  Stream<(String, Map<String, Object?>)> get propertiesChanged =>
      _properties.stream;
  Stream<Map<String, Object?>> get positionsChanged => _positions.stream;
  Stream<(OpenDocument, ModelChangedEvent, bool)> get modelChanges =>
      _modelChanges.stream;
  Stream<(VsUri, bool)> get dirtyChanges => _dirtyChanges.stream;
  Stream<VsUri> get saved => _saved.stream;
  Stream<(VsUri, String)> get encodingChanges => _encodingChanges.stream;
  Stream<(VsUri, String)> get languageChanges => _languageChanges.stream;

  // --- state

  /// The editors the extension host knows, in the host's order.
  List<TextEditorEntry> get allEditors => [
    for (final id in editors.editorIds) ?_entries[id],
  ];

  TextEditorEntry? editor(String id) => _entries[id];

  OpenDocument? documentOfEditor(String id) => _entries[id]?.document;

  /// `IMainThreadEditorLocator.getIdOfCodeEditor`: the editor showing
  /// [uri]'s document, if one is.
  String? editorIdOfUri(VsUri uri) {
    final key = documentKeyOf(uri);
    for (final entry in _entries.values) {
      if (entry.document.key == key) return entry.id;
    }
    return null;
  }

  /// `IMainThreadEditorLocator.findTextEditorIdFor`.
  String? editorIdForPath(String path) =>
      editors.editorIds
          .where((id) => _entries[id]?.document.key == path)
          .firstOrNull ??
      (documents.contains(path) ? _idForDocumentKey(path) : null);

  String? _idForDocumentKey(String key) {
    for (final entry in _entries.values) {
      if (entry.document.key == key) return entry.id;
    }
    return null;
  }

  // --- ExtensionDocumentSync (the app's reports) ---

  /// The keys of the app's untitled documents (`untitled:Untitled-1`), by
  /// the name the app reports them under.
  final Map<String, String> _untitledKeys = {};

  /// The registry key of the document the app calls [path].
  String _keyOf(String path) => _untitledKeys[path] ?? path;

  @override
  void openDocument(
    String path,
    EditorDocumentModel model, {
    required String text,
    required bool isUntitled,
    required String languageId,
    bool isDirty = false,
    String encoding = 'utf8',
  }) {
    if (_disposed) return;
    final uri = isUntitled ? VsUri('untitled', path: path) : VsUri.file(path);
    if (isUntitled) _untitledKeys[path] = documentKeyOf(uri);
    documents.open(
      _keyOf(path),
      uri: uri,
      text: text,
      model: model,
      languageId: languageId,
      isUntitled: isUntitled,
      isDirty: isDirty,
      encoding: encoding,
    );
    documents.notifyListeners();
  }

  @override
  void changeDocument(
    String path,
    EditorDocumentModel model,
    EditorContentChangeEventLike event,
  ) {
    if (_disposed) return;
    final document = documents[_keyOf(path)];
    if (document == null) return;
    final changed = documents.acceptModelChanges(
      document,
      [for (final change in event.changes) RawContentChange.fromEditor(change)],
      isUndoing: event.isUndoing,
      isRedoing: event.isRedoing,
    );
    // `textFileService.isDirty`: an undo back to the saved text is clean.
    final isDirty = document.isUntitled || model.isDirty;
    if (changed != null) {
      _modelChanges.add((document, changed, isDirty));
    }
    if (document.isDirty != isDirty) {
      documents.markDirty(document, isDirty);
      _dirtyChanges.add((document.uri, isDirty));
    }
    documents.notifyListeners();
  }

  /// A document of another scheme than `file:`/`untitled:` (a
  /// `TextDocumentContentProvider`'s, `git:`…) is open with [text].
  void openResource(
    VsUri uri,
    EditorDocumentModel model, {
    required String text,
    required String languageId,
  }) {
    if (_disposed) return;
    documents.open(
      documentKeyOf(uri),
      uri: uri,
      text: text,
      model: model,
      languageId: languageId,
    );
    documents.notifyListeners();
  }

  /// A new extension host session: it knows nothing yet, so every
  /// document and editor is announced again (upstream's
  /// `MainThreadDocumentsAndEditors` constructor sends the full state).
  void resendAll() {
    if (_disposed) return;
    for (final document in documents.documents) {
      document.announced = false;
    }
    _entries.clear();
    activeEditorId = null;
    _pendingAddedDocuments.clear();
    _pendingRemovedDocuments.clear();
    _pendingAddedEditors.clear();
    _pendingRemovedEditors.clear();
    _deltaHasActiveEditor = false;
    _pendingActiveEditor = null;
    _lastPositions.clear();
    _positionsSent = false;
    _documentsChanged();
  }

  @override
  void saveDocument(String path, EditorDocumentModel model, String text) {
    if (_disposed) return;
    final document = documents[_keyOf(path)];
    if (document == null) return;
    final wasDirty = document.isDirty;
    documents.markSaved(document);
    if (wasDirty) _dirtyChanges.add((document.uri, false));
    _saved.add(document.uri);
    documents.notifyListeners();
  }

  @override
  void dirtyStateChanged(
    String path,
    EditorDocumentModel model,
    bool isDirty,
  ) {
    if (_disposed) return;
    final document = documents[_keyOf(path)];
    if (document == null || document.isDirty == isDirty) return;
    documents.markDirty(document, isDirty);
    _dirtyChanges.add((document.uri, isDirty));
    documents.notifyListeners();
  }

  @override
  void encodingChanged(
    String path,
    EditorDocumentModel model,
    String encoding,
  ) {
    if (_disposed) return;
    final document = documents[_keyOf(path)];
    if (document == null || document.encoding == encoding) return;
    documents.markEncoding(document, encoding);
    _encodingChanges.add((document.uri, encoding));
    documents.notifyListeners();
  }

  @override
  void closeDocument(String path, EditorDocumentModel model) {
    if (_disposed) return;
    final key = _keyOf(path);
    _untitledKeys.remove(path);
    for (final id in _entries.entries
        .where((entry) => entry.value.document.key == key)
        .map((entry) => entry.key)
        .toList()) {
      _dropEditor(id);
    }
    final removed = documents.close(key);
    if (removed != null) _pendingRemovedDocuments.add(removed);
    _flush();
  }

  /// The user (or an extension) changed a document's language mode; the
  /// language changed, so the extension host is told.
  void languageChanged(String path, String languageId) {
    final document = documents[path];
    if (document == null) return;
    documents.changeLanguage(path, languageId);
    _languageChanges.add((document.uri, languageId));
  }

  // --- editor tracking

  void _documentsChanged() {
    if (_disposed) return;
    for (final document in documents.documents) {
      if (document.announced || !document.mirror.isSynchronized) continue;
      document.announced = true;
      _pendingAddedDocuments.add(document);
    }
    _syncEditors();
    _flush();
  }

  void _editorsChanged() {
    if (_disposed) return;
    _syncEditors();
    _flush();
  }

  /// `_updateState`: [_entries] against the host's editors and the open
  /// documents.
  void _syncEditors() {
    if (_disposed) return;
    final ids = editors.editorIds.toSet();
    for (final id in _entries.keys.toList()) {
      final entry = _entries[id]!;
      if (!ids.contains(id) ||
          !identical(editors.uiOf(id), entry.ui) ||
          !documents.contains(entry.document.key)) {
        _dropEditor(id);
      }
    }
    for (final id in editors.editorIds) {
      if (_entries.containsKey(id)) continue;
      final ui = editors.uiOf(id);
      final path = editors.pathOfEditor(id);
      if (ui == null || path == null) continue;
      final document = documents[_keyOf(path)];
      if (document == null || !document.mirror.isSynchronized) continue;
      _entries[id] = TextEditorEntry(id: id, document: document, ui: ui)
        ..tabId = _tabIdFor(document, id);
      _pendingAddedEditors.add(id);
    }
    final active = editors.activeEditorId;
    final next = active != null && _entries.containsKey(active) ? active : null;
    if (activeEditorId != next) {
      activeEditorId = next;
      _pendingActiveEditor = next;
      _deltaHasActiveEditor = true;
    } else if (_pendingActiveEditor != null &&
        _pendingAddedEditors.contains(_pendingActiveEditor)) {
      _deltaHasActiveEditor = true;
    }
  }

  void _dropEditor(String id) {
    if (_entries.remove(id) == null) return;
    _pendingRemovedEditors.add(id);
  }

  /// The tab id of an editor: the host's own when it has one, else one
  /// derived from the document (a tab model entry the extension can hold).
  String _tabIdFor(OpenDocument document, String editorId) {
    for (final tab in _tabsSource?.tabs ?? const <EditorTabInfo>[]) {
      if (tab.path == document.key) return tab.tabId;
    }
    return '${document.key}\u0000$editorId';
  }

  /// The tab strip, when the app has one ([attachTabs]).
  EditorTabsHost? _tabsSource;

  void attachTabs(EditorTabsHost? tabs) {
    if (identical(_tabsSource, tabs)) return;
    _tabsSource?.removeListener(_editorsChanged);
    _tabsSource = tabs;
    tabs?.addListener(_editorsChanged);
  }

  EditorTabsHost? get tabs => _tabsSource;

  // --- deltas

  final List<OpenDocument> _pendingAddedDocuments = [];
  final List<VsUri> _pendingRemovedDocuments = [];
  final List<String> _pendingAddedEditors = [];
  final List<String> _pendingRemovedEditors = [];
  bool _deltaHasActiveEditor = false;
  String? _pendingActiveEditor;

  /// `MainThreadDocumentsAndEditors._onDelta`, building the DTO
  /// `$acceptDocumentsAndEditorsDelta` takes.
  void _flush() {
    if (_disposed) return;
    if (_pendingAddedDocuments.isEmpty &&
        _pendingRemovedDocuments.isEmpty &&
        _pendingAddedEditors.isEmpty &&
        _pendingRemovedEditors.isEmpty &&
        !_deltaHasActiveEditor) {
      return;
    }
    final delta = <String, Object?>{};
    var empty = true;
    if (_deltaHasActiveEditor) {
      empty = false;
      delta['newActiveEditor'] = _pendingActiveEditor ?? rpcUndefined;
    }
    if (_pendingRemovedDocuments.isNotEmpty) {
      empty = false;
      delta['removedDocuments'] = [
        for (final uri in _pendingRemovedDocuments) uri.toJson(),
      ];
    }
    if (_pendingRemovedEditors.isNotEmpty) {
      empty = false;
      delta['removedEditors'] = List.of(_pendingRemovedEditors);
    }
    if (_pendingAddedDocuments.isNotEmpty) {
      empty = false;
      delta['addedDocuments'] = [
        for (final document in _pendingAddedDocuments)
          document.toModelAddedData(),
      ];
    }
    if (_pendingAddedEditors.isNotEmpty) {
      empty = false;
      final added = <Map<String, Object?>>[];
      for (final id in _pendingAddedEditors) {
        if (_entries[id] case final entry?) added.add(_toTextEditorAddData(entry));
      }
      delta['addedEditors'] = added;
      for (final id in _pendingAddedEditors) {
        // The first state is part of `addedEditors`; only send the delta
        // when the app's editor answers something else later.
        final entry = _entries[id];
        if (entry != null) entry.properties = entry.readProperties();
      }
    }
    _pendingAddedDocuments.clear();
    _pendingRemovedDocuments.clear();
    _pendingAddedEditors.clear();
    _pendingRemovedEditors.clear();
    _deltaHasActiveEditor = false;
    _pendingActiveEditor = null;
    if (!empty) _deltas.add(delta);
    _sendPositions();
  }

  Map<String, Object?> _toTextEditorAddData(TextEditorEntry entry) => {
    'id': entry.id,
    'documentUri': entry.document.uri.toJson(),
    ...entry.readProperties().toJson(),
    'editorPosition': _columnOf(entry.id) ?? rpcUndefined,
  };

  int? _columnOf(String editorId) {
    final column = editors.columnOf(editorId);
    if (column != null) return column;
    final index = editors.editorIds.indexOf(editorId);
    return index < 0 ? null : index + 1;
  }

  final Map<String, Object?> _lastPositions = {};
  bool _positionsSent = false;

  /// `_updateActiveAndVisibleTextEditors`/`_getTextEditorPositionData`.
  void _sendPositions() {
    if (_disposed) return;
    final data = <String, Object?>{};
    for (final id in editors.editorIds) {
      if (!_entries.containsKey(id)) continue;
      final column = _columnOf(id);
      if (column != null) data[id] = column;
    }
    if (mapEquals(data, _lastPositions)) return;
    _lastPositions
      ..clear()
      ..addAll(data);
    if (_positionsSent || data.isNotEmpty) {
      _positionsSent = true;
      _positions.add(data);
    }
  }

  /// The app's editor moved its carets, scrolled or changed options: send
  /// what changed (`$acceptEditorPropertiesChanged`).
  void editorStateChanged(String editorId, {String? selectionChangeSource}) {
    final entry = _entries[editorId];
    if (entry == null) return;
    final delta = entry.generateDelta(
      entry.properties,
      selectionChangeSource: selectionChangeSource,
    );
    if (delta != null) _properties.add((editorId, delta));
  }

  /// The app's editors changed in a way the host's listeners do not cover
  /// (a tab was added or removed).
  void editorsChanged() => _editorsChanged();

  // --- editor commands (`MainThreadTextEditors`) ---

  /// `MainThreadTextEditor.applyEdits`: [edits] are in model coordinates.
  /// Whether they were applied (the versions match and there is an
  /// editor).
  bool applyEdits(
    String editorId,
    int modelVersionId,
    List<({Range range, String? text})> edits,
    ({bool undoStopBefore, bool undoStopAfter, String? eol}) options,
  ) {
    final entry = _entries[editorId];
    if (entry == null) return false;
    final mirror = entry.document.mirror;
    if (mirror.versionId != modelVersionId) return false;
    entry.ui.applyEdits(
      [
        for (final edit in edits)
          (
            range: mirror.toEditorRange(mirror.validateModelRange(edit.range)),
            text: edit.text,
          ),
      ],
      undoStopBefore: options.undoStopBefore,
      undoStopAfter: options.undoStopAfter,
      eol: options.eol,
    );
    return true;
  }

  /// `MainThreadTextEditor.insertSnippet`: [text] goes at each of
  /// [ranges] (model coordinates). Whether there was an editor at that
  /// version.
  bool insertSnippet(
    String editorId,
    int modelVersionId,
    String text,
    List<Range> ranges, {
    required bool undoStopBefore,
    required bool undoStopAfter,
  }) {
    final entry = _entries[editorId];
    if (entry == null) return false;
    final mirror = entry.document.mirror;
    if (mirror.versionId != modelVersionId) return false;
    entry.ui.insertAtRanges(
      text,
      [for (final range in ranges) mirror.toEditorRange(range)],
      undoStopBefore: undoStopBefore,
      undoStopAfter: undoStopAfter,
    );
    return true;
  }

  /// `MainThreadTextEditor.setSelections`: [selections] are in model
  /// coordinates.
  void setSelections(String editorId, List<EditorSelectionValue> selections) {
    final entry = _entries[editorId];
    if (entry == null) return;
    final mirror = entry.document.mirror;
    entry.ui.setSelections([
      for (final selection in selections)
        _rawSelection(mirror, selection),
    ]);
    editorStateChanged(editorId);
  }

  static EditorSelectionValue _rawSelection(
    ExtHostDocumentMirror mirror,
    EditorSelectionValue selection,
  ) {
    final start = mirror.toEditorPosition(
      Position(selection.anchorLine, selection.anchorColumn),
    );
    final end = mirror.toEditorPosition(
      Position(selection.activeLine, selection.activeColumn),
    );
    return EditorSelectionValue(
      anchorLine: start.lineNumber,
      anchorColumn: start.column,
      activeLine: end.lineNumber,
      activeColumn: end.column,
    );
  }

  /// `MainThreadTextEditor.setConfiguration`.
  void setOptions(
    String editorId, {
    int? tabSize,
    int? indentSize,
    bool? insertSpaces,
    int? cursorStyle,
    int? lineNumbers,
    bool tabSizeAuto = false,
    bool insertSpacesAuto = false,
  }) {
    final entry = _entries[editorId];
    if (entry == null) return;
    entry.ui.updateOptions(
      tabSize: tabSizeAuto ? null : tabSize,
      indentSize: indentSize,
      insertSpaces: insertSpacesAuto ? null : insertSpaces,
      cursorStyle: cursorStyle,
      lineNumbers: lineNumbers,
      detectIndentation: tabSizeAuto || insertSpacesAuto,
    );
    editorStateChanged(editorId);
  }

  /// `MainThreadTextEditor.revealRange`: [range] is in model coordinates.
  void revealRange(String editorId, Range range, int revealType) {
    final entry = _entries[editorId];
    if (entry == null) return;
    entry.ui.revealRange(entry.document.mirror.toEditorRange(range), revealType);
  }

  // --- decorations ---

  /// `$registerTextEditorDecorationType`: `exthost-api-<extension>` is the
  /// key extension's types live under.
  void registerDecorationType(
    String extensionId,
    String key,
    Map<String, Object?> options,
  ) => decorations?.registerDecorationType(
    key,
    DecorationRenderOptions.fromJson(options),
    description: 'exthost-api-$extensionId',
  );

  /// `$removeTextEditorDecorationType`.
  void removeDecorationType(String key) =>
      decorations?.removeDecorationType(key);

  /// `$trySetDecorations`: [decorations] are in editor coordinates.
  void setDecorations(
    String editorId,
    String key,
    List<Map<String, Object?>> decorations,
  ) {
    final controller = _entries[editorId]?.ui.decorations;
    if (controller == null) return;
    final mirror = _entries[editorId]!.document.mirror;
    controller.setDecorations(key, [
      for (final decoration in decorations)
        if (DecorationOptions.fromJson(decoration) case final options?)
          DecorationOptions(
            range: mirror.toEditorRange(options.range),
            hoverMessage: options.hoverMessage,
            renderOptions: options.renderOptions,
          ),
    ]);
  }

  /// `$trySetDecorationsFast`: four numbers per decoration range, in
  /// editor coordinates.
  void setDecorationsFast(String editorId, String key, List<num> ranges) =>
      _entries[editorId]?.ui.decorations?.setDecorationsFast(key, ranges);

  /// The decoration type keys one editor currently paints (for checks).
  Iterable<String> decorationKeysOf(String editorId) =>
      _entries[editorId]?.ui.decorations?.typeKeys ?? const [];

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    documents.removeListener(_documentsChanged);
    editors.removeListener(_editorsChanged);
    _tabsSource?.removeListener(_editorsChanged);
    unawaited(_deltas.close());
    unawaited(_properties.close());
    unawaited(_positions.close());
    unawaited(_modelChanges.close());
    unawaited(_dirtyChanges.close());
    unawaited(_saved.close());
    unawaited(_encodingChanges.close());
    unawaited(_languageChanges.close());
    _entries.clear();
    super.dispose();
  }
}
