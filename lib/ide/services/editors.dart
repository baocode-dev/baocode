// The editors as the workbench opens, shows and closes them (upstream
// `IEditorService` over the editor group, editorService.ts): a file opened
// at a place, a tab brought to the front or closed (asking to save it),
// the active one's pane focused and scrolled, and where its caret is. The
// open documents themselves are the workspace's (IdeWorkspace, as
// upstream's `EditorGroupModel`); this is what acts on them.

import 'dart:async';
import 'dart:math' as math;

import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import '../../workspace/window_controls.dart';
import '../save_copy.dart' show saveFileCopyAs;
import '../ide_dialog.dart';
import '../ide_editor.dart';
import '../ide_layout.dart';
import '../ide_tab_bar.dart' show IdeTabAction;
import '../ide_workspace.dart';
import '../lsp/lsp_protocol.dart';
import '../lsp_ui/lsp_convert.dart';
import '../workbench/contributions.dart';
import '../workbench/editor_panes.dart';
import '../workbench/storage.dart';
import 'navigation_history.dart';

class EditorService extends ChangeNotifier
    implements WorkbenchStorageParticipant {
  EditorService({
    required this.host,
    required this.panes,
    required this._workspace,
    required this._layout,
    required this._history,
    required this._focusWorkbench,
    this.onShowEditor,
    this.onViewChanged,
    this.revealInExplorer,
    this.storage,
  });

  final WorkbenchHost host;
  final EditorPaneRegistry panes;

  /// The window's workspace, whose documents these are.
  final IdeWorkspace Function() _workspace;
  final IdeLayout Function() _layout;
  final NavigationHistoryService? Function() _history;

  /// The keyboard to the workbench itself, with no editor to take it.
  final VoidCallback _focusWorkbench;

  /// An editor brought to the front (another tab, an extension's page,
  /// goes behind it).
  final VoidCallback? onShowEditor;

  /// The text editor scrolled, or its caret moved.
  final VoidCallback? onViewChanged;

  /// A tab's file shown in the explorer (Reveal in Explorer View).
  final ValueChanged<String>? revealInExplorer;

  /// Where the editors open, the one in front and each file's view (its
  /// scroll, its caret) are kept with the window.
  final WorkbenchStorage? storage;

  /// The editors kept by the last run opened again, the one in front as
  /// it was; each file's view as it was left.
  @override
  void restoreState(Map<String, Object?> kept) {
    _ws.viewStates.restore(kept['editorViews']);
    final editors = switch (kept['editors']) {
      final List<Object?> paths => paths.whereType<String>().toList(),
      _ => const <String>[],
    };
    if (editors.isEmpty) return;
    final restoring = _ws.restore(editors, active: kept['active'] as String?);
    if (storage case final storage?) {
      storage.holdWhile(restoring);
    } else {
      unawaited(restoring);
    }
  }

  /// Those of files (not a diff's or a revision's, nor an untitled one).
  @override
  void saveState(Map<String, Object?> into) {
    final workspace = _ws;
    final editors = [
      for (final doc in workspace.documents)
        if (doc.label == null && (doc.isFile || doc.isMedia)) doc.path,
    ];
    final active = workspace.active?.key;
    editor?.keepViewStates();
    final paths = workspace.paths;
    final views = workspace.viewStates.toJson(
      (key) => !key.contains('\u0000') && paths.isAbsolute(key),
    );
    into['editors'] = editors;
    if (editors.contains(active)) into['active'] = active;
    if (views.isNotEmpty) into['editorViews'] = views;
  }

  IdeWorkspace get _ws => _workspace();

  /// The text editor, while one shows.
  final editorKey = GlobalKey<IdeEditorState>();
  IdeEditorState? get editor => editorKey.currentState;

  /// Where the text editor's caret is, and how much is selected: the status
  /// bar alone is built again as it moves.
  final caret = ValueNotifier<IdeEditorPosition>((
    position: const Position(1, 1),
    statusColumn: 1,
    selectionLength: 0,
    selectionLines: 0,
  ));
  Position get position => caret.value.position;

  /// Whether an editor is opening (or closing), which another waits for.
  bool get busy => _busy;
  bool _busy = false;

  /// Whether editors are closing: the one in front changing for it brings
  /// none to the front.
  bool get closing => _closing;
  bool _closing = false;

  void _setBusy(bool busy) {
    if (_busy == busy) return;
    _busy = busy;
    if (host.context != null) notifyListeners();
  }

  /// The text editor scrolled, or its caret moved: the window is kept once
  /// it has come to rest, a scroll not written at each frame.
  void viewChanged() {
    onViewChanged?.call();
    final storage = this.storage;
    if (storage == null || !storage.keeps) return;
    _viewTimer?.cancel();
    _viewTimer = Timer(const Duration(seconds: 1), storage.keepSoon);
  }

  Timer? _viewTimer;

  /// The text editor's caret moved.
  void positionChanged(IdeEditorPosition selection) {
    _history()?.caretMoved(selection.position);
    viewChanged();
    final now = caret.value;
    if (host.context != null &&
        (!now.position.equals(selection.position) ||
            now.statusColumn != selection.statusColumn ||
            now.selectionLength != selection.selectionLength ||
            now.selectionLines != selection.selectionLines)) {
      caret.value = selection;
    }
  }

  /// [path] as the explorer and Copy Relative Path have it: relative to
  /// its folder (with the folder's name in a multi-folder workspace).
  String relativePath(String path) {
    final workspace = _ws;
    return workspace.isMultiRoot
        ? workspace.relativePath(path)
        : workspace.paths.relative(path, from: workspace.root);
  }

  /// A tab's context menu's [action] on [doc].
  void tabAction(IdeDocument doc, IdeTabAction action) {
    final docs = _ws.documents;
    switch (action) {
      case IdeTabAction.close:
        unawaited(close(doc));
      case IdeTabAction.closeOthers:
        unawaited(
          closeAll([
            for (final d in docs)
              if (!identical(d, doc)) d,
          ]),
        );
      case IdeTabAction.closeToTheRight:
        unawaited(closeAll(docs.sublist(docs.indexOf(doc) + 1)));
      case IdeTabAction.closeSaved:
        unawaited(
          closeAll([
            for (final d in docs)
              if (!d.dirty) d,
          ]),
        );
      case IdeTabAction.closeAll:
        unawaited(closeAll(docs));
      case IdeTabAction.copyPath:
        unawaited(Clipboard.setData(ClipboardData(text: doc.path)));
      case IdeTabAction.copyRelativePath:
        unawaited(
          Clipboard.setData(ClipboardData(text: relativePath(doc.path))),
        );
      case IdeTabAction.saveAs:
        unawaited(saveAs(doc));
      case IdeTabAction.revealInFileManager:
        unawaited(WindowControls.revealInFileManager(doc.path));
      case IdeTabAction.openInDefaultApp:
        unawaited(host.openInDefaultApp(doc.path));
      case IdeTabAction.revealInExplorer:
        revealInExplorer?.call(doc.path);
    }
  }

  /// The active document's pane but the text editor's, while it shows.
  EditorPaneControl? get _pane => switch (_ws.active) {
    final active? => panes.paneFor(active)?.control?.call(active),
    null => null,
  };

  /// The edits the text editor holds back (a field of the fallback
  /// editor) put in its document.
  Future<void> flush() async {
    await editor?.flush();
  }

  /// The keyboard to the active editor, or its pane.
  void focus() {
    if (editor case final editor?) {
      editor.focus();
    } else {
      _pane?.focus();
    }
  }

  /// The keyboard to the editor if one is open, else to the workbench.
  void focusEditorOrWorkbench() {
    final editor = this.editor;
    if (editor != null && _ws.active != null) {
      editor.focus();
    } else {
      _focusWorkbench();
    }
  }

  /// [line] (one-based) of the active document shown: the caret there in
  /// its editor, or its block at the top of its pane.
  void revealLine(int line, [int column = 1]) {
    if (editor case final editor?) {
      unawaited(editor.revealLine(line, column));
    } else {
      _pane?.revealLine(line, column);
    }
  }

  void revealRange(LspRange range, {bool select = false, bool center = false}) {
    if (editor case final editor?) {
      editor.revealRange(range, select: select, center: center);
    } else {
      _pane?.revealLine(range.start.line + 1);
    }
  }

  /// Runs [action], an editor's opening, once the editor's changes are
  /// written back, telling of a failure. Nothing while another opens.
  Future<void> _whileBusy(Future<void> Function() action) async {
    if (_busy) return;
    _setBusy(true);
    try {
      await flush();
      await action();
    } catch (error) {
      host.report(error);
    } finally {
      _setBusy(false);
    }
  }

  /// Opens [path] in an editor: at [range] (selected where [select], in
  /// the middle where [center]; [afterReveal] once shown) or [line] and
  /// [column], with the keyboard where [focusEditor].
  Future<void> open(
    String path, {
    int? line,
    int? column,
    LspRange? range,
    bool select = false,
    bool center = false,
    bool focusEditor = false,
    VoidCallback? afterReveal,
  }) => _whileBusy(() async {
    await _ws.open(path);
    if (host.context == null) return;
    onShowEditor?.call();
    // The active one opened again changes nothing the workbench follows,
    // but is asked for all the same.
    _layout().showEditor();
    if (line == null && range == null && !focusEditor) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (host.context == null) return;
      if (range != null) {
        revealRange(range, select: select, center: center);
        afterReveal?.call();
      } else if (line != null) {
        revealLine(line, column ?? 1);
      } else {
        focus();
      }
    });
  });

  /// Opens [location] (another file too), recording where the caret was
  /// for Go Back where [record].
  Future<void> openLocation(
    IdeLocation location, {
    bool select = false,
    bool center = false,
    bool record = true,
    VoidCallback? afterReveal,
  }) async {
    if (record) _history()?.recordHere();
    if (_ws.active?.path == location.path) {
      revealRange(location.range, select: select, center: center);
      afterReveal?.call();
      notifyListeners();
      return;
    }
    await open(
      location.path,
      range: location.range,
      select: select,
      center: center,
      focusEditor: true,
      afterReveal: afterReveal,
    );
  }

  /// Runs [open], an editor's opening (a diff's, a revision's); the
  /// keyboard to the editor after where [focusEditor].
  Future<void> openWith(
    Future<void> Function() open, {
    bool focusEditor = false,
  }) => _whileBusy(() async {
    await open();
    if (host.context != null && focusEditor) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (host.context != null) focus();
      });
    }
  });

  /// Brings the open [doc] to the front.
  Future<void> select(IdeDocument doc) => _whileBusy(() async {
    onShowEditor?.call();
    _ws.select(doc.key);
  });

  /// The editor [delta] tabs on from the active one, around the ends.
  void cycle(int delta) {
    final docs = _ws.documents;
    if (docs.length < 2) return;
    final index = docs.indexOf(_ws.active ?? docs.first);
    unawaited(select(docs[(index + delta) % docs.length]));
  }

  /// The editor at [index] (the last for -1, or past the end).
  void openAt(int index) {
    final docs = _ws.documents;
    if (docs.isEmpty) return;
    unawaited(
      select(
        docs[index < 0 ? docs.length - 1 : math.min(index, docs.length - 1)],
      ),
    );
  }

  /// VS Code's save confirmation: Save, Don't Save or Cancel.
  Future<String?> _confirmClose(IdeDocument doc) async {
    final context = host.context;
    if (context == null) return null;
    final l10n = context.l10n;
    final choice = await showIdeDialog(
      context,
      message: l10n.wbConfirmSave(doc.name),
      detail: l10n.explorerChangesLost,
      buttons: [l10n.commonSave, l10n.commonDontSave],
    );
    return switch (choice) {
      0 => 'save',
      1 => 'discard',
      _ => null,
    };
  }

  /// Closes [docs] in order, asking about each unsaved one; Cancel stops.
  Future<void> closeAll(List<IdeDocument> docs) async {
    if (_busy || docs.isEmpty) return;
    _setBusy(true);
    _closing = true;
    final workspace = _ws;
    try {
      await flush();
      for (final doc in docs) {
        if (host.context == null) return;
        if (!workspace.documents.contains(doc)) continue;
        if (doc.dirty) {
          final choice = await _confirmClose(doc);
          if (choice == null || host.context == null) return;
          if (choice == 'save' && doc.isUntitled) {
            // Saved as a file, that is what closes; not saved, nothing.
            final saved = await workspace.saveAs(doc);
            if (saved == null || host.context == null) return;
            workspace.close(saved);
            continue;
          }
          if (choice == 'save') await workspace.save(doc);
        }
        await editor?.closeDocument(doc);
        _history()?.editorClosed(doc);
        workspace.close(doc);
      }
    } catch (error) {
      host.report(error);
    } finally {
      _closing = false;
      _setBusy(false);
      if (host.context != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (host.context != null) focusEditorOrWorkbench();
        });
      }
    }
  }

  Future<void> close(IdeDocument doc) => closeAll([doc]);

  /// Save: the editor's, or the active pane's document.
  Future<void> save() async {
    if (editor case final editor?) return editor.save();
    final doc = _ws.active;
    if (doc == null) return;
    try {
      await _ws.save(doc);
    } catch (error) {
      host.report(error);
    }
  }

  Future<void> saveAll() async {
    try {
      await flush();
      for (final doc in _ws.documents) {
        if (doc.dirty) await _ws.save(doc);
      }
    } catch (error) {
      host.report(error);
    }
  }

  /// Save As: the editor's text ([doc]'s, else the active one's) to a file
  /// asked for, its tab then that file's. A picture's or a file not shown
  /// as text is copied instead.
  Future<void> saveAs([IdeDocument? doc]) async {
    final workspace = _ws;
    doc ??= workspace.active;
    if (doc == null) return;
    try {
      if (!doc.isFile && !doc.isUntitled) {
        await saveFileCopyAs(workspace.files, doc.path);
        return;
      }
      if (identical(doc, workspace.active)) await flush();
      final saved = await workspace.saveAs(doc);
      if (saved != null && host.context != null) host.focusSoon();
    } catch (error) {
      host.report(error);
    }
  }

  /// New Text File: an untitled one, its editor focused.
  void newUntitled() => unawaited(select(_ws.newUntitled()));

  @override
  void dispose() {
    _viewTimer?.cancel();
    caret.dispose();
    super.dispose();
  }
}
