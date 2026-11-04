import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderClipRect;
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/tab_strip_scroll.dart';
import 'package:baocode/workspace/islands.dart';

/// Tabs 100 wide over a card 250 wide, the [active]th in front, the strip
/// scrolling across.
Widget _strip(
  ScrollController scroll, {
  required int active,
  List<GlobalKey>? keys,
}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 250,
      height: 200,
      child: IslandTabbedCard(
        tabsHeight: IslandTab.height,
        color: Colors.grey,
        body: const SizedBox.expand(),
        tabs: TabStripScroll(
          controller: scroll,
          child: Row(
            children: [
              for (var i = 0; i < 6; i++)
                SizedBox(
                  key: keys?[i],
                  width: 100,
                  child: IslandTab(
                    active: i == active,
                    atStart: i == 0,
                    color: Colors.grey,
                    onTap: () {},
                    builder: (context, foreground) => const SizedBox(),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  ),
);

double _corner(WidgetTester tester) =>
    tester.widget<Island>(find.byType(Island)).topLeft;

/// How much of the strip's left is hidden.
double _hidden(WidgetTester tester) {
  final clip = tester.renderObject<RenderClipRect>(
    find
        .descendant(
          of: find.byType(TabStripScroll),
          matching: find.byType(ClipRect),
        )
        .first,
  );
  return clip.clipper!.getClip(clip.size).left;
}

void main() {
  testWidgets('at its start the first tab is flush with the card, its '
      'corner square under it; scrolled, the tabs are hidden from where the '
      'corner\'s rounding ends, the corner rounded, eased between', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_strip(scroll, active: 0));
    await tester.pumpAndSettle();
    expect(_corner(tester), 0);
    expect(_hidden(tester), 0);

    scroll.jumpTo(5);
    // The corner told after the frame the tab is built in.
    await tester.pump();
    await tester.pump();
    await tester.pump(IslandCornerRadius.duration ~/ 2);
    // On the way.
    expect(_corner(tester), inExclusiveRange(0, Islands.radius));
    expect(_hidden(tester), inExclusiveRange(0, Islands.radius));
    await tester.pumpAndSettle();
    expect(_corner(tester), Islands.radius);
    expect(_hidden(tester), Islands.radius);

    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(_corner(tester), 0);
    expect(_hidden(tester), 0);
  });

  testWidgets('another tab in front leaves the corner rounded, however '
      'scrolled', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_strip(scroll, active: 2));
    await tester.pumpAndSettle();
    expect(_corner(tester), Islands.radius);
    for (final offset in [188.0, 195.0, 250.0]) {
      scroll.jumpTo(offset);
      await tester.pumpAndSettle();
      expect(_corner(tester), Islands.radius, reason: '$offset');
    }
  });

  testWidgets('a tab revealed shows past the corner', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final keys = [for (var i = 0; i < 6; i++) GlobalKey()];
    await tester.pumpWidget(_strip(scroll, active: 2, keys: keys));
    await tester.pumpAndSettle();
    scroll.jumpTo(400);
    await tester.pumpAndSettle();
    TabStripScroll.reveal(keys[2].currentContext!);
    await tester.pumpAndSettle();
    final strip = tester.getRect(find.byType(TabStripScroll));
    expect(
      tester.getRect(find.byKey(keys[2])).left - strip.left,
      greaterThanOrEqualTo(Islands.radius - 0.01),
    );
    // The first, at the start: flush.
    TabStripScroll.reveal(keys[0].currentContext!);
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
  });
}
