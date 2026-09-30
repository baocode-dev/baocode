import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/ide_input.dart';

void main() {
  testWidgets('a multi-line input scrolls without a scrollbar', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = TextEditingController(
      text: List.generate(30, (i) => 'line $i').join('\n'),
    );
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
}
