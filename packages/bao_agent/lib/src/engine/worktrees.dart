import 'dart:io';

import 'package:path/path.dart' as p;

import '../util/ids.dart';
import '../util/json.dart';

/// A git worktree the agent made to work in apart: where it is, its
/// branch, and the commit it started from.
class Worktree {
  const Worktree({
    required this.path,
    required this.branch,
    required this.base,
    required this.repository,
    this.made = true,
  });

  final String path;

  /// Null for one entered that has no branch of its own (detached).
  final String? branch;

  /// The commit it started from, to tell what was done in it.
  final String? base;

  /// The repository's own folder (its main worktree).
  final String repository;

  /// Whether the agent made it (it may then remove it), or entered one
  /// that was there.
  final bool made;
}

/// Makes, inspects and removes the agent's git worktrees: under
/// `.claude/worktrees/` of the repository, a branch `worktree-<name>` each.
abstract final class Worktrees {
  /// What a name may be: segments of letters, digits, `.`, `_` and `-`
  /// joined by `/`, 64 characters at most.
  static final _name = RegExp(r'^[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*$');

  /// What is wrong with [name]; null when nothing.
  static String? checkName(String name) {
    if (name.length > 64) return 'The name is longer than 64 characters.';
    if (!_name.hasMatch(name) ||
        name.split('/').any((part) => part == '.' || part == '..')) {
      return 'Each "/"-separated part of the name may hold only letters, '
          'digits, dots, underscores and dashes.';
    }
    return null;
  }

  static Future<ProcessResult> _git(
    List<String> args,
    String cwd,
    Map<String, String> environment,
  ) => Process.run(
    'git',
    args,
    workingDirectory: cwd,
    environment: {...environment, 'GIT_OPTIONAL_LOCKS': '0'},
    includeParentEnvironment: false,
  );

  /// The top of the repository [cwd] is in; null when it is in none.
  static Future<String?> topLevel(
    String cwd,
    Map<String, String> environment,
  ) async {
    try {
      final result = await _git(
        ['rev-parse', '--path-format=absolute', '--git-common-dir'],
        cwd,
        environment,
      );
      if (result.exitCode != 0) return null;
      final common = '${result.stdout}'.trim();
      // The common folder is `<repository>/.git` for the main worktree and
      // every other.
      return p.basename(common) == '.git' ? p.dirname(common) : null;
    } on ProcessException {
      return null;
    }
  }

  /// Makes a worktree named [name] (one made up when null) for the
  /// repository [cwd] is in, from [baseRef]: `fresh` (the remote's default
  /// branch, else HEAD), `head`, or a ref.
  static Future<Worktree> create(
    String cwd,
    Map<String, String> environment, {
    String? name,
    String? baseRef,
  }) async {
    final repository = await topLevel(cwd, environment);
    if (repository == null) {
      throw const WorktreeError('Not in a git repository.');
    }
    final chosen = name ?? randomSlug();
    if (checkName(chosen) case final error?) throw WorktreeError(error);
    final path = p.joinAll([
      repository,
      '.claude',
      'worktrees',
      ...chosen.split('/'),
    ]);
    if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
      throw WorktreeError('There is a worktree at $path already.');
    }
    final branch = 'worktree-${chosen.replaceAll('/', '-')}';
    final base = await _baseRef(repository, environment, baseRef);
    final added = await _git(
      ['worktree', 'add', '-b', branch, path, base],
      repository,
      environment,
    );
    if (added.exitCode != 0) {
      throw WorktreeError(
        'git worktree add failed: ${'${added.stderr}'.trim()}',
      );
    }
    final head = await _git(['rev-parse', 'HEAD'], path, environment);
    return Worktree(
      path: path,
      branch: branch,
      base: head.exitCode == 0 ? '${head.stdout}'.trim() : null,
      repository: repository,
    );
  }

  static Future<String> _baseRef(
    String repository,
    Map<String, String> environment,
    String? setting,
  ) async {
    final asked = setting?.trim();
    if (asked == 'head') return 'HEAD';
    if (asked != null && asked.isNotEmpty && asked != 'fresh') return asked;
    final remote = await _git(
      ['symbolic-ref', '--quiet', 'refs/remotes/origin/HEAD'],
      repository,
      environment,
    );
    if (remote.exitCode == 0) {
      final ref = '${remote.stdout}'.trim();
      if (ref.isNotEmpty) return ref.replaceFirst('refs/remotes/', '');
    }
    return 'HEAD';
  }

  /// The worktree at [path], which `git worktree list` of the repository
  /// [cwd] is in must name.
  static Future<Worktree> existing(
    String cwd,
    String path,
    Map<String, String> environment,
  ) async {
    final repository = await topLevel(cwd, environment);
    final target = p.normalize(p.isAbsolute(path) ? path : p.join(cwd, path));
    final owner = repository ?? await topLevel(target, environment);
    if (owner == null) throw const WorktreeError('Not in a git repository.');
    final listed = await _git(
      ['worktree', 'list', '--porcelain'],
      owner,
      environment,
    );
    String? branch;
    var found = false;
    String? current;
    for (final line in '${listed.stdout}'.split('\n')) {
      if (line.startsWith('worktree ')) {
        current = line.substring('worktree '.length).trim();
        continue;
      }
      if (current != null && _same(current, target)) {
        found = true;
        if (line.startsWith('branch ')) {
          branch = line
              .substring('branch '.length)
              .replaceFirst('refs/heads/', '');
        }
      }
    }
    if (!found) {
      throw WorktreeError(
        '$target is not a worktree of this repository (see '
        '`git worktree list`).',
      );
    }
    final head = await _git(['rev-parse', 'HEAD'], target, environment);
    return Worktree(
      path: target,
      branch: branch,
      base: head.exitCode == 0 ? '${head.stdout}'.trim() : null,
      repository: owner,
      made: false,
    );
  }

  static bool _same(String a, String b) {
    String real(String path) {
      try {
        return Directory(path).resolveSymbolicLinksSync();
      } on FileSystemException {
        return p.normalize(path);
      }
    }

    return real(a) == real(b);
  }

  /// What [worktree] holds that its start did not: files changed and not
  /// committed, and commits made.
  static Future<({List<String> files, List<String> commits})> changes(
    Worktree worktree,
    Map<String, String> environment,
  ) async {
    final status = await _git(
      ['status', '--porcelain'],
      worktree.path,
      environment,
    );
    final files = [
      for (final line in '${status.stdout}'.split('\n'))
        if (line.trim().isNotEmpty) line.trimRight(),
    ];
    var commits = <String>[];
    if (worktree.base case final base?) {
      final log = await _git(
        ['log', '--oneline', '$base..HEAD'],
        worktree.path,
        environment,
      );
      commits = [
        for (final line in '${log.stdout}'.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];
    }
    return (files: files, commits: commits);
  }

  /// Removes [worktree] and its branch.
  static Future<void> remove(
    Worktree worktree,
    Map<String, String> environment,
  ) async {
    final removed = await _git(
      ['worktree', 'remove', '--force', worktree.path],
      worktree.repository,
      environment,
    );
    if (removed.exitCode != 0) {
      throw WorktreeError(
        'git worktree remove failed: ${'${removed.stderr}'.trim()}',
      );
    }
    if (worktree.branch case final branch?) {
      await _git(['branch', '-D', branch], worktree.repository, environment);
    }
  }

  /// [worktree] as a hook or the host is told it.
  static Map<String, Object?> toJson(Worktree worktree) => {
    'worktree_path': worktree.path,
    'worktree_branch': ?worktree.branch,
    'original_repository': worktree.repository,
  };

  /// The setting that says where a new worktree starts from.
  static String? baseRefSetting(Object? worktreeSettings) =>
      asText(asMap(worktreeSettings)['baseRef']);
}

/// A worktree that could not be made, entered or removed.
class WorktreeError implements Exception {
  const WorktreeError(this.message);

  final String message;

  @override
  String toString() => message;
}
