// An in-memory workbench for the document/editor tests: the app's editors,
// their tab strip, and the documents they show, without Flutter.

import 'dart:async';

import 'package:bao_editor/monaco/flutter/editor_decoration_types.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/editors/document_registry.dart';
import 'package:baocode/extensions/editors/documents_and_editors_service.dart';
import 'package:baocode/extensions/editors/documents_and_editors.dart';
import 'package:baocode/extensions/editors/editor_ports.dart';
import 'package:baocode/extensions/editors/extension_document_sync.dart';
import 'package:flutter/foundation.dart';

/// One fake editor: its document, carets, visible lines and options.
class FakeTextEditorUi implements TextEditorUi {
  FakeTextEditorUi(this.document);

  @override
  final EditorDocumentModel document;

  List<EditorSelectionValue> _selections = [
    const EditorSelectionValue(
      anchorLine: 1,
      anchorColumn: 1,
      activeLine: 1,
      activeColumn: 1,
    ),
  ];
  List<Range> _visibleRanges = [Range(1, 1, 40, 1)];
  EditorOptions _options = const EditorOptions(
    tabSize: 4,
    indentSize: 4,
    insertSpaces: true,
    cursorStyle: EditorCursorStyle.line,
    lineNumbers: EditorLineNumbers.on,
  );
  bool focused = false;
  bool focusedChanged = false;

  /// What was applied through [applyEdits], for checks.
  final List<({Range range, String? text})> appliedEdits = [];

  /// What [insertAtRanges] inserted.
  final List<({String text, List<Range> ranges})> inserted = [];

  /// What [revealRange] was asked for.
  final List<(Range, int)> revealed = [];

  /// What [updateOptions] was asked for.
  final List<Map<String, Object?>> optionUpdates = [];

  EditorDecorationsController? _decorations;

  /// The decorations this editor paints, if the test made a registry.
  set decorationTypes(EditorDecorationTypeRegistry registry) =>
      _decorations = EditorDecorationsController(
        document: document,
        types: registry,
        theme: EditorDecorationTheme(
          isDark: true,
          colors: (id) => null,
        ),
      );

  @override
  EditorDecorationsController? get decorations => _decorations;

  @override
  List<EditorSelectionValue> get selections => _selections;

  set selections(List<EditorSelectionValue> value) => _selections = value;

  @override
  List<Range> get visibleRanges => _visibleRanges;

  set visibleRanges(List<Range> value) => _visibleRanges = value;

  @override
  EditorOptions get options => _options;

  set options(EditorOptions value) => _options = value;

  @override
  bool get isFocused => focused;

  @override
  void setSelections(List<EditorSelectionValue> selections) =>
      _selections = List.of(selections);

  @override
  void applyEdits(
    List<({Range range, String? text})> edits, {
    required bool undoStopBefore,
    required bool undoStopAfter,
    String? eol,
  }) {
    appliedEdits.addAll(edits);
    if (eol != null) {
      document.replaceText(
        document.text.replaceAll(RegExp('\r\n|\r|\n'), eol),
      );
    }
    document.applyEdits([
      for (final edit in edits)
        EditorDocumentEdit(_lift(edit.range), edit.text ?? ''),
    ]);
  }

  @override
  void insertAtRanges(
    String text,
    List<Range> ranges, {
    required bool undoStopBefore,
    required bool undoStopAfter,
  }) {
    inserted.add((text: text, ranges: List.of(ranges)));
    document.applyEdits([
      for (final range in ranges) EditorDocumentEdit(_lift(range), text),
    ]);
  }

  @override
  void revealRange(Range range, int revealType) =>
      revealed.add((_lift(range), revealType));

  @override
  void updateOptions({
    int? tabSize,
    int? indentSize,
    bool? insertSpaces,
    int? cursorStyle,
    int? lineNumbers,
    bool detectIndentation = false,
  }) {
    optionUpdates.add({
      'tabSize': ?tabSize,
      'indentSize': ?indentSize,
      'insertSpaces': ?insertSpaces,
      'cursorStyle': ?cursorStyle,
      'lineNumbers': ?lineNumbers,
      if (detectIndentation) 'detectIndentation': true,
    });
    _options = EditorOptions(
      tabSize: tabSize ?? _options.tabSize,
      indentSize: indentSize ?? _options.indentSize,
      insertSpaces: insertSpaces ?? _options.insertSpaces,
      cursorStyle: cursorStyle ?? _options.cursorStyle,
      lineNumbers: lineNumbers ?? _options.lineNumbers,
    );
  }

  @override
  void focus() {
    focused = true;
    focusedChanged = true;
  }

  @override
  void release() {}

  static Range _lift(IRange range) => Range(
    range.startLineNumber,
    range.startColumn,
    range.endLineNumber,
    range.endColumn,
  );
}

/// One fake tab of the tab strip.
class FakeTab {
  FakeTab({required this.tabId, required this.label, this.path, this.uri});

  String tabId;
  String label;
  String? path;
  VsUri? uri;
  bool isActive = false;
  bool isPinned = false;
  bool isPreview = false;
  bool isDirty = false;
}

/// An in-memory [TextEditorHost] and [EditorTabsHost].
class FakeWorkbench extends ChangeNotifier implements TextEditorHost,
    EditorTabsHost {
  final Map<String, EditorDocumentModel> models = {};
  final Map<String, FakeTextEditorUi> editors = {};
  final Map<String, String> paths = {};
  final List<FakeTab> allTabs = [];
  String? _activeEditorId;
  /// The active tab's id, for the model's activeness.
  String? activeTabId;

  final _operations = StreamController<Map<String, Object?>>.broadcast(
    sync: true,
  );

  /// The bulk edits the app applied (`WorkspaceEditApplier`), if a test
  /// set one up.
  int movedTabs = 0;
  final List<List<String>> closedTabs = [];
  int closedGroups = 0;

  /// The editor states: `ui.documents` by editor id.
  int openedColumn = 1;

  /// Opens an editor for [path] with [text], as the app would when its tab
  /// is selected.
  FakeTextEditorUi openEditor(
    String path, {
    String? text,
    String? tabId,
    String? label,
    bool isDirty = false,
  }) {
    final model = models.putIfAbsent(path, () => EditorDocumentModel(text ?? ''));
    final id = 'editor:$path';
    editors[id] = FakeTextEditorUi(model);
    paths[id] = path;
    allTabs.add(
      FakeTab(
        tabId: tabId ?? path,
        label: label ?? path.split('/').last,
        path: path,
        uri: VsUri.file(path),
      )..isDirty = isDirty,
    );
    selectEditor(id);
    notifyListeners();
    return editors[id]!;
  }

  /// Opens an untitled editor (the app's `Untitled-1` tab).
  FakeTextEditorUi openUntitled(
    String name, {
    String text = '',
    String? tabId,
  }) {
    final model = models.putIfAbsent(name, () => EditorDocumentModel(text));
    final id = 'untitled:$name';
    editors[id] = FakeTextEditorUi(model);
    paths.remove(id);
    allTabs.add(
      FakeTab(tabId: tabId ?? name, label: name, uri: VsUri('untitled', path: name)),
    );
    if (_activeEditorId == null) selectEditor(id);
    notifyListeners();
    return editors[id]!;
  }

  void closeEditor(String id) {
    editors.remove(id);
    paths.remove(id);
    allTabs.removeWhere((tab) => tab.tabId == id.replaceFirst('editor:', ''));
    if (_activeEditorId == id) _activeEditorId = editors.keys.firstOrNull;
    notifyListeners();
  }

  void selectEditor(String id) {
    _activeEditorId = id;
    final tabId = id.replaceFirst('editor:', '');
    for (final tab in allTabs) {
      tab.isActive = tab.tabId == tabId || tab.tabId == id;
      if (tab.isActive) activeTabId = tab.tabId;
    }
    notifyListeners();
  }

  /// The editor's carets moved, as the app reports.
  void reportSelectionChange(String editorId) {
    editors[editorId]?.focusedChanged = true;
    notifyListeners();
  }

  @override
  String? pathOfEditor(String editorId) => paths[editorId];

  @override
  List<String> get editorIds => List.of(editors.keys);

  @override
  String? get activeEditorId => _activeEditorId;

  @override
  TextEditorUi? uiOf(String editorId) => editors[editorId];

  @override
  int? columnOf(String editorId) =>
      editors.containsKey(editorId) ? openedColumn : null;

  @override
  Future<String?> showTextDocument(
    String path, {
    int? column,
    bool preserveFocus = false,
    bool preview = false,
    EditorSelectionValue? selection,
  }) async {
    final existing = editors['editor:$path'];
    if (existing != null) {
      if (!preserveFocus) selectEditor('editor:$path');
      return 'editor:$path';
    }
    openEditor(path, text: models[path]?.text);
    if (!preserveFocus) selectEditor('editor:$path');
    return 'editor:$path';
  }

  @override
  Future<void> showEditor(String editorId, {int? column}) async =>
      selectEditor(editorId);

  @override
  Future<void> hideEditor(String editorId) async => closeEditor(editorId);

  @override
  bool hasTab(String tabId) => allTabs.any((tab) => tab.tabId == tabId);

  @override
  void moveTab(
    String tabId,
    int index, {
    int? column,
    bool? preserveFocus,
  }) {
    final tab = allTabs.where((tab) => tab.tabId == tabId).firstOrNull;
    if (tab == null) return;
    allTabs.remove(tab);
    allTabs.insert(index.clamp(0, allTabs.length), tab);
    movedTabs++;
    notifyListeners();
  }

  @override
  Future<bool> closeTabs(List<String> tabIds, {bool? preserveFocus}) async {
    closedTabs.add(List.of(tabIds));
    for (final tabId in tabIds) {
      final tab = allTabs.where((tab) => tab.tabId == tabId).firstOrNull;
      if (tab == null) continue;
      allTabs.remove(tab);
      editors.remove('editor:${tab.path}');
      paths.remove('editor:${tab.path}');
    }
    notifyListeners();
    return true;
  }

  @override
  Future<bool> closeGroup(int column, {bool? preserveFocus}) async {
    closedGroups++;
    allTabs.clear();
    editors.clear();
    paths.clear();
    _activeEditorId = null;
    notifyListeners();
    return true;
  }

  // `EditorTabsHost`
  @override
  List<EditorTabInfo> get tabs => tabInfoList;

  @override
  List<int> get groupIds => const [0];

  @override
  int get activeGroupId => 0;

  @override
  Stream<Map<String, Object?>> get tabOperations => _operations.stream;

  /// The tabs as [EditorTabsHost] wants them.
  List<EditorTabInfo> get tabInfoList => [
    for (final tab in allTabs)
      EditorTabInfo(
        tabId: tab.tabId,
        isActive: tab.isActive,
        isPinned: tab.isPinned,
        isPreview: tab.isPreview,
        isDirty: tab.isDirty,
        label: tab.label,
        path: tab.path,
        uri: tab.uri,
      ),
  ];

  void fireTabOperation(Map<String, Object?> operation) =>
      _operations.add(operation);

  @override
  void dispose() {
    for (final editor in editors.values) {
      editor.decorations?.dispose();
    }
    unawaited(_operations.close());
    super.dispose();
  }
}

/// A `TextEditorHost`/`EditorTabsHost`/`DocumentsAndEditors` bundle, with
/// the registry the doc/editor tests use.
class FakeDocumentsAndEditors {
  FakeDocumentsAndEditors({
    LanguageIdResolver? languageId,
    bool withDecorations = false,
  }) : workbench = FakeWorkbench() {
    decorations = withDecorations ? EditorDecorationTypeRegistry() : null;
    documents = ExtensionDocumentRegistry();
    service = DocumentsAndEditorsService(
      documents: documents,
      editors: workbench,
      decorations: decorations,
    );
    _languageId = languageId;
  }

  final FakeWorkbench workbench;
  late final ExtensionDocumentRegistry documents;
  late final DocumentsAndEditorsService service;
  EditorDecorationTypeRegistry? decorations;
  LanguageIdResolver? _languageId;

  /// The model changes the workspace forwards to [state], as
  /// `IdeWorkspace._startExtensionSync` does.
  final Map<String, StreamSubscription<EditorContentChangeEvent>> _syncing = {};

  DocumentsAndEditorsState get state => service.state;

  /// Reports a document opening as the app's workspace would, and starts
  /// forwarding its changes (the LSP sync's replacement).
  void open(String path, String text, {String languageId = 'plaintext'}) {
    final model = workbench.models.putIfAbsent(
      path,
      () => EditorDocumentModel(text),
    );
    state.openDocument(
      path,
      model,
      text: text,
      isUntitled: false,
      languageId: _languageId?.call(path) ?? languageId,
    );
    _sync(path, model);
  }

  /// Reports an untitled document opening.
  void openUntitled(String name, String text) {
    final model = workbench.models.putIfAbsent(
      name,
      () => EditorDocumentModel(text),
    );
    state.openDocument(
      name,
      model,
      text: text,
      isUntitled: true,
      languageId: 'plaintext',
    );
    _sync(name, model);
  }

  void _sync(String path, EditorDocumentModel model) {
    _syncing[path] ??= model.changes.listen(
      (event) => state.changeDocument(path, model, (
        version: event.version,
        changes: event.changes,
        isUndoing: event.isUndoing,
        isRedoing: event.isRedoing,
      )),
    );
  }

  /// The document [path]'s model.
  EditorDocumentModel modelOf(String path) => workbench.models[path]!;

  /// Saves [path]'s document, as the app does.
  void save(String path) {
    final model = modelOf(path);
    model.markSaved();
    state.saveDocument(path, model, model.text);
  }

  /// Repopulates [path]'s document from disk, as `IdeWorkspace.reload`
  /// does (the text is replaced and the baseline moves).
  void reload(String path, String text) {
    final model = modelOf(path);
    state.documents[path]!.mirror.reset(text);
    model.replaceText(text);
    model.markSaved();
    state.notifyListeners();
  }

  /// Closes [path]'s document, as the app does when its last tab goes.
  void close(String path) {
    unawaited(_syncing.remove(path)?.cancel());
    state.closeDocument(path, modelOf(path));
  }

  /// The extension host's version of [path]'s document (the mirror's).
  int versionOf(String path) => documents[path]!.mirror.versionId;

  void dispose() {
    for (final subscription in _syncing.values) {
      unawaited(subscription.cancel());
    }
    _syncing.clear();
    service.dispose();
    documents.dispose();
    workbench.dispose();
    decorations?.dispose();
  }
}

/// The language id the app gives a path.
typedef LanguageIdResolver = String Function(String path);

/// Collects the deltas one state sends, for checks.
class DeltaRecorder {
  DeltaRecorder(DocumentsAndEditorsState state) {
    _subscriptions
      ..add(state.deltas.listen(deltas.add))
      ..add(
        state.propertiesChanged.listen(
          (event) => properties.add(event),
        ),
      )
      ..add(state.positionsChanged.listen(positions.add));
  }

  final List<Map<String, Object?>> deltas = [];
  final List<(String, Map<String, Object?>)> properties = [];
  final List<Map<String, Object?>> positions = [];
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// Every `addedDocuments` entry of every delta, in order.
  List<Map<String, Object?>> get addedDocuments => [
    for (final delta in deltas)
      ...?(delta['addedDocuments'] as List?)?.cast<Map<String, Object?>>(),
  ];

  List<Map<String, Object?>> get addedEditors => [
    for (final delta in deltas)
      ...?(delta['addedEditors'] as List?)?.cast<Map<String, Object?>>(),
  ];

  List<Object?> get removedEditors => [
    for (final delta in deltas) ...?(delta['removedEditors'] as List?),
  ];

  List<Object?> get removedDocuments => [
    for (final delta in deltas) ...?(delta['removedDocuments'] as List?),
  ];

  List<Object?> get activeEditors => [
    for (final delta in deltas)
      if (delta.containsKey('newActiveEditor'))
        delta['newActiveEditor'] == rpcUndefined
            ? null
            : delta['newActiveEditor'],
  ];

  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
  }
}

/// An `ExtensionDocumentSync` the tests drive, like the app's workspace.
class RecordingSync implements ExtensionDocumentSync {
  final opened = <String>[];
  final changes = <String>[];
  final saves = <String>[];
  final dirty = <(String, bool)>[];
  final encodings = <(String, String)>[];
  final closes = <String>[];

  @override
  void openDocument(
    String path,
    EditorDocumentModel model, {
    required String text,
    required bool isUntitled,
    required String languageId,
    bool isDirty = false,
    String encoding = 'utf8',
  }) => opened.add(path);

  @override
  void changeDocument(
    String path,
    EditorDocumentModel model,
    EditorContentChangeEventLike event,
  ) => changes.add(path);

  @override
  void saveDocument(String path, EditorDocumentModel model, String text) =>
      saves.add(path);

  @override
  void dirtyStateChanged(
    String path,
    EditorDocumentModel model,
    bool isDirty,
  ) => dirty.add((path, isDirty));

  @override
  void encodingChanged(
    String path,
    EditorDocumentModel model,
    String encoding,
  ) => encodings.add((path, encoding));

  @override
  void closeDocument(String path, EditorDocumentModel model) =>
      closes.add(path);
}
