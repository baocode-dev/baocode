// JetBrains IDEs' Push dialog, from the log's Push: the commits that go,
// a commit's files beside them, where the branch goes (which can be
// changed); Push, Force Push (with lease, once confirmed), the tags too
// where asked.

import 'package:baocode/ide/git/git_service.dart';
import 'package:baocode/ide/git/ide_git_push_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

void main() {
  late FakeGit git;

  setUp(() {
    git = FakeGit(testRoot)
      ..status = '## main...origin/main [ahead 2]\x00'
      ..log =
          '${gitLogRecord('c3', ['c2'], 'Third', refs: 'HEAD -> refs/heads/main')}\n'
          '${gitLogRecord('c2', ['c1'], 'Second')}';
    git.refs['HEAD'] = 'c3';
    git.show['c3'] = 'M\x00lib/a.dart\x00A\x00lib/b.dart\x00';
  });

  Finder inDialog(Finder finder) =>
      find.descendant(of: find.byType(IdeGitPushDialog), matching: finder);

  Future<void> open(WidgetTester tester) async {
    await pumpWorkbench(
      tester,
      const {'lib/a.dart': 'a'},
      git: git.repository(),
      size: const Size(1800, 900),
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Push (2)'));
    await tester.pumpAndSettle();
  }

  testWidgets("the commits that go, a commit's files; Push to the upstream", (
    tester,
  ) async {
    await open(tester);
    expect(inDialog(find.text('Third')), findsOneWidget);
    expect(inDialog(find.text('Second')), findsOneWidget);
    expect(inDialog(find.text('Select a commit to see its files')), findsOne);
    await tester.tap(inDialog(find.text('Third')));
    await tester.pumpAndSettle();
    expect(
      inDialog(find.textContaining('b.dart', findRichText: true)),
      findsOneWidget,
    );

    await tester.tap(inDialog(find.text('Push tags')));
    await tester.tap(inDialog(find.text('Push')));
    await tester.pumpAndSettle();
    expect(find.byType(IdeGitPushDialog), findsNothing);
    expect(git.callsTo('push'), [
      ['push', '--follow-tags', 'origin', 'main:main'],
    ]);
  });

  testWidgets('another branch there, by force once confirmed', (tester) async {
    await open(tester);
    await tester.enterText(
      inDialog(find.byType(EditableText)).first,
      'release',
    );
    await tester.tapAt(
      tester.getCenter(inDialog(find.byTooltip('Force Push'))),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Force Push').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Force push to origin/release'), findsOne);
    await tester.tap(find.text('Force Push').last);
    await tester.pumpAndSettle();
    expect(git.callsTo('push'), [
      ['push', '--force-with-lease', 'origin', 'main:release'],
    ]);
  });

  testWidgets('a push refused because the remote moved on offers Sync Changes', (
    tester,
  ) async {
    git.answers['push'] = const IdeGitOutput(
      1,
      '',
      ' ! [rejected] main -> main (fetch first)\n'
      'error: failed to push some refs to origin\n',
    );
    final workspace = await pumpWorkbench(
      tester,
      const {'lib/a.dart': 'a'},
      git: git.repository(),
      size: const Size(1800, 900),
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Push (2)'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.text('Push')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final note = workspace.notifications.notifications.single;
    expect(note.message, contains('fetch first'));
    expect(note.primary.single.label, 'Sync Changes');

    // The action pulls the upstream, then pushes again.
    note.primary.single.run();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(git.callsTo('pull'), isNotEmpty);
    expect(git.callsTo('push'), hasLength(2));
  });

  testWidgets(
    'a rejected push to a different branch than upstream does not offer Sync Changes',
    (tester) async {
      git.answers['push'] = const IdeGitOutput(
        1,
        '',
        ' ! [rejected] main -> release (fetch first)\n',
      );
      final workspace = await pumpWorkbench(
        tester,
        const {'lib/a.dart': 'a'},
        git: git.repository(),
        size: const Size(1800, 900),
      );
      await tester.pumpAndSettle();
      await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Push (2)'));
      await tester.pumpAndSettle();
      await tester.enterText(
        inDialog(find.byType(EditableText)).first,
        'release',
      );
      await tester.tap(inDialog(find.text('Push')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      final note = workspace.notifications.notifications.single;
      expect(note.message, contains('fetch first'));
      expect(note.primary, isEmpty);
    },
  );
}
