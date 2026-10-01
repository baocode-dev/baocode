import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_input.dart';

String lines(int count) => List.generate(count, (i) => 'line $i').join('\n');

void main() {
  testWidgets('a multi-line input scrolls without a scrollbar', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = TextEditingController(text: lines(30));
    addTearDown(controller.dispose);
    final scrollbar = find.byWidgetPredicate((w) => w is RawScrollbar);
    Future<void> pump(Widget field) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: field)));
      await tester.pumpAndSettle();
    }

    // Desktop Flutter gives a plain text field one.
    await pump(TextField(controller: controller, maxLines: 10));
    expect(scrollbar, findsOneWidget);

    await pump(IdeInputBox(controller: controller, maxLines: 10));
    expect(find.byType(Scrollable), findsWidgets);
    expect(scrollbar, findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('grows line by line up to maxLines', (tester) async {
    final controller = TextEditingController(text: 'one');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: IdeInputBox(controller: controller, maxLines: 5),
          ),
        ),
      ),
    );
    double height() => tester.getSize(find.byType(IdeInputBox)).height;
    // A line of 18, padding of 4 and a border of 1 above and below.
    expect(height(), 28);
    controller.text = lines(3);
    await tester.pump();
    expect(height(), 3 * 18 + 10);
    controller.text = lines(30);
    await tester.pump();
    expect(height(), 5 * 18 + 10);
  });

  testWidgets('toggles are centered on the first line', (tester) async {
    Future<Rect> toggleIn(IdeInputBox box) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(alignment: Alignment.topCenter, child: box),
          ),
        ),
      );
      return tester.getRect(find.byType(IdeInputToggle));
    }

    final controller = TextEditingController(text: lines(3));
    addTearDown(controller.dispose);
    final toggle = IdeInputToggle(
      icon: Icons.abc,
      tooltip: 'Toggle',
      checked: true,
      onChanged: (_) {},
    );
    // One line: the middle of the box.
    var rect = await toggleIn(
      IdeInputBox(controller: TextEditingController(), toggles: [toggle]),
    );
    expect(rect.center.dy, 28 / 2);
    // The Source Control input: 20px lines, 2px of padding.
    rect = await toggleIn(
      IdeInputBox(
        controller: controller,
        maxLines: 10,
        lineHeight: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        toggles: [toggle],
      ),
    );
    expect(tester.getSize(find.byType(IdeInputBox)).height, 3 * 20 + 6);
    expect(rect.center.dy, 1 + 2 + 20 / 2);
  });

  group('wheel scrolling', () {
    late ScrollController outer;
    late TextEditingController text;

    Future<void> pumpInList(WidgetTester tester) async {
      outer = ScrollController();
      text = TextEditingController(text: lines(30));
      addTearDown(outer.dispose);
      addTearDown(text.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: outer,
              children: [
                const SizedBox(height: 100),
                IdeInputBox(controller: text, maxLines: 5),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      );
    }

    double inner(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(IdeInputBox),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .pixels;

    var clock = Duration.zero;
    Future<void> wheel(WidgetTester tester, Offset at, double dy) async {
      clock += const Duration(milliseconds: 50);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(at, timeStamp: clock));
      await tester.sendEventToBinding(
        pointer.scroll(Offset(0, dy), timeStamp: clock),
      );
      await tester.pump();
    }

    void pause() => clock += const Duration(seconds: 1);

    testWidgets('a gesture over the input keeps to it past its end', (
      tester,
    ) async {
      await pumpInList(tester);
      final over = tester.getCenter(find.byType(IdeInputBox));
      pause();
      for (var i = 0; i < 10; i++) {
        await wheel(tester, over, 60);
      }
      // 30 lines of 18 and the padding, 5 of them shown.
      expect(inner(tester), 30 * 18 + 8 - (5 * 18 + 8));
      expect(outer.offset, 0);

      // A new one, the input at its end: the list scrolls.
      pause();
      await wheel(tester, over, 60);
      expect(outer.offset, 60);
    });

    testWidgets('a gesture begun outside keeps to the list over the input', (
      tester,
    ) async {
      await pumpInList(tester);
      pause();
      await wheel(tester, const Offset(400, 50), 20);
      expect(outer.offset, 20);
      await wheel(tester, tester.getCenter(find.byType(IdeInputBox)), 30);
      expect(inner(tester), 0);
      expect(outer.offset, 50);
    });
  });
}
