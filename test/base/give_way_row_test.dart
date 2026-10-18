import 'package:baocode/base/give_way_row.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget box(String name, double width) => SizedBox(
    key: ValueKey(name),
    width: width,
    height: 10,
    child: Text(name),
  );

  Future<void> pump(WidgetTester tester, double width, List<GiveWay> row) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: width,
              height: 20,
              child: GiveWayRow(children: row),
            ),
          ),
        ),
      );

  List<GiveWay> row() => [
    GiveWay(box('status', 20)),
    GiveWay.fill(minWidth: 50, box('title', 0)),
    GiveWay(priority: 2, box('stash', 30)),
    GiveWay(priority: 1, box('time', 30)),
    GiveWay(priority: 0, box('diff', 40)),
    GiveWay(priority: 3, compact: box('icon', 10), box('label', 40)),
    GiveWay(box('close', 20)),
  ];

  double left(WidgetTester tester, String name) =>
      tester.getTopLeft(find.byKey(ValueKey(name))).dx;
  double width(WidgetTester tester, String name) =>
      tester.getSize(find.byKey(ValueKey(name))).width;

  testWidgets('with room, all as they are, the fill taking the rest', (
    tester,
  ) async {
    await pump(tester, 400, row());
    final start = tester.getTopLeft(find.byType(GiveWayRow)).dx;
    expect(width(tester, 'title'), 400 - 20 - 30 - 30 - 40 - 40 - 20);
    expect(left(tester, 'status'), start);
    expect(left(tester, 'title'), start + 20);
    for (final name in ['stash', 'time', 'diff', 'label', 'close']) {
      expect(find.byKey(ValueKey(name)), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('icon')), findsNothing);
    expect(
      tester.getTopRight(find.byKey(const ValueKey('close'))).dx,
      start + 400,
    );
  });

  testWidgets('too narrow, the fill down to its least, then the rest give '
      'way lowest first: hidden, or compact', (tester) async {
    // 20 + 50 + 30 + 30 + 40 + 40 + 20 = 230: the diff goes first.
    await pump(tester, 200, row());
    expect(find.byKey(const ValueKey('diff')), findsNothing);
    expect(find.byKey(const ValueKey('time')), findsOneWidget);
    expect(width(tester, 'title'), 200 - 20 - 30 - 30 - 40 - 20);

    // Then the time, the stash, then the label to its icon.
    await pump(tester, 140, row());
    expect(find.byKey(const ValueKey('time')), findsNothing);
    expect(find.byKey(const ValueKey('stash')), findsNothing);
    expect(find.byKey(const ValueKey('label')), findsOneWidget);
    await pump(tester, 110, row());
    expect(find.byKey(const ValueKey('label')), findsNothing);
    expect(find.byKey(const ValueKey('icon')), findsOneWidget);
    expect(width(tester, 'title'), 110 - 20 - 10 - 20);

    // What never gives way stays, the fill cut instead; nothing past the
    // row's end.
    await pump(tester, 60, row());
    expect(find.byKey(const ValueKey('status')), findsOneWidget);
    expect(find.byKey(const ValueKey('close')), findsOneWidget);
    expect(width(tester, 'title'), 60 - 20 - 10 - 20);
    final end = tester.getTopRight(find.byType(GiveWayRow)).dx;
    expect(tester.getTopRight(find.byKey(const ValueKey('close'))).dx, end);
  });

  testWidgets('what gave way is not hit', (tester) async {
    var taps = 0;
    await pump(tester, 80, [
      GiveWay.fill(minWidth: 60, box('title', 0)),
      GiveWay(
        priority: 0,
        GestureDetector(onTap: () => taps++, child: box('button', 40)),
      ),
    ]);
    expect(find.byKey(const ValueKey('button')), findsNothing);
    final end = tester.getTopRight(find.byType(GiveWayRow));
    await tester.tapAt(end + const Offset(-5, 5));
    expect(taps, 0);

    await pump(tester, 120, [
      GiveWay.fill(minWidth: 60, box('title', 0)),
      GiveWay(
        priority: 0,
        GestureDetector(onTap: () => taps++, child: box('button', 40)),
      ),
    ]);
    await tester.tap(find.byKey(const ValueKey('button')));
    expect(taps, 1);
  });
}
