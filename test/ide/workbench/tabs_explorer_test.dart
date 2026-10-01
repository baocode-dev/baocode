import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/ide_breadcrumbs.dart';
import 'package:monad/ide/ide_explorer.dart';
import 'package:monad/ide/ide_hover.dart';
import 'package:monad/ide/ide_tab_bar.dart';
import 'package:monad/ide/ide_welcome.dart';

import 'fake_files.dart';

Finder _tab(String name) =>
    find.descendant(of: find.byType(IdeTabBar), matching: find.text(name));

Finder _explorerRow(String name) =>
    find.descendant(of: find.byType(IdeExplorer), matching: find.text(name));

List<String> _tabNames(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(of: find.byType(IdeTabBar), matching: find.byType(Text)),
  ))
    if (text.textSpan != null) text.textSpan!.toPlainText(),
];

Future<void> _menu(WidgetTester tester, String tab, String action) async {
  await tester.tap(_tab(tab), buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

void main() {
  const files = {
    'a.dart': 'a',
    'b.dart': 'b',
    'c.dart': 'c',
    'lib/util.dart': 'u',
    'test/util.dart': 't',
  };

  testWidgets('tab context menu closes others, to the right and saved', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      files,
      open: ['a.dart', 'b.dart', 'c.dart', 'lib/util.dart', 'test/util.dart'],
    );
    // Duplicate names are told apart by their folder.
    expect(_tabNames(tester), [
      'a.dart',
      'b.dart',
      'c.dart',
      'util.dart  lib',
      'util.dart  test',
    ]);

    await _menu(tester, 'c.dart', 'Close to the Right');
    expect(_tabNames(tester), ['a.dart', 'b.dart', 'c.dart']);

    workspace.edit(inRoot('b.dart'), 'changed');
    await tester.pump();
    expect(find.byKey(const ValueKey('dirty')), findsOneWidget);
    await _menu(tester, 'a.dart', 'Close Saved');
    expect(_tabNames(tester), ['b.dart']);
    expect(workspace.active!.path, inRoot('b.dart'));

    await workspace.open(inRoot('a.dart'));
    await tester.pump();
    await _menu(tester, 'a.dart', 'Close Others');
    // b.dart is dirty: the prompt asks first.
    expect(find.textContaining('Do you want to save'), findsOneWidget);
    await tester.tap(find.text("Don't Save"));
    await tester.pumpAndSettle();
    expect(_tabNames(tester), ['a.dart']);
  });

  testWidgets('copy paths and reveal in explorer from a tab', (tester) async {
    final copied = <String>[];
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
    await pumpWorkbench(tester, files, open: ['lib/util.dart', 'a.dart']);
    await _menu(tester, 'util.dart', 'Copy Relative Path');
    await _menu(tester, 'util.dart', 'Copy Path');
    expect(copied, ['lib/util.dart', inRoot('lib/util.dart')]);

    // The explorer follows the active editor: a.dart is selected now.
    await tester.pumpAndSettle();
    await _menu(tester, 'util.dart', 'Reveal in Explorer View');
    expect(_explorerRow('util.dart'), findsOneWidget);
  });

  testWidgets('keyboard: close, cycle, reopen and open by index', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      files,
      open: ['a.dart', 'b.dart', 'c.dart'],
    );
    expect(workspace.active!.path, inRoot('c.dart'));
    // Ctrl+Tab picks the editor used before, Ctrl+Shift+Tab the least
    // recently used one (released at once: they open).
    await chord(tester, LogicalKeyboardKey.tab, control: true);
    expect(workspace.active!.path, inRoot('b.dart'));
    await chord(tester, LogicalKeyboardKey.tab, control: true, shift: true);
    expect(workspace.active!.path, inRoot('a.dart'));
    await chord(tester, LogicalKeyboardKey.digit2, alt: true);
    expect(workspace.active!.path, inRoot('b.dart'));
    await chord(tester, LogicalKeyboardKey.digit9, alt: true);
    expect(workspace.active!.path, inRoot('c.dart'));
    // Ctrl+PageDown / Ctrl+PageUp cycle through the tabs.
    await chord(tester, LogicalKeyboardKey.pageDown, control: true);
    expect(workspace.active!.path, inRoot('a.dart'));
    await chord(tester, LogicalKeyboardKey.pageUp, control: true);
    expect(workspace.active!.path, inRoot('c.dart'));

    await chord(tester, LogicalKeyboardKey.keyW, control: true);
    await tester.pumpAndSettle();
    expect(_tabNames(tester), ['a.dart', 'b.dart']);
    await chord(tester, LogicalKeyboardKey.keyT, control: true, shift: true);
    await tester.pumpAndSettle();
    expect(_tabNames(tester), ['a.dart', 'b.dart', 'c.dart']);

    // Middle-click closes; the close button closes the active tab, whose
    // tooltip has Close Editor's keys.
    await tester.tap(_tab('a.dart'), buttons: kMiddleMouseButton);
    await tester.pumpAndSettle();
    expect(_tabNames(tester), ['b.dart', 'c.dart']);
    await tester.tap(find.byTooltip('Close c.dart (Ctrl+W)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close b.dart (Ctrl+W)'));
    await tester.pumpAndSettle();
    expect(workspace.documents, isEmpty);
    expect(find.byType(IdeWelcome), findsOneWidget);
    // The workbench keeps focus, so shortcuts still work.
    await chord(tester, LogicalKeyboardKey.keyB, control: true);
    expect(find.byType(IdeExplorer), findsNothing);
    await chord(tester, LogicalKeyboardKey.keyB, control: true);
    expect(find.byType(IdeExplorer), findsOneWidget);
  });

  testWidgets('explorer: a row\'s title is its path, in the workbench hover '
      'at the pointer', (tester) async {
    await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    final row = tester.getRect(_explorerRow('a.dart'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(row.center);
    await tester.pump();
    await tester.pump(ideHoverDelay + const Duration(milliseconds: 150));
    final hover = find.ancestor(
      of: find.text(inRoot('a.dart')),
      matching: find.byType(IdeHoverBox),
    );
    expect(hover, findsOneWidget);
    expect(tester.getRect(hover).left, closeTo(row.center.dx + 10, 0.01));
  });

  testWidgets('explorer: keyboard navigation, collapse all and refresh', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(tester, {
      ...files,
      'lib/src/deep.dart': 'deep',
    });
    await tester.pumpAndSettle();
    expect(_explorerRow('lib'), findsOneWidget);
    expect(_explorerRow('util.dart'), findsNothing);

    await tester.tap(_explorerRow('lib'));
    await tester.pumpAndSettle();
    expect(_explorerRow('util.dart'), findsOneWidget);
    expect(_explorerRow('src'), findsOneWidget);

    // Down to src, right expands it, right again enters it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_explorerRow('deep.dart'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(workspace.active!.path, inRoot('lib/src/deep.dart'));

    // Left goes to the parent folder, then collapses it.
    await tester.tap(_explorerRow('deep.dart'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_explorerRow('deep.dart'), findsNothing);

    // The folder pane's actions show while it is hovered.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(IdeExplorer)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Collapse Folders in Explorer'));
    await tester.pumpAndSettle();
    expect(_explorerRow('util.dart'), findsNothing);

    // Breadcrumbs reveal a folder of the active file in the explorer.
    await tester.tap(
      find.descendant(
        of: find.byType(IdeBreadcrumbs),
        matching: find.text('src'),
      ),
    );
    await tester.pumpAndSettle();
    expect(_explorerRow('src'), findsOneWidget);
    expect(_explorerRow('util.dart'), findsOneWidget);

    await tester.tap(find.byTooltip('Refresh Explorer'));
    await tester.pumpAndSettle();
    expect(_explorerRow('src'), findsOneWidget);
  });
}
