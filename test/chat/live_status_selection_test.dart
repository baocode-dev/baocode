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

/// A live turn, changed by hand.
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
  @override
  bool get isStreaming => true;
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
}
