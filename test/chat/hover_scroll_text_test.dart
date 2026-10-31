import 'package:baocode/chat/widgets/hover_scroll_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const long = 'A title far too long for the room it is given in the title bar';

  Future<void> pump(WidgetTester tester, String text) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 120, child: HoverScrollText(text)),
      ),
    ),
  );

  ScrollController? scroll(WidgetTester tester) => tester
      .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
      .firstOrNull
      ?.controller;

  Future<TestGesture> hover(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(HoverScrollText)));
    await tester.pump();
    return mouse;
  }

  testWidgets('too long, it is cut off until hovered, then scrolls to the '
      'rest and back to its start once left', (tester) async {
    await pump(tester, long);
    expect(
      tester.widget<Text>(find.text(long)).overflow,
      TextOverflow.ellipsis,
    );
    final mouse = await hover(tester);
    expect(scroll(tester), isNotNull);
    await tester.pump(HoverScrollText.pause);
    await tester.pump(const Duration(seconds: 2));
    expect(scroll(tester)!.offset, greaterThan(0));

    await mouse.moveTo(const Offset(500, 500));
    await tester.pump();
    expect(scroll(tester), isNull);
    expect(
      tester.widget<Text>(find.text(long)).overflow,
      TextOverflow.ellipsis,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('one that fits does not scroll', (tester) async {
    await pump(tester, 'Short');
    await hover(tester);
    expect(scroll(tester), isNull);
  });
}
