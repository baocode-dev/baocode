// The chat window's terminal panel, under the conversations (see
// workspace/chat_terminal.dart): its toggles, its keys, and the project
// its terminals start in.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/main.dart';
import 'package:baocode/workspace/chat_terminal.dart';
import 'package:baocode/workspace/window_header/window_header.dart';
import 'package:baocode/workspace/workspace.dart';

import '../ide/terminal/fake_pty.dart';
import '../ide/terminal/fake_terminal.dart';
import 'chat_window_keys_test.dart' show press;

const _window = MethodChannel('baocode/window');

Future<Workspace> _pumpApp(
  WidgetTester tester, {
  required TerminalBackend terminalBackend,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
  await tester.pumpWidget(
    BaoCodeApp(workspace: workspace, terminalBackend: terminalBackend),
  );
  await tester.pump();
  return workspace;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

final _mac = TargetPlatformVariant.only(TargetPlatform.macOS);
final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

Finder get _panel => find.text('TERMINAL');

/// The title bar's button (the panel's own Hide is another).
Finder get _toggle => find.byType(ChatTerminalToggle);

/// Whether the button says it hides the panel (its icon, its hover).
bool _toggleShown(WidgetTester tester) =>
    tester.widget<ChatTerminalToggle>(_toggle).shown;

ChatTerminals _terminals(WidgetTester tester) => tester
    .widget<ChatTerminalArea>(find.byType(ChatTerminalArea).first)
    .terminals;

void main() {
  testWidgets('the title bar\'s button shows the panel under the chat, a '
      'terminal started in the agent\'s project, and hides it again with '
      'the terminal still running', (tester) async {
    final ptys = <FakePty>[];
    final workspace = await _pumpApp(
      tester,
      terminalBackend: fakeTerminalBackend(ptys),
    );
    final chat = tester.state(find.byType(ChatScreen).first);
    expect(_panel, findsNothing);

    await tester.tap(_toggle);
    await _settle(tester);
    expect(_panel, findsOneWidget);
    expect(ptys, hasLength(1));
    expect(
      ptys.single.launch!.workingDirectory,
      workspace.current!.project.path,
    );
    // Below the conversation, which kept its state.
    expect(
      tester.getTopLeft(_panel).dy,
      greaterThan(tester.getCenter(find.byType(ChatScreen).first).dy),
    );
    expect(tester.state(find.byType(ChatScreen).first), same(chat));
    expect(_terminals(tester).focused, isTrue);
    expect(_toggleShown(tester), isTrue);

    await tester.tap(_toggle);
    await _settle(tester);
    expect(_panel, findsNothing);
    expect(_toggleShown(tester), isFalse);
    expect(ptys.single.kills, isEmpty);
    // Running, as closing the window or quitting asks about.
    expect(_terminals(tester).running(childProcesses: false), isTrue);
    expect(tester.state(find.byType(ChatScreen).first), same(chat));

    // Shown again, the same terminal.
    await tester.tap(_toggle);
    await _settle(tester);
    expect(_panel, findsOneWidget);
    expect(ptys, hasLength(1));
  }, variant: _mac);

  testWidgets('⌃` toggles it from the chat and from the terminal, whose '
      'shell never gets the key; other keys are the shell\'s', (tester) async {
    final ptys = <FakePty>[];
    await _pumpApp(tester, terminalBackend: fakeTerminalBackend(ptys));

    await press(tester, LogicalKeyboardKey.backquote, control: true);
    await _settle(tester);
    expect(_panel, findsOneWidget);
    expect(_terminals(tester).focused, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await press(tester, LogicalKeyboardKey.keyC, control: true);
    // The chat's keys too (Escape cancels its turn there).
    await press(tester, LogicalKeyboardKey.escape);
    expect(ptys.single.written, '\r\x03\x1b');

    final before = ptys.single.writes.length;
    await press(tester, LogicalKeyboardKey.backquote, control: true);
    await _settle(tester);
    expect(_panel, findsNothing);
    expect(ptys.single.writes, hasLength(before));
  }, variant: _mac);

  testWidgets('it is the IDE\'s Toggle Terminal: its hover names the '
      'command with the key in effect, and the keys rebound for it or for '
      'Toggle Panel Visibility toggle it', (tester) async {
    addTearDown(() => KeybindingService.instance = KeybindingService());
    final ptys = <FakePty>[];
    await _pumpApp(tester, terminalBackend: fakeTerminalBackend(ptys));
    final hover = tester.widget<IdeHover>(
      find.descendant(of: _toggle, matching: find.byType(IdeHover)),
    );
    expect(hover.message, 'Toggle Terminal (⌃`)');

    KeybindingService.instance.userEntries = const [
      KeybindingEntry(key: 'ctrl+alt+t', command: toggleTerminalCommand),
      KeybindingEntry(key: 'ctrl+alt+p', command: togglePanelCommand),
    ];
    await tester.pump();
    await press(tester, LogicalKeyboardKey.keyT, control: true, alt: true);
    await _settle(tester);
    expect(_panel, findsOneWidget);
    await press(tester, LogicalKeyboardKey.keyP, control: true, alt: true);
    await _settle(tester);
    expect(_panel, findsNothing);
  }, variant: _mac);

  testWidgets('⌃⇧` makes another terminal; the tabs list them both', (
    tester,
  ) async {
    final ptys = <FakePty>[];
    await _pumpApp(tester, terminalBackend: fakeTerminalBackend(ptys));

    await press(tester, LogicalKeyboardKey.backquote, control: true);
    await _settle(tester);
    await press(
      tester,
      LogicalKeyboardKey.backquote,
      control: true,
      shift: true,
    );
    await _settle(tester);
    expect(ptys, hasLength(2));
    expect(_terminals(tester).current!.instances, hasLength(2));
    expect(ptys.first.written, isNot(contains('`')));
  }, variant: _mac);

  testWidgets('each project has its own terminals: the panel follows the '
      'agent focused', (tester) async {
    final ptys = <FakePty>[];
    final workspace = await _pumpApp(
      tester,
      terminalBackend: fakeTerminalBackend(ptys),
    );
    final first = workspace.current!;
    await tester.tap(_toggle);
    await _settle(tester);

    final other = workspace.threads.firstWhere(
      (thread) => thread.project != first.project,
    );
    workspace.select(other);
    await _settle(tester);
    // None are made for it until asked for.
    expect(_panel, findsNothing);
    expect(ptys, hasLength(1));
    await tester.tap(_toggle);
    await _settle(tester);
    expect(_panel, findsOneWidget);
    expect(ptys, hasLength(2));
    expect(ptys.last.launch!.workingDirectory, other.project.path);

    workspace.select(first);
    await _settle(tester);
    expect(_panel, findsOneWidget);
    expect(_terminals(tester).current!.instances, hasLength(1));
    expect(ptys, hasLength(2));
  }, variant: _mac);

  testWidgets('its last terminal exited, the panel hides', (tester) async {
    final ptys = <FakePty>[];
    await _pumpApp(tester, terminalBackend: fakeTerminalBackend(ptys));
    await tester.tap(_toggle);
    await _settle(tester);
    expect(_panel, findsOneWidget);

    ptys.single.exit();
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_panel, findsNothing);
  }, variant: _mac);

  testWidgets('without terminals (the web) there is no button and no panel', (
    tester,
  ) async {
    final ptys = <FakePty>[];
    await _pumpApp(
      tester,
      terminalBackend: fakeTerminalBackend(ptys, supported: false),
    );
    expect(_toggle, findsNothing);
    await press(tester, LogicalKeyboardKey.backquote, control: true);
    await _settle(tester);
    expect(_panel, findsNothing);
    expect(ptys, isEmpty);
  }, variant: _mac);

  testWidgets('on Windows the chat\'s title bar has the button by the pin, '
      'as on macOS: no header, no menus', (tester) async {
    final ptys = <FakePty>[];
    await _pumpApp(tester, terminalBackend: fakeTerminalBackend(ptys));
    expect(find.byType(WindowHeader), findsNothing);
    final toggle = find.descendant(
      of: find.byType(ChatScreen),
      matching: _toggle,
    );
    expect(toggle, findsOneWidget);

    await tester.tap(toggle);
    await _settle(tester);
    expect(_panel, findsOneWidget);
    expect(find.text('View'), findsNothing);
  }, variant: _windows);

  test('the side panel\'s terminals are each project\'s own, apart from the '
      'panel\'s, and keep the window asking before it closes', () async {
    final started = <FakePty>[];
    final terminals = ChatTerminals(
      fakeTerminalBackend(started),
      rootOf: () => '/p',
      pathOf: (root) => '$root-host',
    );
    addTearDown(terminals.dispose);
    final side = terminals.sidePanelTerminals('/p');
    expect(terminals.sidePanelTerminals('/p'), same(side));
    expect(terminals.sidePanelTerminals('/q'), isNot(same(side)));
    expect(terminals.running(childProcesses: false), isFalse);
    side.create();
    await pumpEventQueue();
    expect(started.single.launch!.workingDirectory, '/p-host');
    expect(terminals.current, isNull);
    expect(terminals.shown, isFalse);
    expect(terminals.running(childProcesses: false), isTrue);
  });
}
