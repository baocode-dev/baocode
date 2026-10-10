import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/widgets/edge_fade_mask.dart';
import 'package:baocode/chat/widgets/scroll_edge_fade.dart';

void main() {
  Future<ScrollController> pump(WidgetTester tester, int items) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            height: 100,
            child: ScrollEdgeFade(
              child: ListView(
                controller: controller,
                children: [
                  for (var i = 0; i < items; i++) const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  (bool, bool) edges(WidgetTester tester) {
    final mask = tester.widget<EdgeFadeMask>(find.byType(EdgeFadeMask));
    return (mask.top, mask.bottom);
  }

  testWidgets('fades the edges more of the list is past', (tester) async {
    final controller = await pump(tester, 10);
    expect(edges(tester), (false, true));

    controller.jumpTo(100);
    await tester.pump();
    expect(edges(tester), (true, true));

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(edges(tester), (true, false));
  });

  testWidgets('no fade when it all fits', (tester) async {
    await pump(tester, 2);
    expect(edges(tester), (false, false));
  });
}
