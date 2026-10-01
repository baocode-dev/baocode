// The chat window's keys as keybindings (see keybindings/chat_keybindings.dart):
// its agents and panes, from anywhere in the window.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/keybindings/chat_keybindings.dart';
import 'package:baocode/keybindings/keybinding_entry.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/main.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/workspace/chat_grid.dart';
import 'package:baocode/workspace/window_header/header_menu_bar.dart';
import 'package:baocode/workspace/workspace.dart';

const _window = MethodChannel('baocode/window');

Future<Workspace> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // What the window is told (the Windows header's controls) goes nowhere.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _window,
    (call) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _window,
      null,
    ),
  );
  final workspace = Workspace.mock();
  await tester.pumpWidget(BaoCodeApp(workspace: workspace));
  await tester.pump();
  return workspace;
}

/// Presses [key] with the modifiers given.
Future<void> press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool alt = false,
  bool shift = false,
  bool meta = false,
  bool pump = true,
}) async {
  final modifiers = [
    if (control) LogicalKeyboardKey.controlLeft,
    if (alt) LogicalKeyboardKey.altLeft,
    if (shift) LogicalKeyboardKey.shiftLeft,
    if (meta) LogicalKeyboardKey.metaLeft,
  ];
  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  await tester.sendKeyEvent(key);
  for (final modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
  if (pump) {
    await tester.pump();
    await tester.pump();
  }
}

/// The agents as the sidebar lists them (by project, the most recent
/// first, pinned ones on top).
List<AgentThread> sidebarOrder(Workspace workspace) {
  final threads = [
    for (final thread in workspace.threads)
      if (!thread.archived) thread,
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return [
    ...threads.where((thread) => thread.pinned),
    for (final project in workspace.projects)
      ...threads.where((thread) => !thread.pinned && thread.project == project),
  ];
}

/// Whether the focus is in the input of the agent [thread].
bool inputFocused(WidgetTester tester, AgentThread thread) {
  final screen = find.byWidgetPredicate(
    (widget) =>
        widget is ChatScreen && identical(widget.session, thread.session),
  );
  final editor = find.descendant(
    of: screen,
    matching: find.byType(QuillEditor),
  );
  if (editor.evaluate().isEmpty) return false;
  return tester.widget<QuillEditor>(editor.first).focusNode.hasFocus;
}

void main() {
  setUp(() => KeybindingService.instance = KeybindingService());
  tearDown(() => KeybindingService.instance = KeybindingService());

  testWidgets('Ctrl+N starts an agent, its input focused', (tester) async {
    final workspace = await pumpApp(tester);
    final before = workspace.current;
    await press(tester, LogicalKeyboardKey.keyN, control: true);
    final agent = workspace.current!;
    expect(agent, isNot(same(before)));
    expect(agent.session.itemCount, 0);
    expect(inputFocused(tester, agent), isTrue);
  });

  testWidgets('⌘N on macOS', (tester) async {
    final workspace = await pumpApp(tester);
    final before = workspace.current;
    await press(tester, LogicalKeyboardKey.keyN, meta: true);
    expect(workspace.current, isNot(same(before)));
    expect(workspace.current!.session.itemCount, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Ctrl+Tab and Ctrl+Shift+Tab go through the agents as the '
      'sidebar lists them; Alt+2 opens the second', (tester) async {
    final workspace = await pumpApp(tester);
    final order = sidebarOrder(workspace);
    final at = order.indexOf(workspace.current!);
    expect(at, isNonNegative);

    await press(tester, LogicalKeyboardKey.tab, control: true);
    final next = order[(at + 1) % order.length];
    expect(workspace.current, same(next));
    expect(inputFocused(tester, next), isTrue);

    await press(tester, LogicalKeyboardKey.tab, control: true, shift: true);
    expect(workspace.current, same(order[at]));

    await press(tester, LogicalKeyboardKey.digit2, alt: true);
    expect(workspace.current, same(order[1]));
    await press(tester, LogicalKeyboardKey.pageDown, control: true);
    expect(workspace.current, same(order[2]));
  });

  testWidgets('on macOS, ⌃1 opens the first agent and ⇧⌘[ the one before', (
    tester,
  ) async {
    final workspace = await pumpApp(tester);
    final order = sidebarOrder(workspace);
    await press(tester, LogicalKeyboardKey.digit2, control: true);
    expect(workspace.current, same(order[1]));
    await press(
      tester,
      LogicalKeyboardKey.bracketLeft,
      shift: true,
      meta: true,
    );
    expect(workspace.current, same(order[0]));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Ctrl+1 and Ctrl+2 focus the panes, Ctrl+W closes the one '
      'focused', (tester) async {
    final workspace = await pumpApp(tester);
    final first = workspace.selected;
    final other = sidebarOrder(workspace)
        .firstWhere((thread) => !identical(thread, first));
    workspace.openBeside(other, first, PaneSide.right);
    await tester.pump();
    await tester.pump();
    expect(workspace.grid.panes, [first, other]);

    await press(tester, LogicalKeyboardKey.digit1, control: true);
    expect(workspace.current, same(first));
    expect(inputFocused(tester, first), isTrue);
    await press(tester, LogicalKeyboardKey.digit2, control: true);
    expect(workspace.current, same(other));
    expect(inputFocused(tester, other), isTrue);

    await press(tester, LogicalKeyboardKey.keyW, control: true);
    expect(workspace.grid.panes, [first]);
    expect(workspace.current, same(first));
    // The last pane stays.
    await press(tester, LogicalKeyboardKey.keyW, control: true);
    expect(workspace.grid.panes, [first]);
  });

  testWidgets('Ctrl+Shift+F shows the sidebar and focuses its search; '
      'Ctrl+L goes back to the chat', (tester) async {
    final workspace = await pumpApp(tester);
    final search = find.descendant(
      of: find.byType(Sidebar),
      matching: find.byType(TextField),
    );
    FocusNode searchFocus() => tester.widget<TextField>(search).focusNode!;
    // Hidden first.
    await press(tester, LogicalKeyboardKey.keyB, control: true);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Show sidebar'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.keyF, control: true, shift: true);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Show sidebar'), findsNothing);
    expect(searchFocus().hasFocus, isTrue);

    await press(tester, LogicalKeyboardKey.keyL, control: true);
    expect(searchFocus().hasFocus, isFalse);
    expect(inputFocused(tester, workspace.selected), isTrue);
  });

  testWidgets('Ctrl+Alt+I opens the agent in Fast Ide', (tester) async {
    final workspace = await pumpApp(tester);
    await press(
      tester,
      LogicalKeyboardKey.keyI,
      control: true,
      alt: true,
      pump: false,
    );
    expect(workspace.layout, WorkspaceLayout.ide);
    // Not built: the chat's keys are what is tested.
    workspace.layout = WorkspaceLayout.chat;
    await tester.pump();
  });

  testWidgets('a dialog over the window keeps its keys', (tester) async {
    final workspace = await pumpApp(tester);
    final before = workspace.current;
    final sent = before!.session.itemCount;
    unawaitedDialog(tester);
    await tester.pump();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.keyN, control: true);
    await press(tester, LogicalKeyboardKey.tab, control: true);
    await press(tester, LogicalKeyboardKey.enter);
    expect(workspace.current, same(before));
    expect(before.session.itemCount, sent);
  });

  testWidgets('rebound in keybindings.json, New Agent takes its new keys', (
    tester,
  ) async {
    KeybindingService.instance.userEntries = const [
      KeybindingEntry(
        key: 'ctrl+alt+n',
        command: ChatCommandIds.newChat,
        when: 'chatMode',
      ),
      KeybindingEntry(key: 'ctrl+n', command: '-${ChatCommandIds.newChat}'),
    ];
    final workspace = await pumpApp(tester);
    final before = workspace.current;
    await press(tester, LogicalKeyboardKey.keyN, control: true);
    expect(workspace.current, same(before));
    await press(tester, LogicalKeyboardKey.keyN, control: true, alt: true);
    expect(workspace.current, isNot(same(before)));
  });

  testWidgets('the Windows header\'s menus show the keys in effect', (
    tester,
  ) async {
    final workspace = await pumpApp(tester);
    Future<void> openMenu(String name) async {
      await tester.tap(find.text(name));
      await tester.pump();
    }

    Future<void> closeMenu() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
    }

    await openMenu('File');
    expect(find.byType(HeaderMenuBar), findsOneWidget);
    expect(find.text('New Agent'), findsWidgets);
    expect(find.text('Ctrl+N'), findsOneWidget);
    await closeMenu();
    await openMenu('View');
    expect(find.text('Search Agents'), findsOneWidget);
    expect(find.text('Ctrl+Shift+F'), findsOneWidget);
    expect(find.text('Open in Fast Ide'), findsOneWidget);
    expect(find.text('Ctrl+Alt+I'), findsOneWidget);
    await closeMenu();

    KeybindingService.instance.userEntries = const [
      KeybindingEntry(
        key: 'ctrl+alt+n',
        command: ChatCommandIds.newChat,
        when: 'chatMode',
      ),
    ];
    await tester.pump();
    await openMenu('File');
    expect(find.text('Ctrl+Alt+N'), findsOneWidget);
    expect(find.text('Ctrl+N'), findsNothing);
    // Chosen, it runs (the sidebar's button is the other New Agent).
    final before = workspace.current;
    await tester.tap(find.text('New Agent').last, warnIfMissed: false);
    await tester.pump();
    await tester.pump();
    expect(workspace.current, isNot(same(before)));
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}

/// A dialog with a text field over the window, left open.
void unawaitedDialog(WidgetTester tester) {
  showDialog<void>(
    context: tester.element(find.byType(ChatScreen).first),
    builder: (context) => const Dialog(child: TextField(autofocus: true)),
  );
}
