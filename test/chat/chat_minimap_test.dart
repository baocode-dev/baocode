import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/chat/composer/composer_files.dart';
import 'package:baocode/chat/widgets/assistant_text.dart';
import 'package:baocode/chat/widgets/chat_minimap.dart';
import 'package:baocode/chat/widgets/hover_scrollbar.dart';
import 'package:baocode/chat/widgets/user_message_bubble.dart';
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
  void editMessage(int index, ComposerMessage message) {}

  @override
  VoidCallback? moveToBackgroundAt(int index) => null;

  @override
  VoidCallback? stopAt(int index) => null;
}

/// [turns] questions, each answered at length: with a heading, a list, a
/// code block and a table.
List<ChatItem> _conversation(int turns) => [
  for (var n = 0; n < turns; n++) ...[
    UserMessageItem(text: '问题 $n：这个函数为什么会在窄窗口下溢出？'),
    AssistantTextItem(
      '## Answer $n\n\n'
      '${'The column keeps its width while the pane shrinks. ' * 6}\n\n'
      '- first point\n- second point\n\n'
      '```dart\nfinal width = math.min(maxWidth, available);\n'
      '  return width;\n```\n\n'
      '| a | b |\n|---|---|\n| 1 | 2 |\n',
    ),
  ],
];

Future<void> _pump(
  WidgetTester tester,
  ChatFeed feed, {
  double width = 1200,
  double maxWidth = 720,
  bool minimap = true,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ChatHistoryView(
          feed: feed,
          maxContentWidth: maxWidth,
          minimap: minimap,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

Finder get _strip => find.descendant(
  of: find.byType(ChatMinimap),
  matching: find.byType(CustomPaint),
);

/// The minimap's track: its paint but the room either side for the glass,
/// which is a little wider.
Rect _track(WidgetTester tester) {
  final strip = tester.getRect(_strip);
  final outset = (strip.width - 24) / 2;
  expect(outset, greaterThan(0));
  return Rect.fromLTRB(
    strip.left + outset,
    strip.top,
    strip.right - outset,
    strip.bottom,
  );
}

double _opacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(ChatMinimap),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

Scrollbar _scrollbar(WidgetTester tester) =>
    tester.widget<Scrollbar>(find.byType(Scrollbar).first);

void main() {
  testWidgets('shows in the margin left of the column', (tester) async {
    await _pump(tester, _Feed(_conversation(30)));
    expect(_opacity(tester), 1);
    final strip = _track(tester);
    // The column is 720 wide in the middle of 1200 (less its gutters).
    expect(strip.right, lessThanOrEqualTo(240 - 16));
    expect(strip.left, greaterThanOrEqualTo(16));
    // However roomy the margin, as narrow.
    expect(strip.width, 24);
    // It stands in for the scrollbar.
    expect(_scrollbar(tester).interactive, isFalse);
  });

  for (final width in [1300.0, 790.0]) {
    testWidgets(
      'a column as wide as a ${width.round()} window leaves it room',
      (tester) async {
        await _pump(
          tester,
          _Feed(_conversation(30)),
          width: width,
          maxWidth: 1200,
        );
        expect(_opacity(tester), 1);
        final strip = _track(tester);
        final text = tester.getRect(find.byType(AssistantText).first);
        expect(strip.left, greaterThanOrEqualTo(12));
        // Room to breathe beside the text; none kept on the other side,
        // where the column is narrower than it could be.
        expect(strip.right, lessThanOrEqualTo(text.left - 20));
        expect(text.left, greaterThanOrEqualTo(ChatMinimap.room));
        if (width < 1200) {
          expect(width - text.right, lessThan(ChatMinimap.room));
        }
      },
    );
  }

  testWidgets('gives way in a very narrow pane only', (tester) async {
    await _pump(tester, _Feed(_conversation(30)), width: 600);
    expect(_opacity(tester), 1);
    await _pump(tester, _Feed(_conversation(30)), width: 380);
    expect(_opacity(tester), 0);
    // The scrollbar is back.
    expect(_scrollbar(tester).interactive, isTrue);
  });

  testWidgets('a table in the history keeps its bar while it shows', (
    tester,
  ) async {
    await _pump(tester, _Feed(_conversation(30)));
    expect(_opacity(tester), 1);
    // The list's own bar gives way to it...
    Color? thumb(Finder bar) =>
        ScrollbarTheme.of(tester.element(bar)).thumbColor?.resolve(const {});
    expect(thumb(find.byType(Scrollbar).first), Colors.transparent);
    // ...a table's, under it, not.
    final table = find.byType(HoverScrollbar).last;
    expect(table, findsOneWidget);
    expect(thumb(table), isNot(Colors.transparent));
  });

  testWidgets('not while all of the history shows', (tester) async {
    await _pump(tester, _Feed(_conversation(1)));
    expect(_opacity(tester), 0);
  });

  testWidgets('its room kept only once the history scrolls: until then the '
      'column is where it is without one', (tester) async {
    double textLeft() => tester.getRect(find.byType(AssistantText).first).left;
    await _pump(tester, _Feed(_conversation(1)), width: 790, maxWidth: 1200);
    final short = textLeft();
    await _pump(
      tester,
      _Feed(_conversation(1)),
      width: 790,
      maxWidth: 1200,
      minimap: false,
    );
    expect(short, textLeft());
    expect(short, lessThan(ChatMinimap.room));
    await _pump(tester, _Feed(_conversation(30)), width: 790, maxWidth: 1200);
    expect(_opacity(tester), 1);
    expect(textLeft(), greaterThanOrEqualTo(ChatMinimap.room));
  });

  testWidgets('not while the conversation is short, though it scrolls; once '
      'long, it stays as the history grows shorter (its steps folded)', (
    tester,
  ) async {
    // The fewest turns that scroll at all.
    var turns = 1;
    while (true) {
      await _pump(tester, _Feed(_conversation(turns)));
      if (_position(tester).maxScrollExtent > 0) break;
      turns++;
    }
    final position = _position(tester);
    expect(
      position.maxScrollExtent,
      lessThan(position.viewportDimension * ChatMinimap.longAfter),
    );
    expect(_opacity(tester), 0);

    final items = _conversation(30);
    final feed = _Feed(items);
    await _pump(tester, feed);
    expect(_opacity(tester), 1);
    items.removeRange(2 * turns, items.length);
    feed.notifyListeners();
    await tester.pumpAndSettle();
    expect(_position(tester).maxScrollExtent, greaterThan(0));
    expect(
      _position(tester).maxScrollExtent,
      lessThan(position.viewportDimension * ChatMinimap.longAfter),
    );
    expect(_opacity(tester), 1);
  });

  testWidgets('not where it is not asked for (the IDE)', (tester) async {
    await _pump(tester, _Feed(_conversation(30)), minimap: false);
    expect(find.byType(ChatMinimap), findsNothing);
  });

  testWidgets('a press scrolls there, a drag to the end back to it', (
    tester,
  ) async {
    await _pump(tester, _Feed(_conversation(30)));
    final position = _position(tester);
    expect(position.pixels, position.maxScrollExtent);
    final strip = tester.getRect(_strip);

    // Near its top: the start of the conversation.
    await tester.tapAt(strip.topCenter + const Offset(0, 4));
    await tester.pumpAndSettle();
    expect(position.pixels, lessThan(position.maxScrollExtent * 0.1));

    // Its glass dragged all the way down: at the end, and held there.
    final gesture = await tester.startGesture(
      strip.topCenter + const Offset(0, 6),
    );
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(Offset(0, strip.height / 10));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(position.pixels, position.maxScrollExtent);
  });

  test('a message samples as its bubble shows it: a paste as its tag, '
      'a long one as its first lines', () {
    double height(String text) =>
        ChatMinimap.sampledHeight(UserMessageItem(text: text));
    final pasted = PastedText(
      number: 1,
      text: [for (var i = 0; i < 548; i++) 'UPDATE t SET a = $i;'].join('\n'),
    );
    expect(
      height('${pasted.reference} 去掉注释。${codeAppendix([pasted])}'),
      height('${pasted.reference} 去掉注释。'),
    );
    final three = height('one\ntwo\nthree');
    expect(height('one\ntwo\nthree\nfour'), greaterThan(three));
    expect(height([for (var i = 0; i < 40; i++) 'line $i'].join('\n')), three);
  });

  testWidgets('the pointer is drawn to a message of the user\'s, peeks at it '
      'and what answered it, and a press goes there', (tester) async {
    await _pump(tester, _Feed(_conversation(30)));
    final strip = tester.getRect(_strip);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final peek = find.descendant(
      of: find.byType(ChatMinimap),
      matching: find.textContaining('问题'),
    );
    expect(peek, findsNothing);

    // Down the minimap, until near one.
    Offset? at;
    for (var y = strip.top + 2; y < strip.bottom; y += 3) {
      // Beside it, not on it: near enough.
      at = Offset(strip.left - 6, y);
      await tester.sendEventToBinding(pointer.hover(at));
      await tester.pump(const Duration(milliseconds: 100));
      if (peek.evaluate().isNotEmpty) break;
    }
    expect(peek, findsOneWidget);
    final shown = tester.widget<Text>(peek);
    final asked = shown.data ?? shown.textSpan!.toPlainText();
    expect(
      find.descendant(
        of: find.byType(ChatMinimap),
        matching: find.textContaining('The column keeps its width'),
      ),
      findsWidgets,
    );

    await tester.sendEventToBinding(pointer.down(at!));
    await tester.sendEventToBinding(pointer.up());
    await tester.pumpAndSettle();
    // The message at the top of the history.
    final bubble = find.byWidgetPredicate(
      (widget) => widget is UserMessageBubble && widget.text == asked,
    );
    expect(bubble, findsWidgets);
    final history = tester.getRect(find.byType(Scrollable).first);
    expect(
      tester.getRect(bubble.first).top - history.top,
      inInclusiveRange(0, 40),
    );

    // Away from the minimap, gone.
    await tester.sendEventToBinding(pointer.hover(history.center));
    await tester.pumpAndSettle();
    expect(peek, findsNothing);
  });

  testWidgets('the wheel over it scrolls the history', (tester) async {
    await _pump(tester, _Feed(_conversation(30)));
    final position = _position(tester);
    final before = position.pixels;
    final strip = tester.getRect(_strip);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(strip.center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -300)));
    await tester.pumpAndSettle();
    expect(position.pixels, lessThan(before));
  });
}
