import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'package:monad/main.dart';

void main() {
  testWidgets('renders the chat history', (tester) async {
    await tester.pumpWidget(const MonadApp());

    expect(find.text('100,000 BLOCKS'), findsNothing);
    expect(find.textContaining('第 1 轮'), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
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
      final selectionArea = tester.widget<SelectionArea>(
        find.byType(SelectionArea),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(find.textContaining('第 1 轮')));
      await tester.pump();
      expect(selectionArea.focusNode!.hasFocus, isTrue);

      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();

      expect(copiedText, contains('第 1 轮'));
      expect(copiedText, contains('final visibleRange'));
      await mouse.removePointer();
    });
  }

  testWidgets('scrollbar thumb jumps across the virtual feed', (tester) async {
    await tester.pumpWidget(const MonadApp());
    await tester.pumpAndSettle();
    final controller = tester
        .widget<SuperListView>(find.byType(SuperListView))
        .controller!;
    final painterFinder = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.foregroundPainter is ScrollbarPainter,
    );
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

    final thinking = find.textContaining('Thought for').first;
    await tester.tap(thinking);
    await tester.pumpAndSettle();

    expect(find.textContaining('我先估算当前 viewport'), findsOneWidget);

    await tester.tap(thinking);
    await tester.pumpAndSettle();

    expect(find.textContaining('我先估算当前 viewport'), findsNothing);
  });
}
