import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/widgets/edit_step.dart';
import 'package:baocode/chat/widgets/step_header.dart';
import 'package:baocode/ide/ide_code_diff.dart';

void main() {
  test('the sides number their lines as their files do, across hunks', () {
    final sides = DiffSides(const [
      DiffLine(DiffLineType.context, 142, 'a'),
      DiffLine(DiffLineType.removed, 143, 'b'),
      DiffLine(DiffLineType.added, 143, 'B'),
      DiffLine(DiffLineType.added, 144, 'B2'),
      DiffLine(DiffLineType.context, 145, 'c'),
      // The next hunk: one line further on the new side than the old.
      DiffLine(DiffLineType.context, 201, 'd'),
      DiffLine(DiffLineType.removed, 201, 'e'),
      DiffLine(DiffLineType.context, 202, 'f'),
    ]);
    expect(sides.original, 'a\nb\nc\nd\ne\nf');
    expect(sides.modified, 'a\nB\nB2\nc\nd\nf');
    expect(sides.originalNumbers, [142, 143, 144, 200, 201, 202]);
    expect(sides.modifiedNumbers, [142, 143, 144, 145, 201, 202]);
    expect(sides.originalNumberOf(4), 200);
    expect(sides.modifiedNumberOf(2), 143);
    expect(sides.created, isFalse);
    expect(sides.rows, 6);
  });

  test('a new file has nothing on the old side', () {
    final sides = DiffSides(const [
      DiffLine(DiffLineType.added, 1, 'one'),
      DiffLine(DiffLineType.added, 2, 'two'),
    ]);
    expect(sides.created, isTrue);
    expect(sides.original, '');
    expect(sides.modified, 'one\ntwo');
    expect(sides.rows, 2);
  });

  testWidgets('the card shows the diff side by side, as tall as its lines', (
    tester,
  ) async {
    const item = CodeDiffItem(
      fileName: 'a.dart',
      directory: 'lib',
      lines: [
        DiffLine(DiffLineType.context, 10, 'final a = 1;'),
        DiffLine(DiffLineType.removed, 11, 'final b = 2;'),
        DiffLine(DiffLineType.added, 11, 'final b = 3;'),
      ],
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: EditStep(item: item)),
      ),
    );
    await tester.pump();
    final diff = tester.widget<IdeCodeDiff>(find.byType(IdeCodeDiff));
    expect(diff.sideBySide, isTrue);
    expect(diff.embedded, isTrue);
    expect(diff.original, 'final a = 1;\nfinal b = 2;');
    expect(diff.modified, 'final a = 1;\nfinal b = 3;');
    expect(diff.originalLineNumberOf!(2), 11);
    final context = tester.element(find.byType(IdeCodeDiff));
    expect(
      tester.getSize(find.byType(IdeCodeDiff)).height,
      2 * IdeCodeDiff.lineHeight(context),
    );
  });

  group('a card taller than it shows', () {
    final item = CodeDiffItem(
      fileName: 'a.dart',
      directory: 'lib',
      lines: [
        for (var i = 1; i <= 40; i++)
          DiffLine(
            DiffLineType.added,
            i,
            'final value$i = ${'"${'x' * 120}"'};',
          ),
      ],
    );

    Future<ScrollController> pumpInList(WidgetTester tester) async {
      final outer = ScrollController();
      addTearDown(outer.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: outer,
              children: [
                const SizedBox(height: 100),
                EditStep(item: item),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return outer;
    }

    ScrollPosition inner(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(StepBody),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;

    testWidgets('keeps the wheel at its end, a new gesture too', (
      tester,
    ) async {
      final outer = await pumpInList(tester);
      final at = tester.getCenter(find.byType(StepBody));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      var clock = const Duration(seconds: 1);
      Future<void> wheel() async {
        clock += const Duration(milliseconds: 50);
        await tester.sendEventToBinding(pointer.hover(at, timeStamp: clock));
        await tester.sendEventToBinding(
          pointer.scroll(const Offset(0, 120), timeStamp: clock),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }

      for (var i = 0; i < 20; i++) {
        await wheel();
      }
      await tester.pumpAndSettle();
      final position = inner(tester);
      expect(position.pixels, position.maxScrollExtent);
      // A pause, then the wheel again: still the card's.
      clock += const Duration(seconds: 1);
      await wheel();
      await tester.pumpAndSettle();
      expect(outer.offset, 0);
    });

    testWidgets('its editors scroll across by bars at its bottom', (
      tester,
    ) async {
      await pumpInList(tester);
      final diff = tester.widget<IdeCodeDiff>(find.byType(IdeCodeDiff));
      final editors = diff.horizontal!.value;
      expect(editors, hasLength(1)); // A new file: the modified alone.
      final editor = editors.single;
      expect(editor.max, greaterThan(0));
      // The bar is at the bottom of what the card shows, not the diff's,
      // out of view.
      final shown = tester.getRect(
        find
            .descendant(
              of: find.byType(StepBody),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final bar = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_AcrossBar',
      );
      expect(tester.getRect(bar).bottom, shown.bottom);
      expect(
        shown.bottom,
        lessThan(tester.getRect(find.byType(IdeCodeDiff)).bottom),
      );
      // Dragged, the editor scrolls across.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      final thumb = find.descendant(
        of: bar,
        matching: find.byType(GestureDetector),
      );
      await mouse.down(tester.getCenter(thumb));
      await mouse.moveBy(const Offset(40, 0));
      await mouse.moveBy(const Offset(40, 0));
      await mouse.up();
      await tester.pump();
      expect(editor.scroll.value.dx, greaterThan(0));
    });
  });
}
