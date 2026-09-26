import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:monad/chat/chat_models.dart';
import 'package:monad/chat/chat_session.dart';
import 'package:monad/chat/chat_screen.dart';
import 'package:monad/chat/composer/composer.dart';
import 'package:monad/chat/composer/composer_caret.dart';
import 'package:monad/chat/composer/composer_embeds.dart';
import 'package:monad/chat/composer/suggestion_menu.dart';
import 'package:monad/chat/panels/activity_strip.dart';
import 'package:monad/chat/panels/ask_question_panel.dart';
import 'package:monad/chat/panels/context_usage_panel.dart';
import 'package:monad/theme/cursor_theme.dart';

Future<ChatSession> pumpScreen(WidgetTester tester) async {
  final session = ChatSession(historyCount: 16);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildCursorTheme(),
      localizationsDelegates: const [FlutterQuillLocalizations.delegate],
      home: ChatScreen(session: session),
    ),
  );
  await tester.pump();
  return session;
}

QuillController composerController(WidgetTester tester) =>
    tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;

/// Types [text] at the end of the composer through the text input channel.
Future<void> typeText(WidgetTester tester, String text) async {
  final controller = composerController(tester);
  final current = controller.document.toPlainText();
  final body = current.substring(0, current.length - 1) + text;
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: '$body\n',
      selection: TextSelection.collapsed(offset: body.length),
    ),
  );
  await tester.pump();
}

/// Runs short UI transitions to completion without waiting on repeating
/// animations (the live status shimmer never settles).
Future<void> settleAnimations(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<void> pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

void main() {
  testWidgets('@ opens the mention menu and inserts an atomic token', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.byType(SuggestionMenu), findsNothing);

    await typeText(tester, 'look at @hist');
    expect(find.byType(SuggestionMenu), findsOneWidget);
    expect(
      find.text('chat_history_view.dart', findRichText: true),
      findsOneWidget,
    );

    await pressKey(tester, LogicalKeyboardKey.enter);
    expect(find.byType(SuggestionMenu), findsNothing);

    final ops = composerController(tester).document.toDelta().toList();
    final token = ops
        .map((op) => op.data)
        .whereType<Map>()
        .single[ComposerTokenEmbed.type];
    expect(
      ComposerTokenEmbed.plainText(token),
      '@lib/chat/chat_history_view.dart',
    );
    expect(ops.first.data, 'look at ');
  });

  testWidgets('escape dismisses the menu until the trigger changes', (
    tester,
  ) async {
    await pumpScreen(tester);
    await typeText(tester, '/pl');
    expect(find.byType(SuggestionMenu), findsOneWidget);

    await pressKey(tester, LogicalKeyboardKey.escape);
    expect(find.byType(SuggestionMenu), findsNothing);

    await typeText(tester, 'a');
    expect(find.byType(SuggestionMenu), findsNothing);
  });

  testWidgets('shift+enter inserts a newline, enter sends', (tester) async {
    final session = await pumpScreen(tester);
    await typeText(tester, 'hello');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(session.itemCount, 16);

    await pressKey(tester, LogicalKeyboardKey.enter);
    expect(session.itemCount, greaterThan(16));
    final sent = session.itemAt(16) as UserMessageItem;
    expect(sent.text, 'hello');
    expect(sent.attachments, isEmpty);
    expect(composerController(tester).document.toPlainText(), '\n');
    expect(session.isStreaming, isTrue);

    await tester.tap(find.byTooltip('Stop'));
    await tester.pump(const Duration(seconds: 3));
    expect(session.isStreaming, isFalse);
  });

  testWidgets('full mock turn drives the panels', (tester) async {
    final session = await pumpScreen(tester);
    await typeText(tester, 'build the composer');
    await pressKey(tester, LogicalKeyboardKey.enter);

    for (var i = 0; i < 60 && session.pendingQuestion == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AskQuestionPanel), findsOneWidget);

    // Single choice advances, multi choice toggles then submits.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2, character: '2');
    await tester.pump();
    await pressKey(tester, LogicalKeyboardKey.enter);
    await settleAnimations(tester);
    expect(find.byType(AskQuestionPanel), findsNothing);

    for (var i = 0; i < 80 && session.isStreaming; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ActivityStrip), findsOneWidget);
    expect(find.text('3 files changed'), findsOneWidget);
    expect(find.textContaining('Running ·'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Passed'), findsOneWidget);

    await tester.tap(find.text('Keep all'));
    await settleAnimations(tester);
    expect(find.text('3 files changed'), findsNothing);
  });

  testWidgets('context panel opens from the ring', (tester) async {
    await pumpScreen(tester);
    final ring = find.byWidgetPredicate(
      (widget) =>
          widget is Tooltip &&
          (widget.message ?? '').endsWith('% of context used'),
    );
    await tester.tap(ring);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ContextUsagePanel), findsOneWidget);

    await tester.tap(ring);
    await settleAnimations(tester);
    expect(find.byType(ContextUsagePanel), findsNothing);
  });

  testWidgets('history stays pinned to the bottom as panels open', (
    tester,
  ) async {
    await pumpScreen(tester);
    final position = tester
        .widget<SuperListView>(find.byType(SuperListView))
        .controller!
        .position;
    expect(position.pixels, position.maxScrollExtent);

    final ring = find.byWidgetPredicate(
      (widget) =>
          widget is Tooltip &&
          (widget.message ?? '').endsWith('% of context used'),
    );
    await tester.tap(ring);
    // Every frame of the resize animation, not just the last one.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      expect(position.pixels, position.maxScrollExtent);
    }
  });

  testWidgets('caret is text-height, centered on the line, never clipped', (
    tester,
  ) async {
    // Quill nudges its caret on Apple platforms; ours must not inherit that.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await pumpScreen(tester);
    await tester.pump();
    final caret = tester.state<ComposerCaretState>(find.byType(ComposerCaret));
    final editor = tester
        .state<QuillRawEditorState>(find.byType(QuillRawEditor))
        .renderEditor;

    void expectCentered(int offset) {
      final rect = caret.caretRect!;
      final line = editor.getLocalRectForCaret(TextPosition(offset: offset));
      final caretBox = tester.renderObject<RenderBox>(
        find.byType(ComposerCaret),
      );
      final lineTop = caretBox
          .globalToLocal(editor.localToGlobal(line.topLeft))
          .dy;
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.height, lessThan(line.height));
      expect(rect.center.dy, moreOrLessEquals(lineTop + line.height / 2));
    }

    expectCentered(0);
    await typeText(tester, 'Plan');
    await tester.pump();
    expectCentered(4);
    expect(caret.caretRect!.left, greaterThan(10));

    // Blinks off when idle, solid again on the next edit.
    await tester.pump(const Duration(milliseconds: 600));
    expect(caret.caretRect, isNull);
    await typeText(tester, 's');
    await tester.pump();
    expect(caret.caretRect, isNotNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('tokens never change the line height', (tester) async {
    await pumpScreen(tester);
    double height() => tester.getSize(find.byType(ChatComposer)).height;
    final empty = height();

    // A line holding only a token and a trailing space used to lay out
    // taller than the same line with text after it.
    await typeText(tester, '/rev');
    await pressKey(tester, LogicalKeyboardKey.enter);
    await tester.pump();
    expect(height(), empty);
    await typeText(tester, '1 @chat_s');
    await pressKey(tester, LogicalKeyboardKey.enter);
    await tester.pump();
    expect(height(), empty);
    await typeText(tester, 'x');
    await tester.pump();
    expect(height(), empty);

    // Deleting the space after a token leaves a token-only line, which
    // Flutter lays out taller; a trailing space is kept after the caret.
    final controller = composerController(tester);
    controller.clear();
    await typeText(tester, '/rev');
    await pressKey(tester, LogicalKeyboardKey.enter);
    controller.replaceText(1, 1, '', const TextSelection.collapsed(offset: 1));
    await tester.pump();
    expect(height(), empty);
    expect(controller.selection.baseOffset, 1);
    expect(controller.document.toPlainText(), '\uFFFC \n');
  });

  testWidgets('accepting a suggestion inserts exactly one space', (
    tester,
  ) async {
    await pumpScreen(tester);
    await typeText(tester, 'see @chat_s');
    await pressKey(tester, LogicalKeyboardKey.enter);
    final controller = composerController(tester);
    expect(controller.document.toPlainText(), 'see \uFFFC \n');
    expect(controller.selection.baseOffset, 6);
  });

  testWidgets('text area keeps its resting height, grows, then scrolls', (
    tester,
  ) async {
    await pumpScreen(tester);
    double height() => tester.getSize(find.byType(ChatComposer)).height;
    final resting = height();

    // Two lines fit in the resting height.
    await typeText(tester, 'one\ntwo');
    expect(height(), resting);

    await typeText(tester, '\nthree\nfour');
    final grown = height();
    expect(grown, greaterThan(resting));

    // Far past the cap: height stops growing, content scrolls inside, and
    // the caret at the end stays in view.
    await typeText(tester, List.generate(30, (i) => '\nline $i').join());
    await tester.pump();
    final capped = height();
    await typeText(tester, '\nmore\nand more');
    // Quill animates the scroll to the caret (100ms).
    await settleAnimations(tester);
    expect(height(), capped);
    expect(capped, lessThan(resting + 13.5 * 1.5 * 10));

    final scroll = tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .scrollController;
    expect(scroll.offset, greaterThan(0));
    expect(scroll.offset, scroll.position.maxScrollExtent);
    // One slim scrollbar, not a second default one from the scroll behavior.
    expect(
      find.descendant(
        of: find.byType(ChatComposer),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.foregroundPainter is ScrollbarPainter,
        ),
      ),
      findsOneWidget,
    );
    final caret = tester.state<ComposerCaretState>(find.byType(ComposerCaret));
    final area = tester.getSize(find.byType(ComposerCaret));
    expect(caret.caretRect, isNotNull);
    expect(caret.caretRect!.bottom, lessThanOrEqualTo(area.height));
    expect(caret.caretRect!.top, greaterThanOrEqualTo(0));
  });
}
