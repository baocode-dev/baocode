// Go Back / Go Forward and the other history commands (upstream
// history.contribution and editor's navigation actions), over the
// workspace's NavigationHistoryService.

import 'dart:async';

import '../../ide_workspace.dart';
import '../../services/navigation_history.dart';
import '../actions.dart';
import '../context_keys.dart';
import '../contributions.dart';
import '../services.dart';

class NavigationContribution extends WorkbenchRegistrations {
  NavigationContribution(WorkbenchServices services) {
    NavigationHistoryService? history() =>
        services.find<NavigationHistoryService>();
    bool hasEditors(WorkbenchServices s) =>
        s.find<IdeWorkspace>()?.documents.isNotEmpty ?? false;
    add(
      services.get<ActionRegistry>().registerAll([
        WorkbenchAction(
          id: 'workbench.action.navigateBack',
          category: 'Go',
          title: 'Go Back',
          precondition: (_) => history()?.canGoBack ?? false,
          run: (_, _) => history()?.navigate(back: true),
        ),
        WorkbenchAction(
          id: 'workbench.action.navigateForward',
          category: 'Go',
          title: 'Go Forward',
          precondition: (_) => history()?.canGoForward ?? false,
          run: (_, _) => history()?.navigate(back: false),
        ),
        WorkbenchAction(
          id: 'workbench.action.reopenClosedEditor',
          category: 'View',
          title: 'Reopen Closed Editor',
          precondition: (_) => history()?.canReopenClosed ?? false,
          run: (s, _) {
            final path = history()?.takeClosed();
            if (path == null) return;
            unawaited(s.get<WorkbenchHost>().openFile(path, focusEditor: true));
          },
        ),
        WorkbenchAction.catalog(
          'workbench.action.navigateToLastEditLocation',
          precondition: (_) => history()?.lastEdit != null,
          run: (_, _) => history()?.goToLastEdit(),
        ),
        WorkbenchAction.catalog(
          'workbench.action.navigateLast',
          precondition: (_) {
            final h = history();
            return h != null && (h.canGoBack || h.canGoForward);
          },
          run: (_, _) => history()?.goPrevious(),
        ),
        for (final (id, next) in [
          ('workbench.action.openNextRecentlyUsedEditor', true),
          ('workbench.action.openPreviousRecentlyUsedEditor', false),
          ('workbench.action.openNextRecentlyUsedEditorInGroup', true),
          ('workbench.action.openPreviousRecentlyUsedEditorInGroup', false),
        ])
          WorkbenchAction.catalog(
            id,
            precondition: hasEditors,
            run: (_, _) => history()?.openRecentlyUsed(next: next),
          ),
      ]),
    );
    add(
      services.get<ContextKeyService>().addProvider(
        (key) => switch (key) {
          'canNavigateBack' => history()?.canGoBack ?? false,
          'canNavigateForward' => history()?.canGoForward ?? false,
          _ => null,
        },
      ),
    );
  }
}
