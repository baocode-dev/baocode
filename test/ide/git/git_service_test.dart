@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/git/git_model.dart';
import 'package:baocode/ide/git/git_repository.dart';
import 'package:baocode/ide/git/git_service.dart';
import 'package:path/path.dart' as p;

/// Runs local Git (no network) in a temporary repository whose own config
/// keeps the user's hooks, signing and templates out.
void main() {
  final hasGit = () {
    try {
      return Process.runSync('git', ['--version']).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }();

  late Directory temp;
  late String root;

  Future<void> git(List<String> arguments) async {
    final result = await Process.run('git', arguments, workingDirectory: root);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  }

  Future<void> write(String relative, String text) async {
    final file = File(p.join(root, relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('baocode_git_');
    root = p.normalize((await temp.resolveSymbolicLinks()));
    await git(['init', '-q', '-b', 'main']);
    final hooks = await Directory(p.join(root, '.no-hooks')).create();
    for (final (key, value) in [
      ('user.name', 'Ada'),
      ('user.email', 'ada@example.com'),
      ('commit.gpgsign', 'false'),
      ('core.hooksPath', hooks.path),
    ]) {
      await git(['config', key, value]);
    }
    await write('.gitignore', '.no-hooks/\nbuild/\n');
    await write('lib/a.dart', 'a\n');
    await git(['add', '-A']);
    await git(['commit', '-q', '-m', 'Initial commit']);
  });

  tearDown(() => temp.delete(recursive: true));

  test('status, stage, unstage, discard and commit', () async {
    final service = IdeGitService(p.join(root, 'lib'));
    expect(await service.repositoryRoot(), root);

    await write('lib/a.dart', 'changed\n');
    await write('lib/new.dart', 'new\n');
    await write('build/out.js', 'x');
    var state = (await service.status())!;
    expect(state.head.branch, 'main');
    expect(
      [for (final r in state.resources) (p.basename(r.path), r.status)],
      [('a.dart', IdeGitStatus.modified), ('new.dart', IdeGitStatus.untracked)],
    );
    expect(
      state.decorations.folder(p.join(root, 'build'))!.colorId,
      'gitDecoration.ignoredResourceForeground',
    );

    await service.stage([p.join(root, 'lib/new.dart')]);
    state = (await service.status())!;
    expect(
      state.group(IdeGitGroup.staged).single.status,
      IdeGitStatus.indexAdded,
    );

    await service.unstage([p.join(root, 'lib/new.dart')]);
    state = (await service.status())!;
    expect(state.group(IdeGitGroup.staged), isEmpty);

    await service.discard(state.resources);
    expect(await File(p.join(root, 'lib/a.dart')).readAsString(), 'a\n');
    expect(await File(p.join(root, 'lib/new.dart')).exists(), isFalse);
    expect((await service.status())!.resources, isEmpty);

    await write('lib/a.dart', 'second\n');
    await service.commit('Second commit', all: true);
    final log = await service.log();
    expect(
      [for (final c in log) c.subject],
      ['Second commit', 'Initial commit'],
    );
    expect(log.first.references.single.name, 'main');
    expect(log.first.parentIds, [log.last.id]);

    final history = await service.fileLog(p.join(root, 'lib/a.dart'));
    expect(history, hasLength(2));
    final changes = await service.commitChanges(log.first.id);
    expect(
      [for (final c in changes) (c.path, c.status)],
      [(p.join(root, 'lib/a.dart'), 'M')],
    );
  }, skip: hasGit ? false : 'Git is not installed');

  test('refs, checkout and branch, as Checkout to… runs them', () async {
    final service = IdeGitService(root);
    await write('lib/a.dart', 'second\n');
    await service.commit('Second commit', all: true);
    final second = (await service.revParse('HEAD'))!;
    final first = (await service.revParse('HEAD~'))!;
    await git(['branch', 'older', first]);
    await git(['tag', '-a', 'v1', '-m', 'Version 1', second]);
    // A remote's branch as a fetch would have left it (never fetched).
    await git(['remote', 'add', 'origin', p.join(root, 'nowhere')]);
    await git(['update-ref', 'refs/remotes/origin/topic', first]);

    final refs = await service.refs();
    expect(
      [for (final r in refs) (r.name, r.kind, r.remote)],
      unorderedEquals([
        ('main', IdeGitRefKind.branch, null),
        ('older', IdeGitRefKind.branch, null),
        ('origin/topic', IdeGitRefKind.remote, 'origin'),
        ('v1', IdeGitRefKind.tag, null),
      ]),
    );
    // The last committed first.
    expect(refs.first.name, 'main');
    final main = refs.first;
    expect(main.commit, second);
    expect(main.details!.subject, 'Second commit');
    expect(main.details!.author, 'Ada');
    expect(main.ahead, isNull);
    // An annotated tag: its commit and that commit's details; a root
    // commit has none (upstream `parseRefs` wants its parents).
    final tag = refs.singleWhere((r) => r.name == 'v1');
    expect(tag.commit, second);
    expect(tag.details!.subject, 'Second commit');
    expect(refs.singleWhere((r) => r.name == 'older').details, isNull);

    // A remote branch is checked out as a new branch tracking it.
    expect(await service.trackingBranches('origin/topic'), isEmpty);
    await service.checkout('origin/topic', track: true);
    expect((await service.status())!.head.branch, 'topic');
    expect(await service.trackingBranches('origin/topic'), ['topic']);

    await service.checkout(second, detached: true);
    expect((await service.status())!.head.branch, isNull);

    await service.branch('feature', ref: 'older');
    expect((await service.status())!.head.branch, 'feature');
    expect(await service.revParse('HEAD'), first);
    await expectLater(
      service.branch('feature', ref: 'HEAD'),
      throwsA(isA<IdeGitException>()),
    );
  }, skip: hasGit ? false : 'Git is not installed');

  test('outside a repository there is no status', () async {
    final outside = await Directory.systemTemp.createTemp('baocode_nogit_');
    addTearDown(() => outside.delete(recursive: true));
    final service = IdeGitService(outside.path);
    expect(await service.status(), isNull);
  }, skip: hasGit ? false : 'Git is not installed');

  test('the repository commits everything, untracked files included', () async {
    final repository = IdeGitRepository(
      IdeGitService(root),
      refreshDelay: Duration.zero,
    );
    addTearDown(repository.dispose);
    await repository.refresh();
    expect(repository.isRepository, isTrue);
    await write('lib/b.dart', 'b\n');
    await write('lib/a.dart', 'edited\n');
    await repository.refresh();
    expect(repository.state!.count, 2);
    await repository.commitEverything('Everything');
    expect(repository.state!.count, 0);
    final log = await repository.service.log();
    expect(log.first.subject, 'Everything');
  }, skip: hasGit ? false : 'Git is not installed');

  test('blame gives the commits of the lines on disk', () async {
    final service = IdeGitService(root);
    await write('lib/a.dart', 'a\nb\n');
    final blame = (await service.blame(p.join(root, 'lib/a.dart')))!;
    final commit = blame.singleWhere((b) => !b.uncommitted);
    expect(commit.subject, 'Initial commit');
    expect(commit.authorName, 'Ada');
    expect(commit.authorEmail, 'ada@example.com');
    expect(commit.hash, (await service.revParse('HEAD'))!);
    expect(commit.ranges, [(startLineNumber: 1, endLineNumber: 1)]);
    expect(blame.singleWhere((b) => b.uncommitted).ranges, [
      (startLineNumber: 2, endLineNumber: 2),
    ]);

    await write('lib/new.dart', 'new\n');
    expect(await service.blame(p.join(root, 'lib/new.dart')), isNull);
  }, skip: hasGit ? false : 'Git is not installed');
}
