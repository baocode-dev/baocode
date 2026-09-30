import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../theme/codicons.dart';
import '../theme/cursor_theme.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/back_to_chat_button.dart';
import '../workspace/editor_launcher.dart';
import '../workspace/pin_window_button.dart';
import '../workspace/title_bar_double_click.dart';
import '../workspace/window_controls.dart';
import '../workspace/workspace.dart';
import 'editor/monaco/flutter/document_snapshot.dart';
import 'editor/monaco/vs/editor/common/core/position.dart';
import 'editor/monaco/vs/editor/contrib/gotoError/browser/marker_navigation.dart';
import 'extensions/ide_extensions.dart';
import 'extensions/ide_extensions_view.dart';
import 'git/commit_message.dart';
import 'git/git_repository.dart';
import 'git/ide_scm_view.dart';
import 'git/ide_timeline_view.dart';
import 'ide_breadcrumbs.dart';
import 'ide_color_theme_picker.dart';
import 'ide_columns.dart';
import 'ide_rows.dart';
import 'ide_commands.dart';
import 'ide_dialog.dart';
import 'ide_editor.dart';
import 'ide_editor_placeholder.dart';
import 'ide_explorer.dart';
import 'ide_hover.dart';
import 'ide_layout.dart';
import 'ide_modern_ui.dart';
import 'ide_notifications.dart';
import 'ide_panes.dart';
import 'ide_quick_input.dart';
import 'ide_quick_open.dart';
import 'ide_status_bar.dart';
import 'ide_tab_bar.dart';
import 'ide_welcome.dart';
import 'ide_workspace.dart';
import 'lsp/language_features.dart';
import 'lsp/lsp_protocol.dart';
import 'lsp_ui/diagnostics.dart';
import 'lsp_ui/document_symbols.dart';
import 'lsp_ui/language_status.dart';
import 'lsp_ui/lsp_convert.dart';
import 'lsp_ui/problems_panel.dart';
import 'lsp_ui/workspace_edit.dart';
import 'project_tools.dart';
import 'search/ide_search_view.dart';
import 'search/text_search.dart';
import 'terminal/links/terminal_links.dart';
import 'terminal/terminal_instance.dart';
import 'terminal/terminal_panel.dart';
import 'terminal/terminal_service.dart';
import 'terminal/terminal_tabs.dart';

/// The IDE shell is kept mounted when the user returns to the conversation.
class IdeWorkbench extends StatefulWidget {
  const IdeWorkbench({
    super.key,
    required this.workspace,
    required this.project,
    required this.visible,
    required this.chat,
    required this.onBack,
    this.editorBuilder,
    this.nativeEditorEnabled = const bool.fromEnvironment(
      'MONAD_NATIVE_EDITOR',
      defaultValue: true,
    ),
    this.commands = const [],
    this.ignoredRecommendations = const {},
    this.onIgnoreRecommendation,
    this.textSearch = ideSearchText,
    this.extensions,
    this.commitMessage = ideClaudeCommitMessage,
    this.pinned = false,
    this.onPinnedChanged,
    this.terminalBackend = const TerminalBackend(),
    this.colorThemes,
  });

  final IdeWorkspace workspace;
  final Project project;
  final bool visible;
  final Widget chat;
  final VoidCallback onBack;

  /// Optional editor override for widget tests.
  final Widget Function(BuildContext, IdeWorkspace)? editorBuilder;

  /// Whether the editor uses the painted Monaco surface (see [IdeEditor]).
  final bool nativeEditorEnabled;

  /// Extra commands for the palette, after the workbench's and the editor's.
  final List<IdeCommand> commands;

  /// Language servers not to recommend installing again (Don't Show Again
  /// for this Language Server), kept by [onIgnoreRecommendation].
  final Set<String> ignoredRecommendations;
  final ValueChanged<String>? onIgnoreRecommendation;

  /// The Search view's engine (a fake in widget tests).
  final IdeTextSearch textSearch;

  /// What the Extensions view lists; the standard catalog's language
  /// servers when null.
  final IdeExtensions? extensions;

  /// Writes the Source Control view's commit messages (Claude Haiku; a
  /// fake in widget tests).
  final IdeCommitMessageModel commitMessage;

  /// Whether the window is kept on top of other apps; [onPinnedChanged]
  /// toggles it from the title bar, as the chat's pin does.
  final bool pinned;
  final ValueChanged<bool>? onPinnedChanged;

  /// Where the panel's terminals come from: the user's shell on a pseudo
  /// terminal; fakes in widget tests. Without one (the web), there is no
  /// TERMINAL tab.
  final TerminalBackend terminalBackend;

  /// The color themes Preferences: Color Theme (⌘K ⌘T) picks from; the
  /// command is disabled without them.
  final IdeColorThemeController? colorThemes;

  @override
  State<IdeWorkbench> createState() => IdeWorkbenchState();
}

/// The side views of the activity bar. The outline is a pane of the
/// explorer, as in VS Code; there is no Run and Debug view.
enum IdeSideView { explorer, search, sourceControl, extensions }

/// A navigation history entry (Go Back / Go Forward).
typedef _NavigationEntry = ({String path, LspPosition position});

/// A chord being typed (see [IdeWorkbenchState._chord]).
typedef _Chord = ({
  String label,
  List<({IdeKeybinding binding, VoidCallback run})> candidates,
  String message,
  bool editor,
});

class IdeWorkbenchState extends State<IdeWorkbench> {
  final _editorKey = GlobalKey<IdeEditorState>();
  final FocusNode _workbenchFocus = FocusNode(debugLabel: 'ide workbench');
  final FocusNode _explorerFocus = FocusNode(debugLabel: 'ide explorer');
  late IdeExplorerController _explorer;
  late IdeFileIndex _fileIndex;
  final IdeRecentList _recentFiles = IdeRecentList();
  final IdeRecentList _recentCommands = IdeRecentList();
  final List<String> _closedEditors = [];

  /// The widths the side bar and the chat open at, and have while there is
  /// room (see [IdeColumns.fit]).
  double _chatWidth = IdeColumns.defaultChat;
  double _sidebarWidth = IdeColumns.defaultSidebar;

  /// The widths, and the room for them, when a sash's drag began: it
  /// follows the pointer from there, so what it pushed aside or snapped
  /// shut comes back as it returns. (The room is the start's: the chat
  /// snapped shut takes the window's gap beside it along.)
  ({IdeColumns columns, double room})? _dragStart;

  /// Which parts show: the workspace's, for the window's header to toggle
  /// as well (see [IdeLayout]); [_layoutChanged] follows it.
  IdeLayout get _layout => widget.workspace.layout;
  bool get _sidebarShown => _layout.sidebar;
  set _sidebarShown(bool value) => _layout.sidebar = value;
  bool get _chatShown => _layout.chat;
  set _chatShown(bool value) => _layout.chat = value;

  /// The panel's height below the editor; null is a third of the column
  /// (see [IdeRows]). Whether it shows, and what, is [_panel].
  double? _panelHeight;

  /// The panel's height, and the room for it, when its sash's drag began.
  ({IdeRows rows, double room})? _panelDragStart;
  IdeSideView _view = IdeSideView.explorer;
  final IdeNotifications _notifications = IdeNotifications();

  /// Servers whose install was recommended in this session.
  final Set<String> _recommended = {};
  String _lspStatus = 'Language services';
  Position _caretPosition = const Position(1, 1);
  int _statusColumn = 1;
  int _selectionLength = 0;
  bool _busy = false;
  String? _branch;
  String? _activePath;

  /// The Source Control view's message and state, while other views show.
  IdeScmSession _scm = IdeScmSession();

  /// The explorer's open panes (Folders first, then Outline and Timeline,
  /// collapsed as VS Code starts them), and what the timeline follows.
  final Set<String> _explorerPanes = {'folder'};
  final IdeTimelineController _timeline = IdeTimelineController();
  final _explorerTree = GlobalKey<IdeExplorerState>();

  /// The Search view's inputs and results, while other views show.
  late final IdeSearchSession _search = IdeSearchSession(
    engine: widget.textSearch,
  );
  IdeGitRepository? _git;

  /// The Extensions view's list and search, made when it first shows.
  IdeExtensionsSession? _extensions;

  /// What the activity bar and the status bar show of [_git], rebuilt
  /// only when these change.
  int _gitCount = 0;
  String? _gitBranch;

  /// The quick input's text while it is open (its prefix picks the mode).
  String? _quickInput;

  /// The quick pick the quick input shows instead (e.g. the color themes).
  IdeQuickPick? _quickPick;
  GlobalKey<IdeQuickInputState> _quickInputKey = GlobalKey();
  FocusNode? _focusBeforeQuickInput;

  /// The chord being typed (upstream `_currentChords`): its first key's
  /// label, the keybindings it may complete, its status message, and
  /// whether the editor, which started it, takes the next key.
  _Chord? _chord;
  Timer? _chordChecker;

  /// The status bar's message (upstream `INotificationService.status`),
  /// after the items on the left.
  String? _statusMessage;
  Timer? _statusMessageTimer;

  DocumentSnapshot? _eolSnapshot;
  String _eolLabel = 'LF';

  LanguageFeatures? _languages;
  IdeDocumentSymbols? _symbols;
  StreamSubscription<LspApplyEditRequest>? _editRequests;
  late Listenable _quickRefresh;

  /// The panel's tab, or null when the panel is hidden.
  IdePanelTab? get _panel => _layout.panel;
  set _panel(IdePanelTab? tab) => _layout.panel = tab;

  /// The tab the panel shows again when toggled back.
  IdePanelTab get _lastPanel => _layout.lastPanel;

  /// The panel's tab as [_layoutChanged] last saw it.
  IdePanelTab? _shownPanel;

  /// Around the panel: whether the keyboard is in it.
  final FocusNode _panelFocus = FocusNode(
    debugLabel: 'ide panel',
    canRequestFocus: false,
    skipTraversal: true,
  );

  /// The panel's terminals; none where they cannot run (the web).
  TerminalService? _terminals;
  IdeReferences? _references;
  MarkerList<LspDiagnostic>? _markers;
  final List<_NavigationEntry> _backStack = [];
  final List<_NavigationEntry> _forwardStack = [];
  bool _formatOnSave = false;

  static const _sashWidth = IdeModernUI.gap;

  IdeEditorState? get _editor => _editorKey.currentState;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_onChordKey);
    _notifications.addListener(_notificationsChanged);
    if (widget.terminalBackend.supported) {
      _terminals = TerminalService(
        root: widget.workspace.root,
        backend: widget.terminalBackend,
      )..addListener(_terminalsChanged);
    }
    _attach();
    IdeLanguageNames.ensureLoaded(() {
      if (mounted) setState(() {});
    });
    _readBranch();
    if (widget.visible) _focusSoon();
  }

  void _attach() {
    final workspace = widget.workspace;
    _explorer = IdeExplorerController(
      files: workspace.files,
      root: workspace.root,
    );
    _fileIndex = IdeFileIndex(workspace.files, workspace.root);
    final languages = _languages = workspace.languages;
    _symbols = languages == null ? null : IdeDocumentSymbols(languages)
      ?..addListener(_symbolsChanged);
    _quickRefresh = Listenable.merge([_fileIndex, ?_symbols]);
    languages?.addListener(_languagesChanged);
    _editRequests = languages?.workspaceEdits.listen(_applyEditRequest);
    _markers = null;
    _backStack.clear();
    _forwardStack.clear();
    _references = null;
    workspace.addListener(_workspaceChanged);
    workspace.layout.addListener(_layoutChanged);
    _shownPanel = workspace.layout.panel;
    _activePath = null;
    _workspaceChanged();
    _git = workspace.git?..addListener(_gitChanged);
    _gitChanged();
    // New terminals start in the project; those running stay where they are.
    _terminals?.root = workspace.root;
  }

  void _detach(IdeWorkspace workspace) {
    workspace.removeListener(_workspaceChanged);
    workspace.layout.removeListener(_layoutChanged);
    _git?.removeListener(_gitChanged);
    _git = null;
    _scm.dispose();
    _scm = IdeScmSession();
    _explorer.dispose();
    _fileIndex.dispose();
    _languages?.removeListener(_languagesChanged);
    unawaited(_editRequests?.cancel());
    _editRequests = null;
    _symbols
      ?..removeListener(_symbolsChanged)
      ..dispose();
    _symbols = null;
    _languages = null;
  }

  void _languagesChanged() {
    if (!mounted) return;
    _recommendServers();
    _markers = null;
    final symbols = _symbols;
    if (symbols != null && !symbols.loaded) symbols.refresh();
    setState(() {});
  }

  void _gitChanged() {
    final state = _git?.state;
    final count = state?.count ?? 0;
    final branch = state?.head.branch;
    if (count == _gitCount && branch == _gitBranch) return;
    _gitCount = count;
    _gitBranch = branch;
    if (mounted) setState(() {});
  }

  /// The status bar's bell follows them.
  void _notificationsChanged() {
    if (mounted) setState(() {});
  }

  /// The terminal commands follow them. Once the last terminal is gone,
  /// the panel hides, as VS Code's `terminal.integrated.hideOnLastClosed`.
  void _terminalsChanged() {
    if (!mounted) return;
    setState(() {
      if (_panel == IdePanelTab.terminal &&
          (_terminals?.instances.isEmpty ?? true)) {
        _panel = null;
        // Its keyboard went with it, to the editor.
        _focusSoon();
      }
    });
  }

  void _symbolsChanged() {
    if (mounted) setState(() {});
  }

  /// `workspace/applyEdit` from a server: applied like a rename.
  Future<void> _applyEditRequest(LspApplyEditRequest request) async {
    try {
      final editor = _editor;
      final applied = editor != null
          ? await editor.applyWorkspaceEdit(request.edit)
          : await applyLspWorkspaceEdit(widget.workspace, request.edit);
      request.complete(applied);
    } catch (error) {
      request.complete(false);
      _report(error);
    }
  }

  @override
  void didUpdateWidget(IdeWorkbench oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      _detach(oldWidget.workspace);
      _attach();
      _readBranch();
    }
    if (widget.visible && !oldWidget.visible) {
      _readBranch();
      _focusSoon();
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_onChordKey);
    _chordChecker?.cancel();
    _statusMessageTimer?.cancel();
    // A quick pick going with the workbench hides (the color themes one
    // applies the theme it started with again).
    _quickPick?.onDidHide?.call();
    _detach(widget.workspace);
    _workbenchFocus.dispose();
    _explorerFocus.dispose();
    _timeline.dispose();
    _search.dispose();
    _extensions?.dispose();
    _notifications.dispose();
    _scm.dispose();
    _terminals
      ?..removeListener(_terminalsChanged)
      ..dispose();
    _panelFocus.dispose();
    super.dispose();
  }

  void _readBranch() {
    final root = widget.workspace.root;
    unawaited(
      readGitBranch(root).then((branch) {
        if (mounted && widget.workspace.root == root && branch != _branch) {
          setState(() => _branch = branch);
        }
      }),
    );
  }

  /// Follows the active editor: remembers it for Quick Open and reveals it
  /// in the explorer, as VS Code's `explorer.autoReveal` does.
  void _workspaceChanged() {
    _symbols?.update(widget.workspace.active);
    final path = widget.workspace.active?.path;
    if (path == _activePath) return;
    _activePath = path;
    if (path == null) return;
    // Upstream's `showEditorIfHidden`: an editor opened ends the chat's
    // maximizing.
    _layout.chatMaximized = false;
    _recommendServers();
    _recentFiles.add(path);
    unawaited(_explorer.reveal(path));
  }

  /// Focuses the editor if one is open, else the workbench itself, so the
  /// workbench shortcuts work before anything was clicked.
  void _focusSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.visible) return;
      final focused = FocusManager.instance.primaryFocus;
      if (focused != null &&
          focused != _workbenchFocus &&
          focused.context != null &&
          focused.context!.findAncestorStateOfType<IdeWorkbenchState>() ==
              this) {
        return;
      }
      _focusEditorOrWorkbench();
    });
  }

  void _focusEditorOrWorkbench() {
    final editor = _editor;
    if (editor != null && widget.workspace.active != null) {
      editor.focus();
    } else {
      _workbenchFocus.requestFocus();
    }
  }

  /// Errors are error notifications, as VS Code's are.
  void _report(Object error) {
    if (mounted) _notifications.notify(IdeSeverity.error, '$error');
  }

  // --- Editors ---------------------------------------------------------------

  Future<void> _open(
    String path, {
    int? line,
    int? column,
    LspRange? range,
    bool select = false,
    bool focusEditor = false,
    VoidCallback? afterReveal,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _editor?.flush();
      await widget.workspace.open(path);
      if (!mounted) return;
      if (line != null || range != null || focusEditor) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (range != null) {
            _editor?.revealRange(range, select: select);
            afterReveal?.call();
          } else if (line != null) {
            unawaited(_editor?.revealLine(line, column ?? 1));
          } else {
            _editor?.focus();
          }
        });
      }
    } catch (error) {
      _report(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(IdeDocument doc) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _editor?.flush();
      widget.workspace.select(doc.path);
    } catch (error) {
      _report(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// VS Code's save confirmation: Save, Don't Save or Cancel.
  Future<String?> _confirmClose(IdeDocument doc) async {
    final choice = await showIdeDialog(
      context,
      message: 'Do you want to save the changes you made to ${doc.name}?',
      detail: "Your changes will be lost if you don't save them.",
      buttons: const ['Save', "Don't Save"],
    );
    return switch (choice) {
      0 => 'save',
      1 => 'discard',
      _ => null,
    };
  }

  /// Closes [docs] in order, asking about each unsaved one; Cancel stops.
  Future<void> _closeDocs(List<IdeDocument> docs) async {
    if (_busy || docs.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _editor?.flush();
      for (final doc in docs) {
        if (!mounted) return;
        if (!widget.workspace.documents.contains(doc)) continue;
        if (doc.dirty) {
          final choice = await _confirmClose(doc);
          if (choice == null || !mounted) return;
          if (choice == 'save') await widget.workspace.save(doc);
        }
        await _editor?.closeDocument(doc);
        _closedEditors.remove(doc.path);
        _closedEditors.add(doc.path);
        widget.workspace.close(doc);
      }
    } catch (error) {
      _report(error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusEditorOrWorkbench();
        });
      }
    }
  }

  Future<void> _close(IdeDocument doc) => _closeDocs([doc]);

  void _closeActive() {
    if (widget.workspace.active case final doc?) unawaited(_close(doc));
  }

  void _reopenClosed() {
    final open = {for (final doc in widget.workspace.documents) doc.path};
    while (_closedEditors.isNotEmpty) {
      final path = _closedEditors.removeLast();
      if (!open.contains(path)) {
        unawaited(_open(path, focusEditor: true));
        return;
      }
    }
  }

  void _cycleEditor(int delta) {
    final docs = widget.workspace.documents;
    if (docs.length < 2) return;
    final index = docs.indexOf(widget.workspace.active ?? docs.first);
    unawaited(_select(docs[(index + delta) % docs.length]));
  }

  void _openEditorAt(int index) {
    final docs = widget.workspace.documents;
    if (docs.isEmpty) return;
    unawaited(
      _select(
        docs[index < 0 ? docs.length - 1 : math.min(index, docs.length - 1)],
      ),
    );
  }

  Future<void> _saveAll() async {
    try {
      await _editor?.flush();
      for (final doc in widget.workspace.documents) {
        if (doc.dirty) await widget.workspace.save(doc);
      }
    } catch (error) {
      _report(error);
    }
  }

  String _relative(String path) =>
      p.relative(path, from: widget.workspace.root);

  void _tabAction(IdeDocument doc, IdeTabAction action) {
    final docs = widget.workspace.documents;
    switch (action) {
      case IdeTabAction.close:
        unawaited(_close(doc));
      case IdeTabAction.closeOthers:
        unawaited(
          _closeDocs([
            for (final d in docs)
              if (!identical(d, doc)) d,
          ]),
        );
      case IdeTabAction.closeToTheRight:
        unawaited(_closeDocs(docs.sublist(docs.indexOf(doc) + 1)));
      case IdeTabAction.closeSaved:
        unawaited(
          _closeDocs([
            for (final d in docs)
              if (!d.dirty) d,
          ]),
        );
      case IdeTabAction.closeAll:
        unawaited(_closeDocs(docs));
      case IdeTabAction.copyPath:
        unawaited(Clipboard.setData(ClipboardData(text: doc.path)));
      case IdeTabAction.copyRelativePath:
        unawaited(Clipboard.setData(ClipboardData(text: _relative(doc.path))));
      case IdeTabAction.revealInExplorer:
        _revealInExplorer(doc.path);
    }
  }

  /// Shows the explorer, expands [path]'s folders, selects and focuses it.
  void _revealInExplorer(String path) {
    setState(() {
      _view = IdeSideView.explorer;
      _layout.showSidebar();
      _explorerPanes.add('folder');
    });
    unawaited(
      _explorer.reveal(path).then((_) {
        if (mounted) _explorerFocus.requestFocus();
      }),
    );
  }

  Future<void> _back() async {
    try {
      await _editor?.flush();
      if (mounted) widget.onBack();
    } catch (error) {
      _report(error);
    }
  }

  // --- Language features ---------------------------------------------------

  _NavigationEntry? _here() {
    final path = widget.workspace.active?.path;
    if (path == null) return null;
    return (
      path: path,
      position: LspPosition(
        _caretPosition.lineNumber - 1,
        _caretPosition.column - 1,
      ),
    );
  }

  /// Opens [location] (another file too), recording where the caret was
  /// for Go Back.
  Future<void> _openLocation(
    IdeLocation location, {
    bool select = false,
    bool record = true,
    VoidCallback? afterReveal,
  }) async {
    if (record) {
      final here = _here();
      if (here != null &&
          (_backStack.isEmpty ||
              _backStack.last.path != here.path ||
              _backStack.last.position != here.position)) {
        _backStack.add(here);
        if (_backStack.length > 50) _backStack.removeAt(0);
      }
      _forwardStack.clear();
    }
    if (widget.workspace.active?.path == location.path) {
      _editor?.revealRange(location.range, select: select);
      afterReveal?.call();
      if (mounted) setState(() {});
      return;
    }
    await _open(
      location.path,
      range: location.range,
      select: select,
      focusEditor: true,
      afterReveal: afterReveal,
    );
  }

  /// Go Back (⌃-) / Go Forward (⌃⇧-).
  void _navigate({required bool back}) {
    final from = back ? _backStack : _forwardStack;
    final to = back ? _forwardStack : _backStack;
    if (from.isEmpty) return;
    final here = _here();
    if (here != null) to.add(here);
    final entry = from.removeLast();
    unawaited(
      _openLocation(
        IdeLocation(entry.path, LspRange(entry.position, entry.position)),
        record: false,
      ),
    );
  }

  /// F8 / ⇧F8: the next or previous problem across files, with its hover.
  void _gotoProblem({required bool next}) {
    final languages = _languages;
    if (languages == null) return;
    final markers = _markers ??= ideMarkerList(languages.allDiagnostics);
    final resource = widget.workspace.active?.path ?? '';
    markers.move(next, resource, _caretPosition);
    final selected = markers.selected;
    if (selected == null) return;
    final marker = selected.marker;
    unawaited(
      _openLocation(
        IdeLocation(marker.resource, marker.data.range),
        afterReveal: () => _editor?.showHoverAtCaret(),
      ),
    );
  }

  void _showReferences(String title, List<IdeLocation> locations) {
    setState(() {
      _references = IdeReferences(title, locations);
      _panel = IdePanelTab.references;
    });
  }

  void _togglePanel(IdePanelTab tab) =>
      setState(() => _panel = _panel == tab ? null : tab);

  void _selectPanel(IdePanelTab tab) => setState(() => _panel = tab);

  // --- Terminals -------------------------------------------------------------

  /// Toggle Terminal (⌃`): the panel on TERMINAL, with the keyboard in the
  /// terminal, or hidden.
  void _toggleTerminal() {
    _togglePanel(IdePanelTab.terminal);
    if (_panel == IdePanelTab.terminal) _focusTerminalSoon();
  }

  /// Create New Terminal (⌃⇧`), shown and focused.
  void _newTerminal() {
    _terminals?.create();
    _showTerminal();
  }

  /// The panel on TERMINAL (a terminal made if there is none), the active
  /// terminal focused, as VS Code's `showPanel(true)`.
  void _showTerminal() {
    if (_terminals == null) return;
    setState(() => _panel = IdePanelTab.terminal);
    _focusTerminalSoon();
  }

  /// Once the panel shows (and lets its terminals have the keyboard).
  void _focusTerminalSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _terminals?.active?.focus();
    });
  }

  /// Focus Next (Previous) Terminal Group.
  void _cycleTerminal(bool next) {
    final terminals = _terminals;
    if (terminals == null) return;
    next ? terminals.focusNext() : terminals.focusPrevious();
    _showTerminal();
  }

  /// Rename...: the active terminal's name, edited in its tab (in the
  /// panel's title when it is the only one).
  void _renameTerminal() {
    final terminals = _terminals;
    if (terminals?.active == null) return;
    setState(() => _panel = IdePanelTab.terminal);
    terminals!.startRename();
  }

  Future<String?> _textOf(String path) async {
    for (final doc in widget.workspace.documents) {
      if (doc.path == path) return doc.text;
    }
    return widget.workspace.files.read(path);
  }

  LspPosition get _caretLsp =>
      LspPosition(_caretPosition.lineNumber - 1, _caretPosition.column - 1);

  List<LspDocumentSymbol> get _symbolPath {
    final symbols = _symbols;
    final active = widget.workspace.active;
    if (symbols == null || active == null || symbols.path != active.path) {
      return const [];
    }
    return ideSymbolPathAt(symbols.symbols, _caretLsp);
  }

  void _revealSymbol(LspDocumentSymbol symbol) {
    final path = widget.workspace.active?.path;
    if (path == null) return;
    unawaited(_openLocation(IdeLocation(path, symbol.selectionRange)));
  }

  /// Recommends installing the active file's missing language servers,
  /// once a session each, as VS Code recommends a language's extension
  /// (`FileBasedRecommendations`): a notification with Install.
  void _recommendServers() {
    final languages = _languages;
    final path = widget.workspace.active?.path;
    if (languages == null || path == null) return;
    for (final status in languages.statusFor(path)) {
      if (status.state == LanguageServerState.missing &&
          status.installable &&
          status.missingRuntime == null &&
          !widget.ignoredRecommendations.contains(status.serverId) &&
          _recommended.add(status.serverId)) {
        _recommendServer(status, path);
      }
    }
  }

  void _recommendServer(LanguageServerStatus status, String path) {
    final id = status.serverId;
    final language = IdeLanguageNames.forPath(path);
    _notifications.notify(
      IdeSeverity.info,
      "Do you want to install the recommended '$id' language server for "
      'the $language language?',
      sticky: true,
      primary: [IdeNotificationAction('Install', () => _install(id, path))],
      secondary: [
        IdeNotificationAction(
          "Don't Show Again for this Language Server",
          () => widget.onIgnoreRecommendation?.call(id),
        ),
      ],
    );
  }

  Future<void> _install(String id, String path) async {
    try {
      await _languages?.install(id, path: path);
    } catch (error) {
      _report(error);
    }
  }

  /// The status bar's missing server: why it cannot be installed, or its
  /// recommendation again.
  void _installServer(LanguageServerStatus status) {
    final path = widget.workspace.active?.path;
    if (path == null) return;
    if (status.installable && status.missingRuntime == null) {
      _recommendServer(status, path);
      return;
    }
    final runtime = status.missingRuntime;
    _notifications.notify(
      IdeSeverity.warning,
      runtime != null
          ? "Installing '${status.serverId}' needs $runtime, which was not "
                'found. Install $runtime, then try again.'
          : (status.message ??
                "'${status.serverId}' was not found on PATH and cannot be "
                    'installed automatically.'),
    );
  }

  // --- Layout ------------------------------------------------------------

  void _showView(IdeSideView view) {
    setState(() {
      _view = view;
      _layout.showSidebar();
    });
    if (view == IdeSideView.explorer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _explorerFocus.requestFocus();
      });
    }
  }

  void _toggleSidebar() => _layout.toggleSidebar();

  /// A part shown or hidden, here or from the window's header.
  void _layoutChanged() {
    final panel = _layout.panel;
    if (panel != _shownPanel) {
      _shownPanel = panel;
      // What had the keyboard there goes: it goes back to the editor.
      if (_panelFocus.hasFocus) _focusSoon();
      // VS Code makes a terminal when its view shows with none.
      if (panel == IdePanelTab.terminal) _terminals?.ensureTerminal();
    }
    if (mounted) setState(() {});
  }

  void _toggleChat() => _layout.toggleChat();

  /// VS Code's Toggle Panel: the panel as it was last, or hidden.
  void _togglePanelVisibility() =>
      setState(() => _panel = _panel == null ? _lastPanel : null);

  // --- Quick input ---------------------------------------------------------

  /// Opens the quick input with [prefix] (`>` commands, `:` go to line, none
  /// for files), or switches the open one to it.
  void _showQuickInput(String prefix) {
    if (prefix.isEmpty) unawaited(_fileIndex.refresh());
    if (_quickInput != null) {
      _quickInputKey.currentState?.setText(prefix);
      return;
    }
    _openQuickInput(() => _quickInput = prefix);
  }

  /// Opens [pick] in the quick input, in place of what it shows.
  void _showQuickPick(IdeQuickPick pick) =>
      _openQuickInput(() => _quickPick = pick);

  void _openQuickInput(VoidCallback open) {
    final replaced = _quickPick;
    if (_quickInput == null && replaced == null) {
      _focusBeforeQuickInput = FocusManager.instance.primaryFocus;
    }
    setState(() {
      _quickInputKey = GlobalKey();
      _quickInput = null;
      _quickPick = null;
      open();
    });
    // Upstream hides the quick input that another one replaces.
    replaced?.onDidHide?.call();
  }

  void _closeQuickInput() {
    final pick = _quickPick;
    if (_quickInput == null && pick == null) return;
    setState(() {
      _quickInput = null;
      _quickPick = null;
    });
    final previous = _focusBeforeQuickInput;
    _focusBeforeQuickInput = null;
    if (previous != null &&
        previous.context != null &&
        previous.canRequestFocus) {
      previous.requestFocus();
    } else {
      _focusEditorOrWorkbench();
    }
    pick?.onDidHide?.call();
  }

  /// Preferences: Color Theme (see [ideColorThemePick]).
  void _selectColorTheme() {
    if (widget.colorThemes case final themes?) {
      _showQuickPick(ideColorThemePick(themes, onError: _report));
    }
  }

  void _runCommand(IdeCommand command) {
    _recentCommands.add(command.id);
    command.run();
  }

  List<IdeQuickPickItem> _quickItems(String text) {
    if (text.startsWith('@')) {
      final symbols = _symbols;
      final active = widget.workspace.active;
      return symbolQuickPicks(
        text.substring(1),
        symbols: symbols != null && symbols.path == active?.path
            ? symbols.symbols
            : const [],
        loaded: symbols?.loaded ?? true,
        supported: symbols != null && active != null && symbols.supported,
        onGo: _revealSymbol,
      );
    }
    if (text.startsWith('>')) {
      return commandQuickPicks(
        text.substring(1),
        commands: _allCommands(),
        recent: _recentCommands,
        onRun: _runCommand,
      );
    }
    if (text.startsWith(':')) {
      final active = widget.workspace.active;
      return gotoLineQuickPicks(
        text.substring(1),
        lineCount: active?.model.snapshot.lineCount,
        currentLine: _caretPosition.lineNumber,
        currentColumn: _statusColumn,
        onGo: (line, column) =>
            unawaited(_editor?.revealLine(line, column ?? 1)),
      );
    }
    return fileQuickPicks(
      text,
      index: _fileIndex,
      recent: _recentFiles.items,
      onOpen: (path, line, column) =>
          unawaited(_open(path, line: line, column: column, focusEditor: true)),
    );
  }

  String _quickPlaceholder(String text) {
    if (text.startsWith('>')) return 'Type the name of a command to run.';
    if (text.startsWith(':')) return '';
    if (text.startsWith('@')) return 'Type the name of a symbol to go to.';
    return 'Search files by name (append : to go to a line or > to run a command)';
  }

  // --- Chords --------------------------------------------------------------
  // Two-chord keybindings (⌘K ⌘T), ported from VS Code
  // src/vs/platform/keybinding/common/abstractKeybindingService.ts at
  // 6a598d4a13031703d483d103c1d934a36ad27971 (`_doDispatch`,
  // `_expectAnotherChord`, `_scheduleLeaveChordMode`, `_leaveChordMode`),
  // with the status bar messages of notificationsStatus.ts. A first chord
  // counts when the focus lets it bubble here (a terminal keeps its keys);
  // the editor reports its own through [_onEditorChordKey].

  static final _modifierKeys = {
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
  };

  /// A key the focus let through: the first chord of a two-chord
  /// keybinding starts chord mode (`ResultKind.MoreChordsNeeded`).
  KeyEventResult _onWorkbenchKey(FocusNode node, KeyEvent event) {
    if (_chord != null || event is KeyUpEvent) return KeyEventResult.ignored;
    final candidates = _chordCandidates(event);
    if (candidates.isEmpty) return KeyEventResult.ignored;
    _expectAnotherChord(event, candidates, editor: false);
    return KeyEventResult.handled;
  }

  /// A key of a chord the editor starts ([second] false) or does not bind.
  void _onEditorChordKey(KeyEvent event, {required bool second}) {
    if (!second) {
      _leaveChordMode();
      _expectAnotherChord(event, _chordCandidates(event), editor: true);
    } else if (_chord case final chord? when chord.editor) {
      _resolveChord(chord, event);
    }
  }

  /// The key after a first chord, before the focus sees it: upstream's
  /// keybinding service takes it wherever the focus is.
  KeyEventResult _onChordKey(KeyEvent event) {
    final chord = _chord;
    if (chord == null ||
        event is KeyUpEvent ||
        _modifierKeys.contains(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    if (chord.editor) {
      // The editor takes it, handing it to [_onEditorChordKey] unless it
      // binds it; the chord ends either way.
      _setStatusMessage(null);
      scheduleMicrotask(() {
        if (identical(_chord, chord)) _leaveChordMode();
      });
      return KeyEventResult.ignored;
    }
    _resolveChord(chord, event);
    return KeyEventResult.handled;
  }

  List<({IdeKeybinding binding, VoidCallback run})> _chordCandidates(
    KeyEvent event,
  ) {
    final mac = ideUsesMacKeys;
    return [
      for (final chord in ideChordBindings(_allCommands()))
        if (chord.binding
            .activator(mac: mac)
            .accepts(event, HardwareKeyboard.instance))
          chord,
    ];
  }

  void _expectAnotherChord(
    KeyEvent event,
    List<({IdeKeybinding binding, VoidCallback run})> candidates, {
    required bool editor,
  }) {
    final label = IdeKeybinding.pressed(event).label();
    final message = '($label) was pressed. Waiting for second key of chord...';
    _chord = (
      label: label,
      candidates: candidates,
      message: message,
      editor: editor,
    );
    _setStatusMessage(message);
    // `_scheduleLeaveChordMode`: out after 5 seconds, or once the window
    // is not the active one.
    _chordChecker?.cancel();
    _chordChecker = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final state = WidgetsBinding.instance.lifecycleState;
      if ((state != null && state != AppLifecycleState.resumed) ||
          timer.tick * 500 > 5000) {
        _leaveChordMode();
      }
    });
  }

  /// Runs the keybinding [event] completes, or says there is none.
  void _resolveChord(_Chord chord, KeyEvent event) {
    _leaveChordMode();
    final mac = ideUsesMacKeys;
    for (final candidate in chord.candidates) {
      if (candidate.binding.second!
          .activator(mac: mac)
          .accepts(event, HardwareKeyboard.instance)) {
        candidate.run();
        return;
      }
    }
    final keypress = IdeKeybinding.pressed(event).label();
    _setStatusMessage(
      'The key combination (${chord.label}, $keypress) is not a command.',
      hideAfter: const Duration(seconds: 10),
    );
  }

  void _leaveChordMode() {
    final chord = _chord;
    if (chord == null) return;
    _chord = null;
    _chordChecker?.cancel();
    _chordChecker = null;
    if (identical(_statusMessage, chord.message)) _setStatusMessage(null);
  }

  /// Shows [message] in the status bar in place of the last one, for
  /// [hideAfter] if given (`NotificationsStatus.doSetStatusMessage`).
  void _setStatusMessage(String? message, {Duration? hideAfter}) {
    _statusMessageTimer?.cancel();
    _statusMessageTimer = message != null && hideAfter != null
        ? Timer(hideAfter, () => _setStatusMessage(null))
        : null;
    if (mounted) setState(() => _statusMessage = message);
  }

  // --- Commands ------------------------------------------------------------

  List<IdeCommand> _workbenchCommands() {
    final workspace = widget.workspace;
    final active = workspace.active;
    final hasEditors = workspace.documents.isNotEmpty;
    final terminals = _terminals;
    final terminal = terminals?.active;
    return [
      IdeCommand(
        id: 'workbench.action.showCommands',
        label: 'Show All Commands',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.keyP, primary: true, shift: true),
          IdeKeybinding(LogicalKeyboardKey.f1),
        ],
        run: () => _showQuickInput('>'),
      ),
      IdeCommand(
        id: 'workbench.action.quickOpen',
        label: 'Go to File…',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.keyP, primary: true),
        ],
        run: () => _showQuickInput(''),
      ),
      IdeCommand(
        id: 'workbench.action.gotoLine',
        label: 'Go to Line/Column…',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.keyG, control: true),
        ],
        run: () => _showQuickInput(':'),
      ),
      IdeCommand(
        id: 'actions.find',
        label: 'Find',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.keyF, primary: true),
        ],
        enabled: active != null,
        run: () => _editor?.openFind(),
      ),
      IdeCommand(
        id: 'editor.action.startFindReplaceAction',
        label: 'Replace',
        keybindings: const [
          IdeKeybinding(
            LogicalKeyboardKey.keyF,
            primary: true,
            alt: true,
            mac: true,
          ),
          IdeKeybinding(LogicalKeyboardKey.keyH, primary: true),
        ],
        enabled: active != null,
        run: () => _editor?.openReplace(),
      ),
      IdeCommand(
        id: 'workbench.action.files.save',
        category: 'File',
        label: 'Save',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.keyS, primary: true),
        ],
        enabled: active != null,
        run: () => unawaited(_editor?.save()),
      ),
      IdeCommand(
        id: 'workbench.action.files.saveAll',
        category: 'File',
        label: 'Save All',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.keyS, primary: true, alt: true),
        ],
        enabled: workspace.documents.any((doc) => doc.dirty),
        run: () => unawaited(_saveAll()),
      ),
      IdeCommand(
        id: 'workbench.action.closeActiveEditor',
        category: 'View',
        label: 'Close Editor',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.keyW, primary: true),
          IdeKeybinding(LogicalKeyboardKey.f4, control: true, mac: false),
        ],
        enabled: active != null,
        run: _closeActive,
      ),
      IdeCommand(
        id: 'workbench.action.closeOtherEditors',
        category: 'View',
        label: 'Close Other Editors',
        enabled: active != null && workspace.documents.length > 1,
        run: () => _tabAction(active!, IdeTabAction.closeOthers),
      ),
      IdeCommand(
        id: 'workbench.action.closeEditorsToTheRight',
        category: 'View',
        label: 'Close Editors to the Right',
        enabled: active != null && workspace.documents.last != active,
        run: () => _tabAction(active!, IdeTabAction.closeToTheRight),
      ),
      IdeCommand(
        id: 'workbench.action.closeUnmodifiedEditors',
        category: 'View',
        label: 'Close Saved Editors',
        enabled: workspace.documents.any((doc) => !doc.dirty),
        run: () => unawaited(
          _closeDocs([
            for (final doc in workspace.documents)
              if (!doc.dirty) doc,
          ]),
        ),
      ),
      IdeCommand(
        id: 'workbench.action.closeAllEditors',
        category: 'View',
        label: 'Close All Editors',
        enabled: hasEditors,
        run: () => unawaited(_closeDocs(workspace.documents)),
      ),
      IdeCommand(
        id: 'workbench.action.reopenClosedEditor',
        category: 'View',
        label: 'Reopen Closed Editor',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.keyT, primary: true, shift: true),
        ],
        enabled: _closedEditors.isNotEmpty,
        run: _reopenClosed,
      ),
      IdeCommand(
        id: 'workbench.action.nextEditor',
        category: 'View',
        label: 'Open Next Editor',
        keybindings: const [
          IdeKeybinding(
            LogicalKeyboardKey.bracketRight,
            primary: true,
            shift: true,
            mac: true,
          ),
          IdeKeybinding.character('}', primary: true, mac: true),
          IdeKeybinding(LogicalKeyboardKey.pageDown, control: true, mac: false),
          IdeKeybinding(LogicalKeyboardKey.tab, control: true),
        ],
        enabled: workspace.documents.length > 1,
        run: () => _cycleEditor(1),
      ),
      IdeCommand(
        id: 'workbench.action.previousEditor',
        category: 'View',
        label: 'Open Previous Editor',
        keybindings: const [
          IdeKeybinding(
            LogicalKeyboardKey.bracketLeft,
            primary: true,
            shift: true,
            mac: true,
          ),
          IdeKeybinding.character('{', primary: true, mac: true),
          IdeKeybinding(LogicalKeyboardKey.pageUp, control: true, mac: false),
          IdeKeybinding(LogicalKeyboardKey.tab, control: true, shift: true),
        ],
        enabled: workspace.documents.length > 1,
        run: () => _cycleEditor(-1),
      ),
      IdeCommand(
        id: 'workbench.action.toggleSidebarVisibility',
        category: 'View',
        label: 'Toggle Primary Side Bar Visibility',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.keyB, primary: true),
        ],
        run: _toggleSidebar,
      ),
      IdeCommand(
        id: 'workbench.action.toggleAuxiliaryBar',
        category: 'View',
        label: 'Toggle Chat',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.keyJ, primary: true),
          IdeKeybinding(LogicalKeyboardKey.keyB, primary: true, alt: true),
        ],
        run: _toggleChat,
      ),
      // VS Code's ⌘J toggles the panel; here it is the chat's.
      IdeCommand(
        id: 'workbench.action.togglePanel',
        category: 'View',
        label: 'Toggle Panel Visibility',
        run: _togglePanelVisibility,
      ),
      IdeCommand(
        id: 'workbench.action.terminal.toggleTerminal',
        category: 'Terminal',
        label: 'Toggle Terminal',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.backquote, control: true),
        ],
        enabled: terminals != null,
        run: _toggleTerminal,
      ),
      IdeCommand(
        id: 'workbench.action.terminal.new',
        category: 'Terminal',
        label: 'Create New Terminal',
        keybindings: const [TerminalKeys.create],
        enabled: terminals != null,
        run: _newTerminal,
      ),
      IdeCommand(
        id: 'workbench.action.terminal.kill',
        category: 'Terminal',
        label: 'Kill the Active Terminal Instance',
        enabled: terminal != null,
        run: () => terminals?.kill(),
      ),
      IdeCommand(
        id: 'workbench.action.terminal.rename',
        category: 'Terminal',
        label: 'Rename...',
        enabled: terminal != null,
        run: _renameTerminal,
      ),
      // Their keys are the terminal's own, while it has focus (see
      // TerminalPanel): elsewhere they switch editors.
      IdeCommand(
        id: 'workbench.action.terminal.focusNext',
        category: 'Terminal',
        label: 'Focus Next Terminal Group',
        keybindingLabel: terminalKeyLabel(TerminalKeys.focusNext),
        enabled: terminal != null,
        run: () => _cycleTerminal(true),
      ),
      IdeCommand(
        id: 'workbench.action.terminal.focusPrevious',
        category: 'Terminal',
        label: 'Focus Previous Terminal Group',
        keybindingLabel: terminalKeyLabel(TerminalKeys.focusPrevious),
        enabled: terminal != null,
        run: () => _cycleTerminal(false),
      ),
      IdeCommand(
        id: 'workbench.action.terminal.focus',
        category: 'Terminal',
        label: 'Focus Terminal',
        enabled: terminals != null,
        run: _showTerminal,
      ),
      IdeCommand(
        id: 'workbench.view.explorer',
        category: 'View',
        label: 'Show Explorer',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.keyE, primary: true, shift: true),
        ],
        run: () => _showView(IdeSideView.explorer),
      ),
      IdeCommand(
        id: 'workbench.view.search',
        category: 'View',
        label: 'Show Search',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.keyF, primary: true, shift: true),
        ],
        run: () => _showView(IdeSideView.search),
      ),
      IdeCommand(
        id: 'workbench.view.scm',
        category: 'View',
        label: 'Show Source Control',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.keyG, control: true, shift: true),
        ],
        run: () => _showView(IdeSideView.sourceControl),
      ),
      IdeCommand(
        id: 'workbench.view.extensions',
        category: 'View',
        label: 'Show Extensions',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.keyX, primary: true, shift: true),
        ],
        run: () => _showView(IdeSideView.extensions),
      ),
      IdeCommand(
        id: 'workbench.files.action.showActiveFileInExplorer',
        category: 'File',
        label: 'Reveal Active File in Explorer View',
        enabled: active != null,
        run: () => _revealInExplorer(active!.path),
      ),
      IdeCommand(
        id: 'workbench.files.action.refreshFilesExplorer',
        category: 'File',
        label: 'Refresh Explorer',
        run: () => unawaited(_explorer.refresh()),
      ),
      IdeCommand(
        id: 'workbench.files.action.collapseExplorerFolders',
        category: 'File',
        label: 'Collapse Folders in Explorer',
        run: _explorer.collapseAll,
      ),
      IdeCommand(
        id: 'copyFilePath',
        category: 'File',
        label: 'Copy Path of Active File',
        keybindings: const [
          IdeKeybinding(
            LogicalKeyboardKey.keyC,
            primary: true,
            alt: true,
            mac: true,
          ),
          IdeKeybinding(
            LogicalKeyboardKey.keyC,
            shift: true,
            alt: true,
            mac: false,
          ),
        ],
        enabled: active != null,
        run: () => _tabAction(active!, IdeTabAction.copyPath),
      ),
      IdeCommand(
        id: 'copyRelativeFilePath',
        category: 'File',
        label: 'Copy Relative Path of Active File',
        keybindings: const [
          IdeKeybinding(
            LogicalKeyboardKey.keyC,
            primary: true,
            alt: true,
            shift: true,
            mac: true,
          ),
        ],
        enabled: active != null,
        run: () => _tabAction(active!, IdeTabAction.copyRelativePath),
      ),
      IdeCommand(
        id: 'workbench.action.gotoSymbol',
        label: 'Go to Symbol in Editor...',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.keyO, primary: true, shift: true),
        ],
        enabled: active != null,
        run: () => _showQuickInput('@'),
      ),
      IdeCommand(
        id: 'workbench.actions.view.problems',
        category: 'View',
        label: 'Toggle Problems',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.keyM, primary: true, shift: true),
        ],
        run: () => _togglePanel(IdePanelTab.problems),
      ),
      IdeCommand(
        id: 'outline.focus',
        category: 'View',
        label: 'Show Outline',
        run: () {
          _explorerPanes.add('outline');
          _showView(IdeSideView.explorer);
        },
      ),
      IdeCommand(
        id: 'editor.action.marker.nextInFiles',
        label: 'Go to Next Problem in Files (Error, Warning, Info)',
        keybindings: const [IdeKeybinding(LogicalKeyboardKey.f8)],
        enabled: _languages != null,
        run: () => _gotoProblem(next: true),
      ),
      IdeCommand(
        id: 'editor.action.marker.prevInFiles',
        label: 'Go to Previous Problem in Files (Error, Warning, Info)',
        keybindings: const [IdeKeybinding(LogicalKeyboardKey.f8, shift: true)],
        enabled: _languages != null,
        run: () => _gotoProblem(next: false),
      ),
      IdeCommand(
        id: 'workbench.action.navigateBack',
        category: 'Go',
        label: 'Go Back',
        keybindings: const [
          IdeKeybinding(LogicalKeyboardKey.minus, control: true, mac: true),
          IdeKeybinding(LogicalKeyboardKey.arrowLeft, alt: true, mac: false),
        ],
        enabled: _backStack.isNotEmpty,
        run: () => _navigate(back: true),
      ),
      IdeCommand(
        id: 'workbench.action.navigateForward',
        category: 'Go',
        label: 'Go Forward',
        keybindings: const [
          IdeKeybinding(
            LogicalKeyboardKey.minus,
            control: true,
            shift: true,
            mac: true,
          ),
          IdeKeybinding(LogicalKeyboardKey.arrowRight, alt: true, mac: false),
        ],
        enabled: _forwardStack.isNotEmpty,
        run: () => _navigate(back: false),
      ),
      IdeCommand(
        id: ideSelectColorThemeCommandId,
        category: 'Preferences',
        label: 'Color Theme',
        keybindings: const [ideSelectColorThemeKeybinding],
        enabled: widget.colorThemes != null,
        run: _selectColorTheme,
      ),
      IdeCommand(
        id: 'monad.ide.toggleFormatOnSave',
        category: 'Preferences',
        label: _formatOnSave
            ? 'Turn Off Format on Save'
            : 'Turn On Format on Save',
        enabled: _languages != null,
        run: () => setState(() => _formatOnSave = !_formatOnSave),
      ),
      IdeCommand(
        id: 'monad.ide.retryLanguageServices',
        category: 'Developer',
        label: 'Retry Language Services',
        enabled: active != null,
        run: () => unawaited(_editor?.retryLanguageServer()),
      ),
      IdeCommand(
        id: 'monad.ide.backToChat',
        category: 'View',
        label: 'Back to Chat',
        run: () => unawaited(_back()),
      ),
    ];
  }

  /// The workbench's commands, then the editor's, then [IdeWorkbench.commands].
  List<IdeCommand> _allCommands() => [
    ..._workbenchCommands(),
    ...?_editor?.editorCommands,
    ...widget.commands,
  ];

  /// The commands for the current state, for the palette and for tests.
  @visibleForTesting
  List<IdeCommand> get commands => _allCommands();

  Map<ShortcutActivator, VoidCallback> _shortcuts(List<IdeCommand> commands) {
    final mac = ideUsesMacKeys;
    return {
      ...ideShortcutBindings(commands),
      // Open Editor at Index: ⌃1…⌃9 on macOS, Alt+1…9 elsewhere (VS Code).
      for (var i = 1; i <= 9; i++)
        SingleActivator(
          LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i - 1),
          control: mac,
          alt: !mac,
        ): () =>
            _openEditorAt(i == 9 ? -1 : i - 1),
    };
  }

  // --- Widgets -------------------------------------------------------------

  /// The activity bar's card, [joined] to the side bar beside it when that
  /// is showing (their seam is this card's border).
  Widget _activityBar({required bool joined}) {
    Widget item(IdeSideView view, IconData icon, String label, {int? badge}) {
      // The side bar as it shows: one given way to the chat opens.
      final selected = _view == view && joined;
      return _ActivityItem(
        icon: icon,
        label: label,
        badge: badge,
        selected: selected,
        onTap: () => setState(() {
          if (selected) {
            _sidebarShown = false;
          } else {
            _view = view;
            _layout.showSidebar();
          }
        }),
      );
    }

    String shortcut(LogicalKeyboardKey key, {bool control = false}) {
      final binding = control
          ? IdeKeybinding(key, control: true, shift: true)
          : IdeKeybinding(key, primary: true, shift: true);
      return ' (${binding.label()})';
    }

    const radius = Radius.circular(IdeModernUI.radius);
    // Half the lane each side, less the border already there.
    const inset = IdeModernUI.activityLane / 2 - 1;
    final items = [
      item(
        IdeSideView.explorer,
        Codicons.files,
        'Explorer${shortcut(LogicalKeyboardKey.keyE)}',
      ),
      item(
        IdeSideView.search,
        Codicons.search,
        'Search files${shortcut(LogicalKeyboardKey.keyF)}',
      ),
      item(
        IdeSideView.sourceControl,
        Codicons.sourceControl,
        'Source Control${shortcut(LogicalKeyboardKey.keyG, control: true)}'
        '${_gitCount > 0 ? ' - $_gitCount pending changes' : ''}',
        badge: _gitCount,
      ),
      item(
        IdeSideView.extensions,
        Codicons.extensions,
        'Extensions${shortcut(LogicalKeyboardKey.keyX)}',
      ),
    ];
    return SizedBox(
      width: IdeModernUI.activityBarWidth,
      child: IdeCard(
        color: IdeModernUI.activityBarBackground,
        radius: joined
            ? const BorderRadius.horizontal(left: radius)
            : const BorderRadius.all(radius),
        child: Padding(
          padding: const EdgeInsets.all(inset),
          child: Column(
            children: [
              for (final (index, item) in items.indexed) ...[
                if (index > 0)
                  const SizedBox(height: IdeModernUI.activityItemGap),
                item,
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The side bar's card, joined to the activity bar's on its left.
  Widget _sidebarCard() => IdeCard(
    color: IdeModernUI.surface,
    radius: const BorderRadius.horizontal(
      right: Radius.circular(IdeModernUI.radius),
    ),
    border: Border(
      top: BorderSide(color: IdeModernUI.border),
      right: BorderSide(color: IdeModernUI.border),
      bottom: BorderSide(color: IdeModernUI.border),
    ),
    child: _sidePanel(),
  );

  Widget _sidePanel() => switch (_view) {
    IdeSideView.explorer => _explorerView(),
    IdeSideView.search => IdeSearchView(
      session: _search,
      workspace: widget.workspace,
      onOpen: (path, range, {required focusEditor}) =>
          _open(path, range: range, select: true, focusEditor: focusEditor),
      onError: _report,
    ),
    IdeSideView.sourceControl => IdeScmView(
      workspace: widget.workspace,
      session: _scm,
      notifications: _notifications,
      onOpen: (path, {focusEditor = false}) =>
          _open(path, focusEditor: focusEditor),
      onRevealInExplorer: _revealInExplorer,
      trash: WindowControls.canMoveToTrash ? WindowControls.moveToTrash : null,
      commitMessage: widget.commitMessage,
    ),
    IdeSideView.extensions => IdeExtensionsView(
      session: _extensions ??= IdeExtensionsSession(
        widget.extensions ?? IdeLanguageServerExtensions(),
      ),
      recommended: _recommendedServers(),
      onInstalled: _startServer,
      onError: _report,
    ),
  };

  /// Starts the open files' servers named [id], and those limited to some
  /// of its features (`ruff#only=format`), now that it is installed.
  void _startServer(String id) {
    final languages = _languages;
    if (languages == null) return;
    final ids = {
      id,
      for (final doc in widget.workspace.documents)
        for (final status in languages.statusFor(doc.path))
          if (status.serverId.split('#').first == id) status.serverId,
    };
    ids.forEach(languages.retry);
  }

  /// The servers the open files want and could install, less those not to
  /// recommend: the Extensions view's Recommended pane.
  Set<String> _recommendedServers() {
    final languages = _languages;
    if (languages == null) return const {};
    return {
      for (final doc in widget.workspace.documents)
        for (final status in languages.statusFor(doc.path))
          if (status.state == LanguageServerState.missing &&
              status.installable &&
              !widget.ignoredRecommendations.contains(status.serverId))
            status.serverId.split('#').first,
    };
  }

  /// The Explorer view: the folder's tree, the active editor's outline and
  /// its file's timeline, as panes.
  Widget _explorerView() {
    final workspace = widget.workspace;
    final activePath = workspace.active?.path;
    final timelinePath = IdeTimelineView.pathOf(_timeline, activePath);
    return ColoredBox(
      color: themeColors['sideBar.background'],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const IdeViewTitle('Explorer'),
          Expanded(
            child: IdePaneContainer(
              expanded: _explorerPanes,
              onToggle: (id) => setState(() {
                if (!_explorerPanes.remove(id)) _explorerPanes.add(id);
              }),
              panes: [
                IdePane(
                  id: 'folder',
                  title: widget.project.name,
                  weight: 3,
                  actions: [
                    IdePaneAction(
                      icon: Codicons.newFile,
                      tooltip: 'New File...',
                      onPressed: () => unawaited(
                        _explorerTree.currentState?.startCreate(
                          directory: false,
                        ),
                      ),
                    ),
                    IdePaneAction(
                      icon: Codicons.newFolder,
                      tooltip: 'New Folder...',
                      onPressed: () => unawaited(
                        _explorerTree.currentState?.startCreate(
                          directory: true,
                        ),
                      ),
                    ),
                    IdePaneAction(
                      icon: Codicons.refresh,
                      tooltip: 'Refresh Explorer',
                      onPressed: () => unawaited(_explorer.refresh()),
                    ),
                    IdePaneAction(
                      icon: Codicons.collapseAll,
                      tooltip: 'Collapse Folders in Explorer',
                      onPressed: _explorer.collapseAll,
                    ),
                  ],
                  body: IdeExplorer(
                    key: _explorerTree,
                    controller: _explorer,
                    focusNode: _explorerFocus,
                    git: workspace.git,
                    onOpen: (path, focusEditor) =>
                        unawaited(_open(path, focusEditor: focusEditor)),
                    onMoved: workspace.moved,
                    onDeleted: workspace.deleted,
                    unsavedIn: (path) => workspace
                        .documentsIn(path)
                        .where((d) => d.dirty)
                        .length,
                    trash: WindowControls.canMoveToTrash
                        ? WindowControls.moveToTrash
                        : null,
                    onError: _report,
                    onFindInFolder: (folder) {
                      _search.findInFolder(
                        _relative(folder) == '.' ? '' : _relative(folder),
                        workspace.root,
                      );
                      _showView(IdeSideView.search);
                    },
                  ),
                ),
                IdePane(
                  id: 'outline',
                  title: 'Outline',
                  body: IdeOutlineView(
                    symbols: _symbols,
                    caret: workspace.active == null ? null : _caretLsp,
                    onReveal: _revealSymbol,
                    showHeader: false,
                  ),
                ),
                IdePane(
                  id: 'timeline',
                  title: 'Timeline',
                  description: timelinePath == null
                      ? null
                      : p.basename(timelinePath),
                  actions: [
                    IdePaneAction(
                      icon: _timeline.pinned == null
                          ? Codicons.pin
                          : Codicons.pinned,
                      tooltip: _timeline.pinned == null
                          ? 'Pin the Current Timeline'
                          : 'Unpin the Current Timeline',
                      onPressed: () =>
                          setState(() => _timeline.togglePin(activePath)),
                    ),
                    IdePaneAction(
                      icon: Codicons.refresh,
                      tooltip: 'Refresh',
                      onPressed: _timeline.refresh,
                    ),
                  ],
                  body: IdeTimelineView(
                    controller: _timeline,
                    git: workspace.git,
                    activePath: activePath,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _editorArea(List<IdeCommand> commands) {
    final active = widget.workspace.active;
    return IdeCard(
      color: themeColors['editor.background'],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.workspace.documents.isNotEmpty) ...[
            IdeTabBar(
              documents: widget.workspace.documents,
              active: active,
              root: widget.workspace.root,
              onSelect: (doc) => unawaited(_select(doc)),
              onClose: (doc) => unawaited(_close(doc)),
              onAction: _tabAction,
            ),
            if (active != null)
              IdeBreadcrumbs(
                root: widget.workspace.root,
                path: active.path,
                onReveal: _revealInExplorer,
                symbols: _symbolPath,
                onSymbol: _revealSymbol,
              ),
          ],
          Expanded(
            child: active == null
                ? IdeWelcome(
                    commands: [
                      for (final id in const [
                        'workbench.action.showCommands',
                        'workbench.action.quickOpen',
                        'workbench.view.search',
                        'actions.find',
                        'workbench.action.gotoLine',
                        'workbench.action.toggleSidebarVisibility',
                        'workbench.action.toggleAuxiliaryBar',
                      ])
                        ...commands.where((command) => command.id == id),
                    ],
                  )
                : active.openError != null
                ? IdeEditorPlaceholder(
                    key: ValueKey(active),
                    error: active.openError!,
                    onOpenAnyway: () =>
                        unawaited(widget.workspace.reopen(active, force: true)),
                    onRetry: () => unawaited(widget.workspace.reopen(active)),
                  )
                : widget.editorBuilder?.call(context, widget.workspace) ??
                      IdeEditor(
                        nativeEditorEnabled: widget.nativeEditorEnabled,
                        key: _editorKey,
                        workspace: widget.workspace,
                        active: active,
                        onError: _report,
                        onLspStatus: (status) {
                          if (mounted) setState(() => _lspStatus = status);
                        },
                        onPositionChanged: _positionChanged,
                        onOpenLocation: _openLocation,
                        onShowReferences: _showReferences,
                        onShowCommands: () => _showQuickInput('>'),
                        formatOnSave: _formatOnSave,
                        onChordKey: _onEditorChordKey,
                      ),
          ),
        ],
      ),
    );
  }

  void _positionChanged(IdeEditorPosition selection) {
    if (mounted &&
        (!_caretPosition.equals(selection.position) ||
            _statusColumn != selection.statusColumn ||
            _selectionLength != selection.selectionLength)) {
      setState(() {
        _caretPosition = selection.position;
        _statusColumn = selection.statusColumn;
        _selectionLength = selection.selectionLength;
      });
    }
  }

  /// The chat, kept mounted (and its state kept) while hidden.
  Widget _chatSlot(double width) {
    final shown = width > 0;
    final laidOut = shown ? width : _chatWidth;
    return SizedBox(
      key: const ValueKey('ide-chat'),
      width: width,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: laidOut,
        maxWidth: laidOut,
        child: Offstage(
          offstage: !shown,
          child: TickerMode(
            enabled: shown,
            child: ExcludeFocus(excluding: !shown, child: _chatCard()),
          ),
        ),
      ),
    );
  }

  /// The chat's card, which keeps its state as it moves to the editor's
  /// place, maximized, and back.
  Widget _chatCard() => IdeCard(key: _chatKey, child: widget.chat);
  final _chatKey = GlobalKey(debugLabel: 'ide chat');

  /// What [IdeLayout.roomForBoth] is to be, from the last layout: the
  /// layout's listeners build, so it is told after the frame.
  bool _roomForBoth = true;
  bool _roomForBothPending = false;

  void _noteRoomForBoth(bool value) {
    _roomForBoth = value;
    if (value == _layout.roomForBoth || _roomForBothPending) return;
    _roomForBothPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _roomForBothPending = false;
      if (mounted) _layout.roomForBoth = _roomForBoth;
    });
  }

  /// The Modern UI's cards on the shell: 4px apart, and 4px from the
  /// window's sides and the status bar. The chat stays on the right however
  /// narrow the window (see [IdeColumns.fit]), or, maximized, has the
  /// editor's place and the side bar's.
  Widget _split(Size size, List<IdeCommand> commands) {
    const gap = IdeModernUI.gap;
    final maximized = _layout.chatMaximized;
    // Hidden, the chat leaves its sash as the gap at the window's side. The
    // gap above the status bar is each column's: the panel's sash, hidden.
    final outside = EdgeInsets.fromLTRB(gap, 0, _chatShown ? gap : 0, 0);
    // Keyed, so a sash keeps its drag as the columns change about it.
    Widget above(Widget column, String slot) => Padding(
      key: ValueKey('ide-row-$slot'),
      padding: const EdgeInsets.only(bottom: gap),
      child: column,
    );
    // Maximized, the chat has one sash less, but is sized as though both
    // were there: dragged back, the editor comes out where the pointer is.
    final room =
        size.width -
        outside.horizontal -
        IdeModernUI.activityBarWidth -
        2 * _sashWidth;
    _noteRoomForBoth(IdeColumns.roomForBoth(room - (_chatShown ? 0 : gap)));
    final columns = IdeColumns.fit(
      room,
      sidebar: _sidebarShown ? _sidebarWidth : null,
      chat: _chatShown ? _chatWidth : null,
      chatMaximized: maximized,
    );
    final sidebarVisible = columns.sidebar > 0;
    final chatVisible = columns.chat > 0;
    final chatSash = above(
      _Sash(
        key: const ValueKey('ide-chat-sash'),
        grip: chatVisible,
        canMoveBack: columns.canGrowChat(room),
        canMoveForward: chatVisible,
        onStart: () => _dragStart = (columns: columns, room: room),
        onDrag: (dx) => _dragTo((start, room) => start.dragChat(room, dx)),
        onReset: () => setState(() {
          _layout
            ..showChat()
            ..chatMaximized = false;
          _chatWidth = IdeColumns.defaultChat;
        }),
      ),
      'chat-sash',
    );
    return Padding(
      padding: outside,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          above(_activityBar(joined: sidebarVisible), 'activity-bar'),
          if (sidebarVisible)
            above(
              SizedBox(
                key: const ValueKey('ide-sidebar'),
                width: columns.sidebar,
                child: _sidebarCard(),
              ),
              'sidebar',
            ),
          // Maximized, the chat's sash is by the activity bar: dragged
          // back, the editor comes out.
          if (maximized)
            chatSash
          else
            // With the side bar hidden, the gap by the activity bar: dragged
            // out, it opens the side bar.
            above(
              _Sash(
                key: const ValueKey('ide-sidebar-sash'),
                grip: sidebarVisible,
                canMoveBack: sidebarVisible,
                canMoveForward: columns.canGrowSidebar(room),
                onStart: () => _dragStart = (columns: columns, room: room),
                onDrag: (dx) =>
                    _dragTo((start, room) => start.dragSidebar(room, dx)),
                onReset: () => setState(() {
                  _layout.showSidebar();
                  _sidebarWidth = IdeColumns.defaultSidebar;
                }),
              ),
              'sidebar-sash',
            ),
          Expanded(
            key: const ValueKey('ide-editor-column'),
            child: _editorColumn(size.height, commands, maximized: maximized),
          ),
          if (!maximized) ...[chatSash, above(_chatSlot(columns.chat), 'chat')],
        ],
      ),
    );
  }

  /// The editor, and below it the panel (the terminal), as VS Code's panel
  /// at the bottom, centered: under the editor only. Hidden, the panel
  /// leaves its sash as the gap above the status bar. [maximized], the chat
  /// has the editor's place, above the panel; the editor is kept, as the
  /// chat hidden is.
  Widget _editorColumn(
    double height,
    List<IdeCommand> commands, {
    required bool maximized,
  }) {
    final shown = _panel != null;
    final room = height - _sashWidth - (shown ? IdeModernUI.gap : 0);
    final rows = IdeRows.fit(
      room,
      panel: shown ? _panelHeight ?? IdeRows.defaultPanel(room) : null,
      minAbove: maximized ? IdeRows.minChat : IdeRows.minEditor,
    );
    final panelVisible = rows.panel > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: maximized,
                child: TickerMode(
                  enabled: !maximized,
                  child: ExcludeFocus(
                    excluding: maximized,
                    child: KeyedSubtree(
                      key: const ValueKey('ide-editor'),
                      child: _editorArea(commands),
                    ),
                  ),
                ),
              ),
              if (maximized)
                KeyedSubtree(
                  key: const ValueKey('ide-chat'),
                  child: _chatCard(),
                ),
            ],
          ),
        ),
        _Sash(
          key: const ValueKey('ide-panel-sash'),
          axis: Axis.vertical,
          grip: panelVisible,
          canMoveBack: rows.canGrowPanel(room),
          canMoveForward: panelVisible,
          onStart: () => _panelDragStart = (rows: rows, room: room),
          onDrag: _dragPanel,
          onReset: () => setState(() {
            _panel ??= _lastPanel;
            _panelHeight = null;
          }),
        ),
        _panelSlot(rows.panel, commands),
        if (shown) const SizedBox(height: IdeModernUI.gap),
      ],
    );
  }

  /// Opens a link from a terminal, as VS Code's link openers: a URL in the
  /// browser, a file in the editor at its line and column, a folder of the
  /// workspace in the explorer (another in the system's file manager, where
  /// VS Code opens a window), a word in quick open.
  void _openTerminalLink(TerminalLink link) {
    switch (link.type) {
      case TerminalLinkType.url:
        unawaited(openExternal(link.text));
      case TerminalLinkType.localFile:
        unawaited(
          _open(
            link.path!,
            line: link.line,
            column: link.column,
            focusEditor: true,
          ),
        );
      case TerminalLinkType.localFolder:
        if (link.inWorkspace) {
          _revealInExplorer(link.path!);
        } else {
          unawaited(openExternal(link.path!));
        }
      case TerminalLinkType.search:
        _showQuickInput(link.searchText ?? link.text);
    }
  }

  /// The panel's sash, [dy] from where its drag began. Snapped shut, the
  /// panel opens again (⌃`) as high as it was.
  void _dragPanel(double dy) {
    final start = _panelDragStart;
    if (start == null) return;
    final next = start.rows.drag(start.room, dy);
    setState(() {
      if (next.panel > 0) {
        _panel ??= _lastPanel;
        _panelHeight = next.panel;
      } else if (start.rows.panel > 0) {
        _panel = null;
        _panelHeight = start.rows.panel;
      }
    });
  }

  /// The panel, kept mounted (and its terminals running) while hidden.
  Widget _panelSlot(double height, List<IdeCommand> commands) {
    final shown = height > 0;
    final laidOut = shown ? height : _panelHeight ?? IdeRows.minPanel;
    return SizedBox(
      key: const ValueKey('ide-panel'),
      height: height,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minHeight: laidOut,
        maxHeight: laidOut,
        child: Offstage(
          offstage: !shown,
          child: TickerMode(
            enabled: shown,
            child: ExcludeFocus(
              excluding: !shown,
              child: Focus(
                focusNode: _panelFocus,
                // panelPart.ts' `panel.background` (the editor's by
                // default), not the shell's.
                child: IdeCard(
                  color: themeColors['panel.background'],
                  child: IdeBottomPanel(
                    tab: _panel ?? _lastPanel,
                    root: widget.workspace.root,
                    languages: _languages,
                    references: _references,
                    // TERMINAL, clicked, gives its terminal the keyboard.
                    onTab: (tab) => tab == IdePanelTab.terminal
                        ? _showTerminal()
                        : _selectPanel(tab),
                    onClose: () => setState(() => _panel = null),
                    onOpen: (location, {select = false}) =>
                        unawaited(_openLocation(location, select: select)),
                    textOf: _textOf,
                    terminal: switch (_terminals) {
                      final terminals? => TerminalPanel(
                        terminals: terminals,
                        onNew: _newTerminal,
                        onOpenLink: _openTerminalLink,
                        skipShell: [
                          for (final command in commands)
                            if (terminalCommandsToSkipShell.contains(
                              command.id,
                            ))
                              ...command.keybindings,
                        ],
                      ),
                      null => null,
                    },
                    terminalActions: switch (_terminals) {
                      final terminals? => TerminalTitleActions(
                        terminals: terminals,
                        onNew: _newTerminal,
                      ),
                      null => null,
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Where a sash's drag has got to, [drag] from its start. A part pushed
  /// or snapped shut opens again (⌘B, ⌘J) as wide as it was, and the chat
  /// maximized comes back as wide as it was.
  void _dragTo(IdeColumns Function(IdeColumns start, double room) drag) {
    final start = _dragStart;
    if (start == null) return;
    final columns = start.columns;
    final next = drag(columns, start.room);
    setState(() {
      _layout.chatMaximized = next.chatMaximized;
      if (next.sidebar > 0) {
        _sidebarShown = true;
        _sidebarWidth = next.sidebar;
      } else if (columns.sidebar > 0) {
        _sidebarShown = false;
        _sidebarWidth = columns.sidebar;
      }
      // Maximized, the chat is all the room: it comes back from there as
      // wide as when the drag began.
      if (next.chatMaximized) {
        if (!columns.chatMaximized) _chatWidth = columns.chat;
      } else if (next.chat > 0) {
        _chatShown = true;
        _chatWidth = next.chat;
      } else if (columns.chat > 0) {
        _chatShown = false;
        if (!columns.chatMaximized) _chatWidth = columns.chat;
      }
    });
  }

  Widget _titleBar() {
    final quickOpen = const IdeKeybinding(
      LogicalKeyboardKey.keyP,
      primary: true,
    ).label();
    // A double click on its empty part zooms the window, as the system's
    // title bar does.
    return TitleBarDoubleClick(
      child: SizedBox(
        height: CursorMetrics.titleBarHeight,
        child: Row(
          children: [
            SizedBox(width: CursorMetrics.trafficLightsWidth + 6),
            // VS Code's layout controls; the side bar's on its side, after
            // the traffic lights.
            IdeLayoutToggle.sidebar(_layout),
            const SizedBox(width: 12),
            Expanded(
              child: Center(
                child: _CommandCenter(
                  label: widget.project.name,
                  shortcut: quickOpen,
                  onTap: () => _showQuickInput(''),
                ),
              ),
            ),
            TitleBarControls(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IdeLayoutToggle.panel(_layout),
                  IdeLayoutToggle.chat(_layout),
                  if (widget.onPinnedChanged case final onPinnedChanged?) ...[
                    const SizedBox(width: 2),
                    PinWindowButton(
                      pinned: widget.pinned,
                      onChanged: onPinnedChanged,
                    ),
                  ],
                  const SizedBox(width: 8),
                  BackToChatButton(onPressed: () => unawaited(_back())),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  IdeStatusBar _statusBar() {
    final active = widget.workspace.active;
    final left = [
      if (_gitBranch ?? _branch case final branch?)
        IdeStatusBarItem(
          branch,
          icon: Codicons.gitBranch,
          tooltip: 'Source Control',
          onTap: () => _showView(IdeSideView.sourceControl),
        ),
      IdeStatusBarItem(
        _lspStatus,
        tooltip: 'Retry language services',
        onTap: () => unawaited(_editor?.retryLanguageServer()),
      ),
      if (_languages case final languages?) ...[
        () {
          final counts = ideDiagnosticCounts(languages.allDiagnostics);
          return IdeStatusBarItem(
            '\$(error) ${counts.errors} \$(warning) ${counts.warnings}'
            '${counts.infos > 0 ? ' \$(info) ${counts.infos}' : ''}',
            tooltip: counts.errors + counts.warnings + counts.infos == 0
                ? 'No Problems'
                : 'Errors: ${counts.errors}, Warnings: ${counts.warnings}'
                      '${counts.infos > 0 ? ', Infos: ${counts.infos}' : ''}',
            onTap: () => _togglePanel(IdePanelTab.problems),
          );
        }(),
        if (widget.workspace.active case final doc?)
          ...ideLanguageStatusItems(
            languages,
            doc.path,
            onInstall: _installServer,
          ),
      ],
      if (_statusMessage case final message?) IdeStatusBarItem(message),
    ];
    final bell = ideNotificationsStatusItem(_notifications);
    if (active == null || active.openError != null) {
      return IdeStatusBar(left: left, right: [bell]);
    }
    final snapshot = active.model.snapshot;
    if (!identical(snapshot, _eolSnapshot)) {
      _eolSnapshot = snapshot;
      _eolLabel = ideEolLabel(snapshot);
    }
    return IdeStatusBar(
      left: left,
      right: [
        IdeStatusBarItem(
          'Ln ${_caretPosition.lineNumber}, Col $_statusColumn'
          '${_selectionLength > 0 ? ' ($_selectionLength selected)' : ''}',
          tooltip: 'Go to Line/Column',
          onTap: () => _showQuickInput(':'),
        ),
        IdeStatusBarItem(
          _editor?.indentationLabel ?? 'Spaces: 4',
          tooltip: 'Indentation',
        ),
        IdeStatusBarItem(ideEncodingLabel(snapshot.text), tooltip: 'Encoding'),
        IdeStatusBarItem(_eolLabel, tooltip: 'End of Line Sequence'),
        IdeStatusBarItem(
          IdeLanguageNames.forPath(active.path),
          tooltip: 'Language Mode',
        ),
        bell,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.workspace,
      builder: (context, _) {
        final commands = _allCommands();
        return CallbackShortcuts(
          bindings: _shortcuts(commands),
          child: Focus(
            focusNode: _workbenchFocus,
            onKeyEvent: _onWorkbenchKey,
            child: Material(
              color: IdeModernUI.shell,
              child: Stack(
                children: [
                  Column(
                    children: [
                      if (!WindowControls.drawsHeader) _titleBar(),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) =>
                              _split(constraints.biggest, commands),
                        ),
                      ),
                      _statusBar(),
                    ],
                  ),
                  // VS Code's toasts and center: 8px from the right, 36px
                  // from the bottom (`notificationsDialogs.css`).
                  Positioned(
                    right: 8,
                    bottom: 36,
                    top: CursorMetrics.titleBarHeight,
                    left: 8,
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: IdeNotificationsCenter(
                        notifications: _notifications,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 36,
                    left: 8,
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: IdeNotificationToasts(
                        notifications: _notifications,
                      ),
                    ),
                  ),
                  if (_quickPick != null || _quickInput != null)
                    Positioned.fill(
                      top: WindowControls.drawsHeader
                          ? 0
                          : CursorMetrics.titleBarHeight,
                      child: switch (_quickPick) {
                        final pick? => IdeQuickInput.pick(
                          key: _quickInputKey,
                          pick: pick,
                          onClose: _closeQuickInput,
                        ),
                        null => IdeQuickInput(
                          key: _quickInputKey,
                          initialText: _quickInput!,
                          itemsFor: _quickItems,
                          placeholderFor: _quickPlaceholder,
                          onClose: _closeQuickInput,
                          refresh: _quickRefresh,
                        ),
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// VS Code's title bar search box: opens Quick Open.
class _CommandCenter extends StatefulWidget {
  const _CommandCenter({
    required this.label,
    required this.shortcut,
    required this.onTap,
  });

  final String label;
  final String shortcut;
  final VoidCallback onTap;

  @override
  State<_CommandCenter> createState() => _CommandCenterState();
}

class _CommandCenterState extends State<_CommandCenter> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final foreground =
        colors[_hover
            ? 'commandCenter.activeForeground'
            : 'commandCenter.foreground'];
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380, minWidth: 160),
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          // `.command-center-center` (titlebarpart.css).
          decoration: BoxDecoration(
            color:
                colors[_hover
                    ? 'commandCenter.activeBackground'
                    : 'commandCenter.background'],
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color:
                  colors[_hover
                      ? 'commandCenter.activeBorder'
                      : 'commandCenter.border'],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Codicons.search, size: 14, color: foreground),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A draggable border between two panes, highlighted while hovered or
/// dragged. Its cursor says which ways it can go (`.monaco-sash.minimum`,
/// `.maximum`), and stays while dragged past where it stops; a double click
/// resets what it sizes.
class _Sash extends StatefulWidget {
  const _Sash({
    super.key,
    required this.onStart,
    required this.onDrag,
    required this.onReset,
    this.axis = Axis.horizontal,
    this.grip = true,
    this.canMoveBack = true,
    this.canMoveForward = true,
  });

  final VoidCallback onStart;

  /// How far the pointer is from where the drag began, along [axis].
  final ValueChanged<double> onDrag;
  final VoidCallback onReset;

  /// Which way it moves: between columns, or (vertical) between rows.
  final Axis axis;

  /// The Modern UI's grip dots at rest: not for a sash that stands for a
  /// hidden part.
  final bool grip;

  /// Whether it can go left (or up), and right (or down).
  final bool canMoveBack;
  final bool canMoveForward;

  MouseCursor get cursor => switch ((axis, canMoveBack, canMoveForward)) {
    (_, false, false) => SystemMouseCursors.basic,
    (Axis.horizontal, true, true) => SystemMouseCursors.resizeColumn,
    (Axis.horizontal, true, false) => SystemMouseCursors.resizeLeft,
    (Axis.horizontal, false, true) => SystemMouseCursors.resizeRight,
    (Axis.vertical, true, true) => SystemMouseCursors.resizeRow,
    (Axis.vertical, true, false) => SystemMouseCursors.resizeUp,
    (Axis.vertical, false, true) => SystemMouseCursors.resizeDown,
  };

  @override
  State<_Sash> createState() => _SashState();
}

class _SashState extends State<_Sash> {
  bool _hover = false;
  bool _dragging = false;
  double _start = 0;

  /// Over the window while dragging, with the sash's cursor: the pointer
  /// leaves the sash where it stops, and the cursor goes with it rather
  /// than turn into what it is over (VS Code's drag shield).
  OverlayEntry? _shield;

  @override
  void didUpdateWidget(_Sash oldWidget) {
    super.didUpdateWidget(oldWidget);
    // After this frame's build: the shield is the overlay's, not below us.
    if (_shield != null && widget.cursor != oldWidget.cursor) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _shield?.markNeedsBuild(),
      );
    }
  }

  @override
  void dispose() {
    _removeShield();
    super.dispose();
  }

  double _along(Offset position) =>
      widget.axis == Axis.horizontal ? position.dx : position.dy;

  void _begin(DragStartDetails details) {
    _start = _along(details.globalPosition);
    widget.onStart();
    setState(() => _dragging = true);
    if (Overlay.maybeOf(context) case final overlay?) {
      _shield = OverlayEntry(
        builder: (context) => MouseRegion(cursor: widget.cursor, opaque: true),
      );
      overlay.insert(_shield!);
    }
  }

  void _end() {
    _removeShield();
    setState(() => _dragging = false);
  }

  void _removeShield() {
    _shield
      ?..remove()
      ..dispose();
    _shield = null;
  }

  @override
  Widget build(BuildContext context) {
    final active = _hover || _dragging;
    final horizontal = widget.axis == Axis.horizontal;
    void update(DragUpdateDetails details) =>
        widget.onDrag(_along(details.globalPosition) - _start);
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: horizontal ? _begin : null,
        onHorizontalDragUpdate: horizontal ? update : null,
        onHorizontalDragEnd: horizontal ? (_) => _end() : null,
        onHorizontalDragCancel: horizontal ? _end : null,
        onVerticalDragStart: horizontal ? null : _begin,
        onVerticalDragUpdate: horizontal ? null : update,
        onVerticalDragEnd: horizontal ? null : (_) => _end(),
        onVerticalDragCancel: horizontal ? null : _end,
        onDoubleTap: widget.onReset,
        // At rest, the Modern UI's three grip dots; hovered or dragged,
        // the `sash.hoverBorder` filling the gap.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: horizontal ? IdeWorkbenchState._sashWidth : null,
          height: horizontal ? null : IdeWorkbenchState._sashWidth,
          color: active ? IdeModernUI.sashHover : Colors.transparent,
          child: active || !widget.grip
              ? null
              : CustomPaint(painter: _SashGripPainter(widget.axis)),
        ),
      ),
    );
  }
}

/// `.modern-ui .monaco-sash.vertical::after`: a 2px dot at the middle and
/// one 5px above and below it.
class _SashGripPainter extends CustomPainter {
  const _SashGripPainter(this.axis);

  final Axis axis;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = IdeModernUI.sashGrip;
    final center = size.center(Offset.zero);
    for (final d in const [-5.0, 0.0, 5.0]) {
      canvas.drawCircle(
        axis == Axis.horizontal
            ? center.translate(0, d)
            : center.translate(d, 0),
        1,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SashGripPainter oldDelegate) => oldDelegate.axis != axis;
}

/// An activity bar item: a 24px codicon in a 36px square; the active and
/// the hovered item sit on a rounded 32px box.
class _ActivityItem extends StatefulWidget {
  const _ActivityItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// A count shown on the icon (`NumberBadge`); none when null or 0.
  final int? badge;

  @override
  State<_ActivityItem> createState() => _ActivityItemState();
}

class _ActivityItemState extends State<_ActivityItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => IdeHover(
    message: widget.label,
    position: IdeHoverPosition.right,
    pointer: true,
    child: Semantics(
      button: true,
      selected: widget.selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox.square(
            dimension: IdeModernUI.activityItemSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(child: _icon()),
                if (widget.badge case final count? when count > 0)
                  Positioned(
                    top: 18,
                    right: 3,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: IdeModernUI.activityBadgeBackground,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        ideBadgeLabel(count),
                        style: TextStyle(
                          fontSize: 10,
                          height: 1,
                          color: IdeModernUI.activityBadgeForeground,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _icon() => Container(
    width: IdeModernUI.activityItemSize - 4,
    height: IdeModernUI.activityItemSize - 4,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: widget.selected
          ? IdeModernUI.activityActiveBackground
          : _hover
          ? IdeModernUI.activityHoverBackground
          : null,
      borderRadius: BorderRadius.circular(IdeModernUI.activityItemRadius),
    ),
    child: Icon(
      widget.icon,
      size: IdeModernUI.activityIconSize,
      color: widget.selected
          ? IdeModernUI.activityActiveForeground
          : _hover
          ? IdeModernUI.activityHoverForeground
          : IdeModernUI.activityForeground,
    ),
  );
}
