import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/git/git_model.dart';
import 'package:monad/ide/git/git_service.dart';
import 'package:monad/ide/ide_hover.dart';
import 'package:monad/ide/ide_explorer.dart';
import 'package:monad/ide/ide_list.dart';
import 'package:monad/ide/ide_modern_ui.dart';

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

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    await tester.tapAt(
      tester.getCenter(finder),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  TestGesture? mouse;
  tearDown(() => mouse = null);

  Future<void> hover(WidgetTester tester, Finder finder) async {
    if (mouse case final mouse?) {
      await mouse.moveTo(tester.getCenter(finder));
    } else {
      final created = mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(created.removePointer);
      await created.addPointer(location: tester.getCenter(finder));
    }
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
    expect(find.text('Graph'), findsOneWidget);
  });

  testWidgets('shows the groups, their counts, letters and the badge', (
    tester,
  ) async {
    await pumpScm(tester);
    expect(find.text('Source Control'), findsOneWidget);
    final input = tester.widget<TextField>(find.byType(TextField).first);
    expect(input.decoration!.hintText, contains('to commit on "main")'));

    expect(find.text('Staged Changes'), findsOneWidget);
    expect(
      find.descendant(
        of: rowOf('Staged Changes'),
        matching: find.byType(IdeCountBadge),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IdeCountBadge>(
            find.descendant(
              of: rowOf('Changes').last,
              matching: find.byType(IdeCountBadge),
            ),
          )
          .count,
      2,
    );
    // As a tree (the default): the folder, then the name and the status
    // letter.
    expect(rowOf('lib'), findsWidgets);
    final a = tester.widget<IdeResourceLabel>(
      find.descendant(
        of: rowOf('a.dart'),
        matching: find.byType(IdeResourceLabel),
      ),
    );
    expect((a.description, a.letter), (null, 'M'));
    expect(a.letterColor, IdeGitStatus.modified.color);
    final notes = tester.widget<IdeResourceLabel>(
      find.descendant(
        of: rowOf('notes.md'),
        matching: find.byType(IdeResourceLabel),
      ),
    );
    expect((notes.description, notes.letter), (null, 'U'));

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

  testWidgets('a group collapses and expands', (tester) async {
    await pumpScm(tester);
    await tester.tap(find.text('Staged Changes'));
    await tester.pumpAndSettle();
    expect(text('staged.dart'), findsNothing);
    await tester.tap(find.text('Staged Changes'));
    await tester.pumpAndSettle();
    expect(text('staged.dart'), findsOneWidget);
  });

  testWidgets('committing without a message asks for one', (tester) async {
    await pumpScm(tester);
    await tester.tap(find.byTooltip('Commit Changes (Ctrl+Enter)'));
    await tester.pumpAndSettle();
    expect(find.text('Please provide a commit message'), findsOneWidget);
    expect(git.callsTo('commit'), isEmpty);
    await tester.enterText(find.byType(TextField).first, 'W');
    await tester.pumpAndSettle();
    expect(find.text('Please provide a commit message'), findsNothing);
  });

  testWidgets('commits the staged changes and clears the message', (
    tester,
  ) async {
    await pumpScm(tester);
    await tester.enterText(find.byType(TextField).first, 'Fix a bug');
    git.onCommand = (arguments) {
      if (arguments.first == 'commit') git.status = '## main\x00';
    };
    await tester.tap(find.byTooltip('Commit Changes (Ctrl+Enter)'));
    await tester.pumpAndSettle();
    expect(git.callsTo('commit').single, [
      'commit',
      '--quiet',
      '-m',
      'Fix a bug',
    ]);
    expect(find.text('Fix a bug'), findsNothing);
    expect(text('staged.dart'), findsNothing);
  });

  testWidgets('with nothing staged, the smart commit asks, then commits all', (
    tester,
  ) async {
    git.status = '## main\x00 M lib/a.dart\x00?? notes.md\x00';
    await pumpScm(tester);
    await tester.enterText(find.byType(TextField).first, 'Everything');
    await tester.tap(find.byTooltip('Commit Changes (Ctrl+Enter)'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('There are no staged changes to commit.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    // The untracked file is staged first (`git.smartCommitChanges: all`).
    expect(git.callsTo('add').single, ['add', '-A', '--', 'notes.md']);
    expect(git.callsTo('commit').single, [
      'commit',
      '--quiet',
      '--all',
      '-m',
      'Everything',
    ]);
  });

  testWidgets('Never stops the smart commit from asking or committing', (
    tester,
  ) async {
    git.status = '## main\x00 M lib/a.dart\x00';
    await pumpScm(tester);
    await tester.enterText(find.byType(TextField).first, 'Nope');
    await tester.tap(find.byTooltip('Commit Changes (Ctrl+Enter)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Never'));
    await tester.pumpAndSettle();
    // Nothing to commit now: the branch's own action takes the button.
    expect(find.byTooltip('Commit Changes (Ctrl+Enter)'), findsNothing);
    expect(find.text('Publish Branch'), findsOneWidget);
    await tester.tap(find.byType(TextField).first);
    await chord(tester, LogicalKeyboardKey.enter, control: true);
    await tester.pumpAndSettle();
    expect(find.textContaining('no staged changes'), findsNothing);
    expect(git.callsTo('commit'), isEmpty);
  });

  testWidgets('inline actions stage and unstage', (tester) async {
    await pumpScm(tester);
    await hover(tester, rowOf('a.dart'));
    await tester.tap(
      find.descendant(
        of: rowOf('a.dart'),
        matching: find.byTooltip('Stage Changes'),
      ),
    );
    await tester.pumpAndSettle();
    expect(git.callsTo('add').single, ['add', '-A', '--', 'lib/a.dart']);

    await hover(tester, rowOf('Staged Changes'));
    await tester.tap(find.byTooltip('Unstage All Changes'));
    await tester.pumpAndSettle();
    expect(git.callsTo('restore').single, ['restore', '--staged', '--', '.']);
  });

  testWidgets('discarding a tracked file confirms as VS Code does', (
    tester,
  ) async {
    await pumpScm(tester);
    await rightClick(tester, rowOf('a.dart'));
    expect(find.text('Open File'), findsOneWidget);
    expect(find.text('Add to .gitignore'), findsOneWidget);
    expect(find.text('Reveal in Explorer View'), findsOneWidget);
    await tester.tap(find.text('Discard Changes'));
    await tester.pumpAndSettle();
    expect(
      find.text("Are you sure you want to discard changes in 'a.dart'?"),
      findsOneWidget,
    );
    await tester.tap(find.text('Discard File'));
    await tester.pumpAndSettle();
    expect(git.callsTo('checkout').single, [
      'checkout',
      '-q',
      '--',
      'lib/a.dart',
    ]);
  });

  testWidgets('Discard All Changes offers tracked files alone, or all', (
    tester,
  ) async {
    await pumpScm(tester);
    await rightClick(tester, rowOf('Changes').last);
    await tester.tap(find.text('Discard All Changes'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        "Are you sure you want to DELETE the following untracked file: "
        "'notes.md'?",
      ),
      findsOneWidget,
    );
    expect(find.text('Discard 1 Tracked File'), findsOneWidget);
    await tester.tap(find.text('Discard All 2 Files'));
    await tester.pumpAndSettle();
    expect(git.callsTo('checkout'), hasLength(1));
    // Without a Trash (off macOS), untracked files are deleted.
    expect(git.callsTo('clean').single, [
      'clean',
      '-f',
      '-q',
      '--',
      'notes.md',
    ]);
  });

  testWidgets('a resource opens its change; Reveal in Explorer View selects '
      'it', (tester) async {
    final workspace = await pumpWorkbench(tester, const {
      'lib/a.dart': 'a',
      'lib/staged.dart': 's',
      'notes.md': 'n',
    }, git: git.repository());
    await tester.pumpAndSettle();
    await showScm(tester);
    await tester.tap(rowOf('a.dart'));
    await tester.pumpAndSettle();
    expect(workspace.active?.path, inRoot('lib/a.dart'));
    expect(workspace.active?.title, 'a.dart (Working Tree)');

    await rightClick(tester, rowOf('notes.md'));
    await tester.tap(find.text('Reveal in Explorer View'));
    await tester.pumpAndSettle();
    expect(find.text('Explorer'), findsOneWidget);
    final explorer = tester.widget<IdeExplorer>(find.byType(IdeExplorer));
    expect(explorer.controller.selected, inRoot('notes.md'));
  });

  testWidgets('the graph shows commits, references and a commit\'s files', (
    tester,
  ) async {
    git.status = '## main\x00';
    git.refs['HEAD'] = 'c2';
    git.log =
        '${gitLogRecord('c2', ['c1'], 'Second', refs: 'HEAD -> refs/heads/main, tag: refs/tags/v1')}\n'
        '${gitLogRecord('c1', [], 'First', author: 'Grace')}';
    git.show['c2'] = 'M\x00lib/a.dart\x00A\x00lib/b.dart\x00';
    await pumpScm(tester, files: const {'lib/a.dart': 'a', 'lib/b.dart': 'b'});
    expect(find.textContaining('Second', findRichText: true), findsOneWidget);
    expect(find.textContaining('Grace', findRichText: true), findsOneWidget);
    // HEAD's badge carries the branch name.
    expect(find.text('main'), findsWidgets);

    await tester.tap(find.textContaining('Second', findRichText: true));
    await tester.pumpAndSettle();
    expect(git.callsTo('show'), hasLength(1));
    expect(text('b.dart'), findsOneWidget);
    final label = tester.widget<IdeResourceLabel>(
      find.descendant(
        of: rowOf('b.dart'),
        matching: find.byType(IdeResourceLabel),
      ),
    );
    expect(label.letter, 'A');

    await tester.tap(find.textContaining('Second', findRichText: true));
    await tester.pumpAndSettle();
    expect(text('b.dart'), findsNothing);
  });

  testWidgets('a commit\'s files grow in, and so does a refresh\'s new '
      'commit', (tester) async {
    git.status = '## main\x00';
    git.refs['HEAD'] = 'c2';
    git.log =
        '${gitLogRecord('c2', ['c1'], 'Second', refs: 'HEAD -> refs/heads/main')}\n'
        '${gitLogRecord('c1', [], 'First')}';
    git.show['c2'] = 'M\x00lib/a.dart\x00A\x00lib/b.dart\x00';
    await pumpScm(tester, files: const {'lib/a.dart': 'a', 'lib/b.dart': 'b'});
    double height(String key) =>
        tester.getSize(find.byKey(ValueKey(key)).first).height;

    await tester.tap(find.textContaining('Second', findRichText: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(height('changes:c2'), greaterThan(0));
    expect(height('changes:c2'), lessThan(2 * IdeListColors.rowHeight));
    await tester.pumpAndSettle();
    expect(height('changes:c2'), 2 * IdeListColors.rowHeight);

    git.refs['HEAD'] = 'c3';
    git.log =
        '${gitLogRecord('c3', ['c2'], 'Third', refs: 'HEAD -> refs/heads/main')}\n'
        '${gitLogRecord('c2', ['c1'], 'Second')}\n'
        '${gitLogRecord('c1', [], 'First')}';
    await hover(tester, find.text('Graph'));
    await tester.tap(find.byTooltip('Refresh').last);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(height('commit:c3'), greaterThan(0));
    expect(height('commit:c3'), lessThan(IdeListColors.rowHeight));
    await tester.pumpAndSettle();
    expect(height('commit:c3'), IdeListColors.rowHeight);
  });

  testWidgets('Undo Last Commit restores its message to the input', (
    tester,
  ) async {
    git.status = '## main\x00';
    git.refs['HEAD'] = 'c2';
    git.log = gitLogRecord('c2', ['c1'], 'Oops\n\nDetails');
    await pumpScm(tester);
    await hover(tester, find.text('Changes').first);
    await tester.tap(find.byTooltip('More Actions...').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commit').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo Last Commit'));
    await tester.pumpAndSettle();
    expect(git.callsTo('reset').single, ['reset', '--soft', 'HEAD~']);
    final input = tester.widget<TextField>(find.byType(TextField).first);
    expect(input.controller!.text, 'Oops\n\nDetails');
  });

  group('the action button, with nothing to commit', () {
    Finder button(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is IdeHover),
    );

    testWidgets('Sync Changes pulls, then pushes, once confirmed', (
      tester,
    ) async {
      git.status = '## main...origin/main [ahead 2, behind 1]\x00';
      await pumpScm(tester);
      expect(find.text('Sync Changes'), findsOneWidget);
      expect(find.text(' 1'), findsOneWidget);
      expect(find.text(' 2'), findsOneWidget);
      expect(
        find.byTooltip('Pull 1 and push 2 commits between origin/main'),
        findsOneWidget,
      );
      expect(find.byTooltip('Commit Changes (Ctrl+Enter)'), findsNothing);

      await tester.tap(find.text('Sync Changes'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This action will pull and push commits from and to '
          '"origin/main".',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(git.callsTo('pull'), isEmpty);

      git.onCommand = (arguments) {
        if (arguments.first == 'push') git.status = '## main...origin/main\x00';
      };
      await tester.tap(find.text('Sync Changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(git.callsTo('pull').single, ['pull', '--tags', 'origin', 'main']);
      expect(git.callsTo('push').single, ['push', 'origin', 'main:main']);
      // In sync: Commit, with nothing to commit.
      expect(find.text('Sync Changes'), findsNothing);
      expect(find.byTooltip('Commit Changes (Ctrl+Enter)'), findsOneWidget);
    });

    testWidgets('behind alone, it pulls and does not push; Don\'t Show Again '
        'syncs straight away after', (tester) async {
      git.status = '## main...origin/main [behind 3]\x00';
      await pumpScm(tester);
      expect(find.byTooltip('Pull 3 commits from origin/main'), findsOneWidget);
      await tester.tap(find.text('Sync Changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("OK, Don't Show Again"));
      await tester.pumpAndSettle();
      expect(git.callsTo('pull'), hasLength(1));
      expect(git.callsTo('push'), isEmpty);

      await tester.tap(find.text('Sync Changes'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This action will pull'), findsNothing);
      expect(git.callsTo('pull'), hasLength(2));
    });

    testWidgets('a remote with a slash in its name is told from the branch', (
      tester,
    ) async {
      git
        ..remotes = 'origin\nteam/fork\n'
        ..status = '## topic...team/fork/feature/x [ahead 1]\x00';
      await pumpScm(tester);
      expect(find.byTooltip('Push 1 commits to team/fork/feature/x'), findsOne);
      await tester.tap(find.text('Sync Changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(git.callsTo('pull').single, [
        'pull',
        '--tags',
        'team/fork',
        'feature/x',
      ]);
      expect(git.callsTo('push').single, [
        'push',
        'team/fork',
        'topic:feature/x',
      ]);
    });

    testWidgets('while it syncs, the icon spins and the button waits', (
      tester,
    ) async {
      git.status = '## main...origin/main [ahead 1]\x00';
      await pumpScm(tester);
      await tester.tap(find.text('Sync Changes'));
      await tester.pumpAndSettle();
      final pushed = Completer<void>();
      git.hold = (arguments) =>
          arguments.first == 'push' ? pushed.future : null;
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump();
      expect(find.byTooltip('Synchronizing Changes...'), findsOneWidget);
      final spinning = find.descendant(
        of: button('Sync Changes'),
        matching: find.byType(RotationTransition),
      );
      expect(spinning, findsOneWidget);
      final turned = tester.widget<RotationTransition>(spinning).turns.value;
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.widget<RotationTransition>(spinning).turns.value,
        isNot(turned),
      );
      // Disabled: another tap asks nothing.
      await tester.tap(find.text('Sync Changes'));
      await tester.pump();
      expect(find.textContaining('This action will pull'), findsNothing);

      pushed.complete();
      await tester.pumpAndSettle();
      expect(find.byType(RotationTransition), findsNothing);
      expect(git.callsTo('push'), hasLength(1));
    });

    testWidgets('Publish Branch pushes the branch to the only remote and '
        'sets its upstream', (tester) async {
      git.status = '## feature/x\x00';
      await pumpScm(tester);
      expect(find.byTooltip('Publish Branch "feature/x"'), findsOneWidget);
      await tester.tap(find.text('Publish Branch'));
      await tester.pumpAndSettle();
      expect(git.callsTo('push').single, ['push', '-u', 'origin', 'feature/x']);
    });

    testWidgets('with more remotes, Publish Branch asks which', (tester) async {
      git
        ..remotes = 'origin\nupstream\n'
        ..status = '## feature/x\x00';
      await pumpScm(tester);
      await tester.tap(find.text('Publish Branch'));
      await tester.pumpAndSettle();
      expect(git.callsTo('push'), isEmpty);
      await tester.tap(find.text('upstream'));
      await tester.pumpAndSettle();
      expect(git.callsTo('push').single, [
        'push',
        '-u',
        'upstream',
        'feature/x',
      ]);
    });

    testWidgets('without remotes, Publish Branch says so', (tester) async {
      git
        ..remotes = ''
        ..status = '## feature/x\x00';
      await pumpScm(tester);
      await tester.tap(find.text('Publish Branch'));
      await tester.pumpAndSettle();
      expect(
        find.text('Your repository has no remotes configured to publish to.'),
        findsOneWidget,
      );
      expect(git.callsTo('push'), isEmpty);
    });

    testWidgets('a failed push is reported', (tester) async {
      git
        ..status = '## feature/x\x00'
        ..answers['push'] = const IdeGitOutput(
          128,
          '',
          "fatal: could not read Username for 'https://example.com'",
        );
      await pumpScm(tester);
      await tester.tap(find.text('Publish Branch'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cannot push.'), findsOneWidget);
      expect(find.text('Publish Branch'), findsOneWidget);
    });
  });
}
