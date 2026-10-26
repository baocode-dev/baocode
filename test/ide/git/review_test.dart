// The model's review before a commit, in the place of JetBrains IDEs'
// before-commit checks: its problems listed, each a click from its line;
// asked for before each commit, the commit held back by a warning until
// Commit Anyway, made at once where nothing is wrong.

import 'package:baocode/ide/git/commit_message.dart';
import 'package:baocode/ide/git/git_review.dart';
import 'package:baocode/ide/git/ide_git_commit_panel.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

void main() {
  test("the problems in the model's answer", () {
    final problems = ideGitReviewProblems(
      'Here is what I found:\n'
      '- error lib/a.dart:12 The list is read after it is disposed.\n'
      'warning b/README.md Mentions a flag that is gone.\n'
      'info c.dart:3: A TODO was added.\n',
    );
    expect(
      [for (final p in problems) (p.severity, p.path, p.line)],
      [
        (IdeGitReviewSeverity.error, 'lib/a.dart', 12),
        (IdeGitReviewSeverity.warning, 'README.md', null),
        (IdeGitReviewSeverity.info, 'c.dart', 3),
      ],
    );
    expect(problems.first.message, 'The list is read after it is disposed.');
    expect(problems.last.blocks, isFalse);
    expect(ideGitReviewProblems('NO PROBLEMS'), isEmpty);
  });

  group('the Commit panel', () {
    late FakeGit git;
    late List<String> prompts;
    late String answer;

    setUp(() {
      git = FakeGit(testRoot)
        ..status = '## main\x00 M a.dart\x00'
        ..diff = 'diff --git a/a.dart b/a.dart\n+print(1);\n'
        ..log = gitLogRecord(
          'c1',
          [],
          'First',
          refs: 'HEAD -> refs/heads/main',
        );
      git.refs['HEAD'] = 'c1';
      prompts = [];
      answer = 'warning a.dart:2 A debug print is left in.';
    });

    Future<String> model(
      IdeCommitMessagePrompt prompt, {
      Future<void>? cancel,
    }) async {
      prompts.add(prompt.user);
      return answer;
    }

    Finder inPanel(Finder finder) =>
        find.descendant(of: find.byType(IdeGitCommitPanel), matching: finder);

    Future<void> open(WidgetTester tester) async {
      await pumpWorkbench(
        tester,
        const {'a.dart': 'void main() {\n  print(1);\n}\n'},
        git: git.repository(),
        commitMessage: model,
      );
      await tester.pumpAndSettle();
      await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
      await tester.pumpAndSettle();
    }

    testWidgets('reviewed on demand: the problem listed, a click from its '
        'line', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Review Changes with AI'));
      await tester.pumpAndSettle();
      expect(prompts.single, contains('+print(1);'));
      expect(inPanel(find.text('1 problem found')), findsOneWidget);
      final problem = inPanel(
        find.textContaining('A debug print is left in.', findRichText: true),
      );
      expect(problem, findsOneWidget);
      expect(inPanel(find.text('Commit Anyway')), findsNothing);
    });

    testWidgets('reviewed before each commit: held back by a warning, then '
        'committed anyway; nothing wrong, committed at once', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Commit Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review with AI Before Committing'));
      await tester.pumpAndSettle();

      await tester.enterText(inPanel(find.byType(TextField)).first, 'Print');
      await tester.tap(inPanel(find.text('Commit')).last);
      await tester.pumpAndSettle();
      expect(prompts.single, contains('Print'));
      expect(git.callsTo('commit'), isEmpty);
      await tester.tap(inPanel(find.text('Commit Anyway')));
      await tester.pumpAndSettle();
      expect(git.callsTo('commit'), hasLength(1));
      expect(prompts, hasLength(1));

      answer = 'NO PROBLEMS';
      await tester.enterText(inPanel(find.byType(TextField)).first, 'Again');
      await tester.tap(inPanel(find.text('Commit')).last);
      await tester.pumpAndSettle();
      expect(prompts, hasLength(2));
      expect(git.callsTo('commit'), hasLength(2));
    });
  });
}
