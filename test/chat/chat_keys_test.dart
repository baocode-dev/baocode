// The chat's keys as keybindings (see keybindings/chat_keybindings.dart):
// a chat alone, its composer and a prompt's options.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer_embeds.dart';
import 'package:baocode/chat/composer/composer_picker.dart';
import 'package:baocode/chat/composer/suggestion_menu.dart';
import 'package:baocode/chat/panels/interaction_panel.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/keybindings/chat_keybindings.dart';
import 'package:baocode/keybindings/keybinding_entry.dart';
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
      localizationsDelegates: const [FlutterQuillLocalizations.delegate],
      home: ChatScreen(session: session),
    ),
  );
  await tester.pump();
  return session;
}

QuillController composer(WidgetTester tester) =>
    tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;

String composerText(WidgetTester tester) {
  final text = composer(tester).document.toPlainText();
  return text.substring(0, text.length - 1);
}

/// What the composer would send: its tokens as their text.
String composerMessage(WidgetTester tester) => [
  for (final op in composer(tester).document.toDelta().toList())
    switch (op.data) {
      final String text => text,
      final Map<dynamic, dynamic> embed => ComposerTokenEmbed.plainText(
        embed[ComposerTokenEmbed.type],
      ),
      _ => '',
    },
].join().trim();

/// Types [text] in place of what the composer has, the caret at its end;
/// [composing], the part an input method is still composing.
Future<void> typeText(
  WidgetTester tester,
  String text, {
  TextRange composing = TextRange.empty,
}) async {
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: '$text\n',
      selection: TextSelection.collapsed(offset: text.length),
      composing: composing,
    ),
  );
  await tester.pump();
}

void moveCaret(WidgetTester tester, int offset) => composer(
  tester,
).updateSelection(TextSelection.collapsed(offset: offset), ChangeSource.local);

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

  testWidgets('with the @ menu open, its keys win: ↓ moves, Enter picks, '
      'Esc closes it', (tester) async {
    final session = await pumpChat(tester);
    final before = sentMessages(session).length;
    await typeText(tester, 'look at @');
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
      composer(tester).document.toDelta().toList().map((op) => op.data),
      contains(isA<Map>()),
      reason: 'the token of ${picked.label}',
    );

    await typeText(tester, '/');
    expect(find.byType(SuggestionMenu), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SuggestionMenu), findsNothing);
    expect(composerText(tester), '/');
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

    moveCaret(tester, composer(tester).document.length - 1);
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
    final modeRow = find.text('Plan, edit and run on its own');
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

  testWidgets('on macOS: ⌘/ starts a mention, ⌘. opens the mode picker, '
      '⌘Esc cancels the turn', (tester) async {
    final session = await pumpChat(tester);
    await typeText(tester, 'see');
    await press(tester, LogicalKeyboardKey.slash, meta: true);
    expect(composerText(tester), 'see @');
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));

    final modeRow = find.text('Plan, edit and run on its own');
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

  testWidgets('Ctrl+/ starts a mention', (tester) async {
    await pumpChat(tester);
    await typeText(tester, 'see');
    await press(tester, LogicalKeyboardKey.slash, control: true);
    expect(composerText(tester), 'see @');
    expect(find.byType(SuggestionMenu), findsOneWidget);
  });

  testWidgets('Ctrl+↑ focuses the conversation, where the list\'s keys '
      'scroll it; Ctrl+↓ goes back to the input', (tester) async {
    await pumpChat(tester);
    await tester.pump(const Duration(milliseconds: 300));
    final input = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(input.focusNode.hasFocus, isTrue);
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
    expect(input.focusNode.hasFocus, isFalse);
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
    expect(input.focusNode.hasFocus, isTrue);
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
        case PlanReviewRequest():
          session.answer(const PlanAnswer(PlanDecision.approve));
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
  });
}
