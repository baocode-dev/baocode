// The chat's keys as keybindings (see keybindings/chat_keybindings.dart):
// a chat alone, its composer and a prompt's options.

import 'package:bao_markdown/bao_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer_controller.dart';
import 'package:baocode/chat/composer/composer_picker.dart';
import 'package:baocode/chat/composer/suggestion_menu.dart';
import 'package:baocode/chat/panels/interaction_panel.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/keybindings/chat_keybindings.dart';
import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/theme/app_theme.dart';

Future<ChatSession> pumpChat(
  WidgetTester tester, {
  KernelDescriptor? kernel,
  int historyCount = 16,
}) async {
  final session = kernel == null
      ? ChatSession(historyCount: historyCount)
      : ChatSession(kernel: kernel, historyCount: historyCount);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: ChatScreen(session: session),
    ),
  );
  await tester.pump();
  return session;
}

ComposerController composer(WidgetTester tester) =>
    tester.widget<MarkdownEditor>(find.byType(MarkdownEditor)).controller
        as ComposerController;

String composerText(WidgetTester tester) => composer(tester).shownText;

/// What the composer would send: its tokens as their text.
String composerMessage(WidgetTester tester) =>
    composer(tester).plainText.trim();

/// The (mock) window's file picker answers [paths].
void pickFiles(WidgetTester tester, List<String> paths) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('baocode/window'),
    (call) async => switch (call.method) {
      'pickFiles' => [
        for (final path in paths) {'path': path, 'directory': false},
      ],
      _ => null,
    },
  );
  addTearDown(
    () => messenger.setMockMethodCallHandler(
      const MethodChannel('baocode/window'),
      null,
    ),
  );
}

/// Types [text] in place of what the composer has, the caret at its end;
/// [composing], the part an input method is still composing.
Future<void> typeText(
  WidgetTester tester,
  String text, {
  TextRange composing = TextRange.empty,
}) async {
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: composing,
    ),
  );
  await tester.pump();
}

void moveCaret(WidgetTester tester, int offset) =>
    composer(tester).selection = TextSelection.collapsed(offset: offset);

/// Presses [key] with the modifiers given.
Future<void> press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool alt = false,
  bool shift = false,
  bool meta = false,
  String? character,
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
  await tester.sendKeyEvent(key, character: character);
  for (final modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pump();
}

List<String> sentMessages(ChatSession session) => [
  for (var i = 0; i < session.itemCount; i++)
    if (session.itemAt(i) case UserMessageItem(:final text)) text,
];

/// Stops the turn running, and lets it end.
Future<void> stopTurn(WidgetTester tester, ChatSession session) async {
  session.stop();
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  setUp(() => KeybindingService.instance = KeybindingService());
  tearDown(() => KeybindingService.instance = KeybindingService());

  testWidgets('Enter sends, and Esc then cancels the turn from the input', (
    tester,
  ) async {
    final session = await pumpChat(tester);
    final before = sentMessages(session).length;
    await typeText(tester, 'hello');
    await press(tester, LogicalKeyboardKey.enter);
    expect(sentMessages(session), hasLength(before + 1));
    expect(sentMessages(session).last, 'hello');
    expect(composerText(tester), '');
    expect(session.isStreaming, isTrue);

    await press(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(seconds: 3));
    expect(session.isStreaming, isFalse);
  });

  testWidgets('Esc cancels the turn from the history too, not only the '
      'input', (tester) async {
    final session = await pumpChat(tester);
    await typeText(tester, 'hello');
    await press(tester, LogicalKeyboardKey.enter);
    expect(session.isStreaming, isTrue);

    // The focus leaves the input: the list's (Ctrl+Up, Focus Chat List).
    await press(tester, LogicalKeyboardKey.arrowUp, control: true);
    expect(
      tester
          .widget<MarkdownEditor>(find.byType(MarkdownEditor))
          .focusNode!
          .hasFocus,
      isFalse,
    );

    await press(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(seconds: 3));
    expect(session.isStreaming, isFalse);
  });

  testWidgets('bound to Ctrl+Enter in keybindings.json, Send leaves Enter '
      'to the text', (tester) async {
    KeybindingService.instance.userEntries = const [
      KeybindingEntry(
        key: 'ctrl+enter',
        command: ChatCommandIds.submit,
        when: ChatContextKeys.inChatInput,
      ),
      KeybindingEntry(key: 'enter', command: '-${ChatCommandIds.submit}'),
    ];
    final session = await pumpChat(tester);
    final before = sentMessages(session).length;
    await typeText(tester, 'two lines');
    await press(tester, LogicalKeyboardKey.enter);
    expect(sentMessages(session), hasLength(before));
    expect(session.isStreaming, isFalse);

    await press(tester, LogicalKeyboardKey.enter, control: true);
    expect(sentMessages(session), hasLength(before + 1));
    await stopTurn(tester, session);
  });

  testWidgets('while an input method composes, Enter is its own', (
    tester,
  ) async {
    final session = await pumpChat(tester);
    final before = sentMessages(session).length;
    await typeText(
      tester,
      'ni hao',
      composing: const TextRange(start: 0, end: 6),
    );
    await press(tester, LogicalKeyboardKey.enter);
    expect(sentMessages(session), hasLength(before));

    await typeText(tester, '你好');
    await press(tester, LogicalKeyboardKey.enter);
    expect(sentMessages(session).last, '你好');
    await stopTurn(tester, session);
  });

  testWidgets('with the / menu open, its keys win: ↓ moves, Enter picks, '
      'Esc closes it', (tester) async {
    final session = await pumpChat(tester);
    final before = sentMessages(session).length;
    await typeText(tester, '/');
    SuggestionMenu menu() => tester.widget(find.byType(SuggestionMenu));
    expect(menu().highlighted, 0);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(menu().highlighted, 1);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(menu().highlighted, 0);
    final picked = menu().matches.first.suggestion;
    await press(tester, LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SuggestionMenu), findsNothing);
    expect(sentMessages(session), hasLength(before));
    expect(
      composer(tester).embeds,
      isNotEmpty,
      reason: 'the token of ${picked.label}',
    );

    composer(tester).clear();
    await typeText(tester, '/');
    expect(find.byType(SuggestionMenu), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SuggestionMenu), findsNothing);
    expect(composerText(tester), '/');
  });

  testWidgets('a / starting a word within the message opens the menu too; '
      'one starting no command, or within a word, stays text', (tester) async {
    await pumpChat(tester);
    await typeText(tester, '/');
    SuggestionMenu menu() => tester.widget(find.byType(SuggestionMenu));
    final command = menu().matches.first.suggestion;
    composer(tester).clear();

    await typeText(tester, '111 /${command.label}');
    expect(menu().matches.first.suggestion.label, command.label);
    await press(tester, LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SuggestionMenu), findsNothing);
    expect(composerMessage(tester), '111 /${command.value}');

    composer(tester).clear();
    await typeText(tester, 'see /zzqqxx');
    expect(find.byType(SuggestionMenu), findsNothing);
    await typeText(tester, 'src/${command.label}');
    expect(find.byType(SuggestionMenu), findsNothing);
  });

  testWidgets('↑ at the start shows the messages sent before, ↓ at the end '
      'the ones after, then what was typed', (tester) async {
    final session = await pumpChat(tester);
    final sent = sentMessages(session);
    expect(sent.length, greaterThan(1));
    await typeText(tester, 'draft');

    // Not at the start: the caret's.
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(composerText(tester), 'draft');

    moveCaret(tester, 0);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(composerMessage(tester), sent.last.trim());
    expect(composer(tester).selection.baseOffset, 0);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(composerMessage(tester), sent[sent.length - 2].trim());

    moveCaret(tester, composer(tester).length);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(composerMessage(tester), sent.last.trim());
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(composerText(tester), 'draft');

    // Edited, the message recalled is the one typed: no way on.
    moveCaret(tester, 0);
    await press(tester, LogicalKeyboardKey.arrowUp);
    await typeText(tester, 'edited');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(composerText(tester), 'edited');
  });

  testWidgets('Ctrl+. opens the mode picker, Ctrl+Alt+. the model picker', (
    tester,
  ) async {
    await pumpChat(tester);
    await tester.pump(const Duration(milliseconds: 300));
    final modeRow = find.text('Plan, edit and run code');
    expect(modeRow, findsNothing);
    await press(tester, LogicalKeyboardKey.period, control: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(modeRow, findsOneWidget);
    // Its keys are the open menu's.
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    expect(modeRow, findsNothing);

    final pickers = tester
        .widgetList<ComposerPicker>(find.byType(ComposerPicker))
        .toList();
    final model = pickers.last;
    final other = model.options.firstWhere(
      (option) => option != model.selected,
    );
    expect(find.text(other.label), findsNothing);
    await press(tester, LogicalKeyboardKey.period, control: true, alt: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(other.label), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('on macOS: ⌘/ adds files, ⌘. opens the mode picker, '
      '⌘Esc cancels the turn', (tester) async {
    final session = await pumpChat(tester);
    pickFiles(tester, ['/tmp/notes.md']);
    await typeText(tester, 'see');
    await press(tester, LogicalKeyboardKey.slash, meta: true);
    await tester.pump();
    expect(composerMessage(tester), 'see @/tmp/notes.md');

    final modeRow = find.text('Plan, edit and run code');
    await press(tester, LogicalKeyboardKey.period, meta: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(modeRow, findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    expect(modeRow, findsNothing);

    await press(tester, LogicalKeyboardKey.enter);
    expect(session.isStreaming, isTrue);
    await press(tester, LogicalKeyboardKey.escape, meta: true);
    await tester.pump(const Duration(seconds: 3));
    expect(session.isStreaming, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Ctrl+/ adds files', (tester) async {
    await pumpChat(tester);
    pickFiles(tester, [r'C:\work\notes.md']);
    await typeText(tester, 'see');
    await press(tester, LogicalKeyboardKey.slash, control: true);
    await tester.pump();
    expect(composerMessage(tester), r'see @C:\work\notes.md');
    expect(find.byType(SuggestionMenu), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Ctrl+↑ focuses the conversation, where the list\'s keys '
      'scroll it; Ctrl+↓ goes back to the input', (tester) async {
    await pumpChat(tester);
    await tester.pump(const Duration(milliseconds: 300));
    final input = tester.widget<MarkdownEditor>(find.byType(MarkdownEditor));
    expect(input.focusNode!.hasFocus, isTrue);
    final list = tester
        .stateList<ScrollableState>(
          find.descendant(
            of: find.byType(ChatHistoryView),
            matching: find.byType(Scrollable),
          ),
        )
        .map((scrollable) => scrollable.position)
        .reduce((a, b) => a.maxScrollExtent >= b.maxScrollExtent ? a : b);
    expect(list.maxScrollExtent, greaterThan(200));
    expect(list.pixels, closeTo(list.maxScrollExtent, 1));

    await press(tester, LogicalKeyboardKey.arrowUp, control: true);
    expect(input.focusNode!.hasFocus, isFalse);
    await press(tester, LogicalKeyboardKey.home);
    expect(list.pixels, lessThan(1));
    await press(tester, LogicalKeyboardKey.arrowDown);
    final line = list.pixels;
    expect(line, greaterThan(1));
    await press(tester, LogicalKeyboardKey.pageDown);
    expect(list.pixels, greaterThan(line + 100));
    await press(tester, LogicalKeyboardKey.end);
    await tester.pump();
    expect(list.pixels, closeTo(list.maxScrollExtent, 1));

    await press(tester, LogicalKeyboardKey.arrowDown, control: true);
    expect(input.focusNode!.hasFocus, isTrue);
  });

  testWidgets('Ctrl+Enter allows the tool the agent asks for', (tester) async {
    final session = await pumpChat(
      tester,
      kernel: MockKernels.codex,
      historyCount: 0,
    );
    // Codex asks before it runs the tests.
    session.send(const ComposerMessage(text: 'fix the composer'));
    for (var i = 0; i < 400 && session.isStreaming; i++) {
      switch (session.pendingInteraction) {
        case ApprovalRequest():
          break;
        case QuestionRequest():
          session.answer(const QuestionAnswer([], skipped: true));
        case null:
      }
      if (session.pendingInteraction is ApprovalRequest) break;
      await tester.pump(const Duration(milliseconds: 100));
    }
    final request = session.pendingInteraction;
    expect(request, isA<ApprovalRequest>());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(InteractionPanel), findsOneWidget);

    await press(tester, LogicalKeyboardKey.enter, control: true);
    expect(session.pendingInteraction, isNot(same(request)));
    await stopTurn(tester, session);
  });

  group('a prompt\'s options', () {
    const request = QuestionRequest(
      id: 'q',
      title: 'Question',
      questions: [
        Question(
          prompt: 'Which one?',
          options: [
            QuestionOption('Alpha'),
            QuestionOption('Beta'),
            QuestionOption('Gamma'),
          ],
        ),
      ],
    );

    Future<List<InteractionAnswer>> pumpPanel(WidgetTester tester) async {
      final answers = <InteractionAnswer>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: InteractionPanel(request: request, onAnswer: answers.add),
          ),
        ),
      );
      await tester.pump();
      return answers;
    }

    List<String>? picked(List<InteractionAnswer> answers) =>
        switch (answers.lastOrNull) {
          QuestionAnswer(:final picks, skipped: false) => picks.first,
          _ => null,
        };

    testWidgets('↓ and Enter pick the next one; 2 picks the second', (
      tester,
    ) async {
      var answers = await pumpPanel(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.enter);
      expect(picked(answers), ['Beta']);

      answers = await pumpPanel(tester);
      await press(tester, LogicalKeyboardKey.digit3, character: '3');
      expect(picked(answers), ['Gamma']);
    });

    testWidgets('Esc dismisses them', (tester) async {
      final answers = await pumpPanel(tester);
      await press(tester, LogicalKeyboardKey.escape);
      expect(answers.single, isA<QuestionAnswer>());
      expect((answers.single as QuestionAnswer).skipped, isTrue);
    });

    testWidgets('folded to its header, it shows the question; digits pick '
        'nothing unseen and Enter unfolds it', (tester) async {
      final answers = await pumpPanel(tester);
      await tester.tap(find.text('Question'));
      await tester.pump();
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Which one?'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.digit2, character: '2');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(answers, isEmpty);

      await press(tester, LogicalKeyboardKey.enter);
      expect(find.text('Alpha'), findsOneWidget);
      expect(answers, isEmpty);
      await press(tester, LogicalKeyboardKey.digit2, character: '2');
      expect(picked(answers), ['Beta']);
    });

    testWidgets('rebound, J moves down and Enter no longer goes on', (
      tester,
    ) async {
      KeybindingService.instance.userEntries = const [
        KeybindingEntry(
          key: 'j',
          command: ChatCommandIds.interactionFocusNext,
          when: ChatContextKeys.inInteraction,
        ),
        KeybindingEntry(
          key: 'ctrl+enter',
          command: ChatCommandIds.interactionAccept,
          when: ChatContextKeys.inInteraction,
        ),
        KeybindingEntry(
          key: 'enter',
          command: '-${ChatCommandIds.interactionAccept}',
        ),
      ];
      final answers = await pumpPanel(tester);
      await press(tester, LogicalKeyboardKey.keyJ, character: 'j');
      await press(tester, LogicalKeyboardKey.keyJ, character: 'j');
      await press(tester, LogicalKeyboardKey.enter);
      expect(answers, isEmpty);
      await press(tester, LogicalKeyboardKey.enter, control: true);
      expect(picked(answers), ['Gamma']);
    });

    group('with more than one question', () {
      const twoQuestions = QuestionRequest(
        id: 'q2',
        title: 'Questions',
        questions: [
          Question(
            prompt: 'First?',
            options: [QuestionOption('Alpha'), QuestionOption('Beta')],
          ),
          Question(
            prompt: 'Second?',
            options: [QuestionOption('Gamma'), QuestionOption('Delta')],
          ),
        ],
      );

      Future<List<InteractionAnswer>> pumpTwo(WidgetTester tester) async {
        final answers = <InteractionAnswer>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: InteractionPanel(
                request: twoQuestions,
                onAnswer: answers.add,
              ),
            ),
          ),
        );
        await tester.pump();
        return answers;
      }

      testWidgets('← goes back, keeps the pick, and Enter goes on again', (
        tester,
      ) async {
        final answers = await pumpTwo(tester);
        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.enter);
        expect(find.text('Second?'), findsOneWidget);

        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(find.text('First?'), findsOneWidget);
        // Up highlights Alpha; Enter goes on with Beta, the kept pick, not
        // with the highlighted one.
        await press(tester, LogicalKeyboardKey.arrowUp);
        await press(tester, LogicalKeyboardKey.enter);
        expect(find.text('Second?'), findsOneWidget);

        await press(tester, LogicalKeyboardKey.digit2, character: '2');
        final answer = answers.single as QuestionAnswer;
        expect(answer.skipped, isFalse);
        expect(answer.picks, [
          ['Beta'],
          ['Delta'],
        ]);
      });

      testWidgets('← on the first question does nothing', (tester) async {
        final answers = await pumpTwo(tester);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(find.text('First?'), findsOneWidget);
        expect(answers, isEmpty);
      });
    });
  });
}
