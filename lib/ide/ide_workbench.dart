import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../base/mouse_navigation.dart';
import '../debug/service/debug_service.dart';
import '../debug/ui/debug_strings.dart';
import '../debug/ui/debug_toolbar.dart';
import '../debug/ui/debug_view.dart';
import '../extensions/theme_extensions.dart';
import '../chat/composer/composer_files.dart' show CodeReference, ComposerFile;
import '../chat/open_editor.dart';
import '../keybindings/default_keybindings.dart' show openSettingsCommandId;
import '../l10n/l10n.dart';
import '../keybindings/keybinding_service.dart';
import '../settings/user_settings.dart';
import '../theme/codicons.dart';
import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/back_to_chat_button.dart';
import '../workspace/editor_launcher.dart';
import '../workspace/islands.dart';
import '../workspace/pin_window_button.dart';
import '../workspace/title_bar_double_click.dart';
import '../workspace/window_controls.dart';
import '../workspace/workspace.dart';

import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';

import 'extensions/ide_extensions.dart';
import 'file_service.dart' show IdeHostFiles, localizedFileError;
import 'git/commit_message.dart';
import 'git/git_repository.dart';
import 'git/ide_git_commit_panel.dart';
import 'git/ide_git_log_view.dart';
import 'git/ide_scm_view.dart';
import 'git/ide_timeline_view.dart';
import 'ide_agent_edits.dart';
import 'ide_breadcrumbs.dart';
import 'ide_command_center.dart';
import 'ide_button.dart';
import 'ide_color_theme_picker.dart';
import 'ide_columns.dart';
import 'ide_rows.dart';
import 'ide_commands.dart';
import 'ide_editor.dart';
import 'markdown/markdown_paste.dart';
import 'ide_explorer.dart';
import 'ide_local_history.dart';
import 'ide_hover.dart';
import 'ide_layout.dart';
import 'ide_modern_ui.dart';
import 'ide_diff_options.dart';
import 'ide_notifications.dart';
import 'ide_panes.dart';
import 'ide_quick_input.dart';
import 'ide_status_bar.dart';
import 'ide_tab_bar.dart';
import 'ide_welcome.dart';
import 'ide_workspace.dart';
import 'lsp/language_features.dart';
import 'lsp/lsp_protocol.dart';
import 'lsp_ui/document_symbols.dart';
import 'lsp_ui/lsp_convert.dart';
import 'lsp_ui/problems_panel.dart';
import 'lsp_ui/workspace_edit.dart';
import 'search/ide_search_view.dart';
import 'search/text_search.dart';
import 'terminal/links/terminal_links.dart';
import 'terminal/terminal_instance.dart';
import 'terminal/terminal_panel.dart';
import 'terminal/terminal_tasks.dart';
import 'terminal/terminal_hosts.dart';
import 'terminal/terminal_service.dart';
import 'host_paths.dart';
import 'services/navigation_history.dart';
import 'services/scm_service.dart';
import 'services/debug_view.dart';
import 'services/editors.dart';
import 'services/explorer.dart';
import 'services/extensions_view.dart';
import 'services/language.dart';
import 'services/keybindings.dart';
import 'services/layout.dart';
import 'services/auto_save.dart';
import 'services/chat.dart';
import 'services/configuration.dart';
import 'services/commands.dart';
import 'services/quick_input.dart';
import 'services/search_view.dart';
import 'services/lists.dart';
import 'services/markdown_preview.dart';
import 'services/problems.dart';
import 'services/references.dart';
import 'services/terminal_view.dart';
import 'workbench/contributions/all.dart';
import 'workbench/editor_panes.dart';
import 'workbench/environment.dart';
import 'workbench/parts/extensions.dart';
import 'workbench/parts/quick_input.dart';
import 'workbench/quick_access.dart';
import 'workbench/actions.dart';
import 'workbench/context_keys.dart';
import 'workbench/contributions.dart';
import 'workbench/services.dart';
import 'workbench/statusbar.dart';
import 'workbench/storage.dart';
import 'workbench/views.dart';

/// The IDE shell is kept mounted when the user returns to the conversation.
class IdeWorkbench extends StatefulWidget {
  const IdeWorkbench({
    super.key,
    required this.workspace,
    required this.project,
    required this.visible,
    required this.chat,
    this.onAddToChat,
    this.onAddCodeToChat,
    this.onAskInChat,
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
    this.themeExtensions,
    this.debugService,
    this.commitMessage = ideClaudeCommitMessage,
    this.pinned = false,
    this.onPinnedChanged,
    this.terminalBackend = const TerminalBackend(),
    this.terminalTasks,
    this.terminals,
    this.terminalHosts,
    this.colorThemes,
    this.recentFolders = const [],
    this.onOpenRecent,
    this.settings,
    this.viewState,
    this.onViewState,
    this.remote,
    this.onAddFolder,
    this.onRemoveFolder,
    this.recentWorkspaceOf,
    this.agentEdits,
  });

  final IdeWorkspace workspace;

  /// Whether its parts are islands, as the agents' window's (see
  /// [IslandStyle]): not for now, flush and square with a line between
  /// them as before; kept to come back to.
  static bool islands = false;

  /// Between two of its cards; none where they are not ([islands]).
  static double get gap => islands ? Islands.gap : 0;

  /// The multi-folder workspace a recent folder is, for the start page.
  final IdeRecentWorkspace? Function(String path)? recentWorkspaceOf;

  /// Create Workspace...: the host's command, which asks for a workspace's
  /// name and folders.
  static const createWorkspaceCommandId = 'baocode.workspace.create';

  /// Add Folder to Workspace...: of a multi-folder workspace (see
  /// [IdeWorkspace.isMultiRoot]), the host asking for the folder.
  final VoidCallback? onAddFolder;

  /// Remove Folder from Workspace, of a workspace folder's explorer row.
  final ValueChanged<String>? onRemoveFolder;

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

  /// Puts files and folders in [chat]'s composer (Source Control's Add to
  /// Chat); none offered when null.
  final ValueChanged<List<ComposerFile>>? onAddToChat;

  /// Puts lines of code in [chat]'s composer, after what is typed there
  /// (Add Selection to Chat), and the keyboard in it; with none, only the
  /// keyboard. None offered when null.
  final ValueChanged<List<CodeReference>>? onAddCodeToChat;

  /// Puts a request in [chat]'s composer, to be sent once looked over
  /// (Ask AI about a commit, changes, a conflict); none offered when null.
  final ValueChanged<String>? onAskInChat;
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

  /// What the Extensions view's Language Servers lists; the standard
  /// catalog's language servers when null.
  final IdeExtensions? extensions;

  /// The color and file icon themes installed, which the Extensions view's
  /// Themes lists and installs; that tab is not there without them.
  final ThemeExtensions? themeExtensions;

  /// The debugger; the workbench makes the workspace's when null (a fake
  /// in widget tests).
  final DebugService? debugService;

  /// Writes the Source Control view's commit messages (Claude Haiku; a
  /// fake in widget tests).
  final IdeCommitMessageModel commitMessage;

  /// The agents' changes pending in its files, shown in the editor with
  /// Undo and Keep by each change, and over its tabs for the file's.
  final IdeAgentEdits? agentEdits;

  /// Whether the window is kept on top of other apps; [onPinnedChanged]
  /// toggles it from the title bar, as the chat's pin does.
  final bool pinned;
  final ValueChanged<bool>? onPinnedChanged;

  /// Where the panel's terminals come from: the user's shell on a pseudo
  /// terminal; fakes in widget tests. Without one (the web), there is no
  /// TERMINAL tab.
  final TerminalBackend terminalBackend;

  /// The background commands of the agent in its chat, listed with the
  /// terminals (see [IdeWorkbenchState.showTerminalTask]).
  final TerminalTasks? terminalTasks;

  /// The project's terminals where the chat has them too, the same in
  /// both (kept by the chat, not disposed here); else the IDE's own, on
  /// [terminalBackend]. [terminalHosts] has where each shows, the IDE's
  /// panel one of the places.
  final TerminalService? terminals;
  final TerminalHosts? terminalHosts;

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

  /// Searches each of [roots] with [search], as one search (see
  /// [searchFolders]).
  static Stream<Object> searchRoots(
    List<String> roots,
    IdeTextQuery query,
    IdeTextSearch search,
  ) => searchFolders(roots, query, search);
}

class IdeWorkbenchState extends State<IdeWorkbench> {
  /// The window's services and what the features add with them (see
  /// docs/workbench-architecture.md): made as the workbench is, gone with
  /// it.
  final WorkbenchServices _services = WorkbenchServices();
  late final ContextKeyService _contextKeys;
  late final ActionRegistry _actions;
  late final StatusbarService _statusbar;
  late final WorkbenchStorage _storage;
  late final _Host _host = _Host(this);
  final List<WorkbenchContribution> _contributions = [];

  /// The window's services: those its features use, then the features.
  void _createServices() {
    _contextKeys = _services.add(ContextKeyService());
    _actions = _services.add(ActionRegistry());
    _statusbar = _services.add(StatusbarService());
    _storage = _services.add(WorkbenchStorage(onChanged: _keepViewSoon));
    _services
      ..add<WorkbenchHost>(_host)
      ..add<WorkbenchEnvironment>(_host);
    _config = _services.add(
      ConfigurationService(settings: () => widget.settings),
    );
    _layoutService = _services.add(
      LayoutService(host: _host, layout: () => widget.workspace.layout),
    );
    _storage.register(_layoutService);
    _commands = _services.add(
      CommandService(services: _services, actions: _actions),
    );
    _keybindings = _services.add(
      KeybindingDispatchService(
        host: _host,
        commands: _commands,
        contextKeys: _contextKeys,
        statusbar: _statusbar,
        focusNode: _workbenchFocus,
        active: () => widget.visible,
      ),
    );
    _quickInput = _services.add(
      QuickInputService(
        host: _host,
        registry: _services.add(QuickAccessRegistry()),
        focusWorkbench: () => _editors.focusEditorOrWorkbench(),
      ),
    );
    _scmService = _services.add(
      ScmService(
        host: _host,
        storage: _storage,
        settings: widget.settings,
        agentEdits: () => widget.agentEdits,
      ),
    );
    _storage.register(_scmService);
    final runs = widget.terminals != null || widget.terminalBackend.supported;
    _terminalView = _services.add(
      TerminalViewService(
        terminals: runs
            ? widget.terminals ??
                  TerminalService(
                    root: widget.workspace.root,
                    backend: widget.terminalBackend,
                  )
            : null,
        owned: widget.terminals == null,
        host: _host,
        layout: () => widget.workspace.layout,
      ),
    );
    _panes = _services.add(EditorPaneRegistry());
    _editors = _services.add(
      EditorService(
        host: _host,
        panes: _panes,
        workspace: () => widget.workspace,
        layout: () => widget.workspace.layout,
        history: () => _services.find<NavigationHistoryService>(),
        focusWorkbench: _workbenchFocus.requestFocus,
        // The one in front opened again puts the extension page behind.
        onShowEditor: () => _extensionsView.editorShown(),
        onViewChanged: _editorViewChanged,
        revealInExplorer: (path) => _explorerService.reveal(path),
      ),
    );
    _autoSave = _services.add(
      AutoSaveService(
        host: _host,
        config: _config,
        editors: _editors,
        workspace: () => widget.workspace,
      ),
    );
    _chat = ChatService(
      host: _host,
      layout: _layoutService,
      editors: _editors,
      addCode: () => widget.onAddCodeToChat,
      ask: () => widget.onAskInChat,
      back: () => widget.onBack,
    );
    _services.add(_chat);
    _searchView = _services.add(
      SearchViewService(
        host: _host,
        layout: _layoutService,
        editors: _editors,
        workspace: () => widget.workspace,
        textSearch: () => widget.textSearch,
        storage: _storage,
      ),
    );
    _storage.register(_searchView);
    _markdown = _services.add(
      MarkdownPreviewService(
        host: _host,
        storage: _storage,
        workspace: () => widget.workspace,
        caret: () => _caretPosition,
        clipboard: () => IdeWorkbench.markdownClipboard,
        insertInEditor: (text) => _editor?.insertAtCaret(text),
      ),
    );
    _storage.register(_markdown);
    _debugView = _services.add(
      DebugViewService(
        host: _host,
        given: () => widget.debugService,
        layout: () => widget.workspace.layout,
        selection: () => switch (_editor?.selection) {
          final selection? when selection.isValid => (
            start: selection.start,
            end: selection.end,
          ),
          _ => null,
        },
        settings: widget.settings,
      ),
    );
    _services.add(ListService());
    _explorerService = _services.add(
      ExplorerService(host: _host, settings: () => widget.settings),
    );
    _language = _services.add(
      LanguageService(
        host: _host,
        caret: () => _caretPosition,
        applyEdit: (edit) => switch (_editor) {
          final editor? => editor.applyWorkspaceEdit(edit),
          null => applyLspWorkspaceEdit(widget.workspace, edit),
        },
        ignored: () => widget.ignoredRecommendations,
        onIgnore: (id) => widget.onIgnoreRecommendation?.call(id),
      ),
    );
    _extensionsView = _services.add(
      ExtensionsViewService(
        host: _host,
        environment: _host,
        quickInput: _quickInput,
        themes: () => widget.themeExtensions,
        languageServers: () => widget.extensions,
        notify: (message) => _notifications.notify(IdeSeverity.error, message),
      ),
    );
    _problems = _services.add(
      ProblemsService(
        host: _host,
        language: _language,
        layout: () => widget.workspace.layout,
        caret: () => _caretPosition,
        activePath: () => widget.workspace.active?.path,
        showHover: () => _editor?.showHoverAtCaret(),
      ),
    );
    _referencesView = _services.add(
      ReferencesService(
        host: _host,
        layout: () => widget.workspace.layout,
        caret: () => _caretPosition,
        activePath: () => widget.workspace.active?.path,
      ),
    );
  }

  /// The activity bar's badge and the Git log follow Source Control; the
  /// editor's part, a markdown preview switched.
  void _servicesChanged() {
    if (mounted) setState(() {});
  }

  /// The services of ide_workbench_keys.dart and the views, for tests.
  @visibleForTesting
  WorkbenchServices get services => _services;

  final FocusNode _workbenchFocus = FocusNode(debugLabel: 'ide workbench');

  /// The Explorer view: its tree, Quick Open's files, its panes.
  late final ExplorerService _explorerService;
  IdeExplorerController get _explorer => _explorerService.controller;
  FocusNode get _explorerFocus => _explorerService.focusNode;

  /// The workspace's navigation history (Go Back, the editors by recent
  /// use, those closed).
  late NavigationHistoryService _history;

  /// The parts' layout: the side bar's view, the sizes, which part has
  /// the keyboard.
  late final LayoutService _layoutService;
  bool get _panelMaximized => _layoutService.panelMaximized;
  set _panelMaximized(bool value) => _layoutService.panelMaximized = value;
  FocusNode get _sidebarFocus => _layoutService.sidebarFocus;
  FocusNode get _chatFocus => _layoutService.chatFocus;
  FocusNode get _panelFocus => _layoutService.panelFocus;

  /// The widths the side bar and the chat open at, and have while there is
  /// room (see [IdeColumns.fit]).
  double get _chatWidth => _layoutService.chatWidth;
  set _chatWidth(double value) => _layoutService.chatWidth = value;
  double get _sidebarWidth => _layoutService.sidebarWidth;
  set _sidebarWidth(double value) => _layoutService.sidebarWidth = value;

  /// The widths, and the room for them, when a sash's drag began: it
  /// follows the pointer from there, so what it pushed aside or snapped
  /// shut comes back as it returns. (The room is the start's: the chat
  /// snapped shut takes the window's gap beside it along.)
  ({IdeColumns columns, double room})? _dragStart;

  /// Whether the chat's sash is being dragged: snapped shut, it stays till
  /// the drag ends, so the drag can bring the chat back.
  bool _chatSashDragging = false;

  /// Which parts show: the workspace's, for the window's header to toggle
  /// as well (see [IdeLayout]); [_layoutService] follows it.
  IdeLayout get _layout => widget.workspace.layout;
  bool get _sidebarShown => _layout.sidebar;
  set _sidebarShown(bool value) => _layout.sidebar = value;
  bool get _chatShown => _layout.chat;

  /// The panel's height below the editor; null is a third of the column
  /// (see [IdeRows]). Whether it shows, and what, is [_panel].
  double? get _panelHeight => _layoutService.panelHeight;
  set _panelHeight(double? value) => _layoutService.panelHeight = value;

  /// The panel's height, and the room for it, when its sash's drag began.
  ({IdeRows rows, double room})? _panelDragStart;
  IdeSideView get _view => _layoutService.view;
  set _view(IdeSideView view) => _layoutService.view = view;

  /// The workspace being taken up: its editor in front then is not one
  /// opened, which would leave the Git log.
  bool _attaching = false;

  /// The workspace's notifications (the debugger's go there too).
  IdeNotifications get _notifications => widget.workspace.notifications;

  /// Where the caret is (its column as the status bar counts it) and how
  /// much is selected: the status bar alone is built again as it moves.
  ValueNotifier<IdeEditorPosition> get _caret => _editors.caret;
  Position get _caretPosition => _editors.position;
  String? _activeKey;

  /// Source Control: the repository shown, its sessions, what opens and
  /// compares changes.
  late final ScmService _scmService;
  IdeScmSession get _scm => _scmService.session;
  IdeGitRepository? get _git => _scmService.git;

  /// The Search view's inputs and results, while other views show.
  late final SearchViewService _searchView;

  /// Whether the project's files are this machine's (not a remote host's):
  /// only then are they shown in the file manager, opened in other apps,
  /// or moved to the trash.
  bool get _local => widget.workspace.files is! IdeHostFiles;

  /// The Extensions view, and a theme extension's page.
  late final ExtensionsViewService _extensionsView;

  /// The window's commands, and the quick input (the palette is one).
  late final CommandService _commands;
  late final QuickInputService _quickInput;

  /// What a key press runs.
  late final KeybindingDispatchService _keybindings;

  /// Reads the Git status again when the app comes back to the front: a
  /// pull or a commit made elsewhere may have changed it unseen.
  AppLifecycleListener? _lifecycle;

  /// The workspace's language servers, and the active file's symbols.
  late final LanguageService _language;
  LanguageFeatures? get _languages => _language.languages;
  IdeDocumentSymbols? get _symbols => _language.symbols;

  /// The Problems and References views.
  late final ProblemsService _problems;
  late final ReferencesService _referencesView;

  /// The panel's tab, or null when the panel is hidden.
  IdePanelTab? get _panel => _layout.panel;
  set _panel(IdePanelTab? tab) => _layout.panel = tab;

  DebugService? get _debug => _debugView.service;

  /// The tab the panel shows again when toggled back.
  IdePanelTab get _lastPanel => _layout.lastPanel;

  /// The panel's terminals; none where they cannot run (the web).
  late final TerminalViewService _terminalView;
  TerminalService? get _terminals => _terminalView.terminals;

  /// The editor's panes beside the text editor (see EditorPaneRegistry).
  late final EditorPaneRegistry _panes;

  /// The editors opened, shown and closed.
  late final EditorService _editors;

  /// The markdown files' previews.
  late final MarkdownPreviewService _markdown;

  /// The workspace's debugger as the workbench shows it.
  late final DebugViewService _debugView;

  /// Settings as the window reads and toggles them; auto save; the chat
  /// beside the editor.
  late final ConfigurationService _config;
  late final AutoSaveService _autoSave;
  late final ChatService _chat;

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
    _storage.restore(kept);
    widget.workspace.viewStates.restore(kept['editorViews']);
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
    _editor?.keepViewStates();
    final paths = widget.workspace.paths;
    // Those of files (not a diff's or a revision's, nor an untitled one).
    final views = widget.workspace.viewStates.toJson(
      (key) => !key.contains('\u0000') && paths.isAbsolute(key),
    );
    return {
      'editors': editors,
      if (editors.contains(active)) 'active': active,
      if (views.isNotEmpty) 'editorViews': views,
      ..._storage.collect(),
    };
  }

  /// Once the editor has come to rest (scrolled, its caret moved): where
  /// it is kept, a scroll not written at each frame.
  void _editorViewChanged() {
    if (widget.onViewState == null) return;
    _editorViewTimer?.cancel();
    _editorViewTimer = Timer(const Duration(seconds: 1), _keepViewSoon);
  }

  Timer? _editorViewTimer;

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
    _config.reloaded();
    // The explorer's exclusions follow the file.
    _explorerService.settingsChanged();
    // Auto save turned on (or its delay changed) saves what is unsaved.
    _autoSave.schedule();
    setState(() {});
  }

  static const _sashWidth = IdeModernUI.gap;

  IdeEditorState? get _editor => _editors.editor;

  /// The file in front in the editor, its cursor and the lines selected:
  /// what the chat beside it tells the agent. None for a tab of no file of
  /// its own (untitled, a revision, one that could not open).
  OpenEditor? get openEditor {
    final doc = widget.workspace.active;
    if (doc == null || doc.isUntitled || doc.openError != null) return null;
    if (doc.isMedia) return OpenEditor(doc.path);
    if (!doc.isFile) return null;
    return OpenEditor.at(doc.path, doc.model.snapshot, _editor?.selection);
  }

  @override
  void initState() {
    super.initState();
    IdeDiffOptions.instance.attach(widget.settings);
    widget.workspace.localHistory ??= IdeLocalHistory.inDataDirectory();
    _createServices();
    _contributions.addAll(createWorkbenchContributions(_services));
    KeybindingService.instance.addListener(_keybindingsChanged);
    _registerCommandKeybindings();
    widget.agentEdits?.open = _openAgentChange;
    widget.settings?.addListener(_settingsChanged);
    widget.remote?.addListener(_remoteChanged);
    _restoreView();
    _attach();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_git?.refresh()),
      // The window left: `onFocusChange` and `onWindowChange` save.
      onInactive: () {
        unawaited(_autoSave.saveNow(const {'onFocusChange', 'onWindowChange'}));
        // Where the editors are, should the app be quit from elsewhere.
        _keepView();
      },
    );
    IdeLanguageNames.ensureLoaded(() {
      if (mounted) setState(() {});
    });
    _scmService
      ..readBranch()
      ..addListener(_servicesChanged);
    _terminalView.addListener(_terminalsChanged);
    // A preview switched to its source, or back.
    _markdown.addListener(_servicesChanged);
    // The debugger made, a session started or stopped.
    _debugView.addListener(_servicesChanged);
    // The servers or their symbols changed; references found.
    _language.addListener(_servicesChanged);
    _referencesView.addListener(_servicesChanged);
    // The explorer's panes opened or closed; an editor opening.
    _explorerService.addListener(_servicesChanged);
    _editors.addListener(_servicesChanged);
    // A part shown or hidden, here or from the window's header.
    _layoutService.addListener(_servicesChanged);
    // Format on Save or the blame toggled.
    _config.addListener(_servicesChanged);
    // An extension's page opened or closed.
    _extensionsView.addListener(_servicesChanged);
    if (widget.visible) _focusSoon();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _language.localized();
  }

  void _attach() {
    final workspace = widget.workspace;
    workspace.notifications.addListener(_notificationsChanged);
    workspace.layout.terminals = _terminals != null;
    _explorerService.attach(workspace);
    _language.attach(workspace);
    _problems.clear();
    _referencesView.clear();
    _services.add(workspace);
    _scmService.attach(workspace);
    _history = _services.add(
      NavigationHistoryService(
        workspace: workspace,
        caret: () => _caretPosition,
        open: (location) => _editors.openLocation(location, record: false),
        select: _editors.select,
      ),
    );
    workspace.addListener(_workspaceChanged);
    workspace.edits.addListener(_documentEdited);
    _layoutService.attach(workspace.layout);
    _activeKey = null;
    _attaching = true;
    _workspaceChanged();
    _attaching = false;
    // New terminals start in the project (a workspace's first folder);
    // those running stay where they are. The chat's start where it says.
    _terminalView.root = workspace.roots.firstOrNull ?? workspace.root;
    _debugView.attach(workspace);
  }

  /// A multi-folder workspace's folders, or the repository shown (of a
  /// workspace's, or of those in a folder's subfolders) changed: the
  /// explorer, Quick Open and Source Control follow.
  void _rootsChanged() {
    final workspace = widget.workspace;
    _explorerService.rootsChanged();
    if (workspace.isMultiRoot) {
      _terminalView.root = workspace.roots.firstOrNull ?? workspace.root;
    }
    _scmService.rootsChanged();
  }

  void _detach(IdeWorkspace workspace) {
    workspace.notifications.removeListener(_notificationsChanged);
    _debugView.detach(workspace);
    workspace.removeListener(_workspaceChanged);
    workspace.edits.removeListener(_documentEdited);
    _autoSave.detach();
    _services.remove<NavigationHistoryService>();
    _services.remove<IdeWorkspace>(owned: false);
    _layoutService.detach();
    _scmService.detach();
    _explorerService.detach();
    _language.detach();
  }

  /// The status bar's bell follows them.
  void _notificationsChanged() {
    if (mounted) setState(() {});
  }

  /// The terminal commands and the panel follow them.
  void _terminalsChanged() {
    if (mounted) setState(() {});
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
    if (!identical(oldWidget.agentEdits, widget.agentEdits)) {
      if (oldWidget.agentEdits?.open == _openAgentChange) {
        oldWidget.agentEdits?.open = null;
      }
      widget.agentEdits?.open = _openAgentChange;
    }
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
    if (oldWidget.debugService != widget.debugService) {
      _debugView.givenChanged();
    }
    if (oldWidget.workspace != widget.workspace) {
      _detach(oldWidget.workspace);
      _attach();
      _scmService.readBranch();
    }
    if (widget.visible && !oldWidget.visible) {
      _scmService.readBranch();
      _focusSoon();
    }
  }

  @override
  void dispose() {
    if (widget.agentEdits?.open == _openAgentChange) {
      widget.agentEdits?.open = null;
    }
    _statusUnderChat.dispose();
    KeybindingService.instance.removeListener(_keybindingsChanged);
    widget.settings?.removeListener(_settingsChanged);
    widget.remote?.removeListener(_remoteChanged);
    _editorViewTimer?.cancel();
    _keepView();
    _lifecycle?.dispose();
    // A quick pick or input box going with the workbench hides (the color
    // themes one applies the theme it started with again).
    _markdown.removeListener(_servicesChanged);
    _debugView.removeListener(_servicesChanged);
    _language.removeListener(_servicesChanged);
    _referencesView.removeListener(_servicesChanged);
    _explorerService.removeListener(_servicesChanged);
    _editors.removeListener(_servicesChanged);
    _layoutService.removeListener(_servicesChanged);
    _config.removeListener(_servicesChanged);
    _extensionsView.removeListener(_servicesChanged);
    _detach(widget.workspace);
    disposeContributions(_contributions);
    _services.dispose();
    _workbenchFocus.dispose();
    _terminalView.removeListener(_terminalsChanged);
    super.dispose();
  }

  /// An edit typed in the editor, which the workspace's own listeners
  /// hear of only when it makes the document dirty or clean again.
  void _documentEdited() {
    _language.documentChanged();
    _autoSave.schedule();
    _searchView.documentsChanged();
  }

  /// Follows the active editor: remembers it for Quick Open and reveals it
  /// in the explorer, as VS Code's `explorer.autoReveal` does.
  void _workspaceChanged() {
    _rootsChanged();
    _keepViewSoon();
    _language.documentChanged();
    _history.documentsChanged();
    _searchView.documentsChanged();
    _autoSave.documentsChanged();
    final active = widget.workspace.active;
    if (widget.workspace.takeReveal() case final range? when active != null) {
      final location = IdeLocation(active.path, range);
      // Once the editor shows it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _layout.showEditor();
        unawaited(
          _editors.openLocation(
            location,
            select: true,
            record: false,
            afterReveal: _editors.focus,
          ),
        );
      });
    }
    if (active?.key == _activeKey) return;
    // Another editor in front: `onFocusChange` saves the one left.
    if (_activeKey != null) {
      unawaited(_autoSave.saveNow(const {'onFocusChange'}));
    }
    _activeKey = active?.key;
    _history.activeChanged(active);
    if (active == null) return;
    final path = active.path;
    // Upstream's `showEditorIfHidden`: an editor opened ends the chat's
    // maximizing, and has the side bar give way to it rather than it to
    // the side bar.
    _layout.showEditor();
    // In the Git log's place, which has the editor's: the explorer's view
    // back beside it.
    if (_view == IdeSideView.sourceControl && !_attaching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _view == IdeSideView.sourceControl) {
          setState(() => _view = IdeSideView.explorer);
        }
      });
    }
    if (!_editors.closing) _extensionsView.editorShown();
    _language.recommendServers();
    _explorerService.follow(path);
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
      _editors.focusEditorOrWorkbench();
    });
  }

  /// Hands [path] to the app the system opens it with (a file the IDE
  /// does not show: a PDF, a video…).
  Future<void> _openInDefaultApp(String path) async {
    if (await IdeWorkbench.openInDefaultApp(path) || !mounted) return;
    _report(context.l10n.openInDefaultAppFailed(hostBasename(path)));
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

  /// The next file with an agent's change pending, once one is done.
  void _openAgentChange(String path) => unawaited(_editors.open(path));

  void _leaveGitLog() => _scmService.leaveGitLog();

  // --- Language features ---------------------------------------------------

  /// Go Back (⌃-) / Go Forward (⌃⇧-), and the mouse's back and forward
  /// buttons: whether there was somewhere to go.
  bool _navigate({required bool back}) => _history.navigate(back: back);

  Future<String?> _textOf(String path) async {
    for (final doc in widget.workspace.documents) {
      if (doc.path == path) return doc.text;
    }
    return widget.workspace.files.read(path);
  }

  // --- Quick input ---------------------------------------------------------

  /// Opens [model] in the quick input, for the views the workbench hosts
  /// (e.g. its chat).
  void showQuickPick(IdeQuickInputModel model) => _quickInput.showModel(model);

  /// Opens [path] in an editor and focuses it (the host's Open File…).
  Future<void> openFile(String path) => _editors.open(path, focusEditor: true);

  /// Shows the chat, if hidden (e.g. for an agent a notification opens).
  void showChat() => _layout.showChat();

  /// Shows the output of the background command [id] (one of its chat's)
  /// on the panel's TERMINAL tab.
  void showTerminalTask(String id) => _terminalView.showTask(id);

  /// Has the editor's last keys in its document, for what is unsaved to be
  /// all of it (before its window closes, or the app quits).
  Future<void> flush() async => _editors.flush();

  /// Whether the panel's terminals run: a shell alive, or
  /// ([childProcesses]) one running a command
  /// (`terminal.integrated.confirmOnExit`).
  bool terminalsRunning({required bool childProcesses}) =>
      _terminalView.running(childProcesses: childProcesses);

  /// Tells of [message] as the IDE's own notifications do.
  void notify(IdeSeverity severity, String message) =>
      _notifications.notify(severity, message);

  /// Runs the command [id] (the palette's, or one of its keybindings'),
  /// as a menu does; false when there is none here, or it cannot run now.
  bool runCommand(String id) => _commands.runById(id);

  // --- Keybindings ---------------------------------------------------------

  /// The context keys a keybinding's `when` reads, as they are now.
  @visibleForTesting
  Object? keyContext(String key) => _contextKeys.getValue(key);

  // --- Commands ------------------------------------------------------------

  /// The palette's commands: the features', the editor's, the app's.
  List<IdeCommand> _allCommands() => _commands.palette();

  /// Takes the .vsix files and extension folders among [paths] dropped on
  /// the window: false when there are none.
  bool dropExtensions(List<String> paths) => _extensionsView.drop(paths);

  /// The commands for the current state, for the palette and for tests.
  @visibleForTesting
  List<IdeCommand> get commands => _allCommands();

  /// Those and the keybinding-only ones (the lists', the quick input's…),
  /// by id, for tests.
  @visibleForTesting
  Map<String, IdeCommand> get commandsById => _commands.byId();

  // --- Widgets -------------------------------------------------------------

  /// The activity bar; its view's item is selected when [sidebarShowing].
  Widget _activityBar({required bool sidebarShowing}) {
    Widget item(IdeSideView view, IconData icon, String label, {int? badge}) {
      // The side bar as it shows: one given way to the chat opens.
      final selected = _view == view && sidebarShowing;
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
            (_scmService.count > 0
                ? ' - ${l10n.wbPendingChanges(_scmService.count)}'
                : ''),
        badge: _scmService.count,
      ),
      if (debugEntryShown)
        item(
          IdeSideView.debug,
          Codicons.debugAlt,
          keys.titleWithKeybinding(
            DebugStrings.of(context).runAndDebug,
            'workbench.view.debug',
          ),
        ),
      item(
        IdeSideView.extensions,
        Codicons.extensions,
        keys.titleWithKeybinding(l10n.extTitle, 'workbench.view.extensions'),
      ),
    ];
    // Settings at its foot, as upstream's Manage gear: the chat's sidebar
    // has them, the IDE had no way to them but the palette.
    final settings = _host.hostCommand(openSettingsCommandId);
    return SizedBox(
      width: IdeModernUI.activityBarWidth,
      // On the window's color, beside the cards; not islands, a part of
      // its own, its line beside the side bar.
      child: IdePart(
        color: IdeWorkbench.islands ? null : IdeModernUI.activityBarBackground,
        border: IdeWorkbench.islands
            ? null
            : Border(right: IdePart.side('activityBar.border')),
        child: Padding(
          // Half the lane above and below; the items centered across.
          padding: const EdgeInsets.symmetric(
            vertical: IdeModernUI.activityLane / 2,
          ),
          child: Column(
            children: [
              for (final (index, item) in items.indexed) ...[
                if (index > 0)
                  const SizedBox(height: IdeModernUI.activityItemGap),
                item,
              ],
              if (settings != null) ...[
                const Spacer(),
                _ActivityItem(
                  key: const ValueKey('ide.activity.settings'),
                  icon: Codicons.settingsGear,
                  label: keys.titleWithKeybinding(
                    l10n.settingsTitle,
                    openSettingsCommandId,
                  ),
                  selected: false,
                  onTap: settings.run,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The side bar: its view on a card, its title in it; the Git log,
  /// cards of its own, untitled. Not islands, a part of the side bar's
  /// color, its line at its right but where it has the editor's place
  /// ([border]).
  Widget _sidebarPart({bool border = true}) {
    final view = Focus(focusNode: _sidebarFocus, child: _sidePanel());
    if (!IdeWorkbench.islands) {
      return IdePart(
        color: themeColors['sideBar.background'],
        border: border ? Border(right: _sideBarBorder) : null,
        child: view,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Islands.gap / 2),
      child: _view == IdeSideView.sourceControl
          ? view
          : HeadedIsland(header: 0, color: AppColors.code, child: view),
    );
  }

  /// Not islands, between the side bars and the editor: `sideBar.border`,
  /// else the Modern UI's `surface.border`, so every theme has the line.
  static BorderSide get _sideBarBorder =>
      IdePart.side('sideBar.border', fallback: 'surface.border');

  Widget _sidePanel() => switch (_view) {
    IdeSideView.explorer => _explorerView(),
    IdeSideView.search => IdeSearchView(
      key: _searchView.viewKey,
      session: _searchView.session,
      root: widget.workspace.root,
      // The workspace's own: replacing writes into its documents.
      replaceBackend: widget.workspace,
      onOpen: (path, range, {required focusEditor}) => _editors.open(
        path,
        range: range,
        select: true,
        focusEditor: focusEditor,
      ),
      onError: _report,
    ),
    // The Git log, in the side bar's and the editor's place (see
    // [_split]): the local changes' commit box and groups its first row's
    // details, their changes in its table's place.
    IdeSideView.sourceControl => IdeGitLogView(
      key: _scmService.logKey,
      host: widget.workspace,
      session: _scm,
      notifications: _notifications,
      islands: IdeWorkbench.islands,
      ai: widget.commitMessage,
      onAsk: _chat.canAsk ? _chat.ask : null,
      onFixup: (git, commit) async =>
          _scmService.panelKey.currentState?.fixupInto(git, commit),
      onOpen: (path) {
        _leaveGitLog();
        unawaited(_editors.open(path, focusEditor: true));
      },
      onAddToChat: widget.onAddToChat,
      // Another worktree's changes and branch in Source Control.
      worktrees: IdeGitWorktreeChoice(
        following: false,
        onSelect: widget.workspace.openWorktree == null
            ? null
            : (path) {
                if (path != null) widget.workspace.showWorktree(path);
              },
      ),
      changes: IdeGitCommitPanel(
        onAsk: _chat.canAsk ? _chat.ask : null,
        key: _scmService.panelKey,
        host: widget.workspace,
        session: _scm,
        sessionOf: _scmService.sessionOf,
        notifications: _notifications,
        onOpen: (path, {focusEditor = false}) {
          _leaveGitLog();
          return _editors.open(path, focusEditor: focusEditor);
        },
        onOpenChange: _scmService.openChangeInLog,
        onRevealInExplorer: (path) {
          _leaveGitLog();
          _explorerService.reveal(path);
        },
        onAddToChat: widget.onAddToChat,
        trash: WindowControls.canMoveToTrash
            ? WindowControls.moveToTrash
            : null,
        commitMessage: widget.commitMessage,
        hunks: _scmService.hunks,
        changelists: _scmService.changelists,
        onShowDiff: (files, index) => _scm.log.showDiff(files, index),
        onOpenAt: (path, line) {
          _leaveGitLog();
          return _editors.open(
            path,
            line: line,
            center: true,
            focusEditor: true,
          );
        },
      ),
    ),
    IdeSideView.debug => switch (_debug) {
      final debug? => DebugView(
        service: debug,
        runAndDebugKey: _debugView.runAndDebugKey,
      ),
      null => const SizedBox.shrink(),
    },
    IdeSideView.extensions => ExtensionsViewPart(
      service: _extensionsView,
      language: _language,
      islands: IdeWorkbench.islands,
    ),
  };

  /// The Explorer view: the folder's tree, the active editor's outline and
  /// its file's timeline, as panes.
  Widget _explorerView() {
    final workspace = widget.workspace;
    final activePath = workspace.active?.path;
    final timelinePath = IdeTimelineView.pathOf(
      _explorerService.timeline,
      activePath,
    );
    // The folder's actions are the explorer's commands: their keybindings
    // in their tooltips (upstream's `MenuEntryActionViewItem.getTooltip`).
    final keys = KeybindingService.instance;
    // Over a card (the side bar's, under this, its title in it too): its
    // color under the panes.
    return Builder(
      builder: (context) => ColoredBox(
        color: IslandSurface.colorOf(context) == null
            ? AppColors.background
            : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IdeViewTitle(context.l10n.wbExplorer),
            Expanded(
              child: IdePaneContainer(
                expanded: _explorerService.panes,
                onToggle: _explorerService.togglePane,
                panes: [
                  if (!workspace.hasFolder)
                    IdePane(
                      id: 'folder',
                      title: context.l10n.explorerNoFolderTitle,
                      weight: 3,
                      body: _NoFolder(
                        onOpenFolder: _host
                            .hostCommand('workbench.action.files.openFolder')
                            ?.run,
                      ),
                    )
                  else
                    IdePane(
                      id: 'folder',
                      title: workspace.isMultiRoot
                          ? context.l10n.ideWorkspaceTitle(widget.project.name)
                          : widget.project.name,
                      weight: 3,
                      actions: [
                        if (widget.onAddFolder case final add?
                            when workspace.isMultiRoot)
                          IdePaneAction(
                            icon: Codicons.rootFolder,
                            tooltip: context.l10n.ideAddFolderToWorkspace,
                            onPressed: add,
                          ),
                        IdePaneAction(
                          icon: Codicons.newFile,
                          tooltip: keys.titleWithKeybinding(
                            context.l10n.explorerNewFile,
                            'explorer.newFile',
                          ),
                          onPressed: () => unawaited(
                            _explorerService.view?.startCreate(
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
                            _explorerService.view?.startCreate(directory: true),
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
                      body: workspace.isMultiRoot && workspace.roots.isEmpty
                          ? _EmptyWorkspace(onAddFolder: widget.onAddFolder)
                          : IdeExplorer(
                              key: _explorerService.tree,
                              controller: _explorer,
                              focusNode: _explorerFocus,
                              isBound: (event) =>
                                  _keybindings.resolveEditorKey(event) != null,
                              git: workspace.git,
                              repositories: [
                                for (final (_, git) in workspace.repositories)
                                  git,
                              ],
                              onAddFolder: workspace.isMultiRoot
                                  ? widget.onAddFolder
                                  : null,
                              onRemoveFolder: workspace.isMultiRoot
                                  ? widget.onRemoveFolder
                                  : null,
                              onOpen: (path, focusEditor) => unawaited(
                                _editors.open(path, focusEditor: focusEditor),
                              ),
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
                              onFindInFolder: _searchView.findInFolder,
                              onOpenInTerminal: _terminals == null
                                  ? null
                                  : _terminalView.openIn,
                              onShowHistory: _scmService.showHistory,
                              onShowLocalHistory: (path) =>
                                  unawaited(_scmService.showLocalHistory(path)),
                              onCompareFiles:
                                  (original, modified, {folders = false}) =>
                                      unawaited(
                                        _scmService.compareFiles(
                                          original,
                                          modified,
                                          folders: folders,
                                        ),
                                      ),
                            ),
                    ),
                  IdePane(
                    id: 'outline',
                    title: context.l10n.wbOutline,
                    body: ListenableBuilder(
                      listenable: _caret,
                      builder: (context, _) => IdeOutlineView(
                        symbols: _symbols,
                        caret: workspace.active == null
                            ? null
                            : _language.caret,
                        onReveal: _language.revealSymbol,
                        showHeader: false,
                      ),
                    ),
                  ),
                  IdePane(
                    id: 'timeline',
                    title: context.l10n.wbTimeline,
                    description: timelinePath == null
                        ? null
                        : hostBasename(timelinePath),
                    actions: [
                      IdePaneAction(
                        icon: _explorerService.timeline.pinned == null
                            ? Codicons.pin
                            : Codicons.pinned,
                        tooltip: _explorerService.timeline.pinned == null
                            ? context.l10n.wbPinTimeline
                            : context.l10n.wbUnpinTimeline,
                        onPressed: () =>
                            _explorerService.toggleTimelinePin(activePath),
                      ),
                      IdePaneAction(
                        icon: Codicons.refresh,
                        tooltip: context.l10n.commonRefresh,
                        onPressed: _explorerService.timeline.refresh,
                      ),
                    ],
                    body: IdeTimelineView(
                      controller: _explorerService.timeline,
                      // The file's repository: one in a subfolder, if so.
                      git: switch (timelinePath) {
                        final path? => workspace.gitAt(path),
                        null => workspace.git,
                      },
                      activePath: activePath,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editorArea(List<IdeCommand> commands) {
    final active = widget.workspace.active;
    final page = _extensionsView.page;
    final pageShown = _extensionsView.pageShown;
    final debug = _debug;
    final dockedToolbar =
        debug != null && debug.settings().toolBarLocation == 'docked';
    // Its tabs on the window's color over its card; their row there with
    // none, the card's top where the side bar's and the chat's are.
    final tabs = widget.workspace.documents.isNotEmpty || page != null;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: IdeWorkbench.gap / 2),
      child: HeadedIsland(
        header: IdeTabStrip.height,
        color: themeColors['editor.background'],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!tabs) ...[
              // Not islands, no row: nothing over the editor's part.
              if (IdeWorkbench.islands)
                const SizedBox(height: IdeTabStrip.height),
              if (dockedToolbar) DebugToolbar(service: debug),
            ],
            if (tabs) ...[
              IdeTabBar(
                documents: widget.workspace.documents,
                active: pageShown ? null : active,
                root: widget.workspace.root,
                onSelect: (doc) => unawaited(_editors.select(doc)),
                onClose: (doc) => unawaited(_editors.close(doc)),
                onAction: _editors.tabAction,
                onMove: widget.workspace.moveDocument,
                local: _local,
                markdownPreview:
                    !pageShown && active != null && _markdown.hasPreview(active)
                    ? _markdown.previewing(active)
                    : null,
                onMarkdownPreview: (preview) =>
                    unawaited(_markdown.setPreview(preview)),
                page: page == null
                    ? null
                    : ExtensionPageTab(service: _extensionsView),
                actions: switch (widget.agentEdits) {
                  final edits? when !pageShown && active != null =>
                    ListenableBuilder(
                      listenable: edits,
                      builder: (context, _) => switch (edits.of(active.path)) {
                        final edit? when active.diff == null =>
                          IdeAgentEditActions(
                            edit: edit,
                            hunks: edits.hunksOf(active.path),
                          ),
                        _ => const SizedBox.shrink(),
                      },
                    ),
                  _ => null,
                },
              ),
              // On the card, under the tabs.
              if (dockedToolbar) DebugToolbar(service: debug),
              if (!pageShown && active != null && !active.isUntitled)
                ListenableBuilder(
                  listenable: _caret,
                  builder: (context, _) => IdeBreadcrumbs(
                    root: widget.workspace.root,
                    path: active.path,
                    onReveal: _explorerService.reveal,
                    symbols: _language.symbolPath,
                    onSymbol: _language.revealSymbol,
                  ),
                ),
            ],
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // The editors stay built under an extension's page.
                  Offstage(
                    offstage: pageShown,
                    child: _markdown.drops(
                      active,
                      active == null && !widget.workspace.hasFolder
                          ? IdeStartPage(
                              actions: [
                                for (final id in const [
                                  'workbench.action.files.openFolder',
                                  'git.clone',
                                  'baocode.remote.openFolder',
                                  IdeWorkbench.createWorkspaceCommandId,
                                  'workbench.action.files.openFile',
                                  'workbench.action.files.newUntitledFile',
                                ])
                                  ...commands.where(
                                    (command) => command.id == id,
                                  ),
                              ],
                              recent: widget.recentFolders,
                              onOpenRecent: widget.onOpenRecent,
                              workspaceOf: widget.recentWorkspaceOf,
                              onShowAllRecent: commands
                                  .where(
                                    (c) =>
                                        c.id == 'workbench.action.openRecent',
                                  )
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
                                  ...commands.where(
                                    (command) => command.id == id,
                                  ),
                              ],
                            )
                          // A pane of its own (a file view, an image, a
                          // preview), else the text editor.
                          : _panes.paneFor(active)?.build(context, active) ??
                                widget.editorBuilder?.call(
                                  context,
                                  widget.workspace,
                                ) ??
                                IdeEditor(
                                  nativeEditorEnabled:
                                      widget.nativeEditorEnabled,
                                  key: _editors.editorKey,
                                  workspace: widget.workspace,
                                  active: active,
                                  onError: _report,
                                  onLspStatus: (_) {},
                                  onPositionChanged: _editors.positionChanged,
                                  onScrolled: _editorViewChanged,
                                  // Go to Definition's target (F12),
                                  // centered even when already in view.
                                  onOpenLocation: (location) => _editors
                                      .openLocation(location, center: true),
                                  onShowReferences: _referencesView.show,
                                  onShowCommands: () => _quickInput.show('>'),
                                  gitBlame: _config.gitBlame,
                                  onShowCommit: _scmService.showCommitInLog,
                                  onShowHistory: _scmService.showHistory,
                                  onCompare: (path, what) => unawaited(
                                    _scmService.compareWith(path, what),
                                  ),
                                  keyResolver: _keybindings.resolveEditorKey,
                                  onPaste: _markdown.pasteInEditor,
                                  formatOnSave: _config.formatOnSave,
                                  debug: _debug,
                                  agentEdits: widget.agentEdits,
                                ),
                    ),
                  ),
                  // And it under them, while another tab is in front.
                  if (page != null)
                    Offstage(
                      offstage: !pageShown,
                      child: ExtensionPageView(service: _extensionsView),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The chat, kept mounted (and its state kept) while hidden.
  /// [trailing]: the status bar's right items, in the row under its card.
  Widget _chatSlot(double width, {Widget? trailing}) {
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
            child: ExcludeFocus(
              excluding: !shown,
              child: _chatPart(trailing: trailing),
            ),
          ),
        ),
      ),
    );
  }

  /// The chat, which keeps its state as it moves to the editor's place,
  /// maximized, and back: its tabs on the window's color over its card.
  Widget _chatPart({Widget? trailing}) => Padding(
    key: _chatKey,
    padding: EdgeInsets.symmetric(horizontal: IdeWorkbench.gap / 2),
    child: IslandFootTrailing(
      trailing: trailing,
      onRoom: (room) {
        _chatFootRoom = room;
        _fitStatus();
      },
      child: HeadedIsland(
        header: IdeTabStrip.height,
        // In its own column, down to the window's foot: its branch under
        // its card, in the status bar's row, then [trailing]; in the
        // editor's place, the panel under it.
        footer: _layout.editorVisible ? Islands.belowHeight : 0,
        color: AppColors.code,
        // Not islands: beside the editor, the secondary side bar, the side
        // bar's line on its left; its row in line with the status bar.
        border: _layout.editorVisible ? Border(left: _sideBarBorder) : null,
        footerLine: IdeStatusBar.line,
        footerColor: themeColors.get('statusBar.background'),
        child: Focus(focusNode: _chatFocus, child: widget.chat),
      ),
    ),
  );
  final _chatKey = GlobalKey(debugLabel: 'ide chat');

  /// How many of the status bar's right items, from its end, are in the
  /// row under the chat, after its branch: as many as fit there, the rest
  /// at the end of the bar under the rest.
  final _statusUnderChat = ValueNotifier(0);

  /// The status bar's right items' widths, by index, wherever they are.
  final _statusWidths = <int, double>{};

  /// How many right items the status bar has.
  int _statusRight = 0;

  /// The room for them under the chat, after its branch.
  double _chatFootRoom = 0;
  bool _fittingStatus = false;

  void _noteStatusWidth(int index, double width) {
    _statusWidths[index] = width;
    _fitStatus();
  }

  /// [_statusUnderChat] from what was measured: told in layout, set after
  /// the frame.
  void _fitStatus() {
    if (_fittingStatus) return;
    _fittingStatus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fittingStatus = false;
      if (!mounted) return;
      var (width, fit) = (0.0, 0);
      for (var i = _statusRight - 1; i >= 0; i--) {
        final item = _statusWidths[i];
        if (item == null || width + item > _chatFootRoom) break;
        width += item;
        fit++;
      }
      _statusUnderChat.value = fit;
    });
  }

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

  /// The parts, flush and square: the activity bar, the side bar, the
  /// editor (the panel below it) and the chat, each sash over the line
  /// between two (VS Code's `sash-size`, half on either side). The chat
  /// stays on the right however narrow the window (see [IdeColumns.fit]).
  /// With the editor hidden ([IdeLayout.editorHidden]), the chat has its
  /// place, beside the side bar if that shows, the panel below the two.
  /// [statusChanges]: what changes the status bar.
  Widget _split(
    Size size,
    List<IdeCommand> commands,
    Listenable statusChanges,
  ) {
    // The activity bar's room: its lane at the right the half gap the card
    // after it keeps, so the card is against it, its items as far from
    // either side.
    final bar = IdeModernUI.activityBarWidth - IdeWorkbench.gap / 2;
    // The editor hidden, the chat is sized as though it were there: dragged
    // back, the editor comes out where the pointer is.
    final room = size.width - bar;
    _noteRoom((
      both: IdeColumns.roomForBoth(room),
      sides: IdeColumns.roomForSides(room),
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
    // Source Control, the Git log, has the side bar's and the editor's
    // place, above the panel; the editor is kept, back as another view
    // shows.
    final gitLog =
        !editorHidden && sidebarVisible && _view == IdeSideView.sourceControl;
    final sidebar = SizedBox(
      key: const ValueKey('ide-sidebar'),
      width: columns.sidebar,
      child: KeyedSubtree(key: _sidebarKey, child: _sidebarPart()),
    );
    // With the side bar hidden, by the activity bar: dragged out, it opens
    // the side bar.
    final sidebarSash = KeyedSubtree(
      key: _sidebarSashKey,
      child: _Sash(
        key: const ValueKey('ide-sidebar-sash'),
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
    final chatSash = _Sash(
      key: const ValueKey('ide-chat-sash'),
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
    );
    // The chat in its column, the status bar's right items are in the row
    // under its card, after its branch, against the window's edge, as many
    // as fit there; the bar under the rest has the others.
    final underChat = !editorHidden && chatVisible;
    final status = Listenable.merge([statusChanges, _statusUnderChat]);
    int under(int right) {
      _statusRight = right;
      return underChat ? math.min(_statusUnderChat.value, right) : 0;
    }

    final statusBar = ListenableBuilder(
      listenable: status,
      builder: (context, _) {
        final bar = _statusBar();
        final right = bar.right;
        return IdeStatusBar(
          left: bar.left,
          right: right.sublist(0, right.length - under(right.length)),
          onRightWidth: _noteStatusWidth,
        );
      },
    );
    final statusTrailing = underChat
        ? ListenableBuilder(
            listenable: status,
            builder: (context, _) {
              final right = _statusBar().right;
              final start = right.length - under(right.length);
              return IdeStatusBarTrailing(
                right: right.sublist(start),
                onWidth: (i, width) => _noteStatusWidth(start + i, width),
              );
            },
          )
        : null;
    final chat = KeyedSubtree(
      key: const ValueKey('ide-chat'),
      child: _chatPart(),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The status bar under all but the chat, which has its own
              // row there (its branch, then the bar's right items), as in
              // the agents' window.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: bar,
                            child: OverflowBox(
                              alignment: Alignment.centerLeft,
                              minWidth: IdeModernUI.activityBarWidth,
                              maxWidth: IdeModernUI.activityBarWidth,
                              child: KeyedSubtree(
                                key: const ValueKey('ide-activity-bar'),
                                child: _activityBar(
                                  sidebarShowing: sidebarVisible,
                                ),
                              ),
                            ),
                          ),
                          if (!editorHidden && sidebarVisible && !gitLog)
                            sidebar,
                          Expanded(
                            key: const ValueKey('ide-editor-column'),
                            child: _editorColumn(
                              size.height - IdeStatusBar.height,
                              commands,
                              inPlace: gitLog
                                  ? KeyedSubtree(
                                      key: _sidebarKey,
                                      child: _sidebarPart(border: false),
                                    )
                                  : !editorHidden
                                  ? null
                                  : sidebarVisible
                                  ? Stack(
                                      children: [
                                        Positioned.fill(
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              sidebar,
                                              Expanded(child: chat),
                                            ],
                                          ),
                                        ),
                                        _sashAt(
                                          columns.sidebar,
                                          room,
                                          sidebarSash,
                                        ),
                                      ],
                                    )
                                  : chat,
                            ),
                          ),
                        ],
                      ),
                    ),
                    statusBar,
                  ],
                ),
              ),
              if (!editorHidden)
                _chatSlot(columns.chat, trailing: statusTrailing),
            ],
          ),
        ),
        if (!editorHidden && !gitLog)
          _sashAt(bar + columns.sidebar, size.width, sidebarSash),
        if (!editorHidden && (chatVisible || _chatSashDragging))
          _sashAt(size.width - columns.chat, size.width, chatSash)
        else if (editorHidden && !sidebarVisible)
          // The chat maximized: its sash is by the activity bar, and
          // dragged back, the editor comes out.
          _sashAt(bar, size.width, chatSash),
      ],
    );
  }

  /// [sash] over the line [x] across a row [width] wide, inside it: at the
  /// row's edge, all of it on the near side.
  static Widget _sashAt(double x, double width, Widget sash) => Positioned(
    key: ValueKey(sash.key),
    left: (x - _sashWidth / 2)
        .clamp(0.0, math.max(0.0, width - _sashWidth))
        .toDouble(),
    top: 0,
    bottom: 0,
    width: _sashWidth,
    child: sash,
  );

  /// The editor, and below it the panel (the terminal), as VS Code's panel
  /// at the bottom, centered: under the editor only. Hidden, the panel
  /// leaves its sash at the bottom. [inPlace] has the editor's place where
  /// it is hidden (the chat, and the side bar beside it), above the panel;
  /// the editor is kept, as the chat hidden is.
  Widget _editorColumn(
    double height,
    List<IdeCommand> commands, {
    Widget? inPlace,
  }) {
    final hidden = inPlace != null;
    final shown = _panel != null;
    final room = height;
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
    final debug = _debug;
    final editor = KeyedSubtree(
      key: const ValueKey('ide-editor'),
      child: _editorArea(commands),
    );
    final toolbarLocation = debug?.settings().toolBarLocation;
    // In the middle of the gap over the panel's card.
    final sashTop =
        (height - rows.panel + IdeWorkbench.gap / 2 - _sashWidth / 2)
            .clamp(0.0, math.max(0.0, height - _sashWidth))
            .toDouble();
    return Stack(
      children: [
        Positioned.fill(
          child: Column(
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
                          child: toolbarLocation == 'floating' && debug != null
                              ? FloatingDebugToolbar(
                                  service: debug,
                                  child: editor,
                                )
                              : editor,
                        ),
                      ),
                    ),
                    ?inPlace,
                  ],
                ),
              ),
              _panelSlot(rows.panel),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: sashTop,
          height: _sashWidth,
          child: _Sash(
            key: const ValueKey('ide-panel-sash'),
            axis: Axis.vertical,
            canMoveBack: rows.canGrowPanel(room),
            canMoveForward: panelVisible,
            onStart: () => _panelDragStart = (rows: rows, room: room),
            onDrag: _dragPanel,
            onReset: () => setState(() {
              _panel ??= _lastPanel;
              _panelHeight = null;
            }),
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
          _editors.open(
            link.path!,
            line: link.line,
            column: link.column,
            focusEditor: true,
          ),
        );
      case TerminalLinkType.localFolder:
        if (link.inWorkspace) {
          _explorerService.reveal(link.path!);
        } else {
          unawaited(openExternal(link.path!));
        }
      case TerminalLinkType.search:
        _quickInput.show(link.searchText ?? link.text);
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
                // On a card of its own a gap under the editor's, of the
                // cards' color (not `panel.background`: a card as the
                // others). Not islands, panelPart.ts' `panel.background`,
                // `panel.border` above.
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    IdeWorkbench.gap / 2,
                    IdeWorkbench.gap,
                    IdeWorkbench.gap / 2,
                    0,
                  ),
                  child: IdePart(
                    border: IdeWorkbench.islands
                        ? null
                        : Border(top: IdePart.side('panel.border')),
                    child: Island(
                      color: IdeWorkbench.islands
                          ? AppColors.code
                          : themeColors['panel.background'],
                      child: IdeBottomPanel(
                        tab: _panel ?? _lastPanel,
                        root: widget.workspace.root,
                        languages: _languages,
                        references: _referencesView.references,
                        // TERMINAL, clicked, gives its terminal the keyboard.
                        onTab: (tab) => tab == IdePanelTab.terminal
                            ? _terminalView.show()
                            : (_layoutService.panel = tab),
                        onClose: () => setState(() => _panel = null),
                        onOpen: (location, {select = false}) => unawaited(
                          _editors.openLocation(location, select: select),
                        ),
                        onOpenFocused: (location) =>
                            unawaited(openWithKeyboard(_host, location)),
                        problemsList: _problems.list,
                        referencesList: _referencesView.list,
                        textOf: _textOf,
                        terminal: switch (_terminals) {
                          final terminals? => TerminalPanel(
                            terminals: terminals,
                            tasks: widget.terminalTasks,
                            files: widget.workspace.files,
                            shownTask: _terminalView.task,
                            onShowTask: _terminalView.showTask,
                            onNew: _terminalView.create,
                            onOpenLink: _openTerminalLink,
                            shouldSkipShell: _keybindings.terminalSkipsShell,
                            resolveKey: _keybindings.terminalFindKey,
                            hosts: widget.terminalHosts,
                            place: this,
                            shown: widget.visible,
                          ),
                          null => null,
                        },
                        debugConsole: switch (_debug) {
                          final debug? => DebugConsolePanel(service: debug),
                          null => null,
                        },
                        terminalActions: switch (_terminals) {
                          final terminals? => TerminalTitleActions(
                            terminals: terminals,
                            onNew: _terminalView.create,
                            onNewWithProfile: (profile) =>
                                _terminalView.create(profile: profile),
                            onSelectDefaultProfile: () =>
                                unawaited(_terminalView.selectDefaultProfile()),
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
                child: IdeCommandCenter(
                  label: widget.workspace.hasFolder
                      ? widget.project.name
                      : l10n.ideSearchOpenFiles,
                  tooltip: keys.titleWithKeybinding(
                    widget.workspace.hasFolder
                        ? l10n.ideSearchProject(widget.project.name)
                        : l10n.ideSearchOpenFiles,
                    'workbench.action.quickOpen',
                  ),
                  onSearch: () => _quickInput.show(''),
                  navigation: widget.workspace.navigation,
                  onNavigate: (back) => _navigate(back: back),
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
                      onPressed: () => unawaited(_chat.back()),
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
    final l10n = context.l10n;
    // The entries not yet the status bar service's, with the priorities
    // they will have (the greater, the further left).
    final left = <(double, IdeStatusBarItem)>[
      if (widget.remote?.item(context) case final item?) (100, item),
      if (_statusbar.message case final message?)
        (50, IdeStatusBarItem(message)),
    ];
    final bell = ideNotificationsStatusItem(_notifications, l10n: l10n);
    final leftItems = mergeStatusbarItems(
      left,
      _statusbar.entries(context, StatusbarAlignment.left),
    );
    return IdeStatusBar(
      left: leftItems,
      right: mergeStatusbarItems([
        (-1000, bell),
      ], _statusbar.entries(context, StatusbarAlignment.right)),
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
          onKeyEvent: _keybindings.onKey,
          // The explorer's uploads and downloads show their progress here.
          child: IdeNotificationsScope(
            notifications: _notifications,
            child: Material(
              color: IdeModernUI.shell,
              child: Stack(
                children: [
                  Column(
                    children: [
                      if (!WindowControls.drawsHeader) _titleBar(),
                      Expanded(
                        // The other half of the gap at the window's right
                        // (each card keeps half a gap about it).
                        child: Padding(
                          padding: EdgeInsets.only(right: IdeWorkbench.gap / 2),
                          child: LayoutBuilder(
                            builder: (context, constraints) => _split(
                              constraints.biggest,
                              commands,
                              // Typing moves the caret and edits the
                              // document, and the status bar is all that
                              // shows either; as it is all that shows a
                              // language server's progress.
                              Listenable.merge([
                                _caret,
                                _statusbar,
                                widget.workspace.edits,
                                _languages?.progressChanges,
                              ]),
                            ),
                          ),
                        ),
                      ),
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
                      child: IdeNotificationToasts(
                        notifications: _notifications,
                      ),
                    ),
                  ),
                  QuickInputPart(
                    service: _quickInput,
                    top: WindowControls.drawsHeader
                        ? 0
                        : AppMetrics.titleBarHeight,
                  ),
                ],
              ),
            ),
          ),
        );
        // The mouse's back and forward buttons go back and forward, as
        // upstream's `registerMouseNavigationListener` has them; where
        // what is under the pointer does not go back first (a subagent in
        // the chat, a commit's changes in the Git log).
        return WorkbenchScope(
          services: _services,
          child: MouseNavigation(
            onBack: () => _navigate(back: true),
            onForward: () => _navigate(back: false),
            child: IslandStyle(on: IdeWorkbench.islands, child: focus),
          ),
        );
      },
    );
  }
}

/// What the services need of the workbench's widgets.
class _Host implements WorkbenchHost, WorkbenchEnvironment {
  _Host(this._state);

  final IdeWorkbenchState _state;

  @override
  UserSettings? get settings => _state.widget.settings;

  @override
  IdeColorThemeController? get colorThemes => _state.widget.colorThemes;

  @override
  List<IdeCommand> get hostCommands => _state.widget.commands;

  @override
  BuildContext? get context => _state.mounted ? _state.context : null;

  @override
  Future<void> flushEditor() => _state._editors.flush();

  @override
  void focusEditor() => _state._editors.focus();

  @override
  Future<void> openFile(
    String path, {
    int? line,
    int? column,
    LspRange? range,
    bool focusEditor = false,
  }) => _state._editors.open(
    path,
    line: line,
    column: column,
    range: range,
    focusEditor: focusEditor,
  );

  @override
  Future<void> openInDefaultApp(String path) => _state._openInDefaultApp(path);

  @override
  void revealLine(int line, [int column = 1]) =>
      _state._editors.revealLine(line, column);

  @override
  void revealRange(
    LspRange range, {
    bool select = false,
    bool center = false,
  }) => _state._editors.revealRange(range, select: select, center: center);

  @override
  void focusPanel() => _state._layoutService.focusPanel();

  @override
  Future<void> openLocation(
    IdeLocation location, {
    bool select = false,
    bool record = true,
    VoidCallback? afterReveal,
  }) => _state._editors.openLocation(
    location,
    select: select,
    record: record,
    afterReveal: afterReveal,
  );

  @override
  Future<void> selectEditor(IdeDocument doc) => _state._editors.select(doc);

  @override
  bool get editorBusy => _state._editors.busy;

  @override
  Future<void> openEditorWith(
    Future<void> Function() open, {
    bool focusEditor = false,
  }) => _state._editors.openWith(open, focusEditor: focusEditor);

  @override
  IdeSideView get view => _state._layoutService.view;

  @override
  void showView(IdeSideView view) => _state._layoutService.showView(view);

  @override
  void showQuickModel(IdeQuickInputModel model) {
    if (_state.mounted) _state._quickInput.showModel(model);
  }

  @override
  void report(Object error) => _state._report(error);

  @override
  void focusSoon() => _state._focusSoon();

  @override
  bool executeCommand(String id, [Object? args]) {
    if (!_state.mounted) return false;
    final command = _state._commands.byId()[id];
    if (command == null || !command.enabled) return false;
    command.invoke(args);
    return true;
  }
}

/// A draggable line between two parts, over it: invisible at rest,
/// `sash.hoverBorder` while hovered or dragged. Its cursor says which ways it can go (`.monaco-sash.minimum`,
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: horizontal ? IdeWorkbenchState._sashWidth : null,
          height: horizontal ? null : IdeWorkbenchState._sashWidth,
          color: active ? IdeModernUI.sashHover : Colors.transparent,
        ),
      ),
    );
  }
}

/// An activity bar item: a 24px codicon in a 36px square; the active and
/// the hovered item sit on a rounded 32px box.
class _ActivityItem extends StatefulWidget {
  const _ActivityItem({
    super.key,
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
      borderRadius: BorderRadius.circular(
        IdeWorkbench.islands
            ? IdeModernUI.activityItemRadius
            : IdeModernUI.flatActivityItemRadius,
      ),
    ),
    child: Icon(
      widget.icon,
      size: IdeWorkbench.islands
          ? IdeModernUI.activityIconSize
          : IdeModernUI.flatActivityIconSize,
      color: widget.selected
          ? IdeModernUI.activityActiveForeground
          : _hover
          ? IdeModernUI.activityHoverForeground
          : IdeWorkbench.islands
          ? IdeModernUI.activityForeground
          : IdeModernUI.flatActivityForeground,
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

/// The explorer of a workspace with no folders yet: a button to add one.
class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace({this.onAddFolder});

  final VoidCallback? onAddFolder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      children: [
        Text(
          l10n.ideEmptyWorkspace,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: themeColors['sideBar.foreground'],
          ),
        ),
        if (onAddFolder case final add?) ...[
          const SizedBox(height: 12),
          IdeButton(
            label: l10n.ideAddFolderToWorkspace,
            expand: true,
            onPressed: add,
          ),
        ],
      ],
    );
  }
}
