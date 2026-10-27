// Under the chat input, the Git branch the agent works on: switched from
// its menu, not while the agent works; a workspace's folders each with
// theirs; only the name without a repository.

import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/ide/git/git_repository.dart';
import 'package:baocode/ide/git/git_service.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/workspace/chat_branch_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ide/git/fake_git.dart';

FakeGit _git(String root, {String branch = 'main', String changes = ''}) =>
    FakeGit(root)
      ..status = '## $branch\x00$changes'
      ..forEachRef = [
        gitRefRecord('refs/heads/main', 'a' * 40),
        gitRefRecord('refs/heads/feature', 'b' * 40),
        gitRefRecord('refs/remotes/origin/main', 'a' * 40),
      ].join('\n');

/// An agent at work.
class _Working extends ChatSession {
  _Working() : super(historyCount: 0);

  @override
  bool get isStreaming => true;
}

Future<void> _pump(
  WidgetTester tester, {
  ChatSession? session,
  String name = 'monad',
  bool workspace = false,
  List<(String, IdeGitRepository)> repositories = const [],
}) async {
  session ??= ChatSession(historyCount: 0);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomLeft,
          child: SizedBox(
            width: 600,
            child: ChatBranchBar(
              session: session,
              name: name,
              workspace: workspace,
              repositories: repositories,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the branch, and switches to one from its menu', (
    tester,
  ) async {
    final fake = _git('/work/monad', changes: ' M a.dart\x00');
    final git = fake.repository();
    addTearDown(git.dispose);
    await _pump(tester, repositories: [('/work/monad', git)]);
    // Changes not committed: a star after it.
    expect(find.text('main*'), findsOneWidget);

    await tester.tap(find.text('main*'));
    await tester.pumpAndSettle();
    // Local branches only.
    expect(find.text('feature'), findsOneWidget);
    expect(find.text('origin/main'), findsNothing);
    expect(find.text('Create Branch…'), findsOneWidget);

    fake.onCommand = (arguments) {
      if (arguments case ['checkout', ...]) fake.status = '## feature\x00';
    };
    await tester.tap(find.text('feature'));
    await tester.pumpAndSettle();
    expect(fake.callsTo('checkout'), [
      ['checkout', '-q', 'feature'],
    ]);
    expect(find.text('feature'), findsOneWidget);
  });

  testWidgets('says why Git refused to switch', (tester) async {
    final fake = _git('/work/monad');
    fake.answers['checkout'] = const IdeGitOutput(
      1,
      '',
      'error: Your local changes would be overwritten by checkout',
    );
    final git = fake.repository();
    addTearDown(git.dispose);
    await _pump(tester, repositories: [('/work/monad', git)]);
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('feature'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't switch to “feature”"), findsOneWidget);
    expect(
      find.textContaining('local changes would be overwritten'),
      findsOneWidget,
    );
  });

  testWidgets('refresh reads a switch made elsewhere', (tester) async {
    final fake = _git('/work/monad');
    final git = fake.repository();
    addTearDown(git.dispose);
    await _pump(tester, repositories: [('/work/monad', git)]);
    expect(find.text('main'), findsOneWidget);

    // Switched in a terminal, to a branch made there.
    fake
      ..status = '## hotfix\x00'
      ..forEachRef = [
        gitRefRecord('refs/heads/main', 'a' * 40),
        gitRefRecord('refs/heads/hotfix', 'c' * 40),
      ].join('\n');
    // In the menu's title, not beside the pill.
    expect(find.byIcon(Codicons.refresh), findsNothing);
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
    expect(find.text('feature'), findsOneWidget);
    await tester.tap(find.byIcon(Codicons.refresh));
    await tester.pumpAndSettle();
    // The menu stays open, now the branches read again.
    expect(find.text('Switch Branch'), findsOneWidget);
    expect(find.text('feature'), findsNothing);
    expect(find.text('hotfix'), findsNWidgets(2));
    expect(find.text('main'), findsOneWidget);
    // Fetched first: one pushed by others shows.
    expect(fake.callsTo('fetch'), [
      ['fetch', '--all', '--tags'],
    ]);
  });

  testWidgets('a remote branch is listed, and checked out tracking it', (
    tester,
  ) async {
    final fake = _git('/work/monad')
      ..upstreams['main'] = 'origin/main'
      ..forEachRef = [
        gitRefRecord('refs/heads/main', 'a' * 40),
        gitRefRecord('refs/heads/feature', 'b' * 40),
        gitRefRecord('refs/remotes/origin/main', 'a' * 40),
        gitRefRecord('refs/remotes/origin/teammate', 'd' * 40),
        gitRefRecord('refs/remotes/origin/HEAD', 'a' * 40),
      ].join('\n');
    final git = fake.repository();
    addTearDown(git.dispose);
    await _pump(tester, repositories: [('/work/monad', git)]);
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
    // Local ones first, then those only the remote has; origin/main has
    // a local one, and origin/HEAD is no branch.
    expect(find.text('On the remote'), findsOneWidget);
    expect(find.text('origin/teammate'), findsOneWidget);
    expect(find.text('origin/main'), findsNothing);
    expect(find.text('origin/HEAD'), findsNothing);

    fake.onCommand = (arguments) {
      if (arguments case ['checkout', ...]) fake.status = '## teammate\x00';
    };
    await tester.tap(find.text('origin/teammate'));
    await tester.pumpAndSettle();
    expect(fake.callsTo('checkout'), [
      ['checkout', '-q', '--track', 'origin/teammate'],
    ]);
    expect(find.text('teammate'), findsOneWidget);
  });

  testWidgets('a remote branch a local one tracks is checked out as it', (
    tester,
  ) async {
    final fake = _git('/work/monad')
      ..upstreams['mine'] = 'origin/teammate'
      ..forEachRef = [
        gitRefRecord('refs/heads/main', 'a' * 40),
        gitRefRecord('refs/heads/mine', 'd' * 40),
        gitRefRecord('refs/remotes/origin/teammate', 'd' * 40),
      ].join('\n');
    final git = fake.repository();
    addTearDown(git.dispose);
    await _pump(tester, repositories: [('/work/monad', git)]);
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
    fake.onCommand = (arguments) {
      if (arguments case ['checkout', ...]) fake.status = '## mine\x00';
    };
    // A local branch tracks it under another name: that one, not a new one.
    await tester.tap(find.text('origin/teammate'));
    await tester.pumpAndSettle();
    expect(fake.callsTo('checkout'), [
      ['checkout', '-q', 'mine'],
    ]);
    expect(find.text('mine'), findsOneWidget);
  });

  testWidgets('says why the fetch failed, listing the branches anyway', (
    tester,
  ) async {
    final fake = _git('/work/monad')
      ..answers['fetch'] = const IdeGitOutput(
        128,
        '',
        'fatal: unable to access: Could not resolve host',
      );
    final git = fake.repository();
    addTearDown(git.dispose);
    await _pump(tester, repositories: [('/work/monad', git)]);
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Codicons.refresh));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't fetch from the remotes"), findsOneWidget);
    expect(find.textContaining('Could not resolve host'), findsOneWidget);
  });

  testWidgets('a project switched to shows its own branches', (tester) async {
    final monad = _git('/work/monad').repository();
    final relay =
        (FakeGit('/work/relay')
              ..status = '## dev\x00'
              ..forEachRef = [
                gitRefRecord('refs/heads/dev', 'a' * 40),
                gitRefRecord('refs/heads/release', 'b' * 40),
              ].join('\n'))
            .repository();
    addTearDown(monad.dispose);
    addTearDown(relay.dispose);
    final session = ChatSession(historyCount: 0);
    addTearDown(session.dispose);
    Widget bar(String name, IdeGitRepository git) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ChatBranchBar(
          session: session,
          name: name,
          repositories: [('/work/$name', git)],
        ),
      ),
    );
    await tester.pumpWidget(bar('monad', monad));
    await tester.pumpAndSettle();
    expect(find.text('main'), findsOneWidget);
    // The same bar, now another project's.
    await tester.pumpWidget(bar('relay', relay));
    await tester.pumpAndSettle();
    expect(find.text('dev'), findsOneWidget);
    await tester.tap(find.text('dev'));
    await tester.pumpAndSettle();
    expect(find.text('release'), findsOneWidget);
    expect(find.text('feature'), findsNothing);
  });

  testWidgets('nothing to switch while the agent works', (tester) async {
    final git = _git('/work/monad').repository();
    addTearDown(git.dispose);
    await _pump(
      tester,
      session: _Working(),
      repositories: [('/work/monad', git)],
    );
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
    expect(find.text('feature'), findsNothing);
  });

  testWidgets('a folder without Git shows its name only', (tester) async {
    final fake = _git('/work/notes')..isRepository = false;
    final git = fake.repository();
    addTearDown(git.dispose);
    await _pump(tester, name: 'notes', repositories: [('/work/notes', git)]);
    expect(find.text('notes'), findsOneWidget);
    await tester.tap(find.text('notes'));
    await tester.pumpAndSettle();
    expect(find.text('Switch Branch'), findsNothing);
  });

  testWidgets("a workspace's folders, each with its branch", (tester) async {
    final monad = _git('/work/monad').repository();
    final relay = _git('/work/relay', branch: 'feature').repository();
    final notes = (_git('/work/notes')..isRepository = false).repository();
    for (final git in [monad, relay, notes]) {
      addTearDown(git.dispose);
    }
    await _pump(
      tester,
      name: 'BaoCode',
      workspace: true,
      repositories: [
        ('/work/monad', monad),
        ('/work/relay', relay),
        ('/work/notes', notes),
      ],
    );
    expect(find.text('BaoCode'), findsOneWidget);
    await tester.tap(find.text('BaoCode'));
    await tester.pumpAndSettle();
    expect(find.text('monad'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    expect(find.text('relay'), findsOneWidget);
    expect(find.text('feature'), findsOneWidget);
    expect(find.text('Not a Git repository'), findsOneWidget);
    // A line each, its branch at its end.
    expect(
      tester.getCenter(find.text('main')).dy,
      tester.getCenter(find.text('monad')).dy,
    );
    expect(
      tester.getTopLeft(find.text('main')).dx,
      greaterThan(tester.getTopRight(find.text('monad')).dx),
    );
    expect(
      tester.getTopRight(find.text('main')).dx,
      tester.getTopRight(find.text('Not a Git repository')).dx,
    );

    // Its branches at its side, level with it, its own checked.
    await tester.tap(find.text('monad'));
    await tester.pumpAndSettle();
    final branches = find.text('main');
    expect(branches, findsNWidgets(2));
    expect(
      tester.getCenter(branches.last).dy,
      moreOrLessEquals(tester.getCenter(find.text('monad')).dy, epsilon: 1),
    );
    expect(
      tester.getCenter(find.text('feature').last).dy,
      greaterThan(tester.getCenter(branches.last).dy),
    );
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(
      tester.getCenter(find.byIcon(Icons.check_rounded)).dy,
      tester.getCenter(branches.last).dy,
    );
  });
}
