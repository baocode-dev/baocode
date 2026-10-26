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
/// repository's changes known and listed under its own header, committed
/// with one message, as JetBrains IDEs do.
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

  testWidgets('#76 the local changes list every repository, each under its '
      'header, with one message for them all', (tester) async {
    await pumpScm(tester);
    expect(header(testRoot), findsOneWidget);
    expect(header(inRoot('app')), findsOneWidget);
    expect(find.text('README.md'), findsWidgets);
    expect(find.text('new.dart'), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);
    expect(scmInputs(), findsOneWidget);
    expect(find.text('2 of 3 files checked'), findsOneWidget);
  });

  testWidgets('the repository shown: its header folds and unfolds it', (
    tester,
  ) async {
    await pumpScm(tester);
    // The app's: shown first, then folded.
    await tester.tap(header(inRoot('app')));
    await tester.pumpAndSettle();
    expect(find.text('new.dart'), findsOneWidget);
    await tester.tap(header(inRoot('app')));
    await tester.pumpAndSettle();
    expect(find.text('new.dart'), findsNothing);
    expect(find.text('main.dart'), findsNothing);
    // The other repository's changes stay.
    expect(find.text('README.md'), findsWidgets);

    await tester.tap(header(inRoot('app')));
    await tester.pumpAndSettle();
    expect(find.text('new.dart'), findsOneWidget);
  });

  testWidgets('#76 a repository clicked becomes the one shown', (tester) async {
    await pumpScm(tester);
    final workspace = tester
        .state<IdeWorkbenchState>(find.byType(IdeWorkbench))
        .widget
        .workspace;
    expect(workspace.git?.service.root, testRoot);
    await tester.tap(header(inRoot('app')));
    await tester.pumpAndSettle();
    expect(workspace.git?.service.root, inRoot('app'));
    // Shown, not folded.
    expect(find.text('main.dart'), findsOneWidget);
  });

  testWidgets('#76 one message commits each repository\'s files checked', (
    tester,
  ) async {
    own.status = '## main\x00M  README.md\x00';
    app.status = '## dev\x00M  main.dart\x00';
    await pumpScm(tester);
    await tester.enterText(scmInputs(), 'Update both');
    await tester.tap(find.text('Commit').last);
    await tester.pumpAndSettle();
    expect(app.callsTo('commit').single, [
      'commit',
      '--quiet',
      '-m',
      'Update both',
      '--only',
      '--',
      'main.dart',
    ]);
    expect(own.callsTo('commit').single, [
      'commit',
      '--quiet',
      '-m',
      'Update both',
      '--only',
      '--',
      'README.md',
    ]);
  });

  testWidgets('#76 a repository without changes is left out', (tester) async {
    own.status = '## main\x00';
    await pumpScm(tester);
    expect(find.byKey(ValueKey('r:$testRoot')), findsNothing);
    expect(header(inRoot('app')), findsOneWidget);
    expect(group(testRoot, 'changes'), findsNothing);
    expect(group(inRoot('app'), 'changes'), findsWidgets);
  });

  testWidgets('#76 a repository\'s folded group stays folded as the one '
      'shown changes', (tester) async {
    await pumpScm(tester);
    await tester.tap(group(inRoot('app'), 'unversioned').first);
    await tester.pumpAndSettle();
    expect(find.text('new.dart'), findsNothing);

    await tester.tap(header(inRoot('app')));
    await tester.pumpAndSettle();
    await tester.tap(header(testRoot));
    await tester.pumpAndSettle();
    expect(find.text('README.md'), findsWidgets);
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
