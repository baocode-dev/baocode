// BaoCode's own: in a file's diff in the commit panel, the changes an
// agent made marked with what its turn was asked; the user's own not.

import 'package:baocode/ide/git/git_partial.dart';
import 'package:baocode/ide/ide_code_diff.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("the agent's changes marked with its turns' requests", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // HEAD; the file before the agent (the user changed b); now (the
    // agent changed g).
    const head = 'a\nb\nc\nd\ne\nf\ng\nh\n';
    const base = 'a\nB\nc\nd\ne\nf\ng\nh\n';
    const now = 'a\nB\nc\nd\ne\nf\nG\nh\n';
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: IdeCodeDiff(
            path: 'a.txt',
            original: head,
            modified: now,
            onEdit: (_) async {},
            checks: IdeGitHunkSelection().checksOf('a.txt'),
            agent: const IdeDiffAgentMarks(base, [
              'Rename the thing\nand more',
              'Capitalize g',
            ]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byTooltip('Leave This Change Out of the Commit'),
      findsNWidgets(2),
    );
    // One mark, the last turn's request.
    expect(find.text('AI · Capitalize g'), findsOneWidget);
    final mark = tester.getCenter(find.text('AI · Capitalize g'));
    final changes = find.byTooltip('Leave This Change Out of the Commit');
    expect(
      (mark.dy - tester.getCenter(changes.last).dy).abs(),
      lessThan((mark.dy - tester.getCenter(changes.first).dy).abs()),
    );
  });
}
