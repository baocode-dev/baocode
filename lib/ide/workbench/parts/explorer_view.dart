// The Explorer view (upstream `ExplorerViewPaneContainer`): the folder's
// tree, the active editor's outline and its file's timeline, as panes;
// built again as the ExplorerService, the workspace and the symbols
// change.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../keybindings/keybinding_service.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/codicons.dart';
import '../../../theme/workbench_theme.dart';
import '../../../workspace/islands.dart';
import '../../../workspace/window_controls.dart';
import '../../file_service.dart';
import '../../git/ide_timeline_view.dart';
import '../../host_paths.dart';
import '../../ide_button.dart';
import '../../ide_explorer.dart';
import '../../ide_panes.dart';
import '../../lsp_ui/document_symbols.dart';
import '../../services/editors.dart';
import '../../services/explorer.dart';
import '../../services/keybindings.dart';
import '../../services/language.dart';
import '../../services/scm_service.dart';
import '../../services/search_view.dart';
import '../../services/terminal_view.dart';
import '../contributions.dart';
import '../environment.dart';
import '../options.dart';
import '../services.dart';

class ExplorerViewPart extends StatelessWidget {
  const ExplorerViewPart({super.key, required this.options});

  final WorkbenchOptions options;

  @override
  Widget build(BuildContext context) {
    final services = WorkbenchScope.of(context);
    final explorer = services.get<ExplorerService>();
    final language = services.get<LanguageService>();
    final workspace = options.workspace;
    return ListenableBuilder(
      listenable: Listenable.merge([
        explorer,
        workspace,
        language,
        // Labels (the tooltips', the menus') follow the keybindings.
        KeybindingService.instance,
      ]),
      builder: (context, _) => _view(context, services, explorer, language),
    );
  }

  Widget _view(
    BuildContext context,
    WorkbenchServices services,
    ExplorerService explorer,
    LanguageService language,
  ) {
    final workspace = options.workspace;
    final host = services.get<WorkbenchHost>();
    final environment = services.get<WorkbenchEnvironment>();
    final scm = services.get<ScmService>();
    final terminalView = services.get<TerminalViewService>();
    final caret = services.get<EditorService>().caret;
    final local = workspace.files is! IdeHostFiles;
    final activePath = workspace.active?.path;
    final timelinePath = IdeTimelineView.pathOf(explorer.timeline, activePath);
    // The folder's actions are the explorer's commands: their keybindings
    // in their tooltips (upstream's `MenuEntryActionViewItem.getTooltip`).
    final keys = KeybindingService.instance;
    // Over a card (the side bar's, under this, its title in it too): its
    // color under the panes.
    return Builder(
      builder: (context) => ColoredBox(
        color: IslandSurface.colorOf(context) == null
            ? AppColors.background
            : const Color(0x00000000),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IdeViewTitle(context.l10n.wbExplorer),
            Expanded(
              child: IdePaneContainer(
                expanded: explorer.panes,
                onToggle: explorer.togglePane,
                panes: [
                  if (!workspace.hasFolder)
                    IdePane(
                      id: 'folder',
                      title: context.l10n.explorerNoFolderTitle,
                      weight: 3,
                      body: _NoFolder(
                        onOpenFolder: environment
                            .hostCommand('workbench.action.files.openFolder')
                            ?.run,
                      ),
                    )
                  else
                    IdePane(
                      id: 'folder',
                      title: workspace.isMultiRoot
                          ? context.l10n.ideWorkspaceTitle(options.project.name)
                          : options.project.name,
                      weight: 3,
                      actions: [
                        if (options.onAddFolder case final add?
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
                            explorer.view?.startCreate(directory: false),
                          ),
                        ),
                        IdePaneAction(
                          icon: Codicons.newFolder,
                          tooltip: keys.titleWithKeybinding(
                            context.l10n.explorerNewFolder,
                            'explorer.newFolder',
                          ),
                          onPressed: () => unawaited(
                            explorer.view?.startCreate(directory: true),
                          ),
                        ),
                        IdePaneAction(
                          icon: Codicons.refresh,
                          tooltip: keys.titleWithKeybinding(
                            context.l10n.cmdRefreshExplorer,
                            'workbench.files.action.refreshFilesExplorer',
                          ),
                          onPressed: () =>
                              unawaited(explorer.controller.refresh()),
                        ),
                        IdePaneAction(
                          icon: Codicons.collapseAll,
                          tooltip: keys.titleWithKeybinding(
                            context.l10n.cmdCollapseExplorerFolders,
                            'workbench.files.action.collapseExplorerFolders',
                          ),
                          onPressed: explorer.controller.collapseAll,
                        ),
                      ],
                      body: workspace.isMultiRoot && workspace.roots.isEmpty
                          ? _EmptyWorkspace(onAddFolder: options.onAddFolder)
                          : IdeExplorer(
                              key: explorer.tree,
                              controller: explorer.controller,
                              focusNode: explorer.focusNode,
                              isBound: (event) =>
                                  services
                                      .get<KeybindingDispatchService>()
                                      .resolveEditorKey(event) !=
                                  null,
                              git: workspace.git,
                              repositories: [
                                for (final (_, git) in workspace.repositories)
                                  git,
                              ],
                              onAddFolder: workspace.isMultiRoot
                                  ? options.onAddFolder
                                  : null,
                              onRemoveFolder: workspace.isMultiRoot
                                  ? options.onRemoveFolder
                                  : null,
                              onOpen: (path, focusEditor) => unawaited(
                                services.get<EditorService>().open(
                                  path,
                                  focusEditor: focusEditor,
                                ),
                              ),
                              onMoved: workspace.moved,
                              onDeleted: workspace.deleted,
                              unsavedIn: (path) => workspace
                                  .documentsIn(path)
                                  .where((d) => d.dirty)
                                  .length,
                              local: local,
                              trash: local && WindowControls.canMoveToTrash
                                  ? WindowControls.moveToTrash
                                  : null,
                              onError: host.report,
                              onOpenInDefaultApp:
                                  local && WindowControls.canOpenInDefaultApp
                                  ? (path) =>
                                        unawaited(host.openInDefaultApp(path))
                                  : null,
                              onFindInFolder: services
                                  .get<SearchViewService>()
                                  .findInFolder,
                              onOpenInTerminal: terminalView.terminals == null
                                  ? null
                                  : terminalView.openIn,
                              onShowHistory: scm.showHistory,
                              onShowLocalHistory: (path) =>
                                  unawaited(scm.showLocalHistory(path)),
                              onCompareFiles:
                                  (original, modified, {folders = false}) =>
                                      unawaited(
                                        scm.compareFiles(
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
                      listenable: caret,
                      builder: (context, _) => IdeOutlineView(
                        symbols: language.symbols,
                        caret: workspace.active == null ? null : language.caret,
                        onReveal: language.revealSymbol,
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
                        icon: explorer.timeline.pinned == null
                            ? Codicons.pin
                            : Codicons.pinned,
                        tooltip: explorer.timeline.pinned == null
                            ? context.l10n.wbPinTimeline
                            : context.l10n.wbUnpinTimeline,
                        onPressed: () => explorer.toggleTimelinePin(activePath),
                      ),
                      IdePaneAction(
                        icon: Codicons.refresh,
                        tooltip: context.l10n.commonRefresh,
                        onPressed: explorer.timeline.refresh,
                      ),
                    ],
                    body: IdeTimelineView(
                      controller: explorer.timeline,
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
