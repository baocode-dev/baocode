// Tests of the user message stuck to the top of the chat history: it takes
// over from its message in the list looking as that one did, under the
// list's top fade, and comes in as the list scrolls on; pushed away by the
// next message, it goes the same way.

import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/chat/user_message_style.dart';
import 'package:baocode/chat/widgets/edge_fade_mask.dart';
import 'package:baocode/chat/widgets/user_message_bubble.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

/// Two turns, the second's message near enough to the start to be laid out
/// there.
class _TwoTurnFeed extends ChangeNotifier implements ChatFeed {
  static const second = 12;

  @override
  int get itemCount => 60;

  @override
  ChatItem itemAt(int index) => switch (index) {
    0 => const UserMessageItem(text: 'First question'),
    second => const UserMessageItem(text: 'Second question'),
    _ => AssistantTextItem('Line $index of the answer, long enough to wrap.'),
  };

  @override
  bool get isStreaming => false;

  @override
  bool get isUnprompted => false;

  @override
  bool get canEditMessages => false;

  @override
  ({int index, ComposerDraft draft})? editing;

  @override
  void editMessage(int index, ComposerMessage message, {UserPlace? from}) {}

  @override
  VoidCallback? moveToBackgroundAt(int index) => null;

  @override
  VoidCallback? stopAt(int index) => null;
}

void main() {
  testWidgets('a message stuck to the top comes in and goes as the list '
      'scrolls', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);
    final feed = _TwoTurnFeed();
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pump();
    final listView = find.byType(SuperListView);
    final list = tester.getRect(listView);
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(of: listView, matching: find.byType(Scrollable))
              .first,
        )
        .position;
    position.jumpTo(0);
    await tester.pump();
    await tester.pump();
    final second = find.descendant(
      of: listView,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is UserMessageBubble && widget.text == 'Second question',
      ),
      skipOffstage: false,
    );

    /// Scrolls the second message in the list to [y] below the top.
    Future<void> put(double y) async {
      await Scrollable.ensureVisible(tester.element(second), alignment: 0.5);
      await tester.pump();
      position.jumpTo(position.pixels + tester.getRect(second).top - y);
      await tester.pump();
      await tester.pump();
    }

    /// How bright the history is around [y] below its top, beside the
    /// scrollbar.
    final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    Future<double> brightness(double y) async {
      // Around the message's top, [y] down: under the list's top fade.
      final band = Rect.fromLTRB(
        list.left + 60,
        list.top + y - 4,
        list.right - 60,
        list.top + y + 12,
      );
      final image = (await tester.runAsync(() => layer.toImage(band)))!;
      final bytes = (await tester.runAsync(
        () => image.toByteData(format: ImageByteFormat.rawRgba),
      ))!;
      var sum = 0;
      for (var i = 0; i < image.width * image.height; i++) {
        sum += bytes.getUint8(i * 4 + 1);
      }
      return sum / (image.width * image.height);
    }

    /// The top fades of the list, and of the copy of message [index].
    double listFade() => tester
        .widget<EdgeFadeMask>(
          find.ancestor(of: listView, matching: find.byType(EdgeFadeMask)),
        )
        .topFadeAmount!();
    double copyFade(int index) => tester
        .widget<EdgeFadeMask>(
          find
              .ancestor(
                of: find.byWidgetPredicate(
                  (widget) =>
                      widget is UserMessageBubble &&
                      widget.key == ValueKey(('sticky', index)),
                ),
                matching: find.byType(EdgeFadeMask),
              )
              .first,
        )
        .topFadeAmount!();

    // Stuck once it is less than 24 from the top (as far as from the
    // sides, the chat's gutter): the copy takes over under the list's top
    // fade, as its message was, the list shown below it.
    await put(24.5);
    final inList = await brightness(24.5);
    await put(23.5);
    expect(await brightness(23.5), closeTo(inList, 1.5));
    expect(copyFade(_TwoTurnFeed.second), closeTo(63 / 64, 0.001));
    expect(listFade(), closeTo(1 / 64, 0.001));

    // Whole, and the list faded out below it, 32 on: as bright, its top
    // below the list's fade already where it was taken over.
    await put(-8.5);
    expect(await brightness(24), closeTo(inList, 1.5));
    expect(copyFade(_TwoTurnFeed.second), 0);
    expect(listFade(), 1);

    // The first message's copy, pushed away by the second: with the room
    // above a stuck message (24) and the fade below it (16), it is as tall
    // as its bubble and 40 more.
    final height = tester.getSize(second).height + 40;
    await put(height);
    expect(copyFade(0), 0);
    await put(height - 16);
    expect(copyFade(0), closeTo(0.5, 0.001));
    await put(height - 32);
    expect(copyFade(0), 1);
  });

  testWidgets('under a title, a message sticks nearer the top, and comes in '
      'over less of a scroll', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);
    final feed = _TwoTurnFeed();
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed, underTitle: true)),
      ),
    );
    await tester.pump();
    final listView = find.byType(SuperListView);
    final list = tester.getRect(listView);
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(of: listView, matching: find.byType(Scrollable))
              .first,
        )
        .position;
    position.jumpTo(0);
    await tester.pump();
    await tester.pump();
    final first = find.byWidgetPredicate(
      (widget) =>
          widget is UserMessageBubble && widget.text == 'First question',
    );
    // The room above the first message: 12, not the gutter's 24.
    expect(tester.getRect(first.first).top - list.top, 12);
    final listMask = tester.widget<EdgeFadeMask>(
      find.ancestor(of: listView, matching: find.byType(EdgeFadeMask)),
    );
    expect(listMask.topFadeLength, 24);

    double copyFade() => tester
        .widget<EdgeFadeMask>(
          find
              .ancestor(
                of: find.byWidgetPredicate(
                  (widget) =>
                      widget is UserMessageBubble &&
                      widget.key == const ValueKey(('sticky', 0)),
                ),
                matching: find.byType(EdgeFadeMask),
              )
              .first,
        )
        .topFadeAmount!();

    // Stuck once scrolled past 12 from the top; whole 24 on.
    position.jumpTo(12);
    await tester.pump();
    await tester.pump();
    expect(copyFade(), closeTo(0.5, 0.001));
    position.jumpTo(24);
    await tester.pump();
    await tester.pump();
    expect(copyFade(), 0);
  });

  testWidgets('as bubbles, messages are at the right, as wide as their text, '
      'and scroll away', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);
    UserMessageStyle.current.value = UserMessageStyle.bubble;
    addTearDown(() => UserMessageStyle.current.value = UserMessageStyle.sticky);
    final feed = _TwoTurnFeed();
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pump();
    final listView = find.byType(SuperListView);
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(of: listView, matching: find.byType(Scrollable))
              .first,
        )
        .position;
    position.jumpTo(0);
    await tester.pump();
    await tester.pump();
    Finder box(String text) => find
        .descendant(
          of: find.byWidgetPredicate(
            (widget) => widget is UserMessageBubble && widget.text == text,
          ),
          matching: find.byType(Container),
        )
        .first;

    // Narrow, at the right of the column the answers take.
    final first = tester.getRect(box('First question'));
    final answer = tester.getRect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText() ==
                'Line 1 '
                    'of the answer, long enough to wrap.',
      ),
    );
    // The test font's glyphs are squares: 14 of them, the padding and the
    // tail.
    expect(first.width, lessThan(14 * 14 + 40));
    expect(first.right, greaterThan(answer.left + 400));

    // Scrolled past, the first message is not stuck to the top.
    position.jumpTo(position.pixels + first.bottom + 100);
    await tester.pump();
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is UserMessageBubble &&
            widget.key == const ValueKey(('sticky', 0)),
      ),
      findsNothing,
    );
  });
  testWidgets('the style is switched as the chat shows, its messages stuck '
      'or not', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);
    addTearDown(() => UserMessageStyle.current.value = UserMessageStyle.sticky);
    final feed = _TwoTurnFeed();
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pump();
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(SuperListView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    position.jumpTo(0);
    await tester.pump();
    await tester.pump();
    for (final offset in [0.0, 120.0]) {
      position.jumpTo(offset);
      await tester.pump();
      await tester.pump();
      for (final style in [
        UserMessageStyle.bubble,
        UserMessageStyle.sticky,
        UserMessageStyle.bubble,
        UserMessageStyle.sticky,
      ]) {
        UserMessageStyle.current.value = style;
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    }
  });
}
