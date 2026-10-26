// JetBrains IDEs' branch popup, from the status bar's branch: the
// repository's actions, then the recent, local and remote branches, typed
// to narrow; a branch opens its actions.

import 'package:baocode/ide/git/git_service.dart';
import 'package:baocode/ide/git/ide_git_branch_popup.dart';
import 'package:baocode/ide/git/ide_git_push_dialog.dart';
import 'package:baocode/ide/ide_status_bar.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

final _main = 'a' * 40;
final _feature = 'b' * 40;

void main() {
  late FakeGit git;

  setUp(() {
    git = FakeGit(testRoot)
      ..status = '## main...origin/main\x00'
      ..log = gitLogRecord(_main, [], 'Main work', refs: 'HEAD -> refs/heads/main')
      ..forEachRef = [
        gitRefRecord('refs/heads/main', _main, upstream: 'origin/main'),
        gitRefRecord('refs/heads/feature', _feature),
        gitRefRecord('refs/heads/old', _feature),
        gitRefRecord('refs/remotes/origin/main', _main),
        gitRefRecord('refs/remotes/origin/topic', _feature),
      ].join('\n');
    git.refs['HEAD'] = _main;
    git.answers['reflog'] = const IdeGitOutput(
      0,
      'checkout: moving from feature to main\n'
      'commit: Main work\n'
      'checkout: moving from main to feature\n',
    );
  });

  Finder inPopup(Finder finder) =>
      find.descendant(of: find.byType(IdeGitBranchPopup), matching: finder);

  /// The popup's rows' texts, in order.
  List<String> rows(WidgetTester tester) => [
    for (final text in tester.widgetList<Text>(
      inPopup(
        find.descendant(of: find.byType(ListView), matching: find.byType(Text)),
      ),
    ))
      text.data!,
  ];

  Future<void> open(WidgetTester tester) async {
    await pumpWorkbench(tester, const {'a.dart': 'a'}, git: git.repository());
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(IdeStatusBar),
        matching: find.text('main'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the actions, then the recent, local and remote branches', (
    tester,
  ) async {
    await open(tester);
    expect(rows(tester), [
      'Update Project',
      'Commit…',
      'Push…',
      'New Branch…',
      'Checkout Tag or Revision…',
      'Manage Remotes…',
      'Recent',
      'feature',
      'Local Branches',
      'main',
      'feature',
      'old',
      'Remote Branches',
      'origin/main',
      'origin/topic',
    ]);
  });

  testWidgets('typed, the branches that match; Enter opens the actions of '
      'the one selected, which close the popup', (tester) async {
    await open(tester);
    await tester.enterText(inPopup(find.byType(EditableText)), 'top');
    await tester.pumpAndSettle();
    expect(rows(tester), ['Remote Branches', 'origin/topic']);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checkout'));
    await tester.pumpAndSettle();
    expect(find.byType(IdeGitBranchPopup), findsNothing);
    expect(git.callsTo('checkout').last, [
      'checkout',
      '-q',
      '--track',
      'origin/topic',
    ]);
  });

  testWidgets("Compare with Current lists the branch's commits the current "
      'one has not, and tells how many each has', (tester) async {
    git.answers['rev-list'] = const IdeGitOutput(0, '2\t1\n');
    await open(tester);
    await tester.enterText(inPopup(find.byType(EditableText)), 'old');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compare with “main”'));
    await tester.pumpAndSettle();
    expect(
      git.callsTo('log').last,
      contains('refs/heads/main..refs/heads/old'),
    );
    expect(
      find.textContaining('“old” has 2 commits “main” has not'),
      findsOneWidget,
    );
    expect(find.text('Show Changed Files'), findsOneWidget);
    expect(find.text('main..old'), findsOneWidget);
  });

  testWidgets('Down and Enter run an action; Escape closes', (tester) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(IdeGitBranchPopup), findsNothing);
    // Push…: the Push dialog.
    expect(find.byType(IdeGitPushDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(IdeGitPushDialog), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(IdeStatusBar),
        matching: find.text('main'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(IdeGitBranchPopup), findsNothing);
  });

  testWidgets('Update Project asks: merge or rebase; told not to ask again, '
      'it does as chosen', (tester) async {
    await open(tester);
    await tester.tap(inPopup(find.text('Update Project')));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Don't ask again"));
    await tester.tap(find.text('Rebase'));
    await tester.pumpAndSettle();
    expect(git.callsTo('fetch'), [
      ['fetch', '--all', '--tags'],
    ]);
    expect(git.callsTo('pull'), [
      ['pull', '--rebase', '--autostash', 'origin', 'main'],
    ]);

    await tester.tap(
      find.descendant(
        of: find.byType(IdeStatusBar),
        matching: find.text('main'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(inPopup(find.text('Update Project')));
    await tester.pumpAndSettle();
    expect(find.text('Merge'), findsNothing);
    expect(git.callsTo('pull'), hasLength(2));
    expect(git.callsTo('pull').last, contains('--rebase'));
  });
}
