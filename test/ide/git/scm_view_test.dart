import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/git/ide_git_commit_panel.dart';
import 'package:baocode/ide/git/git_model.dart';
import 'package:baocode/ide/git/git_service.dart';
import 'package:baocode/ide/ide_code_diff.dart';
import 'package:baocode/ide/ide_button.dart';
import 'package:baocode/ide/ide_input.dart';
import 'package:baocode/ide/ide_explorer.dart';
import 'package:baocode/ide/ide_list.dart';
import 'package:baocode/ide/ide_modern_ui.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

/// The Source Control view against a fake Git: what it shows, and the
/// commands and confirmations its actions run.
void main() {
  late FakeGit git;

  setUp(() {
    git = FakeGit(testRoot);
    git.status =
        '## main...origin/main [ahead 1]\x00'
        'M  lib/staged.dart\x00'
        ' M lib/a.dart\x00'
        '?? notes.md\x00';
  });

  Future<void> showScm(WidgetTester tester) async {
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();
  }

  Future<void> pumpScm(
    WidgetTester tester, {
    Map<String, String> files = const {
      'lib/a.dart': 'a',
      'lib/staged.dart': 's',
      'notes.md': 'n',
    },
  }) async {
    await pumpWorkbench(tester, files, git: git.repository());
    await tester.pumpAndSettle();
    await showScm(tester);
  }

  /// A resource's label, or else a text.
  Finder text(String name) => find.byWidgetPredicate(
    (widget) =>
        (widget is IdeResourceLabel && widget.name == name) ||
        (widget is Text && widget.data == name),
  );

  Finder rowOf(String name) =>
      find.ancestor(of: text(name), matching: find.byType(IdeListRow));

  /// The commit message's input, under the local changes' row.
  final message = find
      .descendant(
        of: find.byType(IdeGitCommitPanel),
        matching: find.byType(TextField),
      )
      .first;

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    await tester.tapAt(
      tester.getCenter(finder),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('without a repository provider it says so', (tester) async {
    await pumpWorkbench(tester, const {'a.txt': 'a'});
    await showScm(tester);
    expect(find.text('No source control providers registered.'), findsOne);
  });

  testWidgets('a folder without a repository can be initialized', (
    tester,
  ) async {
    git.isRepository = false;
    await pumpScm(tester);
    expect(
      find.textContaining("doesn't have a Git repository"),
      findsOneWidget,
    );
    await tester.tap(find.text('Initialize Repository'));
    await tester.pumpAndSettle();
    expect(git.callsTo('init'), hasLength(1));
    expect(find.text('Changes'), findsWidgets);
    expect(find.text('Local Changes (3)'), findsOneWidget);
  });

  /// Clicks a row's check box.
  Future<void> check(WidgetTester tester, String name) async {
    await tester.tap(
      find.descendant(
        of: rowOf(name).last,
        matching: find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_Check',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder button(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(IdeButton));

  testWidgets('lists the changes as JetBrains IDEs do: the tracked ones '
      'checked, the unversioned not, the names in their status\'s colors', (
    tester,
  ) async {
    await pumpScm(tester);
    // The log's first row, the local changes, selected.
    expect(find.text('Local Changes (3)'), findsOneWidget);
    final input = tester.widget<TextField>(message);
    expect(input.decoration!.hintText, 'Commit Message');

    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('Unversioned Files'), findsOneWidget);
    expect(find.text('2 files'), findsOneWidget);
    expect(find.text('1 file'), findsOneWidget);
    expect(find.text('2 of 3 files checked'), findsOneWidget);
    // By directory (the default): the folder, then the name in its color.
    expect(rowOf('lib'), findsWidgets);
    final a = tester.widget<IdeResourceLabel>(
      find.descendant(
        of: rowOf('a.dart'),
        matching: find.byType(IdeResourceLabel),
      ),
    );
    expect(a.nameColor, IdeGitStatus.modified.color);

    // Checked, the unversioned file counts.
    await check(tester, 'notes.md');
    expect(find.text('3 of 3 files checked'), findsOneWidget);
    // A folder unchecks what is under it.
    await check(tester, 'lib');
    expect(find.text('1 of 3 files checked'), findsOneWidget);

    // The activity bar counts every change.
    expect(find.text('3'), findsOneWidget);
    // So does the status bar's branch.
    expect(find.text('main'), findsWidgets);
  });

  testWidgets('the activity badge counts in thousands past 999', (
    tester,
  ) async {
    expect(ideBadgeLabel(999), '999');
    expect(ideBadgeLabel(1000), '1K');
    expect(ideBadgeLabel(1234), '1K+');
    expect(ideBadgeLabel(12000), '12K');
  });

  testWidgets('past the status limit it says so, and builds only the rows '
      'shown', (tester) async {
    git.status = [
      '## main\x00',
      for (var i = 0; i <= IdeGitService.statusLimit; i++)
        '?? many/f$i.txt\x00',
    ].join();
    await pumpScm(tester);
    expect(find.textContaining('too many changes'), findsOneWidget);
    expect(find.text('10K'), findsWidgets);
    expect(find.byType(IdeListRow).evaluate().length, lessThan(100));
  });

  testWidgets('a group folds and unfolds', (tester) async {
    await pumpScm(tester);
    await tester.tap(find.text('Unversioned Files'));
    await tester.pumpAndSettle();
    expect(text('notes.md'), findsNothing);
    await tester.tap(find.text('Unversioned Files'));
    await tester.pumpAndSettle();
    expect(text('notes.md'), findsOneWidget);
  });

  testWidgets('committing asks for a message, and for files checked', (
    tester,
  ) async {
    await pumpScm(tester);
    await tester.tap(button('Commit'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a commit message.'), findsOneWidget);
    expect(git.callsTo('commit'), isEmpty);
    await tester.enterText(message, 'W');
    await tester.pumpAndSettle();
    expect(find.text('Enter a commit message.'), findsNothing);

    await check(tester, 'lib');
    await tester.tap(button('Commit'));
    await tester.pumpAndSettle();
    expect(find.text('Check the files to commit.'), findsOneWidget);
    expect(git.callsTo('commit'), isEmpty);
  });

  testWidgets('commits the files checked as they are, an unversioned one '
      'added first, and clears the message', (tester) async {
    await pumpScm(tester);
    await check(tester, 'notes.md');
    await tester.enterText(message, 'Fix a bug');
    git.onCommand = (arguments) {
      if (arguments.first == 'commit') git.status = '## main\x00';
    };
    await tester.tap(button('Commit'));
    await tester.pumpAndSettle();
    expect(git.callsTo('add').single, ['add', '-A', '--', 'notes.md']);
    expect(git.callsTo('commit').single, [
      'commit',
      '--quiet',
      '-m',
      'Fix a bug',
      '--only',
      '--',
      'lib/a.dart',
      'lib/staged.dart',
      'notes.md',
    ]);
    expect(find.text('Fix a bug'), findsNothing);
    expect(find.text('No local changes'), findsOneWidget);
  });

  testWidgets('Amend brings the last commit\'s message, and amends it', (
    tester,
  ) async {
    git.refs['HEAD'] = 'c2';
    git.log = gitLogRecord('c2', ['c1'], 'Oops');
    await pumpScm(tester);
    await tester.tap(find.text('Amend'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(message).controller!.text, 'Oops');
    await tester.tap(button('Commit'));
    await tester.pumpAndSettle();
    expect(
      git.callsTo('commit').single,
      containsAllInOrder([
        'commit',
        '--quiet',
        '--amend',
        '-m',
        'Oops',
        '--only',
      ]),
    );
  });

  testWidgets('Commit and Push publishes a branch without an upstream', (
    tester,
  ) async {
    git.status = '## feature/x\x00 M lib/a.dart\x00';
    await pumpScm(tester);
    await tester.enterText(message, 'Ship it');
    await tester.tap(button('Commit and Push'));
    await tester.pumpAndSettle();
    expect(git.callsTo('commit'), hasLength(1));
    expect(git.callsTo('push').single, ['push', '-u', 'origin', 'feature/x']);
  });

  testWidgets('Rollback asks, then brings the file back from HEAD', (
    tester,
  ) async {
    await pumpScm(tester);
    await rightClick(tester, rowOf('a.dart'));
    for (final item in [
      'Show Diff',
      'Jump to Source',
      'Rollback…',
      'Copy Path',
      'Copy Relative Path',
      'Reveal in Explorer View',
    ]) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
    await tester.tap(find.text('Rollback…'));
    await tester.pumpAndSettle();
    expect(find.text('Roll back the changes of 1 file?'), findsOneWidget);
    await tester.tap(find.text('Rollback'));
    await tester.pumpAndSettle();
    expect(git.callsTo('checkout').single, [
      'checkout',
      '-q',
      'HEAD',
      '--',
      'lib/a.dart',
    ]);
  });

  testWidgets('an unversioned file is added to Git from its menu', (
    tester,
  ) async {
    await pumpScm(tester);
    await rightClick(tester, rowOf('notes.md'));
    await tester.tap(find.text('Add to VCS'));
    await tester.pumpAndSettle();
    expect(git.callsTo('add').single, ['add', '-A', '--', 'notes.md']);
  });

  testWidgets('a resource shows its change in the log; Reveal in Explorer '
      'View selects it', (tester) async {
    final workspace = await pumpWorkbench(tester, const {
      'lib/a.dart': 'a',
      'lib/staged.dart': 's',
      'notes.md': 'n',
    }, git: git.repository());
    await tester.pumpAndSettle();
    await showScm(tester);
    await tester.tap(rowOf('a.dart'));
    await tester.pumpAndSettle();
    // In the table's place, the editor left as it was.
    expect(find.byType(IdeCodeDiff), findsOneWidget);
    expect(workspace.active, isNull);
    // Back to the log after.
    // As the list has them: a step to the next, selected there too.
    expect(find.text('1 / 3'), findsOneWidget);
    IdeGitCommitPanelState panel() =>
        tester.state(find.byType(IdeGitCommitPanel));
    expect(panel().selectedFile, endsWith('a.dart'));
    await tester.tap(find.byTooltip(RegExp('^Next File')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(panel().selectedFile, endsWith('staged.dart'));
    await tester.tap(find.byTooltip(RegExp('^Back to Log')));
    await tester.pumpAndSettle();
    expect(find.byType(IdeCodeDiff), findsNothing);
    expect(find.text('Local Changes (3)'), findsOneWidget);

    await rightClick(tester, rowOf('notes.md'));
    await tester.tap(find.text('Reveal in Explorer View'));
    await tester.pumpAndSettle();
    expect(find.text('Explorer'), findsOneWidget);
    final explorer = tester.widget<IdeExplorer>(find.byType(IdeExplorer));
    expect(explorer.controller.selected, inRoot('notes.md'));
  });

  testWidgets('Enter opens the change in the editor, the log left', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(tester, const {
      'lib/a.dart': 'a',
      'lib/staged.dart': 's',
      'notes.md': 'n',
    }, git: git.repository());
    await tester.pumpAndSettle();
    await showScm(tester);
    await tester.tap(rowOf('a.dart'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(workspace.active?.title, 'a.dart (Working Tree)');
    expect(find.text('Local Changes (3)'), findsNothing);
    expect(find.text('Explorer'), findsOneWidget);
  });

  testWidgets('the log shows commits, references and a commit\'s files', (
    tester,
  ) async {
    git.status = '## main\x00';
    git.refs['HEAD'] = 'c2';
    git.log =
        '${gitLogRecord('c2', ['c1'], 'Second', refs: 'HEAD -> refs/heads/main, tag: refs/tags/v1')}\n'
        '${gitLogRecord('c1', [], 'First', author: 'Grace', refs: 'refs/heads/topic, tag: refs/tags/v0')}';
    git.show['c2'] = 'M\x00lib/a.dart\x00A\x00lib/b.dart\x00';
    await pumpScm(tester, files: const {'lib/a.dart': 'a', 'lib/b.dart': 'b'});
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Grace'), findsOneWidget);
    // Every reference's badge carries its name: HEAD's branch, the other
    // branches and the tags.
    expect(find.text('main'), findsWidgets);
    for (final name in ['v1', 'topic', 'v0']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }

    await tester.tap(find.text('Second'));
    await tester.pumpAndSettle();
    expect(git.callsTo('show').map((call) => call.last), everyElement('c2'));
    expect(find.text('commit: c2'), findsOneWidget);
    expect(find.text('2 files'), findsOneWidget);
    expect(text('b.dart'), findsOneWidget);
    final label = tester.widget<IdeResourceLabel>(
      find.descendant(
        of: rowOf('b.dart'),
        matching: find.byType(IdeResourceLabel),
      ),
    );
    expect((label.letter, label.description), ('A', 'lib'));

    // As a tree: the files under their folder, one level in; the folder
    // closes and opens.
    await tester.tap(find.text('Tree'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(text('b.dart')).dx,
      greaterThan(tester.getTopLeft(text('lib')).dx),
    );
    await tester.tap(rowOf('lib'));
    await tester.pumpAndSettle();
    expect(text('b.dart'), findsNothing);
    await tester.tap(rowOf('lib'));
    await tester.pumpAndSettle();
    expect(text('b.dart'), findsOneWidget);

    // The filter keeps the files that match, wildcards or not.
    await tester.enterText(
      find.descendant(
        of: find.ancestor(
          of: find.text('Filter files (* and ? match any)'),
          matching: find.byType(IdeInputBox),
        ),
        matching: find.byType(TextField),
      ),
      'b.*',
    );
    await tester.pumpAndSettle();
    expect(text('b.dart'), findsOneWidget);
    expect(text('a.dart'), findsNothing);

    // A file's changes, in the table's place.
    await tester.tap(rowOf('b.dart'));
    await tester.pumpAndSettle();
    expect(find.byType(IdeCodeDiff), findsOneWidget);
  });

  testWidgets('a refresh shows a new commit', (tester) async {
    git.status = '## main\x00';
    git.refs['HEAD'] = 'c2';
    git.log =
        '${gitLogRecord('c2', ['c1'], 'Second', refs: 'HEAD -> refs/heads/main')}\n'
        '${gitLogRecord('c1', [], 'First')}';
    await pumpScm(tester);
    expect(find.text('Third'), findsNothing);
    git.refs['HEAD'] = 'c3';
    git.log =
        '${gitLogRecord('c3', ['c2'], 'Third', refs: 'HEAD -> refs/heads/main')}\n'
        '${gitLogRecord('c2', ['c1'], 'Second')}\n'
        '${gitLogRecord('c1', [], 'First')}';
    await tester.tap(find.byTooltip('More Actions...').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh').last);
    await tester.pumpAndSettle();
    expect(find.text('Third'), findsOneWidget);
  });

  testWidgets('the log shows all branches, or the current one, or those '
      'filtered', (tester) async {
    git.status = '## main\x00';
    git.refs['HEAD'] = 'c2';
    git.forEachRef = gitRefRecord('refs/heads/feature', 'f' * 40);
    git.log =
        '${gitLogRecord('f1', ['c1'], 'On feature', refs: 'refs/heads/feature')}\n'
        '${gitLogRecord('c2', ['c1'], 'On main', refs: 'HEAD -> refs/heads/main')}\n'
        '${gitLogRecord('c1', [], 'First')}';
    await pumpScm(tester);
    List<String> lastLog() => git.callsTo('log').last;
    expect(lastLog(), containsAllInOrder(['HEAD', '--branches', '--remotes']));
    expect(find.text('On feature'), findsOneWidget);

    await tester.tap(find.text('All Branches'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Branch'));
    await tester.pumpAndSettle();
    expect(lastLog(), isNot(contains('--branches')));

    await tester.tap(find.text('Current Branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Local Branches'));
    await tester.pumpAndSettle();
    // The menu's, over the badge's.
    await tester.tap(find.text('feature').last);
    await tester.pumpAndSettle();
    expect(lastLog(), containsAllInOrder(['refs/heads/feature', '--']));

    // A message's terms, any of them; then the filters cleared.
    await tester.enterText(
      find.descendant(
        of: find.ancestor(
          of: find.text('Search messages; separate several with |'),
          matching: find.byType(IdeInputBox),
        ),
        matching: find.byType(TextField),
      ),
      'fix | feat',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      lastLog(),
      containsAll(['-i', '--fixed-strings', '--grep=fix', '--grep=feat']),
    );
    await tester.tap(find.byTooltip('Clear Filters'));
    await tester.pumpAndSettle();
    expect(lastLog(), isNot(contains('--grep=fix')));
    expect(lastLog(), contains('--branches'));
  });

  testWidgets('Undo Commit on the last commit brings its message back', (
    tester,
  ) async {
    git.status = '## main\x00';
    git.refs['HEAD'] = 'c2';
    git.log = gitLogRecord(
      'c2',
      ['c1'],
      'Oops\n\nDetails',
      refs: 'HEAD -> refs/heads/main',
    );
    git.onCommand = (arguments) {
      if (arguments.first == 'reset') {
        git.status = '## main\x00 M lib/a.dart\x00';
      }
    };
    await pumpScm(tester);
    await rightClick(tester, find.text('Oops'));
    await tester.tap(find.text('Undo Commit'));
    await tester.pumpAndSettle();
    expect(git.callsTo('reset').single, ['reset', '--soft', 'HEAD~']);
    final input = tester.widget<TextField>(message);
    expect(input.controller!.text, 'Oops\n\nDetails');
  });
}
