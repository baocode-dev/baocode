import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/git/ide_timeline_view.dart';
import 'package:baocode/ide/ide_dates.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

/// The explorer's Timeline pane with Git's provider.
void main() {
  const files = {'lib/a.dart': 'a', 'lib/b.dart': 'b'};

  int ago(Duration duration) =>
      DateTime.now().subtract(duration).millisecondsSinceEpoch ~/ 1000;

  late FakeGit git;
  setUp(() {
    git = FakeGit(testRoot)
      ..status = '## main\x00M  lib/a.dart\x00'
      ..log =
          gitLogRecord(
            'c1',
            ['c2'],
            'Fix the parser\n\nDetails.',
            author: 'Ada',
            time: ago(const Duration(days: 2)),
          ) +
          gitLogRecord(
            'c2',
            ['c3'],
            'Add a test',
            author: 'Grace',
            time: ago(const Duration(days: 2, hours: 1)),
          ) +
          gitLogRecord(
            'c3',
            [],
            'Initial commit',
            author: 'Ada',
            time: ago(const Duration(days: 21)),
          );
  });

  Future<void> showTimeline(WidgetTester tester) async {
    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
  }

  Finder inTimeline(Finder finder) =>
      find.descendant(of: find.byType(IdeTimelineView), matching: finder);

  bool richText(Widget widget, String text) =>
      widget is RichText && widget.text.toPlainText().contains(text);

  testWidgets('without an editor it says it cannot show one', (tester) async {
    await pumpWorkbench(tester, files, git: git.repository());
    await tester.pumpAndSettle();
    await showTimeline(tester);
    expect(
      inTimeline(
        find.text('The active editor cannot provide timeline information.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('lists the file\'s commits, its staged changes first, with '
      'authors and relative times', (tester) async {
    await pumpWorkbench(
      tester,
      files,
      git: git.repository(),
      open: ['lib/a.dart'],
    );
    await tester.pumpAndSettle();
    await showTimeline(tester);

    // The pane's description is the file.
    expect(find.text('a.dart'), findsWidgets);
    final follow = git
        .callsTo('log')
        .where((call) => call.contains('--follow'));
    expect(follow.single.last, 'lib/a.dart');

    final labels = [
      for (final widget in tester.widgetList<RichText>(
        inTimeline(find.byType(RichText)),
      ))
        widget.text.toPlainText(),
    ];
    final order = [
      'Staged Changes',
      'Fix the parser  Ada',
      'Add a test  Grace',
      'Initial commit  Ada',
    ];
    expect(labels.where(order.contains).toList(), order);
    // The second "2 days" is a line, not the time again.
    expect(
      inTimeline(
        find.byWidgetPredicate((widget) => richText(widget, '2 days')),
      ),
      findsOneWidget,
    );
    expect(
      inTimeline(find.byWidgetPredicate((widget) => richText(widget, '3 wks'))),
      findsOneWidget,
    );
  });

  testWidgets('pinned, it stays on its file', (tester) async {
    final workspace = await pumpWorkbench(
      tester,
      files,
      git: git.repository(),
      open: ['lib/a.dart'],
    );
    await tester.pumpAndSettle();
    await showTimeline(tester);
    final view = tester.widget<IdeTimelineView>(find.byType(IdeTimelineView));
    view.controller.togglePin(view.activePath);
    await tester.pumpAndSettle();

    await workspace.open(inRoot('lib/b.dart'));
    await tester.pumpAndSettle();
    final follow = git
        .callsTo('log')
        .where((call) => call.contains('--follow'));
    expect(follow.map((call) => call.last).toSet(), {'lib/a.dart'});
    expect(find.text('a.dart'), findsWidgets);
  });

  test('ideFromNow matches VS Code\'s fromNow', () {
    final now = DateTime(2026, 9, 30, 12);
    expect(
      ideFromNow(now.subtract(const Duration(seconds: 10)), now: now),
      'now',
    );
    expect(
      ideFromNow(now.subtract(const Duration(minutes: 5)), now: now),
      '5 mins',
    );
    expect(
      ideFromNow(now.subtract(const Duration(hours: 1)), now: now, ago: true),
      '1 hr ago',
    );
    expect(
      ideFromNow(
        now.subtract(const Duration(days: 3)),
        now: now,
        ago: true,
        fullWords: true,
      ),
      '3 days ago',
    );
    expect(
      ideFromNow(now.subtract(const Duration(days: 400)), now: now),
      '1 yr',
    );
    expect(ideFromNow(now.add(const Duration(hours: 2)), now: now), 'in 2 hrs');
  });
}
