// Where the Git log's details show: beside the table by the width, or as
// picked from the toolbar's menu, beside it or under it whatever the width.

import 'package:baocode/ide/git/ide_git_log_view.dart';
import 'package:baocode/ide/ide_diff_options.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

void main() {
  tearDown(IdeDiffOptions.instance.reset);

  Finder sash(MouseCursor cursor) => find.descendant(
    of: find.byType(IdeGitLogView),
    matching: find.byWidgetPredicate(
      (widget) => widget is MouseRegion && widget.cursor == cursor,
    ),
  );

  testWidgets('the details go beside the log, or under it, as picked', (
    tester,
  ) async {
    final git = FakeGit(testRoot)
      ..status = '## main\x00'
      ..log = gitLogRecord('c1', [], 'First', refs: 'HEAD -> refs/heads/main');
    git.refs['HEAD'] = 'c1';
    await pumpWorkbench(tester, const {'a.txt': 'a'}, git: git.repository());
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();
    final width = tester.getSize(find.byType(IdeGitLogView)).width;
    expect(width, greaterThanOrEqualTo(IdeGitLogView.wideWidth));
    // Beside: the line between them is a column's (the details' own lines
    // within aside).
    int rows() => sash(SystemMouseCursors.resizeRow).evaluate().length;
    int columns() => sash(SystemMouseCursors.resizeColumn).evaluate().length;
    final (beside, besideRows) = (columns(), rows());
    expect(beside, greaterThan(0));

    IdeDiffOptions.instance.detailsLayout = IdeGitDetailsLayout.below;
    await tester.pumpAndSettle();
    expect(columns(), beside - 1);
    expect(rows(), greaterThan(besideRows));

    IdeDiffOptions.instance.detailsLayout = IdeGitDetailsLayout.beside;
    await tester.pumpAndSettle();
    expect((columns(), rows()), (beside, besideRows));
  });
}
