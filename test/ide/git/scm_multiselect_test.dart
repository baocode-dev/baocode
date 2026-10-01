import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_list.dart';
import 'package:baocode/ide/ide_workspace.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

/// The Source Control view's multi-select, as VS Code's: Ctrl (Cmd) and
/// Shift clicks, Shift with the arrows, Select All and Escape, and the
/// actions on all of the selection.
void main() {
  late FakeGit git;

  setUp(() {
    git = FakeGit(testRoot);
    git.status =
        '## main...origin/main\x00'
        'M  lib/staged.dart\x00'
        ' M lib/a.dart\x00'
        ' M lib/b.dart\x00'
        '?? notes.md\x00';
  });

  Future<IdeWorkspace> pumpScm(WidgetTester tester) async {
    final workspace = await pumpWorkbench(tester, const {
      'lib/a.dart': 'a',
      'lib/b.dart': 'b',
      'lib/staged.dart': 's',
      'notes.md': 'n',
    }, git: git.repository());
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();
    return workspace;
  }

  Finder rowOf(String name) => find.ancestor(
    of: find.byWidgetPredicate(
      (widget) => widget is IdeResourceLabel && widget.name == name,
    ),
    matching: find.byType(IdeListRow),
  );

  /// The names of the selected changes.
  Set<String> selectedOf(WidgetTester tester) => {
    for (final element in find.byType(IdeListRow).evaluate())
      if ((element.widget as IdeListRow).selected)
        ...find
            .descendant(
              of: find.byWidget(element.widget),
              matching: find.byType(IdeResourceLabel),
            )
            .evaluate()
            .map((label) => (label.widget as IdeResourceLabel).name),
  };

  Future<void> click(
    WidgetTester tester,
    String name, {
    LogicalKeyboardKey? holding,
  }) async {
    if (holding != null) await tester.sendKeyDownEvent(holding);
    await tester.tap(rowOf(name));
    if (holding != null) await tester.sendKeyUpEvent(holding);
    await tester.pumpAndSettle();
  }

  Future<void> rightClick(WidgetTester tester, String name) async {
    await tester.tapAt(
      tester.getCenter(rowOf(name)),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Ctrl adds a change without opening it, and the menu stages '
      'the selection; no reveals for more than one', (tester) async {
    final workspace = await pumpScm(tester);
    await click(tester, 'a.dart');
    await click(tester, 'notes.md', holding: LogicalKeyboardKey.controlLeft);
    expect(selectedOf(tester), {'a.dart', 'notes.md'});
    expect(workspace.active?.path, inRoot('lib/a.dart'));

    await rightClick(tester, 'notes.md');
    expect(find.text('Reveal in Explorer View'), findsNothing);
    await tester.tap(find.text('Stage Changes'));
    await tester.pumpAndSettle();
    expect(git.callsTo('add').single, [
      'add',
      '-A',
      '--',
      'lib/a.dart',
      'notes.md',
    ]);
  });

  testWidgets('Shift selects a range from the last one clicked; a row out '
      'of the selection is acted on alone', (tester) async {
    await pumpScm(tester);
    await click(tester, 'a.dart');
    await click(tester, 'notes.md', holding: LogicalKeyboardKey.shiftLeft);
    expect(selectedOf(tester), {'a.dart', 'b.dart', 'notes.md'});

    // The inline action of a selected row: on all of them.
    await tester.tap(
      find.descendant(
        of: rowOf('b.dart'),
        matching: find.byTooltip('Stage Changes'),
      ),
    );
    await tester.pumpAndSettle();
    expect(git.callsTo('add').single, [
      'add',
      '-A',
      '--',
      'lib/a.dart',
      'lib/b.dart',
      'notes.md',
    ]);

    await rightClick(tester, 'staged.dart');
    expect(selectedOf(tester), {'staged.dart'});
    expect(find.text('Reveal in Explorer View'), findsOneWidget);
  });

  testWidgets('Shift with the arrows extends the selection; Ctrl+A selects '
      'every row and Escape none', (tester) async {
    await pumpScm(tester);
    await click(tester, 'a.dart');
    await chord(tester, LogicalKeyboardKey.arrowDown, shift: true);
    await chord(tester, LogicalKeyboardKey.arrowDown, shift: true);
    expect(selectedOf(tester), {'a.dart', 'b.dart', 'notes.md'});
    await chord(tester, LogicalKeyboardKey.arrowUp, shift: true);
    expect(selectedOf(tester), {'a.dart', 'b.dart'});

    await chord(tester, LogicalKeyboardKey.keyA, control: true);
    expect(selectedOf(tester), {
      'staged.dart',
      'a.dart',
      'b.dart',
      'notes.md',
      'lib',
    });

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(selectedOf(tester), isEmpty);
  });
}
