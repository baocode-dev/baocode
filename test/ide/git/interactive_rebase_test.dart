// JetBrains IDEs' interactive rebase, in a real repository: commits put in
// another order, reworded, squashed, fixed up and dropped with no editor;
// one to edit leaves the rebase stopped there.

import 'dart:io';

import 'package:baocode/ide/git/git_model.dart';
import 'package:baocode/ide/git/git_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late String root;
  late IdeGitService service;

  Future<String> git(List<String> arguments) async {
    final result = await Process.run('git', arguments, workingDirectory: root);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return result.stdout as String;
  }

  Future<void> commit(String name) async {
    File(p.join(root, '$name.txt')).writeAsStringSync('$name\n');
    await git(['add', '.']);
    await git(['commit', '-q', '-m', name]);
  }

  Future<List<String>> subjects() async =>
      (await git(['log', '--format=%s'])).trim().split('\n');

  setUp(() async {
    final folder = await Directory.systemTemp.createTemp('rebase');
    addTearDown(() => folder.delete(recursive: true));
    root = folder.resolveSymbolicLinksSync();
    await git(['init', '-q']);
    await git(['config', 'user.email', 'a@b.c']);
    await git(['config', 'user.name', 'A']);
    for (final name in ['a', 'b', 'c', 'd', 'e']) {
      await commit(name);
    }
    service = IdeGitService(root);
  });

  Future<Map<String, IdeGitCommit>> commits() async => {
    for (final commit in await service.log()) commit.subject: commit,
  };

  test('reordered, reworded, squashed, fixed up and dropped', () async {
    if ((await Process.run('git', ['--version'])).exitCode != 0) return;
    final by = await commits();
    final stopped = await service.interactiveRebase(by['b']!, [
      IdeGitRebaseStep(by['d']!.id, IdeGitRebaseAction.pick),
      IdeGitRebaseStep(
        by['b']!.id,
        IdeGitRebaseAction.reword,
        message: 'B, "quoted" \$HOME `x`\n\nWith a body.',
      ),
      IdeGitRebaseStep(by['c']!.id, IdeGitRebaseAction.fixup),
      IdeGitRebaseStep(by['e']!.id, IdeGitRebaseAction.drop),
    ]);
    expect(stopped, isFalse);
    expect(await subjects(), ['B, "quoted" \$HOME `x`', 'd', 'a']);
    expect(
      (await git(['log', '-1', '--format=%B'])).trim(),
      'B, "quoted" \$HOME `x`\n\nWith a body.',
    );
    expect(
      (await git(['show', '--name-only', '--format=', 'HEAD'])).trim(),
      'b.txt\nc.txt',
    );
    expect(File(p.join(root, 'e.txt')).existsSync(), isFalse);
  });

  test('squashed: the messages one after another', () async {
    if ((await Process.run('git', ['--version'])).exitCode != 0) return;
    final by = await commits();
    await service.interactiveRebase(by['d']!, [
      IdeGitRebaseStep(by['d']!.id, IdeGitRebaseAction.pick),
      IdeGitRebaseStep(by['e']!.id, IdeGitRebaseAction.squash),
    ]);
    expect(await subjects(), ['d', 'c', 'b', 'a']);
    expect(
      (await git(['log', '-1', '--format=%B'])).trim().split(RegExp(r'\n+')),
      ['d', 'e'],
    );
  });

  test('a commit to edit: stopped there, a rebase under way', () async {
    if ((await Process.run('git', ['--version'])).exitCode != 0) return;
    final by = await commits();
    final stopped = await service.interactiveRebase(by['c']!, [
      IdeGitRebaseStep(by['c']!.id, IdeGitRebaseAction.edit),
      IdeGitRebaseStep(by['d']!.id, IdeGitRebaseAction.reword, message: 'D'),
      IdeGitRebaseStep(by['e']!.id, IdeGitRebaseAction.pick),
    ]);
    expect(stopped, isTrue);
    expect(await subjects(), ['c', 'b', 'a']);
    // Continued later, the new message still there.
    final result = await Process.run('git', [
      '-c',
      'core.editor=:',
      'rebase',
      '--continue',
    ], workingDirectory: root);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(await subjects(), ['e', 'D', 'c', 'b', 'a']);
  });

  test('Fixup: a fixup! commit squashed into its commit', () async {
    if ((await Process.run('git', ['--version'])).exitCode != 0) return;
    final by = await commits();
    File(p.join(root, 'b.txt')).writeAsStringSync('b2\n');
    await git(['commit', '-q', '-am', 'fixup! ${by['b']!.id}']);
    await service.autosquash(by['b']!);
    expect(await subjects(), ['e', 'd', 'c', 'b', 'a']);
    expect(await git(['show', 'HEAD~3:b.txt']), 'b2\n');
  });
}
