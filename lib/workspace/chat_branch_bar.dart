// Under the chat input: the Git branch the agent works on. A project's
// branch (`*` after it with changes not committed), a menu of its branches
// to switch to and Create Branch…; a workspace's name, a menu of its
// folders with each one's branches at its side. Nothing to switch while
// the agent works (the files would change under it), nor without a
// repository: then only the name. Below the local branches, the remote
// branches no local one has (pushed by others), checked out as local
// branches; at the end of the menu's title, a button that fetches and
// reads them all again.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../chat/chat_session.dart';
import '../chat/composer/composer_picker.dart';
import '../chat/widgets/hover_builder.dart';
import '../ide/git/git_checkout.dart' show ideSanitizeBranchName;
import '../ide/git/git_model.dart';
import '../ide/git/git_repository.dart';
import '../ide/ide_dialog.dart';
import '../ide/ide_hover.dart';
import '../kernel/kernel_types.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;

class ChatBranchBar extends StatefulWidget {
  const ChatBranchBar({
    super.key,
    required this.session,
    required this.name,
    this.workspace = false,
    this.repositories = const [],
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

  @override
  State<ChatBranchBar> createState() => _ChatBranchBarState();
}

class _ChatBranchBarState extends State<ChatBranchBar> {
  /// Each repository's local branches, the last committed first.
  final Map<IdeGitRepository, List<String>> _branches = {};

  /// Each repository's remote branches no local branch has the name of
  /// (`origin/feature`, once fetched), the last committed first.
  final Map<IdeGitRepository, List<String>> _remoteBranches = {};

  /// The branch each repository was on when its branches were read: read
  /// again once it is on another.
  final Map<IdeGitRepository, String?> _read = {};

  static const _readAgainAfter = Duration(seconds: 3);

  /// Between an option of a workspace's submenu's folder and its branch.
  static const _separator = '\u0000';

  /// The branch of a workspace folder's Create Branch….
  static const _create = '\u0001';

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
      _remoteBranches.remove(git);
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
      if (_read.containsKey(git) && _read[git] == state.head.branch) continue;
      unawaited(_readBranches(git));
    }
  }

  /// Reads the branch and the branches again when pointed at: a switch or
  /// one made elsewhere (a terminal, another app) shows, even where the
  /// files' watch missed it.
  void _pointedAt() {
    final now = DateTime.now();
    if (_pointed case final at? when now.difference(at) < _readAgainAfter) {
      return;
    }
    _pointed = now;
    for (final git in _gits) {
      unawaited(git.refresh());
      if (git.isRepository) unawaited(_readBranches(git));
    }
  }

  /// When it was last pointed at.
  DateTime? _pointed;

  /// Whether the refresh button's reads are under way.
  bool _refreshing = false;

  /// The refresh button: each repository fetched from all its remotes
  /// (`git fetch --all`, as Fetch From All Remotes), then its status and
  /// branches read again, those pushed by others among them. A fetch that
  /// fails (offline, no access) says why; what is here is read all the
  /// same.
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final failed = <Object>[];
    try {
      await Future.wait([
        for (final git in _gits)
          if (git.isRepository)
            () async {
              try {
                // Refreshes the status once done.
                await git.fetch();
              } on Object catch (error) {
                failed.add(error);
                await git.refresh(force: true);
              }
              await _readBranches(git);
            }()
          else
            git.refresh(force: true),
      ]);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
    if (failed.isEmpty || !mounted) return;
    final l10n = context.l10n;
    await showIdeDialog(
      context,
      message: l10n.branchBarFetchFailed,
      detail: failed.join('\n\n'),
      buttons: [l10n.commonOk],
      cancel: null,
      type: IdeDialogType.error,
    );
  }

  Future<void> _readBranches(IdeGitRepository git) async {
    _read[git] = git.state?.head.branch;
    try {
      final refs = await git.refs();
      if (!mounted || !_gits.contains(git)) return;
      final local = [
        for (final ref in refs)
          if (ref.kind == IdeGitRefKind.branch) ref.name,
      ];
      final names = local.toSet();
      setState(() {
        _branches[git] = local;
        _remoteBranches[git] = [
          for (final ref in refs)
            if (ref.kind == IdeGitRefKind.remote &&
                // `origin/HEAD`, the remote's default: not a branch.
                !ref.name.endsWith('/HEAD') &&
                !names.contains(_localNameOf(ref)))
              ref.name,
        ];
      });
    } on Object {
      // Not a repository after all, or Git failed: the menu lists what it
      // knows.
    }
  }

  /// The local branch a remote one is checked out as: `feature` of
  /// `origin/feature`.
  static String _localNameOf(IdeGitRef ref) =>
      ref.name.substring((ref.remote?.length ?? -1) + 1);

  /// [git]'s branch, as the pill reads it.
  String _branchLabel(IdeGitState state) {
    final branch = state.head.branch ?? context.l10n.branchBarDetached;
    return state.resources.isEmpty ? branch : '$branch*';
  }

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
  /// what Git said when it refused, in a dialog.
  Future<void> _run(String branch, Future<void> Function() operation) async {
    if (widget.session.isStreaming) return;
    try {
      await operation();
    } on Object catch (error) {
      if (!mounted) return;
      final l10n = context.l10n;
      await showIdeDialog(
        context,
        message: l10n.branchBarFailed(branch),
        detail: '$error',
        buttons: [l10n.commonOk],
        cancel: null,
        type: IdeDialogType.error,
      );
    }
  }

  void _checkout(IdeGitRepository git, String branch) {
    if (branch == git.state?.head.branch) return;
    unawaited(_run(branch, () => git.checkout(branch)));
  }

  /// Checks the remote branch [branch] (`origin/feature`) out as the local
  /// branch tracking it, made if there is none (Git: Checkout to…'s).
  void _checkoutRemote(IdeGitRepository git, String branch) {
    unawaited(
      _run(branch, () async {
        final tracking = await git.trackingBranches(branch);
        if (tracking.isNotEmpty) {
          await git.checkout(tracking.first);
        } else {
          await git.checkoutTracking(branch);
        }
      }),
    );
  }

  /// The menu's group of [_remoteBranches], under its heading.
  KernelOptionGroup _remoteGroup(BuildContext context) =>
      KernelOptionGroup('remote', context.l10n.branchBarRemoteGroup);

  /// Before a remote branch's option id, telling it from a local one's.
  static const _remote = '\u0002';

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
          child: Row(children: [Flexible(child: _buildPill(context))]),
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
          icon: Codicons.folderLibrary,
          label: widget.name,
          tooltip: running ? l10n.branchBarRunning : null,
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
        icon: Codicons.gitBranch,
        label: _branchLabel(state),
        tooltip: l10n.branchBarRunning,
      );
    }
    final current = state.head.branch;
    KernelOption option(String branch) =>
        KernelOption(branch, branch, Codicons.gitBranch, '');
    final remote = _remoteGroup(context);
    return ComposerPicker(
      options: [
        for (final branch in _branchesOf(git)) option(branch),
        // Pushed by others, not here yet: checked out as a local branch.
        for (final branch in _remoteBranches[git] ?? const <String>[])
          KernelOption(
            '$_remote$branch',
            branch,
            Codicons.cloudDownload,
            '',
            group: remote,
          ),
      ],
      selected: current == null
          ? KernelOption('', l10n.branchBarDetached, Codicons.gitBranch, '')
          : option(current),
      label: _branchLabel(state),
      describes: false,
      title: l10n.branchBarSwitch,
      titleAction: _buildRefresh(context),
      searchPlaceholder: l10n.branchBarSearch,
      footer: (
        label: l10n.branchBarCreate,
        icon: Codicons.add,
        onTap: () => unawaited(
          _createBranch(
            git,
            l10n.branchBarCreateFrom(current ?? l10n.branchBarDetached),
          ),
        ),
      ),
      onSelected: (option) => option.id.startsWith(_remote)
          ? _checkoutRemote(git, option.id.substring(_remote.length))
          : _checkout(git, option.id),
    );
  }

  /// At the end of the menu's title: fetches, then reads them all again.
  Widget _buildRefresh(BuildContext context) => _RefreshButton(
    tooltip: context.l10n.branchBarRefresh,
    busy: _refreshing,
    onTap: () => unawaited(_refresh()),
  );

  /// The workspace's folders, each one's branches at its side.
  Widget _buildWorkspacePicker(BuildContext context) {
    final l10n = context.l10n;
    final gits = {for (final (folder, git) in widget.repositories) folder: git};
    // A workspace's folders are this machine's.
    String nameOf(String folder) => p.basename(folder);
    const create = KernelOptionGroup('create', '');
    final remote = _remoteGroup(context);
    return ComposerPicker(
      options: [
        for (final (folder, git) in widget.repositories)
          KernelOption(
            folder,
            nameOf(folder),
            Codicons.folder,
            switch (git.state) {
              final state? => _branchLabel(state),
              null => l10n.branchBarNotRepository,
            },
          ),
      ],
      selected: KernelOption('', widget.name, Codicons.folderLibrary, ''),
      // A line each, its branch at its end.
      descriptionAside: true,
      title: l10n.branchBarWorkspace,
      titleAction: _buildRefresh(context),
      tooltip: l10n.branchBarWorkspace,
      menuWidth: 290,
      submenuOf: (option) => switch (gits[option.id]) {
        final git? when git.isRepository => [
          for (final branch in _branchesOf(git))
            KernelOption(
              '${option.id}$_separator$branch',
              branch,
              Codicons.gitBranch,
              '',
            ),
          for (final branch in _remoteBranches[git] ?? const <String>[])
            KernelOption(
              '${option.id}$_separator$_remote$branch',
              branch,
              Codicons.cloudDownload,
              '',
              group: remote,
            ),
          KernelOption(
            '${option.id}$_separator$_create',
            l10n.branchBarCreate,
            Codicons.add,
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
        if (branch == _create) {
          unawaited(_createBranch(git, l10n.branchBarCreateIn(nameOf(folder))));
        } else if (branch.startsWith(_remote)) {
          _checkoutRemote(git, branch.substring(_remote.length));
        } else {
          _checkout(git, branch);
        }
      },
    );
  }
}

/// In the menu's title line: fetches, then reads the branch and the
/// branches again; faint while it does.
class _RefreshButton extends StatelessWidget {
  const _RefreshButton({
    required this.tooltip,
    required this.busy,
    required this.onTap,
  });

  final String tooltip;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IdeHover(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        enabled: !busy,
        child: HoverBuilder(
          cursor: busy ? MouseCursor.defer : SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            onTap: busy ? null : onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: hovered && !busy
                    ? themeColors['toolbar.hoverBackground']
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Codicons.refresh,
                size: 13,
                color: busy ? AppColors.textFaint : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
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
