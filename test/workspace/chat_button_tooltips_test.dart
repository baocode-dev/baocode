// The chat window's buttons title themselves with what they do and the key
// that does the same, as upstream's action bar items do (`New Agent (⌘N)`),
// following the keybindings as they change; the hints under a prompt's
// options and in the composer show the keys the keybindings have.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/panels/interaction_panel.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/keybindings/chat_keybindings.dart';
import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/main.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/workspace/back_to_chat_button.dart';
import 'package:baocode/workspace/chat_grid.dart';
import 'package:baocode/workspace/editor_launcher.dart';
import 'package:baocode/workspace/window_header/window_header.dart';
import 'package:baocode/workspace/workspace.dart';

const _window = MethodChannel('baocode/window');

final _mac = TargetPlatformVariant.only(TargetPlatform.macOS);

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

/// The texts of the workbench hovers built (under [of], if given).
Set<String> hovers(WidgetTester tester, [Finder? of]) => {
  for (final hover in tester.widgetList<IdeHover>(
    of == null
        ? find.byType(IdeHover)
        : find.descendant(of: of, matching: find.byType(IdeHover)),
  ))
    ?hover.message,
};

void main() {
  setUp(() => KeybindingService.instance = KeybindingService());
  tearDown(() => KeybindingService.instance = KeybindingService());

  group('the chat window', () {
    testWidgets('on macOS, its buttons show what they do and their keys', (
      tester,
    ) async {
      final workspace = await pumpApp(tester);
      workspace.preferredEditor = Editor.fastIde;
      await tester.pump();
      expect(
        hovers(tester),
        containsAll([
          // The sidebar's.
          'Hide sidebar (⌘B)',
          'New Agent (⌘N)',
          'Search Agents (⇧⌘F)',
          'Settings (⌘,)',
          // The title bar's.
          'Open in Fast Ide (⌃⌘I)',
          // The composer's.
          'Set Mode (⌘.)',
          'Pick Model (⌥⌘.)',
          'Send (Enter)',
          // Toggle Context Panel has no key by default.
          'Context usage',
        ]),
      );
      // An app has no key: only the Fast Ide is opened by one.
      workspace.preferredEditor = Editor.vscode;
      await tester.pump();
      expect(hovers(tester), contains('Open in VS Code'));
    }, variant: _mac);

    testWidgets('elsewhere theirs; the sidebar hidden, its toggle in the '
        'pane; a pane\'s close with Close Pane\'s', (tester) async {
      final workspace = await pumpApp(tester);
      expect(
        hovers(tester),
        containsAll(['Hide sidebar (Ctrl+B)', 'New Agent (Ctrl+N)']),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(hovers(tester), contains('Show sidebar (Ctrl+B)'));

      final first = workspace.selected;
      final other = workspace.threads.firstWhere(
        (thread) => !identical(thread, first) && !thread.archived,
      );
      workspace.openBeside(other, first, PaneSide.right);
      await tester.pump();
      await tester.pump();
      expect(
        hovers(tester).where((message) => message == 'Close pane (Ctrl+W)'),
        isNotEmpty,
      );
    });

    testWidgets('rebound in keybindings.json, they show the new keys at '
        'once; unbound, the title alone', (tester) async {
      await pumpApp(tester);
      expect(
        hovers(tester),
        containsAll(['New Agent (⌘N)', 'Hide sidebar (⌘B)']),
      );

      KeybindingService.instance.userEntries = const [
        KeybindingEntry(
          key: 'ctrl+alt+n',
          mac: 'alt+cmd+n',
          command: ChatCommandIds.newChat,
          when: 'chatMode',
        ),
        KeybindingEntry(command: '-workbench.action.toggleSidebarVisibility'),
      ];
      // The window builds again.
      await tester.pump();
      final shown = hovers(tester);
      expect(shown, containsAll(['New Agent (⌥⌘N)', 'Hide sidebar']));
      expect(shown, isNot(contains('New Agent (⌘N)')));
      expect(shown, isNot(contains('Hide sidebar (⌘B)')));
    }, variant: _mac);

    testWidgets('on Windows, the header\'s sidebar toggle; over the IDE, its '
        'Back to Chat, button and menu item, with the IDE\'s keys', (
      tester,
    ) async {
      final workspace = await pumpApp(tester);
      final header = find.byType(WindowHeader);
      expect(hovers(tester, header), contains('Hide sidebar (Ctrl+B)'));

      workspace.layout = WorkspaceLayout.ide;
      await tester.pump();
      await tester.pump();
      final back = find.ancestor(
        of: find.descendant(
          of: header,
          matching: find.byType(BackToChatButton),
        ),
        matching: find.byType(IdeHover),
      );
      expect(tester.widgetList<IdeHover>(back).map((hover) => hover.message), [
        'Back to chat (Ctrl+Alt+I)',
      ]);
      await tester.tap(
        find.descendant(of: header, matching: find.text('View')),
      );
      await tester.pump();
      expect(find.text('Ctrl+Alt+I'), findsOneWidget);
      // Not built further: the header is what is tested.
      workspace.layout = WorkspaceLayout.chat;
      await tester.pump();
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });

  group('a prompt\'s options', () {
    const question = QuestionRequest(
      id: 'q',
      title: 'Question',
      questions: [
        Question(
          prompt: 'Which one?',
          options: [QuestionOption('Alpha'), QuestionOption('Beta')],
        ),
      ],
    );
    const approval = ApprovalRequest(
      id: 'a',
      title: 'Run the tests?',
      toolName: 'Bash',
    );

    Future<void> pumpPanel(
      WidgetTester tester,
      InteractionRequest request,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: InteractionPanel(request: request, onAnswer: (_) {}),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the hint and the buttons have the keys', (tester) async {
      await pumpPanel(tester, question);
      expect(
        find.text('1-9 to choose · Enter to continue · Escape to skip'),
        findsOneWidget,
      );
      expect(hovers(tester), containsAll(['Skip (Escape)', 'Submit (Enter)']));
    });

    testWidgets('a key unbound, its hint goes', (tester) async {
      KeybindingService.instance.userEntries = const [
        KeybindingEntry(command: '-${ChatCommandIds.interactionDismiss}'),
      ];
      await pumpPanel(tester, question);
      expect(find.text('1-9 to choose · Enter to continue'), findsOneWidget);
      expect(hovers(tester), containsAll(['Skip', 'Submit (Enter)']));
    });

    testWidgets('a tool\'s: Allow Once and Deny with Accept\'s and Skip\'s '
        'keys', (tester) async {
      await pumpPanel(tester, approval);
      expect(
        hovers(tester),
        containsAll(['Allow once (⌘Enter)', 'Deny (⌥⌘Enter)']),
      );
    }, variant: _mac);
  });

  testWidgets('the suggested prompt shows the key that takes it, as the '
      'keybindings have it', (tester) async {
    final session = ChatSession(
      kernel: MockKernels.claudeCode,
      historyCount: 0,
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
        home: ChatScreen(session: session),
      ),
    );
    await tester.pump();
    session.send(const ComposerMessage(text: 'make the input grow'));
    for (var i = 0; i < 400 && session.isStreaming; i++) {
      switch (session.pendingInteraction) {
        case QuestionRequest():
          session.answer(const QuestionAnswer([], skipped: true));
        case ApprovalRequest():
          session.answer(const ApprovalAnswer(ApprovalDecision.allowOnce));
        default:
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(session.promptSuggestion, 'Run the tests');
    Finder placeholder(String text) => find.descendant(
      of: find.byType(ChatComposer),
      matching: find.text(text, findRichText: true),
    );
    expect(placeholder('Run the tests    Tab'), findsOneWidget);

    KeybindingService.instance.userEntries = const [
      KeybindingEntry(command: '-${ChatCommandIds.acceptPromptSuggestion}'),
    ];
    // As the window builds again.
    tester.element(find.byType(ChatComposer)).markNeedsBuild();
    await tester.pump();
    expect(placeholder('Run the tests    Tab'), findsNothing);
    expect(placeholder('Run the tests'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
