import 'package:baocode/ide/ide_drag_selection.dart';
import 'package:baocode/settings/pages/model_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpList(
    WidgetTester tester,
    List<bool> values, {
    ScrollController? scroll,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Center(
              child: SizedBox(
                width: 100,
                height: 200,
                child: IdeDragSelection(
                  scrollController: scroll,
                  child: ListView.builder(
                    controller: scroll,
                    itemExtent: 40,
                    itemCount: values.length,
                    itemBuilder: (context, index) => Center(
                      child: ModelCheckbox(
                        key: ValueKey(index),
                        checked: values[index],
                        dragSelect: true,
                        semanticLabel: 'Row $index',
                        onChanged: (value) =>
                            setState(() => values[index] = value),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('fast stroke selects skipped rows and revisits do not toggle', (
    tester,
  ) async {
    final values = [false, true, false, false];
    await pumpList(tester, values);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey(0))),
    );
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey(3))));
    await tester.pump();
    expect(values, [true, true, true, true]);
    await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey(0))));
    await gesture.up();
    await tester.pump();
    expect(values, [true, true, true, true]);
    final clear = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey(0))),
    );
    await clear.moveTo(tester.getCenter(find.byKey(const ValueKey(3))));
    await clear.up();
    await tester.pump();
    expect(values, [false, false, false, false]);
  });

  testWidgets(
    'pointer cancellation ends stroke and a click changes only once',
    (tester) async {
      final values = [false, false];
      await pumpList(tester, values);
      await tester.tap(find.byKey(const ValueKey(0)));
      await tester.pump();
      expect(values, [true, false]);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey(0))),
      );
      await gesture.cancel();
      await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey(1))));
      await tester.pump();
      expect(values, [false, false]);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('edge drag auto-scrolls and selects newly laid out rows', (
    tester,
  ) async {
    final values = List.filled(20, false);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpList(tester, values, scroll: controller);
    final first = tester.getCenter(find.byKey(const ValueKey(0)));
    final gesture = await tester.startGesture(first);
    await gesture.moveTo(first + const Offset(0, 175));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.offset, greaterThan(0));
    expect(values.where((value) => value).length, greaterThan(4));
    await gesture.up();
    await tester.pump();
    final offset = controller.offset;
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, offset);
    await tester.pumpWidget(const SizedBox());
  });
}
