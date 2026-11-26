import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/git/ide_git_commit_panel.dart';
import 'package:baocode/ide/git/repository_scan.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/ide_workspace.dart';

import '../git/fake_git.dart';
import 'fake_files.dart';

/// The local changes with more than one repository (#68, #76): every
/// repository's changes known, the one shown listed alone under its header
/// and committed.
void main() {
  late FakeGit own;
  late FakeGit app;

  setUp(() {
    own = FakeGit(testRoot)..status = '## main\x00 M README.md\x00';
    app = FakeGit(inRoot('app'))
      ..status = '## dev\x00 M main.dart\x00?? new.dart\x00';
  });

  Future<void> pumpScm(WidgetTester tester) async {
    await pumpWorkbench(
      tester,
      const {'README.md': '', 'app/main.dart': '', 'app/new.dart': ''},
      git: own.repository(),
      repositoryDetection: IdeRepositoryDetection(
        find: (_) async => [inRoot('app')],
        open: (_) => app.repository(),
      ),
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();
  }

  testWidgets('the activity bar counts every repository\'s changes', (
    tester,
  ) async {
    await pumpScm(tester);
    // README.md + main.dart + new.dart.
    expect(find.text('3'), findsWidgets);
  });

  Finder header(String root) => find.byKey(ValueKey('r:$root')).first;

  Finder group(String root, String kind) =>
      find.byKey(ValueKey('g:$root:$kind'));

  Finder scmInputs() => find.descendant(
    of: find.byType(IdeGitCommitPanel),
    matching: find.byType(TextField),
  );

  IdeWorkspace workspaceOf(WidgetTester tester) => tester
      .state<IdeWorkbenchState>(find.byType(IdeWorkbench))
      .widget
      .workspace;

  /// Makes [root]'s repository the one shown, as the log's repository menu
  /// does.
  Future<void> show(WidgetTester tester, String root) async {
    final workspace = workspaceOf(tester);
    workspace.selectRepository(
      workspace.repositories.firstWhere((r) => r.$2.service.root == root).$2,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('#76 the local changes list the repository shown alone, under '
      'its header', (tester) async {
    await pumpScm(tester);
    expect(workspaceOf(tester).git?.service.root, testRoot);
    expect(header(testRoot), findsOneWidget);
    expect(find.byKey(ValueKey('r:${inRoot('app')}')), findsNothing);
    expect(find.text('README.md'), findsWidgets);
    expect(find.text('new.dart'), findsNothing);
    expect(find.text('main.dart'), findsNothing);
    expect(scmInputs(), findsOneWidget);
    expect(find.text('1 of 1 files checked'), findsOneWidget);

    await show(tester, inRoot('app'));
    expect(header(inRoot('app')), findsOneWidget);
    expect(find.byKey(ValueKey('r:$testRoot')), findsNothing);
    expect(find.text('new.dart'), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('1 of 2 files checked'), findsOneWidget);
  });

  testWidgets('the repository shown: its header folds and unfolds it', (
    tester,
  ) async {
    await pumpScm(tester);
    await show(tester, inRoot('app'));
    expect(find.text('new.dart'), findsOneWidget);
    await tester.tap(header(inRoot('app')));
    await tester.pumpAndSettle();
    expect(find.text('new.dart'), findsNothing);
    expect(find.text('main.dart'), findsNothing);

    await tester.tap(header(inRoot('app')));
    await tester.pumpAndSettle();
    expect(find.text('new.dart'), findsOneWidget);
  });

  testWidgets('#76 the message commits the shown repository\'s files '
      'checked alone', (tester) async {
    own.status = '## main\x00M  README.md\x00';
    app.status = '## dev\x00M  main.dart\x00';
    await pumpScm(tester);
    await show(tester, inRoot('app'));
    await tester.enterText(scmInputs(), 'Update the app');
    await tester.tap(find.text('Commit').last);
    await tester.pumpAndSettle();
    expect(app.callsTo('commit').single, [
      'commit',
      '--quiet',
      '-m',
      'Update the app',
      '--only',
      '--',
      'main.dart',
    ]);
    expect(own.callsTo('commit'), isEmpty);
  });

  testWidgets('#76 the shown repository without changes lists none, not '
      'another\'s', (tester) async {
    own.status = '## main\x00';
    await pumpScm(tester);
    expect(find.byKey(ValueKey('r:$testRoot')), findsNothing);
    expect(find.byKey(ValueKey('r:${inRoot('app')}')), findsNothing);
    expect(group(testRoot, 'changes'), findsNothing);
    expect(group(inRoot('app'), 'changes'), findsNothing);
  });

  testWidgets('#76 a repository\'s folded group stays folded as the one '
      'shown changes', (tester) async {
    await pumpScm(tester);
    await show(tester, inRoot('app'));
    await tester.tap(group(inRoot('app'), 'unversioned').first);
    await tester.pumpAndSettle();
    expect(find.text('new.dart'), findsNothing);

    await show(tester, testRoot);
    expect(find.text('README.md'), findsWidgets);
    await show(tester, inRoot('app'));
    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('new.dart'), findsNothing);
  });

  test('#68 the workspace knows each file\'s repository', () async {
    final workspace = IdeWorkspace(
      testRoot,
      files: TreeFiles(const {}),
      git: own.repository(),
      repositoryDetection: IdeRepositoryDetection(
        find: (_) async => [inRoot('app')],
        open: (_) => app.repository(),
      ),
    );
    addTearDown(workspace.dispose);
    await pumpEventQueue();
    final ownGit = workspace.repositories.first.$2;
    final appGit = workspace.repositories.last.$2;
    expect(workspace.gitAt(inRoot('app/main.dart')), same(appGit));
    expect(workspace.gitAt(inRoot('README.md')), same(ownGit));
  });

  IdeWorkbenchState workbench(WidgetTester tester) =>
      tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

  testWidgets('#73/#39 Git: Fetch From All Remotes fetches every repository', (
    tester,
  ) async {
    await pumpScm(tester);
    final state = workbench(tester);
    expect(state.commandsById['git.fetchAll']?.enabled, isTrue);
    expect(state.runCommand('git.fetchAll'), isTrue);
    await tester.pumpAndSettle();
    expect(own.callsTo('fetch'), isNotEmpty);
    expect(app.callsTo('fetch'), isNotEmpty);
  });

  testWidgets('a repository\'s ... Fetch From All Remotes fetches that '
      'repository alone', (tester) async {
    await pumpScm(tester);
    await show(tester, inRoot('app'));
    await tester.tap(header(inRoot('app')), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    for (final item in ['Fetch From All Remotes', 'Pull', 'Push']) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
    await tester.tap(find.text('Fetch From All Remotes'));
    await tester.pumpAndSettle();
    expect(app.callsTo('fetch'), isNotEmpty);
    expect(own.callsTo('fetch'), isEmpty);
  });

  testWidgets('Git: Pull and Git: Push run on the shown repository', (
    tester,
  ) async {
    own.status = '## main...origin/main [ahead 1]\x00 M README.md\x00';
    await pumpScm(tester);
    final state = workbench(tester);
    expect(state.runCommand('git.pull'), isTrue);
    await tester.pumpAndSettle();
    expect(own.callsTo('pull').single, ['pull', '--tags', 'origin', 'main']);

    expect(state.runCommand('git.push'), isTrue);
    await tester.pumpAndSettle();
    expect(own.callsTo('push').single, ['push', 'origin', 'main:main']);
  });
}
