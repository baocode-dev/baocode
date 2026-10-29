/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The Git commands the workbench runs, as VS Code's Git extension runs
// them (extensions/git/src/git.ts at 6a598d4a13031703d483d103c1d934a36ad27971):
// status with the branch and ignored paths, add, restore (or the older
// reset, see `unstage`), checkout, clean, commit, log for the graph and the
// timeline, show for the texts a diff editor compares (`buffer`), blame for
// the editor's blame (`blame2`), fetch (one remote or all), pull and push
// for the actions, and for-each-ref, checkout and checkout -b for Checkout
// to… (`getRefs`, `findTrackingBranches`, `checkout`, `branch`).
//
// Deviations: no stash, and no credential prompts
// (`GIT_TERMINAL_PROMPT=0`: a remote that asks for a password fails).

import 'package:bao_remote/git.dart';
import 'package:path/path.dart' as p;

import 'git_model.dart';
import 'git_service_stub.dart'
    if (dart.library.io) 'git_service_io.dart'
    as platform;

export 'package:bao_remote/git.dart';

/// Runs `git` with [arguments] in [workingDirectory]; with [limit], reads
/// only that many NUL-terminated records of its output (`runGit`'s); [stdin]
/// is written to it, and [environment] added to its.
typedef IdeGitRunner = Future<IdeGitOutput> Function(
  List<String> arguments, {
  required String workingDirectory,
  int? limit,
  String? stdin,
  Map<String, String>? environment,
});

/// Changes under the repository at [repositoryRoot], each the path changed
/// ('' where not known).
typedef IdeGitWatcher = Stream<String> Function(String repositoryRoot);

/// `git --version`'s output (`git version 2.23.0.windows.1`, `git version
/// 2.39.2 (Apple Git-143)`) as (major, minor); null when it cannot be read
/// (an unexpected spelling).
(int, int)? parseGitVersion(String output) {
  final match = RegExp(r'(\d+)\.(\d+)').firstMatch(output);
  return match == null ? null : (int.parse(match[1]!), int.parse(match[2]!));
}

/// A file a commit changed.
class IdeGitCommitChange {
  const IdeGitCommitChange(this.path, this.status, {this.originalPath});

  final String path;
  final String? originalPath;

  /// `A`, `M`, `D`, `R`, `C` or `T`.
  final String status;
}

/// Git for the repository containing [root]; [runner] and [watcher]
/// replace running `git` and watching the files (for tests, and a remote
/// host's), [pathContext] how the host Git runs on spells paths (a Linux
/// or macOS host's from Windows).
class IdeGitService {
  IdeGitService(
    String root, {
    IdeGitRunner? runner,
    IdeGitWatcher? watcher,
    p.Context? pathContext,
  }) : pathContext = pathContext ?? p.context,
       root = (pathContext ?? p.context).normalize(root),
       _run = runner ?? platform.runGit,
       _watch = watcher ?? platform.watchRepository;

  final p.Context pathContext;
  final String root;
  final IdeGitRunner _run;
  final IdeGitWatcher _watch;
  String? _repositoryRoot;

  /// Changes under the repository, for refreshing; empty where files cannot
  /// be watched.
  Stream<String> watch(String repositoryRoot) => _watch(repositoryRoot);

  Future<IdeGitOutput> _git(
    List<String> arguments, {
    String? cwd,
    int? limit,
    String? stdin,
    Map<String, String>? environment,
  }) => _run(
    arguments,
    workingDirectory: cwd ?? _repositoryRoot ?? root,
    limit: limit,
    stdin: stdin,
    environment: environment,
  );

  /// JetBrains' Get from Version Control: [url] cloned into [directory],
  /// which Git makes; on this machine, or through [runner]. No prompt for
  /// a password waits on a terminal there is none of.
  static Future<void> clone(
    String url,
    String directory, {
    IdeGitRunner? runner,
    p.Context? pathContext,
  }) async {
    final paths = pathContext ?? p.context;
    _check(
      await (runner ?? platform.runGit)(
        ['clone', '--', url, directory],
        workingDirectory: paths.dirname(directory),
        environment: const {'GIT_TERMINAL_PROMPT': '0'},
      ),
      'Cannot clone $url.',
    );
  }

  static IdeGitOutput _check(IdeGitOutput output, String what) {
    if (output.exitCode == 0) return output;
    // What a failure says, some of Git's commands say on their output.
    final error = switch (output.stderr.trim()) {
      '' => output.stdout.trim(),
      final error => error,
    };
    final detail = error.length > 500 ? '${error.substring(0, 500)}…' : error;
    throw IdeGitException(detail.isEmpty ? what : '$what\n$detail');
  }

  /// The repository's top level, or null when [root] is not in one.
  Future<String?> repositoryRoot() async {
    if (_repositoryRoot case final known?) return known;
    final output = await _git(['rev-parse', '--show-toplevel'], cwd: root);
    if (output.exitCode != 0) return null;
    final top = output.stdout.trim();
    if (top.isEmpty) return null;
    return _repositoryRoot = pathContext.normalize(top);
  }

  /// The folders of the submodules of the repository [root] is in, as its
  /// `.gitmodules` names them (upstream's `git.detectSubmodules` reads the
  /// same); none where it has none, or Git cannot say.
  Future<List<String>> submodulePaths() async {
    try {
      // The top level from [root] as [root] is spelled (`--show-toplevel`
      // resolves links, which [root] may go through).
      final cdup = await _git(['rev-parse', '--show-cdup'], cwd: root);
      if (cdup.exitCode != 0) return const [];
      final up = cdup.stdout.trim();
      final top = pathContext.normalize(pathContext.join(root, up));
      final output = await _git([
        'config',
        '-z',
        '--file',
        up.isEmpty ? '.gitmodules' : '$up.gitmodules',
        '--get-regexp',
        r'^submodule\..*\.path$',
      ], cwd: root);
      if (output.exitCode != 0) return const [];
      // `-z`: each `key` newline `value`, then a NUL.
      return [
        for (final entry in output.stdout.split('\x00'))
          if (entry.indexOf('\n') case final newline when newline >= 0)
            pathContext.joinAll([
              top,
              ...entry.substring(newline + 1).split('/'),
            ]),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Whether [root] is a working tree's top level, not a folder in one
  /// (nor a bare repository): what finds the repositories of a folder's
  /// subfolders. Asked by the path's prefix in the tree, which is empty
  /// at its top, where the top level would be spelled with links resolved.
  Future<bool> isRepositoryTop() async {
    try {
      final output = await _git([
        'rev-parse',
        '--is-inside-work-tree',
        '--show-prefix',
      ], cwd: root);
      if (output.exitCode != 0) return false;
      final lines = output.stdout.split('\n');
      return lines.first.trim() == 'true' &&
          (lines.length < 2 || lines[1].trim().isEmpty);
    } catch (_) {
      // Git missing, or the folder gone.
      return false;
    }
  }

  Future<String> _requireRoot() async {
    final top = await repositoryRoot();
    if (top == null) throw const IdeGitException('Not a Git repository.');
    return top;
  }

  List<String> _relative(String top, Iterable<String> paths) => [
    for (final path in paths)
      pathContext.relative(path, from: top).replaceAll(r'\', '/'),
  ];

  /// [paths] relative to [top], or the whole tree (`.`) for none: long
  /// lists of paths are not passed on the command line.
  List<String> _pathspec(String top, Iterable<String>? paths) =>
      paths == null ? const ['.'] : _relative(top, paths);

  /// `git init` in [root]: Initialize Repository.
  Future<void> init() async {
    _check(
      await _git(['init'], cwd: root),
      'Cannot initialize the repository.',
    );
  }

  /// How many changes the status reads at most (VS Code's
  /// `git.statusLimit`): a folder with a huge untracked tree (a home
  /// folder made a repository) has hundreds of thousands, too many to read,
  /// keep and show.
  static const statusLimit = 10000;

  /// The status, or null outside a repository: at most [statusLimit]
  /// records, [IdeGitState.didHitLimit] when there were more.
  ///
  /// Gits before 2.16 have no `--ignored=matching`, and their plain
  /// `--ignored` lists each file of an ignored folder (`node_modules`): the
  /// ignored paths are listed apart, folders whole, as `!!` records (#311).
  Future<IdeGitState?> status() async {
    final top = await repositoryRoot();
    if (top == null) return null;
    final version = await _gitVersion();
    final matching = version == null || _atLeast(version, 2, 16);
    // Read alongside the status.
    final operation = _operation().catchError((Object _) => null);
    final output = _check(
      await _git(
        [
          'status',
          '-z',
          // v1, spelled as Gits before 2.11 know it.
          '--porcelain',
          '--branch',
          '--untracked-files=all',
          if (matching) '--ignored=matching',
        ],
        // And the branch's.
        limit: statusLimit + 1,
      ),
      'Cannot read the Git status.',
    );
    var records = output.stdout;
    if (!matching && !output.truncated) {
      final ignored = await _git([
        'ls-files',
        '-z',
        '--others',
        '--ignored',
        '--exclude-standard',
        '--directory',
      ], limit: statusLimit);
      if (ignored.exitCode == 0) {
        records += [
          for (final path in ignored.stdout.split('\x00'))
            if (path.isNotEmpty) '!! $path\x00',
        ].join();
      }
    }
    return parseGitStatus(
      top,
      records,
      truncated: output.truncated,
      pathContext: pathContext,
      operation: await operation,
    );
  }

  /// The operation Git stopped in the middle of, by the pseudo-refs it
  /// leaves: one `git log` of those there are (`--ignore-missing`), each
  /// by its name (`%S`).
  Future<IdeGitOperation?> _operation() async {
    final output = await _git([
      'log',
      '--no-walk',
      '--source',
      '--ignore-missing',
      '--format=%S',
      for (final operation in IdeGitOperation.values) operation.ref,
      '--',
    ]);
    if (output.exitCode != 0) return null;
    final refs = output.stdout.split('\n').map((line) => line.trim()).toSet();
    // A rebase that stopped on a merge also has MERGE_HEAD: the rebase is
    // what goes on.
    for (final operation in const [
      IdeGitOperation.rebase,
      IdeGitOperation.cherryPick,
      IdeGitOperation.revert,
      IdeGitOperation.merge,
    ]) {
      if (!refs.contains(operation.ref)) continue;
      if (operation == IdeGitOperation.rebase && !await _rebasing()) continue;
      return operation;
    }
    return null;
  }

  /// Whether a rebase is under way, REBASE_HEAD there: Git (2.50) leaves
  /// it once the rebase is done, which goes by its folder, `rebase-merge`
  /// (or `rebase-apply`, `rebasing` in it: not `git am`'s). Read by Git
  /// (`hash-object`, which fails on a file not there), the repository
  /// being where Git runs. One that cannot be told is taken to be.
  Future<bool> _rebasing() async {
    final paths = await _git([
      'rev-parse',
      '--git-path',
      'rebase-merge/head-name',
      '--git-path',
      'rebase-apply/rebasing',
    ]);
    if (paths.exitCode != 0) return true;
    for (final path in paths.stdout.split('\n')) {
      if (path.trim().isEmpty) continue;
      if ((await _git(['hash-object', '--', path.trim()])).exitCode == 0) {
        return true;
      }
    }
    return false;
  }

  /// Resolves the conflicts of [paths] with one side's version: the
  /// current one's (`--ours`) or the incoming one's (`--theirs`), staged;
  /// [deleted], those that side deleted, removed.
  Future<void> acceptSide(
    Iterable<String> paths, {
    required bool ours,
    Iterable<String> deleted = const [],
  }) async {
    final top = await _requireRoot();
    final kept = _relative(top, paths);
    if (kept.isNotEmpty) {
      _check(
        await _git(['checkout', ours ? '--ours' : '--theirs', '--', ...kept]),
        'Cannot take ${ours ? 'the current' : 'the incoming'} version.',
      );
      _check(
        await _git(['add', '--', ...kept]),
        'Cannot mark the conflicts resolved.',
      );
    }
    final removed = _relative(top, deleted);
    if (removed.isNotEmpty) {
      _check(
        await _git(['rm', '-q', '--', ...removed]),
        'Cannot mark the conflicts resolved.',
      );
    }
  }

  /// Goes on with [operation] (`--continue`), its conflicts resolved and
  /// staged, [include] staged first (what is checked to be committed, as
  /// Commit takes it); or aborts it (`--abort`), or skips the commit it
  /// stopped on (`--skip`).
  Future<void> continueOperation(
    IdeGitOperation operation, {
    bool abort = false,
    bool skip = false,
    Iterable<String> include = const [],
  }) async {
    final top = await _requireRoot();
    final going = !abort && !skip;
    final failed =
        'Cannot ${abort
            ? 'abort'
            : skip
            ? 'skip'
            : 'continue'} the '
        '${operation.command}.';
    final staged = going ? _relative(top, include) : const <String>[];
    if (staged.isNotEmpty) {
      _check(await _git(['add', '-A', '--', ...staged]), failed);
    }
    final output = await _git([
      // Its commit's message as it is: no editor.
      '-c',
      'core.editor=:',
      operation.command,
      abort
          ? '--abort'
          : skip
          ? '--skip'
          : '--continue',
    ]);
    // A rebase goes on only from a clean tree; Git says so as if the
    // conflicts were not resolved.
    if (output.exitCode != 0 &&
        going &&
        operation == IdeGitOperation.rebase &&
        (await _git(['diff', '--quiet'])).exitCode == 1) {
      throw IdeGitException(
        '$failed\nChanges not checked to be committed are left: a rebase '
        'goes on only without them. Check them, or roll them back or '
        'stash them.',
      );
    }
    _check(output, failed);
  }

  /// `git add -A --`: stages the changes of [paths] (all when null),
  /// deletions included.
  Future<void> stage(Iterable<String>? paths) async {
    final top = await _requireRoot();
    _check(
      await _git(['add', '-A', '--', ..._pathspec(top, paths)]),
      'Cannot stage the changes.',
    );
  }

  /// Unstages [paths] (all when null): `git restore --staged` where Git has
  /// it (2.23+), else `git reset -q HEAD --` (2.0+); before the first
  /// commit, `git rm --cached -r -q --` either way (there is no HEAD to
  /// reset against).
  ///
  /// Older Gits (before 2.23, e.g. the 2.17 shipped on some systems) have no
  /// `restore`; asking for it fails outright, so the version is read once
  /// and `reset` used instead.
  Future<void> unstage(Iterable<String>? paths, {bool unborn = false}) async {
    final top = await _requireRoot();
    final relative = _pathspec(top, paths);
    final command = unborn
        ? ['rm', '--cached', '-r', '-q', '--', ...relative]
        : await _supportsRestore()
        ? ['restore', '--staged', '--', ...relative]
        : ['reset', '-q', 'HEAD', '--', ...relative];
    _check(await _git(command), 'Cannot unstage the changes.');
  }

  /// Whether this Git has `git restore` (added in 2.23), read once from
  /// `git --version`. A Git whose version cannot be read is taken to have
  /// it: the newer commands are the ones a modern Git expects.
  Future<bool> _supportsRestore() async =>
      _restoreSupport ??= switch (await _gitVersion()) {
        final version? => _atLeast(version, 2, 23),
        null => true,
      };

  /// The Git version, or null when Git is missing or its version cannot be
  /// read. Kept: it does not change while the service runs.
  Future<(int, int)?>? _gitVersionCache;
  Future<(int, int)?> _gitVersion() => _gitVersionCache ??= () async {
    final output = await _git(['--version']);
    if (output.exitCode != 0) return null;
    return parseGitVersion(output.stdout);
  }();

  bool? _restoreSupport;

  /// Whether [version] (major, minor) is [major].[minor] or newer.
  static bool _atLeast((int, int) version, int major, int minor) =>
      version.$1 != major ? version.$1 > major : version.$2 >= minor;

  /// Discards working-tree changes: tracked files are checked out from the
  /// index, untracked ones deleted (`git clean -f -q`).
  Future<void> discard(Iterable<IdeGitResource> resources) async {
    final top = await _requireRoot();
    final untracked = [
      for (final resource in resources)
        if (resource.status == IdeGitStatus.untracked) resource.path,
    ];
    final tracked = [
      for (final resource in resources)
        if (resource.status != IdeGitStatus.untracked) resource.path,
    ];
    if (tracked.isNotEmpty) {
      _check(
        await _git(['checkout', '-q', '--', ..._relative(top, tracked)]),
        'Cannot discard the changes.',
      );
    }
    if (untracked.isNotEmpty) {
      _check(
        await _git(['clean', '-f', '-q', '--', ..._relative(top, untracked)]),
        'Cannot delete the untracked files.',
      );
    }
  }

  /// Commits the index with [message]; [all] stages tracked changes first
  /// (`--all`), [amend] replaces the last commit, [empty] allows a commit
  /// without changes.
  Future<void> commit(
    String message, {
    bool all = false,
    bool amend = false,
    bool empty = false,
  }) async {
    await _requireRoot();
    _check(
      await _git([
        'commit',
        '--quiet',
        if (all) '--all',
        if (amend) '--amend',
        if (empty) '--allow-empty',
        if (message.isEmpty && amend) '--no-edit' else ...['-m', message],
      ]),
      'Cannot commit.',
    );
  }

  /// Commits [paths] as they are in the working tree, whatever is staged
  /// (`git commit --only -- <paths>`, as JetBrains IDEs commit the files
  /// checked); [amend] replaces the last commit, its message kept when
  /// [message] is empty.
  Future<void> commitPaths(
    String message,
    Iterable<String> paths, {
    bool amend = false,
    IdeGitCommitOptions options = const IdeGitCommitOptions(),
  }) async {
    final top = await _requireRoot();
    final relative = _relative(top, paths);
    _check(
      await _git([
        'commit',
        '--quiet',
        ...options.arguments,
        if (amend) '--amend',
        if (message.isEmpty && amend) '--no-edit' else ...['-m', message],
        if (relative.isNotEmpty) ...['--only', '--', ...relative],
      ]),
      'Cannot commit.',
    );
  }

  /// Commits [paths] as they are in the working tree and each of
  /// [partial]'s files with its text there (some of its changes left out),
  /// whatever is staged, as [commitPaths] does: through an index of its
  /// own (`GIT_INDEX_FILE`) made from HEAD's, the repository's then given
  /// what was committed of them. [amend] replaces the last commit.
  Future<void> commitPartial(
    String message,
    Iterable<String> paths,
    Map<String, String> partial, {
    bool amend = false,
    IdeGitCommitOptions options = const IdeGitCommitOptions(),
  }) async {
    final top = await _requireRoot();
    final indexPath = _check(
      await _git(['rev-parse', '--git-path', 'baocode-commit-index']),
      'Cannot commit.',
    ).stdout.trim();
    final environment = {
      'GIT_INDEX_FILE': pathContext.isAbsolute(indexPath)
          ? indexPath
          : pathContext.join(top, indexPath),
    };
    Future<IdeGitOutput> git(List<String> arguments, {String? stdin}) async =>
        _check(
          await _git(arguments, stdin: stdin, environment: environment),
          'Cannot commit.',
        );
    final head = await _git(['rev-parse', '--verify', '-q', 'HEAD']);
    await git(['read-tree', if (head.exitCode == 0) 'HEAD' else '--empty']);
    final whole = _relative(top, paths);
    if (whole.isNotEmpty) await git(['add', '-A', '--', ...whole]);
    final parts = <String>[];
    for (final MapEntry(key: path, value: text) in partial.entries) {
      final relative = _relative(top, [path]).single;
      parts.add(relative);
      final blob = (await git([
        'hash-object',
        '-w',
        '--path',
        relative,
        '--stdin',
      ], stdin: text)).stdout.trim();
      // Its mode as committed.
      final listed = (await git(['ls-files', '-s', '--', relative])).stdout;
      final mode = listed.isEmpty ? '100644' : listed.split(' ').first;
      await git([
        'update-index',
        '--add',
        '--cacheinfo',
        '$mode,$blob,$relative',
      ]);
    }
    await git([
      'commit',
      '--quiet',
      ...options.arguments,
      if (amend) '--amend',
      if (message.isEmpty && amend) '--no-edit' else ...['-m', message],
    ]);
    // The repository's index: the files as committed, the rest of the
    // partial ones' changes left unstaged.
    _check(
      await _git(['reset', '-q', '--', ...whole, ...parts]),
      'Cannot commit.',
    );
  }

  /// Rolls [paths] back to HEAD, index and working tree both
  /// (`git checkout HEAD -- <paths>`); [added] ones, not in HEAD, are left
  /// untracked (`git rm --cached`).
  Future<void> rollback(
    Iterable<String> paths, {
    Iterable<String> added = const [],
  }) async {
    final top = await _requireRoot();
    if (added.isNotEmpty) {
      _check(
        await _git([
          'rm',
          '--cached',
          '-q',
          '-r',
          '--',
          ..._relative(top, added),
        ]),
        'Cannot roll back the changes.',
      );
    }
    if (paths.isNotEmpty) {
      _check(
        await _git(['checkout', '-q', 'HEAD', '--', ..._relative(top, paths)]),
        'Cannot roll back the changes.',
      );
    }
  }

  /// What a commit would take, as a unified diff: the staged changes
  /// ([staged]), else the tracked ones, and each of [untracked] as a new
  /// file (`git diff --no-index`, which exits 1 when there is a
  /// difference). With [paths], HEAD against the working tree for those
  /// alone, staged or not (as a commit of them takes them).
  Future<String> diff({
    required bool staged,
    Iterable<String> untracked = const [],
    Iterable<String>? paths,
  }) async {
    final top = await _requireRoot();
    const options = ['--no-color', '--no-ext-diff'];
    final relative = paths == null ? null : _relative(top, paths);
    final out = StringBuffer(
      relative != null && relative.isEmpty
          ? ''
          : _check(
              await _git([
                'diff',
                ...options,
                '-M',
                if (relative != null) 'HEAD' else if (staged) '--cached',
                if (relative != null) ...['--', ...relative],
              ]),
              'Cannot read the changes.',
            ).stdout,
    );
    for (final path in _relative(top, untracked)) {
      final added = await _git([
        'diff',
        ...options,
        '--no-index',
        '--',
        '/dev/null',
        path,
      ]);
      if (added.exitCode <= 1) out.write(added.stdout);
    }
    return out.toString();
  }

  /// Undoes [head], the last commit, keeping its changes staged: `git reset
  /// --soft HEAD~`, or for the first commit, deleting HEAD and unstaging.
  Future<void> undoCommit(IdeGitCommit head) async {
    await _requireRoot();
    if (head.parentIds.isNotEmpty) {
      _check(
        await _git(['reset', '--soft', 'HEAD~']),
        'Cannot undo the last commit.',
      );
    } else {
      _check(
        await _git(['update-ref', '-d', 'HEAD']),
        'Cannot undo the last commit.',
      );
      _check(
        await _git(['rm', '--cached', '-r', '-q', '--', '.']),
        'Cannot unstage the changes.',
      );
    }
  }

  /// [path]'s text at [ref] (`git show --textconv <ref>:<path>`): `HEAD`,
  /// `''` for the index, or `:1` to `:3` for a merge's stages.
  Future<String> show(String ref, String path) async {
    final top = await _requireRoot();
    final relative = _relative(top, [path]).single;
    return _check(
      await _git(['show', '--textconv', '$ref:$relative']),
      'Could not show object.',
    ).stdout;
  }

  /// `git blame --root --incremental` of [path] as it is on disk (`blame2`);
  /// null where Git cannot blame it: untracked, outside the repository, or
  /// before the first commit.
  Future<List<IdeGitBlameInformation>?> blame(String path) async {
    try {
      final top = await repositoryRoot();
      if (top == null) return null;
      final output = await _git([
        '-c',
        'i18n.logOutputEncoding=UTF-8',
        'blame',
        '--root',
        '--incremental',
        '--',
        ..._relative(top, [path]),
      ]);
      if (output.exitCode != 0) return null;
      return parseGitBlame(output.stdout.trim());
    } on IdeGitException {
      return null;
    }
  }

  /// The remotes' names (`git remote`).
  Future<List<String>> remotes() async {
    await _requireRoot();
    final output = _check(await _git(['remote']), 'Cannot read the remotes.');
    return [
      for (final line in output.stdout.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
  }

  /// Each remote and the URL it fetches from (`git remote -v`), by name.
  Future<Map<String, String>> remoteUrls() async {
    await _requireRoot();
    final output = _check(
      await _git(['remote', '-v']),
      'Cannot read the remotes.',
    );
    final urls = <String, String>{};
    for (final line in output.stdout.split('\n')) {
      final match = RegExp(r'^(\S+)\s+(.*?)\s+\((fetch|push)\)$')
          .firstMatch(line.trim());
      if (match == null) continue;
      if (match[3] == 'fetch' || !urls.containsKey(match[1])) {
        urls[match[1]!] = match[2]!;
      }
    }
    return urls;
  }

  /// JetBrains' Manage Remotes: a remote added (`git remote add`).
  Future<void> addRemote(String name, String url) async {
    await _requireRoot();
    _check(
      await _git(['remote', 'add', '--', name, url]),
      'Cannot add the remote $name.',
    );
  }

  /// Remote [name] renamed [to] where it is not, its URL [url].
  Future<void> editRemote(String name, {String? to, String? url}) async {
    await _requireRoot();
    var current = name;
    if (to != null && to != name) {
      _check(
        await _git(['remote', 'rename', '--', name, to]),
        'Cannot rename the remote $name.',
      );
      current = to;
    }
    if (url != null) {
      _check(
        await _git(['remote', 'set-url', '--', current, url]),
        'Cannot change the URL of $current.',
      );
    }
  }

  /// Remote [name] removed, its remote branches with it.
  Future<void> removeRemote(String name) async {
    await _requireRoot();
    _check(
      await _git(['remote', 'remove', '--', name]),
      'Cannot remove the remote $name.',
    );
  }

  /// The tag [name] pushed to [remote].
  Future<void> pushTag(String remote, String name) async {
    await _requireRoot();
    _check(
      await _git(['push', remote, 'refs/tags/$name']),
      'Cannot push the tag $name.',
    );
  }

  /// The tag [name] deleted on [remote].
  Future<void> deleteRemoteTag(String remote, String name) async {
    await _requireRoot();
    _check(
      await _git(['push', remote, '--delete', 'refs/tags/$name']),
      'Cannot delete the tag $name on $remote.',
    );
  }

  /// `git fetch <remote> --tags` for one remote, or `git fetch --all
  /// --tags` for every remote (`git.fetch`/`git.fetchAll`).
  Future<void> fetch({String? remote}) async {
    await _requireRoot();
    _check(
      await _git(['fetch', ?remote, if (remote == null) '--all', '--tags']),
      remote == null ? 'Cannot fetch from all remotes.' : 'Cannot fetch.',
    );
  }

  /// `git pull --tags remote branch` (`pull` with `git.pullTags`, without
  /// rebasing: `git.rebaseWhenSync` is off by default).
  Future<void> pull(String remote, String branch) async {
    await _requireRoot();
    _check(await _git(['pull', '--tags', remote, branch]), 'Cannot pull.');
  }

  /// `git push [-u] remote name` (`push`; [setUpstream] to publish).
  Future<void> push(
    String remote,
    String name, {
    bool setUpstream = false,
    bool forceWithLease = false,
    bool followTags = false,
  }) async {
    await _requireRoot();
    _check(
      await _git([
        'push',
        if (setUpstream) '-u',
        if (forceWithLease) '--force-with-lease',
        if (followTags) '--follow-tags',
        remote,
        name,
      ]),
      'Cannot push.',
    );
  }

  /// The branches, remote branches and tags with their commits' details,
  /// the last committed first (`getRefs` with `git.branchSortOrder:
  /// committerdate` and `git.showReferenceDetails`).
  Future<List<IdeGitRef>> refs() async {
    await _requireRoot();
    final output = _check(
      await _git([
        'for-each-ref',
        '--sort',
        '-committerdate',
        '--format',
        ideGitRefsFormat,
      ]),
      'Cannot read the branches.',
    );
    return parseGitRefs(output.stdout);
  }

  /// The local branches whose upstream is [upstream] (`origin/main`).
  Future<List<String>> trackingBranches(String upstream) async {
    await _requireRoot();
    final output = _check(
      await _git([
        'for-each-ref',
        '--format',
        '%(refname:short)%00%(upstream:short)',
        'refs/heads',
      ]),
      'Cannot read the branches.',
    );
    return [
      for (final line in output.stdout.trim().split('\n'))
        if (line.trim().split('\x00') case [final name, final tracked]
            when tracked == upstream)
          name,
    ];
  }

  /// `git checkout -q [--track] [--detach] <treeish>`.
  Future<void> checkout(
    String treeish, {
    bool track = false,
    bool detached = false,
  }) async {
    await _requireRoot();
    _check(
      await _git([
        'checkout',
        '-q',
        if (track) '--track',
        if (detached) '--detach',
        treeish,
      ]),
      'Cannot check out $treeish.',
    );
  }

  /// `git checkout -q -b <name> --no-track [<ref>]`: the new branch
  /// [name], checked out.
  Future<void> branch(String name, {String? ref}) async {
    await _requireRoot();
    _check(
      await _git(['checkout', '-q', '-b', name, '--no-track', ?ref]),
      'Cannot create the branch $name.',
    );
  }

  /// The resolved commit of [ref], or null.
  Future<String?> revParse(String ref) async {
    final output = await _git(['rev-parse', '--verify', '-q', ref]);
    return output.exitCode == 0 ? output.stdout.trim() : null;
  }

  /// The best common ancestor of [a] and [b], or null.
  Future<String?> mergeBase(String a, String b) async {
    final output = await _git(['merge-base', a, b]);
    return output.exitCode == 0 ? output.stdout.trim() : null;
  }

  /// `git log` of [refs] in topological order (by date with [dateOrder]),
  /// newest first; [filter]'s commits only.
  Future<List<IdeGitCommit>> log({
    List<String> refs = const ['HEAD'],
    int limit = 50,
    IdeGitLogFilter filter = const IdeGitLogFilter(),
    bool dateOrder = false,
  }) async {
    final top = await _requireRoot();
    final lines = filter.lines;
    final output = _check(
      await _git([
        'log',
        dateOrder ? '--date-order' : '--topo-order',
        '--decorate=full',
        // Each record marked: an older Git prints -L's patches all the same.
        '--format=${lines == null ? '' : '%x1d'}$ideGitLogFormat',
        '-n',
        '$limit',
        ...filter.arguments,
        if (lines != null) ...[
          '--no-patch',
          '-L${lines.start},${lines.end}:${_relative(top, [lines.path]).single}',
        ],
        // -L digs from one commit only: the first ref's (HEAD's).
        if (lines == null) ...refs else refs.first,
        '--',
        if (lines == null) ..._relative(top, filter.paths),
      ]),
      'Cannot read the Git history.',
    );
    if (lines == null) return parseGitLog(output.stdout);
    return parseGitLog(
      output.stdout
          .split('\x1e')
          .map((record) {
            final start = record.indexOf('\x1d');
            return start < 0 ? '' : record.substring(start + 1);
          })
          .join('\x1e'),
    );
  }

  /// The repository's working trees, its own first (`git worktree list
  /// --porcelain`).
  Future<List<IdeGitWorktree>> worktrees() async {
    await _requireRoot();
    final output = _check(
      await _git(['worktree', 'list', '--porcelain']),
      'Cannot read the worktrees.',
    );
    return parseGitWorktrees(output.stdout, normalize: pathContext.normalize);
  }

  /// Adds a working tree at [path] (`git worktree add`): on a new branch
  /// [newBranch] from HEAD, or on [branch], one not checked out elsewhere.
  Future<void> addWorktree(
    String path, {
    String? newBranch,
    String? branch,
  }) async {
    assert((newBranch == null) != (branch == null));
    await _requireRoot();
    _check(
      await _git([
        'worktree',
        'add',
        if (newBranch != null) ...['-b', newBranch],
        '--',
        path,
        ?branch,
      ]),
      'Cannot add the worktree.',
    );
  }

  /// The branches, local and remote, that have [commit]
  /// (`git branch -a --contains`): a remote's HEAD left out.
  Future<List<IdeGitRef>> branchesContaining(String commit) async {
    await _requireRoot();
    final output = _check(
      await _git(['branch', '-a', '--contains', commit, '--format=%(refname)']),
      'Cannot read the branches.',
    );
    return [
      for (final line in output.stdout.split('\n'))
        if (line.trim() case final ref when ref.isNotEmpty)
          if (ref.startsWith('refs/heads/'))
            IdeGitRef(
              ref,
              ref.substring('refs/heads/'.length),
              IdeGitRefKind.branch,
            )
          else if (ref.startsWith('refs/remotes/'))
            if (!ref.endsWith('/HEAD'))
              IdeGitRef(
                ref,
                ref.substring('refs/remotes/'.length),
                IdeGitRefKind.remote,
              ),
    ];
  }

  /// The lines [commit] added and deleted in each file against its first
  /// parent (`git show --numstat`), by absolute path; null counts for a
  /// binary file.
  Future<Map<String, ({int? added, int? deleted})>> commitStats(
    String commit,
  ) async {
    final top = await _requireRoot();
    final output = _check(
      await _git([
        'show',
        '--format=',
        '--numstat',
        '-z',
        '--first-parent',
        '-m',
        commit,
      ]),
      'Cannot read the commit.',
    );
    return parseGitNumstat(output.stdout, (relative) {
      return pathContext.normalize(
        pathContext.join(top, pathContext.joinAll(relative.split('/'))),
      );
    });
  }

  /// [key]'s value in Git's configuration (`git config --get`); null when
  /// it has none.
  Future<String?> config(String key) async {
    final output = await _git(['config', '--get', key]);
    final value = output.stdout.trim();
    return output.exitCode == 0 && value.isNotEmpty ? value : null;
  }

  /// The messages of the last [limit] commits of the user's (by
  /// `user.email`, else anyone's) from HEAD, the newest first, each once:
  /// JetBrains' commit message history.
  Future<List<String>> recentMessages({int limit = 20}) async {
    await _requireRoot();
    final email = await config('user.email');
    final output = await _git([
      'log',
      '-n',
      '$limit',
      '--format=%B%x1e',
      if (email != null) '--author=<${_escapeRegExp(email)}>',
      'HEAD',
      '--',
    ]);
    if (output.exitCode != 0) return const [];
    return {
      for (final message in output.stdout.split('\x1e'))
        if (message.trim() case final text when text.isNotEmpty) text,
    }.toList();
  }

  static String _escapeRegExp(String text) =>
      text.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (m) => '\\${m[0]}');

  /// The files and folders Git ignores (a folder ignored whole once, its
  /// path ending in a separator), by absolute path: JetBrains' Ignored
  /// Files.
  Future<List<String>> ignoredFiles() async {
    final top = await _requireRoot();
    final output = _check(
      await _git([
        'ls-files',
        '--others',
        '--ignored',
        '--exclude-standard',
        '--directory',
        '-z',
      ]),
      'Cannot read the ignored files.',
    );
    return [
      for (final relative in output.stdout.split('\x00'))
        if (relative.isNotEmpty)
          pathContext.join(top, pathContext.joinAll(relative.split('/'))) +
              (relative.endsWith('/') ? pathContext.separator : ''),
    ]..sort();
  }

  /// The commits that changed [path], following renames.
  Future<List<IdeGitCommit>> fileLog(String path, {int limit = 50}) async {
    final top = await _requireRoot();
    final output = _check(
      await _git([
        'log',
        '--follow',
        '--decorate=full',
        '--format=$ideGitLogFormat',
        '-n',
        '$limit',
        '--',
        ..._relative(top, [path]),
      ]),
      'Cannot read the file\'s history.',
    );
    return parseGitLog(output.stdout);
  }

  /// The files [commit] changed against its first parent.
  Future<List<IdeGitCommitChange>> commitChanges(String commit) async {
    final top = await _requireRoot();
    final output = _check(
      await _git([
        'show',
        '--format=',
        '--name-status',
        '-z',
        '--first-parent',
        '-m',
        commit,
      ]),
      'Cannot read the commit.',
    );
    return _parseNameStatus(top, output.stdout);
  }

  /// The files that differ between [commit] and the working tree
  /// (`git diff --name-status <commit>`): Compare with Local; or [other]
  /// (two commits compared).
  Future<List<IdeGitCommitChange>> changesSince(
    String commit, {
    String? other,
  }) async {
    final top = await _requireRoot();
    final output = _check(
      await _git(['diff', '--name-status', '-z', '-M', commit, ?other, '--']),
      'Cannot compare with $commit.',
    );
    return _parseNameStatus(top, output.stdout);
  }

  // --- Stashes ---------------------------------------------------------------

  /// The stashes, the newest first.
  Future<List<IdeGitStash>> stashes() async {
    await _requireRoot();
    final output = _check(
      await _git(['stash', 'list', '--format=%gd%x00%H%x00%ct%x00%gs']),
      'Cannot list the stashes.',
    );
    return parseGitStashes(output.stdout);
  }

  /// Stashes the local changes (only [paths]' where given) with [message];
  /// [untracked] the untracked files too, [keepIndex] leaving what is
  /// staged.
  Future<void> stash({
    String message = '',
    Iterable<String>? paths,
    bool untracked = false,
    bool keepIndex = false,
  }) async {
    final top = await _requireRoot();
    _check(
      await _git([
        'stash',
        'push',
        if (message.isNotEmpty) ...['-m', message],
        if (untracked) '--include-untracked',
        if (keepIndex) '--keep-index',
        if (paths != null) ...['--', ..._relative(top, paths)],
      ]),
      'Cannot stash the changes.',
    );
  }

  /// Applies [ref]'s changes ([pop]: and drops it once they apply);
  /// [index]: what was staged staged again.
  Future<void> unstash(
    String ref, {
    bool pop = false,
    bool index = false,
  }) async {
    await _requireRoot();
    _check(
      await _git(['stash', pop ? 'pop' : 'apply', if (index) '--index', ref]),
      'Cannot apply the stash.',
    );
  }

  Future<void> dropStash(String ref) async {
    await _requireRoot();
    _check(await _git(['stash', 'drop', ref]), 'Cannot drop the stash.');
  }

  Future<void> clearStashes() async {
    await _requireRoot();
    _check(await _git(['stash', 'clear']), 'Cannot clear the stashes.');
  }

  /// A branch [name] made where [ref] was stashed, its changes on it, the
  /// stash dropped (`git stash branch`).
  Future<void> stashBranch(String name, String ref) async {
    await _requireRoot();
    _check(
      await _git(['stash', 'branch', name, ref]),
      'Cannot unstash to the branch $name.',
    );
  }

  /// The files stashed in [stash] (its commit) that were untracked: its
  /// third parent's.
  Future<List<String>> stashedUntracked(String stash) async {
    final top = await _requireRoot();
    final output = await _git([
      'ls-tree',
      '-r',
      '--name-only',
      '-z',
      '$stash^3',
    ]);
    if (output.exitCode != 0) return const [];
    return [
      for (final path in output.stdout.split('\x00'))
        if (path.isNotEmpty) pathContext.join(top, path),
    ];
  }

  // --- Commit operations (JetBrains' Git log) --------------------------------

  /// Applies [commits] (oldest first) on HEAD: `git cherry-pick`.
  Future<void> cherryPick(List<String> commits) async {
    await _requireRoot();
    _check(await _git(['cherry-pick', ...commits]), 'Cannot cherry-pick.');
  }

  /// Commits the inverse of [commits] (newest first): `git revert`.
  Future<void> revert(List<String> commits) async {
    await _requireRoot();
    _check(await _git(['revert', '--no-edit', ...commits]), 'Cannot revert.');
  }

  /// Moves the current branch to [commit]: `git reset --<mode>`.
  Future<void> reset(String commit, IdeGitResetMode mode) async {
    await _requireRoot();
    _check(
      await _git(['reset', '--${mode.name}', commit]),
      'Cannot reset to $commit.',
    );
  }

  /// Tags [commit] [name]; annotated with [message] where there is one.
  Future<void> tag(String name, String commit, {String? message}) async {
    await _requireRoot();
    _check(
      await _git([
        'tag',
        if (message != null && message.isNotEmpty) ...['-a', '-m', message],
        name,
        commit,
      ]),
      'Cannot create the tag $name.',
    );
  }

  /// [commit] as a patch (`git format-patch --stdout`).
  Future<String> patch(String commit) async {
    await _requireRoot();
    return _check(
      await _git(['format-patch', '-1', '--stdout', commit]),
      'Cannot make a patch of $commit.',
    ).stdout;
  }

  /// Gives [commit], HEAD or one before it, [message]: HEAD amended (its
  /// message only), an older one by an `amend!` commit squashed into it
  /// (`rebase -i --autosquash`, no editor), the changes not committed set
  /// aside meanwhile. Merges after it would be flattened: refused.
  Future<void> reword(IdeGitCommit commit, String message) async {
    await _requireRoot();
    final head = await revParse('HEAD');
    if (head == commit.id) {
      _check(
        await _git([
          'commit',
          '--amend',
          '--only',
          '--allow-empty',
          '-m',
          message,
        ]),
        'Cannot edit the commit message.',
      );
      return;
    }
    await _requireLinearSince(commit);
    final tree = _check(
      await _git(['rev-parse', 'HEAD^{tree}']),
      'Cannot edit the commit message.',
    ).stdout.trim();
    final amend = _check(
      await _git([
        'commit-tree',
        tree,
        '-p',
        'HEAD',
        '-m',
        'amend! ${commit.id}',
        '-m',
        message,
      ]),
      'Cannot edit the commit message.',
    ).stdout.trim();
    _check(
      await _git(['update-ref', '-m', 'reword', 'HEAD', amend]),
      'Cannot edit the commit message.',
    );
    await _rebaseFrom(
      commit,
      ['-i', '--autosquash'],
      undo: () async {
        await _git(['reset', '--soft', 'HEAD~']);
      },
    );
  }

  /// JetBrains' Fixup: the `fixup!` commit just made (HEAD) squashed into
  /// [commit] (`rebase -i --autosquash`, no editor), the changes not
  /// committed set aside meanwhile; where the rebase fails, the fixup
  /// commit undone, its changes staged.
  Future<void> autosquash(IdeGitCommit commit) async {
    await _requireRoot();
    await _requireLinearSince(commit);
    await _rebaseFrom(
      commit,
      ['-i', '--autosquash'],
      undo: () async {
        await _git(['reset', '--soft', 'HEAD~']);
      },
    );
  }

  /// Takes [commit] out of the branch: the commits after it rebased onto
  /// its parent (`git rebase --onto`), the changes not committed set aside
  /// meanwhile.
  Future<void> drop(IdeGitCommit commit) async {
    await _requireRoot();
    await _requireLinearSince(commit);
    if (commit.parentIds.isEmpty) {
      throw const IdeGitException('Cannot drop the first commit.');
    }
    final output = await _git([
      'rebase',
      '--autostash',
      '--onto',
      commit.parentIds.first,
      commit.id,
    ]);
    if (output.exitCode != 0) {
      await _git(['rebase', '--abort']);
      _check(output, 'Cannot drop ${commit.shortId}.');
    }
  }

  /// Squashes [commits] (oldest first, one after another in the current
  /// branch) into the first, their messages one after another: a rebase
  /// whose list `sed` edits, no editor.
  Future<void> squash(List<IdeGitCommit> commits) async {
    await _requireRoot();
    if (commits.length < 2) return;
    await _requireLinearSince(commits.first);
    final script = [
      for (final commit in commits.skip(1))
        "-e 's/^pick \\(${commit.id.length > 7 ? commit.id.substring(0, 7) : commit.id}[0-9a-f]*\\) /"
            "squash \\1 /'",
    ].join(' ');
    await _rebaseFrom(commits.first, [
      '-i',
    ], sequenceEditor: 'sed -i.bak $script');
  }

  /// JetBrains' interactive rebase: the commits from [from] on, as [steps]
  /// (oldest first, in their new order) say: each picked, reworded (its
  /// message put in through Git, an `exec` amending it, so that a rebase
  /// stopped and continued still has it), stopped at to be edited, squashed
  /// or fixed up into the one before, or dropped. True where the rebase
  /// stopped (to edit a commit, at a conflict): it is still under way.
  Future<bool> interactiveRebase(
    IdeGitCommit from,
    List<IdeGitRebaseStep> steps,
  ) async {
    await _requireRoot();
    await _requireLinearSince(from);
    Future<String> blob(String text) async => _check(
      await _git(['hash-object', '-w', '--stdin'], stdin: text),
      'Cannot rebase.',
    ).stdout.trim();
    final todo = StringBuffer();
    for (final step in steps) {
      final id = step.commit;
      switch (step.action) {
        case IdeGitRebaseAction.reword:
          todo
            ..writeln('pick $id')
            ..writeln(
              'exec git cat-file blob ${await blob(step.message ?? '')} | '
              'git commit --amend --only --allow-empty --no-verify -q -F -',
            );
        case final action:
          todo.writeln('${action.name} $id');
      }
    }
    final list = await blob(todo.toString());
    final output = await _git([
      '-c',
      'sequence.editor=git cat-file blob $list >',
      '-c',
      'core.editor=:',
      'rebase',
      '-i',
      '--autostash',
      '--no-autosquash',
      if (from.parentIds.isEmpty) '--root' else from.parentIds.first,
    ]);
    // Stopped where Git left REBASE_HEAD: at a commit to edit, or a
    // conflict.
    final underWay = await _operation() == IdeGitOperation.rebase;
    if (output.exitCode != 0 && !underWay) _check(output, 'Cannot rebase.');
    return underWay;
  }

  /// Rebases from [commit] with [options] and no editor (the list as it is,
  /// or as [sequenceEditor] makes it); aborted, then [undo] run, where it
  /// fails.
  Future<void> _rebaseFrom(
    IdeGitCommit commit,
    List<String> options, {
    String sequenceEditor = ':',
    Future<void> Function()? undo,
  }) async {
    final output = await _git([
      '-c',
      'sequence.editor=$sequenceEditor',
      '-c',
      'core.editor=:',
      'rebase',
      ...options,
      '--autostash',
      if (commit.parentIds.isEmpty) '--root' else commit.parentIds.first,
    ]);
    if (output.exitCode != 0) {
      await _git(['rebase', '--abort']);
      await undo?.call();
      _check(output, 'Cannot rewrite the history.');
    }
  }

  /// Throws unless [commit] is in HEAD's history with no merge after it.
  Future<void> _requireLinearSince(IdeGitCommit commit) async {
    final ancestor = await _git([
      'merge-base',
      '--is-ancestor',
      commit.id,
      'HEAD',
    ]);
    if (ancestor.exitCode != 0) {
      throw IdeGitException('${commit.shortId} is not on the current branch.');
    }
    final merges = await _git([
      'rev-list',
      '--merges',
      '--count',
      '${commit.id}..HEAD',
    ]);
    if (merges.exitCode == 0 && (int.tryParse(merges.stdout.trim()) ?? 0) > 0) {
      throw const IdeGitException(
        'There are merge commits after it; rewrite the history from a '
        'terminal.',
      );
    }
  }

  // --- Branches (JetBrains' branch popup, the log's branch tree) ----------

  /// The branches checked out of late, the latest first, by the reflog's
  /// `checkout: moving from <a> to <b>`: the branch popup's Recent.
  Future<List<String>> recentBranches({int limit = 8}) async {
    await _requireRoot();
    final output = await _git(['reflog', '-n', '500', '--format=%gs']);
    if (output.exitCode != 0) return const [];
    final pattern = RegExp(r'^checkout: moving from (.+) to (.+)$');
    final names = <String>[];
    for (final line in output.stdout.split('\n')) {
      final match = pattern.firstMatch(line.trim());
      if (match == null) continue;
      for (final name in [match[2]!, match[1]!]) {
        if (!names.contains(name)) names.add(name);
      }
      if (names.length >= limit) break;
    }
    return names;
  }

  /// Renames the branch [from] to [to]: `git branch -m`.
  Future<void> renameBranch(String from, String to) async {
    await _requireRoot();
    _check(
      await _git(['branch', '-m', from, to]),
      'Cannot rename the branch $from.',
    );
  }

  /// Deletes the branch [name]: `git branch -d`, or `-D` with [force].
  /// Throws an [IdeGitNotMergedException] where it has commits merged
  /// nowhere and not [force].
  Future<void> deleteBranch(String name, {bool force = false}) async {
    await _requireRoot();
    final output = await _git(['branch', force ? '-D' : '-d', name]);
    if (!force &&
        output.exitCode != 0 &&
        output.stderr.contains('not fully merged')) {
      throw IdeGitNotMergedException(name);
    }
    _check(output, 'Cannot delete the branch $name.');
  }

  /// Deletes the branch [name] of [remote]: `git push --delete`.
  Future<void> deleteRemoteBranch(String remote, String name) async {
    await _requireRoot();
    _check(
      await _git(['push', remote, '--delete', name]),
      'Cannot delete $remote/$name.',
    );
  }

  /// Deletes the tag [name]: `git tag -d`.
  Future<void> deleteTag(String name) async {
    await _requireRoot();
    _check(await _git(['tag', '-d', name]), 'Cannot delete the tag $name.');
  }

  /// Makes the branch [name] at [commit] (no checkout): Restore after a
  /// branch's deleted.
  Future<void> createBranchAt(String name, String commit) async {
    await _requireRoot();
    _check(
      await _git(['branch', name, commit]),
      'Cannot create the branch $name.',
    );
  }

  /// Merges [ref] into the current branch: `git merge --no-edit`.
  Future<void> merge(String ref) async {
    await _requireRoot();
    _check(await _git(['merge', '--no-edit', ref]), 'Cannot merge $ref.');
  }

  /// Rebases [branch] (the current one when null) onto [onto]:
  /// `git rebase --autostash <onto> [<branch>]`; with a branch, it is
  /// checked out.
  Future<void> rebaseOnto(String onto, {String? branch}) async {
    await _requireRoot();
    _check(
      await _git(['rebase', '--autostash', onto, ?branch]),
      'Cannot rebase onto $onto.',
    );
  }

  /// Pulls [branch] of [remote] into the current branch, by rebase or by
  /// merge.
  Future<void> pullInto(
    String remote,
    String branch, {
    required bool rebase,
  }) async {
    await _requireRoot();
    _check(
      await _git([
        'pull',
        rebase ? '--rebase' : '--no-rebase',
        '--autostash',
        remote,
        branch,
      ]),
      'Cannot pull $remote/$branch.',
    );
  }

  /// Fast-forwards the branch [name], not checked out, to its upstream
  /// [upstream] (`remote/branch`): `git fetch <remote> <branch>:<name>`.
  Future<void> updateBranch(String name, String upstream) async {
    await _requireRoot();
    final slash = upstream.indexOf('/');
    if (slash <= 0) throw IdeGitException('No remote in $upstream.');
    _check(
      await _git([
        'fetch',
        upstream.substring(0, slash),
        '${upstream.substring(slash + 1)}:$name',
      ]),
      'Cannot update $name.',
    );
  }

  /// Sets the branch [name]'s upstream to [upstream], or unsets it.
  Future<void> setUpstream(String name, String? upstream) async {
    await _requireRoot();
    _check(
      await _git([
        'branch',
        if (upstream == null)
          '--unset-upstream'
        else
          '--set-upstream-to=$upstream',
        name,
      ]),
      'Cannot set the upstream of $name.',
    );
  }

  /// How many commits [ref] has that HEAD has not, and HEAD has that it
  /// has not: `git rev-list --left-right --count`.
  Future<({int ahead, int behind})> compareWithHead(String ref) async {
    await _requireRoot();
    final output = _check(
      await _git(['rev-list', '--left-right', '--count', '$ref...HEAD']),
      'Cannot compare $ref with HEAD.',
    );
    final counts = output.stdout.trim().split(RegExp(r'\s+'));
    return (
      ahead: int.tryParse(counts.first) ?? 0,
      behind: counts.length > 1 ? int.tryParse(counts[1]) ?? 0 : 0,
    );
  }

  /// Pushes the current branch up to [commit] to its upstream
  /// ([upstream], `remote/branch`): `git push <remote> <commit>:<branch>`.
  Future<void> pushUpTo(String commit, String upstream) async {
    await _requireRoot();
    final slash = upstream.indexOf('/');
    if (slash <= 0) throw IdeGitException('No remote in $upstream.');
    _check(
      await _git([
        'push',
        upstream.substring(0, slash),
        '$commit:refs/heads/${upstream.substring(slash + 1)}',
      ]),
      'Cannot push.',
    );
  }

  /// `--name-status -z` output, its paths absolute.
  List<IdeGitCommitChange> _parseNameStatus(String top, String stdout) {
    final fields = stdout.split('\x00');
    final changes = <IdeGitCommitChange>[];
    String absolute(String relative) => pathContext.normalize(
      pathContext.join(top, pathContext.joinAll(relative.split('/'))),
    );
    for (var i = 0; i + 1 < fields.length; i++) {
      final status = fields[i].trim();
      if (status.isEmpty) continue;
      if (status.startsWith('R') || status.startsWith('C')) {
        if (i + 2 >= fields.length) break;
        changes.add(
          IdeGitCommitChange(
            absolute(fields[i + 2]),
            status[0],
            originalPath: absolute(fields[i + 1]),
          ),
        );
        i += 2;
      } else {
        changes.add(IdeGitCommitChange(absolute(fields[i + 1]), status[0]));
        i += 1;
      }
    }
    return changes;
  }
}
