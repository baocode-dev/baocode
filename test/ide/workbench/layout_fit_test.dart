import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/ide_columns.dart';
import 'package:monad/ide/ide_layout.dart';
import 'package:monad/ide/ide_modern_ui.dart';
import 'package:monad/theme/codicons.dart';
import 'package:monad/workspace/back_to_chat_button.dart';

import '../../title_bar_double_click_test.dart'
    show doubleClickAt, recordWindowCalls, titleDoubleClicks;
import 'fake_files.dart';

Finder _part(String key) => find.byKey(ValueKey(key));

double _width(WidgetTester tester, String key) =>
    tester.getSize(_part(key)).width;

void main() {
  testWidgets('with no room for both, the side bar opened closes the chat, '
      'and the chat opened closes the side bar', (tester) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.txt': 'a'},
      open: ['a.txt'],
      size: const Size(740, 800),
    );
    await tester.pump();
    // The side bar gave way to the chat: its toggle is off.
    expect(_part('ide-sidebar'), findsNothing);
    expect(workspace.layout.sidebar, isTrue);
    expect(workspace.layout.sidebarVisible, isFalse);
    expect(find.byIcon(Codicons.layoutSidebarLeftOff), findsOneWidget);

    // Its view's icon opens it, rather than hide what does not show.
    await tester.tap(find.byIcon(Codicons.files));
    await tester.pump();
    expect(_part('ide-sidebar'), findsOneWidget);
    expect(find.byKey(chatKey), findsNothing);
    expect(workspace.layout.chat, isFalse);
    expect(find.byIcon(Codicons.layoutSidebarLeft), findsOneWidget);
    // Again, it hides.
    await tester.tap(find.byIcon(Codicons.files));
    await tester.pump();
    expect(_part('ide-sidebar'), findsNothing);
    await tester.tap(find.byIcon(Codicons.files));
    await tester.pump();

    await tester.tap(find.byIcon(Codicons.layoutSidebarRightOff));
    await tester.pump();
    expect(find.byKey(chatKey), findsOneWidget);
    expect(_part('ide-sidebar'), findsNothing);
    expect(workspace.layout.sidebar, isFalse);

    // The title bar's toggle as well.
    await tester.tap(find.byIcon(Codicons.layoutSidebarLeftOff));
    await tester.pump();
    expect(_part('ide-sidebar'), findsOneWidget);
    expect(find.byKey(chatKey), findsNothing);
  });

  testWidgets('with room for both, one opened leaves the other', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(tester, {'a.txt': 'a'});
    await tester.pump();
    await tester.tap(find.byIcon(Codicons.layoutSidebarRight));
    await tester.pump();
    await tester.tap(find.byIcon(Codicons.layoutSidebarRightOff));
    await tester.pump();
    expect(workspace.layout.sidebarVisible, isTrue);
    expect(find.byKey(chatKey), findsOneWidget);
  });

  testWidgets('the chat\'s sash dragged on past the editor\'s minimum '
      'maximizes the chat, the panel below it, and the editor comes back '
      'with the pointer', (tester) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.txt': 'a'},
      open: ['a.txt'],
    );
    await tester.tap(find.byIcon(Codicons.layoutPanelOff));
    await tester.pump();
    final chat = tester.element(find.byKey(chatKey));
    final panelHeight = tester.getSize(_part('ide-panel')).height;

    final drag = await tester.startGesture(
      tester.getCenter(_part('ide-chat-sash')),
    );
    // Of 1340, the side bar snaps shut at a chat of 878⅓, and the editor
    // at 1073⅓.
    await drag.moveBy(const Offset(-20, 0));
    await drag.moveBy(const Offset(-633, 0));
    await tester.pump();
    expect(_part('ide-sidebar'), findsNothing);
    expect(_width(tester, 'ide-editor'), IdeColumns.minEditor);
    await drag.moveBy(const Offset(-1, 0));
    await tester.pump();
    expect(workspace.layout.chatMaximized, isTrue);
    expect(_part('ide-editor'), findsNothing);
    const left = IdeModernUI.gap + IdeModernUI.activityBarWidth;
    expect(tester.getRect(_part('ide-chat-sash')).left, left);
    final maximized = tester.getRect(_part('ide-chat'));
    expect(maximized.left, left + IdeModernUI.gap);
    expect(maximized.right, 1400 - IdeModernUI.gap);
    // The panel below it, as high as it was.
    final panel = tester.getRect(_part('ide-panel'));
    expect(panel.left, maximized.left);
    expect(panel.right, maximized.right);
    expect(panel.top, maximized.bottom + IdeModernUI.gap);
    expect(panel.height, closeTo(panelHeight, 0.01));
    // The same chat, moved.
    expect(tester.element(find.byKey(chatKey)), same(chat));
    expect(find.byIcon(Codicons.layoutSidebarLeftOff), findsOneWidget);

    // Back, the editor comes out at its minimum.
    await drag.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(workspace.layout.chatMaximized, isFalse);
    expect(_width(tester, 'ide-editor'), IdeColumns.minEditor);
    expect(_width(tester, 'ide-chat'), 1020);
    expect(tester.getRect(_part('ide-panel')).left, left + IdeModernUI.gap);
    expect(tester.element(find.byKey(chatKey)), same(chat));
    await drag.up();
    await tester.pump();
    // The double click's wait.
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('showing the side bar, hiding the chat, or opening an editor '
      'ends the chat\'s maximizing', (tester) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.txt': 'a', 'b.txt': 'b'},
      open: ['a.txt'],
    );
    Future<void> maximize() async {
      await tester.drag(_part('ide-chat-sash'), const Offset(-1000, 0));
      await tester.pump();
      expect(workspace.layout.chatMaximized, isTrue);
      expect(_part('ide-editor'), findsNothing);
      await tester.pump(kDoubleTapTimeout);
    }

    await maximize();
    await tester.tap(find.byIcon(Codicons.files));
    await tester.pump();
    expect(workspace.layout.chatMaximized, isFalse);
    expect(_part('ide-sidebar'), findsOneWidget);
    expect(_part('ide-editor'), findsOneWidget);
    // As wide as when the drag began.
    expect(_width(tester, 'ide-chat'), IdeColumns.defaultChat);

    await maximize();
    await tester.tap(find.byIcon(Codicons.layoutSidebarRight));
    await tester.pump();
    expect(workspace.layout.chatMaximized, isFalse);
    expect(find.byKey(chatKey), findsNothing);
    expect(_part('ide-editor'), findsOneWidget);
    await tester.tap(find.byIcon(Codicons.layoutSidebarRightOff));
    await tester.pump();

    await maximize();
    await workspace.open(inRoot('b.txt'));
    await tester.pump();
    expect(workspace.layout.chatMaximized, isFalse);
    expect(_part('ide-editor'), findsOneWidget);
    expect(find.byKey(chatKey), findsOneWidget);

    // Its sash's double click, too.
    await maximize();
    await tester.tap(_part('ide-chat-sash'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(_part('ide-chat-sash'));
    await tester.pumpAndSettle();
    expect(workspace.layout.chatMaximized, isFalse);
    expect(_width(tester, 'ide-chat'), IdeColumns.defaultChat);
  });

  testWidgets(
    'a double click on the title bar\'s empty part zooms the window; on its '
    'controls, the gaps between them included, it does not',
    (tester) async {
      final calls = recordWindowCalls(tester);
      await pumpWorkbench(tester, {'a.txt': 'a'});
      final panel = tester.getRect(find.byIcon(Codicons.layoutPanelOff));
      await doubleClickAt(tester, Offset(panel.left - 60, panel.center.dy));
      expect(titleDoubleClicks(calls), 1);
      await tester.pump(kDoubleTapTimeout);

      // Between the chat's toggle and Back to Chat.
      final chat = tester.getRect(find.byType(IdeLayoutToggle).last);
      final back = tester.getRect(find.byType(BackToChatButton));
      expect(back.left - chat.right, greaterThan(4));
      await doubleClickAt(
        tester,
        Offset((chat.right + back.left) / 2, chat.center.dy),
      );
      await tester.pump(kDoubleTapTimeout);
      expect(titleDoubleClicks(calls), 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
