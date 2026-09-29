import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/ide_hover.dart';
import 'package:monad/theme/codicons.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );

  Future<void> hover(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(target));
    await tester.pump();
  }

  testWidgets('shows after the workbench delay, in the workbench look', (
    tester,
  ) async {
    await pump(
      tester,
      IdeActionButton(
        icon: Codicons.refresh,
        tooltip: 'Refresh Explorer',
        onPressed: () {},
      ),
    );
    // Screen readers and finders see it as the tooltip.
    expect(find.byTooltip('Refresh Explorer'), findsOneWidget);
    await hover(tester, find.byIcon(Codicons.refresh));
    await tester.pump(ideHoverDelay - const Duration(milliseconds: 50));
    expect(find.text('Refresh Explorer'), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Refresh Explorer'), findsOneWidget);

    final box = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.text('Refresh Explorer'),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, IdeHoverColors.background);
    expect(decoration.border, Border.all(color: IdeHoverColors.border));
    expect(decoration.borderRadius, BorderRadius.circular(5));
    final text = tester.widget<Text>(find.text('Refresh Explorer'));
    final style = DefaultTextStyle.of(
      tester.element(find.text('Refresh Explorer')),
    ).style.merge(text.style);
    expect(style.fontSize, 12);
    expect(style.color, IdeHoverColors.foreground);
    // Below the button, centered on it.
    final hoverRect = tester.getRect(find.byWidget(box));
    final target = tester.getRect(find.byType(IdeActionButton));
    expect(hoverRect.top, greaterThan(target.bottom));
    expect(hoverRect.center.dx, closeTo(target.center.dx, 1));
  });

  testWidgets('the delay is VS Code\'s: 1500 ms on macOS, else 500 ms', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(ideHoverDelay, const Duration(milliseconds: 1500));
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(ideHoverDelay, const Duration(milliseconds: 500));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a hover with a pointer sits beside its target', (tester) async {
    await pump(
      tester,
      const IdeHover(
        message: 'Explorer',
        position: IdeHoverPosition.right,
        pointer: true,
        child: SizedBox(width: 48, height: 48, child: Icon(Codicons.files)),
      ),
    );
    await hover(tester, find.byIcon(Codicons.files));
    await tester.pump(ideHoverDelay + const Duration(milliseconds: 150));
    final hoverRect = tester.getRect(
      find
          .ancestor(
            of: find.text('Explorer'),
            matching: find.byType(IdeHoverBox),
          )
          .first,
    );
    final target = tester.getRect(find.byType(SizedBox).last);
    expect(hoverRect.left, greaterThan(target.right));
    expect(hoverRect.center.dy, closeTo(target.center.dy, 1));
  });

  test('codicons are the pinned VS Code ones, and the font is bundled', () {
    // Spot checks against src/vs/base/common/codiconsLibrary.ts.
    expect(Codicons.files.codePoint, 0xeaf0);
    expect(Codicons.search.codePoint, 0xea6d);
    expect(Codicons.symbolClass.codePoint, 0xeb5b);
    expect(Codicons.lightBulb.codePoint, 0xea61);
    expect(Codicons.byName['source-control'], Codicons.sourceControl);
    expect(Codicons.files.fontFamily, 'codicon');
    expect(File('assets/codicons/codicon.ttf').lengthSync(), greaterThan(0));
    expect(
      File('assets/codicons/LICENSE').readAsStringSync(),
      contains('Attribution 4.0 International'),
    );
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('asset: assets/codicons/codicon.ttf'),
    );
  });
}
