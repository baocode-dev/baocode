import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_animated_list.dart';

void main() {
  Widget row(String name) =>
      SizedBox(key: ValueKey(name), height: 22, child: Text(name));

  Future<void> pumpList(
    WidgetTester tester,
    List<Widget> children, {
    bool reduceMotion = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: IdeAnimatedList(children: children)),
      ),
    ),
  );

  double heightOf(WidgetTester tester, String name) =>
      tester.getSize(find.byKey(ValueKey(name)).first).height;

  double topOf(WidgetTester tester, String name) =>
      tester.getTopLeft(find.text(name)).dy;

  testWidgets('a new row grows in, pushing the next down', (tester) async {
    await pumpList(tester, [row('a'), row('c')]);
    expect(topOf(tester, 'c'), 22);

    await pumpList(tester, [row('a'), row('b'), row('c')]);
    // Starts with no height.
    expect(heightOf(tester, 'b'), 0);
    expect(topOf(tester, 'c'), 22);
    await tester.pump(const Duration(milliseconds: 75));
    final middle = heightOf(tester, 'b');
    expect(middle, greaterThan(0));
    expect(middle, lessThan(22));
    expect(topOf(tester, 'c'), closeTo(22 + middle, 0.01));
    await tester.pumpAndSettle();
    expect(heightOf(tester, 'b'), 22);
    expect(topOf(tester, 'c'), 44);
  });

  testWidgets('a removed row shrinks out where it was', (tester) async {
    await pumpList(tester, [row('a'), row('b'), row('c')]);
    await pumpList(tester, [row('a'), row('c')]);
    // Still there, between its neighbors.
    expect(find.text('b'), findsOneWidget);
    expect(topOf(tester, 'b'), 22);
    await tester.pump(const Duration(milliseconds: 75));
    expect(topOf(tester, 'c'), lessThan(44));
    expect(topOf(tester, 'c'), greaterThan(22));
    await tester.pumpAndSettle();
    expect(find.text('b'), findsNothing);
    expect(topOf(tester, 'c'), 22);
  });

  testWidgets('a row that comes back while leaving grows again', (
    tester,
  ) async {
    await pumpList(tester, [row('a'), row('b')]);
    await pumpList(tester, [row('a')]);
    await tester.pump(const Duration(milliseconds: 50));
    await pumpList(tester, [row('a'), row('b')]);
    await tester.pumpAndSettle();
    expect(heightOf(tester, 'b'), 22);
  });

  testWidgets('rows that stay keep their state', (tester) async {
    final field = TextField(key: const ValueKey('field'));
    await pumpList(tester, [row('a'), field]);
    await tester.enterText(find.byType(TextField), 'typed');
    await pumpList(tester, [row('new'), row('a'), field]);
    await tester.pumpAndSettle();
    expect(find.text('typed'), findsOneWidget);
  });

  testWidgets('most rows changing at once, or reduced motion, do not move', (
    tester,
  ) async {
    await pumpList(tester, [for (var i = 0; i < 12; i++) row('old $i')]);
    await pumpList(tester, [for (var i = 0; i < 12; i++) row('new $i')]);
    expect(find.text('old 0'), findsNothing);
    expect(heightOf(tester, 'new 0'), 22);

    await pumpList(tester, [row('a')], reduceMotion: true);
    await pumpList(tester, [row('a'), row('b')], reduceMotion: true);
    expect(heightOf(tester, 'b'), 22);
  });
}
