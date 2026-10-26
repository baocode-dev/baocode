// A commit's references in the Git log as JetBrains IDEs draw them: an
// icon and a name each, a branch and its remote's as one, the last giving
// way to their icons alone when the row is short of room.

import 'package:baocode/ide/git/git_model.dart';
import 'package:baocode/ide/git/ide_git_ref_labels.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

void main() {
  test("a branch and its remote's of its name are one label", () {
    final labels = ideGitRefLabels(const [
      IdeGitRef('refs/heads/topic', 'topic', IdeGitRefKind.head),
      IdeGitRef(
        'refs/remotes/origin/main',
        'origin/main',
        IdeGitRefKind.remote,
      ),
      IdeGitRef(
        'refs/remotes/origin/topic',
        'origin/topic',
        IdeGitRefKind.remote,
      ),
      IdeGitRef('refs/tags/v1', 'v1', IdeGitRefKind.tag),
    ]);
    expect(
      [for (final label in labels) label.text],
      ['topic', 'origin/main', 'v1'],
    );
    expect(labels.first.tooltip, 'topic\norigin/topic');
  });

  Future<void> pump(
    WidgetTester tester,
    double width,
    String tag, {
    String subject = 'Second',
  }) async {
    final git = FakeGit(testRoot)
      ..status = '## topic...origin/topic\x00'
      ..log = [
        gitLogRecord(
          'c2',
          ['c1'],
          subject,
          refs:
              'HEAD -> refs/heads/topic, refs/remotes/origin/topic, '
              'tag: refs/tags/$tag',
        ),
        gitLogRecord('c1', [], 'First', refs: 'refs/remotes/origin/main'),
      ].join('\n');
    git.refs['HEAD'] = 'c2';
    await pumpWorkbench(
      tester,
      const {'a.txt': 'a'},
      git: git.repository(),
      size: Size(width, 700),
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();
  }

  testWidgets('with room, each label has its name', (tester) async {
    await pump(tester, 1800, 'v1.0');
    expect(find.text('topic'), findsWidgets);
    expect(find.text('v1.0'), findsOneWidget);
    expect(find.text('origin/main'), findsOneWidget);
    // One with the branch.
    expect(find.text('origin/topic'), findsNothing);
  });

  testWidgets('short of room, the last labels are their icons alone', (
    tester,
  ) async {
    await pump(tester, 900, 'release-candidate-1');
    // The current branch's keeps its name; the tag after it does not.
    expect(find.text('topic'), findsWidgets);
    expect(find.text('release-candidate-1'), findsNothing);
  });

  testWidgets("a long subject is cut short before the branch's name; its "
      'hover has the whole commit', (tester) async {
    const subject =
        'Merge pull request #341 from baocode-dev/feat/git-parity with a '
        'subject long enough to be cut short in any table';
    await pump(tester, 900, 'v1.0', subject: subject);
    expect(find.text('topic'), findsWidgets);
    final shown = find.textContaining(
      'Merge pull request #341',
      findRichText: true,
    );
    final before = find.text(subject).evaluate().length;
    final tags = find.text('v1.0').evaluate().length;
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: tester.getCenter(shown.first));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // The hover: the whole message, the references with their names.
    expect(find.text(subject), findsNWidgets(before + 1));
    expect(find.text('v1.0'), findsNWidgets(tags + 1));
  });
}
