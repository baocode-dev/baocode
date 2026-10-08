import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../ide/file_service.dart';
import '../../ide/git/git_model.dart';
import '../../ide/git/git_repository.dart';
import '../../ide/ide_button.dart';
import '../../ide/ide_dialog.dart';
import '../../ide/ide_explorer.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_list.dart';
import '../../ide/ide_menu.dart';
import '../../ide/ide_modern_ui.dart';
import '../../ide/ide_panes.dart' show IdeViewTitle;
import '../../ide/ide_tab_bar.dart' show ideTabDescriptions;
import '../../ide/tab_strip_scroll.dart';
import '../../ide/terminal/links/terminal_links.dart' show TerminalLink;
import '../../ide/terminal/terminal_instance.dart';
import '../../ide/terminal/terminal_service.dart';
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
import '../widgets/hover_builder.dart';
import '../composer/composer_files.dart';
import '../composer/file_drag.dart';
import 'file_link.dart';
import 'file_open.dart';
import 'file_preview.dart';
import 'git_changes.dart';
import 'side_panel_controller.dart';
import 'terminal_preview.dart';

/// [child] (the conversations) and, at its right while [panel] shows, the
/// side panel [builder] builds: beside it, its left edge dragged to make
/// it wider or narrower (a double click gives back its width), narrower
/// where the conversations would have less than [minChat]; over it, where
/// they would beside it at its least.
class AgentSidePanelArea extends StatefulWidget {
  const AgentSidePanelArea({
    super.key,
    required this.panel,
    required this.builder,
    this.rail,
    this.hidden = false,
    required this.child,
  });

  final AgentSidePanel panel;
  final WidgetBuilder builder;
  final Widget? rail;

  /// Whether it gave way to the window's sidebar, though shown: the rail
  /// is there instead, to ask for it again.
  final bool hidden;
  final Widget child;

  /// The least the conversations keep beside it.
  static const minChat = 360.0;

  /// The strip at its left edge that takes the drag.
  static const sashWidth = 5.0;

  /// What the rail keeps at the conversations' right while the panel is
  /// hidden, as VS Code's activity bar keeps its own: they are this much
  /// narrower, not under it.
  static const railWidth = 48.0;

  @override
  State<AgentSidePanelArea> createState() => _AgentSidePanelAreaState();
}

class _AgentSidePanelAreaState extends State<AgentSidePanelArea> {
  bool _dragging = false;
  ({double x, double width})? _dragStart;

  AgentSidePanel get _panel => widget.panel;

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
        final overlay =
            room - AgentSidePanel.minWidth < AgentSidePanelArea.minChat;
        final width = overlay
            ? math.min(_panel.width, math.max(0.0, room - 48))
            : math.min(
                _panel.width,
                room -
                    AgentSidePanelArea.minChat -
                    AgentSidePanelArea.sashWidth,
              );
        // Each child keyed: the conversations and the panel are never
        // built anew as the rail, the scrim or the drag's cursor come and
        // go (the panel built anew mid-drag would drop the drag, and
        // leave the cursor's cover over the window).
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              key: const ValueKey('chat'),
              left: 0,
              top: 0,
              bottom: 0,
              right: shown && !overlay
                  ? width + AgentSidePanelArea.sashWidth
                  : !shown && widget.rail != null
                  ? AgentSidePanelArea.railWidth
                  : 0,
              child: widget.child,
            ),
            if (!shown && widget.rail != null)
              Positioned(
                key: const ValueKey('rail'),
                right: 10,
                top: AppMetrics.titleBarHeight + 12,
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
                right: 0,
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
                    children: [
                      _sash(),
                      Expanded(
                        // A click anywhere in it puts the focus there (on
                        // what takes it, else on the panel), for its keys.
                        child: Listener(
                          onPointerDown: (_) {
                            if (!_panel.focusNode.hasFocus) {
                              _panel.focusNode.requestFocus();
                            }
                          },
                          child: Focus(
                            focusNode: _panel.focusNode,
                            child: ColoredBox(
                              color: AppColors.background,
                              child: widget.builder(context),
                            ),
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

  Widget _sash() => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      key: const ValueKey('side-panel-sash'),
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: (details) => setState(() {
        _dragging = true;
        _dragStart = (x: details.globalPosition.dx, width: _panel.width);
      }),
      onHorizontalDragUpdate: (details) {
        final start = _dragStart;
        if (start == null) return;
        final room =
            (context.size?.width ?? double.infinity) -
            AgentSidePanelArea.minChat;
        _panel.width = math.min(
          start.width - (details.globalPosition.dx - start.x),
          math.max(AgentSidePanel.minWidth, room),
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
        alignment: Alignment.centerRight,
        // At rest the line between the two; dragged, as thick as the IDE's
        // sashes, in their `sash.hoverBorder`.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: _dragging ? IdeModernUI.gap : 1,
          color: _dragging ? IdeModernUI.sashHover : AppColors.border,
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
    this.watchDirectory,
    this.git,
    this.terminals,
    this.terminalSkipShell = const [],
    this.onOpenTerminalLink,
  });

  final AgentSidePanel panel;
  final ChatSession session;

  /// The project's, on its host.
  final IdeFileService files;
  final Future<Uint8List> Function(String path)? readBytes;
  final p.Context? paths;
  final CodeColorizer? colorize;

  /// Opens a file shown in the IDE instead.
  final ValueChanged<FileOpenRequest>? onOpenInIde;

  /// Changes to a folder's entries, for the files page's tree to follow;
  /// the explorer's own watch when null.
  final Stream<void> Function(String directory)? watchDirectory;

  /// The project's repository, whose changes the changes page lists; none
  /// where Git is not at hand.
  final IdeGitRepository? git;

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
    listenable: Listenable.merge([panel, session, ?git, ?terminals]),
    builder: (context, _) {
      final tabs = panel.tabsOf(session);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionBar(
            panel: panel,
            session: session,
            tabs: tabs,
            changes: git?.state?.count ?? 0,
          ),
          Expanded(
            child: switch (tabs.section) {
              SidePanelSection.files => _filesPage(context, tabs),
              SidePanelSection.changes => _changesPage(context, tabs),
              SidePanelSection.terminal => _terminalPage(context, tabs),
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
        : panel.explorerOf(root, files, watch: watchDirectory);
    final local = files is! IdeHostFiles;
    return _Page(
      key: const ValueKey(('page', SidePanelSection.files)),
      panel: panel,
      list: explorer == null
          ? _EmptySection(l10n.sidePanelNoFolder)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ListHeader(
                  title: _paths.basename(explorer.root),
                  actions: [
                    IdeActionButton(
                      icon: Codicons.refresh,
                      tooltip: l10n.cmdRefreshExplorer,
                      onPressed: () => unawaited(explorer.refresh()),
                    ),
                    IdeActionButton(
                      icon: Codicons.collapseAll,
                      tooltip: l10n.cmdCollapseExplorerFolders,
                      onPressed: explorer.collapseAll,
                    ),
                  ],
                ),
                Expanded(
                  child: IdeExplorer(
                    key: ObjectKey(explorer),
                    controller: explorer,
                    local: local,
                    trash: local && WindowControls.canMoveToTrash
                        ? WindowControls.moveToTrash
                        : null,
                    onOpen: (path, _) =>
                        panel.open(session, FileOpenRequest(path)),
                    // A paste, rename or delete that failed.
                    onError: (error) => unawaited(
                      showIdeDialog(
                        context,
                        type: IdeDialogType.error,
                        message: localizedFileError(l10n, error),
                        buttons: const [],
                        cancel: l10n.commonOk,
                      ),
                    ),
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

  /// The project's Git changes (see [GitChangeList]), as a tree or a
  /// list as the IDE's Source Control view shows them, and the changes
  /// opened from it or from the conversation; or, while there are none,
  /// what goes here.
  Widget _changesPage(BuildContext context, SidePanelTabs tabs) {
    final l10n = context.l10n;
    final git = this.git;
    final state = git?.state;
    final active = tabs.activeDiff;
    final local = files is! IdeHostFiles;
    if (state != null && state.count == 0 && tabs.diffs.isEmpty) {
      return const _NoChanges();
    }
    final Widget list;
    if (git == null || (git.loaded && state == null)) {
      list = _NoRepository(
        onInitialize: git == null || session.root == null
            ? null
            : () => unawaited(git.initialize()),
      );
    } else if (state == null) {
      list = const SizedBox.shrink();
    } else {
      list = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ListHeader(
            title: l10n.sidePanelChanges,
            count: state.count,
            actions: [
              IdeActionButton(
                key: const ValueKey('side-panel-view-as'),
                icon: panel.changesAsTree
                    ? Codicons.listFlat
                    : Codicons.listTree,
                tooltip: panel.changesAsTree
                    ? l10n.scmViewAsList
                    : l10n.scmViewAsTree,
                onPressed: () => panel.changesAsTree = !panel.changesAsTree,
              ),
              IdeActionButton(
                icon: Codicons.refresh,
                tooltip: l10n.commonRefresh,
                onPressed: () => unawaited(git.refresh(force: true)),
              ),
            ],
          ),
          Expanded(
            child: state.count == 0
                ? _EmptySection(l10n.sidePanelNoChanges)
                : GitChangeList(
                    git: git,
                    state: state,
                    tree: panel.changesAsTree,
                    selected: active?.path,
                    local: local,
                    trash: local && WindowControls.canMoveToTrash
                        ? WindowControls.moveToTrash
                        : null,
                    onOpen: (resource) => panel.open(
                      session,
                      gitChangeRequest(git, state, resource),
                    ),
                    onOpenFile: (path) =>
                        panel.open(session, FileOpenRequest(path)),
                    onRevealInFiles: _revealInFiles,
                    onAddToChat: session.draft.insertFiles,
                  ),
          ),
        ],
      );
    }
    return _Page(
      key: const ValueKey(('page', SidePanelSection.changes)),
      panel: panel,
      list: list,
      tabs: _fileTabs(context, tabs, tabs.diffs, active),
      body: active == null
          ? _EmptySection(l10n.sidePanelSelectChange)
          : _preview(context, active),
    );
  }

  /// Shows [path] in the files page's tree.
  void _revealInFiles(String path) {
    final root = session.root;
    if (root == null) return;
    final explorer = panel.explorerOf(root, files, watch: watchDirectory);
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
      list: _TerminalList(
        shells: terminals == null ? null : shells,
        tasks: tasks,
        selected: current?.id,
        onOpen: (id) => panel.openTerminal(session, id),
        onNew: terminals == null ? null : newTerminal,
        onKill: kill,
        onStop: stop,
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
                          onTap: () => panel.openTerminal(session, id),
                          onClose: () => panel.closeTerminal(session, id),
                          menu: () => menu(id),
                        ),
                      ),
                      final task as KernelTask => _Tab(
                        active: id == current?.id,
                        icon: _TaskIcon(task, size: _Tab.iconSize),
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
      for (final resource in git?.state?.resources ?? const <IdeGitResource>[])
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
                onTap: () => panel.activate(session, tab),
                onClose: () => panel.close(session, tab),
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
    final root = session.root;
    final path = tab.path;
    final local = files is! IdeHostFiles;
    return ideMenuGroups([
      _closeItems(
        context,
        id: tab,
        index: list.indexOf(tab),
        count: list.length,
        close: (which) {
          for (final other in which([...list])) {
            panel.close(session, other);
          }
        },
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

  Widget _preview(BuildContext context, SidePanelTab tab) => FilePreview(
    key: ValueKey((session, tab.path, tab.diff)),
    request: tab.request,
    reveal: tab.reveal,
    files: files,
    root: session.root,
    readBytes: readBytes,
    paths: paths,
    colorize: colorize,
    onOpenFile: (request) {
      final root = session.root;
      if (root == null) return;
      final path = FileLink.resolvePath(request.path, root, paths: paths);
      if (path != null) {
        panel.open(session, FileOpenRequest(path, range: request.range));
      }
    },
    actions: [
      if (onOpenInIde case final open?)
        IdeActionButton(
          icon: Codicons.goToFile,
          tooltip: context.l10n.sidePanelOpenInIde,
          onPressed: () => open(tab.request),
        ),
    ],
  );
}

extension SidePanelSectionUi on SidePanelSection {
  IconData get icon => switch (this) {
    SidePanelSection.files => Codicons.files,
    SidePanelSection.changes => Codicons.sourceControl,
    SidePanelSection.terminal => Codicons.terminal,
  };

  String get command => switch (this) {
    SidePanelSection.files => ChatCommandIds.sidePanelFiles,
    SidePanelSection.changes => ChatCommandIds.sidePanelChanges,
    SidePanelSection.terminal => ChatCommandIds.sidePanelTerminal,
  };

  String label(BuildContext context) => switch (this) {
    SidePanelSection.files => context.l10n.sidePanelFiles,
    SidePanelSection.changes => context.l10n.sidePanelChanges,
    SidePanelSection.terminal => context.l10n.sidePanelTerminal,
  };
}

/// The window's quick entries, just below the conversation title bar.
class SidePanelRail extends StatelessWidget {
  const SidePanelRail({super.key, required this.onSelect});

  final ValueChanged<SidePanelSection> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('side-panel-rail'),
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final section in SidePanelSection.values)
          SidebarIconButton(
            icon: section.icon,
            tooltip: section.label(context),
            command: section.command,
            size: 28,
            onTap: () => onSelect(section),
          ),
      ],
    ),
  );
}

/// The pages' bar, as the IDE panel's title: each page's icon and name
/// (the icon alone where the panel is narrow), with a count of what is in
/// it, the one shown underlined; then showing the lists and hiding the
/// panel.
class _SectionBar extends StatelessWidget {
  const _SectionBar({
    required this.panel,
    required this.session,
    required this.tabs,
    required this.changes,
  });
  final AgentSidePanel panel;
  final ChatSession session;
  final SidePanelTabs tabs;

  /// How many files Git has changed.
  final int changes;

  static const height = 35.0;

  /// The list's toggle and the close button, at the right.
  static const _actionsWidth = 2 * 22.0 + 2;

  /// What the tabs take with their names (see [_SectionTab]), with
  /// [counts] by page: more than that, they show only their icons.
  static double _fullWidth(
    BuildContext context,
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
    for (final section in SidePanelSection.values) {
      width +=
          2 * 2 +
          2 * 8 +
          15 +
          5 +
          measure(
            section.label(context),
            _SectionTab.labelStyle(selected: true),
          );
      final count = counts[section] ?? 0;
      if (count > 0) {
        width +=
            5 + math.max(16, 2 * 4 + measure(_Badge.text(count), _Badge.style));
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
    return Container(
      height: height,
      padding: const EdgeInsets.only(left: 6, right: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth <
              _fullWidth(context, {
                    SidePanelSection.changes: changes,
                    SidePanelSection.terminal: running,
                  }) +
                  _actionsWidth;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final section in SidePanelSection.values)
                _SectionTab(
                  section: section,
                  selected: tabs.section == section,
                  compact: compact,
                  count: switch (section) {
                    SidePanelSection.files => 0,
                    SidePanelSection.changes => changes,
                    SidePanelSection.terminal => running,
                  },
                  onTap: () => panel.showSection(session, section),
                ),
              const Spacer(),
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

  static TextStyle labelStyle({required bool selected}) => TextStyle(
    fontSize: 12,
    height: 1.2,
    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
  );

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final label = section.label(context);
    return IdeHover(
      message: KeybindingService.instance.titleWithKeybinding(
        label,
        section.command,
      ),
      child: Semantics(
        selected: selected,
        button: true,
        label: compact ? label : null,
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) {
            final foreground =
                colors[selected || hovered
                    ? 'panelTitle.activeForeground'
                    : 'panelTitle.inactiveForeground'];
            return GestureDetector(
              key: ValueKey(section),
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 6 : 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(section.icon, size: 15, color: foreground),
                          if (!compact) ...[
                            const SizedBox(width: 5),
                            Text(
                              label,
                              maxLines: 1,
                              style: labelStyle(selected: selected)
                                  .copyWith(color: foreground),
                            ),
                          ],
                          if (count > 0) ...[
                            const SizedBox(width: 5),
                            _Badge(count),
                          ],
                        ],
                      ),
                    ),
                    // Under the icon and name, as the panel's title's.
                    if (selected)
                      Positioned(
                        left: compact ? 4 : 6,
                        right: compact ? 4 : 6,
                        bottom: 0,
                        height: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors['panelTitle.activeBorder'],
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A page's count in its tab, as the panel title's badge.
class _Badge extends StatelessWidget {
  const _Badge(this.count);

  final int count;

  static String text(int count) => count > 99 ? '99+' : '$count';

  static const style = TextStyle(fontSize: 10, height: 1.2);

  @override
  Widget build(BuildContext context) => Center(
    widthFactor: 1,
    heightFactor: 1,
    child: Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: themeColors['panelTitleBadge.background'],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          text(count),
          style: style.copyWith(
            color: themeColors['panelTitleBadge.foreground'],
          ),
        ),
      ),
    ),
  );
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

  /// The strip at the list's right edge that takes the drag.
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
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_panel.listShown) ...[
            SizedBox(
              key: const ValueKey('side-panel-list'),
              width: listWidth,
              child: widget.list,
            ),
            _sash(listWidth),
          ],
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
      child: Container(
        width: _Page.sashWidth,
        alignment: Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: _dragging ? _Page.sashWidth : 1,
          color: _dragging ? IdeModernUI.sashHover : AppColors.border,
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

/// A list's title, as a side bar pane's: [title], what [count] says, and
/// [actions] at the end; as high as the tabs beside it, its line under it
/// running on under theirs.
class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.title, this.count, this.actions = const []});

  final String title;
  final int? count;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    height: _TabStrip.height,
    padding: const EdgeInsets.only(left: 12, right: 6),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: _TabStrip.borderColor)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: IdeViewTitle.foreground,
                  ),
                ),
              ),
              if (count case final count?) ...[
                const SizedBox(width: 6),
                _Badge(count),
              ],
            ],
          ),
        ),
        for (final action in actions)
          Padding(padding: const EdgeInsets.only(left: 2), child: action),
      ],
    ),
  );
}

/// A page's tabs, as the IDE editor's: scrolled to keep the one in front
/// in sight.
class _TabStrip extends StatefulWidget {
  const _TabStrip({super.key, required this.selected, required this.entries});
  final Object? selected;
  final List<({Object id, Widget child})> entries;

  static const height = 32.0;

  static Color get borderColor =>
      themeColors.get('editorGroupHeader.tabsBorder') ?? AppColors.border;

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
  Widget build(BuildContext context) => Container(
    height: _TabStrip.height,
    decoration: BoxDecoration(
      color: themeColors['editorGroupHeader.tabsBackground'],
      border: Border(bottom: BorderSide(color: _TabStrip.borderColor)),
    ),
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
    this.onClose,
    this.menu,
  });

  final bool active;
  final Widget icon;
  final String label;
  final String? description;
  final VoidCallback onTap;
  final String? tooltip;
  final IdeGitStatus? status;
  final VoidCallback? onClose;
  final List<IdeMenuEntry> Function()? menu;

  static const iconSize = 14.0;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final tab = HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hover) {
        // The tab in front is selected: hovering it changes nothing.
        final hovered = hover && !active;
        final foreground = active
            ? colors['tab.activeForeground']
            : (hovered ? colors.get('tab.hoverForeground') : null) ??
                  colors['tab.inactiveForeground'];
        final bottom = active ? colors.get('tab.activeBorder') : null;
        final status = this.status;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // A middle click closes it, as an editor's tab.
          onTertiaryTapUp: onClose == null ? null : (_) => onClose!(),
          onSecondaryTapUp: menu == null
              ? null
              : (details) => unawaited(
                  showIdeMenu(
                    context,
                    position: details.globalPosition,
                    entries: menu!(),
                  ),
                ),
          child: Container(
            constraints: const BoxConstraints(minWidth: 64, maxWidth: 200),
            padding: EdgeInsets.only(left: 10, right: onClose == null ? 10 : 4),
            decoration: BoxDecoration(
              color: active
                  ? colors['list.activeSelectionBackground']
                  : (hovered ? colors.get('tab.hoverBackground') : null) ??
                        colors['tab.inactiveBackground'],
              border: Border(
                right: BorderSide(
                  color:
                      colors.get('tab.border') ??
                      colors.get('contrastBorder') ??
                      _TabStrip.borderColor,
                ),
              ),
            ),
            foregroundDecoration: bottom == null
                ? null
                : BoxDecoration(
                    border: Border(bottom: BorderSide(color: bottom)),
                  ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(dimension: 16, child: Center(child: icon)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      text: label,
                      style: status == null
                          ? null
                          : TextStyle(
                              color: status.color,
                              decoration: status.strikeThrough
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                      children: [
                        if (description case final description?)
                          TextSpan(
                            text: '  $description',
                            style: TextStyle(
                              color: foreground.withValues(
                                alpha: foreground.a * .7,
                              ),
                              fontSize: 11,
                              decoration: TextDecoration.none,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: foreground),
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    status.letter,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: status.color,
                    ),
                  ),
                ],
                if (onClose case final close?) ...[
                  const SizedBox(width: 2),
                  SizedBox.square(
                    dimension: 20,
                    child: active || hover
                        ? IdeActionButton(
                            icon: Codicons.close,
                            size: 20,
                            iconSize: 12,
                            color: foreground,
                            tooltip: context.l10n.sidePanelCloseTab,
                            onPressed: close,
                          )
                        : null,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
    return Semantics(
      button: true,
      selected: active,
      label: tooltip ?? label,
      child: tooltip == null ? tab : IdeHover(message: tooltip!, child: tab),
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

/// The changes page outside a Git repository: what the IDE's Source
/// Control says, and its Initialize Repository.
class _NoRepository extends StatelessWidget {
  const _NoRepository({this.onInitialize});

  final VoidCallback? onInitialize;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.scmNoRepository,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
          if (onInitialize case final initialize?) ...[
            const SizedBox(height: 12),
            IdeButton(
              label: l10n.scmInitializeRepository,
              expand: true,
              onPressed: initialize,
            ),
          ],
        ],
      ),
    );
  }
}

/// The changes page while Git sees no change.
class _NoChanges extends StatelessWidget {
  const _NoChanges();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Codicons.sourceControl, size: 22, color: AppColors.textFaint),
            const SizedBox(height: 10),
            Text(
              l10n.sidePanelNoChanges,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.sidePanelNoChangesDetail,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textFaint, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// A background command's state: running, done or failed.
class _TaskIcon extends StatelessWidget {
  const _TaskIcon(this.task, {this.size = 16});

  final KernelTask task;
  final double size;

  @override
  Widget build(BuildContext context) => switch (task.status) {
    CommandStatus.running => Icon(
      Codicons.terminal,
      size: size,
      color: themeColors['icon.foreground'],
    ),
    CommandStatus.succeeded => Icon(
      Codicons.pass,
      size: size,
      color: AppColors.added,
    ),
    CommandStatus.failed => Icon(
      Codicons.error,
      size: size,
      color: themeColors['errorForeground'],
    ),
  };
}

/// The terminal page's list: the project's terminals (where they can
/// run), then the agent's background commands, each in a group that
/// folds; each opens in a tab.
class _TerminalList extends StatefulWidget {
  const _TerminalList({
    required this.shells,
    required this.tasks,
    required this.selected,
    required this.onOpen,
    this.onNew,
    this.onKill,
    this.onStop,
  });

  /// Null where terminals cannot run.
  final List<TerminalInstance>? shells;
  final List<KernelTask> tasks;

  /// The one in front: a terminal, or a command's id.
  final Object? selected;

  /// Opens a terminal, or a command's output (by its id).
  final ValueChanged<Object> onOpen;
  final VoidCallback? onNew;
  final ValueChanged<TerminalInstance>? onKill;
  final ValueChanged<KernelTask>? onStop;

  @override
  State<_TerminalList> createState() => _TerminalListState();
}

class _TerminalListState extends State<_TerminalList> {
  final Set<String> _collapsed = {};

  Widget _group(
    String id,
    IconData icon,
    String label,
    int count, {
    List<Widget> actions = const [],
    List<IdeMenuEntry> menu = const [],
  }) {
    final collapsed = _collapsed.contains(id);
    return IdeListRow(
      key: ValueKey(id),
      onContextMenu: menu.isEmpty ? null : (position) => _menu(position, menu),
      onTap: () => setState(() {
        if (!_collapsed.remove(id)) _collapsed.add(id);
      }),
      builder: (context, hovered) => Padding(
        padding: const EdgeInsets.only(left: 4, right: 8),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Icon(
                collapsed ? Codicons.chevronRight : Codicons.chevronDown,
                size: 16,
                color: IdeListColors.foreground,
              ),
            ),
            Icon(icon, size: 16, color: themeColors['icon.foreground']),
            const SizedBox(width: 6),
            Expanded(
              child: IdeResourceLabel(name: label, actions: actions),
            ),
            if (count > 0) ...[const SizedBox(width: 4), IdeCountBadge(count)],
          ],
        ),
      ),
    );
  }

  void _menu(Offset position, List<IdeMenuEntry> entries) =>
      unawaited(showIdeMenu(context, position: position, entries: entries));

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(26, 4, 8, 4),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, color: IdeListColors.description),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final shells = widget.shells;
    final tasks = widget.tasks;
    return ColoredBox(
      key: const ValueKey('side-panel-terminals'),
      color: AppColors.background,
      child: ListenableBuilder(
        listenable: Listenable.merge([...?shells]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          children: [
            if (shells != null) ...[
              _group(
                'terminals',
                Codicons.terminal,
                l10n.sidePanelTerminals,
                shells.length,
                menu: [
                  if (widget.onNew case final onNew?)
                    IdeMenuAction(l10n.termNewTerminal, onSelected: onNew),
                ],
                actions: [
                  if (widget.onNew case final onNew?)
                    IdeActionButton(
                      key: const ValueKey('side-panel-new-terminal'),
                      icon: Codicons.add,
                      size: 20,
                      tooltip: l10n.termNewTerminal,
                      onPressed: onNew,
                    ),
                ],
              ),
              if (!_collapsed.contains('terminals'))
                for (final shell in shells)
                  IdeListRow(
                    key: ValueKey(('shell', shell)),
                    selected: identical(shell, widget.selected),
                    tooltip: shell.title,
                    onTap: () => widget.onOpen(shell),
                    onContextMenu: (position) => _menu(position, [
                      IdeMenuAction(
                        l10n.termNewTerminal,
                        enabled: widget.onNew != null,
                        onSelected: widget.onNew,
                      ),
                      if (widget.onKill case final kill?)
                        IdeMenuAction(
                          l10n.termKillTerminal,
                          onSelected: () => kill(shell),
                        ),
                    ]),
                    builder: (context, hovered) => Padding(
                      padding: const EdgeInsets.only(left: 26, right: 8),
                      child: Row(
                        children: [
                          Icon(
                            shell.exited ? Codicons.warning : Codicons.terminal,
                            size: 16,
                            color: themeColors['icon.foreground'],
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: IdeResourceLabel(
                              name: shell.title,
                              actions: [
                                if (hovered && widget.onKill != null)
                                  IdeActionButton(
                                    icon: Codicons.trash,
                                    size: 20,
                                    tooltip: l10n.termKillTerminal,
                                    onPressed: () => widget.onKill!(shell),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
            _group(
              'background-tasks',
              Codicons.serverProcess,
              l10n.sidePanelBackgroundTasks,
              tasks.length,
            ),
            if (!_collapsed.contains('background-tasks'))
              if (tasks.isEmpty)
                _note(l10n.sidePanelNoTerminals)
              else
                for (final task in tasks)
                  IdeListRow(
                    key: ValueKey(('task', task.id)),
                    selected: task.id == widget.selected,
                    tooltip: task.description,
                    onTap: () => widget.onOpen(task.id),
                    onContextMenu: (position) => _menu(position, [
                      if ((widget.onStop, task.status) case (
                        final stop?,
                        CommandStatus.running,
                      ))
                        IdeMenuAction(
                          l10n.chatStop,
                          onSelected: () => stop(task),
                        ),
                    ]),
                    builder: (context, hovered) => Padding(
                      padding: const EdgeInsets.only(left: 26, right: 8),
                      child: Row(
                        children: [
                          _TaskIcon(task),
                          const SizedBox(width: 6),
                          Expanded(
                            child: IdeResourceLabel(name: task.description),
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
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
