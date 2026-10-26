// JetBrains IDEs' stashes: the changes stashed from the Commit panel (all,
// or the files selected), and the Stash tab: each stash's files, its
// changes shown, Apply, Pop, Drop.

import 'package:baocode/ide/git/git_model.dart';
import 'package:baocode/ide/git/git_service.dart';
import 'package:baocode/ide/git/ide_git_commit_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

final _stash = 's' * 40;

void main() {
  test('the stashes listed: what each says, the branch it was made on', () {
    final stashes = parseGitStashes(
      'stash@{0}\x00$_stash\x001767225600\x00On main: half done\n'
      'stash@{1}\x00${'t' * 40}\x001767225500\x00WIP on dev: abc123 Subject\n',
    );
    expect(
      [for (final stash in stashes) stash.message],
      ['half done', 'abc123 Subject'],
    );
    expect([for (final stash in stashes) stash.branch], ['main', 'dev']);
  });

  late FakeGit git;

  setUp(() {
    git = FakeGit(testRoot)
      ..status = '## main\x00 M lib/a.dart\x00'
      ..diff = 'M\x00lib/a.dart\x00'
      ..log = gitLogRecord('c1', [], 'First', refs: 'HEAD -> refs/heads/main');
    git.refs['HEAD'] = 'c1';
    git.answers['stash'] = IdeGitOutput(
      0,
      'stash@{0}\x00$_stash\x001767225600\x00On main: half done\n',
    );
  });

  Finder inPanel(Finder finder) =>
      find.descendant(of: find.byType(IdeGitCommitPanel), matching: finder);

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
  }

  testWidgets('the changes stashed with a message, the untracked files too', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(inPanel(find.byTooltip('Stash Changes')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'half done');
    await tester.tap(find.text('Include untracked files'));
    await tester.tap(find.text('Stash').last);
    await tester.pumpAndSettle();
    expect(git.callsTo('stash').last, [
      'stash',
      'push',
      '-m',
      'half done',
      '--include-untracked',
    ]);
  });

  testWidgets("the Stash tab: a stash's files, popped from its menu", (
    tester,
  ) async {
    await open(tester);
    await tester.tap(inPanel(find.text('Stash')));
    await tester.pumpAndSettle();
    expect(
      inPanel(find.textContaining('half done', findRichText: true)),
      findsOneWidget,
    );
    await tester.tap(
      inPanel(find.textContaining('half done', findRichText: true)),
    );
    await tester.pumpAndSettle();
    expect(git.callsTo('diff').last, contains('$_stash^1'));
    expect(
      inPanel(find.textContaining('a.dart', findRichText: true)),
      findsOneWidget,
    );

    await tester.tapAt(
      tester.getCenter(
        inPanel(find.textContaining('half done', findRichText: true)),
      ),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pop'));
    await tester.pumpAndSettle();
    expect(
      git.callsTo('stash'),
      anyElement(equals(['stash', 'pop', 'stash@{0}'])),
    );
  });
}
