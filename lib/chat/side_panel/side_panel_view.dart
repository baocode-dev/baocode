import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../browser/browser_bridge.dart';
import '../../browser/browser_mirror.dart';
import '../../ide/file_service.dart';
import '../../ide/git/git_model.dart';
import '../../ide/git/commit_message.dart';
import '../../ide/git/git_repository.dart';
import '../../ide/git/ide_git_log_view.dart'
    show IdeGitLogView, IdeGitWorktreeChoice;
import '../../ide/git/ide_git_commit_panel.dart';
import '../../ide/git/scm_host.dart';
import '../../ide/ide_button.dart';
import '../../ide/ide_dialog.dart';
import '../../ide/ide_explorer.dart';
import '../../ide/ide_agent_edits.dart' show IdeAgentEdit;
import '../../ide/ide_code_editor.dart' show IdeTextFormatter;
import '../../ide/ide_hover.dart';
import '../../ide/file_views.dart';
import '../../ide/search/ide_search_view.dart';
import '../../ide/search/text_search.dart' show IdeTextSearch, ideSearchText;
import '../../ide/ide_list.dart';
import '../../ide/ide_menu.dart';
import '../../ide/ide_notifications.dart';
import '../../ide/ide_modern_ui.dart';
import '../../ide/ide_panes.dart';
import '../../ide/ide_tab_bar.dart'
    show IdeEditorTab, IdeTabStrip, ideTabDescriptions;
import '../../ide/save_copy.dart';
import '../../ide/tab_strip_scroll.dart';
import '../../ide/terminal/links/terminal_links.dart' show TerminalLink;
import '../../ide/terminal/terminal_instance.dart';
import '../../ide/terminal/terminal_service.dart';
import '../../ide/terminal/terminal_tabs.dart';
import '../../ide/terminal/terminal_view.dart';
import '../../kernel/kernel_types.dart' show KernelTask;
import '../../workspace/window_controls.dart';
import '../chat_models.dart' show CommandStatus;
import '../../keybindings/chat_keybindings.dart';
import '../../keybindings/keybinding_service.dart';
import '../../l10n/l10n.dart';
import '../../sidebar/sidebar.dart' show SidebarIconButton;
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_session.dart';
import '../widgets/code_citation.dart' show CodeColorizer;
import '../widgets/plan_start.dart';
import '../chat_column.dart';
import '../composer/composer_files.dart';
import '../composer/file_drag.dart';
import 'file_link.dart';
import 'file_open.dart';
import 'file_preview.dart';
import 'git_changes.dart';
import 'side_panel_controller.dart';
import 'terminal_preview.dart';

/// [child] (the conversations) and, at its right (its left, as [panel] is
/// [AgentSidePanel.atLeft]) while [panel] shows, the side panel [builder]
/// builds: beside it, its edge toward them dragged to make it wider or
/// narrower (a double click gives back its width), narrower
/// where the conversations would have less than [minChat]; over it, where
/// they would beside it at its least.

/// This machine's files, for what is shown as a file (one service: the
/// preview reads its file anew when it changes).
final IdeFileService _localFiles = IdeFileService(p.current);

class AgentSidePanelArea extends StatefulWidget {
  const AgentSidePanelArea({
    super.key,
    required this.panel,
    required this.builder,
    this.rail,
    this.railTop = AppMetrics.titleBarHeight + 4,
    this.hidden = false,
    required this.child,
  });

  final AgentSidePanel panel;
  final WidgetBuilder builder;

  /// While the panel is hidden, over the conversations' top right (left,
  /// the panel at their left), clear of their scrollbar: their column keeps
  /// clear of it ([railInset]), not their title bar nor their scrollbar,
  /// which reach the edge.
  final Widget? rail;

  /// How far down [rail] is: under the conversation's title bar, where it
  /// has one.
  final double railTop;

  /// Whether it gave way to the window's sidebar, though shown: the rail
  /// is there instead, to ask for it again.
  final bool hidden;
  final Widget child;

  /// The least the conversations keep beside it.
  static const minChat = 360.0;

  /// The strip at its left edge that takes the drag.
  static const sashWidth = 5.0;

  /// How long the room is short before it goes over the conversations:
  /// longer than the window's sidebar takes to give way.
  static const overlayDelay = Duration(milliseconds: 260);

  /// How far in from the right [rail] is: clear of the history's
  /// scrollbar.
  static const railRight = 16.0;

  /// How far in from the right the conversations' column keeps while [rail]
  /// shows: clear of it, by a gap.
  static const railInset = railRight + SidePanelRail.width + 8;

  @override
  State<AgentSidePanelArea> createState() => _AgentSidePanelAreaState();
}

class _AgentSidePanelAreaState extends State<AgentSidePanelArea> {
  bool _dragging = false;
  ({double x, double width})? _dragStart;

  /// Whether it is over the conversations: once the room was short for
  /// longer than [overlayDelay]. Short a while only (the window's sidebar
  /// giving way to it, which takes its animation; a window opening), it
  /// stays beside them, narrower, not covering the window for a moment.
  bool _overlay = false;

  /// Runs while the room is short: over them once it ends.
  Timer? _short;

  void _roomShort(bool short) {
    if (!short) {
      _short?.cancel();
      _short = null;
      _overlay = false;
      return;
    }
    if (_overlay || _short != null) return;
    _short = Timer(AgentSidePanelArea.overlayDelay, () {
      _short = null;
      if (mounted) setState(() => _overlay = true);
    });
  }

  @override
  void dispose() {
    _short?.cancel();
    super.dispose();
  }

  AgentSidePanel get _panel => widget.panel;

  /// The widest it shows in [room]: beside the conversations, what they
  /// leave at their least; over them, all but a strip of them.
  double _most(double room) => _overlay
      ? math.max(0.0, room - 48)
      : math.max(
          0.0,
          room - AgentSidePanelArea.minChat - AgentSidePanelArea.sashWidth,
        );

  /// How wide it shows in [room]: as wide as it was made, as far as there
  /// is room for.
  double _shownWidth(double room) => math.min(_panel.width, _most(room));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _panel,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth;
        final shown = _panel.shown && !widget.hidden;
        // Over the conversations only where it cannot be beside them at
        // its least; else beside them, narrower than it would be where
        // they need the room.
        _roomShort(
          shown && room - AgentSidePanel.minWidth < AgentSidePanelArea.minChat,
        );
        final overlay = _overlay;
        final atLeft = _panel.atLeft;
        final beside = shown && !overlay;
        final rail = !shown && widget.rail != null;
        final width = _shownWidth(room);
        // Each child keyed: the conversations and the panel are never
        // built anew as the rail, the scrim or the drag's cursor come and
        // go (the panel built anew mid-drag would drop the drag, and
        // leave the cursor's cover over the window).
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              key: const ValueKey('chat'),
              top: 0,
              bottom: 0,
              // Up to the sash's line; the rest of the sash is over it, so
              // nothing shows between the two.
              left: beside && atLeft ? width + 1 : 0,
              right: beside && !atLeft ? width + 1 : 0,
              child: ChatColumnInset(
                right: rail && !atLeft ? AgentSidePanelArea.railInset : 0,
                left: rail && atLeft ? AgentSidePanelArea.railInset : 0,
                child: widget.child,
              ),
            ),
            if (rail)
              Positioned(
                key: const ValueKey('rail'),
                left: atLeft ? AgentSidePanelArea.railRight : null,
                right: atLeft ? null : AgentSidePanelArea.railRight,
                top: widget.railTop,
                child: widget.rail!,
              ),
            if (shown) ...[
              if (overlay)
                Positioned.fill(
                  key: const ValueKey('scrim'),
                  child: GestureDetector(
                    onTap: _panel.hide,
                    child: const ColoredBox(color: Color(0x33000000)),
                  ),
                ),
              Positioned(
                key: const ValueKey('panel'),
                top: 0,
                bottom: 0,
                left: atLeft ? 0 : null,
                right: atLeft ? null : 0,
                width: width + AgentSidePanelArea.sashWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: overlay
                        ? [
                            BoxShadow(
                              color: themeColors['widget.shadow'],
                              blurRadius: 24,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    // The sash on the side of the conversations.
                    textDirection: atLeft
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    children: [
                      _sash(atLeft: atLeft),
                      Expanded(
                        // Never laid out narrower than its least: squeezed
                        // a while (the sidebar giving way), what has no
                        // room is cut off, as the sidebar's own is.
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.centerLeft,
                            minWidth: math.max(width, AgentSidePanel.minWidth),
                            maxWidth: math.max(width, AgentSidePanel.minWidth),
                            child: _content(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // The resize cursor wherever the pointer goes while dragging;
              // a press there (a drag whose end was lost) ends it.
              if (_dragging)
                Positioned.fill(
                  key: const ValueKey('drag-cursor'),
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => _endDrag(),
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    ),
  );

  /// What it shows, beside its sash.
  Widget _content(BuildContext context) =>
      // A click anywhere in it puts the focus there (on what takes it, else
      // on the panel), for its keys.
      Listener(
        onPointerDown: (_) {
          if (!_panel.focusNode.hasFocus) {
            _panel.focusNode.requestFocus();
          }
        },
        child: Focus(
          focusNode: _panel.focusNode,
          // The editor's background, all of it: the conversation's side,
          // not the window's.
          child: ColoredBox(
            color: AppColors.code,
            child: widget.builder(context),
          ),
        ),
      );

  /// The strip on the panel's edge beside the conversations: its left,
  /// or its right [atLeft].
  Widget _sash({required bool atLeft}) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      key: const ValueKey('side-panel-sash'),
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      // From the width it shows, not the one it was made: narrower where
      // the room is short, the sash would wait for the pointer to cover the
      // difference before it moved.
      onHorizontalDragStart: (details) => setState(() {
        _dragging = true;
        _dragStart = (
          x: details.globalPosition.dx,
          width: _shownWidth(context.size?.width ?? double.infinity),
        );
      }),
      onHorizontalDragUpdate: (details) {
        final start = _dragStart;
        if (start == null) return;
        final room = context.size?.width ?? double.infinity;
        final moved = details.globalPosition.dx - start.x;
        // No wider than it shows: past that the sash waits, and follows
        // again once the pointer is back.
        _panel.width = math.min(
          atLeft ? start.width + moved : start.width - moved,
          math.max(AgentSidePanel.minWidth, _most(room)),
        );
      },
      onHorizontalDragEnd: (_) => _endDrag(),
      onHorizontalDragCancel: _endDrag,
      onDoubleTap: () {
        _panel.width = AgentSidePanel.defaultWidth;
        _panel.save();
      },
      child: Container(
        width: AgentSidePanelArea.sashWidth,
        // Its line against the panel.
        alignment: atLeft ? Alignment.centerLeft : Alignment.centerRight,
        // At rest the line between the two; dragged, as thick as the IDE's
        // sashes, in their `sash.hoverBorder`.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: _dragging ? IdeModernUI.gap : 1,
          color: _dragging ? IdeModernUI.sashHover : AppColors.partBorder,
        ),
      ),
    ),
  );

  void _endDrag() {
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _dragStart = null;
    });
    _panel.save();
  }
}

/// The side panel for [session]'s conversation: its pages (the project's
/// files, the agent's changes, its terminals), each a list at
/// its left and, at its right, the tabs opened from it over the one in
/// front.
class AgentSidePanelView extends StatelessWidget {
  const AgentSidePanelView({
    super.key,
    required this.panel,
    required this.session,
    required this.files,
    this.readBytes,
    this.paths,
    this.colorize,
    this.onOpenInIde,
    this.formatter,
    this.watchDirectory,
    this.searchEngine = ideSearchText,
    this.git,
    this.terminals,
    this.terminalSkipShell = const [],
    this.onOpenTerminalLink,
    this.commitMessage,
    required this.notifications,
    this.workspaceName,
    this.roots = const [],
    this.repositories = const [],
    this.worktreesOf,
    this.onAddFolder,
    this.onRemoveFolder,
    this.titleBarInset = 0,
    this.leading,
  });

  final AgentSidePanel panel;
  final ChatSession session;

  /// Room kept at the left of its tabs: for the traffic lights, where it
  /// is at the window's top left.
  final double titleBarInset;

  /// Before its tabs, after [titleBarInset]: the window's sidebar toggle,
  /// by the traffic lights, where it is at the window's top left.
  final Widget? leading;

  /// The name of the multi-folder workspace the conversation is in; null
  /// for a folder's.
  final String? workspaceName;

  /// The workspace's folders, the roots of the files page's tree as of
  /// the IDE's explorer.
  final List<String> roots;

  /// The repositories of the workspace's folders, by folder, or of a
  /// folder's project when some were found in its subfolders (as Source
  /// Control lists them): the changes page lists them to pick from, [git]
  /// then ignored.
  final List<(String root, IdeGitRepository git)> repositories;

  /// For the repository shown: where the agent works, and how to show
  /// another of its worktrees' changes (see [IdeGitWorktreeChoice]).
  final IdeGitWorktreeChoice Function(IdeGitRepository git)? worktreesOf;

  /// Add Folder to Workspace..., and Remove Folder from Workspace, as the
  /// IDE's explorer has them.
  final VoidCallback? onAddFolder;
  final ValueChanged<String>? onRemoveFolder;

  bool get _isWorkspace => workspaceName != null;

  /// The line under a list's title, as high as the tabs beside it: running
  /// on under theirs.
  static Color get _titleBorder => IdeTabStrip.border ?? AppColors.partBorder;

  /// The repository whose changes show: the one picked of [repositories]
  /// (their first until one is), else [git].
  IdeGitRepository? get _git {
    if (!_isWorkspace && repositories.isEmpty) return git;
    final picked = switch (session.root) {
      final root? => panel.repositoryOf(root),
      null => null,
    };
    return repositories.where((r) => r.$1 == picked).firstOrNull?.$2 ??
        repositories.firstOrNull?.$2;
  }

  /// Every repository the changes page counts.
  List<IdeGitRepository> get _gits => _isWorkspace || repositories.isNotEmpty
      ? [for (final (_, git) in repositories) git]
      : [?git];

  /// The workspace folder [path] is in, else the project's folder.
  String? _rootOf(String path) {
    for (final root in roots) {
      if (root == path || _paths.isWithin(root, path)) return root;
    }
    return session.root;
  }

  /// The project's, on its host.
  final IdeFileService files;
  final Future<Uint8List> Function(String path)? readBytes;
  final p.Context? paths;
  final CodeColorizer? colorize;

  /// Opens a file shown in the IDE instead.
  final ValueChanged<FileOpenRequest>? onOpenInIde;

  /// Formats a file edited here with the project's language servers.
  final IdeTextFormatter? formatter;

  /// Changes to a folder's entries, for the files page's tree to follow;
  /// the explorer's own watch when null.
  final Stream<void> Function(String directory)? watchDirectory;

  /// The files page's text search: the same engine the IDE searches with
  /// (Git's file list, off the UI isolate), so its feel and speed match.
  final IdeTextSearch searchEngine;

  /// The project's repository, whose changes the changes page lists; none
  /// where Git is not at hand.
  final IdeGitRepository? git;

  /// Writes commit messages on the changes page (its sparkle); none
  /// offered when null.
  final IdeCommitMessageModel? commitMessage;

  /// Where the changes page tells of what failed (the window's).
  final IdeNotifications notifications;

  /// The project's terminals on the terminal page; none where terminals
  /// cannot run.
  final TerminalService? terminals;

  /// Keys the window keeps while one of them has focus (see
  /// [TerminalView.skipShell]).
  final List<ShortcutActivator> terminalSkipShell;

  /// Opens a link ⌘-clicked (Ctrl-clicked off macOS) in one of them.
  final ValueChanged<TerminalLink>? onOpenTerminalLink;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      panel,
      session,
      // A file's change kept or undone, part by part.
      ?session.changeReview,
      ..._gits,
      ?terminals,
      BrowserBridge.instance,
    ]),
    builder: (context, _) {
      final tabs = panel.tabsOf(session);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionBar(
            panel: panel,
            session: session,
            tabs: tabs,
            changes: _gits.fold(0, (sum, git) => sum + (git.state?.count ?? 0)),
            inset: titleBarInset,
            leading: leading,
          ),
          Expanded(
            child: switch (tabs.shown) {
              SidePanelSection.files => _filesPage(context, tabs),
              SidePanelSection.changes => _changesPage(context, tabs),
              SidePanelSection.terminal => _terminalPage(context, tabs),
              SidePanelSection.browser => const BrowserMirror(
                key: ValueKey(('page', SidePanelSection.browser)),
              ),
              SidePanelSection.plan => _planPage(context, tabs.plan!),
            },
          ),
        ],
      );
    },
  );

  p.Context get _paths => paths ?? p.context;

  /// The project's tree (the IDE's explorer), and the files opened from
  /// it or from the conversation.
  Widget _filesPage(BuildContext context, SidePanelTabs tabs) {
    final l10n = context.l10n;
    final root = session.root;
    final active = tabs.active;
    final explorer = root == null
        ? null
        : panel.explorerOf(
            root,
            files,
            watch: watchDirectory,
            roots: roots,
            paths: _paths,
          );
    final local = files is! IdeHostFiles;
    // Whether this project's files page shows the text search in place of
    // the tree (the header's magnifier).
    final searching = root != null && panel.searchShown(root);
    return _Page(
      key: const ValueKey(('page', SidePanelSection.files)),
      panel: panel,
      list: explorer == null
          ? _EmptySection(l10n.sidePanelNoFolder)
          : searching
          // The IDE's Search view, under its own title: the way back to the
          // tree first among its actions.
          ? IdeSearchView(
              session: panel.searchOf(explorer.root, searchEngine),
              root: explorer.root,
              titleBorder: _titleBorder,
              background: AppColors.code,
              titleActions: [
                IdePaneAction(
                  icon: Codicons.close,
                  tooltip: l10n.sidePanelCloseSearch,
                  onPressed: () => panel.setSearchShown(explorer.root, false),
                ),
              ],
              // Escape closes the search, the tree back.
              onEscape: () => panel.setSearchShown(explorer.root, false),
              // Searching alone: a replace would write into a project this
              // panel only looks at.
              onOpen: (path, range, {required focusEditor}) async => panel.open(
                session,
                FileOpenRequest(
                  path,
                  range: FileLineRange(
                    range.start.line + 1,
                    range.end.line + 1,
                  ),
                ),
              ),
              onError: (error) => _showFileError(context, error),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IdeViewTitle(
                  switch (workspaceName) {
                    final name? => l10n.ideWorkspaceTitle(name),
                    null => _paths.basename(explorer.root),
                  },
                  border: _titleBorder,
                  actions: [
                    IdePaneAction(
                      icon: Codicons.search,
                      tooltip: l10n.sidePanelSearchFiles,
                      onPressed: () =>
                          panel.setSearchShown(explorer.root, true),
                    ),
                    if (onAddFolder case final add? when _isWorkspace)
                      IdePaneAction(
                        icon: Codicons.rootFolder,
                        tooltip: l10n.ideAddFolderToWorkspace,
                        onPressed: add,
                      ),
                    IdePaneAction(
                      icon: Codicons.refresh,
                      tooltip: l10n.cmdRefreshExplorer,
                      onPressed: () => unawaited(explorer.refresh()),
                    ),
                    IdePaneAction(
                      icon: Codicons.collapseAll,
                      tooltip: l10n.cmdCollapseExplorerFolders,
                      onPressed: explorer.collapseAll,
                    ),
                  ],
                ),
                Expanded(
                  child: _isWorkspace && roots.isEmpty
                      ? _EmptyWorkspace(onAddFolder: onAddFolder)
                      : IdeExplorer(
                          key: ObjectKey(explorer),
                          background: AppColors.code,
                          controller: explorer,
                          local: local,
                          onAddFolder: _isWorkspace ? onAddFolder : null,
                          onRemoveFolder: _isWorkspace ? onRemoveFolder : null,
                          trash: local && WindowControls.canMoveToTrash
                              ? WindowControls.moveToTrash
                              : null,
                          onOpen: (path, _) =>
                              panel.open(session, FileOpenRequest(path)),
                          // A paste, rename or delete that failed.
                          onError: (error) => _showFileError(context, error),
                        ),
                ),
              ],
            ),
      tabs: _fileTabs(context, tabs, tabs.files, active),
      body: active == null
          ? _EmptySection(l10n.sidePanelSelectFile)
          : _preview(context, active),
    );
  }

  /// The project's Git log (one view for this and the IDE's Source
  /// Control): its filters, its history, the row's details (the local
  /// changes' commit box and groups, a commit's files), a workspace's
  /// repositories to pick from; the changes opened, from it or from the
  /// conversation, in its table's place.
  Widget _changesPage(BuildContext context, SidePanelTabs tabs) {
    final git = _git;
    final active = tabs.activeDiff;
    final local = files is! IdeHostFiles;
    if (git == null) {
      // No repository: the changes opened from the conversation alone.
      return KeyedSubtree(
        key: const ValueKey(('page', SidePanelSection.changes)),
        child: active == null
            ? const _NoRepository()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?_fileTabs(context, tabs, tabs.diffs, active),
                  Expanded(child: _preview(context, active)),
                ],
              ),
      );
    }
    final host = _SidePanelScmHost(this);
    return KeyedSubtree(
      key: const ValueKey(('page', SidePanelSection.changes)),
      child: IdeGitLogView(
        key: ValueKey(('git-log', session.root)),
        host: host,
        session: panel.scmOf(git),
        notifications: notifications,
        background: AppColors.code,
        border: AppColors.partBorder,
        onOpen: (path) => panel.open(session, FileOpenRequest(path)),
        // A commit's file: its changes in a tab, as the local ones'.
        onOpenDiff: (file) => panel.open(
          session,
          FileOpenRequest(
            file.path,
            diff: true,
            original: file.original,
            modified: file.modified,
            readOnly: true,
          ),
        ),
        overlay: active == null ? null : _preview(context, active),
        overlayTabs: _fileTabs(context, tabs, tabs.diffs, active),
        onCloseOverlay: () => panel.showLog(session),
        onAddToChat: session.draft.insertFiles,
        worktrees: worktreesOf?.call(git) ?? const IdeGitWorktreeChoice(),
        changes: IdeGitCommitPanel(
          key: ValueKey(('scm', session.root)),
          host: host,
          session: panel.scmOf(git),
          sessionOf: panel.scmOf,
          notifications: notifications,
          onOpen: (path, {focusEditor = false}) async =>
              panel.open(session, FileOpenRequest(path)),
          // Its diff; its HEAD side is the diff's left.
          onOpenChange: (resource, {head = false, focusEditor = false}) async {
            final of = _gitOf(resource.path);
            if (of?.state case final state?) {
              panel.open(session, gitChangeRequest(of!, state, resource));
            }
          },
          onRevealInExplorer: _revealInFiles,
          revealInExplorerLabel: context.l10n.sidePanelRevealInFiles,
          onAddToChat: session.draft.insertFiles,
          trash: local && WindowControls.canMoveToTrash
              ? WindowControls.moveToTrash
              : null,
          commitMessage: commitMessage,
          onTreeViewChanged: (tree) => panel.changesAsTree = tree,
        ),
      ),
    );
  }

  /// The repository [path] is in: the one of [_gits] whose folder holds it
  /// the closest.
  IdeGitRepository? _gitOf(String path) {
    IdeGitRepository? found;
    var length = -1;
    for (final git in _gits) {
      final root = git.service.root;
      if ((root == path || _paths.isWithin(root, path)) &&
          root.length > length) {
        found = git;
        length = root.length;
      }
    }
    return found ?? _git;
  }

  /// Tells of a file operation that failed.
  void _showFileError(BuildContext context, Object error) {
    final l10n = context.l10n;
    unawaited(
      showIdeDialog(
        context,
        type: IdeDialogType.error,
        message: localizedFileError(l10n, error),
        buttons: const [],
        cancel: l10n.commonOk,
      ),
    );
  }

  /// Save As… of [path] to this machine (from a remote project's host
  /// too): [tab]'s text as edited when it has changes not saved.
  void _saveAs(BuildContext context, String path, [SidePanelTab? tab]) {
    final edit = tab?.edit;
    unawaited(
      saveFileCopyAs(
        files,
        path,
        text: edit != null && edit.dirty ? edit.controller.document.text : null,
      ).then<void>(
        (_) {},
        onError: (Object error) {
          if (context.mounted) _showFileError(context, error);
        },
      ),
    );
  }

  IdeMenuAction _saveAsItem(
    BuildContext context,
    String path, [
    SidePanelTab? tab,
  ]) => IdeMenuAction(
    context.l10n.cmdSaveAs,
    onSelected: () => _saveAs(context, path, tab),
  );

  /// Shows [path] in the files page's tree.
  void _revealInFiles(String path) {
    final root = session.root;
    if (root == null) return;
    final explorer = panel.explorerOf(
      root,
      files,
      watch: watchDirectory,
      roots: roots,
      paths: _paths,
    );
    panel.showSection(session, SidePanelSection.files);
    unawaited(explorer.reveal(path));
  }

  /// The project's terminals and the agent's background commands, and
  /// those opened: a terminal, or a command's output.
  Widget _terminalPage(BuildContext context, SidePanelTabs tabs) {
    final l10n = context.l10n;
    final terminals = this.terminals;
    final shells = terminals?.instances ?? const <TerminalInstance>[];
    final tasks = session.terminalTasks;
    final byId = <Object, Object>{
      for (final shell in shells) shell: shell,
      for (final task in tasks) task.id: task,
    };
    final open = [
      for (final id in tabs.terminals)
        if (byId[id] case final item?) (id: id, item: item),
    ];
    final current = open
        .where((entry) => entry.id == tabs.terminal)
        .firstOrNull;
    void newTerminal() {
      final shell = terminals!.create();
      panel.openTerminal(session, shell);
      WidgetsBinding.instance.addPostFrameCallback((_) => shell.focus());
    }

    void kill(TerminalInstance shell) {
      panel.closeTerminal(session, shell);
      terminals!.kill(shell);
    }

    void stop(KernelTask task) => session.stopTask(task);

    /// [id]'s tab's menu: closing it and the others, then what can be
    /// done to what it shows.
    List<IdeMenuEntry> menu(Object id) {
      final ids = [for (final entry in open) entry.id];
      final index = ids.indexOf(id);
      final item = byId[id];
      return ideMenuGroups([
        _closeItems(
          context,
          index: index,
          count: ids.length,
          close: (which) {
            for (final other in which(ids)) {
              panel.closeTerminal(session, other);
            }
          },
          id: id,
        ),
        [
          if (item case final TerminalInstance shell)
            IdeMenuAction(l10n.termKillTerminal, onSelected: () => kill(shell)),
          if (item case final KernelTask task
              when task.status == CommandStatus.running)
            IdeMenuAction(l10n.chatStop, onSelected: () => stop(task)),
        ],
      ]);
    }

    return _Page(
      key: const ValueKey(('page', SidePanelSection.terminal)),
      panel: panel,
      // The IDE's terminal tabs, grouped: each opening in a tab here.
      list: ColoredBox(
        key: const ValueKey('side-panel-terminals'),
        color: AppColors.code,
        child: TerminalTabs(
          terminals: terminals,
          onNew: terminals == null ? null : newTerminal,
          tasks: tasks,
          grouped: true,
          selected: current?.id,
          onOpen: (id) => panel.openTerminal(session, id),
          onKill: kill,
          onStopTask: stop,
          onClearTasks: session.clearTasks,
          border: false,
        ),
      ),
      tabs: open.isEmpty
          ? null
          : _TabStrip(
              key: ValueKey(('terminals', session)),
              selected: current?.id,
              entries: [
                for (final (:id, :item) in open)
                  (
                    id: id,
                    child: switch (item) {
                      final TerminalInstance shell => ListenableBuilder(
                        listenable: shell,
                        builder: (context, _) => _Tab(
                          active: id == current?.id,
                          icon: const _TabIcon(Codicons.terminal),
                          label: shell.title,
                          tooltip: shell.title,
                          onTap: () => panel.openTerminal(session, id),
                          onClose: () => panel.closeTerminal(session, id),
                          menu: () => menu(id),
                        ),
                      ),
                      final task as KernelTask => _Tab(
                        active: id == current?.id,
                        icon: TerminalTaskIcon(task, size: _Tab.iconSize),
                        label: task.description,
                        tooltip: task.description,
                        onTap: () => panel.openTerminal(session, id),
                        onClose: () => panel.closeTerminal(session, id),
                        menu: () => menu(id),
                      ),
                    },
                  ),
              ],
            ),
      body: switch (current?.item) {
        final TerminalInstance shell => TerminalView(
          shell,
          key: ObjectKey(shell),
          skipShell: terminalSkipShell,
          onKill: () => kill(shell),
          onOpenLink: onOpenTerminalLink,
        ),
        final KernelTask task => TerminalPreview(
          key: ValueKey((session, task.id)),
          task: task,
          command: session.commandOf(task.toolUseId),
          files: files,
          onStop: () => stop(task),
          root: terminals?.root ?? session.root ?? '',
          linkStat: terminals?.backend.linkStat,
          skipShell: terminalSkipShell,
          onOpenLink: onOpenTerminalLink,
        ),
        // The list says when there are none.
        _ when shells.isEmpty && tasks.isEmpty && panel.listShown =>
          const SizedBox.shrink(),
        _ => _EmptySection(
          shells.isEmpty && tasks.isEmpty
              ? l10n.sidePanelNoTerminals
              : l10n.sidePanelSelectTerminal,
        ),
      },
    );
  }

  /// The plan the agent wrote, on its own: no list, its tab over it.
  Widget _planPage(BuildContext context, SidePanelTab plan) => Column(
    key: const ValueKey(('page', SidePanelSection.plan)),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _TabStrip(
        key: ValueKey(('plan', session)),
        selected: plan,
        entries: [
          (
            id: plan,
            child: FileDraggable(
              files: [ComposerFile(plan.path)],
              child: _Tab(
                active: true,
                icon: const _TabIcon(Codicons.checklist),
                label: _paths.basename(plan.path),
                tooltip: plan.path,
                dirty: plan.dirty,
                onTap: () {},
                onClose: () => unawaited(_close(context, [plan])),
                menu: () => _planMenu(context, plan),
              ),
            ),
          ),
        ],
      ),
      Expanded(child: _filePreview(context, plan, plan: true)),
    ],
  );

  /// The plan's tab's menu: closing it, opening its file on the files
  /// page, the file for the chat, copying its path, then where else it
  /// opens.
  List<IdeMenuEntry> _planMenu(BuildContext context, SidePanelTab plan) {
    final l10n = context.l10n;
    final path = plan.path;
    final local = files is! IdeHostFiles;
    return ideMenuGroups([
      [
        IdeMenuAction(
          l10n.tabClose,
          onSelected: () => unawaited(_close(context, [plan])),
        ),
      ],
      [
        IdeMenuAction(
          l10n.sidePanelOpenInFiles,
          onSelected: () => panel.open(session, FileOpenRequest(path)),
        ),
        IdeMenuAction(
          l10n.sidePanelAddToChat,
          onSelected: () => session.draft.insertFiles([ComposerFile(path)]),
        ),
        if (local)
          IdeMenuAction(
            l10n.commonCopy,
            onSelected: () =>
                unawaited(WindowControls.writePasteboardFiles([path])),
          ),
      ],
      [
        IdeMenuAction(
          l10n.tabCopyPath,
          onSelected: () =>
              unawaited(Clipboard.setData(ClipboardData(text: path))),
        ),
      ],
      [
        if (canSaveFileCopy) _saveAsItem(context, path, plan),
        if (local && WindowControls.canRevealInFileManager)
          IdeMenuAction(
            l10n.revealInFileManager,
            onSelected: () =>
                unawaited(WindowControls.revealInFileManager(path)),
          ),
        if (onOpenInIde case final open?)
          IdeMenuAction(
            l10n.sidePanelOpenInIde,
            onSelected: () => open(FileOpenRequest(path)),
          ),
      ],
    ]);
  }

  /// Closes [tabs], asking first whether to save those with unsaved
  /// changes.
  Future<void> _close(BuildContext context, List<SidePanelTab> tabs) =>
      closeSidePanelTabs(context, panel, session, tabs);

  /// A tab's Close, Close Others, Close to the Right and Close All, for
  /// the tab [id] at [index] of [count]; [close] closes those it picks of
  /// all the tabs.
  static List<IdeMenuEntry> _closeItems<T extends Object>(
    BuildContext context, {
    required T id,
    required int index,
    required int count,
    required void Function(List<T> Function(List<T> all) which) close,
  }) {
    final l10n = context.l10n;
    return [
      IdeMenuAction(l10n.tabClose, onSelected: () => close((_) => [id])),
      IdeMenuAction(
        l10n.tabCloseOthers,
        enabled: count > 1,
        onSelected: () => close(
          (all) => [
            for (final other in all)
              if (other != id) other,
          ],
        ),
      ),
      IdeMenuAction(
        l10n.tabCloseToTheRight,
        enabled: index >= 0 && index < count - 1,
        onSelected: () => close((all) => all.sublist(index + 1)),
      ),
      IdeMenuAction(l10n.tabCloseAll, onSelected: () => close((all) => all)),
    ];
  }

  /// The tabs of [list], [active] in front; each named by its file, and
  /// its folders where files of the same name are open; a change's with
  /// its status letter, as Git has it now.
  Widget? _fileTabs(
    BuildContext context,
    SidePanelTabs tabs,
    List<SidePanelTab> list,
    SidePanelTab? active,
  ) {
    if (list.isEmpty) return null;
    final root = session.root;
    final descriptions = ideTabDescriptions([
      for (final tab in list) tab.path,
    ], root ?? _paths.rootPrefix(list.first.path));
    final statuses = {
      for (final git in _gits)
        for (final resource in git.state?.resources ?? const <IdeGitResource>[])
          resource.path: resource.status,
    };
    return _TabStrip(
      key: ValueKey((tabs.section, session)),
      selected: active,
      entries: [
        for (final (i, tab) in list.indexed)
          (
            id: tab,
            child: _draggableTab(
              tab,
              statuses[tab.path],
              _Tab(
                active: identical(active, tab),
                icon: FileIcon(tab.path, size: _Tab.iconSize),
                label: _paths.basename(tab.path),
                description: descriptions[i],
                tooltip: tab.path,
                status: tab.diff ? statuses[tab.path] : null,
                dirty: tab.dirty,
                preview: tab.preview,
                onTap: () => panel.activate(session, tab),
                onDoubleTap: tab.preview ? () => panel.pin(tab) : null,
                onClose: () => unawaited(_close(context, [tab])),
                menu: () => _fileTabMenu(context, list, tab),
              ),
            ),
          ),
      ],
    );
  }

  /// [child], the tab of [tab], dragged onto the chat's composer, puts its
  /// file in, as the IDE's tabs do; not a deleted file's ([status]).
  Widget _draggableTab(SidePanelTab tab, IdeGitStatus? status, Widget child) =>
      tab.diff && (status?.strikeThrough ?? false)
      ? child
      : FileDraggable(files: [ComposerFile(tab.path)], child: child);

  /// A file's tab's menu, as the IDE editor's: closing it and the others,
  /// the file for the chat, copying its path, then where else it opens.
  List<IdeMenuEntry> _fileTabMenu(
    BuildContext context,
    List<SidePanelTab> list,
    SidePanelTab tab,
  ) {
    final l10n = context.l10n;
    final path = tab.path;
    final root = _rootOf(path);
    final local = files is! IdeHostFiles;
    return ideMenuGroups([
      _closeItems(
        context,
        id: tab,
        index: list.indexOf(tab),
        count: list.length,
        close: (which) => unawaited(_close(context, which([...list]))),
      ),
      [
        IdeMenuAction(
          l10n.sidePanelAddToChat,
          onSelected: () => session.draft.insertFiles([ComposerFile(path)]),
        ),
        if (local)
          IdeMenuAction(
            l10n.commonCopy,
            onSelected: () =>
                unawaited(WindowControls.writePasteboardFiles([path])),
          ),
      ],
      [
        IdeMenuAction(
          l10n.tabCopyPath,
          onSelected: () =>
              unawaited(Clipboard.setData(ClipboardData(text: path))),
        ),
        if (root != null && _paths.isWithin(root, path))
          IdeMenuAction(
            l10n.tabCopyRelativePath,
            onSelected: () => unawaited(
              Clipboard.setData(
                ClipboardData(text: _paths.relative(path, from: root)),
              ),
            ),
          ),
      ],
      [
        if (tab.diff)
          IdeMenuAction(
            l10n.scmOpenFile,
            onSelected: () => panel.open(session, FileOpenRequest(path)),
          ),
        if (root != null && _paths.isWithin(root, path))
          IdeMenuAction(
            l10n.sidePanelRevealInFiles,
            onSelected: () => _revealInFiles(path),
          ),
        if (canSaveFileCopy) _saveAsItem(context, path, tab),
        if (local && WindowControls.canRevealInFileManager)
          IdeMenuAction(
            l10n.revealInFileManager,
            onSelected: () =>
                unawaited(WindowControls.revealInFileManager(path)),
          ),
        if (onOpenInIde case final open?)
          IdeMenuAction(
            l10n.sidePanelOpenInIde,
            onSelected: () => open(tab.request),
          ),
      ],
    ]);
  }

  Widget _preview(BuildContext context, SidePanelTab tab) {
    // A file of its own kind (a stash): as that, not its text.
    if (tab.diff ? null : FileViews.of(tab.path) case final view?) {
      return KeyedSubtree(
        key: ValueKey((session, tab.path, view.id)),
        child: view.build(context, tab.path),
      );
    }
    return _filePreview(context, tab);
  }

  /// [tab]'s file; as [plan], its bar not naming its language and, put to
  /// the user, starting it as its card does.
  Widget _filePreview(
    BuildContext context,
    SidePanelTab tab, {
    bool plan = false,
  }) => FilePreview(
    key: ValueKey((session, tab.path, tab.diff)),
    request: tab.request,
    reveal: tab.reveal,
    edit: tab.edit,
    onEdit: (edit) => panel.keepEdit(tab, edit),
    agentEdit: tab.diff || tab.request.local || tab.request.readOnly
        ? null
        : IdeAgentEdit.inSession(session, tab.path),
    // In the tab of what was looked at last: one done, the next in its place.
    onOpenAgentChange: (path) => panel.open(
      session,
      FileOpenRequest(path, agentChange: true, preview: true),
    ),
    highlights: panel.highlights,
    formatter: tab.request.local ? null : formatter,
    // Shown as a file, on this machine (see FileOpenScope.showLocal).
    files: tab.request.local ? _localFiles : files,
    root: tab.request.local ? null : _rootOf(tab.path),
    readBytes: tab.request.local ? readFileBytes : readBytes,
    paths: tab.request.local ? null : paths,
    colorize: colorize,
    onOpenFile: (request) {
      final root = _rootOf(request.path);
      if (root == null) return;
      final path = FileLink.resolvePath(request.path, root, paths: paths);
      if (path != null) {
        panel.open(session, FileOpenRequest(path, range: request.range));
      }
    },
    language: !plan,
    actions: [
      if (plan)
        PlanStartBar(
          session: session,
          path: tab.path,
          maxPickerWidth: 180,
          padding: const EdgeInsets.only(left: 6),
        )
      else if (onOpenInIde case final open?)
        IdeActionButton(
          icon: Codicons.goToFile,
          tooltip: context.l10n.sidePanelOpenInIde,
          onPressed: () => open(tab.request),
        ),
    ],
  );
}

/// Closes [tabs] of [conversation] in [panel], asking first, as the IDE's
/// editor does, whether to save the changes of each not saved: none from
/// one canceled on.
Future<void> closeSidePanelTabs(
  BuildContext context,
  AgentSidePanel panel,
  Object conversation,
  List<SidePanelTab> tabs,
) async {
  for (final tab in tabs) {
    if (tab.dirty) {
      if (!context.mounted) return;
      final l10n = context.l10n;
      final choice = await showIdeDialog(
        context,
        message: l10n.wbConfirmSave(p.basename(tab.path)),
        detail: l10n.explorerChangesLost,
        buttons: [l10n.commonSave, l10n.commonDontSave],
      );
      if (choice == 0) {
        await tab.edit?.save();
        // Not saved (changed on disk meanwhile, say): kept open.
        if (tab.dirty) return;
      } else if (choice != 1) {
        return;
      }
    }
    panel.close(conversation, tab);
  }
}

extension SidePanelSectionUi on SidePanelSection {
  IconData get icon => switch (this) {
    SidePanelSection.files => Codicons.files,
    SidePanelSection.changes => Codicons.sourceControl,
    SidePanelSection.terminal => Codicons.terminal,
    SidePanelSection.browser => Codicons.globe,
    SidePanelSection.plan => Codicons.checklist,
  };

  /// The command that shows it; none for the plan's, there only at times.
  String? get command => switch (this) {
    SidePanelSection.files => ChatCommandIds.sidePanelFiles,
    SidePanelSection.changes => ChatCommandIds.sidePanelChanges,
    SidePanelSection.terminal => ChatCommandIds.sidePanelTerminal,
    SidePanelSection.browser || SidePanelSection.plan => null,
  };

  String label(BuildContext context) => switch (this) {
    SidePanelSection.files => context.l10n.sidePanelFiles,
    SidePanelSection.changes => context.l10n.sidePanelChanges,
    SidePanelSection.terminal => context.l10n.sidePanelTerminal,
    SidePanelSection.browser => context.l10n.sidePanelBrowser,
    SidePanelSection.plan => context.l10n.sidePanelPlan,
  };
}

/// The window's quick entries, just below the conversation title bar.
class SidePanelRail extends StatelessWidget {
  const SidePanelRail({
    super.key,
    required this.onSelect,
    this.session,
    this.gits = const [],
  });

  final ValueChanged<SidePanelSection> onSelect;

  /// The conversation focused: its background commands running are
  /// counted on the terminal's button.
  final ChatSession? session;

  /// The repositories whose changes are counted on the changes' button, as
  /// the pages' bar counts them.
  final List<IdeGitRepository> gits;

  /// What [section]'s button counts: none for the files.
  int _count(SidePanelSection section) => switch (section) {
    SidePanelSection.changes => gits.fold(
      0,
      (sum, git) => sum + (git.state?.count ?? 0),
    ),
    SidePanelSection.terminal =>
      session?.terminalTasks
              .where((task) => task.status == CommandStatus.running)
              .length ??
          0,
    SidePanelSection.files ||
    SidePanelSection.browser ||
    SidePanelSection.plan => 0,
  };

  static const _button = 26.0;
  static const _padding = 4.0;
  static const _gap = 4.0;

  /// Across, its border too.
  static const width = _button + 2 * _padding + 2;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([?session, ...gits]),
    builder: (context, _) => Container(
      key: const ValueKey('side-panel-rail'),
      width: width,
      padding: const EdgeInsets.all(_padding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.partBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, section) in alwaysShownSections.indexed) ...[
            if (i > 0) const SizedBox(height: _gap),
            Stack(
              clipBehavior: Clip.none,
              children: [
                SidebarIconButton(
                  icon: section.icon,
                  tooltip: section.label(context),
                  command: section.command,
                  size: _button,
                  onTap: () => onSelect(section),
                ),
                // At its top right corner, over the rail's edge, as an
                // activity bar's badge; the button's hover stays its own.
                if (_count(section) case final count when count > 0)
                  Positioned(
                    top: -5,
                    right: -7,
                    child: IgnorePointer(
                      child: IdeTitleBadge(
                        count,
                        key: ValueKey(('rail', section)),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

/// The pages' bar, a strip of the editor's tabs: each page's icon and
/// name (the icon alone where the panel is narrow), with a count of what
/// is in it; then showing the lists and hiding the panel.
class _SectionBar extends StatelessWidget {
  const _SectionBar({
    required this.panel,
    required this.session,
    required this.tabs,
    required this.changes,
    this.inset = 0,
    this.leading,
  });
  final AgentSidePanel panel;
  final ChatSession session;
  final SidePanelTabs tabs;

  /// Room kept at the left of the tabs (see
  /// [AgentSidePanelView.titleBarInset]).
  final double inset;

  /// See [AgentSidePanelView.leading].
  final Widget? leading;

  /// What [leading] takes, with its gap.
  static const _leadingWidth = 22.0 + 6;

  /// How many files Git has changed.
  final int changes;

  /// The list's toggle and the close button, at the right.
  static const _actionsWidth = 2 * 22.0 + 2 + 6;

  /// The pages there: the browser's once one of the user's has connected,
  /// the plan's once there is one.
  List<SidePanelSection> get _sections => [
    ...alwaysShownSections,
    if (BrowserBridge.instance.used) SidePanelSection.browser,
    if (tabs.plan != null) SidePanelSection.plan,
  ];

  /// What the tabs of [sections] take with their names (see
  /// [_SectionTab]), with [counts] by page: more than that, they show only
  /// their icons.
  static double _fullWidth(
    BuildContext context,
    List<SidePanelSection> sections,
    Map<SidePanelSection, int> counts,
  ) {
    final inherited = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: inherited.merge(style)),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    var width = 0.0;
    for (final section in sections) {
      // Its padding, icon, label and right border (see [IdeEditorTab]).
      width +=
          2 * IdeEditorTab.padding +
          IdeEditorTab.iconSize +
          IdeEditorTab.gap +
          measure(section.label(context), IdeEditorTab.labelStyleBase) +
          1;
      final count = counts[section] ?? 0;
      if (count > 0) {
        width +=
            IdeEditorTab.gap +
            math.max(
              16,
              2 * 4 + measure(IdeTitleBadge.text(count), IdeTitleBadge.style),
            );
      }
    }
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final running = session.terminalTasks
        .where((task) => task.status == CommandStatus.running)
        .length;
    return IdeTabStrip(
      line: AppColors.partBorder,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sections = _sections;
          final shown = tabs.shown;
          final compact =
              constraints.maxWidth <
              _fullWidth(context, sections, {
                    SidePanelSection.changes: changes,
                    SidePanelSection.terminal: running,
                  }) +
                  _actionsWidth +
                  inset +
                  (leading == null ? 0 : _leadingWidth);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: inset),
              if (leading case final leading?) ...[
                Center(child: leading),
                const SizedBox(width: 6),
              ],
              for (final section in sections)
                _SectionTab(
                  section: section,
                  selected: shown == section,
                  compact: compact,
                  count: switch (section) {
                    SidePanelSection.files ||
                    SidePanelSection.browser ||
                    SidePanelSection.plan => 0,
                    SidePanelSection.changes => changes,
                    SidePanelSection.terminal => running,
                  },
                  onTap: () => panel.showSection(session, section),
                ),
              const Spacer(),
              // To the conversations' other side.
              Center(
                child: IdeActionButton(
                  key: const ValueKey('side-panel-move'),
                  icon: Codicons.arrowSwap,
                  tooltip: KeybindingService.instance.titleWithKeybinding(
                    panel.atLeft
                        ? l10n.sidePanelMoveRight
                        : l10n.sidePanelMoveLeft,
                    ChatCommandIds.toggleSidePanelPosition,
                  ),
                  onPressed: () => panel.atLeft = !panel.atLeft,
                ),
              ),
              const SizedBox(width: 2),
              // The plan's page has no list to show or hide.
              if (shown != SidePanelSection.plan) ...[
                Center(
                  child: IdeActionButton(
                    key: const ValueKey('side-panel-list-toggle'),
                    icon: panel.listShown
                        ? Codicons.layoutSidebarLeft
                        : Codicons.layoutSidebarLeftOff,
                    tooltip: panel.listShown
                        ? l10n.sidePanelHideList
                        : l10n.sidePanelShowList,
                    onPressed: panel.toggleList,
                  ),
                ),
                const SizedBox(width: 2),
              ],
              Center(
                child: IdeActionButton(
                  icon: Codicons.close,
                  tooltip: KeybindingService.instance.titleWithKeybinding(
                    l10n.sidePanelHide,
                    ChatCommandIds.toggleSidePanel,
                  ),
                  onPressed: panel.hide,
                ),
              ),
              const SizedBox(width: 6),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTab extends StatelessWidget {
  const _SectionTab({
    required this.section,
    required this.selected,
    required this.compact,
    required this.count,
    required this.onTap,
  });

  final SidePanelSection section;
  final bool selected;
  final bool compact;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = section.label(context);
    return IdeEditorTab(
      key: ValueKey(section),
      icon: Icon(section.icon),
      label: compact ? null : label,
      trailing: count > 0 ? IdeTitleBadge(count) : null,
      active: selected,
      minWidth: 0,
      // The page's sections, not files: no line above the one shown.
      borderTop: false,
      tooltip: switch (section.command) {
        final command? => KeybindingService.instance.titleWithKeybinding(
          label,
          command,
        ),
        null => label,
      },
      onSelect: onTap,
    );
  }
}

/// A page: [list] at the left while the panel's lists show, as wide as
/// its right edge is dragged (a double click gives back its width); [tabs]
/// over [body] at the right.
class _Page extends StatefulWidget {
  const _Page({
    super.key,
    required this.panel,
    required this.list,
    required this.tabs,
    required this.body,
  });

  final AgentSidePanel panel;
  final Widget list;
  final Widget? tabs;
  final Widget body;

  /// The strip over the list's right edge, half on either side, that takes
  /// the drag.
  static const sashWidth = 4.0;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  bool _dragging = false;
  ({double x, double width})? _dragStart;

  AgentSidePanel get _panel => widget.panel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final room = constraints.maxWidth;
      // The tabs keep at least 200px, unless the list would be narrower
      // than about half the page.
      final listWidth = math.min(
        _panel.listWidth,
        math.max(room * 0.45, room - 200),
      );
      // The list against the tabs, the line between them its border; the
      // sash over that line, as the IDE's are.
      return Stack(
        children: [
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_panel.listShown)
                  SizedBox(
                    key: const ValueKey('side-panel-list'),
                    width: listWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: AppColors.partBorder),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 1),
                        child: widget.list,
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ?widget.tabs,
                      Expanded(child: widget.body),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_panel.listShown)
            Positioned(
              left: listWidth - _Page.sashWidth / 2,
              top: 0,
              bottom: 0,
              width: _Page.sashWidth,
              child: _sash(listWidth),
            ),
        ],
      );
    },
  );

  Widget _sash(double width) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      key: const ValueKey('side-panel-list-sash'),
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: (details) => setState(() {
        _dragging = true;
        _dragStart = (x: details.globalPosition.dx, width: width);
      }),
      onHorizontalDragUpdate: (details) {
        final start = _dragStart;
        if (start == null) return;
        _panel.listWidth = start.width + details.globalPosition.dx - start.x;
      },
      onHorizontalDragEnd: (_) => _endDrag(),
      onHorizontalDragCancel: _endDrag,
      onDoubleTap: () {
        _panel.listWidth = AgentSidePanel.defaultListWidth;
        _panel.save();
      },
      // Invisible over the line at rest; dragged, `sash.hoverBorder`.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: _Page.sashWidth,
        color: _dragging ? IdeModernUI.sashHover : Colors.transparent,
      ),
    ),
  );

  void _endDrag() {
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _dragStart = null;
    });
    _panel.save();
  }
}

/// A page's tabs, the IDE editor's ([IdeTabStrip]): scrolled to keep the one in front
/// in sight.
class _TabStrip extends StatefulWidget {
  const _TabStrip({super.key, required this.selected, required this.entries});
  final Object? selected;
  final List<({Object id, Widget child})> entries;

  @override
  State<_TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<_TabStrip> {
  final _scroll = ScrollController();
  final Map<Object, GlobalKey> _keys = {};

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(_TabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected ||
        oldWidget.entries.length != widget.entries.length) {
      _reveal();
    }
    _keys.removeWhere(
      (id, _) => !widget.entries.any((entry) => entry.id == id),
    );
  }

  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    final target = _keys[widget.selected]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
    Scrollable.ensureVisible(
      target,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  });

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IdeTabStrip(
    line: AppColors.partBorder,
    child: TabStripScroll(
      controller: _scroll,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in widget.entries)
            KeyedSubtree(
              key: _keys.putIfAbsent(entry.id, GlobalKey.new),
              child: entry.child,
            ),
        ],
      ),
    ),
  );
}

/// A codicon in a tab, as big as a file's icon there.
class _TabIcon extends StatelessWidget {
  const _TabIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: _Tab.iconSize, color: themeColors['icon.foreground']);
}

/// A tab, as the IDE editor's: its icon and name (and [description], the
/// folders telling it from another of the same name, and a change's
/// [status] letter in its color), its close button while it is in front
/// or hovered, its [menu] on a right click; in the theme's `tab.*` colors.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
    this.description,
    this.tooltip,
    this.status,
    this.dirty = false,
    this.preview = false,
    this.onClose,
    this.menu,
    this.onDoubleTap,
  });

  final bool active;

  /// The tab of what was looked at last: its label in italics, as VS
  /// Code's preview editor's; a double click ([onDoubleTap]) keeps it.
  final bool preview;
  final VoidCallback? onDoubleTap;
  final Widget icon;
  final String label;
  final String? description;
  final VoidCallback onTap;
  final String? tooltip;
  final IdeGitStatus? status;

  /// Its file has unsaved changes: a dot where its Close is, as an
  /// editor's tab, the Close there while hovered.
  final bool dirty;
  final VoidCallback? onClose;
  final List<IdeMenuEntry> Function()? menu;

  static const iconSize = 14.0;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    return IdeEditorTab(
      icon: icon,
      label: label,
      description: description,
      labelStyle: status == null && !preview
          ? null
          : TextStyle(
              color: status?.color,
              fontStyle: preview ? FontStyle.italic : null,
              decoration: status?.strikeThrough ?? false
                  ? TextDecoration.lineThrough
                  : null,
            ),
      trailing: status == null
          ? null
          : Text(
              status.letter,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: status.color,
              ),
            ),
      active: active,
      tooltip: tooltip,
      minWidth: 64,
      onSelect: onTap,
      onDoubleTap: onDoubleTap,
      mark: dirty
          ? (color) => Icon(Codicons.circleFilled, size: 10, color: color)
          : null,
      closeTooltip: context.l10n.sidePanelCloseTab,
      onClose: onClose,
      onMenu: switch (menu) {
        final menu? => (position) => unawaited(
          showIdeMenu(context, position: position, entries: menu()),
        ),
        null => null,
      },
    );
  }
}

/// The files page of a workspace with no folders yet: a button to add
/// one.
class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace({this.onAddFolder});

  final VoidCallback? onAddFolder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.ideEmptyWorkspace,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.textMuted,
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
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
    ),
  );
}

/// The changes page where Git is not at hand: what the IDE's Source Control
/// says outside a repository.
class _NoRepository extends StatelessWidget {
  const _NoRepository();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: Text(
      context.l10n.scmNoRepository,
      style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.textMuted),
    ),
  );
}

/// The title bar's button for the side panel: the layout icon, which
/// shows whether it is open; its hover Toggle Side Panel's title.
class SidePanelToggle extends StatelessWidget {
  const SidePanelToggle({
    super.key,
    required this.shown,
    required this.onTap,
    this.size = 24,
  });

  final bool shown;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => SidebarIconButton(
    icon: shown ? Codicons.layoutSidebarRight : Codicons.layoutSidebarRightOff,
    tooltip: context.l10n.cmdToggleSidePanel,
    command: ChatCommandIds.toggleSidePanel,
    size: size,
    onTap: onTap,
  );
}

/// The side panel's project as Source Control works on it: its
/// repositories (a workspace's folders', or those found in the project's
/// subfolders), the one picked, which are folded; files on its host.
class _SidePanelScmHost implements IdeScmHost {
  _SidePanelScmHost(this.view);

  final AgentSidePanelView view;

  @override
  String get root => view.session.root ?? '';

  @override
  IdeFileService get files => view.files;

  @override
  List<(String root, IdeGitRepository git)> get repositories =>
      view.repositories;

  @override
  IdeGitRepository? get git => view._git;

  @override
  void selectRepository(IdeGitRepository git) {
    final root = view.session.root;
    if (root == null) return;
    for (final (folder, of) in view.repositories) {
      if (identical(of, git)) {
        view.panel.selectRepository(root, folder);
        return;
      }
    }
  }

  @override
  Set<String> get scmCollapsedRepositories => view.panel.scmCollapsedOf(root);

  /// Nothing to read again: a file shown here reads itself anew as it
  /// changes.
  @override
  Future<void> reload(Iterable<String> paths) async {}

  @override
  Future<void> appendLines(String path, String lines) =>
      ideAppendLinesToFile(files, path, lines);

  @override
  String? get activePath => null;
}
