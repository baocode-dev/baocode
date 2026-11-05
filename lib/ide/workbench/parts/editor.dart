// The editor part (upstream editorPart.ts): the tabs, the breadcrumbs
// and the editor in front, a pane of the registry's (see
// EditorPaneRegistry) or the text editor; the start page or the welcome
// with none. Built again as the workspace's editors and the services that
// decorate them change.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

import '../../../debug/ui/debug_toolbar.dart';
import '../../../keybindings/keybinding_service.dart';
import '../../../theme/workbench_theme.dart';
import '../../../workspace/islands.dart';
import '../../file_service.dart';
import '../../ide_agent_edits.dart';
import '../../ide_breadcrumbs.dart';
import '../../ide_commands.dart';
import '../../ide_editor.dart';
import '../../ide_tab_bar.dart';
import '../../ide_welcome.dart';
import '../../services/commands.dart';
import '../../services/configuration.dart';
import '../../services/debug_view.dart';
import '../../services/editors.dart';
import '../../services/explorer.dart';
import '../../services/extensions_view.dart';
import '../../services/keybindings.dart';
import '../../services/language.dart';
import '../../services/markdown_preview.dart';
import '../../services/quick_input.dart';
import '../../services/references.dart';
import '../../services/scm_service.dart';
import '../contributions.dart';
import '../editor_panes.dart';
import '../options.dart';
import '../services.dart';
import '../style.dart';
import 'extensions.dart';

class EditorPart extends StatelessWidget {
  const EditorPart({super.key, required this.options});

  final WorkbenchOptions options;

  @override
  Widget build(BuildContext context) {
    final services = WorkbenchScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        options.workspace,
        services.get<EditorService>(),
        services.get<ExtensionsViewService>(),
        services.get<MarkdownPreviewService>(),
        services.get<DebugViewService>(),
        services.get<ConfigurationService>(),
        KeybindingService.instance,
      ]),
      builder: (context, _) => _area(context, services),
    );
  }

  Widget _area(BuildContext context, WorkbenchServices services) {
    final workspace = options.workspace;
    final host = services.get<WorkbenchHost>();
    final editors = services.get<EditorService>();
    final extensions = services.get<ExtensionsViewService>();
    final markdown = services.get<MarkdownPreviewService>();
    final config = services.get<ConfigurationService>();
    final scm = services.get<ScmService>();
    final language = services.get<LanguageService>();
    final active = workspace.active;
    final page = extensions.page;
    final pageShown = extensions.pageShown;
    final debug = services.get<DebugViewService>().service;
    final local = workspace.files is! IdeHostFiles;
    // The start page's and the welcome's commands, as the palette has them.
    final commands = active == null
        ? services.get<CommandService>().palette()
        : const <IdeCommand>[];
    final dockedToolbar =
        debug != null && debug.settings().toolBarLocation == 'docked';
    // Its tabs on the window's color over its card; their row there with
    // none, the card's top where the side bar's and the chat's are.
    final tabs = workspace.documents.isNotEmpty || page != null;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: WorkbenchStyle.gap / 2),
      child: HeadedIsland(
        header: IdeTabStrip.height,
        color: themeColors['editor.background'],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!tabs) ...[
              // Not islands, no row: nothing over the editor's part.
              if (WorkbenchStyle.islands)
                const SizedBox(height: IdeTabStrip.height),
              if (dockedToolbar) DebugToolbar(service: debug),
            ],
            if (tabs) ...[
              IdeTabBar(
                documents: workspace.documents,
                active: pageShown ? null : active,
                root: workspace.root,
                onSelect: (doc) => unawaited(editors.select(doc)),
                onClose: (doc) => unawaited(editors.close(doc)),
                onAction: editors.tabAction,
                onMove: workspace.moveDocument,
                local: local,
                markdownPreview:
                    !pageShown && active != null && markdown.hasPreview(active)
                    ? markdown.previewing(active)
                    : null,
                onMarkdownPreview: (preview) =>
                    unawaited(markdown.setPreview(preview)),
                page: page == null
                    ? null
                    : ExtensionPageTab(service: extensions),
                actions: switch (options.agentEdits) {
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
                  listenable: Listenable.merge([editors.caret, language]),
                  builder: (context, _) => IdeBreadcrumbs(
                    root: workspace.root,
                    path: active.path,
                    onReveal: services.get<ExplorerService>().reveal,
                    symbols: language.symbolPath,
                    onSymbol: language.revealSymbol,
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
                    child: markdown.drops(
                      active,
                      active == null && !workspace.hasFolder
                          ? IdeStartPage(
                              actions: [
                                for (final id in const [
                                  'workbench.action.files.openFolder',
                                  'git.clone',
                                  'baocode.remote.openFolder',
                                  WorkbenchOptions.createWorkspaceCommandId,
                                  'workbench.action.files.openFile',
                                  'workbench.action.files.newUntitledFile',
                                ])
                                  ...commands.where(
                                    (command) => command.id == id,
                                  ),
                              ],
                              recent: options.recentFolders,
                              onOpenRecent: options.onOpenRecent,
                              workspaceOf: options.recentWorkspaceOf,
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
                          : services
                                    .get<EditorPaneRegistry>()
                                    .paneFor(active)
                                    ?.build(context, active) ??
                                options.editorBuilder?.call(
                                  context,
                                  workspace,
                                ) ??
                                IdeEditor(
                                  nativeEditorEnabled:
                                      options.nativeEditorEnabled,
                                  key: editors.editorKey,
                                  workspace: workspace,
                                  active: active,
                                  onError: host.report,
                                  onLspStatus: (_) {},
                                  onPositionChanged: editors.positionChanged,
                                  onScrolled: editors.viewChanged,
                                  // Go to Definition's target (F12),
                                  // centered even when already in view.
                                  onOpenLocation: (location) => editors
                                      .openLocation(location, center: true),
                                  onShowReferences: services
                                      .get<ReferencesService>()
                                      .show,
                                  onShowCommands: () => services
                                      .get<QuickInputService>()
                                      .show('>'),
                                  gitBlame: config.gitBlame,
                                  onShowCommit: scm.showCommitInLog,
                                  onShowHistory: scm.showHistory,
                                  onCompare: (path, what) =>
                                      unawaited(scm.compareWith(path, what)),
                                  keyResolver: services
                                      .get<KeybindingDispatchService>()
                                      .resolveEditorKey,
                                  onPaste: markdown.pasteInEditor,
                                  formatOnSave: config.formatOnSave,
                                  debug: debug,
                                  agentEdits: options.agentEdits,
                                ),
                    ),
                  ),
                  // And it under them, while another tab is in front.
                  if (page != null)
                    Offstage(
                      offstage: !pageShown,
                      child: ExtensionPageView(service: extensions),
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
