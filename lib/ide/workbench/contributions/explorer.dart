// The explorer's commands (fileActions.contribution.ts, explorerView.ts'
// view actions) and context keys, over the window's ExplorerService: the
// tree's own for its keybindings only, as upstream's.

import 'dart:async';

import '../../explorer_history.dart';
import '../../ide_explorer.dart';
import '../../ide_workspace.dart';
import '../../services/explorer.dart';
import '../../services/layout.dart';
import '../actions.dart';
import '../context_keys.dart';
import '../contributions.dart';
import '../services.dart';
import '../views.dart';

class ExplorerContribution extends WorkbenchRegistrations {
  ExplorerContribution(WorkbenchServices services) {
    final explorer = services.get<ExplorerService>();

    /// The resource selected in the tree is not a root folder.
    bool selected(IdeExplorerState view) =>
        view.contextKey('explorerResourceIsRoot') == false;

    /// One of the tree's (see [IdeExplorerState.contextKey]), while it
    /// shows and [enabled] for it.
    WorkbenchAction command(
      String id,
      void Function(IdeExplorerState view) run, {
      bool Function(IdeExplorerState view)? enabled,
    }) => WorkbenchAction.catalog(
      id,
      palette: false,
      precondition: (_) => switch (explorer.view) {
        final view? => enabled?.call(view) ?? true,
        null => false,
      },
      run: (_, _) {
        if (explorer.view case final view?) run(view);
      },
    );

    add(
      services.get<ActionRegistry>().registerAll([
        WorkbenchAction(
          id: 'workbench.files.action.showActiveFileInExplorer',
          category: 'File',
          title: 'Reveal Active File in Explorer View',
          precondition: (services) =>
              services.find<IdeWorkspace>()?.active != null,
          run: (services, _) {
            if (services.find<IdeWorkspace>()?.active case final active?) {
              explorer.reveal(active.path);
            }
          },
        ),
        WorkbenchAction(
          id: 'workbench.files.action.refreshFilesExplorer',
          category: 'File',
          title: 'Refresh Explorer',
          run: (_, _) => unawaited(explorer.controller.refresh()),
        ),
        WorkbenchAction(
          id: 'workbench.files.action.collapseExplorerFolders',
          category: 'File',
          title: 'Collapse Folders in Explorer',
          run: (_, _) => explorer.controller.collapseAll(),
        ),
        WorkbenchAction(
          id: 'outline.focus',
          category: 'View',
          title: 'Show Outline',
          run: (_, _) => explorer.showOutline(),
        ),
        command(
          'explorer.newFile',
          (view) => unawaited(view.startCreate(directory: false)),
        ),
        command(
          'explorer.newFolder',
          (view) => unawaited(view.startCreate(directory: true)),
        ),
        command(
          'renameFile',
          (view) => view.renameSelected(),
          enabled: selected,
        ),
        command(
          'moveFileToTrash',
          (view) => unawaited(view.deleteSelected()),
          enabled: selected,
        ),
        command(
          'deleteFile',
          (view) => unawaited(view.deleteSelected(permanently: true)),
          enabled: selected,
        ),
        command(
          'filesExplorer.copy',
          (view) => view.copySelected(),
          enabled: selected,
        ),
        command(
          'filesExplorer.cut',
          (view) => view.copySelected(cut: true),
          enabled: selected,
        ),
        // What the system's clipboard holds is only known once read.
        command(
          'filesExplorer.paste',
          (view) => unawaited(view.pasteSelected()),
        ),
        command(
          explorerUndoCommandId,
          (view) => unawaited(view.undo()),
          enabled: (view) => view.canUndo,
        ),
        command(
          explorerRedoCommandId,
          (view) => unawaited(view.redo()),
          enabled: (view) => view.canRedo,
        ),
        command(
          'filesExplorer.openFilePreserveFocus',
          (view) => view.previewSelected(),
          enabled: selected,
        ),
      ]),
    );
    add(services.get<ContextKeyService>().addProvider(explorer.contextKey));
    // Shown, its tree takes the keyboard.
    add(
      services.get<LayoutService>().focusViewWith(
        IdeSideView.explorer,
        explorer.focusNode.requestFocus,
      ),
    );
  }
}
