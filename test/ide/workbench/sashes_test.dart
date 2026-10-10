import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_columns.dart';
import 'package:baocode/ide/ide_modern_ui.dart';
import 'package:baocode/ide/ide_rows.dart';
import 'package:baocode/theme/codicons.dart';

import 'fake_files.dart';

Finder _part(String key) => find.byKey(ValueKey(key));

double _width(WidgetTester tester, String key) =>
    tester.getSize(_part(key)).width;

MouseCursor? get _cursor =>
    RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);

void main() {
  testWidgets('a sash dragged past the editor\'s minimum pushes the view '
      'beyond, then snaps it shut, and it comes back with the pointer', (
    tester,
  ) async {
    await pumpWorkbench(tester, {'a.txt': 'a'});
    expect(_width(tester, 'ide-sidebar'), IdeColumns.defaultSidebar);
    expect(_width(tester, 'ide-chat'), IdeColumns.defaultChat);

    final drag = await tester.startGesture(
      tester.getCenter(_part('ide-sidebar-sash')),
    );
    // As far as the side bar goes: 676 of 1356 (the window less the
    // activity bar).
    await drag.moveBy(const Offset(20, 0));
    await drag.moveBy(const Offset(416, 0));
    await tester.pump();
    expect(_width(tester, 'ide-sidebar'), 676);
    expect(_width(tester, 'ide-editor'), IdeColumns.minEditor);
    expect(_width(tester, 'ide-chat'), IdeColumns.minChat);

    // A sixth of the chat's minimum further, the chat snaps shut.
    await drag.moveBy(const Offset(59, 0));
    await tester.pump();
    expect(_width(tester, 'ide-chat'), IdeColumns.minChat);
    await drag.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(_width(tester, 'ide-chat'), 0);
    expect(find.byKey(chatKey), findsNothing);
    expect(_width(tester, 'ide-sidebar'), 736);

    await drag.moveBy(const Offset(-496, 0));
    await tester.pump();
    expect(_width(tester, 'ide-sidebar'), IdeColumns.defaultSidebar);
    expect(_width(tester, 'ide-chat'), IdeColumns.defaultChat);
    await drag.up();
    await tester.pump();

    // The chat's the other way.
    await tester.drag(_part('ide-chat-sash'), const Offset(-400, 0));
    await tester.pump();
    expect(_width(tester, 'ide-editor'), IdeColumns.minEditor);
    expect(_width(tester, 'ide-sidebar'), 216);
    await tester.drag(_part('ide-chat-sash'), const Offset(-200, 0));
    await tester.pump();
    expect(_part('ide-sidebar'), findsNothing);
    expect(_width(tester, 'ide-chat'), 1020);
    // Opened again, as wide as it was; the chat gives way to it.
    await tester.tap(find.byIcon(Codicons.files));
    await tester.pump();
    expect(_width(tester, 'ide-sidebar'), 216);
    expect(_width(tester, 'ide-editor'), IdeColumns.minEditor);
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('dragged a sixth below its minimum a part snaps shut, opens '
      'again as wide as it was, and a double click resets it', (tester) async {
    await pumpWorkbench(tester, {'a.txt': 'a'});
    await tester.drag(_part('ide-sidebar-sash'), const Offset(60, 0));
    await tester.pump();
    expect(_width(tester, 'ide-sidebar'), 300);

    await tester.drag(_part('ide-sidebar-sash'), const Offset(-250, 0));
    await tester.pump();
    expect(_part('ide-sidebar'), findsNothing);
    await tester.tap(find.byIcon(Codicons.files));
    await tester.pump();
    expect(_width(tester, 'ide-sidebar'), 300);

    await tester.tap(_part('ide-sidebar-sash'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(_part('ide-sidebar-sash'));
    await tester.pumpAndSettle();
    expect(_width(tester, 'ide-sidebar'), IdeColumns.defaultSidebar);

    // Snapped shut, the chat comes back while the drag goes on.
    final drag = await tester.startGesture(
      tester.getCenter(_part('ide-chat-sash')),
    );
    await drag.moveBy(const Offset(20, 0));
    await drag.moveBy(const Offset(280, 0));
    await tester.pump();
    expect(_width(tester, 'ide-chat'), 0);
    expect(_part('ide-chat-sash'), findsOneWidget);
    await drag.moveBy(const Offset(-300, 0));
    await tester.pump();
    expect(_width(tester, 'ide-chat'), IdeColumns.defaultChat);
    await drag.up();
    await tester.pump(kDoubleTapTimeout);

    await tester.drag(_part('ide-chat-sash'), const Offset(300, 0));
    await tester.pump();
    expect(_width(tester, 'ide-chat'), 0);
    expect(find.byKey(chatKey), findsNothing);
    // Once the drag ends, no sash: the window's side is left to its own
    // resizing edge, the editor against it.
    expect(_part('ide-chat-sash'), findsNothing);
    expect(
      tester.getRect(_part('ide-editor')).right,
      tester.view.physicalSize.width,
    );
    await tester.tap(find.byIcon(Codicons.layoutSidebarRightOff));
    await tester.pump();
    expect(_width(tester, 'ide-chat'), IdeColumns.defaultChat);
    // The double click's wait.
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('the cursor says which ways a sash can go, and stays while it '
      'is dragged past where it stops', (tester) async {
    await pumpWorkbench(tester, {'a.txt': 'a'}, open: ['a.txt']);
    final sash = tester.getCenter(_part('ide-sidebar-sash'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: sash);
    await tester.pump();
    expect(_cursor, SystemMouseCursors.resizeColumn);

    await mouse.down(sash);
    // Past as far as the side bar goes, short of snapping the chat shut.
    await mouse.moveBy(const Offset(440, 0));
    await tester.pump();
    await tester.pump();
    expect(_width(tester, 'ide-editor'), IdeColumns.minEditor);
    expect(
      tester.getRect(_part('ide-editor')).contains(sash + const Offset(440, 0)),
      isTrue,
    );
    expect(_cursor, SystemMouseCursors.resizeLeft);

    await mouse.up();
    await tester.pump();
    await tester.pump();
    expect(_cursor, isNot(SystemMouseCursors.resizeLeft));
    await mouse.moveTo(tester.getCenter(_part('ide-sidebar-sash')));
    await tester.pump();
    expect(_cursor, SystemMouseCursors.resizeLeft);
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('the panel opens under the editor only, at a third of its '
      'column; its sash snaps it shut and a double click resets it', (
    tester,
  ) async {
    await pumpWorkbench(tester, {'a.txt': 'a'});
    expect(tester.getSize(_part('ide-panel')).height, 0);
    final column = tester.getRect(_part('ide-editor-column'));
    // Hidden, its sash is over the editor's bottom edge.
    expect(tester.getRect(_part('ide-panel-sash')).bottom, column.bottom);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.backquote);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final editor = tester.getRect(_part('ide-editor'));
    final panel = tester.getRect(_part('ide-panel'));
    // Flush with the editor, the status bar under it.
    final room = column.height;
    expect(panel.height, closeTo(room / 3, 0.01));
    expect(panel.top, editor.bottom);
    expect(panel.left, editor.left);
    expect(panel.right, editor.right);
    expect(panel.bottom, column.bottom);
    // Its sash over the line between the two.
    expect(
      tester.getCenter(_part('ide-panel-sash')).dy,
      closeTo(panel.top, 0.01),
    );
    expect(tester.getSize(_part('ide-panel-sash')).height, IdeModernUI.gap);
    // The side bar and the chat keep the whole height.
    expect(tester.getRect(_part('ide-chat')).bottom, panel.bottom);
    expect(tester.getRect(_part('ide-sidebar')).bottom, panel.bottom);

    final drag = await tester.startGesture(
      tester.getCenter(_part('ide-panel-sash')),
    );
    await drag.moveBy(const Offset(0, -20));
    await drag.moveBy(const Offset(0, -80));
    await tester.pump();
    expect(
      tester.getSize(_part('ide-panel')).height,
      closeTo(room / 3 + 100, 0.01),
    );
    // Below half its minimum, it snaps shut; back, it opens again.
    await drag.moveBy(Offset(0, 100 + room / 3 - 38));
    await tester.pump();
    expect(tester.getSize(_part('ide-panel')).height, 0);
    await drag.moveBy(const Offset(0, -2));
    await tester.pump();
    expect(tester.getSize(_part('ide-panel')).height, IdeRows.minPanel);
    await drag.up();
    await tester.pump();

    await tester.tap(_part('ide-panel-sash'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(_part('ide-panel-sash'));
    await tester.pumpAndSettle();
    expect(tester.getSize(_part('ide-panel')).height, closeTo(room / 3, 0.01));

    // The title bar's layout control hides it, and shows it again.
    await tester.tap(find.byIcon(Codicons.layoutPanel));
    await tester.pump();
    expect(tester.getSize(_part('ide-panel')).height, 0);
    await tester.tap(find.byIcon(Codicons.layoutPanelOff));
    await tester.pump();
    expect(tester.getSize(_part('ide-panel')).height, closeTo(room / 3, 0.01));
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('however narrow the window, the chat stays on the right', (
    tester,
  ) async {
    // Where the chat used to go below.
    await pumpWorkbench(
      tester,
      {'a.txt': 'a'},
      open: ['a.txt'],
      size: const Size(740, 800),
    );
    final editor = tester.getRect(_part('ide-editor'));
    final chat = tester.getRect(_part('ide-chat'));
    expect(chat.top, editor.top);
    expect(chat.bottom, editor.bottom);
    expect(chat.left, editor.right);
    expect(chat.width, IdeColumns.minChat);
    // The side bar gave way to the editor opened.
    expect(_part('ide-sidebar'), findsNothing);
  });
}
