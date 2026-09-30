// Tests of items coming into a live turn: they fade in where they are, and
// the status row whose place one takes fades out there, over it, rather than
// drop below it and fold.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/chat_feed.dart';
import 'package:monad/chat/chat_history_view.dart';
import 'package:monad/chat/chat_models.dart';
import 'package:monad/chat/chat_session.dart';
import 'package:monad/chat/composer/composer_draft.dart';
import 'package:monad/chat/widgets/activity_row.dart';
import 'package:monad/chat/widgets/thinking_section.dart';
import 'package:monad/theme/cursor_theme.dart';

/// A turn under way: its items, then the status row while it streams.
class _LiveFeed extends ChangeNotifier implements ChatFeed {
  final List<ChatItem> items = [const UserMessageItem(text: 'A question')];
  bool statusVisible = true;
  bool streaming = true;

  void add(ChatItem item, {required bool statusVisible}) {
    items.add(item);
    this.statusVisible = statusVisible;
    notifyListeners();
  }

  @override
  int get itemCount => items.length + (streaming ? 1 : 0);

  @override
  ChatItem itemAt(int index) => index < items.length
      ? items[index]
      : LiveStatusItem(
          'Planning next move',
          whimsical: true,
          visible: statusVisible,
        );

  @override
  bool get isStreaming => streaming;

  @override
  bool get canEditMessages => false;

  @override
  ({int index, ComposerDraft draft})? editing;

  @override
  void editMessage(int index, ComposerMessage message) {}

  @override
  void cancelQueued(int index) {}

  @override
  VoidCallback? moveToBackgroundAt(int index) => null;

  @override
  VoidCallback? stopAt(int index) => null;
}

const _thought = ThinkingItem(text: '用', tokens: 1);

Future<_LiveFeed> _pump(WidgetTester tester, {bool still = false}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(800, 600);
  addTearDown(tester.view.reset);
  final feed = _LiveFeed();
  addTearDown(feed.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildCursorTheme(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: still),
        child: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return feed;
}

double _opacityOf(WidgetTester tester, Finder item) => tester
    .widget<FadeTransition>(
      find.ancestor(of: item, matching: find.byType(FadeTransition)).first,
    )
    .opacity
    .value;

void main() {
  testWidgets('the status row gives way to the thought in its place: the one '
      'fades out where it was as the other fades in', (tester) async {
    final feed = await _pump(tester);
    final status = find.byType(ActivityRow);
    final row = tester.element(status);
    final top = tester.getRect(status).top;

    feed.add(_thought, statusVisible: false);
    await tester.pump();
    final thought = find.byType(ThinkingSection);
    // Over the thought, where it was, not below it.
    expect(tester.getRect(status).top, top);
    // Rising into its place.
    expect(tester.getRect(thought).top, inInclusiveRange(top, top + 6));
    expect(tester.element(status), same(row));
    expect(_opacityOf(tester, thought), lessThan(0.2));

    await tester.pump(const Duration(milliseconds: 120));
    expect(_opacityOf(tester, thought), inExclusiveRange(0.2, 1));
    // The row's own fading.
    expect(
      tester
          .widget<FadeTransition>(
            find.descendant(of: status, matching: find.byType(FadeTransition)),
          )
          .opacity
          .value,
      inExclusiveRange(0, 1),
    );

    await tester.pump(const Duration(milliseconds: 200));
    expect(_opacityOf(tester, thought), 1);
    // Back in its place after the thought, folded, and the same row.
    expect(tester.getSize(status).height, 0);
    expect(
      tester.getRect(status).top,
      greaterThan(tester.getRect(thought).top),
    );
    expect(tester.element(status), same(row));

    // Shown again after it, it opens there.
    feed.add(const AssistantTextItem('An answer'), statusVisible: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(status).height, greaterThan(0));
    expect(tester.element(status), same(row));
    // Built again, the thought does not fade in again.
    feed.notifyListeners();
    await tester.pump();
    expect(_opacityOf(tester, thought), 1);
  });

  testWidgets('with the status row showing still, a step fades in above it', (
    tester,
  ) async {
    final feed = await _pump(tester);
    final status = find.byType(ActivityRow);
    final top = tester.getRect(status).top;
    feed.add(
      const ToolCallItem(kind: ToolKind.read, target: 'lib/main.dart'),
      statusVisible: true,
    );
    await tester.pump();
    expect(tester.getRect(status).top, greaterThan(top));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('where motion is turned down, all is at once', (tester) async {
    final feed = await _pump(tester, still: true);
    feed.add(_thought, statusVisible: false);
    await tester.pump();
    final thought = find.byType(ThinkingSection);
    expect(
      find.ancestor(
        of: thought,
        matching: find.byWidgetPredicate(
          (widget) => widget is FadeTransition && widget.opacity.value < 1,
        ),
      ),
      findsNothing,
    );
    expect(tester.getSize(find.byType(ActivityRow)).height, 0);
  });
}
