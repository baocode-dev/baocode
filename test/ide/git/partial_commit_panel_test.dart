// JetBrains IDEs' partial commit, from the Commit panel: a file's diff
// with a check box by each change; one unchecked, the file is checked in
// part, and the commit takes the others alone, through an index of its own.

import 'package:baocode/ide/git/ide_git_commit_panel.dart';
import 'package:baocode/ide/ide_diff_options.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

const _head = 'a\nb\nc\nd\ne\nf\ng\nh\n';
const _file = 'a\nB\nc\nd\ne\nf\ng\nH\n';

void main() {
  late FakeGit git;

  setUp(() {
    git = FakeGit(testRoot)
      ..status = '## main\x00 M lib/a.dart\x00'
      ..log = gitLogRecord('c1', [], 'First', refs: 'HEAD -> refs/heads/main');
    git.refs['HEAD'] = 'c1';
    git.show['HEAD:lib/a.dart'] = _head;
  });

  Finder inPanel(Finder finder) =>
      find.descendant(of: find.byType(IdeGitCommitPanel), matching: finder);

  testWidgets('a change unchecked in the diff stays out of the commit', (
    tester,
  ) async {
    await pumpWorkbench(
      tester,
      const {'lib/a.dart': _file},
      git: git.repository(),
      size: const Size(1800, 900),
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();
    await tester.tap(
      inPanel(find.textContaining('a.dart', findRichText: true)).first,
    );
    await tester.pumpAndSettle();
    final checks = find.byTooltip('Leave This Change Out of the Commit');
    expect(checks, findsNWidgets(2));
    await tester.tap(checks.last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Include This Change in the Commit'), findsOneWidget);

    await tester.enterText(inPanel(find.byType(TextField)), 'Part');
    await tester.tap(inPanel(find.text('Commit')).last);
    await tester.pumpAndSettle();
    expect(git.callsTo('read-tree').single, ['read-tree', 'HEAD']);
    expect(git.callsTo('hash-object').single, [
      'hash-object',
      '-w',
      '--path',
      'lib/a.dart',
      '--stdin',
    ]);
    expect(git.stdins, ['a\nB\nc\nd\ne\nf\ng\nh\n']);
    expect(git.callsTo('commit').single, ['commit', '--quiet', '-m', 'Part']);
    expect(git.callsTo('reset').single, ['reset', '-q', '--', 'lib/a.dart']);
    expect(
      git.environments.every((env) => env.containsKey('GIT_INDEX_FILE')),
      isTrue,
    );
  });

  testWidgets("with the pointer on a change, its lines' check boxes: one "
      'unchecked stays out', (tester) async {
    // The lines taken out show beside the others.
    IdeDiffOptions.instance.layout = IdeDiffLayout.sideBySide;
    await pumpWorkbench(
      tester,
      const {'lib/a.dart': 'a\nB\nc\nd\ne\nf\ng\nH\nI\n'},
      git: git.repository(),
      size: const Size(1800, 900),
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();
    await tester.tap(
      inPanel(find.textContaining('a.dart', findRichText: true)).first,
    );
    await tester.pumpAndSettle();
    final lineChecks = find.byTooltip('Leave This Line Out of the Commit');
    expect(lineChecks, findsNothing);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(
        find.byTooltip('Leave This Change Out of the Commit').last,
      ),
    );
    await tester.pumpAndSettle();
    // h taken out, H and I put in.
    expect(lineChecks, findsNWidgets(3));
    await tester.tap(lineChecks.at(1));
    await tester.pumpAndSettle();
    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    // Some of its lines out: they show still.
    expect(find.byTooltip('Include This Line in the Commit'), findsOneWidget);

    await tester.enterText(inPanel(find.byType(TextField)), 'Part');
    await tester.tap(inPanel(find.text('Commit')).last);
    await tester.pumpAndSettle();
    expect(git.stdins, ['a\nB\nc\nd\ne\nf\ng\nH\n']);
  });
}
