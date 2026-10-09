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
