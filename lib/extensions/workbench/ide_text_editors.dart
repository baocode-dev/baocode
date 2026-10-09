// The extension host's editors and tabs on the IDE's: [TextEditorHost] and
// [EditorTabsHost] over an [IdeWorkspace] and its [IdeEditorViews], and
// [TextEditorUi] over an editor view's controller.
//
// BaoCode shows one editor group, so the extension host sees one visible
// text editor at most: the one on screen (`window.visibleTextEditors`), also
// the active one. Its id lasts as long as the view (the document's
// controller) does.

import 'dart:async';

import 'package:bao_editor/monaco/flutter/editor_decoration_types.dart'
    show EditorDecorationsController;
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show TextSelection;

import '../../ide/ide_editor_views.dart';
import '../../ide/ide_status_bar.dart' show ideEolEdits;
import '../../ide/ide_workspace.dart';
import '../editors/documents_and_editors.dart' show TextEditorRevealType;
import '../editors/editor_ports.dart';
import '../main_thread/main_thread_editor_tabs.dart';

/// The IDE's editors and tab strip, as the extension host's actors use
/// them.
final class IdeTextEditors extends ChangeNotifier
    implements TextEditorHost, EditorTabsHost {
  IdeTextEditors(
    this.workspace, {
    this.showTimeout = const Duration(seconds: 5),
  }) {
    workspace.editorViews.addListener(_viewsChanged);
    _viewChanges = workspace.editorViews.changes.listen(_viewChanged);
    workspace.addListener(_workspaceChanged);
    _tabs = _readTabs();
  }

  /// The editor on screen moved its carets, scrolled or changed options
  /// (`MainThreadTextEditor`'s `onPropertiesChanged`): its id.
  void Function(String editorId)? onEditorStateChanged;

  late final StreamSubscription<IdeEditorView> _viewChanges;

  void _viewChanged(IdeEditorView view) {
    if (_disposed || !identical(view, _shown)) return;
    onEditorStateChanged?.call(idOf(view));
  }

  final IdeWorkspace workspace;

  /// How long [showTextDocument] waits for the editor to show.
  final Duration showTimeout;

  final Expando<String> _ids = Expando('editor id');
  final Map<String, IdeEditorView> _views = {};
  final Map<String, IdeTextEditorUi> _uis = {};
  int _nextId = 0;
  bool _disposed = false;

  /// The id the extension host knows [view] by.
  String idOf(IdeEditorView view) {
    if (_ids[view] case final id?) return id;
    final id = 'ide-editor-${++_nextId}';
    _ids[view] = id;
    _views[id] = view;
    return id;
  }

  /// The view of [editorId], while it is on screen.
  IdeEditorView? viewOf(String editorId) {
    final view = _views[editorId];
    return view != null && identical(view, _shown) ? view : null;
  }

  /// The editor on screen, when it shows a document the extension host
  /// has: a file's (or its diff's modified side), or a new file's.
  IdeEditorView? get _shown {
    final view = workspace.editorViews.active;
    if (view == null) return null;
    final doc = view.document;
    if (!workspace.documents.contains(doc)) return null;
    if (doc.readRevision != null || doc.isMedia || doc.openError != null) {
      return null;
    }
    return view;
  }

  void _viewsChanged() {
    if (_disposed) return;
    final shown = _shown;
    for (final id in _views.keys.toList()) {
      if (!identical(_views[id], shown)) {
        _views.remove(id);
        _uis.remove(id);
      }
    }
    _waiters.removeWhere((waiter) => waiter());
    notifyListeners();
  }

  // --- TextEditorHost

  @override
  List<String> get editorIds => switch (_shown) {
    final view? => [idOf(view)],
    null => const [],
  };

  @override
  String? get activeEditorId => editorIds.firstOrNull;

  @override
  String? pathOfEditor(String editorId) => viewOf(editorId)?.document.path;

  @override
  TextEditorUi? uiOf(String editorId) {
    final view = viewOf(editorId);
    if (view == null) return null;
    return _uis[editorId] ??= IdeTextEditorUi(view);
  }

  @override
  int? columnOf(String editorId) => viewOf(editorId) == null ? null : 1;

  /// Callbacks waiting for an editor to show: each answers whether it is
  /// done.
  final List<bool Function()> _waiters = [];

  @override
  Future<String?> showTextDocument(
    String path, {
    int? column,
    bool preserveFocus = false,
    bool preview = false,
    EditorSelectionValue? selection,
  }) async {
    if (workspace.documents.any((d) => d.isUntitled && d.path == path)) {
      workspace.select(path);
    } else {
      await workspace.open(path);
    }
    final view = await _waitForView(
      (view) =>
          view.document.path == path ||
          workspace.paths.equals(view.document.path, path),
    );
    if (view == null) return null;
    final id = idOf(view);
    if (selection != null) uiOf(id)?.setSelections([selection]);
    if (!preserveFocus) view.focus();
    return id;
  }

  Future<IdeEditorView?> _waitForView(bool Function(IdeEditorView) test) {
    if (_shown case final view? when test(view)) return Future.value(view);
    final completer = Completer<IdeEditorView?>();
    bool check() {
      if (completer.isCompleted) return true;
      if (_shown case final view? when test(view)) {
        completer.complete(view);
        return true;
      }
      return false;
    }

    _waiters.add(check);
    return completer.future.timeout(
      showTimeout,
      onTimeout: () {
        _waiters.remove(check);
        return null;
      },
    );
  }

  @override
  Future<void> showEditor(String editorId, {int? column}) async {
    final view = _views[editorId];
    if (view == null) return;
    workspace.select(view.document.key);
  }

  @override
  Future<void> hideEditor(String editorId) async {
    final view = _views[editorId];
    if (view == null) return;
    workspace.close(view.document);
  }

  // --- EditorTabsHost

  List<EditorTabInfo> _tabs = const [];
  final _operations = StreamController<Map<String, Object?>>.broadcast(
    sync: true,
  );

  @override
  List<EditorTabInfo> get tabs => _tabs;

  @override
  List<int> get groupIds => const [0];

  @override
  int get activeGroupId => 0;

  @override
  Stream<Map<String, Object?>> get tabOperations => _operations.stream;

  @override
  bool hasTab(String tabId) => _tabs.any((tab) => tab.tabId == tabId);

  List<EditorTabInfo> _readTabs() {
    final active = workspace.active;
    return [for (final doc in workspace.documents) _tabOf(doc, active: active)];
  }

  EditorTabInfo _tabOf(IdeDocument doc, {IdeDocument? active}) {
    final uri = doc.isUntitled
        ? VsUri('untitled', path: doc.path)
        : VsUri.file(doc.path);
    final text = doc.isUntitled || (doc.isFile && doc.diff == null);
    return EditorTabInfo(
      tabId: doc.key,
      isActive: identical(doc, active),
      isPinned: false,
      isPreview: false,
      isDirty: doc.dirty,
      label: doc.title,
      path: text ? doc.path : null,
      uri: text ? uri : null,
      // A diff of the file against a revision: the revision has no
      // resource of its own here.
      modifiedUri: doc.diff != null ? uri : null,
      originalUri: doc.diff != null
          ? VsUri('git', path: doc.path, query: doc.label ?? '')
          : null,
    );
  }

  void _workspaceChanged() {
    if (_disposed) return;
    final before = _tabs;
    final after = _readTabs();
    _tabs = after;
    final beforeIds = [for (final tab in before) tab.tabId];
    final afterIds = [for (final tab in after) tab.tabId];
    // Closed, then opened, then the ones whose state changed
    // (`_updateTabsModel`'s operations).
    for (var i = before.length - 1; i >= 0; i--) {
      if (afterIds.contains(before[i].tabId)) continue;
      _operations.add({
        'groupId': 0,
        'kind': TabModelOperationKind.tabClose,
        'index': i,
        'tabDto': editorTabDto(before[i]),
      });
    }
    for (var i = 0; i < after.length; i++) {
      final tab = after[i];
      final index = beforeIds.indexOf(tab.tabId);
      if (index < 0) {
        _operations.add({
          'groupId': 0,
          'kind': TabModelOperationKind.tabOpen,
          'index': i,
          'tabDto': editorTabDto(tab),
        });
        continue;
      }
      final old = before[index];
      if (old.isActive != tab.isActive ||
          old.isDirty != tab.isDirty ||
          old.label != tab.label) {
        _operations.add({
          'groupId': 0,
          'kind': TabModelOperationKind.tabUpdate,
          'index': i,
          'tabDto': editorTabDto(tab),
        });
      }
    }
    _viewsChanged();
  }

  @override
  void moveTab(String tabId, int index, {int? column, bool? preserveFocus}) {
    // BaoCode's tab strip has no programmatic reorder; the tab stays.
  }

  @override
  Future<bool> closeTabs(List<String> tabIds, {bool? preserveFocus}) async {
    for (final tabId in tabIds) {
      final doc = workspace.documents.where((d) => d.key == tabId).firstOrNull;
      if (doc == null) return false;
      workspace.close(doc);
    }
    return true;
  }

  @override
  Future<bool> closeGroup(int column, {bool? preserveFocus}) async {
    for (final doc in workspace.documents.toList()) {
      workspace.close(doc);
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    workspace.editorViews.removeListener(_viewsChanged);
    unawaited(_viewChanges.cancel());
    workspace.removeListener(_workspaceChanged);
    for (final waiter in _waiters) {
      waiter();
    }
    _waiters.clear();
    unawaited(_operations.close());
    super.dispose();
  }
}

/// One IDE editor as the extension host's actors drive it, in editor
/// coordinates (one-based, over the model's raw text).
final class IdeTextEditorUi implements TextEditorUi {
  IdeTextEditorUi(this.view);

  final IdeEditorView view;

  /// The cursor style and line numbers an extension set; the editor paints
  /// its own (a line caret, line numbers on).
  int _cursorStyle = EditorCursorStyle.line;
  int _lineNumbers = EditorLineNumbers.on;

  @override
  EditorDocumentModel get document => view.controller.document;

  @override
  List<EditorSelectionValue> get selections {
    final snapshot = document.snapshot;
    return [
      for (final selection in view.controller.selections)
        _value(
          snapshot.positionAtOffset(selection.baseOffset),
          snapshot.positionAtOffset(selection.extentOffset),
        ),
    ];
  }

  static EditorSelectionValue _value(Position anchor, Position active) =>
      EditorSelectionValue(
        anchorLine: anchor.lineNumber,
        anchorColumn: anchor.column,
        activeLine: active.lineNumber,
        activeColumn: active.column,
      );

  @override
  List<Range> get visibleRanges {
    final lines = view.visibleLines();
    if (lines == null) return const [];
    final snapshot = document.snapshot;
    final last = lines.last.clamp(1, snapshot.lineCount);
    final end = snapshot.contentEnds[last - 1] - snapshot.lineStarts[last - 1];
    return [Range(lines.first, 1, last, end + 1)];
  }

  @override
  EditorOptions get options => EditorOptions(
    tabSize: view.controller.tabSize,
    indentSize: view.controller.tabSize,
    insertSpaces: view.controller.insertSpaces,
    cursorStyle: _cursorStyle,
    lineNumbers: _lineNumbers,
  );

  @override
  bool get isFocused => view.hasFocus();

  int _offset(int line, int column) =>
      document.offsetAtPosition(Position(line, column));

  @override
  void setSelections(List<EditorSelectionValue> selections) {
    if (selections.isEmpty) return;
    view.controller.setSelections([
      for (final selection in selections)
        TextSelection(
          baseOffset: _offset(selection.anchorLine, selection.anchorColumn),
          extentOffset: _offset(selection.activeLine, selection.activeColumn),
        ),
    ]);
  }

  @override
  void applyEdits(
    List<({Range range, String? text})> edits, {
    required bool undoStopBefore,
    required bool undoStopAfter,
    String? eol,
  }) {
    if (undoStopBefore) document.closeUndoGroup();
    if (eol != null) {
      final eolEdits = ideEolEdits(document.snapshot, eol);
      if (eolEdits.isNotEmpty) view.controller.applyEdits(eolEdits);
    }
    final offsets = [
      for (final edit in edits)
        EditorOffsetEdit(
          _offset(edit.range.startLineNumber, edit.range.startColumn),
          _offset(edit.range.endLineNumber, edit.range.endColumn),
          edit.text ?? '',
        ),
    ];
    try {
      view.controller.applyEdits(offsets);
    } on StateError {
      // Overlapping ranges: upstream's `executeEdits` rejects them too.
    }
    if (undoStopAfter) document.closeUndoGroup();
  }

  @override
  void insertAtRanges(
    String text,
    List<Range> ranges, {
    required bool undoStopBefore,
    required bool undoStopAfter,
  }) {
    if (ranges.isEmpty) return;
    view.controller.setSelections([
      for (final range in ranges)
        TextSelection(
          baseOffset: _offset(range.startLineNumber, range.startColumn),
          extentOffset: _offset(range.endLineNumber, range.endColumn),
        ),
    ]);
    view.controller.insertSnippet(text, undoStopBefore: undoStopBefore);
    if (undoStopAfter) document.closeUndoGroup();
  }

  @override
  void revealRange(Range range, int revealType) {
    final start = _offset(range.startLineNumber, range.startColumn);
    final end = _offset(range.endLineNumber, range.endColumn);
    view.reveal(
      start,
      end,
      center:
          revealType == TextEditorRevealType.inCenter ||
          revealType == TextEditorRevealType.inCenterIfOutsideViewport,
    );
  }

  @override
  void updateOptions({
    int? tabSize,
    int? indentSize,
    bool? insertSpaces,
    int? cursorStyle,
    int? lineNumbers,
    bool detectIndentation = false,
  }) {
    final controller = view.controller;
    if (detectIndentation) controller.detectIndentation();
    if (tabSize != null) controller.tabSize = tabSize;
    if (insertSpaces != null) controller.insertSpaces = insertSpaces;
    if (cursorStyle != null) _cursorStyle = cursorStyle;
    if (lineNumbers != null) _lineNumbers = lineNumbers;
  }

  @override
  void focus() => view.focus();

  @override
  EditorDecorationsController? get decorations => view.features.decorations;

  @override
  void release() {}
}
