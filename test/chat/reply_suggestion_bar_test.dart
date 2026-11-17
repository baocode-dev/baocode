import 'package:baocode/chat/panels/reply_suggestion_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget bar(String key) => MaterialApp(
    home: Scaffold(
      body: ReplySuggestionBar(
        suggestions: const ['one', 'two', 'three'],
        playKey: key,
        onPick: (_) {},
        onSend: (_) {},
      ),
    ),
  );

  double opacityOf(WidgetTester tester, String text) {
    final faded = find.ancestor(
      of: find.text(text),
      matching: find.byType(Opacity),
    );
    if (faded.evaluate().isEmpty) return 1;
    return tester.widget<Opacity>(faded.first).opacity;
  }

  testWidgets('they come one after another, once', (tester) async {
    await tester.pumpWidget(bar('a'));
    expect(opacityOf(tester, 'one'), 0);
    // The first coming, the last not yet.
    await tester.pump(ReplySuggestionBar.delay + ReplySuggestionBar.each * 0.5);
    expect(opacityOf(tester, 'one'), greaterThan(0));
    expect(opacityOf(tester, 'three'), 0);
    await tester.pump(const Duration(seconds: 1));
    for (final text in ['one', 'two', 'three']) {
      expect(opacityOf(tester, text), 1);
    }

    // Shown again for the same: at once.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(bar('a'));
    expect(opacityOf(tester, 'three'), 1);
  });
}
