import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_menu.dart';

final _panels = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_MenuPanel',
);

Future<void> _open(
  WidgetTester tester, {
  required Size size,
  required Rect anchor,
  required List<IdeMenuEntry> entries,
  bool alignRight = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (value) {
          context = value;
          return const Scaffold();
        },
      ),
    ),
  );
  unawaited(
    showIdeMenu(
      context,
      anchor: anchor,
      alignRight: alignRight,
      entries: entries,
    ),
  );
  await tester.pumpAndSettle();
}

void _expectInset(Rect rect, Size size) {
  expect(rect.left, greaterThanOrEqualTo(8));
  expect(rect.top, greaterThanOrEqualTo(8));
  expect(rect.right, lessThanOrEqualTo(size.width - 8));
  expect(rect.bottom, lessThanOrEqualTo(size.height - 8));
}

void main() {
  const size = Size(640, 400);

  for (final position in [
    Offset.zero,
    const Offset(640, 0),
    const Offset(0, 400),
    const Offset(640, 400),
  ]) {
    testWidgets('menu keeps an inset near $position', (tester) async {
      await _open(
        tester,
        size: size,
        anchor: position & Size.zero,
        entries: const [IdeMenuAction('First'), IdeMenuAction('Second')],
      );
      _expectInset(tester.getRect(_panels), size);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('long dropdown scrolls within the window inset', (tester) async {
    var chosen = false;
    await _open(
      tester,
      size: size,
      anchor: const Rect.fromLTWH(400, 300, 100, 26),
      entries: [
        for (var i = 0; i < 50; i++) IdeMenuAction('Sound $i'),
        IdeMenuAction('Choose a File', onSelected: () => chosen = true),
      ],
    );
    final panel = tester.getRect(_panels);
    _expectInset(panel, size);
    expect(panel.top, 8);
    expect(panel.bottom, size.height - 8);
    final scroll = find.descendant(
      of: _panels,
      matching: find.byType(Scrollable),
    );
    final state = tester.state<ScrollableState>(scroll);
    expect(state.position.maxScrollExtent, greaterThan(0));
    await tester.drag(scroll, const Offset(0, -1600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a File'));
    await tester.pumpAndSettle();
    expect(chosen, isTrue);
    expect(_panels, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide right-aligned dropdown stays inside the inset', (
    tester,
  ) async {
    await _open(
      tester,
      size: size,
      anchor: const Rect.fromLTWH(540, 200, 100, 26),
      alignRight: true,
      entries: [IdeMenuAction(List.filled(100, 'Long label').join(' '))],
    );
    final panel = tester.getRect(_panels);
    _expectInset(panel, size);
    expect(panel.width, size.width - 16);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submenu flips left and keeps the window inset', (tester) async {
    await _open(
      tester,
      size: size,
      anchor: const Rect.fromLTWH(620, 380, 20, 20),
      entries: const [
        IdeMenuAction('Parent', submenu: [IdeMenuAction('Child')]),
      ],
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_panels, findsNWidgets(2));
    final parent = tester.getRect(_panels.first);
    final submenu = tester.getRect(_panels.last);
    _expectInset(parent, size);
    _expectInset(submenu, size);
    expect(submenu.left, lessThan(parent.left));
    expect(tester.takeException(), isNull);
  });
}
