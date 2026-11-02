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
import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/theme/app_theme.dart';

class _Feed extends ChangeNotifier implements ChatFeed {
  _Feed(this.items);

  final List<ChatItem> items;

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

/// A reply of 60 paragraphs, some 19,000 characters: thousands of pixels
/// tall, in segments of its own (see markdownSegments).
final _reply = [
  for (var i = 0; i < 60; i++) 'Paragraph $i: ${'word ' * 60}'.trimRight(),
].join('\n\n');

void main() {
  String? copied;
  setUp(() {
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  final historyKey = GlobalKey();

  Future<void> show(WidgetTester tester) async {
    final feed = _Feed([
      const UserMessageItem(text: 'Tell me all of it.'),
      AssistantTextItem(_reply),
    ]);
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ChatHistoryView(key: historyKey, feed: feed),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ScrollPosition list(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ChatHistoryView),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  Future<void> copy(WidgetTester tester, {bool all = false}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (all) await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
  }

  testWidgets('a long reply lets go of what is far out of view, as tall, '
      'and has it again as it comes back', (tester) async {
    await show(tester);
    expect(find.textContaining('Paragraph 59:'), findsOneWidget);
    expect(find.textContaining('Paragraph 0:'), findsNothing);
    final height = tester.getSize(find.byType(MarkdownView)).height;
    expect(height, greaterThan(3 * 2400));

    list(tester).jumpTo(0);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Paragraph 0:'), findsOneWidget);
    // The last segment, which may still be written, stays.
    expect(find.textContaining('Paragraph 40:'), findsNothing);
    expect(tester.getSize(find.byType(MarkdownView)).height, height);
  });

  testWidgets('Select All copies the segments let go of', (tester) async {
    await show(tester);
    expect(find.textContaining('Paragraph 0:'), findsNothing);
    final mouse = await tester.startGesture(
      tester.getCenter(find.textContaining('Paragraph 59:')),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 500));
    await copy(tester, all: true);
    expect(copied, startsWith('Tell me all of it.'));
    for (final i in [0, 1, 30, 58]) {
      expect(copied, contains('Paragraph $i: word word'));
    }
    expect(copied, endsWith('Paragraph 59: ${'word ' * 60}'.trimRight()));
  });

  testWidgets('the text a selection ends in is kept as it scrolls away', (
    tester,
  ) async {
    await show(tester);
    final position = list(tester);
    position.jumpTo(position.maxScrollExtent / 2);
    await tester.pump();
    await tester.pump();
    // A paragraph halfway, on screen.
    final paragraph = tester
        .renderObjectList<RenderParagraph>(
          find.byWidgetPredicate(
            (widget) =>
                widget is RichText &&
                widget.text.toPlainText().startsWith('Paragraph '),
          ),
        )
        .firstWhere((paragraph) {
          final top = paragraph.localToGlobal(Offset.zero).dy;
          return top > 50 && top < 400;
        });
    final name = paragraph.text.toPlainText().split(':').first;
    final mouse = await tester.startGesture(
      paragraph.localToGlobal(const Offset(0.5, 8)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(paragraph.localToGlobal(const Offset(300, 8)));
    await tester.pump();
    await mouse.up();
    await tester.pump();
    await copy(tester);
    final selected = copied;
    expect(selected, startsWith('$name: word'));

    // Thousands of pixels away: let go of, but for the selection's end.
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('$name:'), findsOneWidget);
    copied = null;
    await copy(tester);
    expect(copied, selected);

    // Once nothing is selected, it goes.
    await tester.tapAt(tester.getCenter(find.textContaining('Paragraph 59:')));
    await tester.pump(const Duration(milliseconds: 500));
    position.jumpTo(position.maxScrollExtent - 1);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('$name:'), findsNothing);
  });

  testWidgets('the find\'s match at hand in a segment let go of is shown', (
    tester,
  ) async {
    await show(tester);
    expect(find.textContaining('Paragraph 3:'), findsNothing);
    ChatHistoryView.find(historyKey, query: 'paragraph 3:');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final view = tester.getRect(find.byType(ChatHistoryView));
    final shown = find.textContaining('Paragraph 3:', findRichText: true);
    expect(shown, findsOneWidget);
    final rect = tester.getRect(shown);
    expect(rect.top >= view.top && rect.top < view.bottom, isTrue);
  });
}
