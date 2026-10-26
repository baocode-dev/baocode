// A branch's actions, as JetBrains IDEs' branch popup has them: checkout,
// a branch from it, checkout and rebase onto the current one, compare with
// the current one or the working tree, rebase the current one onto it,
// merge it into the current one, pull it, update, push, its upstream,
// rename, favorite, delete (Restore after). The log's branch tree and the
// branch popup show them.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../file_service.dart';
import '../ide_dialog.dart';
import '../ide_menu.dart';
import '../ide_notifications.dart';
import 'git_branch_tree.dart';
import 'git_checkout.dart' show ideSanitizeBranchName;
import 'git_model.dart';
import 'ide_git_remotes_dialog.dart';
import 'git_repository.dart';
import 'ide_git_branch_popup.dart' show IdeGitBranchPopupAction;
import 'ide_git_push_dialog.dart';
import 'ide_scm_view.dart' show IdeScmSession;
import 'ide_git_log_view.dart'
    show IdeGitDiffFile, ideGitRevisionsDiff, ideGitWorkingTreeDiff;

/// Where the branch actions show what they make: the log, or the window
/// (which shows the log first).
abstract interface class IdeGitBranchHost {
  IdeNotifications get notifications;

  /// The project's files, for the working tree's side of a comparison.
  IdeFileService get files;

  IdeGitFavoriteBranches get favoriteBranches;

  /// Where Update Project's way is kept.
  IdeScmSession get session;

  /// The repositories Update Project updates: the window's all.
  List<IdeGitRepository> get repositories;

  /// Runs an operation, its failure told.
  Future<void> run(Future<void> Function() operation);

  /// Shows a comparison's files, as the log shows a commit's.
  void showDiff(List<IdeGitDiffFile> files);

  /// Shows the log of [graphBranch] alone ([IdeGitRepository.graphBranch]):
  /// a ref's, or a range's.
  void showOnly(IdeGitRepository git, String graphBranch);
}

/// [git]'s branch actions, from [context] (its dialogs').
class IdeGitBranchActions {
  IdeGitBranchActions(this.context, this.git, this.host);

  final BuildContext context;
  final IdeGitRepository git;
  final IdeGitBranchHost host;

  /// [ref]'s actions; [refs], all of them, for its upstream's choice;
  /// [showOnly], whether the log shows [ref] alone.
  List<IdeMenuEntry> menu(
    IdeGitRef ref,
    List<IdeGitRef> refs, {
    bool showOnly = false,
  }) {
    final l10n = context.l10n;
    final current = git.state?.head.branch;
    final here = current ?? 'HEAD';
    final local = ref.kind == IdeGitRefKind.branch;
    final remote = ref.kind == IdeGitRefKind.remote;
    final tag = ref.kind == IdeGitRefKind.tag;
    final isCurrent = local && ref.name == current;
    void run(Future<void> Function() operation) =>
        unawaited(host.run(operation));
    final upstreams = [
      for (final other in refs)
        if (other.kind == IdeGitRefKind.remote && !other.name.endsWith('/HEAD'))
          other,
    ];
    // The remotes a tag can go to, or be deleted on.
    final remotes = {
      for (final other in upstreams)
        other.remote ?? other.name.split('/').first,
    }.toList()..sort();
    IdeMenuAction onRemotes(
      String Function(String remote) label,
      Future<void> Function(String remote) operation,
    ) => remotes.length == 1
        ? IdeMenuAction(
            label(remotes.single),
            onSelected: () => run(() => operation(remotes.single)),
          )
        : IdeMenuAction(
            label('…'),
            submenu: [
              for (final remote in remotes)
                IdeMenuAction(
                  remote,
                  onSelected: () => run(() => operation(remote)),
                ),
            ],
          );
    return ideMenuGroups([
      [
        if (!isCurrent)
          IdeMenuAction(
            l10n.gitBranchCheckout,
            onSelected: () => run(() => _checkoutRef(ref, refs)),
          ),
        IdeMenuAction(
          l10n.gitBranchNewFrom(ref.name),
          onSelected: () => unawaited(_newBranchFrom(ref)),
        ),
        if (local && !isCurrent && current != null)
          IdeMenuAction(
            l10n.gitBranchCheckoutRebase(here),
            onSelected: () =>
                run(() => git.rebaseOnto(current, branch: ref.name)),
          ),
      ],
      [
        if (!isCurrent)
          IdeMenuAction(
            l10n.gitBranchCompare(here),
            onSelected: () => unawaited(_compareWithHead(ref)),
          ),
        IdeMenuAction(
          l10n.gitBranchDiffWorkingTree,
          onSelected: () => unawaited(_compareWithWorkingTree(ref)),
        ),
      ],
      [
        if (!isCurrent && current != null) ...[
          IdeMenuAction(
            l10n.gitBranchRebaseOnto(here, ref.name),
            onSelected: () => run(() => git.rebaseOnto(ref.name)),
          ),
          IdeMenuAction(
            l10n.gitBranchMerge(ref.name, here),
            onSelected: () => run(() => git.merge(ref.name)),
          ),
        ],
        if (remote && current != null) ...[
          IdeMenuAction(
            l10n.gitBranchPullRebase(here),
            onSelected: () => run(() => git.pullInto(ref.name, rebase: true)),
          ),
          IdeMenuAction(
            l10n.gitBranchPullMerge(here),
            onSelected: () => run(() => git.pullInto(ref.name, rebase: false)),
          ),
        ],
      ],
      [
        if (local && ref.upstream != null)
          IdeMenuAction(
            l10n.gitBranchUpdate,
            onSelected: () => run(
              isCurrent
                  ? git.pull
                  : () => git.updateBranch(ref.name, ref.upstream!),
            ),
          ),
        if (local)
          IdeMenuAction(
            ref.upstream == null
                ? l10n.gitBranchPush
                : l10n.gitBranchPushTo(ref.upstream!),
            onSelected: () =>
                run(() => git.pushBranch(ref.name, upstream: ref.upstream)),
          ),
        if (local && upstreams.isNotEmpty)
          IdeMenuAction(
            l10n.gitBranchUpstream,
            submenu: [
              for (final upstream in upstreams.take(30))
                IdeMenuAction(
                  upstream.name,
                  checked: upstream.name == ref.upstream,
                  onSelected: () =>
                      run(() => git.setUpstream(ref.name, upstream.name)),
                ),
              if (ref.upstream != null) ...[
                const IdeMenuSeparator(),
                IdeMenuAction(
                  l10n.gitBranchUnsetUpstream,
                  onSelected: () => run(() => git.setUpstream(ref.name, null)),
                ),
              ],
            ],
          ),
        if (local)
          IdeMenuAction(
            l10n.gitBranchRename,
            onSelected: () => unawaited(_renameBranch(ref)),
          ),
        if (tag && remotes.isNotEmpty) ...[
          onRemotes(
            l10n.gitTagPushTo,
            (remote) => git.pushTag(remote, ref.name),
          ),
          onRemotes(
            l10n.gitTagDeleteOn,
            (remote) => _deleteRemoteTag(remote, ref.name),
          ),
        ],
      ],
      [
        IdeMenuAction(
          host.favoriteBranches.of(git.service.root).contains(ref.id)
              ? l10n.gitBranchUnfavorite
              : l10n.gitBranchFavorite,
          onSelected: () =>
              host.favoriteBranches.toggle(git.service.root, ref.id),
        ),
        IdeMenuAction(
          l10n.gitBranchShowOnly,
          checked: showOnly,
          onSelected: () => host.showOnly(git, ref.id),
        ),
      ],
      [
        if (!isCurrent)
          IdeMenuAction(
            tag ? l10n.gitTagDelete : l10n.gitBranchDelete,
            onSelected: () => unawaited(_deleteRef(ref)),
          ),
      ],
    ]);
  }

  /// The tag [name] deleted on [remote], once confirmed: others may have
  /// it.
  Future<void> _deleteRemoteTag(String remote, String name) async {
    final answer = await showIdeDialog(
      context,
      message: context.l10n.gitTagDeleteOnConfirm(name, remote),
      buttons: [context.l10n.gitBranchDeleteButton],
    );
    if (answer != 0) return;
    await git.deleteRemoteTag(remote, name);
  }

  /// Checkout: a branch; a remote one as the local branch of its name,
  /// made to track it where there is none; a tag, detached.
  Future<void> _checkoutRef(IdeGitRef ref, List<IdeGitRef> refs) async {
    switch (ref.kind) {
      case IdeGitRefKind.branch:
        await git.checkout(ref.name);
      case IdeGitRefKind.remote:
        final name = ref.name.substring(ref.name.indexOf('/') + 1);
        final local = refs.any(
          (other) => other.kind == IdeGitRefKind.branch && other.name == name,
        );
        await (local ? git.checkout(name) : git.checkoutTracking(ref.name));
      case IdeGitRefKind.tag:
        await git.checkout(ref.name, detached: true);
      case IdeGitRefKind.head:
        return;
    }
  }

  /// The repository's own actions, above its branches in the branch
  /// popup: Update Project, Commit (by [onCommit]), Push, New Branch,
  /// Checkout Tag or Revision.
  List<IdeGitBranchPopupAction> repositoryActions({VoidCallback? onCommit}) {
    final l10n = context.l10n;
    return [
      IdeGitBranchPopupAction(
        l10n.gitUpdateProject,
        () => unawaited(updateProject()),
        icon: Codicons.repoPull,
      ),
      if (onCommit != null)
        IdeGitBranchPopupAction(
          l10n.gitCommitEllipsis,
          onCommit,
          icon: Codicons.check,
        ),
      IdeGitBranchPopupAction(
        l10n.gitPushEllipsis,
        () => unawaited(push()),
        icon: Codicons.repoPush,
      ),
      IdeGitBranchPopupAction(
        l10n.gitNewBranchEllipsis,
        () => unawaited(newBranch()),
        icon: Codicons.add,
      ),
      IdeGitBranchPopupAction(
        l10n.gitCheckoutRevision,
        () => unawaited(checkoutRevision()),
      ),
      IdeGitBranchPopupAction(
        l10n.gitRemotesManage,
        () => unawaited(manageRemotes()),
      ),
    ];
  }

  /// Manage Remotes: the repository's remotes, to add, edit or remove.
  Future<void> manageRemotes() => showIdeGitRemotesDialog(
    context,
    git: git,
    notifications: host.notifications,
  );

  /// Update Project: each repository's branch brought up to its upstream,
  /// by merge or by rebase, as asked (until told not to ask again).
  Future<void> updateProject() async {
    final l10n = context.l10n;
    final session = host.session;
    var rebase = session.rebaseWhenSync;
    if (session.updateProjectAsks) {
      final result = await showIdeInputDialog(
        context,
        message: l10n.gitUpdateProject,
        detail: l10n.gitUpdateProjectDetail,
        buttons: [l10n.gitUpdateMerge, l10n.gitUpdateRebase],
        checkbox: l10n.gitDontAskAgain,
        type: IdeDialogType.question,
      );
      if (result == null || result.button < 0) return;
      rebase = result.button == 1;
      session.rebaseWhenSync = rebase;
      if (result.checked) session.updateProjectAsks = false;
    }
    final repositories = host.repositories.isEmpty ? [git] : host.repositories;
    for (final repository in repositories) {
      if (repository.state?.head.upstream == null) continue;
      await host.run(() => repository.updateProject(rebase: rebase));
    }
  }

  /// Push…: the Push dialog, for the window's repositories.
  Future<void> push() => showIdeGitPushDialog(
    context,
    repositories: [
      for (final repository
          in host.repositories.isEmpty ? [git] : host.repositories)
        (p.basename(repository.service.root), repository),
    ],
    current: git,
    notifications: host.notifications,
  );

  /// New Branch: asks for its name, then makes it at HEAD and checks it
  /// out.
  Future<void> newBranch() async {
    final l10n = context.l10n;
    final result = await showIdeInputDialog(
      context,
      message: l10n.gitNewBranchEllipsis,
      buttons: [l10n.branchBarCreateButton],
      inputs: [IdeDialogInput(placeholder: l10n.gitBranchName)],
      type: IdeDialogType.question,
    );
    if (result == null || result.button != 0) return;
    final name = ideSanitizeBranchName(result.values.first);
    if (name.isEmpty) return;
    await host.run(() => git.branch(name));
  }

  /// Checkout Tag or Revision: asks for one, then checks it out, HEAD
  /// detached.
  Future<void> checkoutRevision() async {
    final l10n = context.l10n;
    final result = await showIdeInputDialog(
      context,
      message: l10n.gitCheckoutRevision,
      buttons: [l10n.gitBranchCheckout],
      inputs: [IdeDialogInput(placeholder: l10n.gitRevisionPlaceholder)],
      type: IdeDialogType.question,
    );
    if (result == null || result.button != 0) return;
    final revision = result.values.first.trim();
    if (revision.isEmpty) return;
    await host.run(() => git.checkout(revision, detached: true));
  }

  /// New Branch from: asks for its name, then makes it there and checks
  /// it out.
  Future<void> _newBranchFrom(IdeGitRef ref) async {
    final l10n = context.l10n;
    final suggested = ref.kind == IdeGitRefKind.remote
        ? ref.name.substring(ref.name.indexOf('/') + 1)
        : '';
    final result = await showIdeInputDialog(
      context,
      message: l10n.gitBranchNewFrom(ref.name),
      buttons: [l10n.branchBarCreateButton],
      inputs: [
        IdeDialogInput(placeholder: l10n.gitBranchName, value: suggested),
      ],
      type: IdeDialogType.question,
    );
    if (result == null || result.button != 0) return;
    final name = ideSanitizeBranchName(result.values.first);
    if (name.isEmpty) return;
    await host.run(() => git.branch(name, ref: ref.name));
  }

  Future<void> _renameBranch(IdeGitRef ref) async {
    final l10n = context.l10n;
    final result = await showIdeInputDialog(
      context,
      message: l10n.gitBranchRenameTitle(ref.name),
      buttons: [l10n.gitBranchRenameButton],
      inputs: [
        IdeDialogInput(placeholder: l10n.gitBranchName, value: ref.name),
      ],
      type: IdeDialogType.question,
    );
    if (result == null || result.button != 0) return;
    final name = ideSanitizeBranchName(result.values.first);
    if (name.isEmpty || name == ref.name) return;
    final favorites = host.favoriteBranches;
    final root = git.service.root;
    final favorite = favorites.of(root).contains(ref.id);
    var done = false;
    await host.run(() async {
      await git.renameBranch(ref.name, name);
      done = true;
    });
    // A favorite stays one by its new name.
    if (done && favorite) {
      favorites
        ..toggle(root, ref.id)
        ..toggle(root, 'refs/heads/$name');
    }
  }

  /// Delete: a branch at once, then Restore offered; one with commits
  /// merged nowhere else, once confirmed; a remote one, once confirmed.
  Future<void> _deleteRef(IdeGitRef ref) async {
    final l10n = context.l10n;
    final commit = ref.commit;
    switch (ref.kind) {
      case IdeGitRefKind.head:
        return;
      case IdeGitRefKind.remote:
        final answer = await showIdeDialog(
          context,
          message: l10n.gitBranchDeleteRemoteConfirm(ref.name),
          buttons: [l10n.gitBranchDeleteButton],
        );
        if (answer != 0) return;
        final remote = ref.remote ?? ref.name.split('/').first;
        await host.run(
          () => git.deleteRemoteBranch(
            remote,
            ref.name.substring(remote.length + 1),
          ),
        );
        return;
      case IdeGitRefKind.tag:
        var deleted = false;
        await host.run(() async {
          await git.deleteTag(ref.name);
          deleted = true;
        });
        if (deleted && commit != null) {
          _restorable(
            l10n.gitTagDeleted(ref.name),
            () => git.tag(ref.name, commit),
          );
        }
        return;
      case IdeGitRefKind.branch:
        var deleted = false;
        try {
          await git.deleteBranch(ref.name);
          deleted = true;
        } on IdeGitNotMergedException {
          if (!context.mounted) return;
          final answer = await showIdeDialog(
            context,
            message: l10n.gitBranchNotMergedConfirm(ref.name),
            buttons: [l10n.gitBranchDeleteButton],
          );
          if (answer != 0) return;
          await host.run(() async {
            await git.deleteBranch(ref.name, force: true);
            deleted = true;
          });
        } catch (error) {
          host.notifications.notify(IdeSeverity.error, '$error');
        }
        if (deleted && commit != null) {
          _restorable(
            l10n.gitBranchDeleted(ref.name),
            () => git.createBranchAt(ref.name, commit),
          );
        }
    }
  }

  /// [message], with Restore running [restore].
  void _restorable(String message, Future<void> Function() restore) {
    if (!context.mounted) return;
    host.notifications.notify(
      IdeSeverity.info,
      message,
      primary: [
        IdeNotificationAction(
          context.l10n.gitBranchRestore,
          () => unawaited(host.run(restore)),
        ),
      ],
    );
  }

  /// Compare with Current: the log of the commits [ref] has that the
  /// current branch has not (the other way round from the log's branch
  /// menu); how many each has told, the files they differ in, HEAD's side
  /// against [ref]'s, a click away.
  Future<void> _compareWithHead(IdeGitRef ref) async {
    final branch = git.state?.head.branch;
    final here = branch ?? 'HEAD';
    final l10n = context.l10n;
    try {
      final counts = await git.service.compareWithHead(ref.name);
      if (!context.mounted) return;
      host.showOnly(
        git,
        ideGraphRange(branch == null ? 'HEAD' : 'refs/heads/$branch', ref.id),
      );
      host.notifications.notify(
        IdeSeverity.info,
        l10n.gitBranchCompared(ref.name, here, counts.ahead, counts.behind),
        primary: [
          IdeNotificationAction(
            l10n.gitBranchCompareFiles,
            () => unawaited(
              _showComparison(
                () => ideGitRevisionsDiff(
                  git,
                  ('HEAD', here),
                  (ref.name, ref.name),
                ),
              ),
            ),
          ),
        ],
      );
    } catch (error) {
      host.notifications.notify(IdeSeverity.error, '$error');
    }
  }

  /// Show Diff with Working Tree: the files [ref] and the working tree
  /// differ in.
  Future<void> _compareWithWorkingTree(IdeGitRef ref) => _showComparison(
    () => ideGitWorkingTreeDiff(
      git,
      host.files,
      ref.name,
      ref.name,
      context.l10n.gitChangeWorkingTree,
    ),
  );

  /// [compare]'s files shown; that there are none, or why they could not
  /// be read, told.
  Future<void> _showComparison(
    Future<List<IdeGitDiffFile>> Function() compare,
  ) async {
    final List<IdeGitDiffFile> files;
    try {
      files = await compare();
    } catch (error) {
      host.notifications.notify(IdeSeverity.error, '$error');
      return;
    }
    if (!context.mounted) return;
    if (files.isEmpty) {
      host.notifications.notify(
        IdeSeverity.info,
        context.l10n.gitLogNoDifferences,
      );
      return;
    }
    host.showDiff(files);
  }
}
