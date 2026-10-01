import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/ide_explorer.dart';
import 'package:monad/ide/ide_input.dart';
import 'package:monad/keybindings/keybinding_entry.dart';
import 'package:monad/keybindings/keybinding_service.dart';
import 'package:monad/keybindings/keymap.dart';

import 'fake_files.dart';

/// The explorer's keys are keybindings (VS Code's `explorer.newFile`,
/// `renameFile`, `list.focusDown`…): a keymap's and the user's apply there.
void main() {
  const files = {'lib/a.dart': 'a', 'lib/util.dart': 'u', 'README.md': 'r'};

  setUp(() => KeybindingService.instance = KeybindingService());
  tearDown(() => KeybindingService.instance = KeybindingService());

  Finder row(String name) =>
      find.descendant(of: find.byType(IdeExplorer), matching: find.text(name));

  String? selected(WidgetTester tester) =>
      tester.widget<IdeExplorer>(find.byType(IdeExplorer)).controller.selected;

  Finder input() => find.descendant(
    of: find.byType(IdeInputBox),
    matching: find.byType(EditableText),
  );

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  }

  void useAtom() {
    final atom = Keymap.fromJson(
      jsonDecode(
        File('assets/keymaps/ms-vscode.atom-keybindings.json')
            .readAsStringSync(),
      ),
      builtIn: true,
    )!;
    KeybindingService.instance.setKeymap(
      atom.id,
      name: atom.name,
      entries: atom.entries,
    );
  }

  testWidgets("Atom's keys: a and ⇧a make a file and a folder, h j k l move, "
      'backspace deletes', (tester) async {
    useAtom();
    await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    // Selects lib and opens it; the explorer has the focus.
    await tester.tap(row('lib'));
    await tester.pumpAndSettle();
    expect(selected(tester), inRoot('lib'));

    await press(tester, LogicalKeyboardKey.keyJ);
    expect(selected(tester), inRoot('lib/a.dart'));
    await press(tester, LogicalKeyboardKey.keyK);
    expect(selected(tester), inRoot('lib'));
    await press(tester, LogicalKeyboardKey.keyH);
    expect(row('a.dart'), findsNothing, reason: 'lib collapsed');
    await press(tester, LogicalKeyboardKey.keyL);
    expect(row('a.dart'), findsOneWidget, reason: 'lib expanded');

    await press(tester, LogicalKeyboardKey.keyA);
    expect(input(), findsOneWidget);
    expect(tester.widget<EditableText>(input()).controller.text, isEmpty);
    // Typed into the name, a is not New File again (`!inputFocus`).
    await press(tester, LogicalKeyboardKey.keyA);
    expect(input(), findsOneWidget);
    await tester.enterText(input(), 'new.dart');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(row('new.dart'), findsOneWidget);

    await tester.tap(row('lib'));
    await tester.pumpAndSettle();
    await tester.tap(row('lib'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyA, shift: true);
    expect(input(), findsOneWidget);
    await tester.enterText(input(), 'src');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(row('src'), findsOneWidget);

    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.backspace);
    // No Trash under test: it asks to delete permanently.
    expect(
      find.text("Are you sure you want to permanently delete 'README.md'?"),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets("the context menu shows the keymap's keys", (tester) async {
    useAtom();
    await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(row('lib')),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.text('New File...'), findsOneWidget);
    // Atom's a and ⇧a, as the platform writes them (Linux under test).
    expect(find.text('A'), findsOneWidget);
    expect(find.text('Shift+A'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
  });

  testWidgets("the user's keybindings.json moves Rename from F2 to r", (
    tester,
  ) async {
    KeybindingService.instance.userEntries = const [
      KeybindingEntry(command: '-renameFile', key: 'f2'),
      KeybindingEntry(
        command: 'renameFile',
        key: 'r',
        when: 'filesExplorerFocus && !inputFocus',
      ),
    ];
    await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.f2);
    expect(input(), findsNothing);
    await press(tester, LogicalKeyboardKey.keyR);
    expect(tester.widget<EditableText>(input()).controller.text, 'README.md');
    await press(tester, LogicalKeyboardKey.escape);
    expect(input(), findsNothing);
  });

  testWidgets('without a keymap, the default keys: arrows move, Enter opens', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    await tester.tap(row('lib'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(selected(tester), inRoot('lib/a.dart'));
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(selected(tester), inRoot('lib'), reason: 'to the parent');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(row('a.dart'), findsNothing);
    await press(tester, LogicalKeyboardKey.end);
    expect(selected(tester), inRoot('README.md'));
    await press(tester, LogicalKeyboardKey.enter);
    expect(workspace.active?.path, inRoot('README.md'));
    // Unbound in the explorer: j is nothing.
    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyJ);
    expect(selected(tester), inRoot('README.md'));
  });
}
