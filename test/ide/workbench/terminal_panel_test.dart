import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/terminal/pty.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/ide/terminal/terminal_tabs.dart';
import 'package:baocode/ide/terminal/terminal_view.dart';
import 'package:baocode/ide/terminal/terminal_widget.dart';
import 'package:baocode/theme/codicons.dart';

import '../terminal/fake_pty.dart';
import 'fake_files.dart';

final _panel = find.byKey(const ValueKey('ide-panel'));

Finder _inPanel(Finder finder) => find.descendant(of: _panel, matching: finder);

Finder _inTabs(Finder finder) =>
    find.descendant(of: find.byType(TerminalTabs), matching: finder);

double _panelHeight(WidgetTester tester) => tester.getSize(_panel).height;

/// The terminal the panel shows.
TerminalInstance _shown(WidgetTester tester) =>
    tester.widget<TerminalView>(find.byType(TerminalView)).instance;

/// What a terminal's screen shows: its lines, wrapped ones joined.
String _screen(TerminalInstance instance) {
  final lines = instance.terminal.buffer.lines;
  final text = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    final line = lines.get(i)!;
    if (i > 0 && !line.isWrapped) text.write('\n');
    text.write(line.translateToString(true));
  }
  return text.toString();
}

IdeWorkbenchState _workbench(WidgetTester tester) =>
    tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

Future<void> _toggleTerminal(WidgetTester tester) =>
    chord(tester, LogicalKeyboardKey.backquote, control: true);

Future<void> _newTerminal(WidgetTester tester) =>
    chord(tester, LogicalKeyboardKey.backquote, control: true, shift: true);

/// Lets a menu close and run what was chosen, and what that builds.
Future<void> _afterMenu(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();
  await tester.pump();
}

/// Types [text] into the rename input and presses Enter.
Future<void> _rename(WidgetTester tester, String text) async {
  final field = find.descendant(
    of: find.byType(TerminalRenameInput),
    matching: find.byType(TextField),
  );
  await tester.enterText(field, text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('⌃` opens the panel on TERMINAL with a terminal of its own, '
      'focused; hidden, the terminal keeps running', (tester) async {
    final ptys = <FakePty>[];
    await pumpWorkbench(tester, {
      'a.txt': 'a',
    }, startPty: FakePty.starter(ptys));
    expect(ptys, isEmpty);

    await _toggleTerminal(tester);
    expect(_panelHeight(tester), greaterThan(0));
    expect(_inPanel(find.text('TERMINAL')), findsOneWidget);
    expect(ptys, hasLength(1));
    expect(ptys.single.launch!.workingDirectory, testRoot);
    final terminal = _shown(tester);
    expect(terminal.focusNode.hasFocus, isTrue);
    // One terminal: its tab and Kill are in the title, next to New Terminal.
    expect(_inPanel(find.text('zsh')), findsOneWidget);
    expect(_inPanel(find.byIcon(Codicons.add)), findsOneWidget);
    expect(_inPanel(find.byIcon(Codicons.trash)), findsOneWidget);
    expect(find.byType(TerminalTabs), findsNothing);

    await _toggleTerminal(tester);
    expect(_panelHeight(tester), 0);
    expect(ptys.single.kills, isEmpty);
    expect(terminal.focusNode.hasFocus, isFalse);
    // The keyboard is back with the workbench: ⌃` shows the same one.
    await _toggleTerminal(tester);
    expect(_panelHeight(tester), greaterThan(0));
    expect(ptys, hasLength(1));
    expect(_shown(tester), terminal);

    // Another tab leaves it running; back on TERMINAL, it has the keyboard.
    await tester.tap(_inPanel(find.text('PROBLEMS')));
    await tester.pump();
    await tester.pump();
    expect(find.byType(TerminalView), findsNothing);
    expect(terminal.focusNode.hasFocus, isFalse);
    await tester.tap(_inPanel(find.text('TERMINAL')));
    await tester.pump();
    await tester.pump();
    expect(terminal.focusNode.hasFocus, isTrue);
    expect(ptys.single.kills, isEmpty);

    // Gone with the workbench.
    await tester.pumpWidget(const SizedBox());
    expect(ptys.single.kills, [PtySignal.hangup]);
  });

  testWidgets('+ adds a terminal and shows the tabs; a tab\'s Kill and the '
      'title\'s remove them, the last one hiding the panel', (tester) async {
    final ptys = <FakePty>[];
    await pumpWorkbench(tester, {
      'a.txt': 'a',
    }, startPty: FakePty.starter(ptys));
    await _toggleTerminal(tester);
    await tester.tap(_inPanel(find.byIcon(Codicons.add)));
    await tester.pump();
    await tester.pump();
    expect(ptys, hasLength(2));
    expect(_inTabs(find.text('zsh')), findsNWidgets(2));
    expect(_shown(tester).id, 2);
    expect(_shown(tester).focusNode.hasFocus, isTrue);
    // With tabs, the title has only New Terminal.
    expect(_inPanel(find.byIcon(Codicons.trash)), findsNothing);

    // A click selects a tab; selected, with the list focused, it offers
    // Kill.
    await tester.tap(_inTabs(find.text('zsh')).first);
    await tester.pump();
    expect(_shown(tester).id, 1);
    final kill = _inTabs(find.byIcon(Codicons.trash));
    expect(kill, findsOneWidget);
    await tester.tap(kill);
    await tester.pump();
    expect(ptys[0].kills, [PtySignal.hangup]);
    expect(find.byType(TerminalTabs), findsNothing);
    expect(_shown(tester).id, 2);

    await tester.tap(_inPanel(find.byIcon(Codicons.trash)));
    await tester.pump();
    await tester.pump();
    expect(ptys[1].kills, [PtySignal.hangup]);
    expect(_panelHeight(tester), 0);

    // Shown again, the panel makes a terminal again.
    await _toggleTerminal(tester);
    expect(ptys, hasLength(3));
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('a terminal is renamed in place: from the palette, F2 or its '
      'menu; empty, the name goes back', (tester) async {
    await pumpWorkbench(tester, {'a.txt': 'a'});
    await _toggleTerminal(tester);

    // With one terminal, Rename... edits its tab in the title.
    _workbench(tester).commands
        .firstWhere((c) => c.id == 'workbench.action.terminal.rename')
        .run();
    await tester.pump();
    await tester.pump();
    expect(_inPanel(find.byType(TerminalRenameInput)), findsOneWidget);
    await _rename(tester, 'server');
    expect(_inPanel(find.text('server')), findsOneWidget);
    expect(find.byType(TerminalRenameInput), findsNothing);

    await _newTerminal(tester);
    // A click selects a tab, a second soon after focuses its terminal, as
    // VS Code's default `terminal.integrated.tabs.focusMode`.
    await tester.tap(_inTabs(find.text('server')));
    await tester.pump();
    expect(_shown(tester).title, 'server');
    expect(_shown(tester).focusNode.hasFocus, isFalse);
    await tester.tap(_inTabs(find.text('server')));
    await tester.pump();
    await tester.pump();
    expect(find.byType(TerminalRenameInput), findsNothing);
    expect(_shown(tester).focusNode.hasFocus, isTrue);

    // A click gives the list the keyboard, and F2 renames.
    await tester.tap(_inTabs(find.text('server')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    await tester.pump();
    expect(_inTabs(find.byType(TerminalRenameInput)), findsOneWidget);
    // Escape keeps the name, and gives the list the keyboard back.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(_inTabs(find.text('server')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byType(TerminalRenameInput),
        matching: find.byType(TextField),
      ),
      '',
    );
    await tester.pump();
    expect(
      find.text('Providing no name will reset it to the default value'),
      findsOneWidget,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
    expect(_inTabs(find.text('zsh')), findsNWidgets(2));

    await tester.tap(_inTabs(find.text('zsh')).last, buttons: kSecondaryButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Kill Terminal'), findsOneWidget);
    await tester.tap(find.text('Rename...'));
    await _afterMenu(tester);
    await _rename(tester, 'watch');
    expect(_inTabs(find.text('watch')), findsOneWidget);
    expect(_shown(tester).title, 'watch');
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('a process that exits with 0 closes its terminal; another '
      'code leaves it, saying why, marked in its tab', (tester) async {
    final ptys = <FakePty>[];
    await pumpWorkbench(tester, {
      'a.txt': 'a',
    }, startPty: FakePty.starter(ptys));
    await _toggleTerminal(tester);
    await _newTerminal(tester);
    expect(_inTabs(find.text('zsh')), findsNWidgets(2));

    ptys[1].exit(0);
    await tester.pump();
    await tester.pump();
    expect(find.byType(TerminalTabs), findsNothing);
    expect(_shown(tester).id, 1);

    await _newTerminal(tester);
    ptys[2].exit(1);
    await tester.pump();
    await tester.pump();
    expect(_shown(tester).id, 3);
    // Written into the terminal, as VS Code's `formatMessageForTerminal`.
    // (Parsed on timers, in slices of 12ms.)
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      _screen(_shown(tester)),
      contains(
        ' *  The terminal process "/bin/zsh \'-l\'" terminated with exit '
        'code: 1.',
      ),
    );
    expect(_inTabs(find.byIcon(Codicons.error)), findsOneWidget);
    expect(ptys[2].kills, isEmpty);

    // The last one's clean exit hides the panel.
    await tester.tap(_inTabs(find.text('zsh')).last);
    await tester.pump();
    await tester.tap(_inTabs(find.byIcon(Codicons.trash)));
    await tester.pump();
    ptys[0].exit(0);
    await tester.pump();
    await tester.pump();
    expect(_panelHeight(tester), 0);
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('⌃⇧` makes a terminal and shows it; while one has focus, '
      'Ctrl+PageDown and Ctrl+PageUp go round them', (tester) async {
    final ptys = <FakePty>[];
    await pumpWorkbench(tester, {
      'a.txt': 'a',
    }, startPty: FakePty.starter(ptys));
    await _newTerminal(tester);
    expect(_panelHeight(tester), greaterThan(0));
    expect(ptys, hasLength(1));
    await _newTerminal(tester);
    await _newTerminal(tester);
    expect(ptys, hasLength(3));
    expect(_shown(tester).id, 3);

    await chord(tester, LogicalKeyboardKey.pageDown, control: true);
    expect(_shown(tester).id, 1);
    expect(_shown(tester).focusNode.hasFocus, isTrue);
    await chord(tester, LogicalKeyboardKey.pageUp, control: true);
    expect(_shown(tester).id, 3);
    expect(_shown(tester).focusNode.hasFocus, isTrue);

    final commands = {
      for (final command in _workbench(tester).commands)
        if (command.id.startsWith('workbench.action.terminal.'))
          command.id: command,
    };
    expect(
      commands['workbench.action.terminal.focusNext']!.shortcutLabel(),
      'Ctrl+PageDown',
    );
    commands['workbench.action.terminal.focusPrevious']!.run();
    await tester.pump();
    await tester.pump();
    expect(_shown(tester).id, 2);
    expect(_shown(tester).focusNode.hasFocus, isTrue);
    // Killed with the keyboard, the next one takes it.
    commands['workbench.action.terminal.kill']!.run();
    await tester.pump();
    await tester.pump();
    expect(ptys[1].kills, [PtySignal.hangup]);
    expect(_shown(tester).id, 3);
    expect(_shown(tester).focusNode.hasFocus, isTrue);
  });

  testWidgets('where terminals cannot run there is no TERMINAL tab, and no '
      'terminal command', (tester) async {
    final ptys = <FakePty>[];
    await pumpWorkbench(
      tester,
      {'a.txt': 'a'},
      startPty: FakePty.starter(ptys),
      terminals: false,
    );
    final commands = [
      for (final command in _workbench(tester).commands)
        if (command.id.startsWith('workbench.action.terminal.')) command,
    ];
    expect(commands, isNotEmpty);
    expect(commands.where((command) => command.enabled), isEmpty);

    await _toggleTerminal(tester);
    await _newTerminal(tester);
    expect(_panelHeight(tester), 0);
    expect(ptys, isEmpty);

    await chord(tester, LogicalKeyboardKey.keyM, control: true, shift: true);
    expect(_panelHeight(tester), greaterThan(0));
    expect(_inPanel(find.text('PROBLEMS')), findsOneWidget);
    expect(_inPanel(find.text('TERMINAL')), findsNothing);
  });

  testWidgets('a Ctrl-click on a path with a line and column in a terminal '
      'opens the file there in the editor', (tester) async {
    final ptys = <FakePty>[];
    final workspace = await pumpWorkbench(tester, {
      'lib/a.dart': 'one\ntwo words\nthree',
    }, startPty: FakePty.starter(ptys));
    await _toggleTerminal(tester);
    ptys.single.emitText('lib/a.dart:2:3');
    await tester.pump(const Duration(milliseconds: 1));

    final terminal = find.byType(TerminalWidget);
    final controller = tester.widget<TerminalWidget>(terminal).controller!;
    final at =
        tester.getTopLeft(terminal) +
        controller.gridOrigin +
        Offset(
          3.5 * controller.cellSize.width,
          0.5 * controller.cellSize.height,
        );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: at);
    await mouse.moveTo(at + const Offset(1, 0));
    await tester.pump();
    await tester.pump();
    expect(controller.linkUnderline, isNotNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await mouse.down(at);
    await mouse.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(workspace.active?.path, inRoot('lib/a.dart'));
    expect(find.text('Ln 2, Col 3'), findsOneWidget);
    await tester.pump(kDoubleTapTimeout);
  });
}
