// Tests of words streaming into a turn under way: they show together, a
// few times a second, not each on its own; what else changes shows at once.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/theme/app_theme.dart';

/// A turn under way: a question, its answer so far, the status row.
class _LiveFeed extends ChangeNotifier implements ChatFeed {
  final List<ChatItem> items = [
    const UserMessageItem(text: 'A question'),
    const AssistantTextItem('word0'),
  ];

  /// A word more in the answer.
  void write(int n) {
    final answer = items.last as AssistantTextItem;
    items.last = AssistantTextItem('${answer.text} word$n');
    notifyListeners();
  }

  void add(ChatItem item) {
    items.add(item);
    notifyListeners();
  }

  @override
  int get itemCount => items.length + 1;

  @override
  ChatItem itemAt(int index) => index < items.length
      ? items[index]
      : const LiveStatusItem('Planning next move', visible: false);

  @override
  bool get isStreaming => true;

  @override
  bool get isUnprompted => false;

  @override
  bool get canEditMessages => false;

  @override
  ({int index, ComposerDraft draft})? editing;

  @override
  void editMessage(int index, ComposerMessage message) {}

  @override
  VoidCallback? moveToBackgroundAt(int index) => null;

  @override
  VoidCallback? stopAt(int index) => null;
}

/// The feed shown, and how many times its view has been built since.
Future<(_LiveFeed, int Function())> _pump(WidgetTester tester) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(800, 600);
  addTearDown(tester.view.reset);
  final feed = _LiveFeed();
  addTearDown(feed.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: ChatHistoryView(feed: feed)),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  var built = 0;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    if (element.widget is ChatHistoryView) built++;
  };
  addTearDown(() => debugOnRebuildDirtyWidget = null);
  return (feed, () => built);
}

Finder _text(String text) => find.textContaining(text, findRichText: true);

void main() {
  testWidgets('words streaming in show together, a dozen times a second at '
      'most; the first after a pause at once, the last soon after', (
    tester,
  ) async {
    final (feed, built) = await _pump(tester);

    feed.write(1);
    await tester.pump();
    expect(built(), 1);
    expect(_text('word1'), findsOneWidget);

    // 30 words, 10 ms apart: 300 ms.
    for (var n = 2; n <= 31; n++) {
      feed.write(n);
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(built(), inInclusiveRange(4, 6));
    await tester.pump(const Duration(milliseconds: 66));
    expect(_text('word31'), findsOneWidget);
  });

  testWidgets('an item coming while words wait shows at once, the words '
      'with it', (tester) async {
    final (feed, built) = await _pump(tester);
    feed.write(1);
    await tester.pump();
    feed.write(2);
    await tester.pump();
    expect(built(), 1);
    expect(_text('word2'), findsNothing);

    feed.add(const AssistantTextItem('Another part'));
    await tester.pump();
    expect(built(), 2);
    expect(_text('word2'), findsOneWidget);
    expect(_text('Another part'), findsOneWidget);
  });

  testWidgets('behind another window, words show a few times a second', (
    tester,
  ) async {
    final (feed, built) = await _pump(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );

    for (var n = 1; n <= 30; n++) {
      feed.write(n);
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(built(), inInclusiveRange(1, 2));
    await tester.pump(const Duration(milliseconds: 250));
    expect(_text('word30'), findsOneWidget);
  });
}
