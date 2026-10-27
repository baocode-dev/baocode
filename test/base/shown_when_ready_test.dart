import 'package:baocode/base/shown_when_ready.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Holds what it is in back until [release] is called, if [holds].
class _Page extends StatefulWidget {
  const _Page(this.name, {super.key, this.holds = false});

  final String name;
  final bool holds;

  @override
  State<_Page> createState() => _PageState();
}

final _releases = <String, VoidCallback?>{};

class _PageState extends State<_Page> {
  @override
  void initState() {
    super.initState();
    if (widget.holds) _releases[widget.name] = ShownWhenReady.hold(context);
  }

  @override
  Widget build(BuildContext context) =>
      Text(widget.name, textDirection: TextDirection.ltr);
}

Widget _shown(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: ShownWhenReady(child: child),
);

/// The pages drawn: those not hidden.
List<String> _seen(WidgetTester tester) => [
  for (final element in find.byType(_Page).evaluate())
    if (element.findAncestorWidgetOfExactType<Opacity>()!.opacity == 1)
      (element.widget as _Page).name,
];

void main() {
  setUp(_releases.clear);

  testWidgets('the one before stays until the next is ready, then goes', (
    tester,
  ) async {
    await tester.pumpWidget(_shown(const _Page('a', key: ValueKey('a'))));
    final before = tester.state(find.byType(_Page));
    await tester.pumpWidget(
      _shown(const _Page('b', key: ValueKey('b'), holds: true)),
    );
    await tester.pump();
    expect(_seen(tester), ['a']);
    // Kept as it was, not built anew.
    expect(tester.state(find.byKey(const ValueKey('a'))), same(before));
    // Laid out meanwhile, unseen.
    expect(find.byKey(const ValueKey('b')), findsOneWidget);
    _releases['b']!();
    await tester.pump();
    await tester.pump();
    expect(_seen(tester), ['b']);
    expect(find.byKey(const ValueKey('a')), findsNothing);
  });

  testWidgets('what holds nothing back shows after its first frame', (
    tester,
  ) async {
    await tester.pumpWidget(_shown(const _Page('a', key: ValueKey('a'))));
    await tester.pumpWidget(_shown(const _Page('b', key: ValueKey('b'))));
    await tester.pump();
    expect(_seen(tester), ['b']);
    expect(find.byKey(const ValueKey('a')), findsNothing);
  });

  testWidgets('shown after a while whatever holds it', (tester) async {
    await tester.pumpWidget(_shown(const _Page('a', key: ValueKey('a'))));
    await tester.pumpWidget(
      _shown(const _Page('b', key: ValueKey('b'), holds: true)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(_seen(tester), ['a']);
    await tester.pump(const Duration(milliseconds: 200));
    expect(_seen(tester), ['b']);
  });

  testWidgets('a third before the second is ready takes its place; back to '
      'the one shown drops it', (tester) async {
    await tester.pumpWidget(_shown(const _Page('a', key: ValueKey('a'))));
    await tester.pumpWidget(
      _shown(const _Page('b', key: ValueKey('b'), holds: true)),
    );
    await tester.pumpWidget(
      _shown(const _Page('c', key: ValueKey('c'), holds: true)),
    );
    expect(find.byKey(const ValueKey('b')), findsNothing);
    expect(_seen(tester), ['a']);
    await tester.pumpWidget(_shown(const _Page('a', key: ValueKey('a'))));
    expect(find.byKey(const ValueKey('c')), findsNothing);
    expect(_seen(tester), ['a']);
    await tester.pump(const Duration(seconds: 1));
    expect(_seen(tester), ['a']);
  });

  testWidgets('the first shows at once', (tester) async {
    await tester.pumpWidget(
      _shown(const _Page('a', key: ValueKey('a'), holds: true)),
    );
    expect(_seen(tester), ['a']);
    expect(_releases['a'], isNull);
  });
}
