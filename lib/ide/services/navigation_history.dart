// A workspace's navigation history: Go Back / Go Forward, Go Previous, Go to
// Last Edit Location, the editors by recent use and those closed (Reopen
// Closed Editor), and the files opened lately (Quick Open's).
//
// After VS Code's `HistoryService` and its `EditorNavigationStack`
// (src/vs/workbench/services/history/browser/historyService.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971): where the caret was is
// recorded when another file comes to the front (from the explorer, Quick
// Open, search, a tab, a definition), and when the caret jumps more than
// [NavigationHistoryService.threshold] lines in the same file (upstream
// `TEXT_EDITOR_SELECTION_THRESHOLD`); closer moves only update where it
// is. Entries of files that close go (upstream keeps closed editors; here
// their tabs are gone).

import 'dart:async';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart'
    show EditorContentChangeEvent, EditorDocumentModel;
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../ide_commands.dart';
import '../ide_workspace.dart';
import '../lsp/lsp_protocol.dart';
import '../lsp_ui/lsp_convert.dart';

/// A place in a file the history goes back to.
typedef NavigationEntry = ({String path, LspPosition position});

class NavigationHistoryService extends ChangeNotifier {
  NavigationHistoryService({
    required this.workspace,
    required this._caret,
    required this._open,
    required this._select,
  }) {
    _tellSoon();
  }

  final IdeWorkspace workspace;

  /// Where the active editor's caret is.
  final Position Function() _caret;

  /// Opens a location without recording it (the history's own moves).
  final Future<void> Function(IdeLocation location) _open;

  /// Brings an open editor to the front.
  final Future<void> Function(IdeDocument doc) _select;

  /// Lines a move must span to be a navigation of its own.
  static const threshold = 10;

  /// How many entries Go Back keeps.
  static const capacity = 50;

  final List<NavigationEntry> _back = [];
  final List<NavigationEntry> _forward = [];

  bool get canGoBack => _back.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;

  /// Where the caret was last seen, in which file; null when the active
  /// file's caret was not reported since it came to the front (it is where
  /// the last one reported was: the editor reports changes only).
  NavigationEntry? _here;

  /// The file at the front when [_here] was last reset.
  String? _file;

  /// Set while Go Back / Go Forward moves: that move records nothing.
  bool _navigating = false;

  /// Whether the last Go Back / Go Forward went back (for Go Previous).
  bool _lastWentBack = false;

  /// Where the caret is now, in the active file.
  NavigationEntry? here() {
    final path = workspace.active?.path;
    if (path == null) return null;
    if (_here case final here? when here.path == path) return here;
    final caret = _caret();
    return (
      path: path,
      position: LspPosition(caret.lineNumber - 1, caret.column - 1),
    );
  }

  /// Records [entry] for Go Back, unless it is the last one; a new
  /// navigation drops what Go Forward had.
  void record(NavigationEntry? entry) {
    if (entry == null || _navigating) return;
    _lastWentBack = false;
    if (_back.isEmpty ||
        _back.last.path != entry.path ||
        _back.last.position != entry.position) {
      _back.add(entry);
      if (_back.length > capacity) _back.removeAt(0);
    }
    _forward.clear();
    _changed();
  }

  /// Records where the caret is now, before a jump elsewhere.
  void recordHere() => record(here());

  /// The caret moved to [position] in the active file.
  void caretMoved(Position position) {
    final path = workspace.active?.path;
    if (path == null) return;
    final now = (
      path: path,
      position: LspPosition(position.lineNumber - 1, position.column - 1),
    );
    final before = _here;
    if (before != null &&
        before.path == path &&
        (before.position.line - now.position.line).abs() > threshold) {
      record(before);
    }
    _here = now;
  }

  /// Go Back (⌃-) / Go Forward (⌃⇧-), and the mouse's back and forward
  /// buttons: whether there was somewhere to go.
  bool navigate({required bool back}) {
    final from = back ? _back : _forward;
    final to = back ? _forward : _back;
    if (from.isEmpty) return false;
    final here = this.here();
    if (here != null) to.add(here);
    final entry = from.removeLast();
    _changed();
    _lastWentBack = back;
    _navigating = true;
    unawaited(
      _open(IdeLocation(entry.path, LspRange(entry.position, entry.position)))
          .whenComplete(() {
            // The caret lands after a frame: that move is this navigation's.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _navigating = false;
              _here = entry;
            });
            WidgetsBinding.instance.scheduleFrame();
          }),
    );
    return true;
  }

  /// Go Previous (upstream `goPrevious`): where the last Go Back or Go
  /// Forward came from, else back.
  void goPrevious() {
    final back = !_lastWentBack;
    if ((back ? _back : _forward).isEmpty) return;
    navigate(back: back);
  }

  // --- Edits ---------------------------------------------------------------

  /// Where the last edit of an open file ended (Go to Last Edit Location).
  NavigationEntry? get lastEdit => _lastEdit;
  NavigationEntry? _lastEdit;

  /// The open files' changes, watched for [lastEdit].
  final Map<EditorDocumentModel, StreamSubscription<EditorContentChangeEvent>>
  _editWatches = {};

  /// Go to Last Edit Location.
  void goToLastEdit() {
    final edit = _lastEdit;
    if (edit == null) return;
    record(here());
    unawaited(
      _open(IdeLocation(edit.path, LspRange(edit.position, edit.position))),
    );
  }

  void _watchEdits() {
    final models = {
      for (final doc in workspace.documents)
        if (doc.isFile) doc.model,
    };
    for (final model in _editWatches.keys.toList()) {
      if (!models.contains(model)) {
        unawaited(_editWatches.remove(model)!.cancel());
      }
    }
    for (final model in models) {
      _editWatches[model] ??= model.changes.listen(
        (event) => _edited(model, event),
      );
    }
  }

  void _edited(EditorDocumentModel model, EditorContentChangeEvent event) {
    final change = event.changes.lastOrNull;
    final doc = workspace.documents
        .where((doc) => doc.isFile && identical(doc.model, model))
        .firstOrNull;
    if (change == null || doc == null) return;
    final lines = change.text.split(RegExp(r'\r\n|\r|\n'));
    final hadEdit = _lastEdit != null;
    _lastEdit = (
      path: doc.path,
      position: LspPosition(
        change.startLine + lines.length - 1,
        lines.length == 1
            ? change.startCharacter + change.text.length
            : lines.last.length,
      ),
    );
    if (!hadEdit) notifyListeners();
  }

  // --- Editors -------------------------------------------------------------

  /// The open editors' keys, the most recently active first.
  final IdeRecentList _editors = IdeRecentList();

  /// The files opened, the last first (Quick Open's recent ones).
  final IdeRecentList recentFiles = IdeRecentList();

  /// Open Next / Previous Recently Used Editor's stack and where they are
  /// in it (upstream `recentlyUsedEditorsStack`), while they run.
  List<String>? _recentlyUsedStack;
  int _recentlyUsedIndex = 0;
  bool _navigatingRecentlyUsed = false;

  /// The files of the editors closed, the last last (Reopen Closed
  /// Editor).
  final List<String> _closed = [];

  bool get canReopenClosed => _closed.isNotEmpty;

  /// The open editors, the most recently active first (upstream
  /// `EditorsOrder.MOST_RECENTLY_ACTIVE`), then those never active, the
  /// last opened first.
  List<IdeDocument> editorsByRecentlyUsed() {
    final byKey = {for (final doc in workspace.documents) doc.key: doc};
    return [
      for (final key in _editors.items) ?byKey.remove(key),
      ...byKey.values.toList().reversed,
    ];
  }

  /// Open Next / Previous Recently Used Editor (upstream
  /// `ensureRecentlyUsedStack`): the stack of the editors by recent use,
  /// taken when the first of these runs and kept while they bring its
  /// editors to the front, [next] towards its top.
  void openRecentlyUsed({required bool next}) {
    final stack =
        _recentlyUsedStack ??
        [for (final doc in editorsByRecentlyUsed()) doc.key];
    if (stack.isEmpty) return;
    final index = (_recentlyUsedIndex + (next ? -1 : 1)).clamp(
      0,
      stack.length - 1,
    );
    _recentlyUsedStack = stack;
    _recentlyUsedIndex = index;
    final doc = workspace.documents
        .where((doc) => doc.key == stack[index])
        .firstOrNull;
    if (doc == null) return;
    _navigatingRecentlyUsed = true;
    unawaited(_select(doc).whenComplete(() => _navigatingRecentlyUsed = false));
  }

  /// [doc] closed by the user: Reopen Closed Editor opens it again.
  void editorClosed(IdeDocument doc) {
    if (doc.label != null || doc.isUntitled) return;
    final hadClosed = _closed.isNotEmpty;
    _closed
      ..remove(doc.path)
      ..add(doc.path);
    if (!hadClosed) notifyListeners();
  }

  /// The file Reopen Closed Editor opens: the last closed not open again.
  String? takeClosed() {
    final open = {for (final doc in workspace.documents) doc.path};
    while (_closed.isNotEmpty) {
      final path = _closed.removeLast();
      if (!open.contains(path)) {
        if (_closed.isEmpty) notifyListeners();
        return path;
      }
    }
    notifyListeners();
    return null;
  }

  // --- The workspace -------------------------------------------------------

  /// The open editors changed: the entries of files no longer open go,
  /// and their edits are no longer watched.
  void documentsChanged() {
    _watchEdits();
    final open = {for (final doc in workspace.documents) doc.path};
    bool closed(NavigationEntry entry) => !open.contains(entry.path);
    if (!_back.any(closed) && !_forward.any(closed)) return;
    _back.removeWhere(closed);
    _forward.removeWhere(closed);
    _changed();
  }

  /// [doc] came to the front: where the caret was in the one before is
  /// recorded, if that one is still open.
  void activeChanged(IdeDocument? doc) {
    // Upstream resets the recently used stack when an editor comes to the
    // front otherwise than from it.
    if (!_navigatingRecentlyUsed) {
      _recentlyUsedStack = null;
      _recentlyUsedIndex = 0;
    }
    if (doc == null) return;
    _editors.add(doc.key);
    final path = doc.path;
    final previous = _file;
    final caret = _caret();
    final before =
        _here ??
        (previous == null
            ? null
            : (
                path: previous,
                position: LspPosition(caret.lineNumber - 1, caret.column - 1),
              ));
    if (before != null &&
        before.path != path &&
        workspace.documents.any((doc) => doc.path == before.path)) {
      record(before);
    }
    _file = path;
    _here = null;
    recentFiles.add(path);
  }

  /// Tells the title bar's arrows (see [IdeWorkspace.navigation]) where
  /// Go Back and Go Forward can go now; after the frame, while one builds.
  void _changed() {
    notifyListeners();
    _tellSoon();
  }

  void _tellSoon() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) _tell();
      });
    } else {
      _tell();
    }
  }

  void _tell() =>
      workspace.navigation.value = (back: canGoBack, forward: canGoForward);

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    for (final watch in _editWatches.values) {
      unawaited(watch.cancel());
    }
    _editWatches.clear();
    super.dispose();
  }
}
