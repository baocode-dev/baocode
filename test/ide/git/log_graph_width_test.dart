// The Git log's graph is as wide as its lanes: a history of many branches
// side by side has them all, the message beside them, not under them.

import 'package:baocode/ide/git/git_graph_painter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

void main() {
  testWidgets('a graph of 20 lanes is not cut off', (tester) async {
    // 20 branches off one commit, all open down to it.
    const branches = 20;
    final git = FakeGit(testRoot)
      ..status = '## main\x00'
      ..log = [
        for (var i = branches; i >= 1; i--)
          gitLogRecord(
            'c$i',
            ['base'],
            'Branch $i',
            refs: i == branches ? 'HEAD -> refs/heads/main' : '',
            time: 1767225600 + i * 60,
          ),
        gitLogRecord('base', [], 'Base'),
      ].join('\n');
    git.refs['HEAD'] = 'c$branches';
    await pumpWorkbench(tester, const {'a.txt': 'a'}, git: git.repository());
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();

    // The last branch's row: every lane, and its own.
    final subject = find.text('Branch 1');
    final graph = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is IdeGraphPainter,
    );
    final row = find.ancestor(of: subject, matching: find.byType(Row)).first;
    final painted = find.descendant(of: row, matching: graph);
    final full = ideGraphWidth(
      (tester.widget<CustomPaint>(painted).painter! as IdeGraphPainter).row,
    );
    expect(full, greaterThan(ideGraphLaneWidth * 12));
    expect(
      tester.getTopLeft(subject).dx - tester.getTopLeft(painted).dx,
      greaterThanOrEqualTo(full),
    );
  });
}
