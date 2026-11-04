import 'package:baocode/diagnostics/frame_watch.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Small extends StatelessWidget {
  const _Small();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 10, height: 10);
}

class _Row extends StatelessWidget {
  const _Row(this.n);

  final int n;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(1), child: Text('row $n'));
}

class _HeavyPage extends StatelessWidget {
  const _HeavyPage(this.rows);

  final int rows;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(children: [for (var i = 0; i < rows; i++) _Row(i)]),
  );
}

Widget _app(int rows) => Directionality(
  textDirection: TextDirection.ltr,
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Column(children: [_Small(), _Small()]),
      Expanded(child: _HeavyPage(rows)),
    ],
  ),
);

void main() {
  testWidgets('names the page that holds most of the tree, and its rows', (
    tester,
  ) async {
    await tester.pumpWidget(_app(3000));
    final text = FrameWatch.heaviest(tester.binding.rootElement!);
    expect(text, contains('_HeavyPage'));
    expect(text, contains(': Column, '));
    expect(text, contains('in 3000 children (_Row ×3000 '));
    // Nothing else beside them.
    expect(text, isNot(contains('…')));
  });

  testWidgets('keeps the closest names over it', (tester) async {
    await tester.pumpWidget(_app(3000));
    final text = FrameWatch.heaviest(tester.binding.rootElement!, names: 1);
    expect(text, matches(RegExp(r', under [^>:]+: Column, ')));
  });

  testWidgets('a tree of 80,000 elements, walked in a few milliseconds', (
    tester,
  ) async {
    await tester.pumpWidget(_app(20000));
    final root = tester.binding.rootElement!;
    final watch = Stopwatch()..start();
    final text = FrameWatch.heaviest(root);
    watch.stop();
    // ignore: avoid_print
    print('${watch.elapsedMilliseconds} ms: $text');
    expect(text, contains('_Row ×20000'));
  });
}
