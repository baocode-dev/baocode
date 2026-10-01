import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/git/commit_message.dart';
import 'package:baocode/ide/ide_input.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

String fileDiff(String path, {int lines = 3, String mode = ''}) => [
  'diff --git a/$path b/$path',
  ?(mode.isEmpty ? null : mode),
  'index 1111111..2222222 100644',
  '--- a/$path',
  '+++ b/$path',
  '@@ -1,$lines +1,$lines @@',
  for (var i = 0; i < lines; i++) ...['-old $i', '+new $i'],
  '',
].join('\n');

void main() {
  group('the prompt', () {
    test('files, their status and counts', () {
      final files = ideSplitDiff(
        [
          fileDiff('lib/a.dart', lines: 2),
          fileDiff('lib/new.dart', mode: 'new file mode 100644'),
          'diff --git a/old.txt b/new.txt\n'
              'similarity index 90%\n'
              'rename from old.txt\n'
              'rename to new.txt\n',
          'diff --git a/logo.png b/logo.png\n'
              'Binary files a/logo.png and b/logo.png differ\n',
        ].join(),
      );
      expect(
        [for (final file in files) file.summary],
        [
          'M lib/a.dart (+2 -2)',
          'A lib/new.dart (+3 -3)',
          'R old.txt → new.txt',
          'M logo.png (binary)',
        ],
      );
    });

    test('small diffs whole, large ones cut to share the budget', () {
      final small = fileDiff('small.dart', lines: 2);
      final large = [
        fileDiff('large1.dart', lines: 400),
        fileDiff('large2.dart', lines: 400),
      ];
      final trimmed = ideTrimDiff(ideSplitDiff(small + large.join()), 4000);
      expect(trimmed.length, lessThanOrEqualTo(4000));
      expect(trimmed, startsWith(small));
      expect(trimmed, contains('diff --git a/large1.dart'));
      expect(trimmed, contains('diff --git a/large2.dart'));
      expect(
        RegExp(r'\[\d+ more lines not shown\]').allMatches(trimmed),
        hasLength(2),
      );
      // What fits is left alone.
      final whole = small + fileDiff('b.dart');
      expect(ideTrimDiff(ideSplitDiff(whole), 40000), whole);
    });

    test('a lock file by its header alone', () {
      final lock = fileDiff('pubspec.lock', lines: 50);
      final trimmed = ideTrimDiff(ideSplitDiff(lock), 40000);
      expect(trimmed, contains('diff --git a/pubspec.lock'));
      expect(trimmed, isNot(contains('+new 1')));
      expect(trimmed, contains('100 changed lines of a lock or generated'));
    });

    test('with the branch and the recent subjects, within 40k', () {
      final diff = List.generate(
        30,
        (i) => fileDiff('lib/f$i.dart', lines: 200),
      ).join();
      expect(diff.length, greaterThan(ideCommitDiffBudget));
      final prompt = ideCommitMessagePrompt(
        diff,
        recentMessages: ['feat: add a thing\n\nBody', '', 'fix(ui): align'],
        branch: 'main',
      );
      expect(prompt.system, contains('imperative mood'));
      expect(prompt.system, isNot(contains('\n')));
      expect(prompt.user, startsWith('Branch: main\n'));
      expect(prompt.user, contains('- feat: add a thing\n- fix(ui): align\n'));
      expect(prompt.user, isNot(contains('Body')));
      expect(prompt.user, contains('M lib/f29.dart (+200 -200)'));
      final diffPart = prompt.user.substring(prompt.user.indexOf('Diff:\n'));
      expect(diffPart.length, lessThan(ideCommitDiffBudget + 10));
    });

    test('a reply without fences or quotes', () {
      expect(ideCleanCommitMessage('```\nFix it\n```'), 'Fix it');
      expect(ideCleanCommitMessage('"Fix it"\n'), 'Fix it');
      expect(ideCleanCommitMessage('Fix it\n\n- more'), 'Fix it\n\n- more');
    });
  });

  group('Generate Commit Message', () {
    late FakeGit git;
    late List<IdeCommitMessagePrompt> prompts;
    Completer<String>? reply;

    setUp(() {
      git = FakeGit(testRoot)
        ..status = '## main\x00 M lib/a.dart\x00?? notes.md\x00'
        ..diff = fileDiff('lib/a.dart')
        ..log = gitLogRecord('c1', [], 'feat: first');
      git.refs['HEAD'] = 'c1';
      git.newFileDiffs['notes.md'] = fileDiff(
        'notes.md',
        mode: 'new file mode 100644',
      );
      prompts = [];
      reply = null;
    });

    Future<String> model(
      IdeCommitMessagePrompt prompt, {
      Future<void>? cancel,
    }) async {
      prompts.add(prompt);
      final pending = reply;
      if (pending == null) return 'Update a and add notes';
      unawaited(
        cancel?.then((_) {
          if (!pending.isCompleted) {
            pending.completeError(const IdeCommitMessageCancelled());
          }
        }),
      );
      return pending.future;
    }

    Future<void> pumpScm(WidgetTester tester) async {
      await pumpWorkbench(
        tester,
        const {'lib/a.dart': 'a', 'notes.md': 'n'},
        git: git.repository(),
        commitMessage: model,
      );
      await tester.pumpAndSettle();
      await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
      await tester.pumpAndSettle();
    }

    String input(WidgetTester tester) => tester
        .widget<IdeInputBox>(find.byType(IdeInputBox).first)
        .controller
        .text;

    testWidgets('fills the input from every change when none is staged', (
      tester,
    ) async {
      await pumpScm(tester);
      await tester.tap(find.byTooltip('Generate Commit Message'));
      await tester.pumpAndSettle();
      expect(input(tester), 'Update a and add notes');
      final diffs = git.callsTo('diff');
      expect(diffs.first, isNot(contains('--cached')));
      expect(diffs.last, contains('notes.md'));
      final prompt = prompts.single.user;
      expect(prompt, contains('M lib/a.dart (+3 -3)'));
      expect(prompt, contains('A notes.md (+3 -3)'));
      expect(prompt, contains('- feat: first'));
    });

    testWidgets('only the staged changes when some are', (tester) async {
      git.status = '## main\x00M  lib/a.dart\x00?? notes.md\x00';
      await pumpScm(tester);
      await tester.tap(find.byTooltip('Generate Commit Message'));
      await tester.pumpAndSettle();
      expect(git.callsTo('diff').single, contains('--cached'));
      expect(prompts.single.user, isNot(contains('notes.md')));
    });

    testWidgets('clicking again cancels, keeping the input', (tester) async {
      reply = Completer<String>();
      await pumpScm(tester);
      await tester.enterText(find.byType(EditableText).first, 'draft');
      await tester.tap(find.byTooltip('Generate Commit Message'));
      await tester.pump();
      await tester.tap(find.byTooltip('Cancel Generating Commit Message'));
      await tester.pumpAndSettle();
      expect(input(tester), 'draft');
      expect(find.byTooltip('Generate Commit Message'), findsOneWidget);
    });

    testWidgets('says when there is nothing to describe, and reports errors', (
      tester,
    ) async {
      git.diff = '';
      git.newFileDiffs.clear();
      await pumpScm(tester);
      await tester.tap(find.byTooltip('Generate Commit Message'));
      await tester.pumpAndSettle();
      expect(prompts, isEmpty);
      expect(
        find.text('There are no changes to generate a commit message for.'),
        findsOneWidget,
      );

      git.diff = fileDiff('lib/a.dart');
      reply = Completer<String>()
        ..future.ignore()
        ..completeError(
          const IdeCommitMessageException('Claude Code is not installed'),
        );
      await tester.tap(find.byTooltip('Generate Commit Message'));
      await tester.pumpAndSettle();
      expect(find.text('Claude Code is not installed'), findsOneWidget);
    });
  });
}
