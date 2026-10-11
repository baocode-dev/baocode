import 'dart:ui' show PointerDeviceKind;

import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/upstream.dart';
import 'package:baocode/settings/pages/model_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    int count = 4,
    bool selected = false,
  }) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: FetchModelsDialog(
          provider: ModelProvider(
            id: 'p',
            name: 'Picker',
            models: [if (selected) const ProviderModel(id: 'm000')],
          ),
          keyOf: () async => null,
          list: (_, _) async => [
            for (var i = 0; i < count; i++)
              RemoteModel('m${i.toString().padLeft(3, '0')}'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder box(String id) => find.byWidgetPredicate(
    (widget) => widget is ModelCheckbox && widget.semanticLabel == id,
  );
  bool checked(WidgetTester tester, String id) =>
      tester.widget<ModelCheckbox>(box(id)).checked;

  testWidgets(
    'fast mouse drag from checkbox paints skipped rows and does not retoggle',
    (tester) async {
      await open(tester);
      final first = tester.getCenter(box('m000'));
      final last = tester.getCenter(box('m003'));
      final gesture = await tester.startGesture(
        first,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(checked(tester, 'm000'), isTrue);
      await gesture.moveTo(last);
      await tester.pump();
      expect(find.text('4 of 4 checked'), findsOneWidget);
      await gesture.moveTo(first);
      await gesture.up();
      await tester.pump();
      expect(find.text('4 of 4 checked'), findsOneWidget);
      final deselect = await tester.startGesture(
        first,
        kind: PointerDeviceKind.mouse,
      );
      await deselect.moveTo(last);
      await deselect.up();
      await tester.pump();
      expect(find.text('0 of 4 checked'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'starting checked paints deselection; row text and blank space are hot areas',
    (tester) async {
      await open(tester, selected: true);
      await tester.tap(find.text('Select All'));
      await tester.pump();
      final first = tester.getCenter(find.text('m000'));
      final last = tester.getCenter(find.text('m003'));
      final gesture = await tester.startGesture(
        first,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(last);
      await gesture.up();
      await tester.pump();
      expect(find.text('0 of 4 checked'), findsOneWidget);
      // Right of the checkbox/text, still inside the selectable row.
      await tester.tapAt(first + const Offset(200, 0));
      await tester.pump();
      expect(checked(tester, 'm000'), isTrue);
      await tester.tapAt(tester.getCenter(box('m000')));
      await tester.pump();
      expect(checked(tester, 'm000'), isFalse);
    },
  );

  testWidgets('cancel and right button do not leak a selection stroke', (
    tester,
  ) async {
    await open(tester);
    final right = await tester.startGesture(
      tester.getCenter(box('m000')),
      kind: PointerDeviceKind.mouse,
      buttons: 2,
    );
    await right.up();
    await tester.pump();
    expect(find.text('0 of 4 checked'), findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(box('m000')));
    await gesture.cancel();
    await tester.pump();
    expect(find.text('1 of 4 checked'), findsOneWidget);
    await tester.tap(find.text('Select None'));
    await tester.pump();
    expect(find.text('0 of 4 checked'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'm003');
    await tester.pump();
    await tester.tapAt(tester.getCenter(box('m003')));
    await tester.pump();
    expect(find.text('1 of 4 checked'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('edge dragging scrolls to lazy rows, release stops scrolling', (
    tester,
  ) async {
    await open(tester, count: 80);
    final list = find.byType(ListView);
    final rect = tester.getRect(list);
    final x = tester.getCenter(box('m000')).dx;
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(box('m000')),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(Offset(x, rect.bottom - 6));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scrollable.position.pixels, greaterThan(80));
    expect(
      tester.widget<ModelCheckbox>(find.byType(ModelCheckbox).last).checked,
      isTrue,
    );
    await gesture.up();
    await tester.pump();
    final offset = scrollable.position.pixels;
    await tester.pump(const Duration(milliseconds: 150));
    expect(scrollable.position.pixels, offset);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
