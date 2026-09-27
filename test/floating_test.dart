import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/chat_history_view.dart';
import 'package:monad/chat/composer/composer_picker.dart';
import 'package:monad/chat/composer/suggestion_menu.dart';
import 'package:monad/chat/floating/floating_placement.dart';
import 'package:monad/chat/floating/floating_registry.dart';
import 'package:monad/chat/widgets/tool_call_row.dart';
import 'package:monad/chat/widgets/user_message_bubble.dart';

import 'composer_test.dart' show pumpScreen, settleAnimations, typeText;

void main() {
  tearDown(FloatingRegistry.reset);

  group('computeFloatingPosition', () {
    const bounds = Rect.fromLTWH(0, 0, 400, 300);
    const size = Size(120, 80);
    const topStart = (side: FloatingSide.top, align: FloatingAlign.start);

    test('goes on the preferred side when it fits', () {
      final position = computeFloatingPosition(
        anchor: const Rect.fromLTWH(50, 150, 60, 20),
        size: size,
        bounds: bounds,
        placement: topStart,
      );
      expect(position.offset, const Offset(50, 150 - 6 - 80));
      expect(position.placement, topStart);
    });

    test('flips to the other side when it does not', () {
      final position = computeFloatingPosition(
        anchor: const Rect.fromLTWH(50, 20, 60, 20),
        size: size,
        bounds: bounds,
        placement: topStart,
      );
      expect(position.placement.side, FloatingSide.bottom);
      expect(position.offset, const Offset(50, 46));
    });

    test('shifts along the side to stay inside', () {
      final position = computeFloatingPosition(
        anchor: const Rect.fromLTWH(350, 150, 40, 20),
        size: size,
        bounds: bounds,
        placement: topStart,
      );
      expect(position.offset.dx, 400 - 120);
    });

    test('stays inside even when neither side fits', () {
      final position = computeFloatingPosition(
        anchor: const Rect.fromLTWH(50, 120, 60, 40),
        size: const Size(120, 200),
        bounds: bounds,
        placement: topStart,
      );
      final rect = position.offset & const Size(120, 200);
      expect(bounds.contains(rect.topLeft), isTrue);
      expect(rect.bottom, lessThanOrEqualTo(bounds.bottom));
    });

    test('reports an anchor scrolled out of its clip as hidden', () {
      const clip = Rect.fromLTWH(0, 40, 400, 200);
      expect(isAnchorHidden(const Rect.fromLTWH(0, 10, 50, 20), clip), isTrue);
      expect(isAnchorHidden(const Rect.fromLTWH(0, 30, 50, 20), clip), isFalse);
      expect(isAnchorHidden(const Rect.fromLTWH(0, 10, 50, 20), null), isFalse);
    });

    test('caps the extent to the larger side', () {
      expect(
        availableExtent(
          anchor: const Rect.fromLTWH(0, 100, 10, 20),
          bounds: bounds,
          side: FloatingSide.top,
        ),
        300 - 120 - 6,
      );
    });
  });

  Finder historyPicker() => find
      .descendant(
        of: find.byType(ChatHistoryView),
        matching: find.byType(ComposerPicker),
      )
      .last;

  Future<void> openEditorAtTop(WidgetTester tester) async {
    await tester.ensureVisible(
      find.textContaining('第 2 轮', findRichText: true, skipOffstage: false),
    );
    await tester.pump();
    await tester.tap(
      find.ancestor(
        of: find.textContaining('第 2 轮', findRichText: true),
        matching: find.byType(UserMessageBubble),
      ),
    );
    await tester.pump();
    await tester.pump();
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ChatHistoryView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
  }

  testWidgets('a menu with no room above opens below, inside the window', (
    tester,
  ) async {
    await pumpScreen(tester);
    await openEditorAtTop(tester);
    final pill = tester.getRect(historyPicker());
    await tester.tapAt(pill.center);
    await settleAnimations(tester);

    final menu = Rect.fromPoints(
      tester.getTopLeft(find.text('Opus 5.5').last),
      tester.getBottomRight(find.text('Fastest')),
    );
    final window =
        Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(menu.top, greaterThan(pill.bottom));
    expect(window.deflate(8).contains(menu.topLeft), isTrue);
    expect(menu.bottom, lessThanOrEqualTo(window.bottom - 8));
  });

  testWidgets('one popover at a time', (tester) async {
    await pumpScreen(tester);
    await settleAnimations(tester);
    final mode = find.byType(ComposerPicker).at(0);
    final model = find.byType(ComposerPicker).at(1);

    // A picker closes the suggestion menu.
    await typeText(tester, '/');
    expect(find.byType(SuggestionMenu), findsOneWidget);
    await tester.tapAt(tester.getCenter(mode));
    await settleAnimations(tester);
    expect(find.byType(SuggestionMenu), findsNothing);
    expect(find.text('Plan, search, edit and run'), findsOneWidget);

    // The other picker closes the first.
    await tester.tapAt(tester.getCenter(model));
    await settleAnimations(tester);
    expect(find.text('Plan, search, edit and run'), findsNothing);
    expect(find.text('Fastest'), findsOneWidget);
  });

  testWidgets('menu keys stay in the menu', (tester) async {
    final session = await pumpScreen(tester);
    await settleAnimations(tester);
    await typeText(tester, 'draft');
    final count = session.itemCount;

    // Enter picks the option; the draft is not sent.
    await tester.tapAt(tester.getCenter(find.byType(ComposerPicker).at(1)));
    await settleAnimations(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settleAnimations(tester);
    expect(find.text('Fastest'), findsNothing);
    expect(session.itemCount, count);
    expect(
      find.descendant(
        of: find.byType(ComposerPicker).at(1),
        matching: find.text('Opus 5.5'),
      ),
      findsOneWidget,
    );

    // Esc closes a menu in a message being edited, not the editor.
    await openEditorAtTop(tester);
    await tester.tapAt(tester.getCenter(historyPicker()));
    await settleAnimations(tester);
    expect(find.text('Fastest'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleAnimations(tester);
    expect(find.text('Fastest'), findsNothing);
    expect(historyPicker(), findsOneWidget);
  });

  testWidgets('a menu hides while its anchor is out of view', (tester) async {
    await pumpScreen(tester);
    await tester.ensureVisible(
      find.textContaining('第 2 轮', findRichText: true, skipOffstage: false),
    );
    await tester.pump();
    await tester.tap(
      find.ancestor(
        of: find.textContaining('第 2 轮', findRichText: true),
        matching: find.byType(UserMessageBubble),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tapAt(tester.getCenter(historyPicker()));
    await settleAnimations(tester);
    expect(find.text('Fastest'), findsOneWidget);

    // Scroll back so the message (and its editor) is below the list.
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ChatHistoryView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    final start = position.pixels;
    position.jumpTo(start - 1000);
    await tester.pump();
    await tester.pump();
    expect(find.text('Fastest'), findsNothing);

    // Still open: back in view, back on screen.
    position.jumpTo(start);
    await tester.pump();
    await tester.pump();
    expect(find.text('Fastest'), findsOneWidget);
  });

  group('tooltip', () {
    late TestGesture mouse;
    Finder read() => find.widgetWithText(ToolCallRow, 'Read').last;
    Finder grep() => find.widgetWithText(ToolCallRow, 'Grepped').last;
    final readTip = find.text('lib/main.dart');
    final grepTip = find.textContaining('results in');

    Future<void> hover(WidgetTester tester, Offset at) async {
      await mouse.moveTo(at);
      await tester.pump();
    }

    Future<void> setUpScreen(WidgetTester tester) async {
      await pumpScreen(tester);
      await tester.ensureVisible(
        find.widgetWithText(ToolCallRow, 'Read', skipOffstage: false).last,
      );
      await tester.pump();
      mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
    }

    testWidgets('shows after a delay and stays while hovered', (tester) async {
      await setUpScreen(tester);
      await hover(tester, tester.getCenter(read()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(readTip, findsNothing);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(readTip, findsOneWidget);
      expect(find.text('Lines 1–562'), findsOneWidget);

      // Leaving hides it after a moment, unless the pointer reaches it.
      await hover(tester, tester.getCenter(readTip));
      await tester.pump(const Duration(seconds: 1));
      expect(readTip, findsOneWidget);
      await hover(tester, const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 100));
      expect(readTip, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      await settleAnimations(tester);
      expect(readTip, findsNothing);
    });

    testWidgets('moves along a row of items without delay, one at a time', (
      tester,
    ) async {
      await setUpScreen(tester);
      await hover(tester, tester.getCenter(read()));
      await tester.pump(const Duration(milliseconds: 600));
      expect(readTip, findsOneWidget);
      await hover(tester, tester.getCenter(grep()));
      await tester.pump();
      expect(grepTip, findsOneWidget);
      await settleAnimations(tester);
      expect(readTip, findsNothing);
      expect(find.text('lib/main.dart:142'), findsOneWidget);
    });

    testWidgets('hides at once when its row scrolls out of view', (
      tester,
    ) async {
      await setUpScreen(tester);
      await hover(tester, tester.getCenter(read()));
      await tester.pump(const Duration(milliseconds: 600));
      expect(readTip, findsOneWidget);
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ChatHistoryView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      // Pointer off the rows, then the row just out of view.
      final list = tester.getRect(find.byType(ChatHistoryView));
      final row = tester.getRect(read());
      await hover(tester, const Offset(5, 5));
      position.jumpTo(position.pixels + row.bottom - list.top + 40);
      await tester.pump();
      await tester.pump();
      expect(
        find.widgetWithText(ToolCallRow, 'Read', skipOffstage: false),
        findsWidgets,
      );
      expect(readTip, findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a press closes it, and none shows over a popover', (
      tester,
    ) async {
      await setUpScreen(tester);
      await hover(tester, tester.getCenter(read()));
      await tester.pump(const Duration(milliseconds: 600));
      expect(readTip, findsOneWidget);
      await mouse.down(tester.getCenter(read()));
      await mouse.up();
      await settleAnimations(tester);
      expect(readTip, findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(readTip, findsNothing);

      // With a menu open, hovering shows nothing.
      await hover(tester, tester.getCenter(find.byType(ComposerPicker).at(0)));
      await mouse.down(tester.getCenter(find.byType(ComposerPicker).at(0)));
      await mouse.up();
      await settleAnimations(tester);
      await hover(tester, tester.getCenter(grep()));
      await tester.pump(const Duration(seconds: 1));
      expect(grepTip, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleAnimations(tester);
    });
  });
}
