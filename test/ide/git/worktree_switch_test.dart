// The IDE's Source Control shows another worktree of its repository, as
// picked on the Git log: its branch, its changes, what Git does there;
// the folder's own again when its main one is picked.

import 'package:baocode/ide/git/git_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../workbench/fake_files.dart';
import 'fake_git.dart';

void main() {
  testWidgets('a worktree picked shows; the main one again', (tester) async {
    final other = p.join(p.separator, 'project-wt');
    final worktrees =
        'worktree $testRoot\nHEAD ${'1' * 40}\nbranch refs/heads/main\n\n'
        'worktree $other\nHEAD ${'2' * 40}\nbranch refs/heads/feature\n';
    final main = FakeGit(testRoot)
      ..status = '## main\x00'
      ..worktrees = worktrees
      ..log =
          '${gitLogRecord('c2', ['c1'], 'Second', refs: 'refs/heads/feature')}\n'
          '${gitLogRecord('c1', [], 'First', refs: 'HEAD -> refs/heads/main')}';
    main.refs['HEAD'] = 'c1';
    final feature = FakeGit(other)
      ..status = '## feature\x00 M lib/b.dart\x00'
      ..worktrees = worktrees
      ..log = main.log;
    feature.refs['HEAD'] = 'c2';
    final opened = <String>[];
    final workspace = await pumpWorkbench(
      tester,
      const {'lib/a.dart': 'a'},
      git: main.repository(),
      openWorktree: (path) {
        opened.add(path);
        return feature.repository();
      },
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();

    // The worktrees' menu: no agent to follow in the IDE.
    await tester.tap(find.byTooltip('Worktree: $testRoot'));
    await tester.pumpAndSettle();
    expect(find.text('Follow the Agent'), findsNothing);
    await tester.tap(find.text('project-wt').last);
    await tester.pumpAndSettle();
    expect(opened, [other]);
    final IdeGitRepository shown = workspace.git!;
    expect(shown.service.root, other);
    // Its changes.
    expect(find.text('b.dart'), findsWidgets);

    await tester.tap(find.byTooltip('Worktree: $other'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('project  (main worktree)'));
    await tester.pumpAndSettle();
    expect(workspace.git!.service.root, testRoot);
  });
}
