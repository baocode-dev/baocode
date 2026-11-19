import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_column.dart';
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
  void editMessage(int index, ComposerMessage message, {UserPlace? from}) {}

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

Future<ValueNotifier<Rect?>?> _pump(
  WidgetTester tester,
  ChatFeed feed, {
  double width = 1200,
  double maxWidth = 720,
  bool minimap = true,
  ChatMinimapSide side = ChatMinimapSide.left,
  ({double left, double right, Rect? rail})? inset,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  ChatMinimap.side.value = side;
  addTearDown(() => ChatMinimap.side.value = ChatMinimap.defaultSide);
  Widget history = ChatHistoryView(
    feed: feed,
    maxContentWidth: maxWidth,
    minimap: minimap,
  );
  ValueNotifier<Rect?>? rail;
  if (inset != null) {
    rail = ValueNotifier<Rect?>(inset.rail);
    addTearDown(rail.dispose);
    history = ChatColumnInset(
      left: inset.left,
      right: inset.right,
      rail: rail,
      child: history,
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: history),
    ),
  );
  await tester.pumpAndSettle();
  return rail;
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

  // At the right: the column's left level with the composer's (which keeps
  // the room either side), its right clear of the minimap.
  for (final (width, maxWidth) in [
    (1300.0, 1200.0),
    (1200.0, 720.0),
    (790.0, 1200.0),
    (600.0, 720.0),
  ]) {
    testWidgets('at the right of a column ${maxWidth.round()} at most, in a '
        '${width.round()} window', (tester) async {
      await _pump(
        tester,
        _Feed(_conversation(30)),
        width: width,
        maxWidth: maxWidth,
        side: ChatMinimapSide.right,
      );
      expect(_opacity(tester), 1);
      final strip = _track(tester);
      expect(strip.width, 24);
      expect(width - strip.right, greaterThanOrEqualTo(12));
      for (final text in find.byType(AssistantText).evaluate()) {
        final rect = tester.getRect(find.byWidget(text.widget));
        expect(strip.left, greaterThanOrEqualTo(rect.right + 20));
      }
      final text = tester.getRect(find.byType(AssistantText).first);
      if (width < maxWidth + 2 * ChatMinimap.room) {
        expect(text.left, greaterThanOrEqualTo(ChatMinimap.room));
      } else {
        // Room enough: in the middle, as on the left.
        expect(text.left, greaterThan(strip.width + 2 * ChatMinimap.room));
      }
      expect(_scrollbar(tester).interactive, isFalse);
    });
  }

  testWidgets('the side chosen moves it, and the column, at once', (
    tester,
  ) async {
    await _pump(tester, _Feed(_conversation(30)), width: 790, maxWidth: 1200);
    final text = tester.getRect(find.byType(AssistantText).first);
    expect(_track(tester).right, lessThanOrEqualTo(text.left - 20));
    ChatMinimap.side.value = ChatMinimapSide.right;
    await tester.pumpAndSettle();
    final moved = tester.getRect(find.byType(AssistantText).first);
    expect(_track(tester).left, greaterThanOrEqualTo(moved.right + 20));
    expect(moved.left, text.left);
  });

  // The side panel's rail floats over the margin's top: a minimap on its
  // side is under it at any width, in line with it, from below it.
  for (final side in ChatMinimapSide.values) {
    for (final width in [900.0, 1400.0]) {
      testWidgets('under the rail at the ${side.name} of a ${width.round()} '
          'window, in line with it', (tester) async {
        final right = side == ChatMinimapSide.right;
        final rail = right
            ? Rect.fromLTWH(width - 48, 12, 36, 130)
            : const Rect.fromLTWH(12, 12, 36, 130);
        await _pump(
          tester,
          _Feed(_conversation(30)),
          width: width,
          maxWidth: 1200,
          side: side,
          inset: (left: right ? 0 : 56, right: right ? 56 : 0, rail: rail),
        );
        expect(_opacity(tester), 1);
        final strip = _track(tester);
        expect(strip.center.dx, moreOrLessEquals(rail.center.dx));
        expect(strip.top, moreOrLessEquals(rail.bottom + 10));
        expect(strip.bottom, 800 - 14);
        // Clear of the text still.
        for (final text in find.byType(AssistantText).evaluate()) {
          final rect = tester.getRect(find.byWidget(text.widget));
          if (right) {
            expect(strip.left, greaterThan(rect.right));
          } else {
            expect(strip.right, lessThan(rect.left));
          }
        }
      });
    }
  }

  testWidgets('with the rail at the other side, beside the column from the '
      'top', (tester) async {
    const rail = Rect.fromLTWH(1400 - 48, 12, 36, 130);
    await _pump(
      tester,
      _Feed(_conversation(30)),
      width: 1400,
      inset: (left: 0, right: 56, rail: rail),
    );
    final strip = _track(tester);
    final text = tester.getRect(find.byType(AssistantText).first);
    expect(strip.right, lessThanOrEqualTo(text.left - 20));
    expect(strip.top, 14);
  });

  testWidgets('the rail grown, the minimap follows it down at once, though '
      'nothing else moves', (tester) async {
    const rail = Rect.fromLTWH(900 - 48, 12, 36, 130);
    final told = await _pump(
      tester,
      _Feed(_conversation(30)),
      width: 900,
      side: ChatMinimapSide.right,
      inset: (left: 0, right: 56, rail: rail),
    );
    expect(_track(tester).top, moreOrLessEquals(rail.bottom + 10));
    told!.value = const Rect.fromLTWH(900 - 48, 12, 36, 160);
    // A frame of its own to look again in.
    expect(SchedulerBinding.instance.hasScheduledFrame, isTrue);
    await tester.pump();
    await tester.pump();
    expect(_track(tester).top, moreOrLessEquals(12 + 160 + 10));
  });

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

  testWidgets('a long conversation shown again has it, and its room, from '
      'its first frame', (tester) async {
    double textLeft() => tester.getRect(find.byType(AssistantText).first).left;
    final first = _Feed(_conversation(30));
    final second = _Feed(_conversation(30));
    await _pump(tester, first, width: 790, maxWidth: 1200);
    await _pump(tester, second, width: 790, maxWidth: 1200);
    expect(_opacity(tester), 1);
    // Back to the first: one frame, not laid out and found long again.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ChatHistoryView(
            feed: first,
            maxContentWidth: 1200,
            minimap: true,
          ),
        ),
      ),
    );
    expect(_opacity(tester), 1);
    expect(textLeft(), greaterThanOrEqualTo(ChatMinimap.room));
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

  testWidgets('at the right, it peeks to its left', (tester) async {
    await _pump(tester, _Feed(_conversation(30)), side: ChatMinimapSide.right);
    final strip = tester.getRect(_strip);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final peek = find.descendant(
      of: find.byType(ChatMinimap),
      matching: find.textContaining('问题'),
    );
    for (var y = strip.top + 2; y < strip.bottom; y += 3) {
      // Beside it, toward the edge: near enough.
      await tester.sendEventToBinding(
        pointer.hover(Offset(strip.right + 6, y)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (peek.evaluate().isNotEmpty) break;
    }
    expect(peek, findsOneWidget);
    await tester.pumpAndSettle();
    final card = tester.getRect(peek);
    expect(card.right, lessThanOrEqualTo(strip.left));
    expect(card.left, greaterThan(0));
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
