import 'dart:ui' show ImageByteFormat, PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'package:monad/chat/mock_conversation.dart';
import 'package:monad/chat/composer/composer.dart';
import 'package:monad/chat/widgets/edge_fade_mask.dart';
import 'package:monad/main.dart';

void main() {
  testWidgets('renders the chat history', (tester) async {
    await tester.pumpWidget(const MonadApp());

    await tester.pump();

    // Opens at the bottom of the conversation, above the composer.
    expect(find.textContaining('已完成修改'), findsWidgets);
    expect(find.textContaining('第 1 轮'), findsNothing);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(ChatComposer), findsOneWidget);
  });

  for (final modifier in [
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.controlLeft,
  ]) {
    testWidgets('selects and copies feed text with $modifier', (tester) async {
      String? copiedText;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(const MonadApp());
      await tester.pump();
      final selectionArea = tester.widget<SelectionArea>(
        find.byType(SelectionArea),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(find.textContaining('已完成修改').last));
      await tester.pump();
      // Hovering leaves focus in the composer; clicking moves it.
      expect(selectionArea.focusNode!.hasFocus, isFalse);
      await mouse.down(tester.getCenter(find.textContaining('已完成修改').last));
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(selectionArea.focusNode!.hasFocus, isTrue);

      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();

      expect(copiedText, contains('已完成修改'));
      expect(copiedText, contains('flutter test'));
      await mouse.removePointer();
    });
  }

  testWidgets('scrollbar thumb jumps across the virtual feed', (tester) async {
    await tester.pumpWidget(const MonadApp());
    await tester.pumpAndSettle();
    final controller = tester
        .widget<SuperListView>(find.byType(SuperListView))
        .controller!;
    controller.jumpTo(0);
    await tester.pump();
    // The history's scrollbar (the composer has its own further down).
    final painterFinder = find
        .byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.foregroundPainter is ScrollbarPainter,
        )
        .first;
    final painter =
        tester.widget<CustomPaint>(painterFinder).foregroundPainter!
            as ScrollbarPainter;
    final thumbPosition = [
      for (var y = 0; y < 60; y++)
        for (var x = 760; x < 800; x++)
          if (painter.hitTestOnlyThumbInteractive(
            Offset(x.toDouble(), y.toDouble()),
            PointerDeviceKind.mouse,
          ))
            Offset(x.toDouble(), y.toDouble()),
    ].first;
    final thumb = await tester.startGesture(
      tester.getTopLeft(painterFinder) + thumbPosition,
      kind: PointerDeviceKind.mouse,
    );

    await thumb.moveBy(const Offset(0, 340));
    await tester.pump();
    expect(
      controller.offset,
      greaterThan(controller.position.maxScrollExtent * 0.3),
    );
    expect(find.textContaining('第 1 轮'), findsNothing);
    expect(
      find
          .byWidgetPredicate((widget) => widget.key is ValueKey<int>)
          .evaluate()
          .length,
      lessThan(100),
    );

    await thumb.moveBy(const Offset(0, 220));
    await tester.pump();
    expect(
      controller.offset,
      greaterThan(controller.position.maxScrollExtent * 0.7),
    );
    await thumb.up();

    controller.jumpTo(0);
    await tester.pump();
    expect(find.textContaining('第 1 轮'), findsOneWidget);
  });

  testWidgets('expands and collapses a thinking block', (tester) async {
    await tester.pumpWidget(const MonadApp());
    await tester.pump();
    tester
        .widget<SuperListView>(find.byType(SuperListView))
        .controller!
        .jumpTo(0);
    await tester.pump();

    final thinking = find.textContaining('Thought for').first;
    await tester.tap(thinking);
    await tester.pumpAndSettle();

    expect(find.textContaining('我先估算当前 viewport'), findsOneWidget);

    await tester.tap(thinking);
    await tester.pumpAndSettle();

    expect(find.textContaining('我先估算当前 viewport'), findsNothing);
  });

  testWidgets('no content shows through at the bottom edge when scrolled up', (
    tester,
  ) async {
    // 2x, like a Retina display: the list's bottom edge can land mid-pixel.
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MonadApp());
    await tester.pump();
    final list = find.byType(SuperListView);
    final controller = tester.widget<SuperListView>(list).controller!;
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(list));
    final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;

    for (final delta in [-13.0, -29.0, -47.0, -71.0, -7.3, -11.9]) {
      await tester.sendEventToBinding(pointer.scroll(Offset(0, delta)));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(
        controller.position.pixels,
        lessThan(controller.position.maxScrollExtent),
        reason: 'small wheel scrolls must not snap back to the bottom',
      );
      // The last 3 logical px of the list, through the (possibly partial)
      // boundary row, in physical pixels. Text (Ahem blocks, #CCCCCC) must
      // not show there at all; allow background and the composer's border
      // (#4D4D4D) antialiased into the boundary row. A half-covered text row
      // (the old leak) is ~0x70 or brighter.
      final rect = tester.getRect(list);
      final band = Rect.fromLTRB(
        rect.left * 2,
        (rect.bottom - 3) * 2,
        rect.right * 2,
        (rect.bottom * 2).ceilToDouble(),
      );
      final image = (await tester.runAsync(() => layer.toImage(band)))!;
      final bytes = (await tester.runAsync(
        () => image.toByteData(format: ImageByteFormat.rawRgba),
      ))!;
      final jumpButton = (
        (rect.center.dx - rect.left - 24) * 2,
        (rect.center.dx - rect.left + 24) * 2,
      );
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          if (x > jumpButton.$1 && x < jumpButton.$2) continue;
          final i = (y * image.width + x) * 4;
          expect(
            bytes.getUint8(i),
            lessThanOrEqualTo(0x58),
            reason: 'pixel ($x, $y) after scrolling $delta',
          );
        }
      }

      // Same at the top edge: content above is faded out entirely.
      final topBand = Rect.fromLTRB(
        rect.left * 2,
        (rect.top * 2).floorToDouble(),
        rect.right * 2,
        (rect.top + 3) * 2,
      );
      final topImage = (await tester.runAsync(() => layer.toImage(topBand)))!;
      final topBytes = (await tester.runAsync(
        () => topImage.toByteData(format: ImageByteFormat.rawRgba),
      ))!;
      for (var i = 0; i < topImage.width * topImage.height * 4; i += 4) {
        expect(
          topBytes.getUint8(i),
          lessThanOrEqualTo(0x58),
          reason: 'top edge pixel ${i ~/ 4} after scrolling $delta',
        );
      }
    }
  });

  testWidgets('top fade only shows when content is above', (tester) async {
    await tester.pumpWidget(const MonadApp());
    await tester.pump();
    // The two edge fades of the list's mask: top, then bottom.
    List<bool> fadesShown() {
      final mask = tester.widget<EdgeFadeMask>(
        find.ancestor(
          of: find.byType(SuperListView),
          matching: find.byType(EdgeFadeMask),
        ),
      );
      return [mask.top, mask.bottom];
    }

    // Pinned to the bottom of a long history: content above, none below.
    expect(fadesShown(), [true, false]);

    tester
        .widget<SuperListView>(find.byType(SuperListView))
        .controller!
        .jumpTo(0);
    // Switches on the very next frame, no fade.
    await tester.pump();
    expect(fadesShown(), [false, true]);
  });

  testWidgets('mouse wheel scrolls the history faster than 1:1', (
    tester,
  ) async {
    await tester.pumpWidget(const MonadApp());
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    final list = find.byType(SuperListView);
    // Measure how far content moves on screen: scroll offsets of a virtual
    // list can be corrected without the content moving.
    final marker =
        find.textContaining('已完成修改').last.evaluate().single.renderObject!
            as RenderBox;
    final before = marker.localToGlobal(Offset.zero).dy;
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(list));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -40)));
    await tester.pump();
    // Faster than the raw 40px delta (the exact factor is a tuning knob).
    expect(marker.localToGlobal(Offset.zero).dy - before, greaterThan(40));
  });

  testWidgets('drag selection stays contiguous when scrolling mid-drag', (
    tester,
  ) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(const MonadApp());
    await tester.pump();
    final list = find.byType(SuperListView);

    // Start dragging in the last message, bring the pointer to the middle,
    // then wheel-scroll up (holding the button) so new messages stream in
    // under a pointer that does not move.
    final start =
        tester.getTopRight(find.textContaining('已完成修改').last) +
        const Offset(-4, 6);
    final drag = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    final middle = tester.getCenter(list);
    await drag.moveTo(middle);
    await tester.pump();
    final wheel = TestPointer(2, PointerDeviceKind.mouse);
    wheel.hover(middle);
    for (var i = 0; i < 40; i++) {
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, -40)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.moveTo(middle + const Offset(0, 2));
    await tester.pump();
    await drag.up();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    // Every message between the two ends is selected: whole turns, in order.
    final text = copied ?? '';
    final thoughts = 'Thought for'.allMatches(text).length;
    expect(thoughts, greaterThanOrEqualTo(3));
    // Whole turns, except that the first may start partway (after its
    // thinking block, before its diff and terminal).
    expect(
      'lazyRange'.allMatches(text).length - thoughts,
      inInclusiveRange(0, 1),
    );
    expect(
      'flutter test'.allMatches(text).length - thoughts,
      inInclusiveRange(0, 1),
    );
    final turns = RegExp(r'第 (\d+) 轮')
        .allMatches(text)
        .map((match) => int.parse(match.group(1)!))
        .toList();
    expect(turns, [for (var i = 0; i < turns.length; i++) turns.first + i]);
    expect(text, endsWith('拖动滚动条跳到任意位置也不会卡顿。'));

    // Released: further scrolling leaves the selection alone.
    final selected = text;
    for (var i = 0; i < 10; i++) {
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, 40)));
      await tester.pump();
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(copied, selected);
  });

  testWidgets(
    'shift+click extends the selection from an anchor scrolled out of view',
    (tester) async {
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      Future<String> copy() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        return copied ?? '';
      }

      await tester.pumpWidget(const MonadApp());
      await tester.pump();

      // Click at the start of the last message: the anchor.
      final anchor =
          tester.getTopLeft(find.textContaining('已完成修改').last) +
          const Offset(2, 6);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: anchor);
      await mouse.down(anchor);
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 600));

      // Scroll far enough that the anchor's item is no longer built, then
      // shift+click; again further up, still extending from the same anchor.
      final wheel = TestPointer(2, PointerDeviceKind.mouse);
      wheel.hover(tester.getCenter(find.byType(SuperListView)));
      Future<String> scrollAndShiftClick() async {
        for (var i = 0; i < 30; i++) {
          await tester.sendEventToBinding(wheel.scroll(const Offset(0, -60)));
          await tester.pump(const Duration(milliseconds: 16));
        }
        // A terminal line on screen (cached items above are built too);
        // scroll on until one is.
        final visible = tester.getRect(find.byType(SuperListView));
        Offset topLeftOf(RenderBox box) => box.localToGlobal(Offset.zero);
        RenderBox? onScreen() => find
            .textContaining('flutter test')
            .evaluate()
            .map((element) => element.renderObject! as RenderBox)
            .where((box) => visible.deflate(8).contains(topLeftOf(box)))
            .firstOrNull;
        while (onScreen() == null) {
          await tester.sendEventToBinding(wheel.scroll(const Offset(0, -60)));
          await tester.pump(const Duration(milliseconds: 16));
        }
        final targetBox = onScreen()!;
        final targetTopLeft = topLeftOf(targetBox);
        final target = targetTopLeft + const Offset(4, 6);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await mouse.moveTo(target);
        await mouse.down(target);
        await tester.pump();
        await mouse.up();
        // Builds the anchor's range, keeps the view in place, then applies
        // the selection.
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        // The clicked line has not moved.
        expect(topLeftOf(targetBox), targetTopLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        return copy();
      }

      void expectContiguousToAnchor(String text) {
        // From the clicked terminal line down to the anchor: whole turns.
        expect(text, startsWith(r'$ flutter test'));
        expect(text, endsWith('All tests passed!'));
        final thoughts = 'Thought for'.allMatches(text).length;
        expect(thoughts, greaterThanOrEqualTo(3));
        expect('flutter test'.allMatches(text).length, thoughts + 1);
        expect('lazyRange'.allMatches(text).length, thoughts);
      }

      final first = await scrollAndShiftClick();
      expectContiguousToAnchor(first);
      final second = await scrollAndShiftClick();
      expectContiguousToAnchor(second);
      expect(second.length, greaterThan(first.length));
      expect(second, endsWith(first));
      await mouse.removePointer();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('shift+click selects across the whole conversation', (
    tester,
  ) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(const MonadApp());
    await tester.pump();
    final anchor =
        tester.getTopLeft(find.textContaining('已完成修改').last) +
        const Offset(2, 6);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: anchor);
    await mouse.down(anchor);
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 600));

    // Jump to the start of the conversation and shift+click there.
    final list = find.byType(SuperListView);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    scrollable.position.jumpTo(0);
    await tester.pump();
    await tester.pump();
    final target =
        tester.getTopLeft(find.textContaining('第 1 轮').first) +
        const Offset(4, 6);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await mouse.moveTo(target);
    await mouse.down(target);
    await tester.pump();
    await mouse.up();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    // Everything from the first turn down to the anchor, although only
    // the items around the viewport are built; nothing jumped.
    expect(scrollable.position.pixels, 0);
    expect(find.textContaining('已完成修改'), findsNothing);
    final stopwatch = Stopwatch()..start();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    stopwatch.stop();
    final text = copied ?? '';
    expect(text, startsWith('第 1 轮'));
    expect(text, endsWith('All tests passed!'));
    final turns = RegExp(r'第 (\d+) 轮')
        .allMatches(text)
        .map((match) => int.parse(match.group(1)!))
        .toList();
    const turnCount = MockConversation.itemCount ~/ 8;
    expect(turns.length, turnCount);
    expect(turns.last, turnCount);
    expect(turns.indexed.every((entry) => entry.$2 == entry.$1 + 1), isTrue);
    expect('Thought for'.allMatches(text).length, turnCount);
    // Copying builds the text of every item from the model: no freeze.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));

    // Scroll to the middle: the items built there show as selected, and
    // copying again gives the same text.
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent / 2);
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    final viewport = tester.getRect(list);
    final visible = tester
        .renderObjectList<RenderParagraph>(
          find.descendant(of: list, matching: find.byType(RichText)),
        )
        .where(
          (paragraph) =>
              paragraph.registrar != null && // Text, not icons.
              viewport.overlaps(
                paragraph.localToGlobal(Offset.zero) & paragraph.size,
              ),
        )
        .toList();
    expect(visible, isNotEmpty);
    for (final paragraph in visible) {
      // Inline tags are placeholders, selected (and copied) on their own.
      final plain = paragraph.text
          .toPlainText(includeSemanticsLabels: false)
          .replaceAll('\uFFFC', '');
      final selected = paragraph.selections.fold(
        0,
        (sum, s) => sum + s.end - s.start,
      );
      // Ellipsized lines only select what they show.
      expect(
        paragraph.didExceedMaxLines ? selected > 0 : selected == plain.length,
        isTrue,
        reason: 'not fully selected: $plain',
      );
    }
    copied = null;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(copied, text);
    await mouse.removePointer();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
