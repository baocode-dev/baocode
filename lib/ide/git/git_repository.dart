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
          (_) {
            working = true;
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

  /// The last commit, or null before the first.
  Future<IdeGitCommit?> headCommit() async {
    if (_state?.head.unborn ?? true) return null;
    final commits = await service.log(limit: 1);
    return commits.firstOrNull;
  }

  /// Undoes [head] (from [headCommit]), keeping its changes.
  Future<void> undoCommit(IdeGitCommit head) =>
      _operate(() => service.undoCommit(head));

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
        refs: ['HEAD', ?remoteRef],
        limit: _graphLimit + 1,
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

  /// [path]'s commits, newest first (the timeline).
  Future<List<IdeGitCommit>> fileHistory(String path) async {
    if (!isRepository) return const [];
    return service.fileLog(path);
  }

  Future<List<IdeGitCommitChange>> commitChanges(String commit) =>
      service.commitChanges(commit);

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
