import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:baocode/keybindings/keybinding_service.dart';

import 'fake_files.dart';

/// The quick input's keys are keybindings (VS Code's `quickInput.next`,
/// `quickInput.accept`, `workbench.action.quickOpenNavigateNextInEditorPicker`
/// …), and Ctrl+Tab is upstream's editor picker, which releasing Ctrl
/// accepts.
void main() {
  const files = {
    'a.dart': 'a\n',
    'b.dart': 'b\n',
    'c.dart': 'c\n',
    'lib/d.dart': 'd\n',
  };

  setUp(() => KeybindingService.instance = KeybindingService());
  tearDown(() => KeybindingService.instance = KeybindingService());

  IdeWorkbenchState workbench(WidgetTester tester) =>
      tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

  IdeQuickInputState? quick(WidgetTester tester) {
    final found = find.byType(IdeQuickInput);
    if (found.evaluate().isEmpty) return null;
    return tester.state<IdeQuickInputState>(found);
  }

  String? activeRow(WidgetTester tester) => quick(tester)?.activeRow?.label;

  Finder input() => find.descendant(
    of: find.byType(IdeQuickInput),
    matching: find.byType(TextField),
  );

  Future<void> key(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool control = false,
    bool shift = false,
  }) async {
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('the palette\'s keys are the quick input\'s keybindings', (
    tester,
  ) async {
    await pumpWorkbench(tester, files, open: ['a.dart']);
    await chord(tester, LogicalKeyboardKey.keyP, control: true, shift: true);
    final state = workbench(tester);
    expect(state.keyContext('inQuickInput'), isTrue);
    expect(state.keyContext('inQuickOpen'), isTrue);
    expect(state.keyContext('quickInputType'), 'quickPick');
    expect(state.keyContext('inFilesPicker'), isFalse);
    expect(state.keyContext('cursorAtEndOfQuickInputBox'), isTrue);
    final first = activeRow(tester);

    await key(tester, LogicalKeyboardKey.arrowDown);
    final second = activeRow(tester);
    expect(second, isNot(first));
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(activeRow(tester), first);
    // The previous of the first is the last (upstream loops).
    await key(tester, LogicalKeyboardKey.arrowUp);
    final last = activeRow(tester);
    await key(tester, LogicalKeyboardKey.home, control: true);
    expect(activeRow(tester), first);
    await key(tester, LogicalKeyboardKey.end, control: true);
    expect(activeRow(tester), last);
    await key(tester, LogicalKeyboardKey.home, control: true);
    await key(tester, LogicalKeyboardKey.pageDown);
    expect(activeRow(tester), isNot(first));
    await key(tester, LogicalKeyboardKey.pageUp);
    expect(activeRow(tester), first);

    // The typing field keeps its keys: Left moves the caret, and Right
    // accepts in the background only at the end.
    await tester.enterText(input(), '>ab');
    await tester.pump();
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(state.keyContext('cursorAtEndOfQuickInputBox'), isFalse);
    expect(
      tester.widget<TextField>(input()).controller!.selection.baseOffset,
      2,
    );

    await key(tester, LogicalKeyboardKey.escape);
    expect(find.byType(IdeQuickInput), findsNothing);
    expect(state.keyContext('inQuickInput'), isFalse);
  });

  testWidgets('the user\'s keybindings move and accept in the quick input', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(tester, files, open: ['a.dart']);
    KeybindingService.instance.userEntries = const [
      KeybindingEntry(
        key: 'ctrl+j',
        command: 'quickInput.next',
        when: 'inQuickInput',
      ),
      KeybindingEntry(
        key: 'ctrl+l',
        command: 'quickInput.accept',
        when: 'inQuickInput',
      ),
      // The prefix Go to File… opens with, from `args`.
      KeybindingEntry(
        key: 'ctrl+alt+o',
        command: 'workbench.action.quickOpen',
        args: 'b.da',
      ),
    ];
    await tester.pump();
    await chord(tester, LogicalKeyboardKey.keyO, control: true, alt: true);
    // The files' listing comes.
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input()).controller!.text, 'b.da');
    expect(activeRow(tester), 'b.dart');
    await key(tester, LogicalKeyboardKey.keyL, control: true);
    await tester.pump();
    expect(find.byType(IdeQuickInput), findsNothing);
    expect(workspace.active!.path, inRoot('b.dart'));

    await chord(tester, LogicalKeyboardKey.keyP, control: true);
    final first = activeRow(tester);
    await key(tester, LogicalKeyboardKey.keyJ, control: true);
    expect(activeRow(tester), isNot(first));
    // Ctrl+J is no longer the chat's here.
    expect(find.byType(IdeQuickInput), findsOneWidget);
  });

  testWidgets('Ctrl+Tab held: the editor picker, releasing Ctrl opens', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      files,
      open: ['a.dart', 'b.dart', 'c.dart'],
    );
    final state = workbench(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
    // The input is hidden; the one used before is active.
    expect(find.byType(IdeQuickInput), findsOneWidget);
    expect(input(), findsNothing);
    expect(state.keyContext('inEditorsPicker'), isTrue);
    expect(activeRow(tester), 'b.dart');
    // Tab again, Ctrl still held: the next one.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(activeRow(tester), 'a.dart');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(activeRow(tester), 'b.dart');
    // Shift let go first is not the end; Ctrl is.
    expect(find.byType(IdeQuickInput), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    expect(find.byType(IdeQuickInput), findsNothing);
    expect(workspace.active!.path, inRoot('b.dart'));

    // Ctrl+Shift+Tab: the least recently used one.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
    expect(activeRow(tester), 'a.dart');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    expect(workspace.active!.path, inRoot('a.dart'));
  });

  testWidgets('Ctrl+P again in Quick Open navigates; releasing Ctrl opens', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      files,
      open: ['a.dart', 'b.dart'],
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    await tester.pump();
    final state = workbench(tester);
    expect(state.keyContext('inFilesPicker'), isTrue);
    expect(input(), findsOneWidget);
    // Recent files first, the active one on top.
    expect(activeRow(tester), 'b.dart');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(activeRow(tester), 'a.dart');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    expect(find.byType(IdeQuickInput), findsNothing);
    expect(workspace.active!.path, inRoot('a.dart'));
  });

  testWidgets('Right at the end of the input opens in the background', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      files,
      open: ['a.dart', 'b.dart'],
    );
    await chord(tester, LogicalKeyboardKey.keyP, control: true);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(activeRow(tester), 'a.dart');
    await key(tester, LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump();
    expect(workspace.active!.path, inRoot('a.dart'));
    // Quick Open stays, with the keyboard.
    expect(find.byType(IdeQuickInput), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<IdeQuickInput>(),
      isNotNull,
    );
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.byType(IdeQuickInput), findsNothing);
  });

  testWidgets('macOS: Ctrl+N and Ctrl+P select in Quick Open', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await pumpWorkbench(tester, files, open: ['a.dart', 'b.dart']);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    await tester.pump();
    expect(activeRow(tester), 'b.dart');
    await key(tester, LogicalKeyboardKey.keyN, control: true);
    expect(activeRow(tester), 'a.dart');
    await key(tester, LogicalKeyboardKey.keyP, control: true);
    expect(activeRow(tester), 'b.dart');
    // Not a quick navigation: releasing Control does not accept.
    expect(find.byType(IdeQuickInput), findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the editor pickers list, filter and open editors', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      files,
      open: ['a.dart', 'lib/d.dart', 'b.dart'],
    );
    // Ctrl+K Ctrl+P: by appearance.
    await chord(tester, LogicalKeyboardKey.keyK, control: true);
    await chord(tester, LogicalKeyboardKey.keyP, control: true);
    expect(tester.widget<TextField>(input()).controller!.text, 'edt ');
    final labels = [
      for (final text in tester.widgetList<Text>(
        find.descendant(
          of: find.byType(IdeQuickInput),
          matching: find.byType(Text),
        ),
      ))
        if (text.textSpan != null) text.textSpan!.toPlainText(),
    ];
    expect(labels, ['a.dart', 'd.dart  lib', 'b.dart']);
    await tester.enterText(input(), 'edt d.d');
    await tester.pump();
    expect(activeRow(tester), 'd.dart');
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(workspace.active!.path, inRoot('lib/d.dart'));

    await chord(tester, LogicalKeyboardKey.keyK, control: true);
    await chord(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.enterText(input(), 'edt nothing');
    await tester.pump();
    expect(activeRow(tester), 'No matching editors');
    await key(tester, LogicalKeyboardKey.escape);
  });
}
