import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/chat_screen.dart';
import 'package:monad/chat/chat_history_view.dart';
import 'package:monad/chat/widgets/user_message_bubble.dart';
import 'package:monad/main.dart';
import 'package:monad/sidebar/sidebar.dart';
import 'package:monad/theme/app_theme.dart';
import 'package:monad/workspace/workspace.dart';

import 'first_frame_test.dart' show LongTurnFeed;

/// The app. The test's variant picks the platform; macOS and Windows 11
/// have the system's material under the window.
Future<void> pumpMacApp(WidgetTester tester, {double width = 1400}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MonadApp(workspace: Workspace.mock()));
  await tester.pump();
}

/// The colors painted under [finder], nearest first.
List<Color> colorsUnder(WidgetTester tester, Finder finder) => [
  for (final widget in tester.widgetList(
    find.ancestor(of: finder, matching: find.byType(ColoredBox)),
  ))
    (widget as ColoredBox).color,
];

Color sidebarColor(WidgetTester tester) => tester
    .widget<Material>(
      find
          .descendant(of: find.byType(Sidebar), matching: find.byType(Material))
          .first,
    )
    .color!;

void main() {
  testWidgets('on macOS nothing of the transcript shows around the stuck '
      'message, and nothing is painted over it', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final feed = LongTurnFeed();
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _app,
        child: MaterialApp(
          // Its ribbon is in the top corner, over what is measured.
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: ColoredBox(
            color: AppColors.conversationSurface,
            child: ChatHistoryView(feed: feed),
          ),
        ),
      ),
    );
    await tester.pump();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final tint = (AppColors.conversationSurface.a * 255).round();
    for (var step = 0; step < 8; step++) {
      position.jumpTo(position.pixels - 3);
      await tester.pump();
      final bubble = tester.getRect(
        find.byWidgetPredicate(
          (widget) =>
              widget is UserMessageBubble &&
              widget.key == const ValueKey(('sticky', LongTurnFeed.message)),
        ),
      );
      // Just under it, where the transcript only begins to fade back in:
      // next to nothing of the text scrolling beneath shows.
      for (var y = bubble.bottom + 0.5; y < bubble.bottom + 3; y += 0.5) {
        expect(
          await alphaAcross(tester, y, bubble.left + 8, bubble.right - 8),
          everyElement(lessThanOrEqualTo(tint + 4)),
          reason: 'row $y at step $step',
        );
      }
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('on macOS the conversation tints the material evenly, with '
      'no seam, at any width', (tester) async {
    tester.view.physicalSize = const Size(2800, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _app,
        child: MonadApp(workspace: Workspace.mock()),
      ),
    );
    await tester.pump();
    // A width that ends mid-pixel.
    final edge = tester.getTopRight(find.byType(Sidebar)).dx;
    final drag = await tester.startGesture(Offset(edge + 2, 400));
    await drag.moveBy(const Offset(10, 0));
    await drag.moveBy(const Offset(10.25, 0));
    await drag.up();
    await tester.pumpAndSettle();
    final right = tester.getTopRight(find.byType(Sidebar)).dx;
    expect(right % 0.5, isNot(0));
    // Past the border's line, into the chat.
    expect(
      await alphaAcross(tester, 400, right + 2, right + 40),
      everyElement((AppColors.conversationSurface.a * 255).round()),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('on macOS the sidebar and the conversation both show the '
      'material through', (tester) async {
    await pumpMacApp(tester);
    // The window itself paints nothing over the material.
    expect(colorsUnder(tester, find.byType(Sidebar)), [Colors.transparent]);
    expect(sidebarColor(tester).a, lessThan(0.85));
    expect(colorsUnder(tester, find.byType(ChatScreen)), [
      AppColors.conversationSurface,
      Colors.transparent,
    ]);
    expect(AppColors.conversationSurface.a, lessThan(1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('on macOS the sidebar as a drawer is opaque: over the chat, '
      'not the material', (tester) async {
    await pumpMacApp(tester, width: 700);
    await tester.tap(find.bySemanticsLabel('Show sidebar'));
    await tester.pumpAndSettle();
    expect(colorsUnder(tester, find.byType(Sidebar)).first.a, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'on Windows 11 the sidebar and the conversation both show the '
    'material through',
    (tester) async {
      await pumpMacApp(tester);
      expect(colorsUnder(tester, find.byType(Sidebar)), [Colors.transparent]);
      // Acrylic is a thinner blur than macOS's sidebar material: 96% over
      // the sidebar, 98% over the conversation (see AppColors).
      expect(sidebarColor(tester).a, closeTo(0.96, 0.001));
      expect(colorsUnder(tester, find.byType(ChatScreen)), [
        AppColors.conversationSurface,
        Colors.transparent,
      ]);
      expect(AppColors.conversationSurface.a, closeTo(0.98, 0.001));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    skip: _hostIsWindows10,
  );

  testWidgets(
    'on Windows 11 the sidebar as a drawer is opaque: over the '
    'chat, not the material',
    (tester) async {
      await pumpMacApp(tester, width: 700);
      await tester.tap(find.bySemanticsLabel('Show sidebar'));
      await tester.pumpAndSettle();
      expect(colorsUnder(tester, find.byType(Sidebar)).first.a, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    skip: _hostIsWindows10,
  );

  testWidgets('elsewhere the window is opaque throughout', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MonadApp(workspace: Workspace.mock()));
    await tester.pump();
    expect(colorsUnder(tester, find.byType(Sidebar)).first.a, 1);
    expect(sidebarColor(tester).a, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}

/// This machine is Windows 10: the Windows target stays opaque there, so
/// the Windows 11 material tests do not apply.
bool get _hostIsWindows10 {
  if (!Platform.isWindows) return false;
  final match = RegExp(r'Build (\d+)')
      .firstMatch(Platform.operatingSystemVersion);
  final build = int.tryParse(match?.group(1) ?? '') ?? 0;
  return build != 0 && build < 22000;
}

final _app = GlobalKey();

/// How opaque the app (pumped under [_app]) paints each pixel of a row
/// across [from]..[to] (logical), at 2x.
Future<List<int>> alphaAcross(
  WidgetTester tester,
  double y,
  double from,
  double to,
) async {
  final boundary =
      _app.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    return (width: image.width, data: (await image.toByteData())!);
  }))!;
  return [
    for (var x = (from * 2).round(); x < (to * 2).round(); x++)
      bytes.data.getUint8(((y * 2).round() * bytes.width + x) * 4 + 3),
  ];
}
