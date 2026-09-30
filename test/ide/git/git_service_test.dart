@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/git/git_model.dart';
import 'package:monad/ide/git/git_repository.dart';
import 'package:monad/ide/git/git_service.dart';
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
    temp = await Directory.systemTemp.createTemp('monad_git_');
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

  test('outside a repository there is no status', () async {
    final outside = await Directory.systemTemp.createTemp('monad_nogit_');
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
}
