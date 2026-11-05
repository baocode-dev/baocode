import 'dart:async';

import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:flutter/material.dart';

import '../base/mouse_navigation.dart';
import '../chat/composer/composer_files.dart' show CodeReference, ComposerFile;
import '../chat/open_editor.dart';
import '../debug/service/debug_service.dart';
import '../extensions/theme_extensions.dart';
import '../keybindings/keybinding_service.dart';
import '../l10n/l10n.dart';
import '../settings/user_settings.dart';
import '../theme/app_theme.dart';
import '../workspace/editor_launcher.dart';
import '../workspace/islands.dart';
import '../workspace/window_controls.dart';
import '../workspace/workspace.dart';
import 'extensions/ide_extensions.dart';
import 'file_service.dart' show localizedFileError;
import 'git/commit_message.dart';
import 'git/git_repository.dart';
import 'host_paths.dart';
import 'ide_agent_edits.dart';
import 'ide_color_theme_picker.dart';
import 'ide_commands.dart';
import 'ide_diff_options.dart';
import 'ide_editor.dart';
import 'ide_layout.dart';
import 'ide_local_history.dart';
import 'ide_modern_ui.dart';
import 'ide_notifications.dart';
import 'ide_quick_input.dart';
import 'ide_status_bar.dart';
import 'ide_welcome.dart';
import 'ide_workspace.dart';
import 'lsp/lsp_protocol.dart';
import 'lsp_ui/lsp_convert.dart';
import 'lsp_ui/workspace_edit.dart';
import 'markdown/markdown_paste.dart';
import 'search/text_search.dart';
import 'services/auto_save.dart';
import 'services/chat.dart';
import 'services/commands.dart';
import 'services/configuration.dart';
import 'services/debug_view.dart';
import 'services/editors.dart';
import 'services/explorer.dart';
import 'services/extensions_view.dart';
import 'services/keybindings.dart';
import 'services/language.dart';
import 'services/layout.dart';
import 'services/lists.dart';
import 'services/markdown_preview.dart';
import 'services/navigation_history.dart';
import 'services/problems.dart';
import 'services/quick_input.dart';
import 'services/references.dart';
import 'services/scm_service.dart';
import 'services/search_view.dart';
import 'services/terminal_view.dart';
import 'terminal/terminal_hosts.dart';
import 'terminal/terminal_instance.dart';
import 'terminal/terminal_service.dart';
import 'terminal/terminal_tasks.dart';
import 'workbench/actions.dart';
import 'workbench/context_keys.dart';
import 'workbench/contributions.dart';
import 'workbench/contributions/all.dart';
import 'workbench/editor_panes.dart';
import 'workbench/environment.dart';
import 'workbench/options.dart';
import 'workbench/parts/grid.dart';
import 'workbench/parts/quick_input.dart';
import 'workbench/parts/title_bar.dart';
import 'workbench/quick_access.dart';
import 'workbench/services.dart';
import 'workbench/statusbar.dart';
import 'workbench/storage.dart';
import 'workbench/style.dart';
import 'workbench/views.dart';
import 'workbench/workspace_binding.dart';

/// The IDE shell is kept mounted when the user returns to the conversation.
class IdeWorkbench extends StatefulWidget implements WorkbenchOptions {
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

  @override
  final IdeWorkspace workspace;

  /// Whether its parts are islands, as the agents' window's (see
  /// [WorkbenchStyle.islands]).
  static bool get islands => WorkbenchStyle.islands;
  static set islands(bool islands) => WorkbenchStyle.islands = islands;

  /// Between two of its cards; none where they are not ([islands]).
  static double get gap => WorkbenchStyle.gap;

  /// The multi-folder workspace a recent folder is, for the start page.
  @override
  final IdeRecentWorkspace? Function(String path)? recentWorkspaceOf;

  /// Create Workspace...: the host's command, which asks for a workspace's
  /// name and folders.
  static const createWorkspaceCommandId =
      WorkbenchOptions.createWorkspaceCommandId;

  /// Add Folder to Workspace...: of a multi-folder workspace (see
  /// [IdeWorkspace.isMultiRoot]), the host asking for the folder.
  @override
  final VoidCallback? onAddFolder;

  /// Remove Folder from Workspace, of a workspace folder's explorer row.
  @override
  final ValueChanged<String>? onRemoveFolder;

  /// The remote host the project is on, shown first in the status bar;
  /// null for this machine.
  @override
  final IdeRemoteIndicator? remote;

  /// Hands a file to its default app; tests replace it.
  @visibleForTesting
  static Future<bool> Function(String path) openInDefaultApp = openExternal;

  /// What a paste in a markdown document reads; tests replace it.
  @visibleForTesting
  static MarkdownClipboard markdownClipboard = const SystemMarkdownClipboard();

  @override
  final Project project;
  @override
  final bool visible;
  @override
  final Widget chat;

  /// Puts files and folders in [chat]'s composer (Source Control's Add to
  /// Chat); none offered when null.
  @override
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
  @override
  final String? backLabel;

  /// Optional editor override for widget tests.
  @override
  final Widget Function(BuildContext, IdeWorkspace)? editorBuilder;

  /// Whether the editor uses the painted Monaco surface (see [IdeEditor]).
  @override
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
  @override
  final IdeCommitMessageModel commitMessage;

  /// The agents' changes pending in its files, shown in the editor with
  /// Undo and Keep by each change, and over its tabs for the file's.
  @override
  final IdeAgentEdits? agentEdits;

  /// Whether the window is kept on top of other apps; [onPinnedChanged]
  /// toggles it from the title bar, as the chat's pin does.
  @override
  final bool pinned;
  @override
  final ValueChanged<bool>? onPinnedChanged;

  /// Where the panel's terminals come from: the user's shell on a pseudo
  /// terminal; fakes in widget tests. Without one (the web), there is no
  /// TERMINAL tab.
  final TerminalBackend terminalBackend;

  /// The background commands of the agent in its chat, listed with the
  /// terminals (see [IdeWorkbenchState.showTerminalTask]).
  @override
  final TerminalTasks? terminalTasks;

  /// The project's terminals where the chat has them too, the same in
  /// both (kept by the chat, not disposed here); else the IDE's own, on
  /// [terminalBackend]. [terminalHosts] has where each shows, the IDE's
  /// panel one of the places.
  final TerminalService? terminals;
  @override
  final TerminalHosts? terminalHosts;

  /// The color themes Preferences: Color Theme (⌘K ⌘T) picks from; the
  /// command is disabled without them.
  final IdeColorThemeController? colorThemes;

  /// The folders opened last, most recent first, for the welcome page of
  /// a window without one; [onOpenRecent] opens one.
  @override
  final List<String> recentFolders;
  @override
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
    _storage = _services.add(WorkbenchStorage(save: () => widget.onViewState));
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
    // The sizes and the view kept as they change.
    _layoutService.addListener(_storage.changed);
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
    _scmService.addListener(_storage.changed);
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
        storage: _storage,
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
    _services.add(
      ProblemsService(
        host: _host,
        language: _language,
        layout: () => widget.workspace.layout,
        caret: () => _caretPosition,
        activePath: () => widget.workspace.active?.path,
        showHover: () => _editor?.showHoverAtCaret(),
      ),
    );
    _services.add(
      ReferencesService(
        host: _host,
        layout: () => widget.workspace.layout,
        caret: () => _caretPosition,
        activePath: () => widget.workspace.active?.path,
      ),
    );
    // The editors last: those kept open again once the rest is restored.
    _storage.register(_editors);
  }

  /// The services of ide_workbench_keys.dart and the views, for tests.
  @visibleForTesting
  WorkbenchServices get services => _services;

  final FocusNode _workbenchFocus = FocusNode(debugLabel: 'ide workbench');

  /// The Explorer view: its tree, Quick Open's files, its panes.
  late final ExplorerService _explorerService;

  /// The services on the workspace, another as it is swapped.
  late final WorkspaceBinding _binding = WorkspaceBinding(_services);

  /// The parts' layout: the side bar's view, the sizes, which part has
  /// the keyboard.
  late final LayoutService _layoutService;

  /// Which parts show: the workspace's, for the window's header to toggle
  /// as well (see [IdeLayout]); [_layoutService] follows it.
  IdeLayout get _layout => widget.workspace.layout;

  /// The workspace's notifications (the debugger's go there too).
  IdeNotifications get _notifications => widget.workspace.notifications;

  /// Where the caret is.
  Position get _caretPosition => _editors.position;

  /// Source Control: the repository shown, its sessions, what opens and
  /// compares changes.
  late final ScmService _scmService;
  IdeGitRepository? get _git => _scmService.git;

  /// The Search view's inputs and results, while other views show.
  late final SearchViewService _searchView;

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

  /// The panel's terminals; none where they cannot run (the web).
  late final TerminalViewService _terminalView;

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

  /// [IdeWorkbench.viewState] applied: each service reads its keys (which
  /// parts show the workspace's layout was made with, see
  /// [IdeLayout.restore]).
  void _restoreView() {
    if (widget.viewState case final kept?) _storage.restore(kept);
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
    _registerCommandKeybindings();
    widget.agentEdits?.open = _openAgentChange;
    widget.settings?.addListener(_settingsChanged);
    _restoreView();
    _binding.attach(widget.workspace);
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_git?.refresh()),
      // The window left: `onFocusChange` and `onWindowChange` save.
      onInactive: () {
        unawaited(_autoSave.saveNow(const {'onFocusChange', 'onWindowChange'}));
        // Where the editors are, should the app be quit from elsewhere.
        _storage.keep();
      },
    );
    IdeLanguageNames.ensureLoaded(() {
      if (mounted) setState(() {});
    });
    _scmService.readBranch();
    if (widget.visible) _focusSoon();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _language.localized();
  }

  /// The keybindings of [IdeWorkbench.commands] the defaults do not have.
  void _registerCommandKeybindings() =>
      KeybindingService.instance.registerExtraDefaults([
        for (final command in widget.commands) ...command.keybindingEntries,
      ]);

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
    if (oldWidget.debugService != widget.debugService) {
      _debugView.givenChanged();
    }
    if (oldWidget.workspace != widget.workspace) {
      _binding
        ..detach()
        ..attach(widget.workspace);
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
    widget.settings?.removeListener(_settingsChanged);
    _storage.keep();
    _lifecycle?.dispose();
    // A quick pick or input box going with the workbench hides (the color
    // themes one applies the theme it started with again).
    _binding.detach();
    disposeContributions(_contributions);
    _services.dispose();
    _workbenchFocus.dispose();
    super.dispose();
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

  // --- Language features ---------------------------------------------------

  /// Go Back (⌃-) / Go Forward (⌃⇧-), and the mouse's back and forward
  /// buttons: whether there was somewhere to go.
  bool _navigate({required bool back}) =>
      _services.find<NavigationHistoryService>()?.navigate(back: back) ?? false;

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

  /// The parts (lib/ide/workbench/parts/), each built again as its own
  /// services change: the title bar, the grid of the others, the
  /// notifications and the quick input over them.
  @override
  Widget build(BuildContext context) {
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
                  if (!WindowControls.drawsHeader)
                    TitleBarPart(options: widget),
                  Expanded(
                    // The other half of the gap at the window's right
                    // (each card keeps half a gap about it).
                    child: Padding(
                      padding: EdgeInsets.only(right: IdeWorkbench.gap / 2),
                      child: WorkbenchGrid(options: widget),
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
                  child: IdeNotificationsCenter(notifications: _notifications),
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
              QuickInputPart(
                service: _quickInput,
                top: WindowControls.drawsHeader ? 0 : AppMetrics.titleBarHeight,
              ),
            ],
          ),
        ),
      ),
    );
    // The mouse's back and forward buttons go back and forward, as
    // upstream's `registerMouseNavigationListener` has them; where what is
    // under the pointer does not go back first (a subagent in the chat, a
    // commit's changes in the Git log).
    return WorkbenchScope(
      services: _services,
      child: MouseNavigation(
        onBack: () => _navigate(back: true),
        onForward: () => _navigate(back: false),
        child: IslandStyle(on: IdeWorkbench.islands, child: focus),
      ),
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
