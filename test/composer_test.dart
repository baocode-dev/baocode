import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/widgets/activity_row.dart';
import 'package:monad/sidebar/sidebar.dart';
import 'package:monad/workspace/workspace.dart';
import 'package:monad/chat/widgets/markdown_view.dart';
import 'package:monad/workspace/window_controls.dart';
import 'package:monad/main.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:monad/kernel/claude_code/claude_code_kernel.dart';
import 'package:monad/chat/chat_models.dart';
import 'package:monad/chat/widgets/edge_fade_mask.dart';
import 'package:monad/chat/widgets/live_selectable_text.dart';
import 'package:monad/chat/widgets/shimmer_text.dart';
import 'package:monad/chat/widgets/thinking_section.dart';
import 'package:monad/chat/widgets/chat_item_view.dart';
import 'package:monad/chat/widgets/user_message_bubble.dart';
import 'package:monad/chat/chat_history_view.dart';
import 'package:monad/chat/chat_session.dart';
import 'package:monad/chat/chat_screen.dart';
import 'package:monad/chat/composer/composer.dart';
import 'package:monad/chat/composer/composer_caret.dart';
import 'package:monad/chat/composer/composer_embeds.dart';
import 'package:monad/chat/composer/composer_picker.dart';
import 'package:monad/chat/floating/floating_layer.dart';
import 'package:monad/chat/composer/suggestion_menu.dart';
import 'package:monad/chat/panels/activity_strip.dart';
import 'package:monad/chat/panels/interaction_panel.dart';
import 'package:monad/chat/panels/context_usage_panel.dart';
import 'package:monad/theme/cursor_theme.dart';

Future<ChatSession> pumpScreen(
  WidgetTester tester, {
  int historyCount = 16,
}) async {
  final session = ChatSession(historyCount: historyCount);
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

Matcher isSelection(int base, int extent) => isA<TextSelection>()
    .having((s) => s.baseOffset, 'base', base)
    .having((s) => s.extentOffset, 'extent', extent);

void main() {
  testWidgets('the answers sit inset from the user\'s messages by their '
      'corner radius', (tester) async {
    await pumpScreen(tester);
    final items = tester.widgetList<ChatItemView>(find.byType(ChatItemView));
    double width(bool user) => tester
        .getSize(
          find.byWidget(
            items.firstWhere((view) => (view.item is UserMessageItem) == user),
          ),
        )
        .width;
    expect(width(false), width(true) - 2 * UserMessageBubble.radius);
  });

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
    await settleAnimations(tester);
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
    await settleAnimations(tester);
    expect(find.byType(SuggestionMenu), findsNothing);

    await typeText(tester, 'a');
    await settleAnimations(tester);
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

    for (var i = 0; i < 200 && session.pendingInteraction == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(InteractionPanel), findsOneWidget);

    // Single choice advances, multi choice toggles then submits.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2, character: '2');
    await tester.pump();
    await pressKey(tester, LogicalKeyboardKey.enter);
    await settleAnimations(tester);
    expect(find.byType(InteractionPanel), findsNothing);

    for (var i = 0; i < 80 && session.isStreaming; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ActivityStrip), findsOneWidget);
    expect(find.text('3 files changed'), findsOneWidget);
    expect(find.textContaining('Running ·'), findsOneWidget);

    // Done, the task leaves; the changes stay.
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('Running ·'), findsNothing);
    expect(find.text('3 files changed'), findsOneWidget);

    await tester.tap(find.text('Keep all'));
    await settleAnimations(tester);
    expect(find.text('3 files changed'), findsNothing);
  });

  group('thinking', () {
    Finder liveThought() => find.byType(ThinkingSection).last;
    ThinkingSection section(WidgetTester tester) =>
        tester.widget<ThinkingSection>(liveThought());
    EdgeFadeMask liveMask(WidgetTester tester) => tester.widget<EdgeFadeMask>(
      find.descendant(of: liveThought(), matching: find.byType(EdgeFadeMask)),
    );

    testWidgets('a short thought, expanded, keeps to the left of its column', (
      tester,
    ) async {
      // As the history lays out an item: centered, at most the column wide.
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              key: const Key('column'),
              constraints: const BoxConstraints(maxWidth: 400),
              child: ThinkingSection(
                text: '先确认需求涉及的文件。',
                seconds: 2,
                expanded: true,
                onToggle: () {},
              ),
            ),
          ),
        ),
      );
      final column = tester.getRect(find.byKey(const Key('column')));
      final rect = tester.getRect(find.byType(ThinkingSection));
      expect(rect.left, column.left);
      expect(rect.width, 400);
      expect(
        tester.getTopLeft(find.text('先确认需求涉及的文件。')).dx,
        lessThan(column.left + 20),
      );
    });

    testWidgets('keeps a selection in place while its text streams', (
      tester,
    ) async {
      var text = List.generate(12, (i) => '第$i行思考内容，一些文字。').join();
      String? copied;
      late StateSetter setText;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionArea(
              onSelectionChanged: (content) => copied = content?.plainText,
              child: SizedBox(
                width: 300,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    setText = setState;
                    return ThinkingSection(
                      text: text,
                      seconds: null,
                      expanded: true,
                      onToggle: () {},
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();

      final live = find.byType(LiveSelectableText);
      RenderLiveSelectableText render() => tester.renderObject(live);
      final rect = tester.getRect(live);
      final drag = await tester.startGesture(
        rect.topLeft + const Offset(80, 60),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await drag.moveTo(rect.topLeft + const Offset(200, 90));
      await tester.pump();
      await drag.up();
      await tester.pump(const Duration(milliseconds: 500));

      String? selected() => render().selection?.textInside(render().text);
      final before = selected();
      expect(before, hasLength(greaterThan(10)));
      expect(copied, before);

      // The text keeps streaming and following; every frame keeps the same
      // characters selected.
      final scrolled = position.pixels;
      for (var i = 0; i < 4; i++) {
        setText(() => text += '追加的一句新内容追加的一句新内容');
        await tester.pump();
        expect(render().text, text);
        expect(selected(), before);
        await tester.pump();
        expect(selected(), before);
        expect(copied, before);
      }
      expect(position.pixels, greaterThan(scrolled));
      expect(position.pixels, position.maxScrollExtent);
    });

    testWidgets('streams open in a capped box, then settles closed', (
      tester,
    ) async {
      final session = await pumpScreen(tester);
      await typeText(tester, 'build the composer');
      await pressKey(tester, LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 600));

      // Streaming: open, its time so far in the header, from 1s.
      expect(section(tester).seconds, isNull);
      expect(section(tester).expanded, isTrue);
      expect(
        find.descendant(
          of: liveThought(),
          matching: find.textContaining(RegExp(r'^Thinking [1-9]\d*s$')),
        ),
        findsOneWidget,
      );
      // The chevron follows the title, however wide the row.
      final title = tester.getRect(
        find.descendant(
          of: liveThought(),
          matching: find.textContaining(RegExp(r'^Thinking [1-9]\d*s$')),
        ),
      );
      final chevron = tester.getRect(
        find.descendant(
          of: liveThought(),
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
      );
      expect(chevron.left - title.right, lessThan(8));

      // Past seven lines: capped, following the newest, masked at the top.
      final box = find.descendant(
        of: liveThought(),
        matching: find.byType(SingleChildScrollView),
      );
      ScrollPosition position() => tester
          .state<ScrollableState>(
            find.descendant(of: box, matching: find.byType(Scrollable)),
          )
          .position;
      for (var i = 0; i < 150 && position().maxScrollExtent < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(section(tester).seconds, isNull);
      expect(tester.getSize(box).height, lessThanOrEqualTo(13 * 1.6 * 7));
      expect(position().pixels, position().maxScrollExtent);
      expect(position().pixels, greaterThan(0));
      expect(liveMask(tester).top, isTrue);

      // Done: closed, with its time.
      for (var i = 0; i < 150 && section(tester).seconds == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await settleAnimations(tester);
      expect(section(tester).expanded, isFalse);
      expect(
        find.descendant(
          of: liveThought(),
          matching: find.textContaining(
            RegExp(r'^Thought (\d+s|briefly)$'),
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
      session.stop();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the user can close and reopen it while it streams', (
      tester,
    ) async {
      final session = await pumpScreen(tester);
      await typeText(tester, 'build the composer');
      await pressKey(tester, LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 600));
      final header = find.descendant(
        of: liveThought(),
        matching: find.textContaining('Thinking'),
      );

      await tester.tap(header);
      await tester.pump(const Duration(milliseconds: 100));
      expect(section(tester).seconds, isNull);
      expect(section(tester).expanded, isFalse);

      await tester.tap(header);
      await tester.pump(const Duration(milliseconds: 100));
      expect(section(tester).expanded, isTrue);

      // Opened by the user, it stays open once done.
      for (var i = 0; i < 150 && section(tester).seconds == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(section(tester).seconds, isNotNull);
      expect(section(tester).expanded, isTrue);
      session.stop();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('stopping mid-thought settles it', (tester) async {
      final session = await pumpScreen(tester);
      await typeText(tester, 'build the composer');
      await pressKey(tester, LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 800));
      session.stop();
      await tester.pump(const Duration(seconds: 1));
      expect(section(tester).seconds, isNotNull);
      expect(find.byType(ShimmerText), findsNothing);
    });
  });

  testWidgets('context panel opens from the ring', (tester) async {
    ClaudeCodeKernel.forgetAccount();
    await pumpScreen(tester);
    final ring = find.byTooltip('Context usage');
    await tester.tap(ring);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ContextUsagePanel), findsOneWidget);
    // The plan's limits, asked for as it opens, before anything is sent.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Plan usage'), findsOneWidget);
    expect(find.text('Weekly Opus limit'), findsOneWidget);
    // A circle, not squeezed by the taller box it sits in.
    final ringSize = tester.getSize(
      find.descendant(of: ring, matching: find.byType(CustomPaint)).last,
    );
    expect(ringSize, const Size.square(13));
    // Nothing to press but close: compacting is `/compact`.
    expect(
      find.descendant(
        of: find.byType(ContextUsagePanel),
        matching: find.text('Compact'),
      ),
      findsNothing,
    );
    // The ring shows no number, even while its panel is open.
    expect(
      find.descendant(
        of: find.byType(ChatComposer),
        matching: find.textContaining('%'),
      ),
      findsNothing,
    );

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

    final ring = find.byTooltip('Context usage');
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

  testWidgets('a right click opens the system menu: cut, copy, paste, '
      'select all', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final messenger = tester.binding.defaultBinaryMessenger;
    final menus = <List<Map<Object?, Object?>>>[];
    final replies = ['selectAll', 'copy', 'paste'];
    messenger.setMockMethodCallHandler(const MethodChannel('monad/window'), (
      call,
    ) async {
      switch (call.method) {
        case 'canPaste':
          return true;
        case 'showContextMenu':
          final arguments = call.arguments as Map<Object?, Object?>;
          menus.add((arguments['items'] as List).cast());
          return replies.removeAt(0);
      }
      return null;
    });
    String? copied;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        case 'Clipboard.getData':
          return {'text': 'pasted'};
      }
      return null;
    });
    try {
      await pumpScreen(tester);
      await typeText(tester, 'hello world');
      final controller = composerController(tester);
      Future<void> rightClick() async {
        await tester.tapAt(
          tester.getCenter(find.byType(QuillEditor)),
          buttons: kSecondaryMouseButton,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await tester.pump();
      }

      Map<Object?, bool> enabled(List<Map<Object?, Object?>> items) => {
        for (final item in items) ?item['id']: item['enabled'] == true,
      };

      await rightClick();
      expect(enabled(menus.last), {
        'cut': false,
        'copy': false,
        'paste': true,
        'selectAll': true,
      });
      expect(controller.selection, isSelection(0, 11));

      // On the selection: it stays, and is copied.
      await rightClick();
      expect(enabled(menus.last)['copy'], isTrue);
      expect(copied, 'hello world');
      expect(controller.selection, isSelection(0, 11));

      await rightClick();
      expect(controller.document.toPlainText(), 'pasted\n');
      expect(menus, hasLength(3));
    } finally {
      messenger.setMockMethodCallHandler(
        const MethodChannel('monad/window'),
        null,
      );
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the Edit menu acts where the focus is: the composer, or '
      'the conversation', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final messenger = tester.binding.defaultBinaryMessenger;
    String? copied;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    try {
      WindowControls.handleEditCommands();
      await pumpScreen(tester);

      /// The menu item [command] chosen, as the window sends it.
      Future<void> menu(String command) async {
        await messenger.handlePlatformMessage(
          'monad/window',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('editCommand', command),
          ),
          (_) {},
        );
        await tester.pump();
      }

      await typeText(tester, 'hello world');
      await menu('selectAll');
      expect(composerController(tester).selection, isSelection(0, 11));
      await menu('copy');
      expect(copied, 'hello world');

      // In the conversation, once clicked: all of it.
      final reply = find
          .descendant(
            of: find.byType(MarkdownView),
            matching: find.byType(RichText),
          )
          .first;
      final click = await tester.startGesture(
        tester.getCenter(reply),
        kind: PointerDeviceKind.mouse,
      );
      await click.up();
      await tester.pump(const Duration(milliseconds: 500));
      await menu('selectAll');
      await menu('copy');
      expect(copied, contains('第 1 轮'));
      expect(copied!.length, greaterThan(200));
    } finally {
      messenger.setMockMethodCallHandler(
        const MethodChannel('monad/window'),
        null,
      );
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('paste', () {
    /// Puts [text] on the (mock) clipboard and pastes it into the composer.
    Future<void> paste(WidgetTester tester, String text) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => switch (call.method) {
          'Clipboard.getData' => {'text': text},
          _ => null,
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      // ignore: experimental_member_use
      await composerController(tester).clipboardPaste();
      await tester.pump();
    }

    /// The composer's content, tokens as their sent text in brackets.
    String content(WidgetTester tester) => [
      for (final op in composerController(tester).document.toDelta().toList())
        switch (op.data) {
          final Map<dynamic, dynamic> data =>
            '[${ComposerTokenEmbed.plainText(data[ComposerTokenEmbed.type])}]',
          final data => '$data',
        },
    ].join();

    testWidgets('turns known mentions and a leading command into tokens', (
      tester,
    ) async {
      await pumpScreen(tester);
      await paste(tester, '/plan 看一下 @lib/main.dart 和 @pubspec.yaml 里的用法');
      expect(
        content(tester),
        '[/plan] 看一下 [@lib/main.dart] 和 [@pubspec.yaml] 里的用法\n',
      );
      // Caret after the pasted text; no menu from the @s in it.
      final controller = composerController(tester);
      expect(controller.selection.baseOffset, controller.document.length - 1);
      expect(find.byType(SuggestionMenu), findsNothing);
    });

    testWidgets('leaves other @words and a mid-message /command as text', (
      tester,
    ) async {
      await pumpScreen(tester);
      await typeText(tester, 'try ');
      await paste(tester, '/plan with @override and a@lib/main.dart');
      expect(content(tester), 'try /plan with @override and a@lib/main.dart\n');
    });

    testWidgets('replaces the selection', (tester) async {
      await pumpScreen(tester);
      await typeText(tester, 'see here');
      composerController(tester).updateSelection(
        const TextSelection(baseOffset: 4, extentOffset: 8),
        ChangeSource.local,
      );
      await paste(tester, '@README.md');
      expect(content(tester), 'see [@README.md] \n');
    });
  });

  testWidgets('a mouse drag selection follows every move, unthrottled', (
    tester,
  ) async {
    await pumpScreen(tester);
    await typeText(tester, 'hello world, a line to select across');
    final controller = composerController(tester);
    final editor = find.byType(QuillEditor);
    final start = tester.getTopLeft(editor) + const Offset(2, 12);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    var extent = 0;
    for (var dx = 20.0; dx <= 120; dx += 20) {
      await gesture.moveTo(start + Offset(dx, 0));
      // One frame, well within Quill's 50ms throttle.
      await tester.pump(const Duration(milliseconds: 8));
      final selection = controller.selection;
      expect(selection.baseOffset, 0, reason: 'dx $dx');
      expect(selection.extentOffset, greaterThan(extent), reason: 'dx $dx');
      extent = selection.extentOffset;
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.selection.extentOffset, extent);
  });

  testWidgets('the mention menu opens only at the end of a query', (
    tester,
  ) async {
    await pumpScreen(tester);
    await typeText(tester, 'see @chat_s');
    expect(find.byType(SuggestionMenu), findsOneWidget);
    composerController(tester).updateSelection(
      const TextSelection.collapsed(offset: 9),
      ChangeSource.local,
    );
    await settleAnimations(tester);
    expect(find.byType(SuggestionMenu), findsNothing);
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

  testWidgets('mode picker opens on press, animates, and follows the mouse', (
    tester,
  ) async {
    await pumpScreen(tester);
    await settleAnimations(tester);
    final modePill = find.byType(ComposerPicker).first;
    final menuRow = find.text('Plan, edit and run on its own');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(modePill));

    // Opens on press, before release, fading in over the next frames.
    await mouse.down(tester.getCenter(modePill));
    await tester.pump();
    expect(menuRow, findsOneWidget);
    double opacity() => tester
        .widget<FadeTransition>(
          find
              .ancestor(of: menuRow, matching: find.byType(FadeTransition))
              .first,
        )
        .opacity
        .value;
    // Visible on the first frame, still animating in.
    expect(opacity(), inExclusiveRange(0, 1));
    await settleAnimations(tester);
    expect(opacity(), 1);

    // Press-drag-release onto an option picks it.
    await mouse.moveTo(tester.getCenter(find.text('Plan').last));
    await tester.pump();
    await mouse.up();
    await settleAnimations(tester);
    expect(menuRow, findsNothing);
    expect(
      find.descendant(of: modePill, matching: find.text('Plan')),
      findsOneWidget,
    );

    // Click opens it and it stays open; arrows and Enter choose without
    // taking focus from the composer.
    await mouse.down(tester.getCenter(modePill));
    await mouse.up();
    await settleAnimations(tester);
    expect(menuRow, findsOneWidget);
    final focus = tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .focusNode;
    expect(focus.hasFocus, isTrue);
    await pressKey(tester, LogicalKeyboardKey.arrowDown); // Plan -> Agent
    await pressKey(tester, LogicalKeyboardKey.enter);
    await settleAnimations(tester);
    expect(menuRow, findsNothing);
    expect(
      find.descendant(of: modePill, matching: find.text('Agent')),
      findsOneWidget,
    );
    expect(focus.hasFocus, isTrue);
    expect(composerController(tester).document.toPlainText(), '\n');

    // A click outside closes it.
    await mouse.down(tester.getCenter(modePill));
    await mouse.up();
    await settleAnimations(tester);
    await mouse.moveTo(const Offset(5, 5));
    await mouse.down(const Offset(5, 5));
    await mouse.up();
    await settleAnimations(tester);
    expect(menuRow, findsNothing);
    await mouse.removePointer();
  });

  testWidgets('the suggestion menu shows on the next frame and fades out', (
    tester,
  ) async {
    await pumpScreen(tester);
    await settleAnimations(tester);
    await typeText(tester, '/');
    expect(find.byType(SuggestionMenu), findsOneWidget);
    await settleAnimations(tester);

    await pressKey(tester, LogicalKeyboardKey.escape);
    // Still fading out, then gone.
    await tester.pump(FloatingLayer.defaultExitDuration ~/ 2);
    expect(find.byType(SuggestionMenu), findsOneWidget);
    await settleAnimations(tester);
    expect(find.byType(SuggestionMenu), findsNothing);
  });

  /// Another conversation shows, then [session]'s again.
  Future<void> switchAwayAndBack(
    WidgetTester tester,
    ChatSession session, {
    ChatSession? other,
  }) async {
    Future<void> show(ChatSession session) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildCursorTheme(),
          localizationsDelegates: const [FlutterQuillLocalizations.delegate],
          home: ChatScreen(key: ObjectKey(session), session: session),
        ),
      );
      await tester.pump();
    }

    final away = other ?? ChatSession(historyCount: 0);
    if (other == null) addTearDown(away.dispose);
    await show(away);
    expect(composerController(tester).document.toPlainText(), '\n');
    await show(session);
  }

  testWidgets('what is typed stays with its conversation until sent', (
    tester,
  ) async {
    final session = await pumpScreen(tester, historyCount: 0);
    await typeText(tester, 'half a thought');
    await switchAwayAndBack(tester, session);
    final controller = composerController(tester);
    expect(controller.document.toPlainText(), 'half a thought\n');
    expect(controller.selection.baseOffset, 'half a thought'.length);

    await pressKey(tester, LogicalKeyboardKey.enter);
    await switchAwayAndBack(tester, session);
    expect(composerController(tester).document.toPlainText(), '\n');
    session.stop();
    await tester.pump(const Duration(seconds: 5));
  });

  group('editing a sent message', () {
    Finder editorInHistory() => find.descendant(
      of: find.byType(ChatHistoryView),
      matching: find.byType(QuillEditor),
    );
    QuillController editController(WidgetTester tester) =>
        tester.widget<QuillEditor>(editorInHistory()).controller;
    // The message in the list (not its copy stuck to the top).
    Finder inList(Finder finder) =>
        find.descendant(of: find.byType(SuperListView), matching: finder);
    Finder bubble(String text) => find.ancestor(
      of: inList(find.textContaining(text, findRichText: true)),
      matching: find.byType(UserMessageBubble),
    );
    // The history opens at the bottom; bring the message into view.
    Future<void> reveal(WidgetTester tester, String text) async {
      // Mid-view: at the top, the message's copy stuck there would cover it.
      await Scrollable.ensureVisible(
        tester.element(
          find.descendant(
            of: find.byType(SuperListView),
            matching: find.textContaining(
              text,
              findRichText: true,
              skipOffstage: false,
            ),
            skipOffstage: false,
          ),
        ),
        alignment: 0.5,
      );
      await tester.pump();
    }

    testWidgets('history shows the message text only, mentions included', (
      tester,
    ) async {
      await pumpScreen(tester);
      await reveal(tester, '第 2 轮');
      final message = bubble('第 2 轮');
      expect(message, findsOneWidget);
      // No header of attachment pills; the mention in the text shows as
      // an inline tag.
      expect(
        find.descendant(of: message, matching: find.byType(Wrap)),
        findsNothing,
      );
      final chip = find.descendant(
        of: message,
        matching: find.byType(ComposerTokenChip),
      );
      expect(chip, findsOneWidget);
      expect(
        find.descendant(of: chip, matching: find.text('main.dart')),
        findsOneWidget,
      );
    });

    testWidgets('an edit left open stays open, with what was typed', (
      tester,
    ) async {
      final session = await pumpScreen(tester);
      await reveal(tester, '第 2 轮');
      await tester.tap(bubble('第 2 轮'));
      await tester.pump();
      final controller = editController(tester);
      controller.replaceText(controller.document.length - 1, 0, ' 再加一句', null);
      await tester.pump();

      await switchAwayAndBack(tester, session);
      expect(editorInHistory(), findsOneWidget);
      expect(editController(tester).document.toPlainText(), contains('再加一句'));
      // The composer below (after the history) has its own, empty.
      expect(
        tester
            .widget<QuillEditor>(find.byType(QuillEditor).last)
            .controller
            .document
            .toPlainText(),
        isNot(contains('再加一句')),
      );
    });

    testWidgets('an edit stays open while another conversation is visited '
        'from the sidebar', (tester) async {
      await tester.pumpWidget(MonadApp(workspace: Workspace.mock()));
      await tester.pump();
      final title = find.descendant(
        of: find.byType(Sidebar),
        matching: find.text('Optimize virtual list scrolling'),
      );
      await tester.tap(title);
      await tester.pump();
      // Its last message, near the bottom where it opens.
      await reveal(tester, '第 12500 轮');
      await tester.tap(bubble('第 12500 轮'));
      await tester.pump();
      final controller = editController(tester);
      controller.replaceText(controller.document.length - 1, 0, ' 补充', null);
      await tester.pump();

      await tester.tap(
        find.descendant(
          of: find.byType(Sidebar),
          matching: find.text('Sticky user message on scroll'),
        ),
      );
      await tester.pump();
      expect(editorInHistory(), findsNothing);
      await tester.tap(title);
      await tester.pump();
      expect(editorInHistory(), findsOneWidget);
      expect(editController(tester).document.toPlainText(), contains('补充'));
    });

    testWidgets('a click opens a full composer in place, focused', (
      tester,
    ) async {
      final session = await pumpScreen(tester);
      const index = 8; // 第 2 轮
      final original = (session.itemAt(index) as UserMessageItem).text;

      await reveal(tester, '第 2 轮');
      await tester.tap(bubble('第 2 轮'));
      await tester.pump();
      expect(bubble('第 2 轮'), findsNothing);
      expect(editorInHistory(), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ChatHistoryView),
          matching: find.byType(ComposerPicker),
        ),
        findsNWidgets(3), // Mode, approvals, model.
      );
      expect(
        tester.widget<QuillEditor>(editorInHistory()).focusNode.hasFocus,
        isTrue,
      );

      // Mentions come back as tokens; sending it unchanged yields the same
      // text: the message is its text.
      final tokens = editController(tester).document
          .toDelta()
          .toList()
          .map((op) => op.data)
          .whereType<Map>()
          .map(
            (data) =>
                ComposerTokenEmbed.plainText(data[ComposerTokenEmbed.type]),
          )
          .toList();
      expect(tokens, ['@lib/main.dart']);

      // Esc cancels.
      await pressKey(tester, LogicalKeyboardKey.escape);
      expect(editorInHistory(), findsNothing);
      expect(bubble('第 2 轮'), findsOneWidget);
      expect((session.itemAt(index) as UserMessageItem).text, original);

      // Unchanged resend: same text, the rest of the conversation replaced.
      await tester.tap(bubble('第 2 轮'));
      await tester.pump();
      await pressKey(tester, LogicalKeyboardKey.enter);
      expect(editorInHistory(), findsNothing);
      expect((session.itemAt(index) as UserMessageItem).text, original);
      // The message, and its answer begun: a thought, which says the agent
      // is at work itself.
      expect(session.itemCount, index + 2);
      expect(session.itemAt(index + 1), isA<ThinkingItem>());
      expect(session.isStreaming, isTrue);
      // Once the thought is done, the status row: as the answer grows it
      // moves down, and goes on where it was.
      bool rowLast() => session.itemAt(session.itemCount - 1) is LiveStatusItem;
      Future<void> until(bool Function() done) async {
        for (var i = 0; i < 600 && !done(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(done(), isTrue);
      }

      await until(rowLast);
      final row = tester.element(find.byType(ActivityRow));
      final count = session.itemCount;
      await until(() => session.itemCount > count && rowLast());
      expect(tester.element(find.byType(ActivityRow)), same(row));
      session.stop();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('an edited message replaces the rest of the conversation', (
      tester,
    ) async {
      final session = await pumpScreen(tester);
      const index = 8;
      await reveal(tester, '第 2 轮');
      await tester.tap(bubble('第 2 轮'));
      await tester.pump();
      final controller = editController(tester);
      controller.replaceText(
        controller.document.length - 1,
        0,
        ' 另外加上单元测试',
        TextSelection.collapsed(offset: controller.document.length + 8),
      );
      await tester.pump();
      await pressKey(tester, LogicalKeyboardKey.enter);

      final sent = session.itemAt(index) as UserMessageItem;
      expect(sent.text, endsWith('的计算换成惰性的。 另外加上单元测试'));
      expect(sent.text, contains('@lib/main.dart'));
      expect(session.itemCount, lessThan(16));
      expect(session.isStreaming, isTrue);
      session.stop();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('dragging across a message selects instead of editing', (
      tester,
    ) async {
      await pumpScreen(tester);
      await reveal(tester, '第 2 轮');
      final rect = tester.getRect(bubble('第 2 轮'));
      final drag = await tester.startGesture(
        rect.centerLeft + const Offset(16, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await drag.moveTo(rect.center);
      await tester.pump();
      await drag.up();
      await tester.pump();
      expect(editorInHistory(), findsNothing);
    });

    testWidgets('a message with inline tags copies as its text', (
      tester,
    ) async {
      final session = await pumpScreen(tester);
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await reveal(tester, '第 1 轮');
      final original = (session.itemAt(0) as UserMessageItem).text;
      expect(original, contains('@lib/main.dart 和 @pubspec.yaml'));
      final rect = tester.getRect(bubble('第 1 轮'));
      final corners = (
        rect.topLeft + const Offset(13, 12),
        rect.bottomRight - const Offset(13, 10),
      );
      for (final (from, to) in [corners, (corners.$2, corners.$1)]) {
        final drag = await tester.startGesture(
          from,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await drag.moveTo(to);
        await tester.pump();
        await drag.up();
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(copied, original.replaceAll('`', ' '));
        await tester.pump(const Duration(milliseconds: 500));
      }
    });

    testWidgets('a turn\'s message sticks to the top, pushed off by the next', (
      tester,
    ) async {
      await pumpScreen(tester, historyCount: 24);
      // Turn 3, then turn 2 just above it.
      await reveal(tester, '第 3 轮');
      await reveal(tester, '第 2 轮');
      final list = tester.getRect(find.byType(SuperListView));
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(SuperListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      final stuck = find.descendant(
        of: find.byType(ChatHistoryView),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is UserMessageBubble &&
              widget.key == const ValueKey(('sticky', 8)),
        ),
      );

      // In place, near the top: its copy (built, ready) does not show.
      final own = tester.getTopLeft(bubble('第 2 轮')).dy - list.top;
      position.jumpTo(position.pixels + own - 40);
      await tester.pump();
      await tester.pump();
      expect(stuck, findsOneWidget);
      expect(stuck.hitTestable(), findsNothing);

      // Scrolled past: its copy at the top, in the same frame.
      position.jumpTo(position.pixels + 60);
      await tester.pump();
      expect(stuck.hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(stuck).dy, list.top + 8);
      final stuckAt = position.pixels;

      // The next message, arriving, pushes it up: the copy's fade ends at it.
      while (bubble('第 3 轮').evaluate().isEmpty ||
          tester.getTopLeft(bubble('第 3 轮')).dy > list.bottom) {
        position.jumpTo(position.pixels + 200);
        await tester.pump();
      }
      final next = tester.getTopLeft(bubble('第 3 轮')).dy;
      position.jumpTo(position.pixels + next - list.top - 40);
      await tester.pump();
      expect(
        tester.getTopLeft(bubble('第 3 轮')).dy,
        closeTo(list.top + 40, 0.01),
      );
      expect(tester.getTopLeft(stuck).dy, lessThan(list.top + 8));
      expect(tester.getBottomLeft(stuck).dy + 16, closeTo(list.top + 40, 0.01));

      // Clicked, it opens the message to edit, stuck to the top in its place.
      position.jumpTo(stuckAt);
      await tester.pump();
      await tester.tap(stuck);
      await tester.pump();
      await tester.pump();
      expect(stuck, findsNothing);
      expect(editController(tester).document.toPlainText(), contains('第 2 轮'));
    });

    testWidgets('the editor sticks to the top while scrolled past', (
      tester,
    ) async {
      await pumpScreen(tester);
      await reveal(tester, '第 2 轮');
      await tester.tap(bubble('第 2 轮'));
      await tester.pump();
      await tester.pump();
      // The editor opens over a moment.
      await tester.pump(const Duration(milliseconds: 300));
      final list = tester.getRect(find.byType(SuperListView));
      final composer = find.descendant(
        of: find.byType(ChatHistoryView),
        matching: find.byType(ChatComposer),
      );
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(SuperListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;

      // In place: where the message was (brought down from the very top).
      position.jumpTo(position.pixels - 120);
      await tester.pump();
      final start = position.pixels;
      final inPlace = tester.getTopLeft(composer).dy;
      expect(inPlace, greaterThan(list.top + 8));

      // Scrolled past: pinned just below the top of the list.
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(tester.getTopLeft(composer).dy, list.top + 8);
      // Still usable there: the wheel over it scrolls the list.
      final wheel = TestPointer(7, PointerDeviceKind.mouse);
      wheel.hover(tester.getCenter(composer));
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, -30)));
      await tester.pump();
      expect(position.pixels, lessThan(position.maxScrollExtent));

      // Back: in place again.
      position.jumpTo(start);
      await tester.pump();
      expect(tester.getTopLeft(composer).dy, inPlace);
    });

    testWidgets('a click outside the editor cancels, its menus do not', (
      tester,
    ) async {
      await pumpScreen(tester);
      await reveal(tester, '第 2 轮');
      await tester.tap(bubble('第 2 轮'));
      await tester.pump();
      await tester.pump();
      // The editor opens over a moment.
      await tester.pump(const Duration(milliseconds: 300));
      final editPicker = find
          .descendant(
            of: find.byType(ChatHistoryView),
            matching: find.byType(ComposerPicker),
          )
          .first;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(editPicker));
      await mouse.down(tester.getCenter(editPicker));
      await mouse.up();
      await settleAnimations(tester);
      final plan = find.text('Research and plan, then build');
      await mouse.moveTo(tester.getCenter(plan));
      await mouse.down(tester.getCenter(plan));
      await mouse.up();
      await settleAnimations(tester);
      expect(editorInHistory(), findsOneWidget);
      expect(
        find.descendant(of: editPicker, matching: find.text('Plan')),
        findsOneWidget,
      );

      // The title bar is outside.
      await mouse.moveTo(const Offset(400, 10));
      await mouse.down(const Offset(400, 10));
      await mouse.up();
      await tester.pump();
      expect(editorInHistory(), findsNothing);
      expect(bubble('第 2 轮'), findsOneWidget);
      await mouse.removePointer();
    });

    testWidgets('a long message shows its first lines, all of it to edit', (
      tester,
    ) async {
      // Turn 3 carries a long request; turn 2 is short.
      final session = await pumpScreen(tester, historyCount: 24);
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final long = (session.itemAt(16) as UserMessageItem).text;
      expect(long, contains('7. 改完后简要说明取舍'));
      Finder expandIcon(Finder of) => find.descendant(
        of: of,
        matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
      );

      await reveal(tester, '第 3 轮');
      final longBubble = bubble('第 3 轮');
      // Three lines of text, plus the bubble's padding and border.
      expect(tester.getSize(longBubble).height, 13.5 * 1.5 * 3 + 10 + 11 + 2);
      expect(expandIcon(longBubble), findsOneWidget);

      // A short one is not cut: as tall as its text. (Its overlay is built
      // but not painted.)
      await reveal(tester, '第 2 轮');
      final shortBubble = bubble('第 2 轮');
      final text = find.descendant(
        of: shortBubble,
        matching: find.byType(RichText),
      );
      expect(
        tester.getSize(shortBubble).height,
        tester.getSize(text.first).height + 10 + 11 + 2,
      );

      // The hidden lines still copy. (Focusing the history below the
      // message: a click on it would edit it.)
      await tester.tapAt(
        tester.getBottomLeft(shortBubble) + const Offset(40, 40),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(copied, contains('7. 改完后简要说明取舍'));

      // Clicking edits the whole message.
      await reveal(tester, '第 3 轮');
      await tester.tapAt(
        tester.getTopLeft(bubble('第 3 轮')) + const Offset(20, 14),
      );
      await tester.pump();
      await tester.pump();
      // The editor opens over a moment.
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        editController(tester).document.toPlainText(),
        contains('7. 改完后简要说明取舍'),
      );
    });

    testWidgets('a collapsed message shows no text below its fade', (
      tester,
    ) async {
      // Real glyphs (the test font's blocks sit well inside the line and
      // never reach the clip edge): CJK text reaches near the line's top.
      await tester.runAsync(() async {
        final font = File(
          '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
        );
        if (!font.existsSync()) return;
        await (FontLoader('Roboto')..addFont(
              Future.value(ByteData.sublistView(font.readAsBytesSync())),
            ))
            .load();
      });
      // 2x, like a Retina display, at fractional scroll offsets: the clip
      // edge lands mid-pixel.
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await pumpScreen(tester, historyCount: 24);
      await reveal(tester, '第 3 轮');
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ChatHistoryView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
      for (var step = 0; step < 6; step++) {
        position.jumpTo(position.pixels - 0.3);
        await tester.pump();
        // From the (possibly partial) row at the clip edge, where the fade
        // has ended, to the bottom border: the bubble's own color only
        // (#262626; text is #CCCCCC).
        final rect = tester.getRect(bubble('第 3 轮'));
        final clipBottom = rect.bottom - 1 - 11;
        final band = Rect.fromLTRB(
          (rect.left + 12) * 2,
          (clipBottom * 2).floorToDouble(),
          (rect.right - 12) * 2,
          ((rect.bottom - 2) * 2).floorToDouble(),
        );
        final image = (await tester.runAsync(() => layer.toImage(band)))!;
        final bytes = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        // Skipping the expand icon, centered at the bottom.
        final width = band.width.toInt();
        final iconFrom = width ~/ 2 - 24;
        final iconTo = width ~/ 2 + 24;
        var brightest = 0;
        for (var i = 0; i < bytes.lengthInBytes; i += 4) {
          final x = (i ~/ 4) % width;
          if (x >= iconFrom && x < iconTo) continue;
          brightest = math.max(brightest, bytes.getUint8(i));
        }
        expect(brightest, lessThanOrEqualTo(0x28), reason: 'step $step');
      }
    });

    testWidgets(
      'a trackpad pan over a scrolling editor never reaches the list',
      (tester) async {
        await pumpScreen(tester, historyCount: 40);
        final position = tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(ChatHistoryView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        Future<void> pan(Offset at, double dy, {int steps = 10}) async {
          final pointer = TestPointer(9, PointerDeviceKind.trackpad);
          final start = tester.binding.clock.now().microsecondsSinceEpoch;
          Duration now() => Duration(
            microseconds:
                tester.binding.clock.now().microsecondsSinceEpoch - start,
          );
          await tester.sendEventToBinding(pointer.panZoomStart(at));
          for (var i = 1; i <= steps; i++) {
            await tester.sendEventToBinding(
              pointer.panZoomUpdate(
                at,
                pan: Offset(0, dy * i / steps),
                timeStamp: now(),
              ),
            );
            await tester.pump(const Duration(milliseconds: 16));
          }
          await tester.sendEventToBinding(pointer.panZoomEnd(timeStamp: now()));
          await tester.pump();
        }

        // A short message: the text area cannot scroll, so the list does.
        position.jumpTo(0);
        await tester.pump();
        await reveal(tester, '第 2 轮');
        position.jumpTo(position.pixels - 60);
        await tester.pump();
        await tester.tap(bubble('第 2 轮'));
        await tester.pump();
        await tester.pump();
        // The editor opens over a moment.
        await tester.pump(const Duration(milliseconds: 300));
        var before = position.pixels;
        await pan(tester.getCenter(editorInHistory()), -80);
        expect(position.pixels, greaterThan(before + 40));
        // The fingers lifted mid-move: it carries on.
        final lifted = position.pixels;
        await tester.pump(const Duration(milliseconds: 100));
        expect(position.pixels, isNot(lifted));
        await tester.pump(const Duration(seconds: 2));
        await pressKey(tester, LogicalKeyboardKey.escape);

        // A long one: its text area scrolls first, then the list.
        await reveal(tester, '第 3 轮');
        position.jumpTo(position.pixels - 60);
        await tester.pump();
        await tester.tapAt(
          tester.getTopLeft(bubble('第 3 轮')) + const Offset(20, 14),
        );
        await tester.pump();
        await tester.pump();
        // The editor opens over a moment.
        await tester.pump(const Duration(milliseconds: 300));
        final inner = tester
            .state<ChatComposerState>(
              find.descendant(
                of: find.byType(ChatHistoryView),
                matching: find.byType(ChatComposer),
              ),
            )
            .editorScrollPosition!;
        expect(inner.maxScrollExtent, greaterThan(0));
        inner.jumpTo(0);
        await tester.pump();
        // Its text area scrolls, and stops at its end: the list never moves,
        // not even with the next pan.
        before = position.pixels;
        await pan(tester.getCenter(editorInHistory()), -400, steps: 20);
        expect(inner.pixels, inner.maxScrollExtent);
        await tester.pump(const Duration(seconds: 2));
        await pan(tester.getCenter(editorInHistory()), -100);
        await tester.pump(const Duration(seconds: 2));
        expect(position.pixels, before);
        expect(inner.pixels, inner.maxScrollExtent);
      },
    );

    testWidgets("the editor's own scrolling leaves the history scrollbar", (
      tester,
    ) async {
      await pumpScreen(tester, historyCount: 40);
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ChatHistoryView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      position.jumpTo(0);
      await tester.pump();
      await reveal(tester, '第 3 轮');
      await tester.tapAt(
        tester.getTopLeft(bubble('第 3 轮')) + const Offset(20, 14),
      );
      await tester.pump();
      await tester.pump();
      // The editor opens over a moment.
      await tester.pump(const Duration(milliseconds: 300));

      // Where the history scrollbar's thumb is, along its middle (4px in
      // from the right edge, 7px wide).
      final scrollbar = find
          .byWidgetPredicate(
            (widget) =>
                widget is CustomPaint &&
                widget.foregroundPainter is ScrollbarPainter,
          )
          .first;
      final list = tester.getRect(find.byType(ChatHistoryView));
      List<double> thumbRows() {
        final painter =
            tester.widget<CustomPaint>(scrollbar).foregroundPainter!
                as ScrollbarPainter;
        final origin = tester.getTopLeft(scrollbar);
        return [
          for (var y = list.top; y < list.bottom; y += 2)
            if (painter.hitTestOnlyThumbInteractive(
              Offset(list.right - 7, y) - origin,
              PointerDeviceKind.mouse,
            ))
              y,
        ];
      }

      await tester.pump(const Duration(milliseconds: 500));
      final before = thumbRows();
      expect(before, isNotEmpty);
      final inner = tester
          .state<ChatComposerState>(
            find.descendant(
              of: find.byType(ChatHistoryView),
              matching: find.byType(ChatComposer),
            ),
          )
          .editorScrollPosition!;
      expect(inner.maxScrollExtent, greaterThan(0));
      // The text area opens scrolled to the caret, at the end. Scrolling
      // it moves its own scrollbar only.
      expect(inner.pixels, inner.maxScrollExtent);
      inner.jumpTo(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(thumbRows(), before);

      // A wheel over it scrolls it while it can, not the list.
      inner.jumpTo(inner.maxScrollExtent);
      await tester.pump();
      final wheel = TestPointer(8, PointerDeviceKind.mouse);
      wheel.hover(tester.getCenter(editorInHistory()));
      final listBefore = position.pixels;
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, -10)));
      await tester.pump();
      expect(inner.pixels, lessThan(inner.maxScrollExtent));
      expect(position.pixels, listBefore);
      expect(thumbRows(), before);
    });
  });

  testWidgets('a finished thought shows without its trailing blank lines', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThinkingSection(
            text: 'Checking the layout.\n\n',
            seconds: 2,
            expanded: true,
            onToggle: () {},
          ),
        ),
      ),
    );
    expect(find.text('Checking the layout.'), findsOneWidget);
    expect(find.text('Thought 2s', findRichText: true), findsOneWidget);
  });
}
