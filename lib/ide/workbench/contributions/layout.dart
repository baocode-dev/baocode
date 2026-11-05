// The layout's commands (layoutActions.ts, panelActions.ts, the view
// containers' Show commands) and context keys, over the window's
// LayoutService; Focus Active Editor Group over its EditorService.

import '../../ide_workspace.dart';
import '../../services/editors.dart';
import '../../services/layout.dart';
import '../actions.dart';
import '../context_keys.dart';
import '../contributions.dart';
import '../services.dart';
import '../views.dart';

class LayoutContribution extends WorkbenchRegistrations {
  LayoutContribution(WorkbenchServices services) {
    final layout = services.get<LayoutService>();
    bool editing(WorkbenchServices services) =>
        services.find<IdeWorkspace>()?.active != null;

    WorkbenchAction show(String id, String title, IdeSideView view) =>
        WorkbenchAction(
          id: id,
          category: 'View',
          title: title,
          run: (_, _) => layout.showView(view),
        );

    add(
      services.get<ActionRegistry>().registerAll([
        WorkbenchAction(
          id: 'workbench.action.toggleSidebarVisibility',
          category: 'View',
          title: 'Toggle Primary Side Bar Visibility',
          run: (_, _) => layout.toggleSidebar(),
        ),
        WorkbenchAction(
          id: 'workbench.action.toggleAuxiliaryBar',
          category: 'View',
          title: 'Toggle Chat',
          run: (_, _) => layout.toggleChat(),
        ),
        // VS Code's ⌘J toggles the panel; here it is the chat's.
        WorkbenchAction(
          id: 'workbench.action.togglePanel',
          category: 'View',
          title: 'Toggle Panel Visibility',
          run: (_, _) => layout.togglePanel(),
        ),
        show('workbench.view.explorer', 'Show Explorer', IdeSideView.explorer),
        show('workbench.view.search', 'Show Search', IdeSideView.search),
        show(
          'workbench.view.scm',
          'Show Source Control',
          IdeSideView.sourceControl,
        ),
        show(
          'workbench.view.extensions',
          'Show Extensions',
          IdeSideView.extensions,
        ),
        WorkbenchAction.catalog(
          'workbench.action.toggleMaximizedPanel',
          run: (_, _) => layout.toggleMaximizedPanel(),
        ),
        WorkbenchAction.catalog(
          'workbench.action.focusPanel',
          run: (_, _) => layout.focusPanel(),
        ),
        WorkbenchAction.catalog(
          'workbench.action.closePanel',
          precondition: (_) => layout.panel != null,
          run: (_, _) => layout.panel = null,
        ),
        WorkbenchAction.catalog(
          'workbench.action.focusSideBar',
          run: (_, _) => layout.focusSideBar(),
        ),
        WorkbenchAction.catalog(
          'workbench.action.closeSidebar',
          precondition: (_) => layout.layout.sidebarVisible,
          run: (_, _) => layout.layout.sidebar = false,
        ),
        WorkbenchAction.catalog(
          'workbench.action.closeAuxiliaryBar',
          precondition: (_) => layout.chatShown,
          run: (_, _) => layout.layout.chat = false,
        ),
        for (final id in const [
          'workbench.action.focusActiveEditorGroup',
          'workbench.action.focusFirstEditorGroup',
          'workbench.action.focusLastEditorGroup',
        ])
          WorkbenchAction.catalog(
            id,
            precondition: editing,
            run: (services, _) =>
                services.get<EditorService>().focusEditorOrWorkbench(),
          ),
      ]),
    );
    add(
      services.get<ContextKeyService>().addProvider(
        (key) => switch (key) {
          'editorIsOpen' =>
            services.find<IdeWorkspace>()?.documents.isNotEmpty ?? false,
          _ => layout.contextKey(key),
        },
      ),
    );
  }
}
