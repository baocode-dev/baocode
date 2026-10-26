// Ask AI from Git: a commit (or several) from the log's menu, changes or
// conflicts from the Commit panel's, each a request put in the chat's
// composer to be looked over and sent; and the log's Interactively Rebase
// from Here, its list of commits.

import 'package:baocode/ide/git/ide_git_commit_panel.dart';
import 'package:baocode/ide/git/ide_git_rebase_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

void main() {
  late FakeGit git;
  late List<String> asked;

  setUp(() {
    git = FakeGit(testRoot)
      ..status = '## main\x00 M lib/a.dart\x00'
      ..log =
          '${gitLogRecord('c2', ['c1'], 'Second', refs: 'HEAD -> refs/heads/main')}\n'
          '${gitLogRecord('c1', [], 'First', time: 1767225000)}';
    git.refs['HEAD'] = 'c2';
    asked = [];
  });

  Future<void> pump(WidgetTester tester) async {
    await pumpWorkbench(
      tester,
      const {'lib/a.dart': 'a'},
      git: git.repository(),
      onAskInChat: asked.add,
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, Finder row, String item) async {
    await tester.tapAt(
      tester.getCenter(row),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  testWidgets('a commit, and changes, asked about in the chat', (tester) async {
    await pump(tester);
    await menu(
      tester,
      find
          .descendant(
            of: find.byType(IdeGitCommitPanel),
            matching: find.textContaining('a.dart', findRichText: true),
          )
          .first,
      'Ask AI About These Changes',
    );
    expect(asked.single, contains('git diff HEAD -- lib/a.dart'));
    await menu(tester, find.text('Second').first, 'Ask AI About This Commit');
    expect(asked.last, contains('git show c2'));
    expect(asked.last, contains('Second'));
  });

  testWidgets('Interactively Rebase from Here: the commits from it on', (
    tester,
  ) async {
    await pump(tester);
    await menu(
      tester,
      find.text('First').first,
      'Interactively Rebase from Here…',
    );
    expect(find.byType(IdeGitRebaseDialog), findsOneWidget);
    expect(find.text('Rebasing 2 Commits from c1'), findsOneWidget);
  });

  testWidgets('Fixup: the checked changes committed as a fixup! of the '
      'commit, squashed into it', (tester) async {
    await pump(tester);
    await menu(tester, find.text('Second').first, 'Fixup with Checked Changes');
    expect(git.callsTo('commit').single, [
      'commit',
      '--quiet',
      '-m',
      'fixup! c2',
      '--only',
      '--',
      'lib/a.dart',
    ]);
    expect(
      git.callsTo('-c').single,
      containsAllInOrder(['rebase', '-i', '--autosquash', '--autostash']),
    );
  });

  testWidgets("a change in a file's diff, from the button by it", (
    tester,
  ) async {
    git.show['HEAD:lib/a.dart'] = 'a\nb\nc\nd\n';
    await pumpWorkbench(
      tester,
      const {'lib/a.dart': 'a\nb\nc\nD\n'},
      git: git.repository(),
      onAskInChat: asked.add,
      size: const Size(1800, 900),
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(IdeGitCommitPanel),
            matching: find.textContaining('a.dart', findRichText: true),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.byTooltip('Leave This Change Out of the Commit')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ask AI About This Change'));
    await tester.pumpAndSettle();
    expect(asked.single, contains('lib/a.dart at line 4'));
    expect(asked.single, contains('```diff\n-d\n+D\n```'));
  });
}
