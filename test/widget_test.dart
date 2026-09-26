import 'dart:ui' show ImageByteFormat, PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'package:monad/chat/composer/composer.dart';
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
    }
  });
}
