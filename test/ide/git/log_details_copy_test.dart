// A commit's details in the Git log: its text selectable, its references'
// names, hash and author copied from a right-click; the branches that have
// it shown at once. The commit's menu in the table copies its references'
// names too.

import 'package:baocode/ide/git/git_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

void main() {
  late FakeGit git;
  late List<String> copied;

  setUp(() {
    git = FakeGit(testRoot)
      ..status = '## main\x00'
      ..log =
          '${gitLogRecord('c2', ['c1'], 'Second', refs: 'HEAD -> refs/heads/main, tag: refs/tags/v1.0')}\n'
          '${gitLogRecord('c1', [], 'First')}'
      ..answers['branch'] = const IdeGitOutput(
        0,
        'refs/heads/main\nrefs/heads/feature/long-name\n'
        'refs/remotes/origin/feature/long-name\nrefs/remotes/origin/HEAD\n',
      );
    git.refs['HEAD'] = 'c2';
    copied = [];
  });

  Future<void> pump(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpWorkbench(tester, const {
      'lib/a.dart': 'a',
    }, git: git.repository());
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('First').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second').first);
    await tester.pumpAndSettle();
  }

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    await tester.tapAt(
      tester.getCenter(finder),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  final details = find.byType(SelectableRegion);
  Finder inDetails(String text) =>
      find.descendant(of: details, matching: find.text(text));

  testWidgets('the details are selectable, and show the branches that have '
      'the commit, not asked for', (tester) async {
    await pump(tester);
    expect(inDetails('commit: c2'), findsOneWidget);
    expect(inDetails('Second'), findsOneWidget);
    expect(find.text('Hide Branches'), findsOneWidget);
    // A local branch of a slashed name and its remote's, as one; the
    // remote's HEAD left out.
    expect(inDetails('In 2 branches'), findsOneWidget);
    expect(inDetails('feature/long-name'), findsOneWidget);
    expect(inDetails('origin/feature/long-name'), findsNothing);
  });

  testWidgets('a reference right-clicked in the details copies its whole '
      'name; the hash and the author too', (tester) async {
    await pump(tester);
    await rightClick(tester, inDetails('feature/long-name'));
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('feature/long-name').last);
    await tester.pumpAndSettle();
    expect(copied.last, 'feature/long-name');

    await rightClick(tester, inDetails('commit: c2'));
    await tester.tap(find.text('Copy Commit Hash'));
    await tester.pumpAndSettle();
    expect(copied.last, 'c2');

    await rightClick(tester, inDetails('Ada'));
    await tester.tap(find.text("Copy 'ada@example.com'"));
    await tester.pumpAndSettle();
    expect(copied.last, 'ada@example.com');
  });

  testWidgets(
    'text dragged across in the details is copied from its '
    'right-click',
    (tester) async {
      await pump(tester);
      final message = inDetails('Second');
      final box = tester.getRect(message);
      final gesture = await tester.startGesture(
        box.centerLeft + const Offset(1, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(box.centerRight - const Offset(1, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await rightClick(tester, message);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(copied.last, 'Second');
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets("the commit's menu in the table copies its references' names", (
    tester,
  ) async {
    await pump(tester);
    final row = find.text('Second').first;
    await rightClick(tester, row);
    await tester.tap(find.text('Copy Branch or Tag Name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('v1.0').last);
    await tester.pumpAndSettle();
    expect(copied.last, 'v1.0');
  });
}
