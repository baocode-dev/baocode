// Source Control in a window: the repository shown and its changes'
// count and branch (the activity bar's badge, the status bar's branch),
// Source Control's sessions, the favorite branches and changelists kept with
// the window, and what opens a change, compares a file or shows its
// history (after the Git extension's commands.ts and JetBrains' Compare
// with…, Show History and Local History).

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../l10n/l10n.dart';
import '../../settings/user_settings.dart';
import '../file_service.dart';
import '../git/git_branch_actions.dart';
import '../git/git_branch_tree.dart' show IdeGitFavoriteBranches;
import '../git/git_change_editor.dart';
import '../git/git_changelists.dart';
import '../git/git_checkout.dart';
import '../git/git_model.dart';
import '../git/git_partial.dart' show IdeGitHunkSelection;
import '../git/git_repository.dart';
import '../git/ide_git_branch_popup.dart';
import '../git/ide_git_commit_panel.dart';
import '../git/ide_git_log_view.dart';
import '../git/ide_scm_view.dart';
import '../host_paths.dart';
import '../ide_agent_edits.dart';
import '../ide_dates.dart';
import '../ide_editor.dart' show IdeCompareWith;
import '../ide_folder_compare.dart';
import '../ide_local_history.dart';
import '../ide_notifications.dart';
import '../ide_quick_input.dart';
import '../ide_workspace.dart';
import '../project_tools.dart';
import '../workbench/contributions.dart';
import '../workbench/storage.dart';
import '../workbench/views.dart';
import 'git_changes.dart';

class ScmService extends ChangeNotifier implements WorkbenchStorageParticipant {
  ScmService({
    required this.host,
    required this.storage,
    this.settings,
    this._agentEdits,
  }) {
    _session = _newSession();
    favoriteBranches.addListener(storage.changed);
    changelists.addListener(storage.changed);
  }

  final WorkbenchHost host;
  final WorkbenchStorage storage;

  /// settings.json, where Source Control's dialogs keep their choices.
  final UserSettings? settings;

  /// What agents changed and is not yet kept (the workbench's, which may
  /// change), for a diff to mark.
  final IdeAgentEdits? Function()? _agentEdits;

  /// The favorite branches of the window's repositories, kept with its
  /// state.
  final IdeGitFavoriteBranches favoriteBranches = IdeGitFavoriteBranches();

  /// The changes left unchecked in the Commit panel's diffs.
  final IdeGitHunkSelection hunks = IdeGitHunkSelection();

  /// The changelists the Commit panel sorts the changes into.
  final IdeGitChangelists changelists = IdeGitChangelists();

  /// The Commit panel and the Git log, while Source Control shows.
  final panelKey = GlobalKey<IdeGitCommitPanelState>();
  final logKey = GlobalKey<IdeGitLogViewState>();

  IdeWorkspace? _workspace;
  IdeWorkspace get workspace => _workspace!;

  /// The Source Control view's message and state, while other views show.
  IdeScmSession get session => _session;
  late IdeScmSession _session;

  /// Source Control's message and state of each repository of a
  /// workspace but the one shown ([session]'s).
  final Map<IdeGitRepository?, IdeScmSession> _sessions = {};

  IdeScmSession _newSession() =>
      IdeScmSession(settings: settings, favoriteBranches: favoriteBranches);

  /// The session of [git], the one shown's or another's.
  IdeScmSession sessionOf(IdeGitRepository git) =>
      identical(git, _git) ? _session : _sessions.putIfAbsent(git, _newSession);

  /// The repository shown.
  IdeGitRepository? get git => _git;
  IdeGitRepository? _git;

  /// What the activity bar and the status bar show of [git], told only
  /// when these change: every repository's changes, and the branch (the
  /// one read from the folder before Git has it).
  int get count => _count;
  int _count = 0;
  String? get branch => _gitBranch ?? _readBranch;
  String? _gitBranch;
  String? _readBranch;

  /// The status the open revisions were last read against.
  IdeGitState? _gitState;

  final Set<IdeGitRepository> _watched = {};

  /// The diffs of the local changes, written back into the open files.
  GitChangesService get changes => _changes!;
  GitChangesService? _changes;

  // --- The workspace -------------------------------------------------------

  void attach(IdeWorkspace workspace) {
    _workspace = workspace;
    _changes = GitChangesService(
      files: workspace.files,
      notifications: workspace.notifications,
      workspace: workspace,
      agentEdits: _agentEdits,
      hunks: hunks,
    );
    _git = workspace.git?..addListener(_gitChanged);
    _gitChanged();
  }

  void detach() {
    _git?.removeListener(_gitChanged);
    for (final git in _watched) {
      git.removeListener(_repositoryChanged);
    }
    _watched.clear();
    _git = null;
    _gitState = null;
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
    _session.dispose();
    _session = _newSession();
    _workspace = null;
    _changes = null;
  }

  /// The repository shown changed (another picked, a workspace's folders
  /// changed): whether Source Control follows another.
  bool rootsChanged() {
    if (_workspace == null) return false;
    final git = workspace.git;
    if (identical(git, _git)) return false;
    _git?.removeListener(_gitChanged);
    _sessions[_git] = _session;
    _session = _sessions.remove(git) ?? _newSession();
    _git = git?..addListener(_gitChanged);
    _gitChanged();
    notifyListeners();
    return true;
  }

  /// The workspace's folder's branch, read before Git reports it (and
  /// where there is no Git).
  void readBranch() {
    final workspace = _workspace;
    if (workspace == null) return;
    final root = workspace.root;
    unawaited(
      readGitBranch(root).then((branch) {
        if (identical(_workspace, workspace) && branch != _readBranch) {
          _readBranch = branch;
          notifyListeners();
        }
      }),
    );
  }

  void _gitChanged() {
    final state = _git?.state;
    // The status bar's branch checks out once there is a repository.
    final loaded = (state == null) != (_gitState == null);
    // The texts at revisions follow the repository, as `git:` documents do.
    if (!identical(state, _gitState)) {
      _gitState = state;
      if (state != null) unawaited(workspace.reloadRevisions());
    }
    // The activity bar's badge counts every repository's changes (#68); the
    // status bar's branch, the one shown.
    _listenToRepositories();
    final count = _changesInAllRepositories;
    final branch = state?.head.branch;
    if (count == _count && branch == _gitBranch && !loaded) return;
    _count = count;
    _gitBranch = branch;
    notifyListeners();
  }

  /// Every repository's changes, or the shown one's where the workspace is
  /// one ([count]).
  int get _changesInAllRepositories {
    final repositories = workspace.repositories;
    if (repositories.length <= 1) return _git?.state?.count ?? 0;
    return repositories.fold(
      0,
      (sum, repository) => sum + (repository.$2.state?.count ?? 0),
    );
  }

  /// Follows every repository of the workspace, so a change in any of them
  /// updates the badge (#68). The shown one is followed by [_gitChanged]'s
  /// own listener.
  void _listenToRepositories() {
    final current = {for (final (_, git) in workspace.repositories) git};
    for (final git in _watched.toList()) {
      if (current.contains(git)) continue;
      git.removeListener(_repositoryChanged);
      _watched.remove(git);
    }
    for (final git in current) {
      if (_watched.add(git)) git.addListener(_repositoryChanged);
    }
  }

  void _repositoryChanged() {
    if (_workspace == null) return;
    final count = _changesInAllRepositories;
    if (count == _count) return;
    _count = count;
    notifyListeners();
  }

  // --- Storage -------------------------------------------------------------

  @override
  void restoreState(Map<String, Object?> kept) {
    changelists.restore(kept['gitChangelists']);
    if (kept['gitFavoriteBranches'] case final Object json) {
      final favorites = IdeGitFavoriteBranches.fromJson(json);
      favoriteBranches.restore(favorites);
      favorites.dispose();
    }
  }

  @override
  void saveState(Map<String, Object?> into) {
    if (!favoriteBranches.isEmpty) {
      into['gitFavoriteBranches'] = favoriteBranches.toJson();
    }
    if (changelists.several) into['gitChangelists'] = changelists.toJson();
  }

  // --- The Git log ---------------------------------------------------------

  /// The explorer's view in place of the Git log, for the editor it hides
  /// to show.
  void leaveGitLog() {
    if (host.view == IdeSideView.sourceControl) {
      host.showView(IdeSideView.explorer);
    }
  }

  /// [hash] selected in the Git log, shown in the editor's place.
  void showCommitInLog(String hash) {
    host.showView(IdeSideView.sourceControl);
    _session.log.reveal(hash);
  }

  /// Show History: the Git log of [path], a file or folder, or of [lines]
  /// of a file; the other filters go, as from a fresh log.
  void showHistory(String path, [IdeGitLogLines? lines]) {
    final git = workspace.gitAt(path);
    if (git == null) return;
    workspace.selectRepository(git);
    final log = _session.log;
    if (lines == null) log.rememberPath(path);
    log
      ..search.clear()
      ..selected = null;
    git.graphFilter = lines == null
        ? IdeGitLogFilter(paths: [path])
        : IdeGitLogFilter(lines: lines);
    host.showView(IdeSideView.sourceControl);
  }

  /// Shows [resource]'s change in the Git log's table's place, the other
  /// changes a step away (a click); in the editor, the log left, where the
  /// editor is asked for ([focusEditor]: Open Changes, Enter, a double
  /// click) and for its original ([head], Open File (HEAD)).
  Future<void> openChangeInLog(
    IdeGitResource resource, {
    bool head = false,
    bool focusEditor = false,
    List<IdeGitResource>? among,
  }) async {
    final git = _git;
    final state = git?.state;
    final context = host.context;
    if (head || focusEditor || git == null || state == null) {
      leaveGitLog();
      return openChange(resource, head: head, focusEditor: focusEditor);
    }
    if (context == null) return;
    // As Source Control lists them: its arrows and file menu step through
    // them in that order.
    final resources =
        among ??
        [for (final group in IdeGitGroup.values) ...state.group(group)];
    _session.log.showDiff(
      changes.localDiffs(
        git,
        state,
        resources,
        context.l10n,
        onOpenInEditor: (change) {
          leaveGitLog();
          unawaited(openChange(change, focusEditor: true));
        },
      ),
      // The keys go on walking the changes.
      resources.indexWhere((change) => change.path == resource.path),
      focus: false,
    );
  }

  /// Opens [resource]'s change as the Git extension does (see
  /// git_change_editor.dart): a diff editor of its two sides, or its one
  /// side; [head], its original (Open File (HEAD)).
  Future<void> openChange(
    IdeGitResource resource, {
    bool head = false,
    bool focusEditor = false,
  }) async {
    final git = _git;
    final state = git?.state;
    final context = host.context;
    if (git == null || state == null || context == null || host.editorBusy) {
      return;
    }
    final l10n = context.l10n;
    final change = IdeGitChangeEditor.of(
      resource,
      staged: state.group(IdeGitGroup.staged),
      l10n: l10n,
    );
    Future<String> Function() read(IdeGitSide side) =>
        () => git.service.show(side.ref!, side.path);
    final workspace = this.workspace;
    final left = change.left;
    final right = change.right;
    final Future<void> Function() open;
    if (head) {
      if (left == null) {
        workspace.notifications.notify(
          IdeSeverity.warning,
          l10n.wbHeadNotAvailable(hostBasename(resource.path)),
        );
        return;
      }
      open = () => workspace.openRevision(
        resource.path,
        label: 'HEAD',
        read: read(left),
      );
    } else if (right == null) {
      // Upstream's command fails without a side: the file, where it is.
      if (resource.status == IdeGitStatus.bothDeleted) return;
      open = () => workspace.open(resource.path);
    } else if (left == null) {
      // The one side: the file's own tab, or its text at a revision.
      open = right.isFile
          ? () => workspace.open(right.path)
          : () => workspace.openRevision(
              right.path,
              label: change.label,
              read: read(right),
            );
    } else {
      open = () => workspace.openDiff(
        right.path,
        label: change.label,
        original: read(left),
        modified: right.isFile ? null : read(right),
      );
    }
    await host.openEditorWith(open, focusEditor: focusEditor);
  }

  // --- Compare -------------------------------------------------------------

  /// JetBrains' Compare with Branch…, Compare with Revision… and Compare
  /// with Clipboard: [path]'s file against what is picked, in a diff tab.
  Future<void> compareWith(String path, IdeCompareWith what) async {
    final context = host.context;
    if (context == null) return;
    final l10n = context.l10n;
    final workspace = this.workspace;
    final name = hostBasename(path);
    final git = workspace.gitAt(path);
    void show(IdeQuickInputModel model) {
      if (host.context != null) host.showQuickModel(model);
    }

    try {
      switch (what) {
        case IdeCompareWith.clipboard:
          final text =
              (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
          await workspace.openDiff(
            path,
            label: l10n.compareWithClipboardLabel(name),
            original: () async => text,
          );
        case IdeCompareWith.branch:
          if (git == null) return;
          final ref = await ideGitPickRef(
            git,
            show: show,
            l10n: l10n,
            placeholder: l10n.gitCompareWithBranchPlaceholder,
          );
          if (ref == null) return;
          await workspace.openDiff(
            path,
            label: l10n.gitCompareLabel(name, ref.name),
            original: () =>
                git.service.show(ref.name, path).catchError((Object _) => ''),
          );
        case IdeCompareWith.localHistory:
          await showLocalHistory(path);
        case IdeCompareWith.revision:
          if (git == null) return;
          final commit = await ideGitPickRevision(
            git,
            path,
            show: show,
            l10n: l10n,
            placeholder: l10n.gitCompareWithRevisionPlaceholder,
          );
          if (commit == null) return;
          await workspace.openDiff(
            path,
            label: l10n.gitCompareLabel(name, commit.shortId),
            original: () =>
                git.service.show(commit.id, path).catchError((Object _) => ''),
          );
      }
    } catch (error) {
      host.report(error);
    }
  }

  /// Show Local History: the file's versions as saved, the latest first;
  /// one picked, in a diff tab against the file, to be taken back from.
  Future<void> showLocalHistory(String path) async {
    final context = host.context;
    if (context == null) return;
    final l10n = context.l10n;
    final workspace = this.workspace;
    final history = workspace.localHistory;
    if (history == null) return;
    final name = hostBasename(path);
    final List<IdeLocalVersion> versions;
    try {
      versions = await history.versionsOf(path);
    } catch (error) {
      host.report(error);
      return;
    }
    if (host.context == null) return;
    if (versions.isEmpty) {
      workspace.notifications.notify(
        IdeSeverity.info,
        l10n.localHistoryNone(name),
      );
      return;
    }
    String two(int n) => '$n'.padLeft(2, '0');
    String stamp(DateTime t) =>
        '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    final items = {
      for (final version in versions)
        IdeQuickPickItem(
          label: stamp(version.time),
          description: ideFromNow(version.time, ago: true, l10n: l10n),
        ): version,
    };
    host.showQuickModel(
      IdeQuickPick(
        placeholder: l10n.localHistoryPick(name),
        sortByLabel: false,
        items: items.keys.toList(),
        onDidAccept: (item) {
          final version = items[item];
          if (version == null) return;
          unawaited(
            workspace.openDiff(
              path,
              label: l10n.localHistoryLabel(name, stamp(version.time)),
              original: () => history.read(version),
            ),
          );
        },
      ),
    );
  }

  /// Compare Files: [original]'s text against [modified]'s. Two folders:
  /// the files they differ in, stepped through as a commit's are in the
  /// Git log's place (picked from a list outside a repository).
  Future<void> compareFiles(
    String original,
    String modified, {
    bool folders = false,
  }) async {
    final context = host.context;
    if (context == null) return;
    final l10n = context.l10n;
    final workspace = this.workspace;
    final files = workspace.files;
    if (!folders) {
      await workspace.openDiff(
        modified,
        label: l10n.compareFilesLabel(
          hostBasename(original),
          hostBasename(modified),
        ),
        original: () => files.read(original),
      );
      return;
    }
    final List<IdeFolderDifference> differences;
    try {
      differences = await ideCompareFolders(files, original, modified);
    } catch (error) {
      host.report(error);
      return;
    }
    if (host.context == null) return;
    if (differences.isEmpty) {
      workspace.notifications.notify(
        IdeSeverity.info,
        l10n.compareFoldersSame(hostBasename(original), hostBasename(modified)),
      );
      return;
    }
    String at(String folder, String path) =>
        p.joinAll([folder, ...path.split('/')]);
    Future<String> read(String path) =>
        files.read(path).catchError((Object _) => '');
    final git = workspace.gitAt(modified) ?? workspace.gitAt(original);
    if (git != null) {
      workspace.selectRepository(git);
      host.showView(IdeSideView.sourceControl);
      _session.log.showDiff([
        for (final (:path, :change) in differences)
          IdeGitDiffFile(
            path: at(
              change == IdeFolderChange.deleted ? original : modified,
              path,
            ),
            status: switch (change) {
              IdeFolderChange.added => IdeGitStatus.untracked,
              IdeFolderChange.deleted => IdeGitStatus.deleted,
              IdeFolderChange.modified => IdeGitStatus.modified,
            },
            originalLabel: hostBasename(original),
            modifiedLabel: hostBasename(modified),
            original: () async =>
                change == IdeFolderChange.added ? '' : read(at(original, path)),
            modified: () async => change == IdeFolderChange.deleted
                ? ''
                : read(at(modified, path)),
            originalBytes: ideImageSide(
              path,
              change == IdeFolderChange.added
                  ? null
                  : () => readBytesThrough(files, at(original, path)),
            ),
            modifiedBytes: ideImageSide(
              path,
              change == IdeFolderChange.deleted
                  ? null
                  : () => readBytesThrough(files, at(modified, path)),
            ),
            write: change == IdeFolderChange.deleted
                ? null
                : (text) => files.write(at(modified, path), text),
            onOpenInEditor: change == IdeFolderChange.deleted
                ? null
                : () => unawaited(host.openFile(at(modified, path))),
          ),
      ], 0);
      return;
    }
    final items = {
      for (final difference in differences)
        IdeQuickPickItem(
          label: difference.path,
          description: switch (difference.change) {
            IdeFolderChange.added => l10n.compareFoldersOnlyIn(
              hostBasename(modified),
            ),
            IdeFolderChange.deleted => l10n.compareFoldersOnlyIn(
              hostBasename(original),
            ),
            IdeFolderChange.modified => l10n.compareFoldersModified,
          },
        ): difference,
    };
    host.showQuickModel(
      IdeQuickPick(
        placeholder: l10n.compareFoldersPick(
          hostBasename(original),
          hostBasename(modified),
        ),
        sortByLabel: false,
        items: items.keys.toList(),
        onDidAccept: (item) {
          final difference = items[item];
          if (difference == null) return;
          final (:path, :change) = difference;
          unawaited(
            workspace.openDiff(
              at(change == IdeFolderChange.deleted ? original : modified, path),
              label: l10n.compareFilesLabel(
                hostBasename(original),
                hostBasename(modified),
              ),
              original: () async => change == IdeFolderChange.added
                  ? ''
                  : read(at(original, path)),
              modified: change == IdeFolderChange.deleted
                  ? () async => ''
                  : null,
            ),
          );
        },
      ),
    );
  }

  // --- Branches and the Commit panel ---------------------------------------

  /// Runs [action] on the Source Control view, shown first if it is not.
  void onScmView(void Function(IdeGitCommitPanelState view) action) {
    if (panelKey.currentState case final view?) return action(view);
    host.showView(IdeSideView.sourceControl);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (panelKey.currentState case final view?) action(view);
    });
  }

  /// Git: Checkout to… (`git.checkout`), which the status bar's branch
  /// runs too; what Git reports is an error notification.
  void checkout() {
    final git = workspace.git;
    if (git == null) return;
    checkoutOf(git);
  }

  /// Checkout to… on [git] (a repository's `...` in Source Control's
  /// REPOSITORIES, through [IdeScmView.onCheckout]).
  void checkoutOf(IdeGitRepository git) {
    final context = host.context;
    if (context == null) return;
    unawaited(
      ideGitCheckout(
        git,
        show: (model) {
          if (host.context != null) host.showQuickModel(model);
        },
        l10n: context.l10n,
      ).catchError(host.report),
    );
  }

  /// The branch popup (JetBrains') by [anchor], the status bar's branch;
  /// from the palette, at the window's top.
  void showBranchPopup([Rect? anchor]) {
    final git = workspace.git;
    final context = host.context;
    if (git == null || git.state == null || context == null) return;
    final size = MediaQuery.sizeOf(context);
    final branchHost = _BranchHost(this);
    unawaited(
      showIdeGitBranchPopup(
        context,
        git: git,
        anchor:
            anchor ??
            Rect.fromLTWH((size.width - IdeGitBranchPopup.width) / 2, 60, 0, 0),
        host: branchHost,
        actions: IdeGitBranchActions(context, git, branchHost)
            .repositoryActions(
              onCommit: () {
                host.showView(IdeSideView.sourceControl);
                logKey.currentState?.showLocalChanges();
              },
            ),
      ),
    );
  }

  /// [run] on the branch actions of the window's repository: Push…,
  /// Manage Remotes…, Update Project.
  void _branchAction(Future<void> Function(IdeGitBranchActions actions) run) {
    final git = workspace.git;
    final context = host.context;
    if (git == null || context == null) return;
    unawaited(run(IdeGitBranchActions(context, git, _BranchHost(this))));
  }

  /// Push…: the Push dialog, for the window's repositories.
  void pushDialog() => _branchAction((actions) => actions.push());

  /// Manage Remotes…, of the window's repository.
  void manageRemotes() => _branchAction((actions) => actions.manageRemotes());

  /// Update Project, on the window's repositories.
  void updateProject() => _branchAction((actions) => actions.updateProject());

  @override
  void dispose() {
    favoriteBranches.removeListener(storage.changed);
    changelists.removeListener(storage.changed);
    if (_workspace != null) detach();
    _session.dispose();
    favoriteBranches.dispose();
    hunks.dispose();
    changelists.dispose();
    super.dispose();
  }
}

/// What the branch actions do from the window: a comparison or a branch's
/// log in the Git log, shown first.
class _BranchHost implements IdeGitBranchHost {
  _BranchHost(this.scm);

  final ScmService scm;

  @override
  IdeNotifications get notifications => scm.workspace.notifications;

  @override
  IdeFileService get files => scm.workspace.files;

  @override
  IdeGitFavoriteBranches get favoriteBranches => scm.favoriteBranches;

  @override
  IdeScmSession get session => scm.session;

  @override
  List<IdeGitRepository> get repositories => [
    for (final (_, git) in scm.workspace.repositories) git,
  ];

  @override
  Future<void> run(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      scm.host.report(error);
    }
  }

  @override
  void showDiff(List<IdeGitDiffFile> files) {
    scm.host.showView(IdeSideView.sourceControl);
    scm.session.log.showDiff(files, 0);
  }

  @override
  void showOnly(IdeGitRepository git, String graphBranch) {
    scm.host.showView(IdeSideView.sourceControl);
    git.graphBranch = graphBranch;
  }
}
