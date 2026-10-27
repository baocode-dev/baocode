// A merge, rebase, cherry-pick or revert Git stopped in, as JetBrains IDEs
// show it over the changes: what, the conflicts left, Continue once there
// are none, Skip, Abort once confirmed; a conflict resolved with one side's
// version from its menu.

import 'package:baocode/ide/git/git_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

void main() {
  late FakeGit git;

  setUp(() {
    git = FakeGit(testRoot)
      ..status = '## main\x00UU lib/a.dart\x00DU lib/gone.dart\x00'
      ..operation = 'REBASE_HEAD'
      ..log = gitLogRecord('c1', [], 'First', refs: 'HEAD -> refs/heads/main');
    git.refs['HEAD'] = 'c1';
  });

  Future<void> open(WidgetTester tester) async {
    await pumpWorkbench(
      tester,
      const {'lib/a.dart': '<<<<<<< HEAD\na\n=======\nb\n>>>>>>> c2\n'},
      git: git.repository(),
      size: const Size(1800, 900),
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String file, String item) async {
    await tester.tapAt(
      tester.getCenter(find.textContaining(file, findRichText: true).first),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  test('the operation under way is read with the status', () async {
    final repository = git.repository();
    await repository.refresh(force: true);
    expect(repository.state!.operation, IdeGitOperation.rebase);
    git.operation = null;
    await repository.refresh(force: true);
    expect(repository.state!.operation, isNull);
  });

  testWidgets('what Git stopped in, the conflicts left; one side taken, '
      "a file that side deleted removed", (tester) async {
    await open(tester);
    expect(find.text('Rebasing · main  —  2 conflicts left'), findsOneWidget);

    await menu(tester, 'a.dart', 'Accept Incoming (Theirs)');
    expect(git.callsTo('checkout'), [
      ['checkout', '--theirs', '--', 'lib/a.dart'],
    ]);
    expect(git.callsTo('add'), [
      ['add', '--', 'lib/a.dart'],
    ]);
    // Deleted by us: the current side has none.
    await menu(tester, 'gone.dart', 'Accept Current (Ours)');
    expect(git.callsTo('rm'), [
      ['rm', '-q', '--', 'lib/gone.dart'],
    ]);
  });

  testWidgets('Continue once resolved; Abort once confirmed', (tester) async {
    // One resolved and staged, one changed besides: both checked.
    git.status = '## main\x00M  lib/a.dart\x00 M lib/b.dart\x00';
    await open(tester);
    expect(find.text('Rebasing · main  —  conflicts resolved'), findsOne);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    // What is checked goes into the commit, as Commit takes it.
    expect(git.callsTo('add').last, [
      'add',
      '-A',
      '--',
      'lib/a.dart',
      'lib/b.dart',
    ]);
    expect(git.callsTo('-c').last, [
      '-c',
      'core.editor=:',
      'rebase',
      '--continue',
    ]);

    await tester.tap(find.text('Abort'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Abort? Rebasing stops'), findsOneWidget);
    await tester.tap(find.text('Abort').last);
    await tester.pumpAndSettle();
    expect(git.callsTo('-c').last, [
      '-c',
      'core.editor=:',
      'rebase',
      '--abort',
    ]);
  });
}
