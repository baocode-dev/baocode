// JetBrains IDEs' changelists: changes sorted into named lists, one
// active, where a change first goes; a list's changes left unchecked while
// it is not active.

import 'package:baocode/ide/git/git_changelists.dart';
import 'package:baocode/ide/git/ide_git_commit_panel.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

void main() {
  test('a list made active: the changes in none stay where they were', () {
    final lists = IdeGitChangelists();
    final feature = lists.create('Feature', paths: ['/a']);
    expect(lists.listOf('/a'), feature.id);
    expect(lists.listOf('/b'), IdeGitChangelists.defaultId);
    lists.setActive(feature.id, unassigned: ['/a', '/b']);
    expect(lists.listOf('/b'), IdeGitChangelists.defaultId);
    expect(lists.listOf('/c'), feature.id);
    lists.remove(feature.id);
    expect(lists.active, IdeGitChangelists.defaultId);
    expect(lists.listOf('/a'), IdeGitChangelists.defaultId);
  });

  test('restored: an agent turn\'s list there once was is not, its files '
      'the active list\'s', () {
    final lists = IdeGitChangelists()
      ..restore({
        'active': 'default',
        'lists': [
          {'id': 'list1', 'name': 'Mine'},
          {'id': 'turn:t1', 'name': 'AI: fix it', 'turn': true},
        ],
        'assigned': {'/a': 'list1', '/b': 'turn:t1'},
      });
    expect([for (final list in lists.lists) list.id], ['default', 'list1']);
    expect(lists.listOf('/a'), 'list1');
    expect(lists.listOf('/b'), IdeGitChangelists.defaultId);
    expect(lists.toJson()['assigned'], {'/a': 'list1'});
  });

  group('the Commit panel', () {
    late FakeGit git;

    setUp(() {
      git = FakeGit(testRoot)
        ..status = '## main\x00 M a.dart\x00 M b.dart\x00'
        ..log = gitLogRecord(
          'c1',
          [],
          'First',
          refs: 'HEAD -> refs/heads/main',
        );
      git.refs['HEAD'] = 'c1';
    });

    Finder inPanel(Finder finder) =>
        find.descendant(of: find.byType(IdeGitCommitPanel), matching: finder);

    Future<void> menu(WidgetTester tester, Finder row, String item) async {
      await tester.tapAt(
        tester.getCenter(row),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    testWidgets('a change moved to a new list: listed there, unchecked; the '
        'list committed alone, then made active', (tester) async {
      await pumpWorkbench(
        tester,
        const {'a.dart': 'a', 'b.dart': 'b'},
        git: git.repository(),
        size: const Size(1800, 900),
      );
      await tester.pumpAndSettle();
      await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
      await tester.pumpAndSettle();
      // Flat, so that a file's row is its name.
      await tester.tap(inPanel(find.byIcon(Codicons.listFlat)));
      await tester.pumpAndSettle();

      await menu(
        tester,
        inPanel(find.textContaining('b.dart', findRichText: true)).first,
        'Move to Another Changelist',
      );
      await tester.tap(find.text('New Changelist…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'Feature');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(inPanel(find.text('Feature')), findsOneWidget);
      expect(inPanel(find.text('active')), findsOneWidget);
      expect(inPanel(find.text('1 of 2 files checked')), findsOneWidget);

      await menu(
        tester,
        inPanel(find.text('Feature')),
        'Commit Only This Changelist',
      );
      expect(inPanel(find.text('1 of 2 files checked')), findsOneWidget);
      await tester.enterText(
        find
            .descendant(
              of: find.byType(IdeGitCommitPanel),
              matching: find.byType(EditableText),
            )
            .last,
        'Feature work',
      );
      await tester.tap(inPanel(find.text('Commit')).last);
      await tester.pumpAndSettle();
      expect(git.callsTo('commit').single, [
        'commit',
        '--quiet',
        '-m',
        'Feature work',
        '--only',
        '--',
        'b.dart',
      ]);

      await menu(
        tester,
        inPanel(find.text('Feature')),
        'Set Active Changelist',
      );
      final active = tester.getTopLeft(inPanel(find.text('active')));
      expect(
        (active.dy - tester.getTopLeft(inPanel(find.text('Feature'))).dy).abs(),
        lessThan(4),
      );
    });
  });
}
