import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_columns.dart';
import 'package:baocode/ide/ide_layout.dart';
import 'package:baocode/ide/ide_modern_ui.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/workspace/back_to_chat_button.dart';

import '../../title_bar_double_click_test.dart'
    show doubleClickAt, recordWindowCalls, titleDoubleClicks;
import 'fake_files.dart';

Finder _part(String key) => find.byKey(ValueKey(key));

double _width(WidgetTester tester, String key) =>
    tester.getSize(_part(key)).width;

void main() {
  testWidgets('with no room for the three, the side bar opened has the '
      'editor give way, the panel below the two; the side bar hidden, the '
      'chat has its room; an editor opened, the editor is back', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.txt': 'a', 'b.txt': 'b'},
      open: ['a.txt'],
      size: const Size(740, 800),
    );
    await tester.pump();
    // The side bar gave way to the chat: its toggle is off.
    expect(_part('ide-sidebar'), findsNothing);
    expect(workspace.layout.sidebar, isTrue);
    expect(workspace.layout.sidebarVisible, isFalse);
    expect(find.byIcon(Codicons.layoutSidebarLeftOff), findsOneWidget);
    final chat = tester.element(find.byKey(chatKey));

    // Its view's icon opens it, rather than hide what does not show.
    await tester.tap(find.byIcon(Codicons.files));
    await tester.pump();
    expect(_part('ide-editor'), findsNothing);
    expect(workspace.layout.editorVisible, isFalse);
    final sidebar = tester.getRect(_part('ide-sidebar'));
    final beside = tester.getRect(_part('ide-chat'));
    expect(sidebar.left, IdeModernUI.activityBarWidth);
    expect(beside.left, sidebar.right);
    expect(beside.right, 740);
    expect(tester.element(find.byKey(chatKey)), same(chat));
    expect(find.byIcon(Codicons.layoutSidebarLeft), findsOneWidget);

    // The panel below the two.
    await tester.tap(find.byIcon(Codicons.layoutPanelOff));
    await tester.pump();
    final top = tester.getRect(_part('ide-sidebar'));
    final panel = tester.getRect(_part('ide-panel'));
    expect(tester.getRect(_part('ide-chat')).bottom, top.bottom);
    expect(panel.top, top.bottom);
    expect(panel.left, top.left);
    expect(panel.right, beside.right);

    // Hidden again, the chat has its room, not the editor.
    await tester.tap(find.byIcon(Codicons.files));
    await tester.pump();
    expect(_part('ide-sidebar'), findsNothing);
    expect(_part('ide-editor'), findsNothing);
    expect(workspace.layout.chatMaximized, isTrue);
    expect(tester.element(find.byKey(chatKey)), same(chat));

    // An editor opened beside the side bar has the chat give way.
    await tester.tap(find.byIcon(Codicons.files));
    await tester.pump();
    expect(_part('ide-editor'), findsNothing);
    await workspace.open(inRoot('b.txt'));
    await tester.pump();
    expect(_part('ide-editor'), findsOneWidget);
    expect(_part('ide-sidebar'), findsOneWidget);
    expect(find.byKey(chatKey), findsNothing);
    expect(workspace.layout.chat, isFalse);

    // The chat shown again, the editor gives way; the active one clicked in
    // the explorer, it is back.
    await tester.tap(find.byIcon(Codicons.layoutSidebarRightOff));
    await tester.pump();
    expect(_part('ide-editor'), findsNothing);
    // The explorer's row, not the timeline's title.
    await tester.tap(find.text('b.txt').first);
    await tester.pumpAndSettle();
    expect(_part('ide-editor'), findsOneWidget);
    expect(_part('ide-sidebar'), findsOneWidget);
    expect(find.byKey(chatKey), findsNothing);
  });

  testWidgets('with no room for the three, an editor opened with the side bar '
      'hidden has the side bar give way', (tester) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.txt': 'a', 'b.txt': 'b'},
      open: ['a.txt'],
      size: const Size(740, 800),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Codicons.files));
    await tester.pump();
    await tester.tap(find.byIcon(Codicons.files));
    await tester.pump();
    expect(workspace.layout.chatMaximized, isTrue);
    await workspace.open(inRoot('b.txt'));
    await tester.pump();
    expect(_part('ide-editor'), findsOneWidget);
    expect(_part('ide-sidebar'), findsNothing);
    expect(find.byKey(chatKey), findsOneWidget);
  });

  testWidgets('with no room for the three and no editor asked for, the '
      'editor gives way first, then the side bar; both back as the window '
      'widens', (tester) async {
    final workspace = await pumpWorkbench(tester, {
      'a.txt': 'a',
    }, size: const Size(740, 800));
    await tester.pump();
    expect(_part('ide-editor'), findsNothing);
    expect(_part('ide-sidebar'), findsOneWidget);
    expect(find.byKey(chatKey), findsOneWidget);
    expect(workspace.layout.editorHidden, isFalse);

    // Too narrow even for the two: the chat alone.
    tester.view.physicalSize = const Size(560, 800);
    await tester.pump();
    await tester.pump();
    expect(_part('ide-sidebar'), findsNothing);
    expect(workspace.layout.sidebar, isTrue);
    expect(workspace.layout.chatMaximized, isTrue);

    tester.view.physicalSize = const Size(1400, 800);
    await tester.pump();
    await tester.pump();
    expect(_part('ide-editor'), findsOneWidget);
    expect(_part('ide-sidebar'), findsOneWidget);
    expect(find.byKey(chatKey), findsOneWidget);
  });

  testWidgets('beside the chat in the editor\'s place, the side bar dragged '
      'shut gives the editor back, and back again, takes it', (tester) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.txt': 'a'},
      open: ['a.txt'],
      size: const Size(740, 800),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Codicons.files));
    await tester.pump();
    expect(_width(tester, 'ide-sidebar'), IdeColumns.defaultSidebar);

    final drag = await tester.startGesture(
      tester.getCenter(_part('ide-sidebar-sash')),
    );
    // At its minimum, short of snapping shut.
    await drag.moveBy(const Offset(-20, 0));
    await drag.moveBy(const Offset(-70, 0));
    await tester.pump();
    expect(_width(tester, 'ide-sidebar'), IdeColumns.minSidebar);
    await drag.moveBy(const Offset(-10, 0));
    await tester.pump();
    expect(_part('ide-sidebar'), findsNothing);
    expect(_part('ide-editor'), findsOneWidget);
    expect(workspace.layout.editorVisible, isTrue);
    await drag.moveBy(const Offset(100, 0));
    await tester.pump();
    expect(_width(tester, 'ide-sidebar'), IdeColumns.defaultSidebar);
    expect(_part('ide-editor'), findsNothing);
    await drag.up();
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('so does the chat opened beside the side bar', (tester) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.txt': 'a'},
      open: ['a.txt'],
      size: const Size(740, 800),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Codicons.layoutSidebarRight));
    await tester.pump();
    expect(_part('ide-sidebar'), findsOneWidget);
    expect(_part('ide-editor'), findsOneWidget);

    await tester.tap(find.byIcon(Codicons.layoutSidebarRightOff));
    await tester.pump();
    expect(_part('ide-sidebar'), findsOneWidget);
    expect(find.byKey(chatKey), findsOneWidget);
    expect(_part('ide-editor'), findsNothing);
    expect(workspace.layout.editorHidden, isTrue);
  });

  testWidgets('with too little room even for the two, one opened closes the '
      'other', (tester) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.txt': 'a'},
      open: ['a.txt'],
      size: const Size(560, 800),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Codicons.files));
    await tester.pump();
    expect(_part('ide-sidebar'), findsOneWidget);
    expect(_part('ide-editor'), findsOneWidget);
    expect(find.byKey(chatKey), findsNothing);
    expect(workspace.layout.chat, isFalse);

    await tester.tap(find.byIcon(Codicons.layoutSidebarRightOff));
    await tester.pump();
    expect(find.byKey(chatKey), findsOneWidget);
    expect(_part('ide-sidebar'), findsNothing);
    expect(workspace.layout.sidebar, isFalse);
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
    // Of 1356 (the window less the activity bar), the side bar snaps shut
    // at a chat of 894⅓, and the editor at 1089⅓.
    await drag.moveBy(const Offset(-20, 0));
    await drag.moveBy(const Offset(-649, 0));
    await tester.pump();
    expect(_part('ide-sidebar'), findsNothing);
    expect(_width(tester, 'ide-editor'), IdeColumns.minEditor);
    await drag.moveBy(const Offset(-1, 0));
    await tester.pump();
    expect(workspace.layout.chatMaximized, isTrue);
    expect(_part('ide-editor'), findsNothing);
    // Its sash over the activity bar's edge.
    const left = IdeModernUI.activityBarWidth;
    expect(tester.getCenter(_part('ide-chat-sash')).dx, left);
    final maximized = tester.getRect(_part('ide-chat'));
    expect(maximized.left, left);
    expect(maximized.right, 1400);
    // The panel below it, as high as it was.
    final panel = tester.getRect(_part('ide-panel'));
    expect(panel.left, maximized.left);
    expect(panel.right, maximized.right);
    expect(panel.top, maximized.bottom);
    expect(panel.height, closeTo(panelHeight, 0.01));
    // The same chat, moved.
    expect(tester.element(find.byKey(chatKey)), same(chat));
    expect(find.byIcon(Codicons.layoutSidebarLeftOff), findsOneWidget);

    // Back, the editor comes out at its minimum.
    await drag.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(workspace.layout.chatMaximized, isFalse);
    expect(_width(tester, 'ide-editor'), IdeColumns.minEditor);
    expect(_width(tester, 'ide-chat'), 1036);
    expect(tester.getRect(_part('ide-panel')).left, left);
    expect(tester.element(find.byKey(chatKey)), same(chat));
    await drag.up();
    await tester.pump();
    // The double click's wait.
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('showing the side bar puts it beside the maximized chat; '
      'hiding the chat or opening an editor ends the maximizing', (
    tester,
  ) async {
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
    expect(_part('ide-editor'), findsNothing);
    // Hidden again, the chat is maximized again.
    await tester.tap(find.byIcon(Codicons.files));
    await tester.pump();
    expect(workspace.layout.chatMaximized, isTrue);
    expect(_part('ide-editor'), findsNothing);

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
