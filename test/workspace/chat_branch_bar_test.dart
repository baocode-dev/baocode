// Under the chat input, the Git branch the agent works on: switched from
// its menu, not while the agent works; a workspace's folders each with
// theirs; only the name without a repository. Worktrees made and switched
// to from it.

import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/ide/git/git_repository.dart';
import 'package:baocode/ide/git/git_service.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/workspace/chat_branch_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
  void Function(String folder, String path)? onSwitchWorktree,
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
              onSwitchWorktree: onSwitchWorktree,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("in another worktree: the branch, then the worktree's name, "
      'its path on hover', (tester) async {
    final fake = _git('/work/monad-wt', branch: 'feature')
      ..worktrees =
          'worktree /work/monad\nHEAD ${'a' * 40}\nbranch refs/heads/main\n\n'
          'worktree /work/monad-wt\nHEAD ${'b' * 40}\n'
          'branch refs/heads/feature\n';
    final git = fake.repository();
    addTearDown(git.dispose);
    await _pump(tester, repositories: [('/work/monad', git)]);
    expect(find.text('feature · monad-wt'), findsOneWidget);
    expect(
      find.byTooltip('In worktree monad-wt\n/work/monad-wt'),
      findsOneWidget,
    );
  });

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

  group('worktrees', () {
    late FakeGit fake;
    late IdeGitRepository git;
    late List<(String, String)> switched;

    setUp(() {
      fake = _git('/work/monad')
        ..worktrees =
            'worktree /work/monad\nHEAD ${'a' * 40}\nbranch refs/heads/main\n\n'
            'worktree /work/monad-feature\nHEAD ${'b' * 40}\n'
            'branch refs/heads/feature\n';
      switched = [];
    });

    /// The repository, made in the test's zone.
    IdeGitRepository open() {
      git = fake.repository();
      addTearDown(git.dispose);
      return git;
    }

    Future<ChatSession> pump(WidgetTester tester) async {
      open();
      final session = ChatSession(historyCount: 0);
      await _pump(
        tester,
        session: session,
        repositories: [('/work/monad', git)],
        onSwitchWorktree: (folder, path) => switched.add((folder, path)),
      );
      // The worktrees, read once asked for.
      git.worktrees;
      await tester.pumpAndSettle();
      await tester.tap(find.text('main'));
      await tester.pumpAndSettle();
      return session;
    }

    testWidgets('a branch checked out in another worktree is worked on '
        'there: the conversation on it, the agent told', (tester) async {
      final session = await pump(tester);
      expect(find.text('In worktree monad-feature'), findsOneWidget);
      await tester.tap(find.text('feature'));
      await tester.pumpAndSettle();
      expect(fake.callsTo('checkout'), isEmpty);
      expect(switched, [('/work/monad', '/work/monad-feature')]);
      expect(
        session.draft.pendingMessage?.text,
        'From now on, work in /work/monad-feature (branch feature): read and '
        'edit the files and run the commands there.',
      );
    });

    testWidgets('New Worktree… makes a branch in a worktree beside the '
        'folder, and works there', (tester) async {
      final session = await pump(tester);
      await tester.tap(find.text('New Worktree…'));
      await tester.pumpAndSettle();
      expect(find.textContaining('beside “monad”'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'fix/login');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      // Then read again.
      final worktreeCalls = fake.callsTo('worktree');
      expect(worktreeCalls.where((call) => call[1] == 'add').single, [
        'worktree',
        'add',
        '-b',
        'fix/login',
        '--',
        '/work/monad-fix-login',
      ]);
      expect(worktreeCalls.last, ['worktree', 'list', '--porcelain']);
      expect(switched, [('/work/monad', '/work/monad-fix-login')]);
      expect(
        session.draft.pendingMessage?.text,
        contains('/work/monad-fix-login (branch fix/login)'),
      );
    });

    testWidgets('none offered without a way to switch', (tester) async {
      await _pump(tester, repositories: [('/work/monad', open())]);
      await tester.tap(find.text('main'));
      await tester.pumpAndSettle();
      expect(find.text('New Worktree…'), findsNothing);
    });
  });

  test('a new worktree goes beside the folder, numbered past those taken', () {
    final paths = p.posix;
    expect(
      ideNewWorktreePath('/w/app', 'fix/login', taken: const [], paths: paths),
      '/w/app-fix-login',
    );
    expect(
      ideNewWorktreePath(
        '/w/app',
        'x',
        taken: const ['/w/app', '/w/app-x', '/w/app-x-2'],
        paths: paths,
      ),
      '/w/app-x-3',
    );
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

  testWidgets("a workspace's folder worked on in another worktree: its "
      "branch and worktree after the workspace's name, while the agent "
      'works too', (tester) async {
    final monad =
        (_git('/work/monad-wt', branch: 'feature')
              ..worktrees =
                  'worktree /work/monad\nHEAD ${'a' * 40}\n'
                  'branch refs/heads/main\n\n'
                  'worktree /work/monad-wt\nHEAD ${'b' * 40}\n'
                  'branch refs/heads/feature\n')
            .repository();
    final relay = _git('/work/relay').repository();
    for (final git in [monad, relay]) {
      addTearDown(git.dispose);
    }
    await _pump(
      tester,
      name: 'BaoCode',
      workspace: true,
      repositories: [('/work/monad', monad), ('/work/relay', relay)],
    );
    expect(find.text('BaoCode · feature · monad-wt'), findsOneWidget);
    expect(
      find.byTooltip('In worktree monad-wt\n/work/monad-wt'),
      findsOneWidget,
    );
    await _pump(
      tester,
      session: _Working(),
      name: 'BaoCode',
      workspace: true,
      repositories: [('/work/monad', monad), ('/work/relay', relay)],
    );
    expect(find.text('BaoCode · feature · monad-wt'), findsOneWidget);
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
