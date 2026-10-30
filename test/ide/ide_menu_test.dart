import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_menu.dart';
import 'package:baocode/theme/app_theme.dart' show AppMetrics;
import 'package:baocode/theme/codicons.dart';

final _panels = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_MenuPanel',
);

Future<void> _open(
  WidgetTester tester, {
  required Size size,
  required Rect anchor,
  required List<IdeMenuEntry> entries,
  bool alignRight = false,
  bool iconsInCheckColumn = false,
  bool speedSearch = false,
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
      iconsInCheckColumn: iconsInCheckColumn,
      speedSearch: speedSearch,
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

  testWidgets('speed search filters a menu as it is typed over', (
    tester,
  ) async {
    String? chosen;
    await _open(
      tester,
      size: size,
      anchor: const Rect.fromLTWH(20, 20, 100, 26),
      speedSearch: true,
      entries: [
        IdeMenuAction('No project', onSelected: () => chosen = 'none'),
        const IdeMenuSeparator(),
        for (final name in ['baocode', 'bank_info_ocr', 'demo'])
          IdeMenuAction(name, onSelected: () => chosen = name),
      ],
    );
    Future<void> type(List<LogicalKeyboardKey> keys) async {
      for (final key in keys) {
        await tester.sendKeyEvent(key);
        await tester.pump();
      }
    }

    await type([LogicalKeyboardKey.keyB, LogicalKeyboardKey.keyK]);
    expect(find.text('bk'), findsOneWidget);
    expect(find.text('1/4'), findsOneWidget);
    expect(find.text('baocode'), findsNothing);
    expect(find.text('No project'), findsNothing);
    final label = tester.widget<Text>(find.text('bank_info_ocr'));
    expect((label.textSpan! as TextSpan).children, isNotNull);

    // Back to nothing, every action is listed again.
    await type([LogicalKeyboardKey.backspace, LogicalKeyboardKey.backspace]);
    expect(find.text('baocode'), findsOneWidget);
    expect(find.text('No project'), findsOneWidget);

    await type([LogicalKeyboardKey.keyD]);
    expect(find.text('0/4'), findsNothing);
    await type([LogicalKeyboardKey.keyQ]);
    expect(find.text('0/4'), findsOneWidget);
    // Escape clears the search first, then closes.
    await type([LogicalKeyboardKey.escape]);
    expect(find.text('dq'), findsNothing);
    expect(_panels, findsOneWidget);

    // Enter picks the best match, focused.
    await type([LogicalKeyboardKey.keyD, LogicalKeyboardKey.enter]);
    await tester.pumpAndSettle();
    expect(_panels, findsNothing);
    expect(chosen, 'demo');
  });

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

  // #198: the window drags itself by the header Windows draws, so a first
  // item over it could not be chosen.
  testWidgets('long dropdown stays below the window\'s own header on Windows', (
    tester,
  ) async {
    var chosen = false;
    await _open(
      tester,
      size: size,
      anchor: const Rect.fromLTWH(400, 300, 100, 26),
      entries: [
        IdeMenuAction('First', onSelected: () => chosen = true),
        for (var i = 0; i < 50; i++) IdeMenuAction('Sound $i'),
      ],
    );
    final panel = tester.getRect(_panels);
    expect(panel.top, AppMetrics.headerHeight);
    expect(panel.bottom, size.height - 8);
    expect(
      tester.getRect(find.text('First')).top,
      greaterThan(AppMetrics.headerHeight),
    );
    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();
    expect(chosen, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

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

  testWidgets('an icon given bare is the label\'s size and color', (
    tester,
  ) async {
    await _open(
      tester,
      size: size,
      anchor: const Rect.fromLTWH(20, 20, 100, 26),
      entries: const [
        IdeMenuAction('Disconnect', icon: Icon(Codicons.debugDisconnect)),
      ],
    );
    final glyph = tester.getRect(
      find.descendant(
        of: find.byIcon(Codicons.debugDisconnect),
        matching: find.byType(RichText),
      ),
    );
    expect(glyph.size, const Size(16, 16));
    expect(glyph.right, lessThan(tester.getRect(find.text('Disconnect')).left));
    final label = tester.widget<Text>(find.text('Disconnect')).style!.color;
    final icon = tester.element(find.byIcon(Codicons.debugDisconnect));
    expect(IconTheme.of(icon).color, label);
    expect(tester.takeException(), isNull);
  });

  testWidgets('icons in the check column: where a check is, at the panel\'s '
      'start; one checked shows its check instead', (tester) async {
    await _open(
      tester,
      size: size,
      anchor: const Rect.fromLTWH(20, 20, 100, 26),
      iconsInCheckColumn: true,
      entries: const [
        IdeMenuAction('Copy', icon: Icon(Codicons.copy)),
        IdeMenuAction('Left', icon: Icon(Codicons.arrowLeft), checked: true),
      ],
    );
    final panel = tester.getRect(_panels);
    final copy = tester.getRect(find.byIcon(Codicons.copy));
    expect(copy.size, const Size(16, 16));
    expect(copy.left - panel.left, lessThan(26));
    expect(copy.right, lessThan(tester.getRect(find.text('Copy')).left));
    // The labels where they are with no icons.
    expect(
      tester.getRect(find.text('Copy')).left,
      tester.getRect(find.text('Left')).left,
    );
    expect(find.byIcon(Codicons.arrowLeft), findsNothing);
    expect(find.byIcon(Codicons.menuSelection), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an action kept open toggles in place, its check read anew; '
      'another closes it', (tester) async {
    final picked = <String>{};
    var all = 0;
    await _open(
      tester,
      size: size,
      anchor: const Rect.fromLTWH(20, 20, 100, 26),
      entries: [
        IdeMenuAction(
          'All',
          checkedNow: () => picked.isEmpty,
          onSelected: () => all++,
        ),
        for (final name in ['One', 'Two'])
          IdeMenuAction(
            name,
            keepOpen: true,
            checkedNow: () => picked.contains(name),
            onSelected: () {
              if (!picked.remove(name)) picked.add(name);
            },
          ),
      ],
    );
    Finder checks() => find.descendant(
      of: _panels,
      matching: find.byIcon(Codicons.menuSelection),
    );
    expect(checks(), findsOneWidget);
    await tester.tap(find.text('One'));
    await tester.pump();
    await tester.tap(find.text('Two'));
    await tester.pump();
    expect(picked, {'One', 'Two'});
    expect(_panels, findsOneWidget);
    // All's check went with the first one picked.
    expect(checks(), findsNWidgets(2));
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(_panels, findsNothing);
    expect(all, 1);
  });
}
