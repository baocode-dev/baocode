import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/ide_find_widget.dart';
import 'package:monad/ide/ide_quick_input.dart';
import 'package:monad/ide/ide_workbench.dart';
import 'package:monad/ide/terminal/terminal_instance.dart';
import 'package:monad/ide/terminal/terminal_view.dart';
import 'package:monad/keybindings/keybinding_entry.dart';
import 'package:monad/keybindings/keybinding_service.dart';

import '../terminal/fake_pty.dart';
import 'fake_files.dart';

/// A terminal's keys are the workbench's keybindings (VS Code's terminal
/// commands and `terminal.integrated.commandsToSkipShell`): those that
/// resolve to a command of the list, or start a chord, skip the shell; the
/// rest go to it.
void main() {
  setUp(() => KeybindingService.instance = KeybindingService());
  tearDown(() {
    KeybindingService.instance = KeybindingService();
    debugDefaultTargetPlatformOverride = null;
  });

  IdeWorkbenchState workbench(WidgetTester tester) =>
      tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

  TerminalInstance shown(WidgetTester tester) =>
      tester.widget<TerminalView>(find.byType(TerminalView)).instance;

  /// The clipboard: what was copied, and what a paste reads.
  List<String> clipboard(WidgetTester tester, {String text = ''}) {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.setData' => () {
          copied.add((call.arguments as Map)['text'] as String);
        }(),
        'Clipboard.getData' => {'text': text},
        'Clipboard.hasStrings' => {'value': text.isNotEmpty},
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return copied;
  }

  Future<FakePty> pumpTerminal(WidgetTester tester) async {
    final ptys = <FakePty>[];
    await pumpWorkbench(
      tester,
      {'a.txt': 'a'},
      open: ['a.txt'],
      startPty: FakePty.starter(ptys),
    );
    await chord(tester, LogicalKeyboardKey.backquote, control: true);
    await tester.pump(const Duration(milliseconds: 1));
    final pty = ptys.single;
    expect(shown(tester).focusNode.hasFocus, isTrue);
    pty.writes.clear();
    return pty;
  }

  Future<void> run(WidgetTester tester, String id) async {
    workbench(tester).commands
        .firstWhere((command) => command.id == id)
        .invoke();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool control = false,
    bool shift = false,
    bool alt = false,
    bool meta = false,
  }) async {
    if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await chord(tester, key, control: control, shift: shift, alt: alt);
    if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('copy, paste, clear the selection and the sequences are the '
      'workbench\'s commands; the other keys go to the shell', (tester) async {
    final copied = clipboard(tester, text: 'echo hi');
    final pty = await pumpTerminal(tester);
    final state = workbench(tester);
    final terminal = shown(tester);
    expect(state.keyContext('terminalFocus'), isTrue);
    expect(state.keyContext('terminalFocusInAny'), isTrue);
    expect(state.keyContext('terminalHasBeenCreated'), isTrue);
    expect(state.keyContext('terminalCount'), 1);
    pty.emitText('hello');
    await tester.pump(const Duration(milliseconds: 1));

    // Without a selection Ctrl+Shift+C is the shell's; with one, it copies.
    expect(state.keyContext('terminalTextSelected'), isFalse);
    await run(tester, 'workbench.action.terminal.selectAll');
    expect(state.keyContext('terminalTextSelectedInFocused'), isTrue);
    await press(tester, LogicalKeyboardKey.keyC, control: true, shift: true);
    expect(copied.single, startsWith('hello'));
    expect(pty.written, isEmpty);
    // Escape clears the selection; then it is the shell's.
    await press(tester, LogicalKeyboardKey.escape);
    expect(terminal.selection.hasSelection, isFalse);
    expect(pty.written, isEmpty);
    await press(tester, LogicalKeyboardKey.escape);
    expect(pty.written, '\x1b');
    pty.writes.clear();

    // Ctrl+Shift+V pastes (Linux); Alt+Left sends Ctrl+Left's sequence.
    await press(tester, LogicalKeyboardKey.keyV, control: true, shift: true);
    expect(pty.written, 'echo hi');
    pty.writes.clear();
    await press(tester, LogicalKeyboardKey.arrowLeft, alt: true);
    expect(pty.written, '\x1b[1;5D');
    pty.writes.clear();

    // Ctrl+B toggles the side bar elsewhere; here it is the shell's.
    final sidebar = state.keyContext('sideBarVisible');
    await press(tester, LogicalKeyboardKey.keyB, control: true);
    expect(pty.written, '\x02');
    expect(state.keyContext('sideBarVisible'), sidebar);
    pty.writes.clear();
    // Ctrl+P skips the shell: Quick Open.
    await press(tester, LogicalKeyboardKey.keyP, control: true);
    expect(pty.written, isEmpty);
    expect(find.byType(IdeQuickInput), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(IdeQuickInput), findsNothing);
  });

  testWidgets('the user\'s keybindings: Send Sequence with its text, and a '
      'terminal key given back to the shell', (tester) async {
    clipboard(tester, text: 'echo hi');
    final pty = await pumpTerminal(tester);
    KeybindingService.instance.userEntries = const [
      KeybindingEntry(
        key: 'ctrl+alt+l',
        command: 'workbench.action.terminal.sendSequence',
        args: {'text': 'ls -la\n'},
        when: 'terminalFocus',
      ),
      KeybindingEntry(
        key: 'ctrl+shift+v',
        command: '-workbench.action.terminal.paste',
      ),
      KeybindingEntry(key: 'ctrl+p', command: '-workbench.action.quickOpen'),
    ];
    await tester.pump();
    await press(tester, LogicalKeyboardKey.keyL, control: true, alt: true);
    expect(pty.written, 'ls -la\r');
    pty.writes.clear();
    // Ctrl+Shift+V no longer pastes (xterm.js sends nothing for it).
    await press(tester, LogicalKeyboardKey.keyV, control: true, shift: true);
    expect(pty.written, isEmpty);
    // Ctrl+P, without its command, is the shell's.
    await press(tester, LogicalKeyboardKey.keyP, control: true);
    expect(pty.written, '\x10');
    expect(find.byType(IdeQuickInput), findsNothing);
  });

  testWidgets('a chord\'s first key skips the shell; Shift+PageUp and '
      'Shift+Home scroll', (tester) async {
    final pty = await pumpTerminal(tester);
    final terminal = shown(tester);
    // Ctrl+K starts a chord (`terminal.integrated.allowChords`).
    await press(tester, LogicalKeyboardKey.keyK, control: true);
    expect(pty.written, isEmpty);
    await press(tester, LogicalKeyboardKey.escape);

    pty.emitText([for (var i = 0; i < 200; i++) 'line $i'].join('\r\n'));
    await tester.pump(const Duration(milliseconds: 1));
    final buffer = terminal.terminal.buffer;
    final bottom = buffer.ydisp;
    expect(bottom, greaterThan(0));
    await press(tester, LogicalKeyboardKey.pageUp, shift: true);
    expect(buffer.ydisp, lessThan(bottom));
    await press(tester, LogicalKeyboardKey.home, shift: true);
    expect(buffer.ydisp, 0);
    await press(
      tester,
      LogicalKeyboardKey.arrowDown,
      control: true,
      shift: true,
    );
    expect(buffer.ydisp, 1);
    await press(tester, LogicalKeyboardKey.end, shift: true);
    expect(buffer.ydisp, bottom);
    expect(pty.written, isEmpty);
  });

  testWidgets('macOS: ⌘K clears, ⌘A selects all, ⌘C copies, ⌥← and ⌘← '
      'send their sequences', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final copied = clipboard(tester);
    final pty = await pumpTerminal(tester);
    final terminal = shown(tester);
    pty.emitText('one\r\ntwo');
    await tester.pump(const Duration(milliseconds: 1));

    await press(tester, LogicalKeyboardKey.keyA, meta: true);
    expect(terminal.selection.hasSelection, isTrue);
    await press(tester, LogicalKeyboardKey.keyC, meta: true);
    expect(copied.single, startsWith('one'));
    await press(tester, LogicalKeyboardKey.arrowLeft, alt: true);
    expect(pty.written, '\x1bb');
    pty.writes.clear();
    await press(tester, LogicalKeyboardKey.arrowLeft, meta: true);
    expect(pty.written, '\x01');
    await press(tester, LogicalKeyboardKey.keyK, meta: true);
    await tester.pump(const Duration(milliseconds: 1));
    expect(terminal.terminal.buffer.ybase, 0);
    expect(
      terminal.terminal.buffer.lines.get(1)!.translateToString(true),
      isEmpty,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('find: Ctrl+F, then Enter / Shift+Enter, the toggles and '
      'Escape in its input; F3 and Escape from the terminal; Search '
      'Workspace', (tester) async {
    final pty = await pumpTerminal(tester);
    final state = workbench(tester);
    final terminal = shown(tester);
    pty.emitText('foo 1\r\nfoo 2\r\nfoo 3');
    await tester.pump(const Duration(milliseconds: 1));

    await press(tester, LogicalKeyboardKey.keyF, control: true);
    final find_ = terminal.find;
    expect(find_.isVisible, isTrue);
    expect(state.keyContext('terminalFindInputFocused'), isTrue);
    expect(state.keyContext('terminalFindFocused'), isTrue);
    expect(state.keyContext('terminalFocusInAny'), isFalse);
    await tester.enterText(
      find.descendant(
        of: find.byType(IdeFindWidget),
        matching: find.byType(EditableText),
      ),
      'foo',
    );
    await tester.pump(const Duration(milliseconds: 1));
    expect(find_.resultCount, 3);
    // Enter finds the match above, Shift+Enter the one below.
    final start = find_.resultIndex;
    await press(tester, LogicalKeyboardKey.enter);
    expect(find_.resultIndex, (start + 2) % 3);
    await press(tester, LogicalKeyboardKey.enter, shift: true);
    expect(find_.resultIndex, start);
    await press(tester, LogicalKeyboardKey.keyC, alt: true);
    expect(find_.caseSensitive, isTrue);

    // The user's keybinding for a toggle: its key, and its label.
    KeybindingService.instance.userEntries = const [
      KeybindingEntry(
        key: 'ctrl+alt+w',
        command: 'workbench.action.terminal.toggleFindWholeWord',
        when: 'terminalFindVisible',
      ),
    ];
    await tester.pump();
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel('Whole word (Ctrl+Alt+W)'), findsOneWidget);
    semantics.dispose();
    await press(tester, LogicalKeyboardKey.keyW, control: true, alt: true);
    expect(find_.wholeWord, isTrue);

    // Escape hides it, and the terminal has the keyboard again.
    await press(tester, LogicalKeyboardKey.escape);
    expect(find_.isVisible, isFalse);
    expect(terminal.focusNode.hasFocus, isTrue);
    // F3 in the terminal: Find Next, which shows it; Escape hides it.
    await press(tester, LogicalKeyboardKey.f3);
    expect(find_.isVisible, isTrue);
    expect(terminal.focusNode.hasFocus, isTrue);
    await press(tester, LogicalKeyboardKey.escape);
    expect(find_.isVisible, isFalse);
    expect(pty.written, isEmpty);

    // Ctrl+Shift+F with a selection: the Search view, searching for it.
    await run(tester, 'workbench.action.terminal.selectAll');
    terminal.focus();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.keyF, control: true, shift: true);
    expect(state.keyContext('searchViewletVisible'), isTrue);
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .any((field) => field.controller.text.startsWith('foo 1')),
      isTrue,
    );
    expect(pty.written, isEmpty);
  });

  testWidgets('New Terminal\'s tooltip and the menu show the keybindings', (
    tester,
  ) async {
    await pumpTerminal(tester);
    expect(find.byTooltip('New Terminal (Ctrl+Shift+`)'), findsOneWidget);
    KeybindingService.instance.userEntries = const [
      KeybindingEntry(
        key: 'ctrl+alt+n',
        command: 'workbench.action.terminal.new',
      ),
    ];
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('New Terminal (Ctrl+Alt+N)'), findsOneWidget);
    await run(tester, 'workbench.action.terminal.killAll');
    expect(find.byType(TerminalView), findsNothing);
  });
}
