part of 'ide_git_log_view.dart';

// The branch tree beside the Git log, as JetBrains IDEs have it: HEAD, the
// local branches, the remote ones and the tags, favorites first. A branch
// pressed selects its tip in the log; pressed twice, the log shows it
// alone; its menu has what JetBrains' branch popup has for it: checkout,
// a branch from it, compare, merge, rebase, pull, update, push, rename,
// delete.

extension _Branches on IdeGitLogViewState {
  /// The tree, [refs] once read.
  Widget _branchPane(IdeGitRepository git) => _BranchPane(
    git: git,
    log: _log,
    border: _border,
    onPressed: (ref) => _showRef(git, ref),
    onDoublePressed: (ref) => git.graphBranch = ref.id,
    menu: (ref, refs) => _branchMenu(git, ref, refs),
  );

  /// [ref]'s tip selected in the log; where the log has not loaded it, the
  /// log of [ref] alone, its tip first.
  void _showRef(IdeGitRepository git, IdeGitRef ref) {
    final commit = ref.commit;
    if (commit == null) return;
    if (_ids(git).contains(commit)) {
      _select(commit, reveal: true);
      return;
    }
    git.graphBranch = ref.id;
    _log.reveal(commit);
  }

  /// [ref]'s actions, as the branch popup has them, and the log's own.
  List<IdeMenuEntry> _branchMenu(
    IdeGitRepository git,
    IdeGitRef ref,
    List<IdeGitRef> refs,
  ) => IdeGitBranchActions(
    context,
    git,
    _LogBranchHost(this),
  ).menu(ref, refs, showOnly: git.graphBranch == ref.id);
}

/// What the branch actions do in the log: a comparison in the table's
/// place, the operations as the log's.
class _LogBranchHost implements IdeGitBranchHost {
  _LogBranchHost(this.view);

  final IdeGitLogViewState view;

  @override
  IdeNotifications get notifications => view.widget.notifications;

  @override
  IdeFileService get files => view.widget.host.files;

  @override
  IdeGitFavoriteBranches get favoriteBranches => view._log.favoriteBranches;

  @override
  IdeScmSession get session => view.widget.session;

  @override
  List<IdeGitRepository> get repositories => [?view._git];

  @override
  Future<void> run(Future<void> Function() operation) => view._run(operation);

  @override
  void showDiff(List<IdeGitDiffFile> files) => view._log.showDiff(files, 0);

  @override
  void showOnly(IdeGitRepository git, String graphBranch) =>
      git.graphBranch = graphBranch;
}

/// The branch tree: a filter over HEAD's branch, the local branches, the
/// remote ones and the tags.
class _BranchPane extends StatefulWidget {
  const _BranchPane({
    required this.git,
    required this.log,
    required this.border,
    required this.onPressed,
    required this.onDoublePressed,
    required this.menu,
  });

  final IdeGitRepository git;
  final IdeGitLogController log;
  final Color border;
  final ValueChanged<IdeGitRef> onPressed;
  final ValueChanged<IdeGitRef> onDoublePressed;
  final List<IdeMenuEntry> Function(IdeGitRef ref, List<IdeGitRef> refs) menu;

  @override
  State<_BranchPane> createState() => _BranchPaneState();
}

class _BranchPaneState extends State<_BranchPane> {
  List<IdeGitRef>? _refs;

  /// The status the refs were read for: read again at each.
  IdeGitState? _readFor;
  IdeGitRepository? _readFrom;
  int _request = 0;

  final ScrollController _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _read() {
    final git = widget.git;
    final state = git.state;
    if (identical(state, _readFor) && identical(git, _readFrom)) return;
    if (!identical(git, _readFrom)) _refs = null;
    _readFor = state;
    _readFrom = git;
    final request = ++_request;
    git.refs().then(
      (refs) {
        if (mounted && request == _request) setState(() => _refs = refs);
      },
      onError: (Object _) {
        if (mounted && request == _request) setState(() => _refs = const []);
      },
    );
  }

  String _groupLabel(IdeGitBranchGroup group) {
    final l10n = context.l10n;
    return switch (group) {
      IdeGitBranchGroup.head => l10n.gitBranchesHead,
      IdeGitBranchGroup.local => l10n.gitLogLocalBranches,
      IdeGitBranchGroup.remote => l10n.gitLogRemoteBranches,
      IdeGitBranchGroup.tags => l10n.gitLogTags,
    };
  }

  @override
  Widget build(BuildContext context) {
    _read();
    final l10n = context.l10n;
    final log = widget.log;
    final git = widget.git;
    final refs = _refs;
    final rows = refs == null
        ? const <IdeGitBranchRow>[]
        : ideGitBranchRows(
            refs,
            current: git.state?.head.branch,
            favorites: log.favoriteBranches.of(git.service.root),
            folded: log.foldedBranches,
            filter: log.branchFilter.text,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: IdeInputBox(
            controller: log.branchFilter,
            placeholder: l10n.gitBranchesFilter,
            onChanged: (_) => log.branchFilterChanged(),
          ),
        ),
        Expanded(
          child: refs == null
              ? const SizedBox.shrink()
              : ListView.builder(
                  controller: _scroll,
                  itemExtent: 22,
                  itemCount: rows.length,
                  itemBuilder: (context, index) => _row(rows[index], refs, git),
                ),
        ),
      ],
    );
  }

  Widget _row(IdeGitBranchRow row, List<IdeGitRef> refs, IdeGitRepository git) {
    final log = widget.log;
    final indent = 4.0 + row.depth * 12;
    final ref = row.ref;
    if (ref == null) {
      final expanded = row.expanded ?? true;
      return IdeListRow(
        height: 22,
        onTap: () => log.toggleBranchFolder(row.key),
        builder: (context, _) => Row(
          children: [
            SizedBox(width: indent),
            Icon(
              expanded ? Codicons.chevronDown : Codicons.chevronRight,
              size: 16,
              color: IdeListColors.foreground,
            ),
            const SizedBox(width: 2),
            if (row.group == null) ...[
              Icon(
                row.depth == 1 && row.key.startsWith('remote/')
                    ? Codicons.cloud
                    : Codicons.folder,
                size: 14,
                color: IdeListColors.description,
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                row.group == null ? row.label : _groupLabel(row.group!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: IdeListColors.foreground,
                  fontWeight: row.group == null ? null : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final current =
        ref.kind == IdeGitRefKind.branch && ref.name == git.state?.head.branch;
    final favorite = row.favorite;
    final track = [
      if ((ref.ahead ?? 0) > 0) '↑${ref.ahead}',
      if ((ref.behind ?? 0) > 0) '↓${ref.behind}',
    ].join(' ');
    return IdeListRow(
      height: 22,
      selected: log.branchSelected == row.key,
      tooltip: [
        ref.name,
        if (ref.upstream case final upstream?) '→ $upstream',
        if (ref.details case final details?) details.subject,
      ].join('\n'),
      onTap: () {
        log.branchSelected = row.key;
        widget.onPressed(ref);
      },
      onDoubleTap: () => widget.onDoublePressed(ref),
      onContextMenu: (position) {
        log.branchSelected = row.key;
        unawaited(
          showIdeMenu(
            context,
            position: position,
            entries: widget.menu(ref, refs),
          ),
        );
      },
      builder: (context, hovered) => Row(
        children: [
          SizedBox(width: indent + 18),
          Icon(
            ref.kind == IdeGitRefKind.tag ? Codicons.tag : Codicons.gitBranch,
            size: 14,
            color: current
                ? themeColors['gitDecoration.addedResourceForeground']
                : IdeListColors.description,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: IdeListColors.foreground,
                fontWeight: current ? FontWeight.w600 : null,
              ),
            ),
          ),
          if (track.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              track,
              style: TextStyle(fontSize: 11, color: IdeListColors.description),
            ),
          ],
          if (favorite || hovered)
            IdeActionButton(
              icon: favorite ? Codicons.starFull : Codicons.starEmpty,
              tooltip: favorite
                  ? context.l10n.gitBranchUnfavorite
                  : context.l10n.gitBranchFavorite,
              size: 20,
              iconSize: 14,
              color: favorite
                  ? themeColors.get('charts.yellow') ?? IdeListColors.foreground
                  : null,
              onPressed: () => log.toggleFavorite(git, ref.id),
            )
          else
            const SizedBox(width: 20),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
