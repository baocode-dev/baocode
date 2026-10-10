import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

/// Text left on the selection's list that is no longer there, far below:
/// any edge put to it stays on it.
class _LeftOver extends ChangeNotifier with Selectable {
  @override
  Size get size => const Size(10, 10);
  @override
  List<Rect> get boundingBoxes => [Offset.zero & size];
  @override
  Matrix4 getTransformTo(RenderObject? ancestor) =>
      Matrix4.translationValues(0, 5000, 0);
  @override
  SelectionGeometry get value =>
      const SelectionGeometry(status: SelectionStatus.none, hasContent: true);
  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) =>
      event is SelectionEdgeUpdateEvent
      ? SelectionResult.previous
      : SelectionResult.none;
  @override
  SelectedContent? getSelectedContent() => null;
  @override
  SelectedContentRange? getSelection() => null;
  @override
  int get contentLength => 0;
  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {}
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
  bool get canEditMessages => false;
  @override
  ({int index, ComposerDraft draft})? get editing => null;
  @override
  set editing(({int index, ComposerDraft draft})? value) {}
  @override
  void editMessage(int index, ComposerMessage message) {}
  @override
  void cancelQueued(int index) {}
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
      final delegate = tester
          .widgetList<SelectionContainer>(
            find.ancestor(
              of: find.byType(SuperListView),
              matching: find.byType(SelectionContainer),
            ),
          )
          .map((container) => container.delegate)
          .whereType<StaticSelectionContainerDelegate>()
          .first;

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
        expect(
          paragraph(first).selections
              .any((selection) => !selection.isCollapsed),
          isTrue,
        );
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

  testWidgets('a drag on text that selects nothing is done again on a '
      'clean list, and reported', (tester) async {
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
    final feed = _Feed([
      const UserMessageItem(text: 'Why does it fail?'),
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
    // The history's own selection, around the list's items.
    final delegate = tester
        .widgetList<SelectionContainer>(
          find.ancestor(
            of: find.byType(SuperListView),
            matching: find.byType(SelectionContainer),
          ),
        )
        .map((container) => container.delegate)
        .whereType<StaticSelectionContainerDelegate>()
        .first;
    // ignore: invalid_use_of_protected_member
    delegate.selectables.insert(0, _LeftOver());

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
    expect(
      tester.takeException().toString(),
      contains('A drag on text selected nothing (selected done again)'),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(copied, answer);
  });
}
