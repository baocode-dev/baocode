// Under the chat input: the Git branch the agent works on. A project's
// branch (`*` after it with changes not committed), a menu of its branches
// to switch to, Create Branch… and New Worktree…; a workspace's name, a
// menu of its folders with each one's branches at its side. A branch
// checked out in another worktree is switched to by working there: the
// conversation shows that worktree, and the composer gets a line telling
// the agent so. Nothing to switch while the agent works (the files would
// change under it), nor without a repository: then only the name.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../chat/chat_session.dart';
import '../chat/composer/composer_picker.dart';
import '../ide/git/git_checkout.dart' show ideSanitizeBranchName;
import '../ide/git/git_model.dart';
import '../ide/git/git_repository.dart';
import '../ide/ide_dialog.dart';
import '../ide/ide_hover.dart';
import '../kernel/kernel_types.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';

class ChatBranchBar extends StatefulWidget {
  const ChatBranchBar({
    super.key,
    required this.session,
    required this.name,
    this.workspace = false,
    this.repositories = const [],
    this.onSwitchWorktree,
  });

  /// The conversation whose input it is under: nothing is switched while
  /// it works.
  final ChatSession session;

  /// The project's name, or the workspace's.
  final String name;

  /// Whether it is a multi-folder workspace's, [repositories] its folders'.
  final bool workspace;

  /// The project's repository, or each of the workspace's folders', by
  /// folder; none without Git.
  final List<(String, IdeGitRepository)> repositories;

  /// Makes the conversation show the worktree at `path` of `folder`'s
  /// repository; no worktrees offered when null.
  final void Function(String folder, String path)? onSwitchWorktree;

  @override
  State<ChatBranchBar> createState() => _ChatBranchBarState();
}

class _ChatBranchBarState extends State<ChatBranchBar> {
  /// Each repository's local branches, the last committed first.
  final Map<IdeGitRepository, List<String>> _branches = {};

  /// The branch each repository was on when its branches were read, and
  /// when: read again once it is on another, or pointed at a while after.
  final Map<IdeGitRepository, (String?, DateTime)> _read = {};

  static const _readAgainAfter = Duration(seconds: 3);

  /// Between an option of a workspace's submenu's folder and its branch.
  static const _separator = '\u0000';

  /// The branch of a workspace folder's Create Branch….
  static const _create = '\u0001';

  /// The branch of a workspace folder's New Worktree….
  static const _newWorktree = '\u0002';

  Iterable<IdeGitRepository> get _gits =>
      widget.repositories.map((repository) => repository.$2);

  @override
  void initState() {
    super.initState();
    for (final git in _gits) {
      git.addListener(_gitChanged);
    }
    _gitChanged();
  }

  @override
  void didUpdateWidget(ChatBranchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = {for (final (_, git) in oldWidget.repositories) git};
    final now = {..._gits};
    for (final git in old.difference(now)) {
      git.removeListener(_gitChanged);
      _branches.remove(git);
      _read.remove(git);
    }
    for (final git in now.difference(old)) {
      git.addListener(_gitChanged);
    }
    _gitChanged();
  }

  @override
  void dispose() {
    for (final git in _gits) {
      git.removeListener(_gitChanged);
    }
    super.dispose();
  }

  /// Reads the branches of a repository not read yet, or since on another.
  void _gitChanged() {
    for (final git in _gits) {
      final state = git.state;
      if (state == null) continue;
      if (_read[git] case (final branch, _) when branch == state.head.branch) {
        continue;
      }
      unawaited(_readBranches(git));
    }
  }

  /// Reads them again when pointed at: one made elsewhere shows.
  void _pointedAt() {
    final now = DateTime.now();
    for (final git in _gits) {
      if (!git.isRepository) continue;
      if (_read[git] case (_, final at)
          when now.difference(at) < _readAgainAfter) {
        continue;
      }
      unawaited(_readBranches(git));
    }
  }

  Future<void> _readBranches(IdeGitRepository git) async {
    _read[git] = (git.state?.head.branch, DateTime.now());
    try {
      final refs = await git.refs();
      if (!mounted || !_gits.contains(git)) return;
      setState(() {
        _branches[git] = [
          for (final ref in refs)
            if (ref.kind == IdeGitRefKind.branch) ref.name,
        ];
      });
    } on Object {
      // Not a repository after all, or Git failed: the menu lists what it
      // knows.
    }
  }

  /// [git]'s branch, as the pill reads it: in a worktree of its
  /// repository's other than its own, that worktree's name after it.
  String _branchLabel(IdeGitRepository git, IdeGitState state) {
    var branch = state.head.branch ?? context.l10n.branchBarDetached;
    if (state.resources.isNotEmpty) branch = '$branch*';
    return switch (_worktreeOf(git)) {
      final worktree? =>
        '$branch · ${git.service.pathContext.basename(worktree.path)}',
      null => branch,
    };
  }

  /// The worktree [git] is, when it is not its repository's own (the agent
  /// works there); null otherwise.
  IdeGitWorktree? _worktreeOf(IdeGitRepository git) {
    final worktree = ideWorktreeOf(
      git.service.root,
      git.worktrees,
      git.service.pathContext,
    );
    return worktree == null || worktree.main ? null : worktree;
  }

  /// The workspace's folders worked on in another worktree of theirs.
  Iterable<IdeGitRepository> get _inWorktrees =>
      _gits.where((git) => git.state != null && _worktreeOf(git) != null);

  /// The workspace's name, and the branch and worktree of each folder
  /// worked on in another worktree: where the agent works.
  String get _workspaceLabel => [
    widget.name,
    for (final git in _inWorktrees) _branchLabel(git, git.state!),
  ].join(' · ');

  IconData get _workspaceIcon =>
      _inWorktrees.isEmpty ? Codicons.folderLibrary : Codicons.worktree;

  String? get _workspaceTooltip =>
      switch ([for (final git in _inWorktrees) ?_worktreeTooltip(git)]) {
        [] => null,
        final lines => lines.join('\n'),
      };

  /// Which worktree [git] is, where it is not its repository's own.
  String? _worktreeTooltip(IdeGitRepository git) => switch (_worktreeOf(git)) {
    final worktree? => context.l10n.branchBarWorktree(
      git.service.pathContext.basename(worktree.path),
      worktree.path,
    ),
    null => null,
  };

  /// The worktree other than [git]'s where [branch] is checked out.
  IdeGitWorktree? _worktreeHaving(IdeGitRepository git, String branch) {
    final paths = git.service.pathContext;
    for (final worktree in git.worktrees) {
      if (worktree.branch == branch &&
          !paths.equals(worktree.path, git.service.root)) {
        return worktree;
      }
    }
    return null;
  }

  /// [branch] in the menu, [id] its option's: in another worktree, marked
  /// with that worktree's name.
  KernelOption _branchOption(IdeGitRepository git, String branch, String id) =>
      switch (_worktreeHaving(git, branch)) {
        final worktree? => KernelOption(
          id,
          branch,
          Codicons.worktree,
          worktree.main
              ? context.l10n.gitLogMainWorktree
              : context.l10n.branchBarInWorktree(
                  git.service.pathContext.basename(worktree.path),
                ),
        ),
        null => KernelOption(id, branch, Codicons.gitBranch, ''),
      };

  /// [git]'s branches, the one it is on among them.
  List<String> _branchesOf(IdeGitRepository git) {
    final branches = _branches[git] ?? const [];
    final current = git.state?.head.branch;
    return [
      if (current != null && !branches.contains(current)) current,
      ...branches,
    ];
  }

  // --- Actions ----------------------------------------------------------------

  /// Runs [operation] on [branch] unless the agent has started meanwhile;
  /// what Git said when it refused, in a dialog. Whether it ran.
  Future<bool> _run(String branch, Future<void> Function() operation) async {
    if (widget.session.isStreaming) return false;
    try {
      await operation();
      return true;
    } on Object catch (error) {
      if (!mounted) return false;
      final l10n = context.l10n;
      await showIdeDialog(
        context,
        message: l10n.branchBarFailed(branch),
        detail: '$error',
        buttons: [l10n.commonOk],
        cancel: null,
        type: IdeDialogType.error,
      );
      return false;
    }
  }

  /// [branch] picked in [folder]'s repository: checked out, or, checked
  /// out in another worktree, worked on there.
  void _pick(String folder, IdeGitRepository git, String branch) {
    if (branch == git.state?.head.branch) return;
    if ((_worktreeHaving(git, branch), widget.onSwitchWorktree) case (
      final worktree?,
      final _?,
    )) {
      _workIn(folder, worktree.path, branch);
      return;
    }
    unawaited(_run(branch, () => git.checkout(branch)));
  }

  /// The conversation on the worktree at [path], and a line in the
  /// composer telling the agent to work there.
  void _workIn(String folder, String path, String branch) {
    if (widget.session.isStreaming) return;
    widget.onSwitchWorktree?.call(folder, path);
    widget.session.draft.restore(
      context.l10n.branchBarWorkIn(path, branch),
      const [],
    );
  }

  /// Asks for a branch's name, then makes it from where [git] is in a new
  /// worktree beside the repository's own folder, and works there.
  Future<void> _createWorktree(String folder, IdeGitRepository git) async {
    final l10n = context.l10n;
    final paths = git.service.pathContext;
    final main =
        git.worktrees.where((worktree) => worktree.main).firstOrNull?.path ??
        git.service.root;
    final result = await showIdeInputDialog(
      context,
      message: l10n.branchBarNewWorktreeFrom(
        git.state?.head.branch ?? l10n.branchBarDetached,
        paths.basename(main),
      ),
      buttons: [l10n.branchBarCreateButton],
      inputs: [IdeDialogInput(placeholder: l10n.gitBranchName)],
      type: IdeDialogType.question,
    );
    if (result == null || result.button != 0 || !mounted) return;
    final name = ideSanitizeBranchName(result.values.first);
    if (name.isEmpty) return;
    final path = ideNewWorktreePath(
      main,
      name,
      taken: [for (final worktree in git.worktrees) worktree.path],
      paths: paths,
    );
    if (await _run(name, () => git.addWorktree(path, newBranch: name)) &&
        mounted) {
      _workIn(folder, path, name);
    }
  }

  /// Asks for a branch's name, then makes it where [git] is and checks it
  /// out; [message] says where.
  Future<void> _createBranch(IdeGitRepository git, String message) async {
    final l10n = context.l10n;
    final result = await showIdeInputDialog(
      context,
      message: message,
      buttons: [l10n.branchBarCreateButton],
      inputs: [IdeDialogInput(placeholder: l10n.gitBranchName)],
      type: IdeDialogType.question,
    );
    if (result == null || result.button != 0) return;
    final name = ideSanitizeBranchName(result.values.first);
    if (name.isEmpty) return;
    await _run(name, () => git.branch(name));
  }

  // --- Building -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.session, ..._gits]),
      builder: (context, _) => Padding(
        padding: const EdgeInsets.only(top: 4, left: 4),
        child: MouseRegion(
          onEnter: (_) => _pointedAt(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Flexible(child: _buildPill(context))],
          ),
        ),
      ),
    );
  }

  Widget _buildPill(BuildContext context) {
    final l10n = context.l10n;
    final running = widget.session.isStreaming;
    if (widget.workspace) {
      if (running || widget.repositories.isEmpty) {
        return _Label(
          icon: _workspaceIcon,
          label: _workspaceLabel,
          tooltip: running
              ? [l10n.branchBarRunning, ?_workspaceTooltip].join('\n\n')
              : _workspaceTooltip,
        );
      }
      return _buildWorkspacePicker(context);
    }
    final git = widget.repositories.firstOrNull?.$2;
    final state = git?.state;
    if (git == null || state == null) {
      return _Label(icon: Codicons.folder, label: widget.name);
    }
    if (running) {
      return _Label(
        icon: _worktreeOf(git) == null ? Codicons.gitBranch : Codicons.worktree,
        label: _branchLabel(git, state),
        tooltip: [l10n.branchBarRunning, ?_worktreeTooltip(git)].join('\n\n'),
      );
    }
    final current = state.head.branch;
    final folder = widget.repositories.first.$1;
    return ComposerPicker(
      options: [
        for (final branch in _branchesOf(git))
          _branchOption(git, branch, branch),
      ],
      // In another worktree, its mark.
      selected: KernelOption(
        current ?? '',
        current ?? l10n.branchBarDetached,
        _worktreeOf(git) == null ? Codicons.gitBranch : Codicons.worktree,
        '',
      ),
      label: _branchLabel(git, state),
      tooltip: _worktreeTooltip(git),
      // Where a branch is checked out in another worktree, its name.
      descriptionAside: true,
      title: l10n.branchBarSwitch,
      searchPlaceholder: l10n.branchBarSearch,
      footers: [
        (
          label: l10n.branchBarCreate,
          icon: Codicons.add,
          onTap: () => unawaited(
            _createBranch(
              git,
              l10n.branchBarCreateFrom(current ?? l10n.branchBarDetached),
            ),
          ),
        ),
        if (widget.onSwitchWorktree != null)
          (
            label: l10n.branchBarNewWorktree,
            icon: Codicons.worktree,
            onTap: () => unawaited(_createWorktree(folder, git)),
          ),
      ],
      onSelected: (option) => _pick(folder, git, option.id),
    );
  }

  /// The workspace's folders, each one's branches at its side.
  Widget _buildWorkspacePicker(BuildContext context) {
    final l10n = context.l10n;
    final gits = {for (final (folder, git) in widget.repositories) folder: git};
    // A workspace's folders are this machine's.
    String nameOf(String folder) => p.basename(folder);
    const create = KernelOptionGroup('create', '');
    return ComposerPicker(
      options: [
        for (final (folder, git) in widget.repositories)
          KernelOption(
            folder,
            nameOf(folder),
            Codicons.folder,
            switch (git.state) {
              final state? => _branchLabel(git, state),
              null => l10n.branchBarNotRepository,
            },
          ),
      ],
      selected: KernelOption('', widget.name, _workspaceIcon, ''),
      label: _workspaceLabel,
      // A line each, its branch at its end.
      descriptionAside: true,
      title: l10n.branchBarWorkspace,
      tooltip: _workspaceTooltip ?? l10n.branchBarWorkspace,
      menuWidth: 290,
      submenuOf: (option) => switch (gits[option.id]) {
        final git? when git.isRepository => [
          for (final branch in _branchesOf(git))
            _branchOption(git, branch, '${option.id}$_separator$branch'),
          KernelOption(
            '${option.id}$_separator$_create',
            l10n.branchBarCreate,
            Codicons.add,
            '',
            group: create,
          ),
          if (widget.onSwitchWorktree != null)
            KernelOption(
              '${option.id}$_separator$_newWorktree',
              l10n.branchBarNewWorktree,
              Codicons.worktree,
              '',
              group: create,
            ),
        ],
        _ => const [],
      },
      // Each folder's branch.
      checks: (option) {
        final at = option.id.indexOf(_separator);
        if (at < 0) return false;
        final git = gits[option.id.substring(0, at)];
        return option.id.substring(at + 1) == git?.state?.head.branch;
      },
      onSelected: (option) {
        final at = option.id.indexOf(_separator);
        if (at < 0) return;
        final folder = option.id.substring(0, at);
        final branch = option.id.substring(at + 1);
        final git = gits[folder];
        if (git == null) return;
        switch (branch) {
          case _create:
            unawaited(
              _createBranch(git, l10n.branchBarCreateIn(nameOf(folder))),
            );
          case _newWorktree:
            unawaited(_createWorktree(folder, git));
          default:
            _pick(folder, git, branch);
        }
      },
    );
  }
}

/// The pill's look with nothing to open: the name of a folder without a
/// repository, or the branch while the agent works ([tooltip] says so).
class _Label extends StatelessWidget {
  const _Label({required this.icon, required this.label, this.tooltip});

  final IconData icon;
  final String label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final color = tooltip == null ? AppColors.textMuted : AppColors.textFaint;
    Widget label = Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              this.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
    if (tooltip case final tooltip?) {
      label = IdeHover(message: tooltip, child: label);
    }
    return label;
  }
}

/// Where a new worktree for [branch] goes: beside the repository's own
/// folder [main], named after both (`app` and `fix/login`: `app-fix-login`),
/// numbered past those [taken].
String ideNewWorktreePath(
  String main,
  String branch, {
  required Iterable<String> taken,
  required p.Context paths,
}) {
  final parent = paths.dirname(main);
  final base = '${paths.basename(main)}-${branch.replaceAll('/', '-')}';
  bool free(String path) => !taken.any((other) => paths.equals(other, path));
  var path = paths.join(parent, base);
  for (var n = 2; !free(path); n++) {
    path = paths.join(parent, '$base-$n');
  }
  return path;
}
