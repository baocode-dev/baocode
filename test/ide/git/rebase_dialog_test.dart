// The interactive rebase dialog: actions by key and button, commits moved,
// a message edited making a reword, a squash with nothing below refused,
// and the model's clean-up plan put in the list.

import 'package:baocode/ide/git/commit_message.dart';
import 'package:baocode/ide/git/git_model.dart';
import 'package:baocode/ide/git/ide_git_rebase_dialog.dart';
import 'package:baocode/ide/ide_notifications.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

IdeGitCommit _commit(String id, String message, List<String> parents) =>
    IdeGitCommit(
      id: id * 8,
      parentIds: [for (final parent in parents) parent * 8],
      subject: message.split('\n').first,
      message: message,
      author: 'Ada',
      authorEmail: 'ada@example.com',
      date: DateTime(2026, 10, 1),
    );

/// Newest first.
final _commits = [
  _commit('c', 'wip', ['b']),
  _commit('b', 'Add the parser', ['a']),
  _commit('a', 'Start', ['0']),
];

void main() {
  late List<IdeGitRebaseStep>? result;

  Future<void> pump(WidgetTester tester, {IdeCommitMessageModel? ai}) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => GestureDetector(
            onTap: () async {
              result = await showGeneralDialog<List<IdeGitRebaseStep>>(
                context: context,
                pageBuilder: (_, _, _) => IdeGitRebaseDialog(
                  commits: _commits,
                  notifications: IdeNotifications(),
                  ai: ai,
                ),
              );
            },
            child: const SizedBox.expand(child: Text('open')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  String actions() =>
      [for (final step in result!) '${step.action.name} ${step.commit[0]}']
          .join(', ');

  testWidgets('fixed up by its key, moved, started: the steps oldest first', (
    tester,
  ) async {
    await pump(tester);
    // The newest focused at first.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(find.text('Fixup'), findsNWidgets(2));
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    // Start, now over Add the parser: dropped with the button.
    await tester.tap(find.text('Drop').first);
    await tester.pump();
    await tester.tap(find.text('Start Rebasing'));
    await tester.pumpAndSettle();
    expect(actions(), 'pick b, drop a, fixup c');
  });

  testWidgets('a squash of the oldest refused; a message edited, reworded', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.tap(find.text('Squash').first);
    await tester.pump();
    expect(find.textContaining('nothing below it'), findsOneWidget);
    await tester.tap(find.text('Start Rebasing'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.byType(IdeGitRebaseDialog), findsOneWidget);

    await tester.tap(find.text('Pick').first);
    await tester.pump();
    await tester.tap(find.text('Add the parser'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Add the JSON parser');
    await tester.pump();
    expect(find.text('Reword'), findsNWidgets(2));
    await tester.tap(find.text('Start Rebasing'));
    await tester.pumpAndSettle();
    expect(actions(), 'pick a, reword b, pick c');
    expect(result![1].message, 'Add the JSON parser');
  });

  testWidgets("the model's plan in the list, to be looked over", (
    tester,
  ) async {
    await pump(
      tester,
      ai: (prompt, {cancel}) async {
        expect(prompt.user, contains('cccccccc'.substring(0, 7)));
        return 'pick aaaaaaa\n'
            'reword bbbbbbb\n<<<MESSAGE\nAdd a parser for JSON\nMESSAGE>>>\n'
            'fixup ccccccc\n';
      },
    );
    await tester.tap(find.text('Clean Up with AI'));
    await tester.pumpAndSettle();
    expect(find.text('Add a parser for JSON'), findsOneWidget);
    await tester.tap(find.text('Start Rebasing'));
    await tester.pumpAndSettle();
    expect(actions(), 'pick a, reword b, fixup c');
    expect(result![1].message, 'Add a parser for JSON');
  });

  test('a plan missing a commit, or naming one twice, is none', () {
    final oldestFirst = _commits.reversed.toList();
    expect(ideGitRebasePlan('pick aaaa\npick bbbb', oldestFirst), isNull);
    expect(
      ideGitRebasePlan('pick aaaa\npick aaaa\npick cccc', oldestFirst),
      isNull,
    );
    final plan = ideGitRebasePlan(
      'Here it is:\nedit aaaa\nreword bbbb\nsquash cccc',
      oldestFirst,
    )!;
    // Edit is the user's; a reword with no message, a pick.
    expect(
      [for (final step in plan) step.action],
      [
        IdeGitRebaseAction.pick,
        IdeGitRebaseAction.pick,
        IdeGitRebaseAction.squash,
      ],
    );
  });
}
