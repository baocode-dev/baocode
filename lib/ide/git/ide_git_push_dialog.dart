// JetBrains IDEs' Push dialog: for each repository, its branch, where it
// goes (the remote and the branch there, which can be changed) and the
// commits that go, a commit's files beside them; then Push, or Force Push
// (with lease, once confirmed), the tags of the commits pushed too where
// asked.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../ide_button.dart';
import '../ide_dialog.dart';
import '../ide_hover.dart';
import '../ide_input.dart';
import '../ide_list.dart';
import '../ide_menu.dart';
import '../ide_notifications.dart';
import 'git_model.dart';
import 'git_repository.dart';
import 'git_service.dart';
import 'ide_git_log_view.dart' show ideCommitChangeStatus;

/// Shows the Push dialog for [repositories] (by their folder's name):
/// [current]'s pushed, and the others' whose branches have upstreams; what
/// goes wrong is told in [notifications].
Future<void> showIdeGitPushDialog(
  BuildContext context, {
  required List<(String name, IdeGitRepository git)> repositories,
  required IdeGitRepository current,
  required IdeNotifications notifications,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => IdeGitPushDialog(
    repositories: [
      for (final (name, git) in repositories)
        if (git.state?.head.branch != null) (name, git),
    ],
    current: current,
    notifications: notifications,
  ),
);

/// One repository's push: where its branch goes, and what.
class _Push {
  _Push(this.name, this.git, {required bool current}) {
    final head = git.state!.head;
    final upstream = head.upstream;
    final slash = upstream?.indexOf('/') ?? -1;
    remote = slash > 0 ? upstream!.substring(0, slash) : 'origin';
    target = TextEditingController(
      text: slash > 0 ? upstream!.substring(slash + 1) : head.branch,
    );
    commits = git.service
        .log(
          refs: upstream == null
              ? const ['HEAD', '--not', '--remotes']
              : ['$upstream..HEAD'],
          limit: 500,
        )
        .catchError((Object _) => const <IdeGitCommit>[]);
    remotes = git.remotes().catchError((Object _) => const <String>[]);
    // Another repository's branch with no upstream would be published.
    included = current || upstream != null;
  }

  final String name;
  final IdeGitRepository git;
  late String remote;
  late final TextEditingController target;
  late final Future<List<IdeGitCommit>> commits;
  late final Future<List<String>> remotes;
  late bool included;

  String get branch => git.state!.head.branch!;
  bool get hasUpstream => git.state!.head.upstream != null;
}

/// The dialog itself: what [showIdeGitPushDialog] shows.
class IdeGitPushDialog extends StatefulWidget {
  const IdeGitPushDialog({
    super.key,
    required this.repositories,
    required this.current,
    required this.notifications,
  });

  final List<(String name, IdeGitRepository git)> repositories;
  final IdeGitRepository current;
  final IdeNotifications notifications;

  @override
  State<IdeGitPushDialog> createState() => _IdeGitPushDialogState();
}

class _IdeGitPushDialogState extends State<IdeGitPushDialog> {
  late final List<_Push> _pushes = [
    for (final (name, git) in widget.repositories)
      _Push(name, git, current: identical(git, widget.current)),
  ];

  /// The commit whose files show, and its repository's push.
  (_Push, IdeGitCommit)? _selected;
  final Map<String, Future<List<IdeGitCommitChange>>> _files = {};
  bool _tags = false;

  @override
  void dispose() {
    for (final push in _pushes) {
      push.target.dispose();
    }
    super.dispose();
  }

  Future<void> _push({bool force = false}) async {
    final l10n = context.l10n;
    final notifications = widget.notifications;
    final tags = _tags;
    final pushes = [
      for (final push in _pushes)
        if (push.included && push.target.text.trim().isNotEmpty)
          (git: push.git, remote: push.remote, target: push.target.text.trim()),
    ];
    if (pushes.isEmpty) return;
    if (force) {
      final answer = await showIdeDialog(
        context,
        message: l10n.gitPushForceConfirm(
          pushes.map((push) => '${push.remote}/${push.target}').join(', '),
        ),
        detail: l10n.gitPushForceDetail,
        buttons: [l10n.gitPushForce],
      );
      if (answer != 0 || !mounted) return;
    }
    Navigator.of(context).pop();
    Future<void> runSync(IdeGitRepository git) async {
      try {
        await git.sync();
      } catch (error) {
        notifications.notify(IdeSeverity.error, '$error');
      }
    }

    for (final push in pushes) {
      try {
        await push.git.pushTo(
          push.remote,
          push.target,
          force: force,
          tags: tags,
        );
      } catch (error) {
        // Refused because the remote moved on: offer pull-then-push when
        // pushing directly to the branch's upstream (same as SCM's Push).
        final upstream = push.git.state?.head.upstream;
        if (!force &&
            !tags &&
            upstream == '${push.remote}/${push.target}' &&
            isGitPushRejected(error)) {
          notifications.notify(
            IdeSeverity.error,
            '$error',
            primary: [
              IdeNotificationAction(
                l10n.scmSyncChanges,
                () => unawaited(runSync(push.git)),
              ),
            ],
          );
        } else {
          notifications.notify(IdeSeverity.error, '$error');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final foreground = colors['editorWidget.foreground'];
    final border = colors.get('widget.border');
    final size = MediaQuery.sizeOf(context);
    final width = math.min(860.0, size.width * .9);
    final height = math.min(520.0, size.height * .8);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
            unawaited(_push()),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            unawaited(_push()),
      },
      child: Focus(
        autofocus: true,
        child: Align(
          alignment: const Alignment(0, -0.4),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: colors['editorWidget.background'],
                border: border == null ? null : Border.all(color: border),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Color(0x26000000), blurRadius: 20),
                ],
              ),
              child: DefaultTextStyle(
                style: TextStyle(fontSize: 13, color: foreground),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          Text(
                            l10n.gitPushTitle,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          IdeActionButton(
                            icon: Codicons.close,
                            tooltip: l10n.dialogCloseDialog,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 1, color: border ?? Colors.transparent),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: _commitList()),
                          Container(
                            width: 1,
                            color: border ?? Colors.transparent,
                          ),
                          Expanded(flex: 2, child: _fileList()),
                        ],
                      ),
                    ),
                    Container(height: 1, color: border ?? Colors.transparent),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: IntrinsicWidth(
                                child: IdeCheckbox(
                                  label: l10n.gitPushTags,
                                  checked: _tags,
                                  onChanged: () =>
                                      setState(() => _tags = !_tags),
                                ),
                              ),
                            ),
                          ),
                          IdeButton(
                            label: l10n.scmPush,
                            onPressed: () => unawaited(_push()),
                            dropdownTooltip: l10n.gitPushForce,
                            onDropdown: (rect) => unawaited(
                              showIdeMenu(
                                context,
                                anchor: rect,
                                entries: [
                                  IdeMenuAction(
                                    l10n.gitPushForce,
                                    onSelected: () =>
                                        unawaited(_push(force: true)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IdeButton(
                            label: l10n.commonCancel,
                            secondary: true,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Each repository's header (its branch, the remote and the branch it
  /// goes to) and the commits that go.
  Widget _commitList() => ListView(
    padding: const EdgeInsets.symmetric(vertical: 6),
    children: [
      for (final push in _pushes) ...[
        _header(push),
        FutureBuilder<List<IdeGitCommit>>(
          future: push.commits,
          builder: (context, snapshot) {
            final commits = snapshot.data;
            if (commits == null) return const SizedBox(height: 24);
            if (commits.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(36, 4, 12, 8),
                child: Text(
                  context.l10n.gitPushNothing,
                  style: TextStyle(color: IdeListColors.description),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final commit in commits) _commitRow(push, commit),
              ],
            );
          },
        ),
      ],
    ],
  );

  Widget _header(_Push push) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          if (_pushes.length > 1) ...[
            SizedBox(
              width: 26,
              child: IdeCheckbox(
                label: '',
                checked: push.included,
                onChanged: () => setState(() => push.included = !push.included),
              ),
            ),
          ],
          if (_pushes.length > 1) ...[
            Text(
              push.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
          ],
          Icon(Codicons.gitBranch, size: 14, color: IdeListColors.description),
          const SizedBox(width: 4),
          Text(push.branch),
          const SizedBox(width: 6),
          Icon(Codicons.arrowRight, size: 14, color: IdeListColors.description),
          const SizedBox(width: 6),
          FutureBuilder<List<String>>(
            future: push.remotes,
            builder: (context, snapshot) {
              final remotes = snapshot.data ?? const <String>[];
              return _Pressable(
                tooltip: l10n.gitPushRemote,
                onTap: remotes.length < 2
                    ? null
                    : (rect) => unawaited(
                        showIdeMenu(
                          context,
                          anchor: rect,
                          entries: [
                            for (final remote in remotes)
                              IdeMenuAction(
                                remote,
                                checked: remote == push.remote,
                                onSelected: () =>
                                    setState(() => push.remote = remote),
                              ),
                          ],
                        ),
                      ),
                child: Text(push.remote),
              );
            },
          ),
          const Text(' : '),
          SizedBox(
            width: 180,
            child: IdeInputBox(
              controller: push.target,
              placeholder: l10n.gitBranchName,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            ),
          ),
          if (!push.hasUpstream) ...[
            const SizedBox(width: 6),
            Text(
              l10n.gitPushNew,
              style: TextStyle(
                fontSize: 11,
                color: themeColors['gitDecoration.addedResourceForeground'],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _commitRow(_Push push, IdeGitCommit commit) {
    final selected = _selected?.$2.id == commit.id;
    return IdeListRow(
      height: 24,
      selected: selected,
      tooltip: commit.message,
      onTap: () => setState(() => _selected = (push, commit)),
      builder: (context, _) => Row(
        children: [
          const SizedBox(width: 36),
          Expanded(
            child: Text(
              commit.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            commit.author,
            style: TextStyle(fontSize: 12, color: IdeListColors.description),
          ),
          const SizedBox(width: 8),
          Text(
            commit.shortId,
            style: TextStyle(fontSize: 12, color: IdeListColors.description),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  /// The selected commit's files.
  Widget _fileList() {
    final selected = _selected;
    if (selected == null) {
      return Center(
        child: Text(
          context.l10n.gitPushSelectCommit,
          style: TextStyle(color: IdeListColors.description),
        ),
      );
    }
    final (push, commit) = selected;
    final root = push.git.service.root;
    final paths = push.git.service.pathContext;
    return FutureBuilder<List<IdeGitCommitChange>>(
      future: _files[commit.id] ??= push.git
          .commitChanges(commit.id)
          .catchError((Object _) => const <IdeGitCommitChange>[]),
      builder: (context, snapshot) {
        final files = snapshot.data ?? const <IdeGitCommitChange>[];
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          children: [
            for (final file in files)
              Builder(
                builder: (context) {
                  final status = ideCommitChangeStatus(file.status);
                  final relative = paths.relative(file.path, from: root);
                  final directory = p.posix.dirname(
                    relative.replaceAll(r'\', '/'),
                  );
                  return IdeListRow(
                    height: 24,
                    tooltip: relative,
                    builder: (context, _) => Row(
                      children: [
                        const SizedBox(width: 10),
                        FileIcon(file.path),
                        const SizedBox(width: 6),
                        Expanded(
                          child: IdeResourceLabel(
                            name: paths.basename(file.path),
                            description: directory == '.' ? null : directory,
                            strikeThrough: status.strikeThrough,
                            letter: file.status,
                            letterColor: status.color,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

/// A piece of text pressed for a menu: the remote's.
class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final ValueChanged<Rect>? onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: _hover && onTap != null
            ? themeColors['toolbar.hoverBackground']
            : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.child,
          if (onTap != null) ...[
            const SizedBox(width: 2),
            Icon(
              Codicons.chevronDown,
              size: 12,
              color: IdeListColors.description,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return child;
    return IdeHover(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            onTap(box.localToGlobal(Offset.zero) & box.size);
          },
          child: child,
        ),
      ),
    );
  }
}
