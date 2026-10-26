// The Commit panel's commit options (author, Sign-off, Run Git Hooks), its
// commit message history (Ctrl+M) and inspections, Add to .gitignore and
// the Ignored Files group: as JetBrains IDEs have them.

import 'package:baocode/ide/git/git_model.dart';
import 'package:baocode/ide/git/ide_git_commit_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

void main() {
  test('the inspections: a long subject, no blank line after it', () {
    expect(ideGitMessageProblems('Fix it\n\nWhy'), isEmpty);
    expect(ideGitMessageProblems('x' * 73), [IdeGitMessageProblem.longSubject]);
    expect(ideGitMessageProblems('Fix it\nWhy'), [
      IdeGitMessageProblem.noBlankLine,
    ]);
    expect(
      const IdeGitCommitOptions(
        author: ' Bob <bob@example.com> ',
        signOff: true,
        runHooks: false,
      ).arguments,
      ['--author=Bob <bob@example.com>', '--signoff', '--no-verify'],
    );
    expect(const IdeGitCommitOptions().arguments, isEmpty);
  });

  group('the Commit panel', () {
    late FakeGit git;

    setUp(() {
      git = FakeGit(testRoot)
        ..status = '## main\x00 M a.dart\x00?? new.txt\x00'
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

    Future<void> open(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
      await tester.pumpAndSettle();
    }

    Future<void> option(WidgetTester tester, String item) async {
      await tester.tap(find.byTooltip('Commit Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    testWidgets('signed off, by another author, without the hooks', (
      tester,
    ) async {
      await pumpWorkbench(tester, const {
        'a.dart': 'a',
        'new.txt': 'n',
      }, git: git.repository());
      await open(tester);
      await option(tester, 'Sign-off Commit');
      await option(tester, 'Run Git Hooks');
      await option(tester, 'Author…');
      await tester.enterText(find.byType(TextField).last, 'Bob <b@x.y>');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        inPanel(find.text('Author: Bob <b@x.y> · Signed off · Hooks skipped')),
        findsOneWidget,
      );

      await tester.enterText(inPanel(find.byType(TextField)).first, 'Change');
      await tester.tap(inPanel(find.text('Commit')).last);
      await tester.pumpAndSettle();
      expect(git.callsTo('commit').single, [
        'commit',
        '--quiet',
        '--author=Bob <b@x.y>',
        '--signoff',
        '--no-verify',
        '-m',
        'Change',
        '--only',
        '--',
        'a.dart',
      ]);
      // The author for that commit only.
      expect(inPanel(find.text('Signed off · Hooks skipped')), findsOneWidget);
    });

    testWidgets("the message history: one picked is the input's; the "
        'inspections as it is written', (tester) async {
      git.messages = ['Fix the parser\n\nIt choked on tabs.', 'Second'];
      await pumpWorkbench(tester, const {
        'a.dart': 'a',
        'new.txt': 'n',
      }, git: git.repository());
      await open(tester);
      final input = inPanel(find.byType(TextField)).first;
      await tester.tap(input);
      await tester.pump();
      await chord(tester, LogicalKeyboardKey.keyM, control: true);
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      await tester.tap(find.text('Fix the parser'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Fix the parser\n\nIt choked on tabs.',
      );

      await tester.enterText(input, 'Fix\nWhy');
      await tester.pump();
      expect(
        find.text('Separate the subject from the body with a blank line'),
        findsOneWidget,
      );
      await tester.enterText(input, 'x' * 80);
      await tester.pump();
      expect(
        find.text('The subject is longer than 72 characters'),
        findsOneWidget,
      );
    });

    testWidgets('an unversioned file added to .gitignore; the ignored files '
        'shown', (tester) async {
      git.ignored = ['build/', 'x.log'];
      final workspace = await pumpWorkbench(tester, const {
        'a.dart': 'a',
        'new.txt': 'n',
      }, git: git.repository());
      await open(tester);
      await tester.tapAt(
        tester.getCenter(
          inPanel(find.textContaining('new.txt', findRichText: true)).first,
        ),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to .gitignore'));
      await tester.pumpAndSettle();
      expect(
        (workspace.files as TreeFiles).contents[inRoot('.gitignore')],
        '/new.txt\n',
      );

      expect(inPanel(find.text('Ignored Files')), findsNothing);
      await tester.tap(find.byTooltip('Show Ignored Files'));
      await tester.pumpAndSettle();
      expect(inPanel(find.text('Ignored Files')), findsOneWidget);
      expect(
        inPanel(find.textContaining('build', findRichText: true)),
        findsOneWidget,
      );
      expect(
        inPanel(find.textContaining('x.log', findRichText: true)),
        findsOneWidget,
      );
    });
  });
}
