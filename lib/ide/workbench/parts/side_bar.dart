// The side bar (upstream sidebarPart.ts): the view the activity bar
// picked, built again as the layout, Source Control and the debugger
// change; the Git log has the side bar's and the editor's place.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../debug/ui/debug_view.dart';
import '../../../keybindings/keybinding_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/workbench_theme.dart';
import '../../../workspace/islands.dart';
import '../../../workspace/window_controls.dart';
import '../../git/ide_git_commit_panel.dart';
import '../../git/ide_git_log_view.dart';
import '../../ide_modern_ui.dart';
import '../../search/ide_search_view.dart';
import '../../services/chat.dart';
import '../../services/debug_view.dart';
import '../../services/editors.dart';
import '../../services/explorer.dart';
import '../../services/extensions_view.dart';
import '../../services/language.dart';
import '../../services/layout.dart';
import '../../services/scm_service.dart';
import '../../services/search_view.dart';
import '../contributions.dart';
import '../options.dart';
import '../services.dart';
import '../style.dart';
import '../views.dart';
import 'explorer_view.dart';
import 'extensions.dart';

class SideBarPart extends StatelessWidget {
  const SideBarPart({super.key, required this.options, this.border = true});

  final WorkbenchOptions options;

  /// Its line at its right (not islands); none where it has the editor's
  /// place.
  final bool border;

  /// The side bar: its view on a card, its title in it; the Git log,
  /// cards of its own, untitled. Not islands, a part of the side bar's
  /// color, its line at its right but where it has the editor's place
  /// ([border]).
  @override
  Widget build(BuildContext context) {
    final services = WorkbenchScope.of(context);
    final layout = services.get<LayoutService>();
    final scm = services.get<ScmService>();
    final debugView = services.get<DebugViewService>();
    return ListenableBuilder(
      listenable: Listenable.merge([
        layout,
        scm,
        debugView,
        // Labels (the tooltips', the menus') follow the keybindings.
        KeybindingService.instance,
      ]),
      builder: (context, _) => _part(context, services, layout),
    );
  }

  Widget _part(
    BuildContext context,
    WorkbenchServices services,
    LayoutService layout,
  ) {
    final view = Focus(
      focusNode: layout.sidebarFocus,
      child: _view(context, services, layout),
    );
    if (!WorkbenchStyle.islands) {
      return IdePart(
        color: themeColors['sideBar.background'],
        border: border ? Border(right: line) : null,
        child: view,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Islands.gap / 2),
      child: layout.view == IdeSideView.sourceControl
          ? view
          : HeadedIsland(header: 0, color: AppColors.code, child: view),
    );
  }

  /// Not islands, between the side bars and the editor: `sideBar.border`,
  /// else the Modern UI's `surface.border`, so every theme has the line.
  static BorderSide get line =>
      IdePart.side('sideBar.border', fallback: 'surface.border');

  Widget _view(
    BuildContext context,
    WorkbenchServices services,
    LayoutService layout,
  ) {
    final workspace = options.workspace;
    final host = services.get<WorkbenchHost>();
    final editors = services.get<EditorService>();
    final scm = services.get<ScmService>();
    final chat = services.get<ChatService>();
    final search = services.get<SearchViewService>();
    final debugView = services.get<DebugViewService>();
    return switch (layout.view) {
      IdeSideView.explorer => ExplorerViewPart(options: options),
      IdeSideView.search => IdeSearchView(
        key: search.viewKey,
        session: search.session,
        root: workspace.root,
        // The workspace's own: replacing writes into its documents.
        replaceBackend: workspace,
        onOpen: (path, range, {required focusEditor}) => editors.open(
          path,
          range: range,
          select: true,
          focusEditor: focusEditor,
        ),
        onError: host.report,
      ),
      // The Git log, in the side bar's and the editor's place (see
      // [_split]): the local changes' commit box and groups its first row's
      // details, their changes in its table's place.
      IdeSideView.sourceControl => IdeGitLogView(
        key: scm.logKey,
        host: workspace,
        session: scm.session,
        notifications: workspace.notifications,
        islands: WorkbenchStyle.islands,
        ai: options.commitMessage,
        onAsk: chat.canAsk ? chat.ask : null,
        onFixup: (git, commit) async =>
            scm.panelKey.currentState?.fixupInto(git, commit),
        onOpen: (path) {
          scm.leaveGitLog();
          unawaited(editors.open(path, focusEditor: true));
        },
        onAddToChat: options.onAddToChat,
        // Another worktree's changes and branch in Source Control.
        worktrees: IdeGitWorktreeChoice(
          following: false,
          onSelect: workspace.openWorktree == null
              ? null
              : (path) {
                  if (path != null) workspace.showWorktree(path);
                },
        ),
        changes: IdeGitCommitPanel(
          onAsk: chat.canAsk ? chat.ask : null,
          key: scm.panelKey,
          host: workspace,
          session: scm.session,
          sessionOf: scm.sessionOf,
          notifications: workspace.notifications,
          onOpen: (path, {focusEditor = false}) {
            scm.leaveGitLog();
            return editors.open(path, focusEditor: focusEditor);
          },
          onOpenChange: scm.openChangeInLog,
          onRevealInExplorer: (path) {
            scm.leaveGitLog();
            services.get<ExplorerService>().reveal(path);
          },
          onAddToChat: options.onAddToChat,
          trash: WindowControls.canMoveToTrash
              ? WindowControls.moveToTrash
              : null,
          commitMessage: options.commitMessage,
          hunks: scm.hunks,
          changelists: scm.changelists,
          onShowDiff: (files, index) => scm.session.log.showDiff(files, index),
          onOpenAt: (path, line) {
            scm.leaveGitLog();
            return editors.open(
              path,
              line: line,
              center: true,
              focusEditor: true,
            );
          },
        ),
      ),
      IdeSideView.debug => switch (debugView.service) {
        final debug? => DebugView(
          service: debug,
          runAndDebugKey: debugView.runAndDebugKey,
        ),
        null => const SizedBox.shrink(),
      },
      IdeSideView.extensions => ExtensionsViewPart(
        service: services.get<ExtensionsViewService>(),
        language: services.get<LanguageService>(),
        islands: WorkbenchStyle.islands,
      ),
    };
  }
}
