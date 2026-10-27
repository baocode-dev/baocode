/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The workbench's repository, as VS Code's `Repository` keeps one: the
// status (refreshed when files change, debounced), operations run one at a
// time, and the history for the graph.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// extensions/git/src/repository.ts (`run`, `updateModelState`, the smart
// commit) and extensions/git/src/historyProvider.ts (the graph's refs: the
// current branch, its upstream, and their merge base).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'git_model.dart';
import 'git_service.dart';

/// [IdeGitRepository.graphBranch] for the current branch and its upstream.
const ideGraphCurrentBranch = 'HEAD';

/// [IdeGitRepository.graphBranch] for the commits [to] has that [from] has
/// not (`from..to`), as JetBrains IDEs' Compare with Current lists them.
String ideGraphRange(String from, String to) => '$from..$to';

/// The two ends of [graphBranch], where it is a range ([ideGraphRange]); a
/// ref's name cannot have `..` in it.
({String from, String to})? ideGraphRangeOf(String? graphBranch) {
  final at = graphBranch?.indexOf('..') ?? -1;
  if (at < 0) return null;
  return (
    from: graphBranch!.substring(0, at),
    to: graphBranch.substring(at + 2),
  );
}

class IdeGitRepository extends ChangeNotifier {
  IdeGitRepository(
    this.service, {
    this.refreshDelay = const Duration(milliseconds: 500),
  }) {
    unawaited(refresh());
  }

  final IdeGitService service;

  /// How long file changes settle before the status is read again.
  final Duration refreshDelay;

  IdeGitState? _state;
  Object? _error;
  bool _loaded = false;
  bool _disposed = false;
  Timer? _refreshTimer;
  StreamSubscription<void>? _watcher;
  Future<void> _queue = Future.value();
  Future<void>? _pendingRefresh;
  int _operations = 0;

  List<IdeGraphRow>? _graph;

  /// [_graph] is older than the status: it shows until the next load, so
  /// that a refresh changes rows rather than blanking the graph.
  bool _graphStale = false;
  Future<void>? _graphLoad;
  int _graphLimit = 50;
  bool _graphHasMore = false;

  /// The status; null before the first read and outside a repository.
  IdeGitState? get state => _state;

  /// Why the last read or operation failed.
  Object? get error => _error;

  /// Whether the status has been read once.
  bool get loaded => _loaded;

  /// Whether the project is in a repository (after [loaded]).
  bool get isRepository => _state != null;

  /// Whether an operation is running (the view's progress, and what
  /// disables the commit button). Status reads are not counted: the
  /// watcher runs them whenever a file changes, and counting them made the
  /// commit button and the progress bar flash on every edit.
  bool get busy => _operations > 0;

  /// Whether a sync or a publish is running (upstream `isSyncInProgress`).
  bool get syncing => _syncing > 0;
  int _syncing = 0;

  IdeGitDecorations? get decorations => _state?.decorations;

  /// Reads the status now; queued behind running operations. A read already
  /// queued and not yet started is the one returned unless [force] is true.
  /// Operations use a forced read so a watcher refresh that was queued while
  /// `git pull` was running cannot leave the UI showing its older state.
  Future<void> refresh({bool force = false}) {
    if (!force) {
      final pending = _pendingRefresh;
      if (pending != null) return pending;
    }
    final run = _enqueue(background: true, () async {
      if (!force) _pendingRefresh = null;
      try {
        final state = await service.status();
        if (_disposed) return;
        _state = state;
        _error = null;
        // A huge repository is not refreshed by its files' changes (VS
        // Code's `isRepositoryHuge`): each would read the status again.
        if (state?.didHitLimit ?? false) {
          _unwatch();
        } else if (state != null) {
          _watch(state.root);
        }
      } catch (error) {
        if (_disposed) return;
        _error = error;
      }
      _loaded = true;
      _graphStale = true;
      _worktreesStale = true;
      _notify();
    });
    if (!force) _pendingRefresh = run;
    return run;
  }

  /// Refreshes [refreshDelay] after the first change since the last
  /// read. Not restarted by later changes: files that keep changing (a
  /// build writing its output) would hold the status back for as long.
  void scheduleRefresh() {
    if (_disposed || (_refreshTimer?.isActive ?? false)) return;
    _refreshTimer = Timer(refreshDelay, () => unawaited(refresh()));
  }

  void _watch(String root) {
    if (_watcher != null) return;
    var working = false;
    _watcher = service
        .watch(root)
        .listen(
          (path) {
            working = true;
            // What a build or a test run writes (`build/`, `.dart_tool/`,
            // `node_modules/`): the status lists such a folder whole, so
            // nothing in it changes it. An agent's runs write there many
            // times a second, each a read of the status otherwise.
            if (path.isNotEmpty && (decorations?.ignores(path) ?? false)) {
              return;
            }
            scheduleRefresh();
          },
          // Changes were lost (the change buffer overflowed): read them.
          onError: (Object _) => scheduleRefresh(),
          // A watch that worked and ended is started again by the next read
          // (one that never worked would be started again and again).
          onDone: () {
            if (working) _watcher = null;
          },
        );
  }

  void _unwatch() {
    _refreshTimer?.cancel();
    unawaited(_watcher?.cancel());
    _watcher = null;
  }

  /// Runs [operation] after the ones queued before it; a [background]
  /// one (a status read) does not make the repository [busy].
  Future<void> _enqueue(
    Future<void> Function() operation, {
    bool background = false,
  }) {
    if (background) {
      final run = _queue.then((_) => operation());
      _queue = run.catchError((Object _) {});
      return run;
    }
    _operations++;
    _notify();
    final run = _queue.then((_) => operation()).whenComplete(() {
      _operations--;
      _notify();
    });
    _queue = run.catchError((Object _) {});
    return run;
  }

  /// Runs [operation], then refreshes; its error is kept and rethrown.
  Future<void> _operate(Future<void> Function() operation) async {
    try {
      await _enqueue(operation);
    } catch (error) {
      if (!_disposed) {
        _error = error;
        _notify();
      }
      rethrow;
    } finally {
      if (!_disposed) await refresh(force: true);
    }
  }

  /// Makes the project a repository (`git init`).
  Future<void> initialize() => _operate(service.init);

  Future<void> stage(Iterable<IdeGitResource> resources) =>
      _operate(() => service.stage([for (final r in resources) r.path]));

  Future<void> unstage(Iterable<IdeGitResource> resources) => _operate(
    () => service.unstage([
      for (final r in resources) r.path,
    ], unborn: _state?.head.unborn ?? false),
  );

  /// Resolves the conflicts of [resources] with the current side's
  /// version ([ours]) or the incoming side's; a file that side deleted is
  /// removed.
  Future<void> acceptSide(
    Iterable<IdeGitResource> resources, {
    required bool ours,
  }) => _operate(() {
    bool deletedOnSide(IdeGitStatus status) => switch (status) {
      IdeGitStatus.bothDeleted => true,
      IdeGitStatus.deletedByUs => ours,
      IdeGitStatus.deletedByThem => !ours,
      // The other side added it: this side has none.
      IdeGitStatus.addedByUs => !ours,
      IdeGitStatus.addedByThem => ours,
      _ => false,
    };
    return service.acceptSide(
      [
        for (final resource in resources)
          if (!deletedOnSide(resource.status)) resource.path,
      ],
      ours: ours,
      deleted: [
        for (final resource in resources)
          if (deletedOnSide(resource.status)) resource.path,
      ],
    );
  });

  /// Continue, Abort or Skip of the operation under way; Continue with
  /// [include] staged first (the paths checked to be committed).
  Future<void> continueOperation({
    bool abort = false,
    bool skip = false,
    Iterable<String> include = const [],
  }) => _operate(() async {
    final operation = _state?.operation;
    if (operation == null) return;
    await service.continueOperation(
      operation,
      abort: abort,
      skip: skip,
      include: include,
    );
  });

  /// Stage All Changes: everything in the working tree, untracked files
  /// included.
  Future<void> stageAll() => _operate(() => service.stage(null));

  /// Unstage All Changes.
  Future<void> unstageAll() => _operate(
    () => service.unstage(null, unborn: _state?.head.unborn ?? false),
  );

  /// Discards the changes of [resources]: untracked files go to the Trash
  /// when [trash] moves them there (VS Code's
  /// `git.discardUntrackedChangesToTrash`), else are deleted.
  Future<void> discard(
    Iterable<IdeGitResource> resources, {
    Future<bool> Function(String path)? trash,
  }) => _operate(() async {
    final rest = <IdeGitResource>[];
    for (final resource in resources) {
      if (trash != null &&
          resource.status == IdeGitStatus.untracked &&
          await trash(resource.path)) {
        continue;
      }
      rest.add(resource);
    }
    if (rest.isNotEmpty) await service.discard(rest);
  });

  /// Commits the staged changes, or with [all] every tracked change.
  Future<void> commit(
    String message, {
    bool all = false,
    bool amend = false,
    bool empty = false,
  }) => _operate(
    () => service.commit(message, all: all, amend: amend, empty: empty),
  );

  /// Commits [resources] as they are in the working tree (the files
  /// checked in the commit panel), untracked ones added first; [amend]
  /// replaces the last commit. With none, only the message is amended.
  Future<void> commitResources(
    String message,
    Iterable<IdeGitResource> resources, {
    bool amend = false,
    IdeGitCommitOptions options = const IdeGitCommitOptions(),
  }) => _operate(() async {
    final untracked = [
      for (final resource in resources)
        if (resource.status == IdeGitStatus.untracked) resource.path,
    ];
    if (untracked.isNotEmpty) await service.stage(untracked);
    await service.commitPaths(
      message,
      {
        for (final resource in resources) ...[
          resource.path,
          ?resource.originalPath,
        ],
      },
      amend: amend,
      options: options,
    );
  });

  /// Commits [resources] as [commitResources] does, and each of [partial]'s
  /// files with its text there: some of its changes, the others left in
  /// the working tree.
  Future<void> commitPartial(
    String message,
    Iterable<IdeGitResource> resources,
    Map<String, String> partial, {
    bool amend = false,
    IdeGitCommitOptions options = const IdeGitCommitOptions(),
  }) => _operate(
    () => service.commitPartial(
      message,
      {
        for (final resource in resources) ...[
          resource.path,
          ?resource.originalPath,
        ],
      },
      partial,
      amend: amend,
      options: options,
    ),
  );

  /// Rolls [resources] back to the last commit (JetBrains' Rollback):
  /// untracked files deleted, or moved to the Trash when [trash] does;
  /// files added since left untracked; the others as they were committed.
  Future<void> rollback(
    Iterable<IdeGitResource> resources, {
    Future<bool> Function(String path)? trash,
  }) => _operate(() async {
    final untracked = <IdeGitResource>[];
    final added = <String>[];
    final restored = <String>[];
    final unborn = _state?.head.unborn ?? false;
    for (final resource in resources) {
      switch (resource.status) {
        case IdeGitStatus.untracked:
          if (trash == null || !await trash(resource.path)) {
            untracked.add(resource);
          }
        case IdeGitStatus.indexAdded || IdeGitStatus.intentToAdd:
          added.add(resource.path);
        case IdeGitStatus.indexRenamed || IdeGitStatus.indexCopied:
          added.add(resource.path);
          if (resource.originalPath case final original?
              when resource.status == IdeGitStatus.indexRenamed) {
            restored.add(original);
          }
        case _ when unborn:
          added.add(resource.path);
        case _:
          restored.add(resource.path);
      }
    }
    if (added.isNotEmpty || restored.isNotEmpty) {
      await service.rollback(restored, added: added);
    }
    if (untracked.isNotEmpty) await service.discard(untracked);
  });

  /// The last commit, or null before the first.
  Future<IdeGitCommit?> headCommit() async {
    if (_state?.head.unborn ?? true) return null;
    final commits = await service.log(limit: 1);
    return commits.firstOrNull;
  }

  /// Undoes [head] (from [headCommit]), keeping its changes.
  Future<void> undoCommit(IdeGitCommit head) =>
      _operate(() => service.undoCommit(head));

  /// Cherry-picks [commits] (oldest first) onto HEAD.
  Future<void> cherryPick(List<String> commits) =>
      _operate(() => service.cherryPick(commits));

  /// Reverts [commits] (newest first), a commit each.
  Future<void> revert(List<String> commits) =>
      _operate(() => service.revert(commits));

  /// Reset Current Branch to Here.
  Future<void> reset(String commit, IdeGitResetMode mode) =>
      _operate(() => service.reset(commit, mode));

  /// New Tag at [commit].
  Future<List<IdeGitStash>> stashes() => service.stashes();

  Future<void> stash({
    String message = '',
    Iterable<String>? paths,
    bool untracked = false,
    bool keepIndex = false,
  }) => _operate(
    () => service.stash(
      message: message,
      paths: paths,
      untracked: untracked,
      keepIndex: keepIndex,
    ),
  );

  Future<void> unstash(String ref, {bool pop = false, bool index = false}) =>
      _operate(() => service.unstash(ref, pop: pop, index: index));

  Future<void> dropStash(String ref) => _operate(() => service.dropStash(ref));

  Future<void> clearStashes() => _operate(service.clearStashes);

  Future<void> stashBranch(String name, String ref) =>
      _operate(() => service.stashBranch(name, ref));

  Future<void> tag(String name, String commit, {String? message}) =>
      _operate(() => service.tag(name, commit, message: message));

  /// Edit Commit Message of [commit] in the current branch.
  Future<void> reword(IdeGitCommit commit, String message) =>
      _operate(() => service.reword(commit, message));

  /// Squash Commits: [commits] (oldest first, one after another) made one.
  Future<void> squash(List<IdeGitCommit> commits) =>
      _operate(() => service.squash(commits));

  /// Fixup: the `fixup!` commit at HEAD squashed into [commit].
  Future<void> autosquash(IdeGitCommit commit) =>
      _operate(() => service.autosquash(commit));

  /// Drop Commit: [commit] taken out of the current branch.
  Future<void> drop(IdeGitCommit commit) =>
      _operate(() => service.drop(commit));

  /// Interactively Rebase from Here: the commits from [from] on as [steps]
  /// say; true where the rebase stopped, still under way.
  Future<bool> interactiveRebase(
    IdeGitCommit from,
    List<IdeGitRebaseStep> steps,
  ) async {
    var stopped = false;
    await _operate(
      () async => stopped = await service.interactiveRebase(from, steps),
    );
    return stopped;
  }

  /// Push All up to Here: the current branch's commits up to [commit].
  Future<void> pushUpTo(String commit) => _operate(() async {
    final upstream = _state?.head.upstream;
    if (upstream == null) {
      throw const IdeGitException('The branch has no upstream.');
    }
    await service.pushUpTo(commit, upstream);
  });

  /// Stages the untracked changes too, then commits everything: VS Code's
  /// smart commit with `git.smartCommitChanges: all`. Past the status's
  /// limit, not all of them are known: the whole tree is staged.
  Future<void> commitEverything(String message) => _operate(() async {
    if (_state?.didHitLimit ?? false) {
      await service.stage(null);
      return service.commit(message, all: true);
    }
    final untracked = [
      for (final resource in _state?.resources ?? const <IdeGitResource>[])
        if (resource.status == IdeGitStatus.untracked) resource.path,
    ];
    if (untracked.isNotEmpty) await service.stage(untracked);
    await service.commit(message, all: true);
  });

  /// The remotes' names.
  Future<List<String>> remotes() => service.remotes();

  /// The branches, remote branches and tags, the last committed first.
  Future<List<IdeGitRef>> refs() => service.refs();

  /// The local branches tracking the remote branch [upstream].
  Future<List<String>> trackingBranches(String upstream) =>
      service.trackingBranches(upstream);

  // --- Branches (JetBrains' branch popup, the log's branch tree) ----------

  Future<void> renameBranch(String from, String to) =>
      _operate(() => service.renameBranch(from, to));

  /// Deletes the branch [name]; see [IdeGitService.deleteBranch].
  Future<void> deleteBranch(String name, {bool force = false}) =>
      _operate(() => service.deleteBranch(name, force: force));

  Future<void> deleteRemoteBranch(String remote, String name) =>
      _operate(() => service.deleteRemoteBranch(remote, name));

  Future<void> deleteTag(String name) =>
      _operate(() => service.deleteTag(name));

  Future<void> pushTag(String remote, String name) =>
      _operate(() => service.pushTag(remote, name));

  Future<void> deleteRemoteTag(String remote, String name) =>
      _operate(() => service.deleteRemoteTag(remote, name));

  Future<void> addRemote(String name, String url) =>
      _operate(() => service.addRemote(name, url));

  Future<void> editRemote(String name, {String? to, String? url}) =>
      _operate(() => service.editRemote(name, to: to, url: url));

  Future<void> removeRemote(String name) =>
      _operate(() => service.removeRemote(name));

  Future<void> createBranchAt(String name, String commit) =>
      _operate(() => service.createBranchAt(name, commit));

  Future<void> merge(String ref) => _operate(() => service.merge(ref));

  /// Rebases [branch] (the current one when null) onto [onto].
  Future<void> rebaseOnto(String onto, {String? branch}) =>
      _operate(() => service.rebaseOnto(onto, branch: branch));

  /// Pulls the remote branch [ref] (`origin/main`) into the current one.
  Future<void> pullInto(String ref, {required bool rebase}) =>
      _whileSyncing(() async {
        final (remote, name) = splitUpstream(ref, await service.remotes());
        await service.pullInto(remote, name, rebase: rebase);
      });

  /// The Push dialog's push: the current branch to [target] on [remote],
  /// made its upstream where it has none; [force] with lease (the remote
  /// branch only overwritten as last fetched); [tags], the annotated tags
  /// of the commits pushed.
  Future<void> pushTo(
    String remote,
    String target, {
    bool force = false,
    bool tags = false,
  }) => _whileSyncing(() async {
    final head = _state?.head;
    final branch = head?.branch;
    if (branch == null) {
      throw const IdeGitException('HEAD is on no branch: nothing to push.');
    }
    await service.push(
      remote,
      '$branch:$target',
      setUpstream: head?.upstream == null,
      forceWithLease: force,
      followTags: tags,
    );
  });

  /// Update Project: fetches from every remote, then brings the current
  /// branch up to its upstream, by rebase or by merge, local changes
  /// stashed meanwhile. Throws where the branch has no upstream.
  Future<void> updateProject({required bool rebase}) => _whileSyncing(() async {
    await service.fetch();
    final (remote, name) = await _upstream('update');
    await service.pullInto(remote, name, rebase: rebase);
  });

  /// Fast-forwards the branch [name], not checked out, to [upstream].
  Future<void> updateBranch(String name, String upstream) =>
      _whileSyncing(() => service.updateBranch(name, upstream));

  /// Pushes the branch [name]: to its [upstream] (`remote/branch`), else
  /// to [remote] as its upstream (`git push -u`).
  Future<void> pushBranch(String name, {String? upstream, String? remote}) =>
      _whileSyncing(() async {
        final remotes = await service.remotes();
        if (upstream != null) {
          final (to, branch) = splitUpstream(upstream, remotes);
          await service.push(to, '$name:$branch');
          return;
        }
        final to =
            remote ??
            (remotes.contains('origin') ? 'origin' : remotes.firstOrNull);
        if (to == null) throw const IdeGitException('There is no remote.');
        await service.push(to, '$name:$name', setUpstream: true);
      });

  Future<void> setUpstream(String name, String? upstream) =>
      _operate(() => service.setUpstream(name, upstream));

  /// Checks [treeish] out (`Repository.checkout`); [detached] detaches HEAD
  /// there.
  Future<void> checkout(String treeish, {bool detached = false}) =>
      _operate(() => service.checkout(treeish, detached: detached));

  /// Checks the remote branch [treeish] out as a new branch tracking it
  /// (`Repository.checkoutTracking`).
  Future<void> checkoutTracking(String treeish) =>
      _operate(() => service.checkout(treeish, track: true));

  /// Creates the branch [name] at [ref] and checks it out
  /// (`Repository.branch`).
  Future<void> branch(String name, {String? ref}) =>
      _operate(() => service.branch(name, ref: ref));

  /// Runs [operation] as [_operate] does, [syncing] from its asking until
  /// the refresh after it.
  Future<void> _whileSyncing(Future<void> Function() operation) async {
    _syncing++;
    _notify();
    try {
      await _operate(operation);
    } finally {
      _syncing--;
      _notify();
    }
  }

  /// Sync Changes (`Repository.sync`): pulls the branch's upstream, then
  /// pushes to it, if the branch was ahead of it.
  Future<void> sync() => _whileSyncing(() async {
    final head = _state?.head;
    final branch = head?.branch;
    final upstream = head?.upstream;
    if (head == null || branch == null || upstream == null) return;
    final (remote, name) = splitUpstream(upstream, await service.remotes());
    await service.pull(remote, name);
    if (head.ahead > 0) await service.push(remote, '$branch:$name');
  });

  /// Git: Fetch (`Repository.fetch`), or from every remote
  /// (`Repository.fetchAll`, which the title bar's Fetch From All Remotes
  /// runs) when [remote] is null.
  Future<void> fetch({String? remote}) =>
      _operate(() => service.fetch(remote: remote));

  /// Git: Pull (`Repository.pull`): pulls the branch's upstream. Throws
  /// when the branch has none (`Repository.pull`'s "no tracking
  /// information" message), for the view to report.
  Future<void> pull() => _operate(() async {
    final (remote, name) = await _upstream('pull');
    await service.pull(remote, name);
  });

  /// Git: Push (`Repository.push`): pushes the branch to its upstream.
  /// Throws when the branch has none.
  Future<void> push() => _operate(() async {
    final branch = _state?.head.branch;
    final (remote, name) = await _upstream('push');
    await service.push(remote, '$branch:$name');
  });

  /// The branch's upstream as (remote, remote branch), or an error saying
  /// there is none to [action] from or to.
  Future<(String, String)> _upstream(String action) async {
    final branch = _state?.head.branch;
    final upstream = _state?.head.upstream;
    if (branch == null || upstream == null) {
      throw IdeGitException(
        'There is no tracking information for the current branch: '
        'nothing to $action.',
      );
    }
    return splitUpstream(upstream, await service.remotes());
  }

  /// Publish Branch to [remote] (`Repository.pushTo`, setting the
  /// upstream).
  Future<void> publish(String remote) => _whileSyncing(() async {
    final branch = _state?.head.branch;
    if (branch == null) return;
    await service.push(remote, branch, setUpstream: true);
  });

  /// [upstream] (`origin/feature/x`) as its remote and the remote's branch:
  /// the longest of [remotes] it begins with, else up to its first slash.
  static (String, String) splitUpstream(String upstream, List<String> remotes) {
    String? remote;
    for (final name in remotes) {
      if (upstream.startsWith('$name/') &&
          name.length > (remote?.length ?? -1)) {
        remote = name;
      }
    }
    remote ??= upstream.split('/').first;
    return (
      remote,
      upstream.substring(math.min(upstream.length, remote.length + 1)),
    );
  }

  /// The graph's rows, loaded on first use; null while first loading.
  /// After a refresh, the last rows until the new ones have loaded.
  List<IdeGraphRow>? get graph {
    if ((_graph == null || _graphStale) && _graphLoad == null && isRepository) {
      _reloadGraph();
    }
    return _graph;
  }

  /// Whether older commits can be loaded ([loadMoreGraph]).
  bool get graphHasMore => _graphHasMore;

  /// Whose commits the graph has: every branch's, local and remote (null);
  /// the current branch's and its upstream's ([ideGraphCurrentBranch]);
  /// one branch's, by its ref (`refs/heads/main`); or those one has that
  /// another has not ([ideGraphRange]).
  String? get graphBranch => _graphBranch;
  String? _graphBranch;
  set graphBranch(String? value) {
    if (value == _graphBranch) return;
    _graphBranch = value;
    _reloadGraphFor();
  }

  /// Which of their commits it has.
  IdeGitLogFilter get graphFilter => _graphFilter;
  IdeGitLogFilter _graphFilter = const IdeGitLogFilter();
  set graphFilter(IdeGitLogFilter value) {
    if (value == _graphFilter) return;
    _graphFilter = value;
    _reloadGraphFor();
  }

  /// Newest first by date rather than in topological order.
  bool get graphDateOrder => _graphDateOrder;
  bool _graphDateOrder = false;
  set graphDateOrder(bool value) {
    if (value == _graphDateOrder) return;
    _graphDateOrder = value;
    _reloadGraphFor();
  }

  /// Loads the graph again for what it now has: after a load that started
  /// with the others, another.
  void _reloadGraphFor() {
    _graphStale = true;
    unawaited(_graphLoad ?? _reloadGraph());
    _notify();
  }

  Future<void> loadMoreGraph() {
    _graphLimit += 50;
    // After a load that started with the smaller limit, another.
    _graphStale = true;
    return _graphLoad ?? _reloadGraph();
  }

  Future<void> _reloadGraph() {
    // A refresh from now on needs another load.
    _graphStale = false;
    return _graphLoad = _loadGraph().whenComplete(() => _graphLoad = null);
  }

  Future<void> _loadGraph() async {
    final state = _state;
    if (state == null || state.head.unborn) {
      _graph = const [];
      _notify();
      return;
    }
    try {
      final head = state.head;
      final headRef = head.branch == null ? null : 'refs/heads/${head.branch}';
      final remoteRef = head.upstream == null
          ? null
          : 'refs/remotes/${head.upstream}';
      final headRevision = await service.revParse('HEAD');
      final remoteRevision = remoteRef == null
          ? null
          : await service.revParse(remoteRef);
      final mergeBase = headRevision != null && remoteRevision != null
          ? await service.mergeBase(headRevision, remoteRevision)
          : null;
      final commits = await service.log(
        refs: switch (_graphBranch) {
          null => const ['HEAD', '--branches', '--remotes'],
          ideGraphCurrentBranch => ['HEAD', ?remoteRef],
          final ref => [ref],
        },
        limit: _graphLimit + 1,
        filter: _graphFilter,
        dateOrder: _graphDateOrder,
      );
      if (_disposed) return;
      _graphHasMore = commits.length > _graphLimit;
      _graph = ideGraphRows(
        commits.take(_graphLimit).toList(),
        headRef: headRef,
        headRevision: headRevision,
        remoteRef: remoteRef,
        remoteRevision: remoteRevision,
        mergeBase: mergeBase,
        headName: head.branch,
        remoteName: head.upstream,
      );
    } catch (error) {
      if (_disposed) return;
      _graph = const [];
      _error = error;
    }
    _notify();
  }

  /// The repository's working trees, its own first; read as they are
  /// asked for, again after each status read (one may have been added or
  /// removed meanwhile). Empty until read, or where Git cannot tell.
  List<IdeGitWorktree> get worktrees {
    if (_worktreesStale && _worktreesLoad == null && isRepository) {
      _worktreesStale = false;
      _worktreesLoad = _loadWorktrees().whenComplete(
        () => _worktreesLoad = null,
      );
    }
    return _worktrees;
  }

  List<IdeGitWorktree> _worktrees = const [];
  bool _worktreesStale = true;
  Future<void>? _worktreesLoad;

  Future<void> _loadWorktrees() async {
    List<IdeGitWorktree> worktrees;
    try {
      worktrees = await service.worktrees();
    } catch (_) {
      worktrees = const [];
    }
    if (_disposed || listEquals(worktrees, _worktrees)) return;
    _worktrees = worktrees;
    _notify();
  }

  /// Adds a working tree at [path] ([IdeGitService.addWorktree]), and
  /// reads the worktrees again.
  Future<void> addWorktree(
    String path, {
    String? newBranch,
    String? branch,
  }) async {
    await _operate(
      () => service.addWorktree(path, newBranch: newBranch, branch: branch),
    );
    await reloadWorktrees();
  }

  /// Reads the worktrees again now (one was just made where the agent
  /// works).
  Future<void> reloadWorktrees() {
    _worktreesStale = false;
    return _worktreesLoad ??= _loadWorktrees().whenComplete(
      () => _worktreesLoad = null,
    );
  }

  /// [path]'s commits, newest first (the timeline).
  Future<List<IdeGitCommit>> fileHistory(String path) async {
    if (!isRepository) return const [];
    return service.fileLog(path);
  }

  Future<List<IdeGitCommitChange>> commitChanges(String commit) =>
      service.commitChanges(commit);

  /// The lines [commit] added and deleted in each of its files.
  Future<Map<String, ({int? added, int? deleted})>> commitStats(
    String commit,
  ) => service.commitStats(commit);

  /// The branches that have [commit].
  Future<List<String>> branchesContaining(String commit) =>
      service.branchesContaining(commit);

  /// The user's email as Git commits with it (`user.email`), read once.
  Future<String?> get userEmail => _userEmail ??= service
      .config('user.email')
      .catchError((Object _) => null);
  Future<String?>? _userEmail;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    unawaited(_watcher?.cancel());
    super.dispose();
  }
}
