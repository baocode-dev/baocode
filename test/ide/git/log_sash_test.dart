// The Git log's line between the table and the details stays under the
// pointer as it is dragged, back from past where the details stop too.

import 'package:baocode/ide/git/ide_git_log_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

void main() {
  testWidgets('the sash stays under the pointer', (tester) async {
    final git = FakeGit(testRoot)
      ..status = '## main\x00'
      ..log = gitLogRecord('c1', [], 'First', refs: 'HEAD -> refs/heads/main');
    git.refs['HEAD'] = 'c1';
    await pumpWorkbench(tester, const {'a.txt': 'a'}, git: git.repository());
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();

    final sash = find
        .descendant(
          of: find.byType(IdeGitLogView),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is MouseRegion &&
                widget.cursor == SystemMouseCursors.resizeColumn,
          ),
        )
        .last;
    final start = tester.getCenter(sash);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    // Far past where the details stop growing, then back.
    for (final dx in [-40.0, -400.0, -2000.0, -400.0, -60.0]) {
      await gesture.moveTo(start + Offset(dx, 0));
      await tester.pump();
    }
    expect(
      tester.getCenter(sash).dx,
      moreOrLessEquals(start.dx - 60, epsilon: 1),
    );
    await gesture.moveTo(start + const Offset(30, 0));
    await tester.pump();
    expect(
      tester.getCenter(sash).dx,
      moreOrLessEquals(start.dx + 30, epsilon: 1),
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
