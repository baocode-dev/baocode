import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/git/git_service.dart';
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/ide/ide_status_bar.dart';
import 'package:baocode/keybindings/keybinding_service.dart';

import '../git/fake_git.dart';
import 'fake_files.dart';

/// The status bar's branch runs Checkout to… as VS Code's does
/// (extensions/git/src/commands.ts `_checkout`), against a fake Git.
void main() {
  late FakeGit git;
  final main = 'a' * 40;
  final feature = 'b' * 40;
  final topic = 'c' * 40;
  final release = 'd' * 40;

  setUp(() {
    KeybindingService.instance = KeybindingService();
    git = FakeGit(testRoot)
      ..status = '## main\x00'
      ..refs['HEAD'] = main;
    int ago(Duration duration) =>
        DateTime.now().subtract(duration).millisecondsSinceEpoch ~/ 1000;
    final days = ago(const Duration(days: 3));
    git.forEachRef = [
      gitRefRecord(
        'refs/heads/main',
        main,
        author: 'leo',
        subject: 'feat: add a commit attribution setting',
        time: ago(const Duration(minutes: 17)),
      ),
      gitRefRecord(
        'refs/heads/feature/ide',
        feature,
        subject: 'refactor: rename monad to BaoCode',
        time: ago(const Duration(hours: 1)),
        track: '[ahead 2, behind 1]',
      ),
      gitRefRecord('refs/remotes/origin/HEAD', main, time: days),
      gitRefRecord('refs/remotes/origin/topic', topic, time: days),
      gitRefRecord('refs/tags/v1', release, time: days),
    ].join('\n');
  });
  tearDown(() => KeybindingService.instance = KeybindingService());

  Finder inQuickInput(Finder finder) =>
      find.descendant(of: find.byType(IdeQuickInput), matching: finder);

  final input = inQuickInput(find.byType(TextField));

  /// The rows' texts in order: a label and description, a separator's
  /// label, a detail (its icons left out).
  List<String> rows(WidgetTester tester) => [
    for (final text in tester.widgetList<Text>(
      inQuickInput(
        find.descendant(of: find.byType(ListView), matching: find.byType(Text)),
      ),
    ))
      if (text.textSpan case final span?)
        span.toPlainText(includePlaceholders: false)
      else
        text.data!,
  ];

  Future<void> openCheckout(WidgetTester tester) async {
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

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(input, text);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  testWidgets('the branch says what it runs: Checkout to…', (tester) async {
    await pumpWorkbench(tester, const {'a.dart': 'a'}, git: git.repository());
    await tester.pumpAndSettle();
    final bar = tester.widget<IdeStatusBar>(find.byType(IdeStatusBar));
    expect(
      bar.left.first.tooltip,
      'project (Git) - main, Checkout Branch/Tag...',
    );
  });

  testWidgets('it lists the branch commands, then the branches, remote '
      'branches and tags with their commits', (tester) async {
    await openCheckout(tester);
    expect(
      tester.widget<TextField>(input).decoration!.hintText,
      'Select a branch or tag to checkout',
    );
    // `origin/HEAD` is left out; the `•`s between the commit's author,
    // hash and subject are icons (`$(circle-small-filled)`).
    expect(rows(tester), [
      'Create new branch...',
      'Create new branch from...',
      'Checkout detached...',
      'main  17 minutes ago',
      'branches',
      'leoaaaaaaafeat: add a commit attribution setting',
      'feature/ide  1↓ 2↑1 hour ago',
      'Adabbbbbbbrefactor: rename monad to BaoCode',
      'origin/topic  3 days ago',
      'remote branches',
      'AdacccccccChange',
      'v1  3 days ago',
      'tags',
      'AdadddddddChange',
    ]);
    // A branch with its commit takes two lines.
    final mainRow = tester.getSize(
      find
          .ancestor(
            of: inQuickInput(find.textContaining('main  17')),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    expect(mainRow.height, IdeQuickInput.detailRowHeight);
  });

  testWidgets('picking a branch checks it out', (tester) async {
    await openCheckout(tester);
    await type(tester, 'feature');
    // The match first, the commands after it, always shown.
    final texts = rows(tester);
    expect(texts.first, startsWith('feature/ide'));
    expect(texts, contains('Create new branch...'));
    await enter(tester);
    expect(find.byType(IdeQuickInput), findsNothing);
    expect(git.callsTo('checkout'), [
      ['checkout', '-q', 'feature/ide'],
    ]);
  });

  testWidgets('a remote branch is checked out as the branch tracking it, '
      'made when there is none', (tester) async {
    await openCheckout(tester);
    await type(tester, 'topic');
    await enter(tester);
    expect(git.callsTo('checkout').last, [
      'checkout',
      '-q',
      '--track',
      'origin/topic',
    ]);

    git.upstreams['topic'] = 'origin/topic';
    await tester.tap(
      find.descendant(
        of: find.byType(IdeStatusBar),
        matching: find.text('main'),
      ),
    );
    await tester.pumpAndSettle();
    await type(tester, 'topic');
    await enter(tester);
    expect(git.callsTo('checkout').last, ['checkout', '-q', 'topic']);
  });

  testWidgets('Create new branch... takes the value typed as its name', (
    tester,
  ) async {
    await openCheckout(tester);
    await type(tester, 'my new thing');
    // Nothing matches: the commands alone.
    expect(rows(tester).first, 'Create new branch...');
    await enter(tester);
    expect(find.byType(IdeQuickInput), findsNothing);
    expect(git.callsTo('checkout'), [
      ['checkout', '-q', '-b', 'my-new-thing', '--no-track', 'HEAD'],
    ]);
  });

  testWidgets('Create new branch... asks for a name, saying when it is '
      'taken or would change', (tester) async {
    await openCheckout(tester);
    await enter(tester);
    expect(tester.widget<TextField>(input).decoration!.hintText, 'Branch name');
    expect(
      find.text(
        "Please provide a new branch name (Press 'Enter' to confirm or "
        "'Escape' to cancel)",
      ),
      findsOneWidget,
    );
    await type(tester, 'main');
    expect(find.text('Branch "main" already exists'), findsOneWidget);
    await type(tester, 'my branch');
    expect(find.text('The new branch will be "my-branch"'), findsOneWidget);
    await enter(tester);
    expect(find.byType(IdeQuickInput), findsNothing);
    expect(git.callsTo('checkout'), [
      ['checkout', '-q', '-b', 'my-branch', '--no-track', 'HEAD'],
    ]);
  });

  testWidgets('Escape on the name creates nothing', (tester) async {
    await openCheckout(tester);
    await enter(tester);
    await type(tester, 'never');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(IdeQuickInput), findsNothing);
    expect(git.callsTo('checkout'), isEmpty);
  });

  testWidgets('Create new branch from... picks the ref first, HEAD at the '
      'top', (tester) async {
    await openCheckout(tester);
    await tester.tap(inQuickInput(find.text('Create new branch from...')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(input).decoration!.hintText,
      'Select a ref to create the branch from',
    );
    expect(rows(tester).first, 'HEAD  aaaaaaa');
    await type(tester, 'topic');
    await enter(tester);
    await type(tester, 'fix');
    await enter(tester);
    expect(git.callsTo('checkout'), [
      ['checkout', '-q', '-b', 'fix', '--no-track', 'origin/topic'],
    ]);

    // With a value typed, that is the name: no input box.
    await tester.tap(
      find.descendant(
        of: find.byType(IdeStatusBar),
        matching: find.text('main'),
      ),
    );
    await tester.pumpAndSettle();
    await type(tester, 'hotfix');
    await tester.tap(inQuickInput(find.text('Create new branch from...')));
    await tester.pumpAndSettle();
    // HEAD is always shown.
    await type(tester, 'nothing like it');
    expect(rows(tester), ['HEAD  aaaaaaa']);
    await enter(tester);
    expect(find.byType(IdeQuickInput), findsNothing);
    expect(git.callsTo('checkout').last, [
      'checkout',
      '-q',
      '-b',
      'hotfix',
      '--no-track',
      'HEAD',
    ]);
  });

  testWidgets('Checkout detached... lists the branches alone and detaches '
      'at the commit', (tester) async {
    await openCheckout(tester);
    await tester.tap(inQuickInput(find.text('Checkout detached...')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(input).decoration!.hintText,
      'Select a branch to checkout in detached mode',
    );
    final texts = rows(tester);
    expect(texts, isNot(contains('Create new branch...')));
    expect(texts, isNot(contains('tags')));
    // Detached, `origin/HEAD` is listed (upstream skips it otherwise only).
    expect(texts.any((text) => text.startsWith('origin/HEAD')), isTrue);
    await type(tester, 'feature');
    await enter(tester);
    expect(git.callsTo('checkout'), [
      ['checkout', '-q', '--detach', feature],
    ]);
  });

  testWidgets('what Git reports is an error notification', (tester) async {
    git.answers['checkout'] = const IdeGitOutput(
      1,
      '',
      'error: Your local changes to the following files would be '
          'overwritten by checkout:\n\ta.dart\n'
          'Please commit your changes or stash them before you switch '
          'branches.\nAborting',
    );
    await openCheckout(tester);
    await type(tester, 'feature');
    await enter(tester);
    expect(
      find.textContaining('Cannot check out feature/ide.'),
      findsOneWidget,
    );
  });
}
