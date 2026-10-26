// JetBrains IDEs' Stash tab of the Commit tool window: each repository's
// stashes, the newest first, each unfolding to its files (a click shows a
// file's changes in the log's place); Apply, Pop, Unstash as Branch and
// Drop from a stash's menu, and over them Stash Changes and Clear.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../ide_dates.dart';
import '../ide_dialog.dart';
import '../ide_hover.dart';
import '../ide_list.dart';
import '../ide_menu.dart';
import '../ide_notifications.dart';
import 'git_checkout.dart' show ideSanitizeBranchName;
import 'git_model.dart';
import 'git_repository.dart';
import 'ide_git_log_view.dart';

/// Asks how to stash (a message, the untracked files too), then stashes
/// [git]'s changes, only [paths]' where given (JetBrains' shelving of some
/// files); false where it was not asked to.
Future<bool> ideGitStashChanges(
  BuildContext context,
  IdeGitRepository git, {
  Iterable<String>? paths,
}) async {
  final l10n = context.l10n;
  final result = await showIdeInputDialog(
    context,
    message: paths == null
        ? l10n.gitStashChangesTitle
        : l10n.gitStashFilesTitle(paths.length),
    buttons: [l10n.gitStashButton],
    inputs: [IdeDialogInput(placeholder: l10n.gitStashMessage)],
    checkbox: l10n.gitStashUntracked,
    type: IdeDialogType.question,
  );
  if (result == null || result.button != 0) return false;
  await git.stash(
    message: result.values.first.trim(),
    paths: paths,
    untracked: result.checked,
  );
  return true;
}

class IdeGitStashView extends StatefulWidget {
  const IdeGitStashView({
    super.key,
    required this.repositories,
    required this.notifications,
    required this.onShowDiff,
  });

  /// Each repository, by its folder's name.
  final List<(String name, IdeGitRepository git)> repositories;
  final IdeNotifications notifications;

  /// Shows a stash's files' changes, from the one at the index.
  final void Function(List<IdeGitDiffFile> files, int index) onShowDiff;

  @override
  State<IdeGitStashView> createState() => IdeGitStashViewState();
}

class IdeGitStashViewState extends State<IdeGitStashView> {
  final Map<IdeGitRepository, Future<List<IdeGitStash>>> _stashes = {};
  final Map<String, Future<List<IdeGitDiffFile>>> _files = {};
  final Set<String> _open = {};
  String? _selected;

  @override
  void initState() {
    super.initState();
    _listen(widget.repositories);
  }

  @override
  void didUpdateWidget(IdeGitStashView oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final (_, git) in oldWidget.repositories) {
      git.removeListener(_repositoryChanged);
    }
    _listen(widget.repositories);
  }

  @override
  void dispose() {
    for (final (_, git) in widget.repositories) {
      git.removeListener(_repositoryChanged);
    }
    super.dispose();
  }

  void _listen(List<(String, IdeGitRepository)> repositories) {
    for (final (_, git) in repositories) {
      git.addListener(_repositoryChanged);
    }
  }

  /// Read again as a repository changes: a stash made or dropped from a
  /// terminal shows.
  void _repositoryChanged() {
    if (!mounted) return;
    setState(_stashes.clear);
  }

  Future<List<IdeGitStash>> _stashesOf(IdeGitRepository git) =>
      _stashes[git] ??= git.stashes().catchError(
        (Object _) => const <IdeGitStash>[],
      );

  /// [stash]'s files: the changes to tracked ones against where it was
  /// made, then the untracked ones it took.
  Future<List<IdeGitDiffFile>> _filesOf(
    IdeGitRepository git,
    IdeGitStash stash,
  ) => _files[stash.id] ??= () async {
    final l10n = context.l10n;
    final base = '${stash.id}^1';
    final (tracked, untracked) = await (
      ideGitRevisionsDiff(
        git,
        (base, l10n.gitStashBase),
        (stash.id, stash.ref),
      ),
      git.service.stashedUntracked(stash.id),
    ).wait;
    return [
      ...tracked,
      for (final path in untracked)
        IdeGitDiffFile(
          path: path,
          status: IdeGitStatus.untracked,
          original: () => Future.value(''),
          modified: () => git.service
              .show('${stash.id}^3', path)
              .catchError((Object _) => ''),
          modifiedLabel: stash.ref,
        ),
    ];
  }();

  Future<void> _run(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      if (mounted) widget.notifications.notify(IdeSeverity.error, '$error');
    }
    if (mounted) setState(_stashes.clear);
  }

  Future<void> _menu(
    Offset position,
    IdeGitRepository git,
    IdeGitStash stash,
  ) => showIdeMenu(
    context,
    position: position,
    entries: [
      IdeMenuAction(
        context.l10n.gitStashApply,
        onSelected: () => unawaited(_run(() => git.unstash(stash.ref))),
      ),
      IdeMenuAction(
        context.l10n.gitStashPop,
        onSelected: () =>
            unawaited(_run(() => git.unstash(stash.ref, pop: true))),
      ),
      IdeMenuAction(
        context.l10n.gitStashAsBranch,
        onSelected: () => unawaited(_asBranch(git, stash)),
      ),
      const IdeMenuSeparator(),
      IdeMenuAction(
        context.l10n.gitStashCopyMessage,
        onSelected: () =>
            unawaited(Clipboard.setData(ClipboardData(text: stash.message))),
      ),
      IdeMenuAction(
        context.l10n.gitStashDrop,
        onSelected: () => unawaited(_drop(git, stash)),
      ),
    ],
  );

  Future<void> _asBranch(IdeGitRepository git, IdeGitStash stash) async {
    final l10n = context.l10n;
    final result = await showIdeInputDialog(
      context,
      message: l10n.gitStashAsBranch,
      buttons: [l10n.branchBarCreateButton],
      inputs: [IdeDialogInput(placeholder: l10n.gitBranchName)],
      type: IdeDialogType.question,
    );
    if (result == null || result.button != 0) return;
    final name = ideSanitizeBranchName(result.values.first);
    if (name.isEmpty) return;
    await _run(() => git.stashBranch(name, stash.ref));
  }

  Future<void> _drop(IdeGitRepository git, IdeGitStash stash) async {
    final l10n = context.l10n;
    final choice = await showIdeDialog(
      context,
      message: l10n.gitStashDropConfirm(stash.ref),
      detail: stash.message,
      buttons: [l10n.gitStashDropButton],
    );
    if (choice != 0) return;
    await _run(() => git.dropStash(stash.ref));
  }

  /// Every stash of the repositories dropped, once confirmed.
  Future<void> clear() async {
    final l10n = context.l10n;
    final choice = await showIdeDialog(
      context,
      message: l10n.gitStashClearConfirm,
      buttons: [l10n.gitStashClearButton],
    );
    if (choice != 0) return;
    for (final (_, git) in widget.repositories) {
      await _run(git.clearStashes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final several = widget.repositories.length > 1;
    return FutureBuilder<List<List<IdeGitStash>>>(
      future: Future.wait([
        for (final (_, git) in widget.repositories) _stashesOf(git),
      ]),
      builder: (context, snapshot) {
        final lists = snapshot.data;
        if (lists == null) return const SizedBox.shrink();
        if (lists.every((stashes) => stashes.isEmpty)) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              context.l10n.gitStashNone,
              style: TextStyle(color: IdeListColors.description, fontSize: 13),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 2),
          children: [
            for (final (index, (name, git)) in widget.repositories.indexed)
              if (lists[index].isNotEmpty) ...[
                if (several) _header(name),
                for (final stash in lists[index]) ..._stash(git, stash),
              ],
          ],
        );
      },
    );
  }

  Widget _header(String name) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
    child: Text(
      name,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );

  List<Widget> _stash(IdeGitRepository git, IdeGitStash stash) {
    final open = _open.contains(stash.id);
    final l10n = context.l10n;
    final description = [
      ?stash.branch,
      ideFromNow(stash.date, ago: true, l10n: l10n),
    ].join(' · ');
    return [
      IdeListRow(
        key: ValueKey('stash:${stash.id}'),
        selected: _selected == stash.id,
        onTap: () => setState(() {
          _selected = stash.id;
          if (!_open.remove(stash.id)) _open.add(stash.id);
        }),
        onContextMenu: (position) {
          setState(() => _selected = stash.id);
          unawaited(_menu(position, git, stash));
        },
        builder: (context, hovered) => Row(
          children: [
            const SizedBox(width: 4),
            Icon(
              open ? Codicons.chevronDown : Codicons.chevronRight,
              size: 14,
              color: IdeListColors.description,
            ),
            const SizedBox(width: 2),
            Icon(Codicons.gitStash, size: 14, color: IdeListColors.description),
            const SizedBox(width: 6),
            Expanded(
              child: IdeHover(
                message: '${stash.ref}  ${stash.message}',
                child: IdeResourceLabel(
                  name: stash.message,
                  description: description,
                ),
              ),
            ),
          ],
        ),
      ),
      if (open)
        FutureBuilder<List<IdeGitDiffFile>>(
          future: _filesOf(git, stash),
          builder: (context, snapshot) {
            final files = snapshot.data ?? const <IdeGitDiffFile>[];
            final paths = git.service.pathContext;
            return Column(
              children: [
                for (final (index, file) in files.indexed)
                  IdeListRow(
                    key: ValueKey('stash:${stash.id}:${file.path}'),
                    selected: _selected == '${stash.id}:${file.path}',
                    onTap: () {
                      setState(() => _selected = '${stash.id}:${file.path}');
                      widget.onShowDiff(files, index);
                    },
                    builder: (context, hovered) => Row(
                      children: [
                        const SizedBox(width: 40),
                        FileIcon(file.path),
                        const SizedBox(width: 6),
                        Expanded(
                          child: IdeResourceLabel(
                            name: paths.basename(file.path),
                            nameColor: file.status?.color,
                            description: switch (paths.relative(
                              paths.dirname(file.path),
                              from: git.service.root,
                            )) {
                              '.' => null,
                              final folder => folder,
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
    ];
  }
}
