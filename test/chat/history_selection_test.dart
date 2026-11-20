import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/selection/chat_selection.dart';
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/chat/widgets/step_header.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

/// The conversation's selection, as a test reads it.
class _Selection {
  _Selection(this.tester);

  final WidgetTester tester;

  ChatSelectionController get _controller => tester
      .renderObject<RenderChatSelectionItem>(
        find.byType(ChatSelectionItem).first,
      )
      .controller;

  SelectedContent? getSelectedContent() => switch (_controller.selectedText()) {
    final text? => SelectedContent(plainText: text),
    null => null,
  };
}

/// Whether some of [paragraph]'s text shows selected.
bool _shown(RenderParagraph paragraph) {
  RenderObject? node = paragraph.parent;
  while (node != null && node is! RenderChatSelectionItem) {
    node = node.parent;
  }
  return node is RenderChatSelectionItem && node.showsSelected(paragraph);
}

/// A conversation, changed by hand.
class _Feed extends ChangeNotifier implements ChatFeed {
  _Feed(this.items);

  List<ChatItem> items;

  void update(List<ChatItem> next) {
    items = next;
    notifyListeners();
  }

  @override
  int get itemCount => items.length;
  @override
  ChatItem itemAt(int index) => items[index];
  bool streaming = true;

  @override
  bool get isStreaming => streaming;

  @override
  bool get isUnprompted => false;
  @override
  bool get canEditMessages => false;
  @override
  ({int index, ComposerDraft draft})? get editing => null;
  @override
  set editing(({int index, ComposerDraft draft})? value) {}
  @override
  void editMessage(int index, ComposerMessage message, {UserPlace? from}) {}
  @override
  VoidCallback? moveToBackgroundAt(int index) => null;
  @override
  VoidCallback? stopAt(int index) => null;
}

void main() {
  testWidgets('a selection holds while the status row changes under it', (
    tester,
  ) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    const answer = 'The parser drops the last token.';
    final steps = <ChatItem>[
      const UserMessageItem(text: 'Why does it fail?'),
      const AssistantTextItem(answer),
    ];
    final feed = _Feed([...steps, const LiveStatusItem('Reading parser.dart')]);
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == answer,
      ),
    );
    final mouse = await tester.startGesture(
      paragraph.localToGlobal(Offset(0.5, paragraph.size.height / 2)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(
      paragraph.localToGlobal(
        Offset(paragraph.size.width - 0.5, paragraph.size.height / 2),
      ),
    );
    await tester.pump();
    await mouse.up();
    await tester.pump();

    // Steps come in while the answer stays selected: the status row below
    // them moves down and says what comes next, both in one frame.
    for (var i = 0; i < 3; i++) {
      steps.add(ToolCallItem(kind: ToolKind.read, target: 'file$i.dart'));
      feed.update([...steps, LiveStatusItem('Reading file$i.dart')]);
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(copied, answer);
  });

  testWidgets('replacing selected code keeps later conversation text '
      'selectable', (tester) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    const code = 'final count = 42;';
    const answer = 'The count is now available.';
    final feed = _Feed([
      const UserMessageItem(text: 'What is the count?'),
      const AssistantTextItem('```dart\n$code\n```'),
    ])..streaming = false;
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> copy() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
    }

    Future<void> selectAndCopy(String text) async {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(SuperListView),
          matching: find.byWidgetPredicate(
            (widget) => widget is RichText && widget.text.toPlainText() == text,
          ),
        ),
      );
      final start = paragraph.localToGlobal(
        Offset(1, paragraph.size.height / 2),
      );
      final mouse = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await mouse.moveTo(
        paragraph.localToGlobal(
          Offset(paragraph.size.width - 1, paragraph.size.height / 2),
        ),
      );
      await tester.pump();
      await mouse.up();
      await tester.pump();
      await copy();
      expect(copied, text);
    }

    await selectAndCopy(code);
    feed.update([
      const UserMessageItem(text: 'What is the count?'),
      const AssistantTextItem('```dart\n$code\n```'),
      const LiveStatusItem('Working'),
    ]);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(tester.takeException(), isNull);
    copied = null;
    await copy();
    expect(copied, code);

    feed.update([
      const UserMessageItem(text: 'What is the count?'),
      const AssistantTextItem(answer),
    ]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await selectAndCopy(answer);
    await selectAndCopy('What is the count?');
  });

  for (final paragraphs in [1, 40]) {
    testWidgets('a $paragraphs-paragraph plan preview does not capture '
        'selection in later replies', (tester) async {
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      const before = 'Earlier reply is selectable.';
      const after = 'Later reply should be selectable.';
      const last = 'The work is complete.';
      final feed = _Feed([
        const UserMessageItem(text: 'Please make a plan.'),
        const AssistantTextItem(before),
        PlanItem(
          path: '/tmp/plan.md',
          round: 2,
          title: 'The plan',
          status: PlanStatus.approved,
          text: [
            '# The plan',
            for (var i = 0; i < paragraphs; i++) 'Plan step $i.',
          ].join('\n\n'),
        ),
        const AssistantTextItem('$after\n\n$last'),
      ])..streaming = false;
      addTearDown(feed.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: ChatHistoryView(feed: feed)),
        ),
      );
      await tester.pumpAndSettle();
      final delegate = _Selection(tester);

      RenderParagraph paragraph(String text) =>
          tester.renderObject<RenderParagraph>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is RichText && widget.text.toPlainText() == text,
            ),
          );
      Offset point(String text, {bool end = false}) {
        final render = paragraph(text);
        final boxes = render.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length),
        );
        final box = (end ? boxes.last : boxes.first).toRect();
        return render.localToGlobal(
          Offset(end ? box.right - 0.5 : box.left + 0.5, box.center.dy),
        );
      }

      Future<void> copy(String expected) async {
        copied = null;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        expect(copied, expected);
        expect(tester.takeException(), isNull);
      }

      Future<void> drag(
        String first,
        String last,
        String expected, {
        bool reverse = false,
      }) async {
        final start = point(first);
        final end = point(last, end: true);
        final mouse = await tester.startGesture(
          reverse ? end : start,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await mouse.moveTo(reverse ? start : end);
        await tester.pump();
        // Before release: the history's empty-drag retry must not be needed.
        expect(delegate.getSelectedContent()?.plainText, expected);
        expect(_shown(paragraph(first)), isTrue);
        await mouse.up();
        await tester.pump();
        await copy(expected);
      }

      for (final reverse in [false, true]) {
        for (final text in [before, 'Plan step 0.', after]) {
          await drag(text, text, text, reverse: reverse);
        }
        await drag(after, last, '$after\n$last', reverse: reverse);
      }

      // A word in the later reply must not select an invisible plan word.
      final render = paragraph(after);
      final word = render
          .getBoxesForSelection(
            const TextSelection(baseOffset: 6, extentOffset: 11),
          )
          .first
          .toRect();
      final position = render.localToGlobal(word.center);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(position, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(position, kind: PointerDeviceKind.mouse);
      await tester.pump();
      await copy('reply');

      // The hidden layout used to move with the plan, covering later replies
      // even after a scroll or a change of column width.
      tester.view.physicalSize = const Size(520, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<SuperListView>(find.byType(SuperListView))
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await drag(after, after, after);
      await drag(after, after, after, reverse: true);
    });
  }

  testWidgets('a drag on the text below a code block, begun left of the '
      'code, selects that text alone', (tester) async {
    const after = 'The parser drops the last token.';
    final feed = _Feed([
      const UserMessageItem(text: 'Why does it fail?'),
      const AssistantTextItem(
        'It reads:\n\n```dart\nfinal token = next(); // the last one\n```'
        '\n\n$after',
      ),
    ])..streaming = false;
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pumpAndSettle();
    final delegate = _Selection(tester);
    RenderParagraph paragraphOf(String text) =>
        tester.renderObject<RenderParagraph>(
          find.byWidgetPredicate(
            (widget) =>
                widget is RichText &&
                widget.text.toPlainText().startsWith(text),
          ),
        );
    final paragraph = paragraphOf(after);
    final from = paragraph.localToGlobal(const Offset(0.5, 6));
    // The text begins left of the code (past its line numbers).
    expect(
      from.dx,
      lessThan(paragraphOf('final token').localToGlobal(Offset.zero).dx),
    );

    final mouse = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(
      paragraph.localToGlobal(Offset(paragraph.size.width - 0.5, 6)),
    );
    await tester.pump();
    await mouse.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(delegate.getSelectedContent()?.plainText, after);
  });

  testWidgets('a release the list did not see (the button let go outside '
      'the window) ends the drag: the wheel then leaves the selection', (
    tester,
  ) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final feed = _Feed([
      for (var n = 0; n < 30; n++) ...[
        UserMessageItem(text: 'Question $n?'),
        AssistantTextItem('Answer $n, a line of its own.'),
      ],
    ])..streaming = false;
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pumpAndSettle();

    const answer = 'Answer 27, a line of its own.';
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == answer,
      ),
    );
    final end = paragraph.localToGlobal(
      Offset(paragraph.size.width - 0.5, paragraph.size.height / 2),
    );
    final mouse = await tester.startGesture(
      paragraph.localToGlobal(Offset(0.5, paragraph.size.height / 2)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(end);
    await tester.pump();
    // No release comes; the mouse moves on with no button down.
    tester.binding.handlePointerEvent(
      PointerHoverEvent(
        position: end,
        kind: PointerDeviceKind.mouse,
        device: 1,
      ),
    );
    await tester.pump();
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: end,
        kind: PointerDeviceKind.mouse,
        device: 1,
        scrollDelta: const Offset(0, -300),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(copied, answer);
  });

  testWidgets('Select All copies the whole conversation, not only what is '
      'built of it', (tester) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final feed = _Feed([
      for (var i = 0; i < 60; i++) ...[
        UserMessageItem(text: 'Question $i?'),
        AssistantTextItem('Answer $i, at some length.\n\nAnd a second line.'),
      ],
    ])..streaming = false;
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pumpAndSettle();
    // At the end: the first answers are not built.
    expect(find.textContaining('Question 0?'), findsNothing);

    final last = tester.getCenter(find.textContaining('Answer 59,'));
    final mouse = await tester.startGesture(
      last,
      kind: PointerDeviceKind.mouse,
    );
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(copied, startsWith('Question 0?'));
    expect(copied, contains('Answer 30, at some length.'));
    expect(copied, endsWith('And a second line.'));
  });

  testWidgets('a selection holds while items come in above text that '
      'changes, in a scroll view or not', (tester) async {
    const answer = 'The parser drops the last token.';
    const head = <ChatItem>[
      UserMessageItem(text: 'Why does it fail?'),
      AssistantTextItem(answer),
    ];
    String table(int n) => '| a | b |\n|---|---|\n| cell $n | x |';
    final feed = _Feed([...head, AssistantTextItem(table(0))]);
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == answer,
      ),
    );
    final mouse = await tester.startGesture(
      paragraph.localToGlobal(Offset(0.5, paragraph.size.height / 2)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(
      paragraph.localToGlobal(
        Offset(paragraph.size.width - 0.5, paragraph.size.height / 2),
      ),
    );
    await tester.pump();
    await mouse.up();
    await tester.pump();

    // Each new step takes the place of what was there, which gets new text
    // in the same frame; the table's cell too, a step further down.
    for (var i = 1; i < 4; i++) {
      feed.update([
        ...head,
        for (var j = 0; j < i; j++)
          ToolCallItem(kind: ToolKind.read, target: 'file$j.dart'),
        AssistantTextItem(table(i)),
      ]);
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('text below an open diff with a line cut short is '
      'selectable', (tester) async {
    const answer = 'The parser drops the last token.';
    final feed = _Feed([
      const UserMessageItem(text: 'Fix the parser.'),
      CodeDiffItem(
        fileName: 'parser.dart',
        directory: 'lib',
        lines: [
          for (var i = 1; i <= 20; i++)
            DiffLine(
              i.isEven ? DiffLineType.added : DiffLineType.context,
              i,
              // Wider than the diff: cut short with an ellipsis.
              i == 3 ? 'final token = ${'x' * 300};' : 'line $i',
            ),
        ],
      ),
      const AssistantTextItem(answer),
    ])..streaming = false;
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pumpAndSettle();
    // The diff's card, taller than its box: what it scrolls to lies below
    // it, under the answer.
    expect(find.byType(StepBody), findsOneWidget);

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == answer,
      ),
    );
    final mouse = await tester.startGesture(
      paragraph.localToGlobal(Offset(0.5, paragraph.size.height / 2)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(
      paragraph.localToGlobal(
        Offset(paragraph.size.width - 0.5, paragraph.size.height / 2),
      ),
    );
    await tester.pump();
    // Selected as it is dragged, not only by the history's retry.
    expect(_shown(paragraph), isTrue);
    await mouse.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('a drag in an edit card\'s editor leaves the conversation\'s '
      'selection as it was', (tester) async {
    const answer = 'The parser drops the last token.';
    final feed = _Feed([
      const UserMessageItem(text: 'Fix the parser.'),
      CodeDiffItem(
        fileName: 'parser.dart',
        directory: 'lib',
        lines: [
          for (var i = 1; i <= 20; i++)
            DiffLine(
              i.isEven ? DiffLineType.added : DiffLineType.context,
              i,
              'line $i',
            ),
        ],
      ),
      const AssistantTextItem(answer),
    ])..streaming = false;
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == answer,
      ),
    );
    Future<void> drag(Offset from, Offset to) async {
      final mouse = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await mouse.moveTo(to);
      await tester.pump();
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 500));
    }

    final middle = paragraph.size.height / 2;
    final editor = tester.getRect(find.byType(StepBody));
    final below = paragraph.localToGlobal(
      Offset(paragraph.size.width / 2, middle + 40),
    );
    // From the editor's lines out past the answer: the editor's selection,
    // not the conversation's.
    await drag(editor.center, below);
    expect(_shown(paragraph), isFalse);

    // Nor does it clear one.
    await drag(
      paragraph.localToGlobal(Offset(0.5, middle)),
      paragraph.localToGlobal(Offset(paragraph.size.width - 0.5, middle)),
    );
    final selected = _Selection(tester).getSelectedContent()?.plainText;
    expect(selected, answer);

    await drag(editor.center, below);
    expect(_Selection(tester).getSelectedContent()?.plainText, selected);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.desktop());

  for (final composerFirst in [false, true]) {
    testWidgets('a drag on text holds as something else takes the focus '
        '(the composer focused first: $composerFirst)', (tester) async {
      const answer = 'The parser drops the last token of every line.';
      final feed = _Feed([
        const UserMessageItem(text: 'Fix the parser.'),
        const AssistantTextItem(answer),
      ])..streaming = false;
      addTearDown(feed.dispose);
      final elsewhere = FocusNode();
      addTearDown(elsewhere.dispose);
      // In use: a selection losing the focus is cleared only then.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Column(
              children: [
                Expanded(child: ChatHistoryView(feed: feed)),
                // A panel come up meanwhile, taking the focus (a question's).
                Focus(focusNode: elsewhere, child: const SizedBox(height: 40)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (composerFirst) {
        elsewhere.requestFocus();
        await tester.pump();
      }

      final paragraph = tester.renderObject<RenderParagraph>(
        find.byWidgetPredicate(
          (widget) => widget is RichText && widget.text.toPlainText() == answer,
        ),
      );
      Offset at(double x) =>
          paragraph.localToGlobal(Offset(x, paragraph.size.height / 2));
      final mouse = await tester.startGesture(
        at(0.5),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await mouse.moveTo(at(paragraph.size.width / 3));
      await tester.pump();
      elsewhere.requestFocus();
      await tester.pump();
      await mouse.moveTo(at(paragraph.size.width - 0.5));
      await tester.pump();
      expect(_shown(paragraph), isTrue);
      await mouse.up();
      await tester.pump();
      expect(_shown(paragraph), isTrue);
      // Focused again, for the keys to copy it.
      expect(elsewhere.hasFocus, isFalse);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.desktop());
  }

  testWidgets('the end moves on as the pointer goes down past a list, '
      'beside it or over it', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 700);
    addTearDown(tester.view.reset);
    final feed = _Feed([
      const UserMessageItem(text: 'Lists'),
      AssistantTextItem(
        [
          // (Not numbers: in the tests' font a number is wider than its
          // column, and wraps.)
          'Bulleted:',
          '',
          for (var i = 1; i <= 4; i++) '- Point $i, `inline` and words.',
          '',
          'After the lists.',
        ].join('\n'),
      ),
    ])..streaming = false;
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pumpAndSettle();
    final controller = tester
        .renderObject<RenderChatSelectionItem>(
          find.byType(ChatSelectionItem).first,
        )
        .controller;
    for (final x in [4.0, 40.0, 300.0, 880.0]) {
      ChatTextPos? last;
      for (var y = 0.0; y < 700; y += 1) {
        final pos = controller.positionAt(Offset(x, y));
        if (pos == null) continue;
        if (last != null) {
          expect(pos < last, isFalse, reason: 'x $x, y $y: $last to $pos');
        }
        last = pos;
      }
    }
  });

  testWidgets('a selection in a long reply holds its text as the reply\'s '
      'segments let go of above it are built again', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 700);
    addTearDown(tester.view.reset);
    final reply = [
      for (var i = 0; i < 400; i++) 'Paragraph $i of the reply, some words.',
    ].join('\n\n');
    final feed = _Feed([
      const UserMessageItem(text: 'Long'),
      AssistantTextItem(reply),
    ])..streaming = false;
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pumpAndSettle();
    final controller = tester
        .renderObject<RenderChatSelectionItem>(
          find.byType(ChatSelectionItem).first,
        )
        .controller;
    final item = controller.builtItems[1]!;
    final before = item.leaves().length;
    RenderParagraph paragraph(int i) => tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text.toPlainText() == 'Paragraph $i of the reply, some words.',
      ),
    );
    final from = paragraph(395);
    final to = paragraph(397);
    final mouse = await tester.startGesture(
      from.localToGlobal(Offset(30, from.size.height / 2)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(to.localToGlobal(Offset(30, to.size.height / 2)));
    await tester.pump();
    await mouse.up();
    await tester.pump();
    final selected = controller.selectedText();
    expect(selected, contains('395 of the reply, some words.\nParagraph 396'));

    // Up to the reply's start and back: what was let go of comes back.
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(0);
    await tester.pumpAndSettle();
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(
      controller.builtItems[1]!.leaves().length,
      greaterThan(before),
      reason: 'segments let go of at the start, built again',
    );
    expect(controller.selectedText(), selected);
  });

  testWidgets('held above the list, it scrolls up without the text under '
      'the pointer leaping as rows above are laid out', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 700);
    addTearDown(tester.view.reset);
    // Rows of very different heights: their extents, estimated before
    // they are laid out, are corrected as they are.
    final feed = _Feed([
      for (var i = 0; i < 40; i++) ...[
        UserMessageItem(text: 'Question $i'),
        AssistantTextItem(
          [
            for (var j = 0; j < (i % 3 == 0 ? 40 : 2); j++)
              'Answer $i, line $j.',
          ].join('\n\n'),
        ),
      ],
    ])..streaming = false;
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Column(
            children: [
              const SizedBox(height: 50),
              Expanded(child: ChatHistoryView(feed: feed)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final controller = tester
        .renderObject<RenderChatSelectionItem>(
          find.byType(ChatSelectionItem).first,
        )
        .controller;
    Map<int, double> tops() => {
      for (final item in controller.builtItems.values)
        if (item.attached && item.hasSize)
          item.index: item.localToGlobal(Offset.zero).dy,
    };
    final mouse = await tester.startGesture(
      const Offset(450, 400),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(const Offset(450, 300));
    await tester.pump();
    await mouse.moveTo(const Offset(450, 30));
    var was = tops();
    for (var frame = 0; frame < 400; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final now = tops();
      for (final MapEntry(:key, :value) in now.entries) {
        if (was[key] case final top?) {
          expect(
            value - top,
            greaterThan(-1),
            reason: 'frame $frame: item $key went up ${top - value}',
          );
        }
      }
      was = now;
    }
    await mouse.up();
  });

  testWidgets('held past the list\'s bottom (on the composer), the end is '
      'on the line at the edge, not on hidden text beyond it', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 700);
    addTearDown(tester.view.reset);
    final feed = _Feed([
      for (var i = 0; i < 60; i++) ...[
        UserMessageItem(text: 'Question $i'),
        AssistantTextItem('Answer $i.\n\nAnd a second paragraph of it.'),
      ],
    ])..streaming = false;
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: ChatHistoryView(feed: feed)),
              const SizedBox(height: 150),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(position.maxScrollExtent / 2);
    await tester.pumpAndSettle();
    final controller = tester
        .renderObject<RenderChatSelectionItem>(
          find.byType(ChatSelectionItem).first,
        )
        .controller;
    const listBottom = 550.0;
    final mouse = await tester.startGesture(
      const Offset(450, 300),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(const Offset(450, 400));
    await tester.pump();
    await mouse.moveTo(const Offset(450, listBottom + 100));
    await tester.pump();
    final end = controller.globalOf(controller.focus!)!;
    expect(end.dy, lessThan(listBottom + 20));
    expect(end.dy, greaterThan(listBottom - 60));
    await mouse.up();
  });

  test('a piece holding an end gone (a header\'s second line), the end is '
      'between the pieces still there, not inside the next one', () {
    final header = _Piece('Used 4 tools · thought 1s');
    final second = _Piece('tabs 查看已共享的蓝鲸报表标签页');
    List<({RenderBox box, String text})> was(List<_Piece> pieces) => [
      for (final p in pieces) (box: p.box, text: p.text),
    ];
    // Gone, the last: the end of the one before it.
    expect(
      ChatSelectionController.placeAgain(
        const ChatTextPos(3, 1, 9),
        was([header, second]),
        [header],
      ),
      ChatTextPos(3, 0, header.text.length),
    );
    // Built anew in its place (its text changed): the same place in it.
    final again = _Piece('tabs 查看已共享的报表');
    expect(
      ChatSelectionController.placeAgain(
        const ChatTextPos(3, 1, 4),
        was([header, second]),
        [header, again],
      ),
      const ChatTextPos(3, 1, 4),
    );
    // Gone, the first: the start of the one after it.
    expect(
      ChatSelectionController.placeAgain(
        const ChatTextPos(3, 0, 7),
        was([header, second]),
        [second],
      ),
      const ChatTextPos(3, 0, 0),
    );
  });

  test('part of a piece copies its placeholders as they copy (a chip, a '
      'formula), not dropped', () {
    const text = ChatItemText([
      (
        text: 'see ￼ and ￼ here',
        copied: 'see [Image #1] and [Pasted text] here',
        join: '\n',
        placeholders: ['[Image #1]', '[Pasted text]'],
      ),
    ]);
    expect(
      text.copy(const ChatTextPos(0, 0, 0), const ChatTextPos(0, 0, 9)),
      'see [Image #1] and',
    );
    expect(
      text.copy(const ChatTextPos(0, 0, 6), null),
      'and [Pasted text] here',
    );
  });

  testWidgets('a press held while a reply streams in keeps the text under '
      'it still; a click lets the list follow again', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 700);
    addTearDown(tester.view.reset);
    final items = <ChatItem>[
      for (var i = 0; i < 20; i++) ...[
        UserMessageItem(text: 'Question $i'),
        AssistantTextItem('Answer $i.\n\nAnd a second paragraph of it.'),
      ],
    ];
    final feed = _Feed([...items]);
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.pixels, position.maxScrollExtent);
    var streamed = '';
    Future<void> streamOn() async {
      streamed += 'More words of the reply coming in. ' * 4;
      feed.update([...items, AssistantTextItem(streamed)]);
      await tester.pump(const Duration(milliseconds: 50));
    }

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == 'Answer 18.',
      ),
    );
    final at = paragraph.localToGlobal(Offset(4, paragraph.size.height / 2));
    final mouse = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await streamOn();
    }
    expect(paragraph.localToGlobal(Offset(4, paragraph.size.height / 2)), at);
    await mouse.up();
    await tester.pump();
    // A click, not a drag: what is written is followed again.
    for (var i = 0; i < 5; i++) {
      await streamOn();
    }
    expect(position.pixels, position.maxScrollExtent);
  });

  testWidgets('a drag held as a row above it gets shorter (steps folding, a '
      'thought closing) keeps the text under the pointer, and what it '
      'selects, where they were', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 700);
    addTearDown(tester.view.reset);
    final long = [
      for (var i = 0; i < 12; i++) 'Step $i of the work, done and told.',
    ].join('\n\n');
    List<ChatItem> items(String folded) => [
      for (var i = 0; i < 20; i++) ...[
        UserMessageItem(text: 'Question $i'),
        AssistantTextItem(
          i == 15 ? folded : 'Answer $i.\n\nAnd a second paragraph of it.',
        ),
      ],
    ];
    final feed = _Feed(items(long));
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    // Off the end: there, the list's end coming up would move it anyway.
    position.jumpTo(position.maxScrollExtent - 300);
    await tester.pumpAndSettle();
    RenderParagraph paragraphOf(String text) =>
        tester.renderObject<RenderParagraph>(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == text,
          ),
        );
    final paragraph = paragraphOf('Answer 17.');
    Offset under() =>
        paragraph.localToGlobal(Offset(4, paragraph.size.height / 2));
    final at = under();
    final mouse = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await mouse.moveBy(const Offset(0, 40));
    await tester.pump();
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    Future<String?> copy() async {
      copied = null;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      return copied;
    }

    final selected = await copy();
    expect(selected, startsWith('Answer 17.'));
    for (final folded in [
      long.substring(0, long.length ~/ 2),
      'Worked for 2m',
    ]) {
      feed.update(items(folded));
      await tester.pump();
      expect(under(), at);
      // Moved a little, the end lands where the pointer is, on the text it
      // was on.
      await mouse.moveBy(const Offset(0, 0.5));
      await tester.pump();
      await mouse.moveBy(const Offset(0, -0.5));
      await tester.pump();
      expect(await copy(), selected);
    }
    await mouse.up();
  });

  testWidgets("a selection started on the turn's status row stays on it as "
      'what the turn does comes in before it', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 700);
    addTearDown(tester.view.reset);
    final items = <ChatItem>[
      const UserMessageItem(text: 'Question'),
      const AssistantTextItem('A first part of the answer.'),
    ];
    const status = LiveStatusItem('Working on it');
    final feed = _Feed([...items, status]);
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final controller = tester
        .renderObject<RenderChatSelectionItem>(
          find.byType(ChatSelectionItem).first,
        )
        .controller;
    final label = tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().startsWith('Working'),
      ),
    );
    final at = label.localToGlobal(Offset(2, label.size.height / 2));
    final mouse = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(controller.anchor?.item, 2);
    feed.update([
      ...items,
      const AssistantTextItem('Another part, come in meanwhile.'),
      status,
    ]);
    await tester.pump();
    expect(controller.anchor?.item, 3);
    await mouse.up();
  });
}

/// A piece of text, in a box of its own.
class _Piece implements ChatTextLeaf {
  _Piece(this.text);

  @override
  final RenderBox box = RenderConstrainedBox(
    additionalConstraints: const BoxConstraints(),
  );

  @override
  final String text;

  @override
  String copyOf(int start, int end) => text.substring(start, end);

  @override
  int positionAt(Offset local) => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
