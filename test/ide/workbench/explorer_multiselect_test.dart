import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_explorer.dart';

import 'fake_files.dart';

/// The explorer's multi-select, as VS Code's: Ctrl (Cmd) and Shift clicks,
/// Shift with the arrows, Select All and Escape, and the file operations
/// on all of the selection.
void main() {
  const files = {
    'a.txt': 'a',
    'b.txt': 'b',
    'c.txt': 'c',
    'd.txt': 'd',
    'lib/x.dart': 'x',
  };

  Finder row(String name) =>
      find.descendant(of: find.byType(IdeExplorer), matching: find.text(name));

  IdeExplorerController controllerOf(WidgetTester tester) =>
      tester.widget<IdeExplorer>(find.byType(IdeExplorer)).controller;

  TreeFiles filesOf(WidgetTester tester) =>
      controllerOf(tester).files as TreeFiles;

  Set<String> selectionOf(WidgetTester tester) =>
      controllerOf(tester).selection;

  Future<void> click(
    WidgetTester tester,
    String name, {
    LogicalKeyboardKey? holding,
  }) async {
    if (holding != null) await tester.sendKeyDownEvent(holding);
    await tester.tap(row(name));
    if (holding != null) await tester.sendKeyUpEvent(holding);
    await tester.pumpAndSettle();
  }

  Future<void> rightClick(WidgetTester tester, String name) async {
    await tester.tapAt(
      tester.getCenter(row(name)),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Ctrl adds a row or takes it out without opening it; Shift '
      'selects a range from the last one clicked', (tester) async {
    final workspace = await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    await click(tester, 'a.txt');
    expect(workspace.active?.path, inRoot('a.txt'));

    await click(tester, 'c.txt', holding: LogicalKeyboardKey.controlLeft);
    expect(selectionOf(tester), {inRoot('a.txt'), inRoot('c.txt')});
    expect(workspace.active?.path, inRoot('a.txt'));

    await click(tester, 'a.txt', holding: LogicalKeyboardKey.controlLeft);
    expect(selectionOf(tester), {inRoot('c.txt')});

    await click(tester, 'b.txt');
    await click(tester, 'd.txt', holding: LogicalKeyboardKey.shiftLeft);
    expect(selectionOf(tester), {
      inRoot('b.txt'),
      inRoot('c.txt'),
      inRoot('d.txt'),
    });
    // Back from the same anchor.
    await click(tester, 'a.txt', holding: LogicalKeyboardKey.shiftLeft);
    expect(selectionOf(tester), {inRoot('a.txt'), inRoot('b.txt')});

    // A plain click selects the one row again.
    await click(tester, 'c.txt');
    expect(selectionOf(tester), {inRoot('c.txt')});
  });

  testWidgets('Shift with the arrows extends the selection; Ctrl+A selects '
      'every row and Escape none', (tester) async {
    await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    await click(tester, 'b.txt');
    await chord(tester, LogicalKeyboardKey.arrowDown, shift: true);
    await chord(tester, LogicalKeyboardKey.arrowDown, shift: true);
    expect(selectionOf(tester), {
      inRoot('b.txt'),
      inRoot('c.txt'),
      inRoot('d.txt'),
    });
    await chord(tester, LogicalKeyboardKey.arrowUp, shift: true);
    expect(selectionOf(tester), {inRoot('b.txt'), inRoot('c.txt')});

    await chord(tester, LogicalKeyboardKey.keyA, control: true);
    expect(selectionOf(tester), hasLength(5));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(selectionOf(tester), isEmpty);
  });

  testWidgets('the context menu acts on the whole selection, and has no '
      'Rename for more than one', (tester) async {
    await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    await click(tester, 'a.txt');
    await click(tester, 'b.txt', holding: LogicalKeyboardKey.controlLeft);
    await rightClick(tester, 'b.txt');
    expect(find.text('Rename...'), findsNothing);
    await tester.tap(find.text('Delete').first);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Are you sure you want to permanently delete the following 2 '
        'files/directories and their contents?',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    final contents = filesOf(tester).contents;
    expect(contents.containsKey(inRoot('a.txt')), isFalse);
    expect(contents.containsKey(inRoot('b.txt')), isFalse);
    expect(contents.containsKey(inRoot('c.txt')), isTrue);

    // A row outside the selection is acted on alone.
    await click(tester, 'c.txt');
    await click(tester, 'd.txt', holding: LogicalKeyboardKey.controlLeft);
    await rightClick(tester, 'lib');
    expect(selectionOf(tester), {inRoot('lib')});
  });

  testWidgets('Ctrl+C copies the selection; Paste copies each', (tester) async {
    await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    await click(tester, 'a.txt');
    await click(tester, 'b.txt', holding: LogicalKeyboardKey.shiftLeft);
    await chord(tester, LogicalKeyboardKey.keyC, control: true);
    await rightClick(tester, 'lib');
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    final contents = filesOf(tester).contents;
    expect(contents[inRoot('lib/a.txt')], 'a');
    expect(contents[inRoot('lib/b.txt')], 'b');
  });
}
