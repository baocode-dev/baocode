import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/git/commit_message.dart';
import '../../ide/git/git_model.dart';
import '../../ide/git/git_repository.dart';
import '../../ide/git/ide_scm_view.dart' show IdeScmSession;
import '../../ide/ide_button.dart';
import '../../ide/ide_commands.dart' show IdeKeybinding;
import '../../ide/ide_dialog.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_input.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';

/// Over the changes page's list, as over the Source Control view's: the
/// commit message, which the sparkle writes from the changes (Generate
/// Commit Message, again to cancel it), and Commit, with its variants in a
/// menu. Nothing staged, Commit offers to commit every change (the smart
/// commit, `git.enableSmartCommit`), as the IDE's does; nothing to commit,
/// it gives way to Publish Branch or Sync Changes where there is that to
/// do. The message and those choices are [scm]'s, kept for the repository
/// while the panel is.
///
/// Adapted from the IDE's Source Control view (ide_scm_view.dart), itself
/// after VS Code 6a598d4a13031703d483d103c1d934a36ad27971's Git extension
/// (`git.commit`) and Copilot's Generate Commit Message.
class GitCommitBox extends StatefulWidget {
  const GitCommitBox({
    super.key,
    required this.git,
    required this.state,
    required this.scm,
    this.commitMessage,
  });

  final IdeGitRepository git;
  final IdeGitState state;
  final IdeScmSession scm;

  /// Writes commit messages; no sparkle when null.
  final IdeCommitMessageModel? commitMessage;

  @override
  State<GitCommitBox> createState() => _GitCommitBoxState();
}

class _GitCommitBoxState extends State<GitCommitBox> {
  final _focus = FocusNode(debugLabel: 'side panel commit message');
  final _publishKey = GlobalKey(debugLabel: 'side-panel-publish');
  IdeInputValidation? _validation;

  /// Accepts the message: commits (`scm.acceptInput`'s ⌘Enter, Ctrl+Enter).
  static const _accept = IdeKeybinding(LogicalKeyboardKey.enter, primary: true);

  IdeGitRepository get _git => widget.git;
  IdeScmSession get _scm => widget.scm;

  @override
  void initState() {
    super.initState();
    _scm.message.addListener(_messageChanged);
  }

  @override
  void didUpdateWidget(GitCommitBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.scm, widget.scm)) {
      oldWidget.scm.message.removeListener(_messageChanged);
      widget.scm.message.addListener(_messageChanged);
      _validation = null;
    }
  }

  @override
  void dispose() {
    _scm.message.removeListener(_messageChanged);
    _focus.dispose();
    super.dispose();
  }

  /// Typed into, it no longer says a message is wanted.
  void _messageChanged() {
    if (_validation != null && _scm.message.text.trim().isNotEmpty) {
      setState(() => _validation = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final branch = widget.state.head.branch;
    final key = _accept.label();
    final generating = _scm.generating != null;
    final busy = _git.busy;
    return Padding(
      key: const ValueKey('side-panel-commit'),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdeInputBox(
            controller: _scm.message,
            focusNode: _focus,
            semanticsLabel: l10n.scmInput,
            placeholder: branch == null
                ? l10n.scmMessagePlaceholder(key)
                : l10n.scmMessagePlaceholderBranch(key, branch),
            minLines: 1,
            maxLines: 8,
            lineHeight: 20,
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
            validation: _validation,
            togglesInset: 3,
            shortcuts: {_accept.activator(): () => unawaited(_commit())},
            toggles: [
              if (widget.commitMessage != null)
                IdeActionButton(
                  key: const ValueKey('side-panel-generate-commit'),
                  icon: generating ? Codicons.debugStop : Codicons.sparkle,
                  tooltip: generating
                      ? l10n.scmCancelGenerateCommitMessage
                      : l10n.scmGenerateCommitMessage,
                  size: 20,
                  onPressed: () => unawaited(_generate()),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _hasChangesToCommit
                    ? _commitButton(key, enabled: !busy)
                    : _publishButton() ??
                          _syncButton() ??
                          _commitButton(key, enabled: false),
              ),
              const SizedBox(width: 2),
              Builder(
                builder: (context) => IdeActionButton(
                  key: const ValueKey('side-panel-commit-more'),
                  icon: Codicons.chevronDown,
                  tooltip: l10n.commonMoreActions,
                  size: 24,
                  onPressed: busy ? null : () => _showMore(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _commitButton(String key, {required bool enabled}) {
    final l10n = context.l10n;
    return IdeHover(
      message: '${l10n.scmCommitChanges} ($key)',
      child: IdeButton(
        key: const ValueKey('side-panel-commit-button'),
        icon: Codicons.check,
        label: l10n.scmCommit,
        expand: true,
        onPressed: enabled ? () => unawaited(_commit()) : null,
      ),
    );
  }

  /// Nothing to commit, on a branch without an upstream: Publish Branch
  /// (`getPublishBranchActionButton`).
  Widget? _publishButton() {
    final l10n = context.l10n;
    final head = widget.state.head;
    final branch = head.branch;
    if (branch == null || head.upstream != null) return null;
    final syncing = _git.syncing;
    return IdeHover(
      message: syncing
          ? l10n.scmPublishingBranchNamed(branch)
          : l10n.scmPublishBranchNamed(branch),
      child: IdeButton(
        key: _publishKey,
        icon: Codicons.cloudUpload,
        spinning: syncing,
        label: l10n.scmPublishBranch,
        expand: true,
        onPressed: _git.busy ? null : () => unawaited(_publish(branch)),
      ),
    );
  }

  /// Nothing to commit, on a branch ahead of its upstream or behind it:
  /// Sync Changes, with how far (`getSyncChangesActionButton`).
  Widget? _syncButton() {
    final l10n = context.l10n;
    final head = widget.state.head;
    final syncing = _git.syncing;
    if (head.upstream == null ||
        (!syncing && head.ahead == 0 && head.behind == 0)) {
      return null;
    }
    return IdeHover(
      message: syncing ? l10n.scmSynchronizingChanges : _syncTooltip(head),
      child: IdeButton(
        key: const ValueKey('side-panel-sync'),
        icon: Codicons.sync,
        spinning: syncing,
        label: l10n.scmSyncChanges,
        counts: [
          if (head.behind > 0) (head.behind, Codicons.arrowDown),
          if (head.ahead > 0) (head.ahead, Codicons.arrowUp),
        ],
        expand: true,
        onPressed: _git.busy ? null : () => unawaited(_sync(head)),
      ),
    );
  }

  /// `Repository.syncTooltip`.
  String _syncTooltip(IdeGitHead head) {
    final l10n = context.l10n;
    final upstream = head.upstream;
    if (head.branch == null ||
        head.unborn ||
        upstream == null ||
        (head.ahead == 0 && head.behind == 0)) {
      return l10n.scmSynchronizeChanges;
    }
    if (head.ahead == 0) return l10n.scmPullCommits(head.behind, upstream);
    if (head.behind == 0) return l10n.scmPushCommits(head.ahead, upstream);
    return l10n.scmPullPushCommits(head.behind, head.ahead, upstream);
  }

  /// `git.sync`: confirms (`git.confirmSync`), then pulls and pushes.
  Future<void> _sync(IdeGitHead head) async {
    final git = _git;
    final upstream = head.upstream;
    if (upstream == null) return;
    final l10n = context.l10n;
    if (_scm.confirmSync) {
      final pick = await showIdeDialog(
        context,
        message: l10n.scmConfirmSync(upstream),
        buttons: [l10n.commonOk, l10n.scmDontShowAgain],
      );
      if (pick == 1) {
        _scm.confirmSync = false;
      } else if (pick != 0) {
        return;
      }
    }
    try {
      await git.sync();
    } catch (error) {
      await _say('$error', IdeDialogType.error);
    }
  }

  /// `git.publish`: to the only remote, or to the one picked.
  Future<void> _publish(String branch) async {
    final git = _git;
    final l10n = context.l10n;
    try {
      final remotes = await git.remotes();
      if (!mounted) return;
      if (remotes.isEmpty) {
        await _say(l10n.scmNoRemotes, IdeDialogType.warning);
        return;
      }
      var remote = remotes.first;
      if (remotes.length > 1) {
        String? picked;
        final box = _publishKey.currentContext?.findRenderObject();
        await showIdeMenu(
          context,
          anchor: box is RenderBox
              ? box.localToGlobal(Offset.zero) & box.size
              : null,
          entries: [
            for (final name in remotes)
              IdeMenuAction(name, onSelected: () => picked = name),
          ],
        );
        if (picked == null) return;
        remote = picked!;
      }
      await git.publish(remote);
    } catch (error) {
      await _say('$error', IdeDialogType.error);
    }
  }

  /// Whether Commit has something to commit: staged changes, or others the
  /// smart commit would take, or offer to.
  bool get _hasChangesToCommit {
    final state = widget.state;
    return state.group(IdeGitGroup.staged).isNotEmpty ||
        state.group(IdeGitGroup.merge).isNotEmpty ||
        ((_scm.enableSmartCommit || _scm.suggestSmartCommit) &&
            state.group(IdeGitGroup.workingTree).isNotEmpty);
  }

  void _showMore(BuildContext anchor) {
    final l10n = context.l10n;
    final box = anchor.findRenderObject();
    unawaited(
      showIdeMenu(
        context,
        anchor: box is RenderBox
            ? box.localToGlobal(Offset.zero) & box.size
            : null,
        alignRight: true,
        entries: ideMenuGroups([
          [
            IdeMenuAction(
              l10n.scmCommit,
              onSelected: () => unawaited(_commit()),
            ),
            IdeMenuAction(
              l10n.scmCommitStaged,
              onSelected: () => unawaited(_commit(all: false)),
            ),
            IdeMenuAction(
              l10n.scmCommitAll,
              onSelected: () => unawaited(_commit(all: true)),
            ),
          ],
          [
            IdeMenuAction(
              l10n.scmCommitAmend,
              onSelected: () => unawaited(_commit(amend: true)),
            ),
          ],
          [
            IdeMenuAction(
              l10n.scmUndoLastCommit,
              onSelected: () => unawaited(_undoLastCommit()),
            ),
          ],
        ]),
      ),
    );
  }

  /// Generate Commit Message: the staged changes' diff, else every
  /// change's, with the recent commits for their conventions, to the model;
  /// its message replaces the input's. Again while it runs, cancels it.
  Future<void> _generate() async {
    final model = widget.commitMessage;
    if (model == null) return;
    final l10n = context.l10n;
    final scm = _scm;
    final git = _git;
    if (scm.generating case final running?) {
      running.complete();
      return;
    }
    final cancel = scm.generating = Completer<void>();
    setState(() {});
    try {
      final state = widget.state;
      final staged = state.group(IdeGitGroup.staged).isNotEmpty;
      final diff = await git.service.diff(
        staged: staged,
        untracked: [
          if (!staged)
            for (final resource in state.resources)
              if (resource.status == IdeGitStatus.untracked) resource.path,
        ],
      );
      if (cancel.isCompleted) return;
      if (diff.trim().isEmpty) {
        await _say(l10n.scmNoChangesToGenerate, IdeDialogType.info);
        return;
      }
      final recent = state.head.unborn
          ? const <IdeGitCommit>[]
          : await git.service.log(limit: 10);
      final message = await model(
        ideCommitMessagePrompt(
          diff,
          recentMessages: [for (final commit in recent) commit.message],
          branch: state.head.branch,
        ),
        cancel: cancel.future,
      );
      if (cancel.isCompleted || message.isEmpty) return;
      scm.message.value = TextEditingValue(
        text: message,
        selection: TextSelection.collapsed(offset: message.length),
      );
    } on IdeCommitMessageCancelled {
      // Cancelled: the input keeps what it had.
    } catch (error) {
      if (!cancel.isCompleted) await _say('$error', IdeDialogType.error);
    } finally {
      if (identical(scm.generating, cancel)) scm.generating = null;
      if (mounted) setState(() {});
    }
  }

  /// `git.commit` and its variants: [all] null commits the staged changes,
  /// or everything when none are (the smart commit, asked first); false
  /// only the staged ones; true everything.
  Future<void> _commit({bool? all, bool amend = false}) async {
    final git = _git;
    final state = git.state ?? widget.state;
    final l10n = context.l10n;
    final message = _scm.message.text;
    if (message.trim().isEmpty && !amend) {
      setState(() => _validation = IdeInputValidation(l10n.scmProvideMessage));
      _focus.requestFocus();
      return;
    }
    final noStaged = state.group(IdeGitGroup.staged).isEmpty;
    final noUnstaged = state.group(IdeGitGroup.workingTree).isEmpty;
    var commitAll = all ?? false;
    if (all == null && !noUnstaged && noStaged && !amend) {
      if (!_scm.enableSmartCommit) {
        if (!_scm.suggestSmartCommit) return;
        final pick = await showIdeDialog(
          context,
          message: l10n.scmNoStagedChanges,
          buttons: [l10n.commonYes, l10n.scmAlways, l10n.scmNever],
        );
        if (pick == 1) {
          _scm.enableSmartCommit = true;
        } else if (pick == 2) {
          _scm.suggestSmartCommit = false;
          if (mounted) setState(() {});
          return;
        } else if (pick != 0) {
          return;
        }
      }
      commitAll = true;
    }
    final merging = state.group(IdeGitGroup.merge).isNotEmpty;
    if (((noStaged && noUnstaged) || (!commitAll && noStaged)) &&
        !amend &&
        !merging) {
      await _say(l10n.scmNoChangesToCommit, IdeDialogType.info);
      return;
    }
    try {
      if (commitAll && !amend) {
        await git.commitEverything(message);
      } else {
        await git.commit(message, all: commitAll, amend: amend);
      }
      if (_scm.message.text == message) _scm.message.clear();
    } catch (error) {
      await _say('$error', IdeDialogType.error);
    }
  }

  /// Undo Last Commit: its changes back in the index, its message here.
  Future<void> _undoLastCommit() async {
    final git = _git;
    final l10n = context.l10n;
    try {
      final head = await git.headCommit();
      if (!mounted) return;
      if (head == null) {
        await _say(l10n.scmCantUndo, IdeDialogType.warning);
        return;
      }
      if (head.parentIds.length > 1) {
        final pick = await showIdeDialog(
          context,
          message: l10n.scmConfirmUndoMerge,
          buttons: [l10n.scmUndoMergeCommit],
        );
        if (pick != 0) return;
      }
      await git.undoCommit(head);
      _scm.message.text = head.message;
    } catch (error) {
      await _say('$error', IdeDialogType.error);
    }
  }

  Future<void> _say(String message, IdeDialogType type) async {
    if (!mounted) return;
    await showIdeDialog(
      context,
      type: type,
      message: message,
      buttons: const [],
      cancel: context.l10n.commonOk,
    );
  }
}
