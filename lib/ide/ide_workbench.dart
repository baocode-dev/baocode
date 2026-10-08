import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../chat/chat_keys.dart';
import '../chat/composer/composer_files.dart' show ComposerFile;
import '../chat/composer/file_drop.dart';
import '../keybindings/default_keybindings.dart'
    show commandCatalog, openSettingsCommandId;
import '../keybindings/key_chord.dart';
import '../l10n/l10n.dart';
import '../keybindings/keybinding_service.dart';
import '../settings/user_settings.dart';
import '../theme/codicons.dart';
import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/back_to_chat_button.dart';
import '../workspace/editor_launcher.dart';
import '../workspace/pin_window_button.dart';
import '../workspace/title_bar_double_click.dart';
import '../workspace/window_controls.dart';
import '../workspace/workspace.dart';

import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart'
    show EditorContentChangeEvent, EditorDocumentModel;
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart'
    show EditorSurfaceController;
import 'package:bao_editor/monaco/flutter/editor_keybindings.dart'
    show editorChordPrefix;
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_editor/monaco/vs/editor/contrib/gotoError/browser/marker_navigation.dart';

import 'extensions/ide_extensions.dart';
import 'extensions/ide_extensions_view.dart';
import 'file_service.dart'
    show IdeFileListing, IdeHostFiles, localizedFileError, readFileBytes;
import 'git/commit_message.dart';
import 'git/git_change_editor.dart';
import 'git/git_checkout.dart';
import 'git/git_model.dart';
import 'git/git_repository.dart';
import 'git/ide_scm_view.dart';
import 'git/ide_timeline_view.dart';
import 'ide_breadcrumbs.dart';
import 'ide_button.dart';
import 'ide_color_theme_picker.dart';
import 'ide_columns.dart';
import 'ide_rows.dart';
import 'ide_commands.dart';
import 'ide_dialog.dart';
import 'ide_editor.dart';
import 'ide_editor_placeholder.dart';
import 'ide_image_preview.dart';
import 'markdown/markdown_paste.dart';
import 'markdown/markdown_preview.dart';
import 'ide_explorer.dart';
import 'ide_hover.dart';
import 'ide_layout.dart';
import 'ide_list.dart' show IdeKeyboardList;
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
import 'terminal/terminal_profile_service.dart';
import 'terminal/terminal_profiles.dart';
import 'terminal/terminal_service.dart';

part 'ide_workbench_keys.dart';

/// The IDE shell is kept mounted when the user returns to the conversation.
class IdeWorkbench extends StatefulWidget {
  const IdeWorkbench({
    super.key,
    required this.workspace,
    required this.project,
    required this.visible,
    required this.chat,
    required this.onBack,
    this.backLabel,
    this.editorBuilder,
    this.nativeEditorEnabled = const bool.fromEnvironment(
      'BAOCODE_NATIVE_EDITOR',
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
    this.recentFolders = const [],
    this.onOpenRecent,
    this.settings,
    this.viewState,
    this.onViewState,
    this.remote,
  });

  final IdeWorkspace workspace;

  /// The remote host the project is on, shown first in the status bar;
  /// null for this machine.
  final IdeRemoteIndicator? remote;

  /// Hands a file to its default app; tests replace it.
  @visibleForTesting
  static Future<bool> Function(String path) openInDefaultApp = openExternal;

  /// What a paste in a markdown document reads; tests replace it.
  @visibleForTesting
  static MarkdownClipboard markdownClipboard = const SystemMarkdownClipboard();

  final Project project;
  final bool visible;
  final Widget chat;
  final VoidCallback onBack;

  /// The title bar's way back's label: Back to Chat, by default; in a
  /// window of its own, Show Chat Window.
  final String? backLabel;

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

  /// The folders opened last, most recent first, for the welcome page of
  /// a window without one; [onOpenRecent] opens one.
  final List<String> recentFolders;
  final ValueChanged<String>? onOpenRecent;

  /// settings.json: where Source Control keeps the choices made in its
  /// dialogs; none under test.
  final UserSettings? settings;

  /// How the last run left this folder's window: the side bar's and the
  /// chat's widths, the panel's height, which parts and view showed, and
  /// the editors open (as VS Code keeps a workspace's). Restored once,
  /// as the workbench is made.
  final Map<String, Object?>? viewState;

  /// Told how the window is now, as it changes (a moment after), to keep
  /// for the next run.
  final ValueChanged<Map<String, Object?>>? onViewState;

  @override
  State<IdeWorkbench> createState() => IdeWorkbenchState();
}

/// The side views of the activity bar. The outline is a pane of the
/// explorer, as in VS Code; there is no Run and Debug view.
enum IdeSideView { explorer, search, sourceControl, extensions }

/// A navigation history entry (Go Back / Go Forward).
typedef _NavigationEntry = ({String path, LspPosition position});

/// A chord being typed (see [IdeWorkbenchState._chord]): its label, the
/// chords pressed and its status message.
typedef _Chord = ({String label, List<KeyChord> chords, String message});

class IdeWorkbenchState extends State<IdeWorkbench> {
  final _editorKey = GlobalKey<IdeEditorState>();

  /// The markdown files shown as their source rather than their preview,
  /// the last switched last (a few hundred kept, with the window's state).
  final LinkedHashSet<String> _markdownSources = LinkedHashSet();
  static const _keptMarkdownSources = 300;

  /// The line (one-based) each markdown document's preview shows first:
  /// where it was, or the caret's line in its source.
  final Map<IdeDocument, int> _previewLines = {};
  final FocusNode _workbenchFocus = FocusNode(debugLabel: 'ide workbench');
  final FocusNode _explorerFocus = FocusNode(debugLabel: 'ide explorer');
  late IdeExplorerController _explorer;
  late IdeFileIndex _fileIndex;
  final IdeRecentList _recentFiles = IdeRecentList();

  /// The open editors' keys, the most recently active first.
  final IdeRecentList _editorHistory = IdeRecentList();

  /// Open Next / Previous Recently Used Editor's stack and where they are
  /// in it (upstream `recentlyUsedEditorsStack`), while they run.
  List<String>? _recentlyUsedStack;
  int _recentlyUsedIndex = 0;
  bool _navigatingRecentlyUsed = false;

  /// The open files' changes, watched for [_lastEdit].
  final Map<EditorDocumentModel, StreamSubscription<EditorContentChangeEvent>>
  _editWatches = {};

  /// Where the last edit of an open file ended (Go to Last Edit Location).
  _NavigationEntry? _lastEdit;

  /// Whether the last Go Back / Go Forward went back (for Go Previous).
  bool _lastNavigationBack = false;

  /// Whether the panel is maximized (Toggle Maximized Panel).
  bool _panelMaximized = false;

  /// Around the side bar and the chat, for `sideBarFocus` and
  /// `auxiliaryBarFocus`.
  final FocusNode _sidebarFocus = FocusNode(
    debugLabel: 'ide side bar',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final FocusNode _chatFocus = FocusNode(
    debugLabel: 'ide chat',
    canRequestFocus: false,
    skipTraversal: true,
  );
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

  /// Whether the chat's sash is being dragged: snapped shut, it stays till
  /// the drag ends, so the drag can bring the chat back.
  bool _chatSashDragging = false;

  /// Which parts show: the workspace's, for the window's header to toggle
  /// as well (see [IdeLayout]); [_layoutChanged] follows it.
  IdeLayout get _layout => widget.workspace.layout;
  bool get _sidebarShown => _layout.sidebar;
  set _sidebarShown(bool value) => _layout.sidebar = value;
  bool get _chatShown => _layout.chat;

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
  String? _activeKey;

  /// The Source Control view's message and state, while other views show.
  late IdeScmSession _scm = IdeScmSession(settings: widget.settings);

  /// The explorer's open panes (Folders first, then Outline and Timeline,
  /// collapsed as VS Code starts them), and what the timeline follows.
  final Set<String> _explorerPanes = {'folder'};
  final IdeTimelineController _timeline = IdeTimelineController();
  final _explorerTree = GlobalKey<IdeExplorerState>();

  /// The Search view's inputs and results, while other views show.
  late final IdeSearchSession _search = IdeSearchSession(
    engine: (root, query) => switch (widget.workspace) {
      // A remote project's files are searched there.
      IdeWorkspace(hasFolder: true, files: final IdeHostFiles files) =>
        files.searchText(root, query),
      IdeWorkspace(hasFolder: true) => widget.textSearch(root, query),
      _ => _searchOpenFiles(query),
    },
  );
  final _searchKey = GlobalKey<IdeSearchViewState>();

  /// Whether the project's files are this machine's (not a remote host's):
  /// only then are they shown in the file manager, opened in other apps,
  /// or moved to the trash.
  bool get _local => widget.workspace.files is! IdeHostFiles;
  final _scmKey = GlobalKey<IdeScmViewState>();
  IdeGitRepository? _git;

  /// The Extensions view's list and search, made when it first shows.
  IdeExtensionsSession? _extensions;

  /// What the activity bar and the status bar show of [_git], rebuilt
  /// only when these change.
  int _gitCount = 0;
  String? _gitBranch;

  /// The status the open revisions were last read against.
  IdeGitState? _gitState;

  /// The quick input's text while it is open (its prefix picks the mode).
  String? _quickInput;

  /// The quick pick (e.g. the color themes) or input box the quick input
  /// shows instead.
  IdeQuickInputModel? _quickModel;
  GlobalKey<IdeQuickInputState> _quickInputKey = GlobalKey();
  FocusNode? _focusBeforeQuickInput;

  /// How the quick input [_quickInput] shows opens (see
  /// [IdeQuickInput.itemActivation], [IdeQuickInput.quickNavigate],
  /// [IdeQuickInput.hideInput]).
  IdeQuickPickFocus _quickActivation = IdeQuickPickFocus.first;
  List<KeyChord>? _quickNavigateChords;
  bool _quickHideInput = false;

  /// The chord being typed (upstream `_currentChords`).
  _Chord? _chord;
  Timer? _chordChecker;

  /// The status bar's message (upstream `INotificationService.status`),
  /// after the items on the left.
  String? _statusMessage;
  Timer? _statusMessageTimer;

  /// Reads the Git status again when the app comes back to the front: a
  /// pull or a commit made elsewhere may have changed it unseen.
  AppLifecycleListener? _lifecycle;

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

  /// The Problems and References lists' focused rows and collapsed files.
  final _problemsList = IdePanelListModel();
  final _referencesList = IdePanelListModel();
  MarkerList<LspDiagnostic>? _markers;
  final List<_NavigationEntry> _backStack = [];
  final List<_NavigationEntry> _forwardStack = [];

  /// `editor.formatOnSave`, kept in settings.json as VS Code keeps it.
  bool get _formatOnSave => _setting('editor.formatOnSave', false);
  set _formatOnSave(bool value) => _setSetting('editor.formatOnSave', value);

  /// The editor's Git blame (`git.blame.editorDecoration.enabled`), kept
  /// as [_formatOnSave].
  bool get _gitBlame => _setting('git.blame.editorDecoration.enabled', true);
  set _gitBlame(bool value) =>
      _setSetting('git.blame.editorDecoration.enabled', value);

  /// The settings toggled here not written to settings.json yet (or with
  /// none to write to, under test).
  final Map<String, bool> _settingsSet = {};

  bool _setting(String key, bool fallback) =>
      _settingsSet[key] ??
      switch (widget.settings?[key]) {
        final bool value => value,
        _ => fallback,
      };

  void _setSetting(String key, bool value) {
    _settingsSet[key] = value;
    unawaited(
      widget.settings?.update(key, value).catchError((Object error) {
        // A settings file that does not parse is left as it is; its error
        // is shown.
        debugPrint('$key not kept: $error');
      }),
    );
  }

  /// Whether the editors kept are being opened again: until they are, the
  /// window is not kept, lest those not open yet be forgotten.
  bool _restoring = false;
  Timer? _keepTimer;
  String? _kept;

  /// [IdeWorkbench.viewState] applied: the widths, the view and the
  /// editors (which parts show the workspace's layout was made with, see
  /// [IdeLayout.restore]).
  void _restoreView() {
    final kept = widget.viewState;
    if (kept == null) return;
    double? size(String key) => switch (kept[key]) {
      final num value when value.isFinite && value > 0 => value.toDouble(),
      _ => null,
    };
    _sidebarWidth = size('sidebarWidth') ?? _sidebarWidth;
    _chatWidth = size('chatWidth') ?? _chatWidth;
    _panelHeight = size('panelHeight');
    if (kept['view'] case final String name) {
      _view = IdeSideView.values.asNameMap()[name] ?? _view;
    }
    if (kept['markdownSource'] case final List<Object?> paths) {
      _markdownSources.addAll(paths.whereType<String>());
    }
    // VS Code makes a terminal when its view shows with none.
    if (_layout.panel == IdePanelTab.terminal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _terminals?.ensureTerminal();
      });
    }
    final editors = switch (kept['editors']) {
      final List<Object?> paths => paths.whereType<String>().toList(),
      _ => const <String>[],
    };
    if (editors.isEmpty) return;
    _restoring = true;
    unawaited(
      widget.workspace
          .restore(editors, active: kept['active'] as String?)
          .whenComplete(() {
            _restoring = false;
            _keepViewSoon();
          }),
    );
  }

  /// The window as [IdeWorkbench.onViewState] is told it.
  Map<String, Object?> get _viewState {
    final editors = [
      for (final doc in widget.workspace.documents)
        if (doc.label == null && (doc.isFile || doc.isMedia)) doc.path,
    ];
    final active = widget.workspace.active?.key;
    return {
      'sidebarWidth': _sidebarWidth,
      'chatWidth': _chatWidth,
      'panelHeight': ?_panelHeight,
      ..._layout.toJson(),
      'view': _view.name,
      if (_markdownSources.isNotEmpty) 'markdownSource': [..._markdownSources],
      'editors': editors,
      if (editors.contains(active)) 'active': active,
    };
  }

  /// A moment after a change, as a sash dragged changes it at each frame.
  void _keepViewSoon() {
    if (widget.onViewState == null || _restoring) return;
    _keepTimer ??= Timer(const Duration(milliseconds: 300), _keepView);
  }

  void _keepView() {
    _keepTimer?.cancel();
    _keepTimer = null;
    final keep = widget.onViewState;
    if (keep == null || _restoring) return;
    final state = _viewState;
    final json = jsonEncode(state);
    if (json == _kept) return;
    _kept = json;
    keep(state);
  }

  /// settings.json read again: what it says now, written here or not.
  void _settingsChanged() {
    _settingsSet.clear();
    setState(() {});
  }

  static const _sashWidth = IdeModernUI.gap;

  IdeEditorState? get _editor => _editorKey.currentState;

  /// The active markdown document's preview, when it shows.
  IdeMarkdownPreviewState? get _preview => switch (widget.workspace.active) {
    final active? => GlobalObjectKey<IdeMarkdownPreviewState>(
      active,
    ).currentState,
    null => null,
  };

  /// Whether [doc] can show as a markdown preview: a markdown file's own
  /// tab (or a revision's), not its diff.
  bool _hasPreview(IdeDocument doc) =>
      isMarkdownPath(doc.path) &&
      doc.diff == null &&
      !doc.isMedia &&
      doc.openError == null;

  /// Whether [doc] shows as its preview: markdown files do, unless switched
  /// to their source.
  bool _previewing(IdeDocument? doc) =>
      doc != null && _hasPreview(doc) && !_markdownSources.contains(doc.path);

  /// The edits the active editor holds back (a field of the fallback
  /// editor) put in its document.
  Future<void> _flushEditor() async {
    await _editor?.flush();
  }

  /// The keyboard to the active editor, or the preview.
  void _focusEditor() {
    if (_editor case final editor?) {
      editor.focus();
    } else {
      _preview?.focus();
    }
  }

  /// [line] (one-based) of the active document shown: the caret there in
  /// its editor, or its block at the top of its preview.
  void _revealLine(int line, [int column = 1]) {
    if (_editor case final editor?) {
      unawaited(editor.revealLine(line, column));
    } else {
      _preview?.revealLine(line, column);
    }
  }

  void _revealRange(LspRange range, {bool select = false}) {
    if (_editor case final editor?) {
      editor.revealRange(range, select: select);
    } else {
      _preview?.revealLine(range.start.line + 1);
    }
  }

  /// Shows the active markdown document's preview, or its source: in
  /// either, about where the other was (the caret's block; the source of
  /// the block at the top), or the source at [at] (a line and column,
  /// one-based: where the preview was double clicked).
  Future<void> _setMarkdownPreview(
    bool preview, {
    ({int line, int column})? at,
  }) async {
    final doc = widget.workspace.active;
    if (doc == null || !_hasPreview(doc) || _previewing(doc) == preview) {
      return;
    }
    int? line;
    var column = 1;
    if (preview) {
      await _flushEditor();
      _previewLines[doc] = _caretPosition.lineNumber;
      _markdownSources.remove(doc.path);
    } else {
      line = at?.line ?? _preview?.topLine;
      column = at?.column ?? 1;
      _markdownSources
        ..remove(doc.path)
        ..add(doc.path);
      while (_markdownSources.length > _keptMarkdownSources) {
        _markdownSources.remove(_markdownSources.first);
      }
    }
    if (!mounted) return;
    setState(() {});
    _keepViewSoon();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(widget.workspace.active, doc)) return;
      if (line != null) _revealLine(line, column);
      if (at != null || line == null) _focusEditor();
    });
  }

  /// Find in a preview: in its source, as the preview has no find.
  void _find({bool replace = false}) {
    if (_previewing(widget.workspace.active)) {
      _setStatusMessage(
        context.l10n.markdownFindInSource,
        hideAfter: const Duration(seconds: 4),
      );
      unawaited(
        _setMarkdownPreview(false).then((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            replace ? _editor?.openReplace() : _editor?.openFind();
          });
        }),
      );
      return;
    }
    replace ? _editor?.openReplace() : _editor?.openFind();
  }

  /// Save: the editor's, or the preview's document.
  Future<void> _save() async {
    if (_editor case final editor?) return editor.save();
    final doc = widget.workspace.active;
    if (doc == null) return;
    try {
      await widget.workspace.save(doc);
    } catch (error) {
      _report(error);
    }
  }

  /// Opens the file a markdown preview's link goes to: at its line for
  /// `#L12`, at its heading for a markdown file's `#anchor`.
  Future<void> _openLinked(String path, String? fragment) async {
    final line = switch (RegExp(r'^L(\d+)').firstMatch(fragment ?? '')) {
      final match? => int.parse(match[1]!),
      null => null,
    };
    await _open(path, line: line, focusEditor: true);
    if (!mounted || line != null || fragment == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _preview?.revealAnchor(fragment);
    });
  }

  /// [doc]'s preview.
  Widget _markdownPreview(IdeDocument doc) {
    final files = widget.workspace.files;
    return IdeMarkdownPreview(
      key: GlobalObjectKey<IdeMarkdownPreviewState>(doc),
      path: doc.path,
      model: doc.model,
      readOnly: doc.readOnly,
      readBytes: switch (files) {
        final IdeHostFiles files => files.readBytes,
        _ => readFileBytes,
      },
      // A remote project's host is Linux or macOS: POSIX paths.
      pathContext: _local ? p.context : p.posix,
      initialLine: _previewLines[doc],
      onLeave: (line) {
        if (line != null) _previewLines[doc] = line;
      },
      onEdited: () => widget.workspace.notifyDocumentChanged(doc),
      onEdit: (line, column) => unawaited(
        _setMarkdownPreview(false, at: (line: line, column: column)),
      ),
      onOpenFile: (path, fragment) => unawaited(_openLinked(path, fragment)),
      onOpenExternal: (uri) => unawaited(openExternal(uri.toString())),
    );
  }

  /// Pastes and drops of files into the project's markdown documents.
  MarkdownPaste _markdownPaste() {
    final l10n = context.l10n;
    final workspace = widget.workspace;
    return MarkdownPaste(
      files: workspace.files,
      l10n: l10n,
      root: workspace.hasFolder ? workspace.root : null,
      // A remote project's host is Linux or macOS; the clipboard's files
      // are this machine's, uploaded there.
      context: _local ? p.context : p.posix,
      remote: !_local,
      clipboard: IdeWorkbench.markdownClipboard,
      confirmLarge: (name, size) async {
        if (!mounted) return false;
        final pick = await showIdeDialog(
          context,
          type: IdeDialogType.question,
          message: l10n.markdownPasteLargeTitle,
          detail: l10n.markdownPasteLargeMessage(name, ideFormatSize(size)),
          buttons: [l10n.markdownPasteLargeConfirm],
        );
        return pick == 0;
      },
      report: (message) {
        if (mounted) _notifications.notify(IdeSeverity.error, message);
      },
    );
  }

  /// A paste in [doc]'s source: a markdown document's files and pictures
  /// put beside it and linked to (see [pasteMarkdownLinks]).
  Future<bool> _pasteInEditor(
    IdeDocument doc,
    EditorSurfaceController editor,
  ) async {
    if (!isMarkdownPath(doc.path) || doc.readOnly || !mounted) return false;
    final version = doc.model.version;
    final pasted = await pasteMarkdownLinks(
      editor,
      () => _markdownPaste().paste(doc.path),
      onMoved: () {
        if (mounted) {
          _notifications.notify(
            IdeSeverity.info,
            context.l10n.markdownPasteMoved,
          );
        }
      },
    );
    if (doc.model.version != version) {
      widget.workspace.notifyDocumentChanged(doc);
    }
    return pasted;
  }

  /// [editor], taking the files other apps drop on it when it is a
  /// markdown document's (see [_dropOnMarkdown]).
  Widget _markdownDrops(IdeDocument? active, Widget editor) {
    if (active == null ||
        !isMarkdownPath(active.path) ||
        active.readOnly ||
        active.diff != null ||
        active.openError != null) {
      return editor;
    }
    return FileDropRegion(delegate: _markdownDrop, child: editor);
  }

  late final _markdownDrop = _MarkdownDrop(
    (position, files) => unawaited(_dropOnMarkdown(position, files)),
  );

  /// Files dropped from other apps on the active markdown document: put
  /// beside it and linked to, at the caret, or after the block they were
  /// dropped on.
  Future<void> _dropOnMarkdown(
    Offset position,
    List<ComposerFile> files,
  ) async {
    final doc = widget.workspace.active;
    if (doc == null || !isMarkdownPath(doc.path) || doc.readOnly) return;
    final outcome = await _markdownPaste().drop(doc.path, files);
    if (!mounted || outcome is! MarkdownPasteLinks) return;
    if (!identical(widget.workspace.active, doc)) {
      insertMarkdownAtEnd(doc.model, outcome.text);
      widget.workspace.notifyDocumentChanged(doc);
    } else if (_preview case final preview?) {
      preview.insert(outcome.text, position: position);
    } else {
      _editor?.insertAtCaret(outcome.text);
    }
  }

  /// [setState], for the commands of ide_workbench_keys.dart.
  void _refresh(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_onChordKey);
    FocusManager.instance.addLateKeyEventHandler(_onLateKey);
    KeybindingService.instance.addListener(_keybindingsChanged);
    _registerCommandKeybindings();
    _notifications.addListener(_notificationsChanged);
    widget.settings?.addListener(_settingsChanged);
    widget.remote?.addListener(_remoteChanged);
    if (widget.terminalBackend.supported) {
      _terminals = TerminalService(
        root: widget.workspace.root,
        backend: widget.terminalBackend,
      )..addListener(_terminalsChanged);
    }
    _restoreView();
    _attach();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_git?.refresh()),
    );
    IdeLanguageNames.ensureLoaded(() {
      if (mounted) setState(() {});
    });
    _readBranch();
    if (widget.visible) _focusSoon();
  }

  /// Whether the display language can be read: the recommendations
  /// [initState] would make wait for it.
  bool _localized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_localized) return;
    _localized = true;
    _recommendServers();
  }

  void _attach() {
    final workspace = widget.workspace;
    workspace.layout.terminals = _terminals != null;
    _explorer = IdeExplorerController(
      files: workspace.files,
      root: workspace.root,
      // Without a folder, no tree to keep current.
      watch: workspace.hasFolder
          ? workspace.watchFolder
          : (_) => const Stream.empty(),
    );
    _fileIndex = IdeFileIndex(
      workspace.files,
      workspace.root,
      // Without a folder, the open files alone.
      lister: workspace.hasFolder
          ? null
          : (_, _) async => IdeFileListing([
              for (final doc in workspace.documents)
                if (doc.isFile && doc.label == null) doc.path,
            ]),
    );
    final languages = _languages = workspace.languages;
    _symbols = languages == null ? null : IdeDocumentSymbols(languages)
      ?..addListener(_symbolsChanged);
    _quickRefresh = Listenable.merge([_fileIndex, ?_symbols]);
    languages?.addListener(_languagesChanged);
    _editRequests = languages?.workspaceEdits.listen(_applyEditRequest);
    _markers = null;
    _backStack.clear();
    _forwardStack.clear();
    _navigationHere = null;
    _navigationFile = null;
    _references = null;
    _problemsList.clear();
    _referencesList.clear();
    _lastEdit = null;
    workspace.addListener(_workspaceChanged);
    workspace.layout.addListener(_layoutChanged);
    _shownPanel = workspace.layout.panel;
    _activeKey = null;
    _workspaceChanged();
    _git = workspace.git?..addListener(_gitChanged);
    _gitChanged();
    // New terminals start in the project; those running stay where they are.
    _terminals?.root = workspace.root;
  }

  void _detach(IdeWorkspace workspace) {
    workspace.removeListener(_workspaceChanged);
    for (final watch in _editWatches.values) {
      unawaited(watch.cancel());
    }
    _editWatches.clear();
    workspace.layout.removeListener(_layoutChanged);
    _git?.removeListener(_gitChanged);
    _git = null;
    _gitState = null;
    _scm.dispose();
    _scm = IdeScmSession(settings: widget.settings);
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
    // The status bar's branch checks out once there is a repository.
    final loaded = (state == null) != (_gitState == null);
    // The texts at revisions follow the repository, as `git:` documents do.
    if (!identical(state, _gitState)) {
      _gitState = state;
      if (state != null) unawaited(widget.workspace.reloadRevisions());
    }
    final count = state?.count ?? 0;
    final branch = state?.head.branch;
    if (count == _gitCount && branch == _gitBranch && !loaded) return;
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

  /// The keybindings of [IdeWorkbench.commands] the defaults do not have.
  void _registerCommandKeybindings() =>
      KeybindingService.instance.registerExtraDefaults([
        for (final command in widget.commands) ...command.keybindingEntries,
      ]);

  /// Labels (the palette's, the tooltips') follow the keybindings.
  void _keybindingsChanged() {
    if (mounted) setState(() {});
  }

  /// The remote indicator follows the connection.
  void _remoteChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(IdeWorkbench oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.commands, widget.commands)) {
      _registerCommandKeybindings();
    }
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings?.removeListener(_settingsChanged);
      widget.settings?.addListener(_settingsChanged);
    }
    if (oldWidget.remote != widget.remote) {
      oldWidget.remote?.removeListener(_remoteChanged);
      widget.remote?.addListener(_remoteChanged);
    }
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
    FocusManager.instance.removeLateKeyEventHandler(_onLateKey);
    KeybindingService.instance.removeListener(_keybindingsChanged);
    widget.settings?.removeListener(_settingsChanged);
    widget.remote?.removeListener(_remoteChanged);
    _keepView();
    _chordChecker?.cancel();
    _statusMessageTimer?.cancel();
    _lifecycle?.dispose();
    // A quick pick or input box going with the workbench hides (the color
    // themes one applies the theme it started with again).
    _quickModel?.onDidHide?.call();
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
    _problemsList.dispose();
    _referencesList.dispose();
    _sidebarFocus.dispose();
    _chatFocus.dispose();
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
    _keepViewSoon();
    _symbols?.update(widget.workspace.active);
    _forgetClosedNavigation();
    _watchEdits();
    final active = widget.workspace.active;
    if (widget.workspace.takeReveal() case final range? when active != null) {
      final location = IdeLocation(active.path, range);
      // Once the editor shows it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _layout.showEditor();
        unawaited(
          _openLocation(
            location,
            select: true,
            record: false,
            afterReveal: _focusEditor,
          ),
        );
      });
    }
    if (active?.key == _activeKey) return;
    _activeKey = active?.key;
    // Upstream resets the recently used stack when an editor comes to the
    // front otherwise than from it.
    if (!_navigatingRecentlyUsed) {
      _recentlyUsedStack = null;
      _recentlyUsedIndex = 0;
    }
    if (active == null) return;
    _editorHistory.add(active.key);
    final path = active.path;
    _activeFileChanged(path);
    // Upstream's `showEditorIfHidden`: an editor opened ends the chat's
    // maximizing, and has the side bar give way to it rather than it to
    // the side bar.
    _layout.showEditor();
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

  /// Hands [path] to the app the system opens it with (a file the IDE
  /// does not show: a PDF, a video…).
  Future<void> _openInDefaultApp(String path) async {
    if (await IdeWorkbench.openInDefaultApp(path) || !mounted) return;
    _report(context.l10n.openInDefaultAppFailed(p.basename(path)));
  }

  /// Errors are error notifications, as VS Code's are.
  void _report(Object error) {
    if (!mounted) return;
    _notifications.notify(
      IdeSeverity.error,
      localizedFileError(context.l10n, error),
    );
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
      await _flushEditor();
      await widget.workspace.open(path);
      if (!mounted) return;
      // The active one opened again changes nothing [_workspaceChanged]
      // follows, but is asked for all the same.
      _layout.showEditor();
      if (line != null || range != null || focusEditor) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (range != null) {
            _revealRange(range, select: select);
            afterReveal?.call();
          } else if (line != null) {
            _revealLine(line, column ?? 1);
          } else {
            _focusEditor();
          }
        });
      }
    } catch (error) {
      _report(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens [resource]'s change as the Git extension does (see
  /// git_change_editor.dart): a diff editor of its two sides, or its one
  /// side; [head], its original (Open File (HEAD)).
  Future<void> _openChange(
    IdeGitResource resource, {
    bool head = false,
    bool focusEditor = false,
  }) async {
    final git = _git;
    final state = git?.state;
    if (git == null || state == null || _busy) return;
    final change = IdeGitChangeEditor.of(
      resource,
      staged: state.group(IdeGitGroup.staged),
      l10n: context.l10n,
    );
    Future<String> Function() read(IdeGitSide side) =>
        () => git.service.show(side.ref!, side.path);
    final workspace = widget.workspace;
    final left = change.left;
    final right = change.right;
    final Future<void> Function() open;
    if (head) {
      if (left == null) {
        _notifications.notify(
          IdeSeverity.warning,
          context.l10n.wbHeadNotAvailable(p.basename(resource.path)),
        );
        return;
      }
      open = () => workspace.openRevision(
        resource.path,
        label: 'HEAD',
        read: read(left),
      );
    } else if (right == null) {
      // Upstream's command fails without a side: the file, where it is.
      if (resource.status == IdeGitStatus.bothDeleted) return;
      open = () => workspace.open(resource.path);
    } else if (left == null) {
      // The one side: the file's own tab, or its text at a revision.
      open = right.isFile
          ? () => workspace.open(right.path)
          : () => workspace.openRevision(
              right.path,
              label: change.label,
              read: read(right),
            );
    } else {
      open = () => workspace.openDiff(
        right.path,
        label: change.label,
        original: read(left),
        modified: right.isFile ? null : read(right),
      );
    }
    setState(() => _busy = true);
    try {
      await _flushEditor();
      await open();
      if (mounted && focusEditor) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusEditor();
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
      await _flushEditor();
      widget.workspace.select(doc.key);
    } catch (error) {
      _report(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// VS Code's save confirmation: Save, Don't Save or Cancel.
  Future<String?> _confirmClose(IdeDocument doc) async {
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
  Future<void> _closeDocs(List<IdeDocument> docs) async {
    if (_busy || docs.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _flushEditor();
      for (final doc in docs) {
        if (!mounted) return;
        if (!widget.workspace.documents.contains(doc)) continue;
        if (doc.dirty) {
          final choice = await _confirmClose(doc);
          if (choice == null || !mounted) return;
          if (choice == 'save' && doc.isUntitled) {
            // Saved as a file, that is what closes; not saved, nothing.
            final saved = await widget.workspace.saveAs(doc);
            if (saved == null || !mounted) return;
            widget.workspace.close(saved);
            continue;
          }
          if (choice == 'save') await widget.workspace.save(doc);
        }
        await _editor?.closeDocument(doc);
        if (doc.label == null && !doc.isUntitled) {
          _closedEditors.remove(doc.path);
          _closedEditors.add(doc.path);
        }
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
      await _flushEditor();
      for (final doc in widget.workspace.documents) {
        if (doc.dirty) await widget.workspace.save(doc);
      }
    } catch (error) {
      _report(error);
    }
  }

  String _relative(String path) =>
      p.relative(path, from: widget.workspace.root);

  /// New Text File: an untitled one, its editor focused.
  void _newUntitled() {
    final doc = widget.workspace.newUntitled();
    unawaited(_select(doc));
  }

  /// Save As: the active editor's text to a file asked for, its tab then
  /// that file's.
  Future<void> _saveAs() async {
    final doc = widget.workspace.active;
    if (doc == null) return;
    try {
      await _flushEditor();
      final saved = await widget.workspace.saveAs(doc);
      if (saved != null && mounted) _focusSoon();
    } catch (error) {
      _report(error);
    }
  }

  /// Search without a folder: the open files' text, as upstream searches
  /// the open editors alone in an empty window.
  Stream<Object> _searchOpenFiles(IdeTextQuery query) async* {
    final pattern = query.toRegExp();
    var count = 0;
    var limitHit = false;
    final searched = <String>{};
    for (final doc in [...widget.workspace.documents]) {
      if (!doc.isFile || !searched.add(doc.path)) continue;
      final matches = <IdeTextMatch>[];
      for (final (line, text) in doc.text.split(_lineBreak).indexed) {
        for (final match in pattern.allMatches(text)) {
          if (match.end == match.start) continue;
          if (count == query.maxResults) {
            limitHit = true;
            break;
          }
          count++;
          matches.add(IdeTextMatch(line, match.start, match.end, text));
        }
      }
      if (matches.isNotEmpty) yield IdeFileMatches(doc.path, matches);
      if (limitHit) break;
    }
    yield IdeTextSearchComplete(limitHit: limitHit);
  }

  static final _lineBreak = RegExp(r'\r\n|\r|\n');

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
      case IdeTabAction.revealInFileManager:
        unawaited(WindowControls.revealInFileManager(doc.path));
      case IdeTabAction.openInDefaultApp:
        unawaited(_openInDefaultApp(doc.path));
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
      await _flushEditor();
      if (mounted) widget.onBack();
    } catch (error) {
      _report(error);
    }
  }

  // --- Language features ---------------------------------------------------

  // Navigation history (Go Back / Go Forward), after VS Code's
  // `EditorNavigationStack` (src/vs/workbench/services/history/browser/
  // historyService.ts at 6a598d4a13031703d483d103c1d934a36ad27971): where
  // the caret was is recorded when another file comes to the front (from
  // the explorer, Quick Open, search, a tab, a definition), and when the
  // caret jumps more than [_navigationThreshold] lines in the same file
  // (upstream `TEXT_EDITOR_SELECTION_THRESHOLD`); closer moves only update
  // where it is. Entries of files that close go (upstream keeps closed
  // editors; here their tabs are gone).

  /// Lines a move must span to be a navigation of its own.
  static const _navigationThreshold = 10;

  /// Where the caret was last seen, in which file; null when the active
  /// file's caret was not reported since it came to the front (it is where
  /// the last one reported was: the editor reports changes only).
  _NavigationEntry? _navigationHere;

  /// The file at the front when [_navigationHere] was last reset.
  String? _navigationFile;

  /// Set while Go Back / Go Forward moves: that move records nothing.
  bool _navigating = false;

  _NavigationEntry? _here() {
    final path = widget.workspace.active?.path;
    if (path == null) return null;
    if (_navigationHere case final here? when here.path == path) return here;
    return (
      path: path,
      position: LspPosition(
        _caretPosition.lineNumber - 1,
        _caretPosition.column - 1,
      ),
    );
  }

  /// Records [entry] for Go Back, unless it is the last one; a new
  /// navigation drops what Go Forward had.
  void _recordNavigation(_NavigationEntry? entry) {
    if (entry == null || _navigating) return;
    _lastNavigationBack = false;
    if (_backStack.isEmpty ||
        _backStack.last.path != entry.path ||
        _backStack.last.position != entry.position) {
      _backStack.add(entry);
      if (_backStack.length > 50) _backStack.removeAt(0);
    }
    _forwardStack.clear();
  }

  /// The caret moved to [position] in the active file.
  void _caretMoved(Position position) {
    final path = widget.workspace.active?.path;
    if (path == null) return;
    final now = (
      path: path,
      position: LspPosition(position.lineNumber - 1, position.column - 1),
    );
    final before = _navigationHere;
    if (before != null &&
        before.path == path &&
        (before.position.line - now.position.line).abs() >
            _navigationThreshold) {
      _recordNavigation(before);
    }
    _navigationHere = now;
  }

  /// Another file came to the front: where the caret was in the one
  /// before is recorded, if that one is still open.
  void _activeFileChanged(String path) {
    final previous = _navigationFile;
    final before =
        _navigationHere ??
        (previous == null
            ? null
            : (
                path: previous,
                position: LspPosition(
                  _caretPosition.lineNumber - 1,
                  _caretPosition.column - 1,
                ),
              ));
    if (before != null &&
        before.path != path &&
        widget.workspace.documents.any((doc) => doc.path == before.path)) {
      _recordNavigation(before);
    }
    _navigationFile = path;
    _navigationHere = null;
  }

  /// Drops the entries of files no longer open.
  void _forgetClosedNavigation() {
    final open = {for (final doc in widget.workspace.documents) doc.path};
    bool closed(_NavigationEntry entry) => !open.contains(entry.path);
    if (!_backStack.any(closed) && !_forwardStack.any(closed)) return;
    _backStack.removeWhere(closed);
    _forwardStack.removeWhere(closed);
  }

  /// Opens [location] (another file too), recording where the caret was
  /// for Go Back.
  Future<void> _openLocation(
    IdeLocation location, {
    bool select = false,
    bool record = true,
    VoidCallback? afterReveal,
  }) async {
    if (record) _recordNavigation(_here());
    if (widget.workspace.active?.path == location.path) {
      _revealRange(location.range, select: select);
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

  /// Go Back (⌃-) / Go Forward (⌃⇧-), and the mouse's back and forward
  /// buttons.
  void _navigate({required bool back}) {
    final from = back ? _backStack : _forwardStack;
    final to = back ? _forwardStack : _backStack;
    if (from.isEmpty) return;
    final here = _here();
    if (here != null) to.add(here);
    final entry = from.removeLast();
    _lastNavigationBack = back;
    _navigating = true;
    unawaited(
      _openLocation(
        IdeLocation(entry.path, LspRange(entry.position, entry.position)),
        record: false,
      ).whenComplete(() {
        // The caret lands after a frame: that move is this navigation's.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _navigating = false;
          _navigationHere = entry;
        });
        WidgetsBinding.instance.scheduleFrame();
      }),
    );
    if (mounted) setState(() {});
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
    _referencesList.clear();
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

  /// Create New Terminal (⌃⇧`), shown and focused: on [profile]'s shell,
  /// else the default profile's.
  void _newTerminal({TerminalProfile? profile}) {
    _terminals?.create(profile: profile);
    _showTerminal();
  }

  /// Create New Terminal (With Profile): the profile [args] names
  /// (`{"profileName": "bash"}`, upstream's keybinding argument), else the
  /// one picked.
  Future<void> _newTerminalWithProfile([Object? args]) async {
    final profiles = _terminals?.profiles;
    if (profiles == null) return;
    await profiles.refresh();
    if (!mounted) return;
    if (args case {'profileName': final String name}) {
      if (profiles.profileNamed(name) case final profile?) {
        _newTerminal(profile: profile);
      }
      return;
    }
    _showQuickModel(
      terminalProfilePick(
        profiles: profiles.availableProfiles,
        defaultName: profiles.defaultProfileName,
        placeholder: context.l10n.termSelectProfileToCreate,
        onPick: (profile) => _newTerminal(profile: profile),
        l10n: context.l10n,
      ),
    );
  }

  /// Select Default Profile: the one picked is written to settings.json's
  /// `terminal.integrated.defaultProfile.<os>`.
  Future<void> _selectDefaultProfile() async {
    final profiles = _terminals?.profiles;
    if (profiles == null || !profiles.canSetDefault) return;
    await profiles.refresh();
    if (!mounted) return;
    _showQuickModel(
      terminalProfilePick(
        profiles: profiles.availableProfiles,
        defaultName: profiles.defaultProfileName,
        placeholder: context.l10n.termChooseDefaultProfile,
        onPick: (profile) =>
            unawaited(profiles.setDefaultProfile(profile).catchError(_report)),
        l10n: context.l10n,
      ),
    );
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
    if (!_localized || languages == null || path == null) return;
    for (final status in languages.statusFor(path)) {
      if (status.state == LanguageServerState.missing &&
          status.installable &&
          status.missingRuntime == null &&
          !widget.ignoredRecommendations.contains(status.serverId) &&
          _recommended.add(status.serverId)) {
        // Only in the notification center: a toast for every file opened
        // is too much.
        _recommendServer(status, path, silent: true);
      }
    }
  }

  void _recommendServer(
    LanguageServerStatus status,
    String path, {
    bool silent = false,
  }) {
    final id = status.serverId;
    final language = IdeLanguageNames.forPath(path);
    final l10n = context.l10n;
    _notifications.notify(
      IdeSeverity.info,
      l10n.wbRecommendServer(id, language),
      sticky: true,
      silent: silent,
      primary: [
        IdeNotificationAction(l10n.extInstall, () => _install(id, path)),
      ],
      secondary: [
        IdeNotificationAction(
          l10n.wbDontShowAgainServer,
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
          ? context.l10n.extMissingRuntime(status.serverId, runtime)
          : (status.message ?? context.l10n.extUnavailable(status.serverId)),
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
      // Upstream restores a maximized panel as it hides.
      if (panel == null) _panelMaximized = false;
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

  /// Opens the quick input with [prefix] (`>` commands, `:` go to line,
  /// `edt ` editors, none for files), or switches the open one to it.
  ///
  /// With [quickNavigate] (upstream `quickNavigateConfiguration`), releasing
  /// a modifier of those chords accepts, and the input is hidden unless a
  /// quick input shows already; [itemActivation] is the row active first
  /// (the second by default with [quickNavigate]).
  void _showQuickInput(
    String prefix, {
    IdeQuickPickFocus? itemActivation,
    List<KeyChord>? quickNavigate,
  }) {
    if (_quickAccessOf(prefix).$1 == _QuickAccess.files) {
      unawaited(_fileIndex.refresh());
    }
    final shown = _quickInput != null || _quickModel != null;
    if (_quickInput != null &&
        itemActivation == null &&
        quickNavigate == null) {
      _quickInputKey.currentState?.setText(prefix);
      return;
    }
    _openQuickInput(() {
      _quickInput = prefix;
      _quickActivation =
          itemActivation ??
          (quickNavigate != null
              ? IdeQuickPickFocus.second
              : IdeQuickPickFocus.first);
      _quickNavigateChords = quickNavigate;
      _quickHideInput = quickNavigate != null && !shown;
    });
  }

  /// Opens [model] in the quick input, for the views the workbench hosts
  /// (e.g. its chat).
  void showQuickPick(IdeQuickInputModel model) => _showQuickModel(model);

  /// Opens [path] in an editor and focuses it (the host's Open File…).
  Future<void> openFile(String path) => _open(path, focusEditor: true);

  /// Shows the chat, if hidden (e.g. for an agent a notification opens).
  void showChat() => _layout.showChat();

  /// Has the editor's last keys in its document, for what is unsaved to be
  /// all of it (before its window closes, or the app quits).
  Future<void> flush() async => _flushEditor();

  /// Whether the panel's terminals run: a shell alive, or
  /// ([childProcesses]) one running a command
  /// (`terminal.integrated.confirmOnExit`).
  bool terminalsRunning({required bool childProcesses}) {
    for (final terminal
        in _terminals?.instances ?? const <TerminalInstance>[]) {
      if (terminal.exited) continue;
      if (!childProcesses) return true;
      final command =
          terminal.shellIntegration?.commandDetection?.executingCommand;
      if (command != null && command.isNotEmpty) return true;
    }
    return false;
  }

  /// Tells of [message] as the IDE's own notifications do.
  void notify(IdeSeverity severity, String message) =>
      _notifications.notify(severity, message);

  /// Runs the command [id] (the palette's, or one of its keybindings'),
  /// as a menu does; false when there is none here, or it cannot run now.
  bool runCommand(String id) {
    final command = _commandsById()[id];
    if (command == null || !command.enabled) return false;
    _runCommand(command);
    return true;
  }

  /// Opens [model], a quick pick or an input box, in the quick input in
  /// place of what it shows.
  void _showQuickModel(IdeQuickInputModel model) =>
      _openQuickInput(() => _quickModel = model);

  void _openQuickInput(VoidCallback open) {
    final replaced = _quickModel;
    if (_quickInput == null && replaced == null) {
      _focusBeforeQuickInput = FocusManager.instance.primaryFocus;
    }
    setState(() {
      _quickInputKey = GlobalKey();
      _quickInput = null;
      _quickModel = null;
      _quickActivation = IdeQuickPickFocus.first;
      _quickNavigateChords = null;
      _quickHideInput = false;
      open();
    });
    // Upstream hides the quick input that another one replaces.
    replaced?.onDidHide?.call();
  }

  void _closeQuickInput() {
    final model = _quickModel;
    if (_quickInput == null && model == null) return;
    setState(() {
      _quickInput = null;
      _quickModel = null;
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
    model?.onDidHide?.call();
  }

  /// Preferences: Color Theme (see [ideColorThemePick]).
  void _selectColorTheme() {
    if (widget.colorThemes case final themes?) {
      _showQuickModel(
        ideColorThemePick(themes, onError: _report, l10n: context.l10n),
      );
    }
  }

  void _runCommand(IdeCommand command) {
    _recentCommands.add(command.id);
    command.run();
  }

  List<IdeQuickPickItem> _quickItems(String text) {
    final l10n = context.l10n;
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
        l10n: l10n,
      );
    }
    if (text.startsWith('>')) {
      return commandQuickPicks(
        text.substring(1),
        commands: _allCommands(),
        recent: _recentCommands,
        onRun: _runCommand,
        l10n: l10n,
      );
    }
    if (text.startsWith(':')) {
      final active = widget.workspace.active;
      return gotoLineQuickPicks(
        text.substring(1),
        lineCount: active?.model.snapshot.lineCount,
        currentLine: _caretPosition.lineNumber,
        currentColumn: _statusColumn,
        onGo: (line, column) => _revealLine(line, column ?? 1),
        l10n: l10n,
      );
    }
    final (access, prefix) = _quickAccessOf(text);
    if (access != _QuickAccess.files) {
      return _editorPicks(access, text.substring(prefix.length));
    }
    return fileQuickPicks(
      text,
      index: _fileIndex,
      recent: _recentFiles.items,
      onOpen: (path, line, column) =>
          unawaited(_open(path, line: line, column: column, focusEditor: true)),
      onOpenInBackground: _openFileInBackground,
      l10n: l10n,
    );
  }

  String _quickPlaceholder(String text) {
    final l10n = context.l10n;
    if (text.startsWith('>')) return l10n.wbQuickCommands;
    if (text.startsWith(':')) return '';
    if (text.startsWith('@')) return l10n.wbQuickSymbols;
    if (_quickAccessOf(text).$1 != _QuickAccess.files) {
      return l10n.wbQuickEditors;
    }
    return l10n.wbQuickFiles;
  }

  // --- Keybindings ---------------------------------------------------------
  // What a key press runs, as the keybindings resolve it (defaults, the
  // keymap's, the user's; see KeybindingService), with two-chord
  // keybindings (⌘K ⌘T) ported from VS Code
  // src/vs/platform/keybinding/common/abstractKeybindingService.ts at
  // 6a598d4a13031703d483d103c1d934a36ad27971 (`_doDispatch`,
  // `_expectAnotherChord`, `_scheduleLeaveChordMode`, `_leaveChordMode`),
  // with the status bar messages of notificationsStatus.ts. A key counts
  // when the focus lets it bubble here (a terminal keeps its keys, the
  // editor its own commands'); the key after a first chord is taken before
  // the focus sees it.

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

  /// The context keys a keybinding's `when` reads, as they are now.
  @visibleForTesting
  Object? keyContext(String key) {
    final focus = FocusManager.instance.primaryFocus;
    final editorFocus = _editor?.hasTextFocus ?? false;
    // A text field, or the chat's input (a rich text editor of its own).
    final textField =
        focus?.context?.findAncestorStateOfType<EditableTextState>() != null ||
        ChatKeys.focusedTargets().any(
          (target) => target.chatContextKey('inputFocus') == true,
        );
    final terminalFocus =
        _panel == IdePanelTab.terminal &&
        (_terminals?.active?.focusNode.hasFocus ?? false);
    return switch (key) {
      'ideMode' => true,
      'chatMode' => false,
      'editorTextFocus' => editorFocus,
      // The editor or one of its widgets (find, rename).
      'editorFocus' => _editor?.hasFocus ?? false,
      'editorHasSelection' => editorFocus && _selectionLength > 0,
      'editorReadonly' => widget.workspace.active?.readOnly ?? false,
      'editorHasFormattingProvider' => _languages != null,
      'textInputFocus' => editorFocus || textField,
      'inputFocus' => editorFocus || textField || terminalFocus,
      'terminalFocus' => terminalFocus,
      'filesExplorerFocus' => _explorerFocus.hasFocus,
      'listFocus' || 'listSupportsKeyboardNavigation' =>
        _explorerFocus.hasFocus || _focusedList != null,
      'listSupportsMultiselect' =>
        _explorerFocus.hasFocus
            ? _explorerTree.currentState?.contextKey(key) == true
            : _focusedList?.listSupportsMultiselect ?? false,
      'listHasSelectionOrFocus' =>
        _explorerFocus.hasFocus
            ? _explorerTree.currentState?.contextKey(key) == true
            : _focusedList?.listHasSelection ?? false,
      'foldersViewVisible' || 'explorerViewletVisible' =>
        _sidebarShown && _view == IdeSideView.explorer,
      'treestickyScrollFocused' => false,
      'canNavigateBack' => _backStack.isNotEmpty,
      'canNavigateForward' => _forwardStack.isNotEmpty,
      _ =>
        _listContextKey(key) ??
            _searchContextKey(key) ??
            _terminalContextKey(key) ??
            _panelContextKey(key) ??
            _scmContextKey(key) ??
            _quickInputContextKey(key) ??
            _layoutContextKey(key) ??
            _editor?.contextKey(key) ??
            _explorerTree.currentState?.contextKey(key),
    };
  }

  /// What [event] does after the chords [pending]: a command that is here
  /// and enabled, among the palette's.
  KeybindingResolution _resolveKey(
    KeyEvent event, {
    List<KeyChord> pending = const [],
    Map<String, IdeCommand>? commands,
  }) {
    final byId = commands ?? _commandsById();
    return KeybindingService.instance.resolveEvent(
      event,
      pending: pending,
      context: keyContext,
      canRun: (item) => byId[item.command]?.enabled ?? false,
    );
  }

  Map<String, IdeCommand> _commandsById() {
    final byId = <String, IdeCommand>{};
    for (final command in [
      ..._allCommands(),
      ..._listCommands(),
      ..._explorerCommands(),
      ..._quickInputCommands(),
      ..._keyboardCommands(),
      ..._searchKeyboardCommands(),
      ..._terminalKeyboardCommands(),
      ..._panelKeyboardCommands(),
      ..._scmKeyboardCommands(),
    ]) {
      byId.putIfAbsent(command.id, () => command);
    }
    return byId;
  }

  /// The explorer's commands (see [IdeExplorerState.contextKey]): for its
  /// keybindings, not the palette, as upstream's.
  List<IdeCommand> _explorerCommands() {
    final explorer = _explorerTree.currentState;
    if (explorer == null) return const [];
    final selected = explorer.contextKey('explorerResourceIsRoot') == false;
    IdeCommand command(
      String id,
      VoidCallback run, {
      bool enabled = true,
      void Function(Object? args)? runWithArgs,
    }) => IdeCommand(
      id: id,
      label: commandCatalog[id]?.title ?? id,
      run: run,
      runWithArgs: runWithArgs,
      enabled: enabled,
    );
    // `list.focusDown` / `list.focusUp`'s argument: how many rows.
    int rows(Object? args) => args is num ? args.toInt() : 1;
    return [
      command(
        'explorer.newFile',
        () => unawaited(explorer.startCreate(directory: false)),
      ),
      command(
        'explorer.newFolder',
        () => unawaited(explorer.startCreate(directory: true)),
      ),
      command('renameFile', explorer.renameSelected, enabled: selected),
      command(
        'moveFileToTrash',
        () => unawaited(explorer.deleteSelected()),
        enabled: selected,
      ),
      command(
        'deleteFile',
        () => unawaited(explorer.deleteSelected(permanently: true)),
        enabled: selected,
      ),
      command('filesExplorer.copy', explorer.copySelected, enabled: selected),
      command(
        'filesExplorer.cut',
        () => explorer.copySelected(cut: true),
        enabled: selected,
      ),
      command(
        'filesExplorer.paste',
        () => unawaited(explorer.pasteSelected()),
        enabled: explorer.canPaste,
      ),
      command(
        'filesExplorer.openFilePreserveFocus',
        explorer.previewSelected,
        enabled: selected,
      ),
      command(
        'list.focusDown',
        () => explorer.focusNext(1),
        runWithArgs: (args) => explorer.focusNext(rows(args)),
      ),
      command(
        'list.focusUp',
        () => explorer.focusNext(-1),
        runWithArgs: (args) => explorer.focusNext(-rows(args)),
      ),
      command('list.focusPageDown', () => explorer.focusPage(1)),
      command('list.focusPageUp', () => explorer.focusPage(-1)),
      command('list.focusFirst', explorer.focusFirst),
      command('list.focusLast', explorer.focusLast),
      command('list.expand', explorer.expandSelected),
      command('list.collapse', explorer.collapseSelected),
      command('list.select', explorer.openSelected),
      command('list.toggleExpand', explorer.toggleSelected),
      command('list.expandSelectionDown', () => explorer.expandSelection(1)),
      command('list.expandSelectionUp', () => explorer.expandSelection(-1)),
      command('list.selectAll', explorer.selectAll),
      command(
        'list.clear',
        explorer.clearSelection,
        enabled: explorer.contextKey('listHasSelectionOrFocus') == true,
      ),
      command('list.collapseAll', _explorer.collapseAll),
    ];
  }

  /// For the editor: the command a key runs, [editorChordPrefix] when it
  /// starts a sequence, null when no keybinding has it.
  String? _resolveEditorKey(KeyEvent event) => switch (_resolveKey(event)) {
    KeybindingFound(:final command) => command,
    MoreChordsNeeded() => editorChordPrefix,
    NoKeybinding() => null,
  };

  /// A key the focus let through: the command its keybinding runs, or the
  /// first chord of a two-chord keybinding, which starts chord mode
  /// (`ResultKind.KbFound`, `ResultKind.MoreChordsNeeded`).
  KeyEventResult _onWorkbenchKey(FocusNode node, KeyEvent event) {
    _offeredKey = event;
    // An input method composing text has its keys (Enter picks a
    // candidate); upstream's keyboard events read as `KeyCode.Unknown`.
    if (_chord != null || event is KeyUpEvent || ChatKeys.isComposing) {
      return KeyEventResult.ignored;
    }
    final commands = _commandsById();
    switch (_resolveKey(event, commands: commands)) {
      case KeybindingFound(:final item):
        commands[item.command]!.invoke(item.entry.args);
        return KeyEventResult.handled;
      case MoreChordsNeeded(:final chords):
        _expectAnotherChord(chords);
        return KeyEventResult.handled;
      case NoKeybinding():
        return KeyEventResult.ignored;
    }
  }

  /// The last key [_onWorkbenchKey] was offered, which [_onLateKey]
  /// leaves.
  KeyEvent? _offeredKey;

  /// A key that did not reach [_onWorkbenchKey]: one a widget in the
  /// workbench stopped without handling it (the chat's input keeps its
  /// rich text editor's shortcuts from it, `skipRemainingHandlers`), or one
  /// pressed with the focus on none of the workbench's widgets but on the
  /// window (the focused one went). Upstream's keybinding service listens
  /// on the window, and hears both (`_registerKeyListeners`); a dialog
  /// over the workbench, a menu in the overlay, or an input method
  /// composing text keeps its keys.
  KeyEventResult _onLateKey(KeyEvent event) {
    if (identical(event, _offeredKey) || !widget.visible || !mounted) {
      return KeyEventResult.ignored;
    }
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null ||
        !(focus.ancestors.contains(_workbenchFocus) ||
            _workbenchFocus.ancestors.contains(focus)) ||
        !(ModalRoute.isCurrentOf(context) ?? true)) {
      return KeyEventResult.ignored;
    }
    return _onWorkbenchKey(_workbenchFocus, event);
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
    _resolveChord(chord, event);
    return KeyEventResult.handled;
  }

  void _expectAnotherChord(List<KeyChord> chords) {
    final platform = KeybindingService.instance.platform;
    final label = chords.map((chord) => chord.label(platform)).join(' ');
    final message = context.l10n.wbChordWaiting(label);
    _chord = (label: label, chords: chords, message: message);
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
    final commands = _commandsById();
    final result = _resolveKey(
      event,
      pending: chord.chords,
      commands: commands,
    );
    if (result case KeybindingFound(:final item)) {
      commands[item.command]!.invoke(item.entry.args);
      return;
    }
    final platform = KeybindingService.instance.platform;
    final keypress = KeyChord.fromEvent(event)?.label(platform) ?? '';
    _setStatusMessage(
      context.l10n.wbChordNotCommand(chord.label, keypress),
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
        run: () => _showQuickInput('>'),
      ),
      // A keybinding's `args` is the text to open with (upstream's
      // `prefix`: `"args": ">"` opens the commands).
      IdeCommand(
        id: 'workbench.action.quickOpen',
        label: 'Go to File…',
        run: () => _showQuickInput(''),
        runWithArgs: (args) => _showQuickInput(args is String ? args : ''),
      ),
      IdeCommand(
        id: 'workbench.action.gotoLine',
        label: 'Go to Line/Column…',
        run: () => _showQuickInput(':'),
      ),
      IdeCommand(
        id: 'actions.find',
        label: 'Find',
        enabled: active != null,
        run: _find,
      ),
      IdeCommand(
        id: 'editor.action.startFindReplaceAction',
        label: 'Replace',
        enabled: active != null,
        run: () => _find(replace: true),
      ),
      IdeCommand(
        id: 'workbench.action.files.save',
        category: 'File',
        label: 'Save',
        enabled: active != null,
        run: () => unawaited(_save()),
      ),
      IdeCommand(
        id: 'markdown.showPreview',
        category: 'Markdown',
        label: 'Open Preview',
        enabled: active != null && _hasPreview(active) && !_previewing(active),
        run: () => unawaited(_setMarkdownPreview(true)),
      ),
      IdeCommand(
        id: 'markdown.showSource',
        category: 'Markdown',
        label: 'Show Source',
        enabled: _previewing(active),
        run: () => unawaited(_setMarkdownPreview(false)),
      ),
      IdeCommand(
        id: 'workbench.action.files.saveAll',
        category: 'File',
        label: 'Save All',
        enabled: workspace.documents.any((doc) => doc.dirty),
        run: () => unawaited(_saveAll()),
      ),
      IdeCommand(
        id: 'workbench.action.files.saveAs',
        category: 'File',
        label: 'Save As...',
        enabled:
            active != null &&
            (active.isFile || active.isUntitled) &&
            active.label == null &&
            workspace.askSavePath != null,
        run: () => unawaited(_saveAs()),
      ),
      IdeCommand(
        id: 'workbench.action.files.newUntitledFile',
        category: 'File',
        label: 'New Text File',
        run: _newUntitled,
      ),
      IdeCommand(
        id: 'workbench.action.closeActiveEditor',
        category: 'View',
        label: 'Close Editor',
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
        enabled: _closedEditors.isNotEmpty,
        run: _reopenClosed,
      ),
      IdeCommand(
        id: 'workbench.action.nextEditor',
        category: 'View',
        label: 'Open Next Editor',
        enabled: workspace.documents.length > 1,
        run: () => _cycleEditor(1),
      ),
      IdeCommand(
        id: 'workbench.action.previousEditor',
        category: 'View',
        label: 'Open Previous Editor',
        enabled: workspace.documents.length > 1,
        run: () => _cycleEditor(-1),
      ),
      // ⌃9 / Alt+9 opens the last editor when there are fewer.
      for (var i = 1; i <= 9; i++)
        IdeCommand(
          id: 'workbench.action.openEditorAtIndex$i',
          category: 'View',
          label: 'Open Editor at Index $i',
          enabled: hasEditors,
          run: () => _openEditorAt(i == 9 ? -1 : i - 1),
        ),
      IdeCommand(
        id: 'workbench.action.lastEditorInGroup',
        category: 'View',
        label: 'Open Last Editor in Group',
        enabled: hasEditors,
        run: () => _openEditorAt(-1),
      ),
      IdeCommand(
        id: 'workbench.action.toggleSidebarVisibility',
        category: 'View',
        label: 'Toggle Primary Side Bar Visibility',
        run: _toggleSidebar,
      ),
      IdeCommand(
        id: 'workbench.action.toggleAuxiliaryBar',
        category: 'View',
        label: 'Toggle Chat',
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
        enabled: terminals != null,
        run: _toggleTerminal,
      ),
      IdeCommand(
        id: 'workbench.action.terminal.new',
        category: 'Terminal',
        label: 'Create New Terminal',
        enabled: terminals != null,
        run: _newTerminal,
      ),
      IdeCommand(
        id: 'workbench.action.terminal.newWithProfile',
        category: 'Terminal',
        label: 'Create New Terminal (With Profile)',
        enabled: terminals != null,
        run: () => unawaited(_newTerminalWithProfile()),
        runWithArgs: (args) => unawaited(_newTerminalWithProfile(args)),
      ),
      IdeCommand(
        id: 'workbench.action.terminal.selectDefaultShell',
        category: 'Terminal',
        label: 'Select Default Profile',
        enabled: terminals?.profiles.canSetDefault ?? false,
        run: () => unawaited(_selectDefaultProfile()),
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
        enabled: terminal != null,
        run: () => _cycleTerminal(true),
      ),
      IdeCommand(
        id: 'workbench.action.terminal.focusPrevious',
        category: 'Terminal',
        label: 'Focus Previous Terminal Group',
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
        run: () => _showView(IdeSideView.explorer),
      ),
      IdeCommand(
        id: 'workbench.view.search',
        category: 'View',
        label: 'Show Search',
        run: () => _showView(IdeSideView.search),
      ),
      IdeCommand(
        id: 'workbench.view.scm',
        category: 'View',
        label: 'Show Source Control',
        run: () => _showView(IdeSideView.sourceControl),
      ),
      IdeCommand(
        id: 'workbench.view.extensions',
        category: 'View',
        label: 'Show Extensions',
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
        enabled: active != null,
        run: () => _tabAction(active!, IdeTabAction.copyPath),
      ),
      IdeCommand(
        id: 'copyRelativeFilePath',
        category: 'File',
        label: 'Copy Relative Path of Active File',
        enabled: active != null,
        run: () => _tabAction(active!, IdeTabAction.copyRelativePath),
      ),
      IdeCommand(
        id: 'workbench.action.gotoSymbol',
        label: 'Go to Symbol in Editor...',
        enabled: active != null,
        run: () => _showQuickInput('@'),
      ),
      IdeCommand(
        id: 'workbench.actions.view.problems',
        category: 'View',
        label: 'Toggle Problems',
        run: _toggleProblems,
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
        enabled: _languages != null,
        run: () => _gotoProblem(next: true),
      ),
      IdeCommand(
        id: 'editor.action.marker.prevInFiles',
        label: 'Go to Previous Problem in Files (Error, Warning, Info)',
        enabled: _languages != null,
        run: () => _gotoProblem(next: false),
      ),
      IdeCommand(
        id: 'workbench.action.navigateBack',
        category: 'Go',
        label: 'Go Back',
        enabled: _backStack.isNotEmpty,
        run: () => _navigate(back: true),
      ),
      IdeCommand(
        id: 'workbench.action.navigateForward',
        category: 'Go',
        label: 'Go Forward',
        enabled: _forwardStack.isNotEmpty,
        run: () => _navigate(back: false),
      ),
      IdeCommand(
        id: ideSelectColorThemeCommandId,
        category: 'Preferences',
        label: 'Color Theme',
        enabled: widget.colorThemes != null,
        run: _selectColorTheme,
      ),
      IdeCommand(
        id: 'baocode.ide.toggleFormatOnSave',
        category: 'Preferences',
        label: _formatOnSave
            ? 'Turn Off Format on Save'
            : 'Turn On Format on Save',
        enabled: _languages != null,
        run: () => setState(() => _formatOnSave = !_formatOnSave),
      ),
      _catalogCommand(
        'git.blame.toggleEditorDecoration',
        () => setState(() => _gitBlame = !_gitBlame),
        enabled: widget.workspace.git != null,
      ),
      IdeCommand(
        id: 'baocode.ide.retryLanguageServices',
        category: 'Developer',
        label: 'Retry Language Services',
        enabled: active != null,
        run: () => unawaited(_editor?.retryLanguageServer()),
      ),
      IdeCommand(
        id: 'baocode.ide.backToChat',
        category: 'View',
        label: 'Back to Chat',
        run: () => unawaited(_back()),
      ),
    ];
  }

  /// The workbench's commands, then the editor's, then [IdeWorkbench.commands].
  List<IdeCommand> _allCommands() => [
    ..._workbenchCommands(),
    ..._editorCommands(),
    ..._layoutCommands(),
    ..._searchCommands(),
    ..._terminalCommands(),
    ..._panelCommands(),
    ..._scmCommands(),
    ...?_editor?.editorCommands,
    ...widget.commands,
  ];

  /// The commands for the current state, for the palette and for tests.
  @visibleForTesting
  List<IdeCommand> get commands => _allCommands();

  /// Those and the keybinding-only ones (the lists', the quick input's…),
  /// by id, for tests.
  @visibleForTesting
  Map<String, IdeCommand> get commandsById => _commandsById();

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

    // Each view's name and the keybinding of the command opening it, as
    // upstream's `CompositeBarActionViewItem.computeTitle`
    // (compositeBarActions.ts), then its badge's description.
    final keys = KeybindingService.instance;
    final l10n = context.l10n;
    const radius = Radius.circular(IdeModernUI.radius);
    // Half the lane each side, less the border already there.
    const inset = IdeModernUI.activityLane / 2 - 1;
    final items = [
      item(
        IdeSideView.explorer,
        Codicons.files,
        keys.titleWithKeybinding(l10n.wbExplorer, 'workbench.view.explorer'),
      ),
      item(
        IdeSideView.search,
        Codicons.search,
        // Find in Files has Show Search's ⇧⌘F (workbench_keybindings.dart),
        // which then shows nothing of its own.
        switch (keys.labelFor('workbench.action.findInFiles') ??
            keys.labelFor('workbench.view.search')) {
          final shortcut? => '${l10n.wbSearchFiles} ($shortcut)',
          null => l10n.wbSearchFiles,
        },
      ),
      item(
        IdeSideView.sourceControl,
        Codicons.sourceControl,
        keys.titleWithKeybinding(l10n.scmTitle, 'workbench.view.scm') +
            (_gitCount > 0 ? ' - ${l10n.wbPendingChanges(_gitCount)}' : ''),
        badge: _gitCount,
      ),
      item(
        IdeSideView.extensions,
        Codicons.extensions,
        keys.titleWithKeybinding(l10n.extTitle, 'workbench.view.extensions'),
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
    child: Focus(focusNode: _sidebarFocus, child: _sidePanel()),
  );

  Widget _sidePanel() => switch (_view) {
    IdeSideView.explorer => _explorerView(),
    IdeSideView.search => IdeSearchView(
      key: _searchKey,
      session: _search,
      workspace: widget.workspace,
      onOpen: (path, range, {required focusEditor}) =>
          _open(path, range: range, select: true, focusEditor: focusEditor),
      onError: _report,
    ),
    IdeSideView.sourceControl => IdeScmView(
      key: _scmKey,
      workspace: widget.workspace,
      session: _scm,
      notifications: _notifications,
      onOpen: (path, {focusEditor = false}) =>
          _open(path, focusEditor: focusEditor),
      onOpenChange: _openChange,
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
    // The folder's actions are the explorer's commands: their keybindings
    // in their tooltips (upstream's `MenuEntryActionViewItem.getTooltip`).
    final keys = KeybindingService.instance;
    return ColoredBox(
      color: themeColors['sideBar.background'],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdeViewTitle(context.l10n.wbExplorer),
          Expanded(
            child: IdePaneContainer(
              expanded: _explorerPanes,
              onToggle: (id) => setState(() {
                if (!_explorerPanes.remove(id)) _explorerPanes.add(id);
              }),
              panes: [
                if (!workspace.hasFolder)
                  IdePane(
                    id: 'folder',
                    title: context.l10n.explorerNoFolderTitle,
                    weight: 3,
                    body: _NoFolder(
                      onOpenFolder: _hostCommand(
                        'workbench.action.files.openFolder',
                      )?.run,
                    ),
                  )
                else
                  IdePane(
                    id: 'folder',
                    title: widget.project.name,
                    weight: 3,
                    actions: [
                      IdePaneAction(
                        icon: Codicons.newFile,
                        tooltip: keys.titleWithKeybinding(
                          context.l10n.explorerNewFile,
                          'explorer.newFile',
                        ),
                        onPressed: () => unawaited(
                          _explorerTree.currentState?.startCreate(
                            directory: false,
                          ),
                        ),
                      ),
                      IdePaneAction(
                        icon: Codicons.newFolder,
                        tooltip: keys.titleWithKeybinding(
                          context.l10n.explorerNewFolder,
                          'explorer.newFolder',
                        ),
                        onPressed: () => unawaited(
                          _explorerTree.currentState?.startCreate(
                            directory: true,
                          ),
                        ),
                      ),
                      IdePaneAction(
                        icon: Codicons.refresh,
                        tooltip: keys.titleWithKeybinding(
                          context.l10n.cmdRefreshExplorer,
                          'workbench.files.action.refreshFilesExplorer',
                        ),
                        onPressed: () => unawaited(_explorer.refresh()),
                      ),
                      IdePaneAction(
                        icon: Codicons.collapseAll,
                        tooltip: keys.titleWithKeybinding(
                          context.l10n.cmdCollapseExplorerFolders,
                          'workbench.files.action.collapseExplorerFolders',
                        ),
                        onPressed: _explorer.collapseAll,
                      ),
                    ],
                    body: IdeExplorer(
                      key: _explorerTree,
                      controller: _explorer,
                      focusNode: _explorerFocus,
                      isBound: (event) => _resolveEditorKey(event) != null,
                      git: workspace.git,
                      onOpen: (path, focusEditor) =>
                          unawaited(_open(path, focusEditor: focusEditor)),
                      onMoved: workspace.moved,
                      onDeleted: workspace.deleted,
                      unsavedIn: (path) => workspace
                          .documentsIn(path)
                          .where((d) => d.dirty)
                          .length,
                      local: _local,
                      trash: _local && WindowControls.canMoveToTrash
                          ? WindowControls.moveToTrash
                          : null,
                      onError: _report,
                      onOpenInDefaultApp:
                          _local && WindowControls.canOpenInDefaultApp
                          ? (path) => unawaited(_openInDefaultApp(path))
                          : null,
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
                  title: context.l10n.wbOutline,
                  body: IdeOutlineView(
                    symbols: _symbols,
                    caret: workspace.active == null ? null : _caretLsp,
                    onReveal: _revealSymbol,
                    showHeader: false,
                  ),
                ),
                IdePane(
                  id: 'timeline',
                  title: context.l10n.wbTimeline,
                  description: timelinePath == null
                      ? null
                      : p.basename(timelinePath),
                  actions: [
                    IdePaneAction(
                      icon: _timeline.pinned == null
                          ? Codicons.pin
                          : Codicons.pinned,
                      tooltip: _timeline.pinned == null
                          ? context.l10n.wbPinTimeline
                          : context.l10n.wbUnpinTimeline,
                      onPressed: () =>
                          setState(() => _timeline.togglePin(activePath)),
                    ),
                    IdePaneAction(
                      icon: Codicons.refresh,
                      tooltip: context.l10n.commonRefresh,
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
              local: _local,
              markdownPreview: active != null && _hasPreview(active)
                  ? _previewing(active)
                  : null,
              onMarkdownPreview: (preview) =>
                  unawaited(_setMarkdownPreview(preview)),
            ),
            if (active != null && !active.isUntitled)
              IdeBreadcrumbs(
                root: widget.workspace.root,
                path: active.path,
                onReveal: _revealInExplorer,
                symbols: _symbolPath,
                onSymbol: _revealSymbol,
              ),
          ],
          Expanded(
            child: _markdownDrops(
              active,
              active == null && !widget.workspace.hasFolder
                  ? IdeStartPage(
                      actions: [
                        for (final id in const [
                          'workbench.action.files.openFolder',
                          'baocode.remote.openFolder',
                          'workbench.action.files.openFile',
                          'workbench.action.files.newUntitledFile',
                        ])
                          ...commands.where((command) => command.id == id),
                      ],
                      recent: widget.recentFolders,
                      onOpenRecent: widget.onOpenRecent,
                      onShowAllRecent: commands
                          .where((c) => c.id == 'workbench.action.openRecent')
                          .firstOrNull
                          ?.run,
                    )
                  : active == null
                  ? IdeWelcome(
                      commands: [
                        for (final id in const [
                          'workbench.action.showCommands',
                          'workbench.action.quickOpen',
                          // Upstream's watermark: Show Search has no key of
                          // its own, Find in Files takes its ⇧⌘F.
                          'workbench.action.findInFiles',
                          'actions.find',
                          'workbench.action.gotoLine',
                          'workbench.action.toggleSidebarVisibility',
                          'workbench.action.toggleAuxiliaryBar',
                        ])
                          ...commands.where((command) => command.id == id),
                      ],
                    )
                  : active.isMedia
                  ? IdeImagePreview(
                      key: ValueKey(active),
                      path: active.path,
                      read: switch (widget.workspace.files) {
                        final IdeHostFiles files => files.readBytes,
                        _ => null,
                      },
                      onOpenInDefaultApp:
                          _local && WindowControls.canOpenInDefaultApp
                          ? () => unawaited(_openInDefaultApp(active.path))
                          : null,
                    )
                  : active.openError != null
                  ? IdeEditorPlaceholder(
                      key: ValueKey(active),
                      error: active.openError!,
                      onOpenAnyway: () => unawaited(
                        widget.workspace.reopen(active, force: true),
                      ),
                      onRetry: () => unawaited(widget.workspace.reopen(active)),
                      onOpenInDefaultApp:
                          _local &&
                              WindowControls.canOpenInDefaultApp &&
                              active.readRevision == null
                          ? () => unawaited(_openInDefaultApp(active.path))
                          : null,
                    )
                  : _previewing(active)
                  ? _markdownPreview(active)
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
                          gitBlame: _gitBlame,
                          keyResolver: _resolveEditorKey,
                          onPaste: _pasteInEditor,
                        ),
            ),
          ),
        ],
      ),
    );
  }

  void _positionChanged(IdeEditorPosition selection) {
    _caretMoved(selection.position);
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
  Widget _chatCard() => IdeCard(
    key: _chatKey,
    child: Focus(focusNode: _chatFocus, child: widget.chat),
  );
  final _chatKey = GlobalKey(debugLabel: 'ide chat');

  /// What [IdeLayout.roomForBoth] and [IdeLayout.roomForSides] are to be,
  /// from the last layout: the layout's listeners build, so it is told
  /// after the frame.
  ({bool both, bool sides}) _room = (both: true, sides: true);
  bool _roomPending = false;

  void _noteRoom(({bool both, bool sides}) room) {
    _room = room;
    if ((room.both == _layout.roomForBoth &&
            room.sides == _layout.roomForSides) ||
        _roomPending) {
      return;
    }
    _roomPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _roomPending = false;
      if (mounted) _layout.setRoom(both: _room.both, sides: _room.sides);
    });
  }

  /// The side bar and its sash, which keep their state (and a drag) as they
  /// move beside the chat in the editor's place, and back.
  final _sidebarKey = GlobalKey(debugLabel: 'ide side bar');
  final _sidebarSashKey = GlobalKey(debugLabel: 'ide side bar sash');

  /// The Modern UI's cards on the shell: 4px apart, and 4px from the
  /// window's sides and the status bar. The chat stays on the right however
  /// narrow the window (see [IdeColumns.fit]). With the editor hidden
  /// ([IdeLayout.editorHidden]), the chat has its place, beside the side bar
  /// if that shows, the panel below the two.
  Widget _split(Size size, List<IdeCommand> commands) {
    const gap = IdeModernUI.gap;
    // Hidden, the chat leaves a gap at the window's side, its sash's width
    // but no sash: there it would take the window's own resizing edge. The
    // gap above the status bar is each column's: the panel's sash, hidden.
    final outside = EdgeInsets.fromLTRB(gap, 0, _chatShown ? gap : 0, 0);
    // Keyed, so a sash keeps its drag as the columns change about it.
    Widget above(Widget column, String slot) => Padding(
      key: ValueKey('ide-row-$slot'),
      padding: const EdgeInsets.only(bottom: gap),
      child: column,
    );
    // The editor hidden, there is a sash less, but the chat is sized as
    // though both were there: dragged back, the editor comes out where the
    // pointer is.
    final room =
        size.width -
        outside.horizontal -
        IdeModernUI.activityBarWidth -
        2 * _sashWidth;
    final withChat = room - (_chatShown ? 0 : gap);
    _noteRoom((
      both: IdeColumns.roomForBoth(withChat),
      sides: IdeColumns.roomForSides(withChat),
    ));
    final editorHidden = !_layout.editorVisible;
    final columns = IdeColumns.fit(
      room,
      sidebar: _sidebarShown ? _sidebarWidth : null,
      chat: _chatShown ? _chatWidth : null,
      editorHidden: editorHidden,
    );
    final sidebarVisible = columns.sidebar > 0;
    final chatVisible = columns.chat > 0;
    final sidebar = SizedBox(
      key: const ValueKey('ide-sidebar'),
      width: columns.sidebar,
      child: KeyedSubtree(key: _sidebarKey, child: _sidebarCard()),
    );
    // With the side bar hidden, the gap by the activity bar: dragged out, it
    // opens the side bar.
    final sidebarSash = KeyedSubtree(
      key: _sidebarSashKey,
      child: _Sash(
        key: const ValueKey('ide-sidebar-sash'),
        grip: sidebarVisible,
        canMoveBack: sidebarVisible,
        canMoveForward: columns.canGrowSidebar(room),
        onStart: () => _dragStart = (columns: columns, room: room),
        onDrag: (dx) => _dragTo((start, room) => start.dragSidebar(room, dx)),
        onReset: () => setState(() {
          _layout.showSidebar();
          _sidebarWidth = IdeColumns.defaultSidebar;
        }),
      ),
    );
    final chatSash = above(
      _Sash(
        key: const ValueKey('ide-chat-sash'),
        grip: chatVisible,
        canMoveBack: columns.canGrowChat(room),
        canMoveForward: chatVisible,
        onStart: () {
          _dragStart = (columns: columns, room: room);
          _chatSashDragging = true;
        },
        onEnd: () {
          if (mounted) setState(() => _chatSashDragging = false);
        },
        onDrag: (dx) => _dragTo((start, room) => start.dragChat(room, dx)),
        onReset: () => setState(() {
          _layout
            ..showChat()
            ..showEditor();
          _chatWidth = IdeColumns.defaultChat;
        }),
      ),
      'chat-sash',
    );
    final chat = KeyedSubtree(
      key: const ValueKey('ide-chat'),
      child: _chatCard(),
    );
    return Padding(
      padding: outside,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          above(_activityBar(joined: sidebarVisible), 'activity-bar'),
          if (!editorHidden) ...[
            if (sidebarVisible) above(sidebar, 'sidebar'),
            above(sidebarSash, 'sidebar-sash'),
          ] else if (!sidebarVisible)
            // The chat maximized: its sash is by the activity bar, and
            // dragged back, the editor comes out.
            chatSash,
          Expanded(
            key: const ValueKey('ide-editor-column'),
            child: _editorColumn(
              size.height,
              commands,
              inPlace: !editorHidden
                  ? null
                  : sidebarVisible
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        sidebar,
                        sidebarSash,
                        Expanded(child: chat),
                      ],
                    )
                  : chat,
            ),
          ),
          if (!editorHidden) ...[
            if (chatVisible || _chatSashDragging)
              chatSash
            else
              const SizedBox(key: ValueKey('ide-chat-gap'), width: _sashWidth),
            above(_chatSlot(columns.chat), 'chat'),
          ],
        ],
      ),
    );
  }

  /// The editor, and below it the panel (the terminal), as VS Code's panel
  /// at the bottom, centered: under the editor only. Hidden, the panel
  /// leaves its sash as the gap above the status bar. [inPlace] has the
  /// editor's place where it is hidden (the chat, and the side bar beside
  /// it), above the panel; the editor is kept, as the chat hidden is.
  Widget _editorColumn(
    double height,
    List<IdeCommand> commands, {
    Widget? inPlace,
  }) {
    final hidden = inPlace != null;
    final shown = _panel != null;
    final room = height - _sashWidth - (shown ? IdeModernUI.gap : 0);
    final rows = IdeRows.fit(
      room,
      panel: !shown
          ? null
          : _panelMaximized
          ? double.infinity
          : _panelHeight ?? IdeRows.defaultPanel(room),
      minAbove: hidden ? IdeRows.minChat : IdeRows.minEditor,
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
                offstage: hidden,
                child: TickerMode(
                  enabled: !hidden,
                  child: ExcludeFocus(
                    excluding: hidden,
                    child: KeyedSubtree(
                      key: const ValueKey('ide-editor'),
                      child: _editorArea(commands),
                    ),
                  ),
                ),
              ),
              ?inPlace,
            ],
          ),
        ),
        // Under the side bar too, it keeps clear of the activity bar the
        // side bar is joined to.
        Padding(
          padding: EdgeInsets.only(
            left: hidden && _layout.sidebarVisible ? IdeModernUI.gap : 0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              _panelSlot(rows.panel),
              if (shown) const SizedBox(height: IdeModernUI.gap),
            ],
          ),
        ),
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
      _panelMaximized = false;
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
  Widget _panelSlot(double height) {
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
                    onOpenFocused: (location) =>
                        unawaited(_openFocused(location)),
                    problemsList: _problemsList,
                    referencesList: _referencesList,
                    textOf: _textOf,
                    terminal: switch (_terminals) {
                      final terminals? => TerminalPanel(
                        terminals: terminals,
                        onNew: _newTerminal,
                        onOpenLink: _openTerminalLink,
                        shouldSkipShell: _terminalSkipsShell,
                        resolveKey: _terminalFindKey,
                      ),
                      null => null,
                    },
                    terminalActions: switch (_terminals) {
                      final terminals? => TerminalTitleActions(
                        terminals: terminals,
                        onNew: _newTerminal,
                        onNewWithProfile: (profile) =>
                            _newTerminal(profile: profile),
                        onSelectDefaultProfile: () =>
                            unawaited(_selectDefaultProfile()),
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
      if (next.sidebar > 0) {
        _sidebarWidth = next.sidebar;
      } else if (columns.sidebar > 0) {
        _sidebarWidth = columns.sidebar;
      }
      // With the editor hidden, the chat's width is the room's, not its
      // own: from there it comes back as wide as it was, and maximized, as
      // wide as when the drag began.
      if (next.editorHidden) {
        if (!columns.editorHidden && columns.chat > 0) {
          _chatWidth = columns.chat;
        }
      } else if (next.chat > 0) {
        if (!columns.editorHidden || columns.sidebar == 0) {
          _chatWidth = next.chat;
        }
      } else if (columns.chat > 0 && !columns.editorHidden) {
        _chatWidth = columns.chat;
      }
      _layout.resize(
        sidebar:
            !next.chatMaximized &&
            (next.sidebar > 0 || (columns.sidebar == 0 && _layout.sidebar)),
        chat: next.chat > 0 || (columns.chat == 0 && _layout.chat),
        editorHidden: next.editorHidden,
      );
    });
  }

  Widget _titleBar() {
    final keys = KeybindingService.instance;
    final l10n = context.l10n;
    // A double click on its empty part zooms the window, as the system's
    // title bar does.
    return TitleBarDoubleClick(
      child: SizedBox(
        height: AppMetrics.titleBarHeight,
        child: Row(
          children: [
            SizedBox(width: AppMetrics.trafficLightsWidth + 6),
            // VS Code's layout controls; the side bar's on its side, after
            // the traffic lights.
            IdeLayoutToggle.sidebar(_layout),
            const SizedBox(width: 12),
            Expanded(
              child: Center(
                child: _CommandCenter(
                  label: widget.workspace.hasFolder
                      ? widget.project.name
                      : l10n.ideSearchOpenFiles,
                  tooltip: keys.titleWithKeybinding(
                    widget.workspace.hasFolder
                        ? l10n.ideSearchProject(widget.project.name)
                        : l10n.ideSearchOpenFiles,
                    'workbench.action.quickOpen',
                  ),
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
                  // Its label, and the keys that do the same.
                  IdeHover(
                    message: keys.titleWithKeybinding(
                      widget.backLabel ?? l10n.workspaceBackToChat,
                      'baocode.ide.backToChat',
                    ),
                    child: BackToChatButton(
                      label: widget.backLabel,
                      onPressed: () => unawaited(_back()),
                    ),
                  ),
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
    final l10n = context.l10n;
    // An item doing what a command does has its keybinding in its tooltip
    // (a deviation: upstream's status bar items have their tooltips alone).
    final keys = KeybindingService.instance;
    final left = [
      ?widget.remote?.item(context),
      if (_gitBranch ?? _branch case final branch?)
        // Upstream's `CheckoutStatusBar`: Checkout to…, its tooltip the
        // repository's (`<folder> (Git) - `) before the command's.
        if (_git?.state case final state?)
          IdeStatusBarItem(
            branch,
            icon: Codicons.gitBranch,
            tooltip: keys.titleWithKeybinding(
              '${p.basename(state.root)} (Git) - '
                  '$branch, ${l10n.gitCheckoutBranchTag}',
              'git.checkout',
            ),
            onTap: _gitCheckout,
          )
        else
          IdeStatusBarItem(
            branch,
            icon: Codicons.gitBranch,
            tooltip: keys.titleWithKeybinding(
              l10n.scmTitle,
              'workbench.view.scm',
            ),
            onTap: () => _showView(IdeSideView.sourceControl),
          ),
      IdeStatusBarItem(
        switch (_lspStatus) {
          'Language services' => l10n.wbLanguageServices,
          'Monaco editor' => l10n.wbMonacoEditor,
          'Text editor' => l10n.wbTextEditor,
          final status => status,
        },
        tooltip: keys.titleWithKeybinding(
          l10n.wbRetryLanguageServices,
          'baocode.ide.retryLanguageServices',
        ),
        onTap: () => unawaited(_editor?.retryLanguageServer()),
      ),
      if (_languages case final languages?) ...[
        () {
          final counts = ideDiagnosticCounts(languages.allDiagnostics);
          return IdeStatusBarItem(
            '\$(error) ${counts.errors} \$(warning) ${counts.warnings}'
            '${counts.infos > 0 ? ' \$(info) ${counts.infos}' : ''}',
            tooltip: keys.titleWithKeybinding(
              counts.errors + counts.warnings + counts.infos == 0
                  ? l10n.wbNoProblems
                  : counts.infos > 0
                  ? l10n.wbProblemCountsInfos(
                      counts.errors,
                      counts.warnings,
                      counts.infos,
                    )
                  : l10n.wbProblemCounts(counts.errors, counts.warnings),
              'workbench.actions.view.problems',
            ),
            onTap: () => _togglePanel(IdePanelTab.problems),
          );
        }(),
        if (widget.workspace.active case final doc?)
          ...ideLanguageStatusItems(
            languages,
            doc.path,
            onInstall: _installServer,
            l10n: l10n,
          ),
      ],
      if (_statusMessage case final message?) IdeStatusBarItem(message),
    ];
    final bell = ideNotificationsStatusItem(_notifications, l10n: l10n);
    if (active == null || active.openError != null || active.isMedia) {
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
          l10n.referencesPosition(_caretPosition.lineNumber, _statusColumn) +
              (_selectionLength > 0
                  ? ' ${l10n.wbSelectedCount(_selectionLength)}'
                  : ''),
          tooltip: keys.titleWithKeybinding(
            l10n.wbGoToLineColumn,
            'workbench.action.gotoLine',
          ),
          onTap: () => _showQuickInput(':'),
        ),
        IdeStatusBarItem(
          _editor?.localizedIndentationLabel(l10n) ?? l10n.wbSpaces(4),
          tooltip: l10n.wbIndentation,
        ),
        IdeStatusBarItem(
          ideEncodingLabel(snapshot.text),
          tooltip: l10n.wbEncoding,
        ),
        IdeStatusBarItem(
          _eolLabel == 'Mixed' ? l10n.wbEolMixed : _eolLabel,
          tooltip: l10n.wbEndOfLine,
        ),
        IdeStatusBarItem(
          IdeLanguageNames.forPath(active.path),
          tooltip: l10n.wbLanguageMode,
        ),
        bell,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _keepViewSoon();
    return ListenableBuilder(
      listenable: widget.workspace,
      builder: (context, _) {
        final commands = _allCommands();
        final focus = Focus(
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
                  top: AppMetrics.titleBarHeight,
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
                    child: IdeNotificationToasts(notifications: _notifications),
                  ),
                ),
                if (_quickModel != null || _quickInput != null)
                  Positioned.fill(
                    top: WindowControls.drawsHeader
                        ? 0
                        : AppMetrics.titleBarHeight,
                    child: switch (_quickModel) {
                      final IdeQuickPick pick => IdeQuickInput.pick(
                        key: _quickInputKey,
                        pick: pick,
                        onClose: _closeQuickInput,
                      ),
                      final IdeQuickInputBox box => IdeQuickInput.input(
                        key: _quickInputKey,
                        inputBox: box,
                        onClose: _closeQuickInput,
                      ),
                      null => IdeQuickInput(
                        key: _quickInputKey,
                        initialText: _quickInput!,
                        itemsFor: _quickItems,
                        placeholderFor: _quickPlaceholder,
                        onClose: _closeQuickInput,
                        refresh: _quickRefresh,
                        itemActivation: _quickActivation,
                        quickNavigate: _quickNavigateChords,
                        hideInput: _quickHideInput,
                      ),
                    },
                  ),
              ],
            ),
          ),
        );
        // The mouse's back and forward buttons go back and forward, as
        // upstream's `registerMouseNavigationListener` has them.
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            if (event.buttons & kBackMouseButton != 0) {
              _navigate(back: true);
            } else if (event.buttons & kForwardMouseButton != 0) {
              _navigate(back: false);
            }
          },
          child: focus,
        );
      },
    );
  }
}

/// VS Code's title bar search box: opens Quick Open.
class _CommandCenter extends StatefulWidget {
  const _CommandCenter({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;

  /// `Search baocode (⌘P)`: upstream's `CommandCenterCenterViewItem
  /// .getTooltip` (commandCenterControl.ts), but the window title after it.
  final String tooltip;
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
    return IdeHover(
      message: widget.tooltip,
      child: MouseRegion(
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
    this.onEnd,
    this.axis = Axis.horizontal,
    this.grip = true,
    this.canMoveBack = true,
    this.canMoveForward = true,
  });

  final VoidCallback onStart;

  /// How far the pointer is from where the drag began, along [axis].
  final ValueChanged<double> onDrag;
  final VoidCallback onReset;
  final VoidCallback? onEnd;

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
    widget.onEnd?.call();
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

/// The explorer of a window without a folder: says so, with Open Folder
/// (upstream's empty view, `explorer.openFolder` welcome content).
class _NoFolder extends StatelessWidget {
  const _NoFolder({this.onOpenFolder});

  final VoidCallback? onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      children: [
        Text(
          l10n.explorerNoFolder,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: themeColors['sideBar.foreground'],
          ),
        ),
        if (onOpenFolder case final open?) ...[
          const SizedBox(height: 12),
          IdeButton(
            label: l10n.explorerOpenFolder,
            expand: true,
            onPressed: open,
          ),
        ],
      ],
    );
  }
}

/// What a markdown document's editor does with files other apps drop on
/// it: [onDrop].
class _MarkdownDrop implements FileDropDelegate {
  _MarkdownDrop(this.onDrop);

  final void Function(Offset position, List<ComposerFile> files) onDrop;

  @override
  void fileDragOver(Offset position, List<ComposerFile> files) {}

  @override
  void fileDragLeave() {}

  @override
  void fileDrop(Offset position, List<ComposerFile> files) =>
      onDrop(position, files);
}
