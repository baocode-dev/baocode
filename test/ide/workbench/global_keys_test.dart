import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:baocode/keybindings/keybinding_service.dart';

import '../git/fake_git.dart';
import '../terminal/fake_pty.dart';
import 'fake_files.dart';

/// The workbench's keybindings hold wherever the focus is in it, as
/// upstream's keybinding service hears every key of the window.
void main() {
  setUp(() => KeybindingService.instance = KeybindingService());
  tearDown(() => KeybindingService.instance = KeybindingService());

  IdeWorkbenchState workbench(WidgetTester tester) =>
      tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

  bool mac() => defaultTargetPlatform == TargetPlatform.macOS;

  /// Presses [key] with the platform's primary modifier (⌘, Ctrl).
  Future<void> primary(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    final modifier = mac()
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
    await tester.pump();
  }

  String? quickText(WidgetTester tester) {
    final input = find.descendant(
      of: find.byType(IdeQuickInput),
      matching: find.byType(TextField),
    );
    if (input.evaluate().isEmpty) return null;
    return tester.widget<TextField>(input).controller!.text;
  }

  late FakeGit git;

  Future<void> pump(WidgetTester tester) async {
    git = FakeGit(testRoot)..status = '## main...origin/main\x00 M a.dart\x00';
    await pumpWorkbench(
      tester,
      const {'a.dart': 'void main() {}\n', 'b.dart': 'b\n'},
      open: ['a.dart'],
      nativeEditor: true,
      git: git.repository(),
      startPty: FakePty.starter([]),
      chat: ChatScreen(session: ChatSession(historyCount: 2)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> run(WidgetTester tester, String id) async {
    workbench(tester).commandsById[id]!.invoke();
    await tester.pumpAndSettle();
  }

  /// Where the focus is put, and the context key that says it is there.
  final places = <String, (Future<void> Function(WidgetTester), String)>{
    'the editor': (
      (tester) => run(tester, 'workbench.action.focusActiveEditorGroup'),
      'editorTextFocus',
    ),
    "the editor's find": (
      (tester) async {
        await run(tester, 'workbench.action.focusActiveEditorGroup');
        await primary(tester, LogicalKeyboardKey.keyF);
        await tester.pumpAndSettle();
      },
      'findInputFocussed',
    ),
    'the explorer': (
      (tester) async {
        await tester.tap(
          find
              .descendant(
                of: find.byType(IdeWorkbench),
                matching: find.text('b.dart'),
              )
              .first,
        );
        await tester.pumpAndSettle();
      },
      'filesExplorerFocus',
    ),
    'the search input': (
      (tester) => run(tester, 'workbench.action.findInFiles'),
      'searchInputBoxFocus',
    ),
    'the commit message': (
      (tester) async {
        await run(tester, 'workbench.view.scm');
        await tester.tap(find.byType(TextField).first);
        await tester.pumpAndSettle();
      },
      'scmRepository',
    ),
    'the terminal': (
      (tester) async {
        await run(tester, 'workbench.action.terminal.toggleTerminal');
        await tester.pump(const Duration(milliseconds: 1));
      },
      'terminalFocus',
    ),
    "the terminal's find": (
      (tester) async {
        await run(tester, 'workbench.action.terminal.toggleTerminal');
        await tester.pump(const Duration(milliseconds: 1));
        await run(tester, 'workbench.action.terminal.focusFind');
      },
      'terminalFindInputFocused',
    ),
    "the chat's input": (
      (tester) async {
        await tester.tap(find.byType(QuillEditor));
        await tester.pumpAndSettle();
      },
      'auxiliaryBarFocus',
    ),
    "the chat's history": (
      (tester) async {
        await tester.tap(
          find
              .descendant(
                of: find.byType(ChatHistoryView),
                matching: find.byType(RichText),
              )
              .first,
        );
        await tester.pumpAndSettle();
      },
      'auxiliaryBarFocus',
    ),
    'no editor': (
      (tester) async {
        await run(tester, 'workbench.action.closeAllEditors');
        await tester.tapAt(
          tester.getCenter(find.byType(IdeWorkbench)) + const Offset(-100, 0),
        );
        await tester.pumpAndSettle();
      },
      'ideMode',
    ),
    'nothing': (
      (tester) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
      },
      'ideMode',
    ),
  };

  /// A global key, and what says it ran: a check made before it is
  /// pressed, true after.
  final keys =
      <
        String,
        (
          LogicalKeyboardKey,
          bool,
          bool Function() Function(WidgetTester tester),
        )
      >{
        'Show All Commands': (
          LogicalKeyboardKey.keyP,
          true,
          (tester) =>
              () => quickText(tester) == '>',
        ),
        'Go to File': (
          LogicalKeyboardKey.keyP,
          false,
          (tester) =>
              () => quickText(tester) == '',
        ),
        'Toggle Primary Side Bar': (
          LogicalKeyboardKey.keyB,
          false,
          (tester) {
            final before = workbench(tester).keyContext('sideBarVisible');
            return () =>
                workbench(tester).keyContext('sideBarVisible') != before;
          },
        ),
        'Toggle Chat': (
          LogicalKeyboardKey.keyJ,
          false,
          (tester) {
            final before = workbench(tester).keyContext('auxiliaryBarVisible');
            return () =>
                workbench(tester).keyContext('auxiliaryBarVisible') != before;
          },
        ),
        // The user's ⌘K ⌘Y (Ctrl+K Ctrl+Y): Show All Commands.
        'a chord': (
          LogicalKeyboardKey.keyK,
          false,
          (tester) =>
              () => find
                  .textContaining('Waiting for second key of chord')
                  .evaluate()
                  .isNotEmpty,
        ),
      };

  for (final MapEntry(key: place, value: (focus, focused)) in places.entries) {
    for (final MapEntry(key: name, value: (key, shift, check))
        in keys.entries) {
      testWidgets(
        '$name from $place',
        (tester) async {
          // A terminal's shell has Ctrl+B and Ctrl+J off macOS (upstream's
          // commandsToSkipShell lists neither).
          if (place.startsWith('the terminal') &&
              !mac() &&
              (key == LogicalKeyboardKey.keyB ||
                  key == LogicalKeyboardKey.keyJ)) {
            return;
          }
          KeybindingService.instance.userEntries = [
            KeybindingEntry(
              key: mac() ? 'cmd+k cmd+y' : 'ctrl+k ctrl+y',
              command: 'workbench.action.showCommands',
            ),
          ];
          await pump(tester);
          await focus(tester);
          expect(
            workbench(tester).keyContext(focused),
            isTrue,
            reason: 'focus',
          );
          final ran = check(tester);
          await primary(tester, key, shift: shift);
          expect(ran(), isTrue);
          if (key == LogicalKeyboardKey.keyK) {
            await primary(tester, LogicalKeyboardKey.keyY);
            expect(quickText(tester), '>');
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        },
        variant: TargetPlatformVariant({
          TargetPlatform.macOS,
          TargetPlatform.linux,
        }),
      );
    }
  }

  testWidgets("the chat's input is a text input to the workbench's keys", (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byType(QuillEditor));
    await tester.pumpAndSettle();
    final state = workbench(tester);
    expect(state.keyContext('inputFocus'), isTrue);
    expect(state.keyContext('textInputFocus'), isTrue);
    expect(state.keyContext('editorTextFocus'), isFalse);
  });

  testWidgets('an input method composing text keeps its keys', (tester) async {
    KeybindingService.instance.userEntries = const [
      KeybindingEntry(
        key: 'enter',
        command: 'workbench.action.showCommands',
        when: 'searchInputBoxFocus',
      ),
    ];
    await pump(tester);
    await run(tester, 'workbench.action.findInFiles');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(quickText(tester), isNull);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '你',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(quickText(tester), '>');
  });

  testWidgets('a dialog over the workbench keeps its keys', (tester) async {
    await pump(tester);
    unawaited(
      showDialog<void>(
        context: tester.element(find.byType(IdeWorkbench)),
        builder: (context) => const Dialog(child: TextField(autofocus: true)),
      ),
    );
    await tester.pumpAndSettle();
    await primary(tester, LogicalKeyboardKey.keyP, shift: true);
    expect(quickText(tester), isNull);
    // With the focus on the dialog's route, not in a widget of it.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await primary(tester, LogicalKeyboardKey.keyP, shift: true);
    expect(quickText(tester), isNull);
  });
}
