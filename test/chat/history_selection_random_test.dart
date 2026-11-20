// Random runs of what a conversation goes through (turns streaming in and
// folding, notices, a narrower or wider window, scrolling), each followed
// now and then by a drag across the last answer and a copy: what is copied
// is the answer's text, whatever came before.
//
// A highlight that copied nothing came of such a history on a user's
// machine, the selection's copy of where its ends were out of step with the
// text's own; one run of steps no test had taken.

import 'dart:math';

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

class _Feed extends ChangeNotifier implements ChatFeed {
  List<ChatItem> items = [];
  bool streaming = false;

  void update(List<ChatItem> next) {
    items = next;
    notifyListeners();
  }

  @override
  int get itemCount => items.length;
  @override
  ChatItem itemAt(int index) => items[index];
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

/// Drags across [answer] where it shows and copies; null when it is not
/// on screen.
Future<String?> _copyAcross(WidgetTester tester, String answer) async {
  final found = find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText() == answer,
  );
  if (found.evaluate().isEmpty) return null;
  final paragraph = tester.renderObject<RenderParagraph>(found.first);
  final box = paragraph.localToGlobal(Offset.zero) & paragraph.size;
  if (box.top < 20 || box.bottom > 560) return null;
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
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  return copied ?? '';
}

void main() {
  for (var seed = 0; seed < 8; seed++) {
    testWidgets('random history $seed: the last answer copies', (tester) async {
      final random = Random(seed);
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(900, 600);
      addTearDown(tester.view.reset);
      final items = <ChatItem>[];
      final feed = _Feed();
      addTearDown(feed.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: ChatHistoryView(feed: feed)),
        ),
      );
      Future<void> wait() => tester.pump(
        Duration(milliseconds: const [0, 16, 100, 400][random.nextInt(4)]),
      );
      var turn = 0;
      String? answer;
      final steps = <String>[];
      var checked = 0;
      for (var step = 0; step < 40; step++) {
        switch (random.nextInt(7)) {
          case 0 || 1:
            turn++;
            steps.add('turn $turn');
            final question = 'Question $turn';
            items.add(UserMessageItem(text: question));
            feed.streaming = true;
            feed.update([...items, const LiveStatusItem('Planning next move')]);
            await wait();
            for (var i = random.nextInt(4); i > 0; i--) {
              items.add(
                random.nextBool()
                    ? ThinkingItem(text: 'Hm $turn $i.', tokens: 2, seconds: 1)
                    : ToolCallItem(
                        kind: ToolKind.read,
                        target: 'f$turn$i.dart',
                      ),
              );
              feed.update([
                ...items,
                LiveStatusItem(
                  'Planning next move',
                  visible: random.nextBool(),
                ),
              ]);
              await wait();
            }
            final text = 'Answer number $turn is here.';
            items.add(AssistantTextItem(text));
            feed.update([
              ...items,
              const LiveStatusItem('Planning next move', visible: false),
            ]);
            await wait();
            final prompt = items.indexWhere(
              (item) => item is UserMessageItem && item.text == question,
            );
            items[prompt] = UserMessageItem(
              text: question,
              worked: Duration(seconds: 5 + turn),
            );
            feed.streaming = false;
            feed.update([...items]);
            answer = text;
          case 2:
            steps.add('notice');
            items.add(const NoticeItem(NoticeKind.info, 'Something happened'));
            feed.update([...items]);
          case 3:
            final width = 500.0 + random.nextInt(800);
            steps.add('width $width');
            tester.view.physicalSize = Size(width, 600);
          case 4:
            steps.add('scroll up');
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, 300),
              kind: PointerDeviceKind.trackpad,
            );
          case 5:
            steps.add('scroll down');
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, -2000),
              kind: PointerDeviceKind.trackpad,
            );
          case _:
            steps.add('wait');
        }
        await wait();
        await tester.pump(const Duration(seconds: 1));
        if (answer == null || random.nextInt(3) != 0) continue;
        final copied = await _copyAcross(tester, answer);
        if (copied == null) continue;
        checked++;
        expect(copied, answer, reason: steps.join(' > '));
      }
      expect(checked, greaterThan(0));
    });
  }
}
