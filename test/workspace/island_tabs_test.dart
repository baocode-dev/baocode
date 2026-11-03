import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/workspace/islands.dart';

/// Tabs 100 wide over a card 250 wide, the [active]th in front, the strip
/// scrolling across.
Widget _strip(ScrollController scroll, {required int active}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 250,
      height: 200,
      child: IslandTabbedCard(
        tabsHeight: IslandTab.height,
        color: Colors.grey,
        body: const SizedBox.expand(),
        tabs: SingleChildScrollView(
          controller: scroll,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < 6; i++)
                SizedBox(
                  width: 100,
                  child: IslandTab(
                    active: i == active,
                    atStart: i == 0,
                    color: Colors.grey,
                    onTap: () {},
                    builder: (context, foreground) => Text('tab $i'),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  ),
);

bool _square(WidgetTester tester) =>
    tester.widget<Island>(find.byType(Island)).squareTopLeft;

void main() {
  testWidgets('the card\'s top left corner is square under the tab in '
      'front where it is in the corner: first, or scrolled there', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_strip(scroll, active: 0));
    await tester.pump();
    expect(_square(tester), isTrue);

    await tester.pumpWidget(_strip(scroll, active: 2));
    await tester.pump();
    await tester.pump();
    // Its own place, clear of the corner.
    expect(_square(tester), isFalse);

    // Scrolled to 12 from the card's edge: its foot over the corner's
    // rounding.
    scroll.jumpTo(188);
    await tester.pump();
    await tester.pump();
    expect(_square(tester), isTrue);

    // 5 from it.
    scroll.jumpTo(195);
    await tester.pump();
    await tester.pump();
    expect(_square(tester), isTrue);

    // Half under the strip's edge.
    scroll.jumpTo(250);
    await tester.pump();
    await tester.pump();
    expect(_square(tester), isTrue);

    // Gone past it: the next tab, not in front, there.
    scroll.jumpTo(310);
    await tester.pump();
    await tester.pump();
    expect(_square(tester), isFalse);

    // Back, its foot clear of it again.
    scroll.jumpTo(176);
    await tester.pump();
    await tester.pump();
    expect(_square(tester), isFalse);
  });
}
