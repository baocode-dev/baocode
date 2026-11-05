// Source Control's commands, the commit input's keys, and the status bar's
// branch (upstream's git extension: `git.*` commands, scm.contribution.ts's
// input commands, `CheckoutStatusBar`), over the window's ScmService.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../keybindings/keybinding_service.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/codicons.dart';
import '../../host_paths.dart';
import '../../ide_status_bar.dart';
import '../../ide_workspace.dart';
import '../../services/scm_service.dart';
import '../actions.dart';
import '../context_keys.dart';
import '../contributions.dart';
import '../services.dart';
import '../statusbar.dart';
import '../views.dart';

/// The status bar's branch: right of the remote and the debugger's
/// entries, left of the problems'.
const scmBranchPriority = 80.0;

class ScmContribution extends WorkbenchRegistrations {
  ScmContribution(WorkbenchServices services) {
    final scm = services.get<ScmService>();
    final host = services.get<WorkbenchHost>();
    IdeWorkspace? workspace() => services.find<IdeWorkspace>();
    bool hasRepository(WorkbenchServices _) => workspace()?.git?.state != null;
    add(
      services.get<ActionRegistry>().registerAll([
        WorkbenchAction(
          id: 'baocode.git.branches',
          category: 'Git',
          title: 'Branches…',
          precondition: hasRepository,
          run: (_, _) => scm.showBranchPopup(),
        ),
        WorkbenchAction(
          id: 'baocode.git.pushDialog',
          category: 'Git',
          title: 'Push…',
          precondition: (_) => workspace()?.git?.state?.head.branch != null,
          run: (_, _) => scm.pushDialog(),
        ),
        WorkbenchAction(
          id: 'baocode.git.updateProject',
          category: 'Git',
          title: 'Update Project…',
          precondition: hasRepository,
          run: (_, _) => scm.updateProject(),
        ),
        WorkbenchAction(
          id: 'baocode.git.manageRemotes',
          category: 'Git',
          title: 'Manage Remotes…',
          precondition: hasRepository,
          run: (_, _) => scm.manageRemotes(),
        ),
        WorkbenchAction(
          id: 'baocode.localHistory.show',
          category: 'Local History',
          title: 'Show History',
          precondition: (_) =>
              workspace()?.localHistory != null &&
              (workspace()?.active?.isFile ?? false),
          run: (_, _) {
            if (workspace()?.active case final doc? when doc.isFile) {
              unawaited(scm.showLocalHistory(doc.path));
            }
          },
        ),
        // Git: Commit, Git: Checkout to…, Git: Fetch, Git: Pull, Git: Push
        // and Focus on Changes View, for the palette.
        WorkbenchAction.catalog(
          'git.commit',
          precondition: hasRepository,
          run: (_, _) => scm.onScmView((view) {
            scm.logKey.currentState?.showLocalChanges();
            unawaited(view.commit());
          }),
        ),
        WorkbenchAction.catalog(
          'git.checkout',
          precondition: hasRepository,
          run: (_, _) => scm.checkout(),
        ),
        WorkbenchAction.catalog(
          'git.fetch',
          precondition: hasRepository,
          run: (_, _) => scm.onScmView((view) => unawaited(view.fetch())),
        ),
        WorkbenchAction.catalog(
          'git.fetchAll',
          precondition: (_) => workspace()?.repositories.isNotEmpty ?? false,
          run: (_, _) => scm.onScmView((view) => unawaited(view.fetchAll())),
        ),
        WorkbenchAction.catalog(
          'git.pull',
          precondition: hasRepository,
          run: (_, _) => scm.onScmView((view) => unawaited(view.pull())),
        ),
        WorkbenchAction.catalog(
          'git.push',
          precondition: hasRepository,
          run: (_, _) => scm.onScmView((view) => unawaited(view.push())),
        ),
        WorkbenchAction.catalog(
          'workbench.scm.focus',
          run: (_, _) => scm.onScmView((view) {
            scm.logKey.currentState?.showLocalChanges();
            view.focus();
          }),
        ),
        // The commit input's commands (scm.contribution.ts), for
        // keybindings.
        WorkbenchAction.catalog(
          'scm.acceptInput',
          palette: false,
          precondition: (_) =>
              scm.panelKey.currentState?.inputHasFocus ?? false,
          run: (_, _) => unawaited(scm.panelKey.currentState?.commit()),
        ),
        WorkbenchAction.catalog(
          'scm.clearValidation',
          palette: false,
          precondition: (_) {
            final view = scm.panelKey.currentState;
            return view != null && view.inputHasFocus && view.hasValidation;
          },
          run: (_, _) => scm.panelKey.currentState?.clearValidation(),
        ),
        // Upstream: not while its text has a selection.
        WorkbenchAction.catalog(
          'scm.clearInput',
          palette: false,
          precondition: (_) {
            final view = scm.panelKey.currentState;
            return view != null &&
                view.inputHasFocus &&
                !view.inputHasSelection;
          },
          run: (_, _) => scm.panelKey.currentState?.clearInput(),
        ),
      ]),
    );
    // The commit input's context keys (scmInput.ts).
    add(
      services.get<ContextKeyService>().addProvider((key) {
        final view = scm.panelKey.currentState;
        return switch (key) {
          'scmRepository' => view?.inputHasFocus ?? false,
          'scmInputHasValidationMessage' => view?.hasValidation ?? false,
          _ => null,
        };
      }),
    );
    // Upstream's `CheckoutStatusBar`: Checkout to…, its tooltip the
    // repository's (`<folder> (Git) - `) before the command's. An item
    // doing what a command does has its keybinding in its tooltip (a
    // deviation: upstream's status bar items have their tooltips alone).
    final entry = services.get<StatusbarService>().addEntry(
      'status.scm',
      StatusbarAlignment.left,
      priority: scmBranchPriority,
      changes: Listenable.merge([scm, KeybindingService.instance]),
      (context) {
        final branch = scm.branch;
        if (branch == null) return null;
        final l10n = context.l10n;
        final keys = KeybindingService.instance;
        if (scm.git?.state case final state?) {
          return IdeStatusBarItem(
            branch,
            icon: Codicons.gitBranch,
            tooltip: keys.titleWithKeybinding(
              '${hostBasename(state.root)} (Git) - $branch, '
                  '${l10n.gitBranchesTitle}',
              'baocode.git.branches',
            ),
            onTapRect: scm.showBranchPopup,
          );
        }
        return IdeStatusBarItem(
          branch,
          icon: Codicons.gitBranch,
          tooltip: keys.titleWithKeybinding(
            l10n.scmTitle,
            'workbench.view.scm',
          ),
          onTap: () => host.showView(IdeSideView.sourceControl),
        );
      },
    );
    add(entry.dispose);
  }
}
