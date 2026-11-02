import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_find.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/chat/widgets/user_message_bubble.dart';
import 'package:baocode/ide/ide_find_widget.dart';
import 'package:baocode/theme/app_theme.dart';

class _Feed extends ChangeNotifier implements ChatFeed {
  _Feed(this.items);

  List<ChatItem> items;

  @override
  int get itemCount => items.length;

  @override
  ChatItem itemAt(int index) => items[index];

  @override
  bool get isStreaming => false;

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

/// Turn [n]: its message, steps that each read and say a word (folded
/// away once done), and its answer.
List<ChatItem> _turn(int n) => [
  UserMessageItem(text: 'Question $n', worked: const Duration(seconds: 65)),
  for (var i = 0; i < 6; i++) ...[
    ToolCallItem(kind: ToolKind.read, target: 't${n}_$i.dart'),
    AssistantTextItem('Turn $n step $i.'),
  ],
  AssistantTextItem('Answer **$n**.'),
];

final _historyKey = GlobalKey();

Future<void> _pump(
  WidgetTester tester,
  ChatFeed feed, {
  VoidCallback? onClosed,
}) async {
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ChatHistoryView(
          key: _historyKey,
          feed: feed,
          onFindClosed: onClosed,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _text(String text) => find.textContaining(text, findRichText: true);

/// Whether [finder]'s text is within the history's view.
bool _inView(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) return false;
  final view = tester.getRect(find.byType(ChatHistoryView));
  final rect = tester.getRect(finder.first);
  return rect.top >= view.top && rect.bottom <= view.bottom;
}

void main() {
  test('markdown is searched as it shows', () {
    final text = ChatFind.markdownText(
      '# Title\n\nSome **bold** `code` text<!-- hidden -->\n\n'
      '- one\n- two\n\n```dart\nfoo();\n```',
    );
    expect(text, contains('Title'));
    expect(text, contains('Some bold code text'));
    expect(text, isNot(contains('**')));
    expect(text, isNot(contains('hidden')));
    expect(text, contains('foo();'));
    expect(RegExp('one.two').hasMatch(text), isFalse);
  });

  testWidgets('a match folded away in a turn far up is opened and shown', (
    tester,
  ) async {
    await _pump(tester, _Feed([for (var n = 0; n < 30; n++) ..._turn(n)]));
    expect(_text('Turn 3 step 4.'), findsNothing);

    ChatHistoryView.find(_historyKey, query: 'turn 3 step 4');
    await _settle(tester);

    expect(find.byType(IdeFindWidget), findsOneWidget);
    expect(_inView(tester, _text('Turn 3 step 4.')), isTrue);
  });

  testWidgets('steps through the matches, each brought into view', (
    tester,
  ) async {
    await _pump(tester, _Feed([for (var n = 0; n < 30; n++) ..._turn(n)]));
    ChatHistoryView.find(_historyKey);
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'answer');
    await _settle(tester);
    // As the markdown shows: bold without its stars.
    expect(_inView(tester, _text('Answer 0.')), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(_inView(tester, _text('Answer 1.')), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter, platform: 'macos');
    await _settle(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await _settle(tester);
    expect(_inView(tester, _text('Answer 1.')), isTrue);
  });

  testWidgets('a search shown before the conversation is read back finds '
      'it once there', (tester) async {
    final feed = _Feed([]);
    await _pump(tester, feed);
    ChatHistoryView.find(_historyKey, query: 'turn 3 step 4');
    await tester.pump();
    // Read back as a burst of changes, each turn folding as the next comes.
    for (var n = 0; n < 30; n++) {
      for (final item in _turn(n)) {
        feed.items = [...feed.items, item];
        feed.notifyListeners();
      }
    }
    await _settle(tester);

    expect(_inView(tester, _text('Turn 3 step 4.')), isTrue);
  });

  testWidgets('a long message shows all of it while it holds the match at '
      'hand', (tester) async {
    final long = [for (var i = 0; i < 9; i++) 'Line $i'].join('\n');
    await _pump(
      tester,
      _Feed([UserMessageItem(text: long), AssistantTextItem('Line 8 again.')]),
    );
    double height() =>
        tester.getSize(find.byType(UserMessageBubble).first).height;
    final collapsed = height();

    ChatHistoryView.find(_historyKey, query: 'line 8');
    await _settle(tester);
    expect(height(), greaterThan(collapsed + 50));

    // The next match is the answer's: the message folds back.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(height(), collapsed);
  });

  testWidgets('Escape closes the bar, the focus going on', (tester) async {
    var closed = 0;
    await _pump(tester, _Feed(_turn(0)), onClosed: () => closed++);
    ChatHistoryView.find(_historyKey, query: 'Question');
    await tester.pump();
    expect(find.byType(IdeFindWidget), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(IdeFindWidget), findsNothing);
    expect(closed, 1);
  });
}
