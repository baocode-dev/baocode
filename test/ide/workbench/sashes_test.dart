import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/ide_columns.dart';
import 'package:monad/ide/ide_modern_ui.dart';
import 'package:monad/theme/codicons.dart';

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
    // As far as the side bar goes: 660 of 1340.
    await drag.moveBy(const Offset(20, 0));
    await drag.moveBy(const Offset(400, 0));
    await tester.pump();
    expect(_width(tester, 'ide-sidebar'), 660);
    expect(_width(tester, 'ide-editor'), IdeColumns.minEditor);
    expect(_width(tester, 'ide-chat'), IdeColumns.minChat);

    // Half the chat's minimum further, the chat snaps shut.
    await drag.moveBy(const Offset(179, 0));
    await tester.pump();
    expect(_width(tester, 'ide-chat'), IdeColumns.minChat);
    await drag.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(_width(tester, 'ide-chat'), 0);
    expect(find.byKey(chatKey), findsNothing);
    expect(_width(tester, 'ide-sidebar'), 840);

    await drag.moveBy(const Offset(-600, 0));
    await tester.pump();
    expect(_width(tester, 'ide-sidebar'), IdeColumns.defaultSidebar);
    expect(_width(tester, 'ide-chat'), IdeColumns.defaultChat);
    await drag.up();
    await tester.pump();

    // The chat's the other way.
    await tester.drag(_part('ide-chat-sash'), const Offset(-400, 0));
    await tester.pump();
    expect(_width(tester, 'ide-editor'), IdeColumns.minEditor);
    expect(_width(tester, 'ide-sidebar'), 200);
    await tester.drag(_part('ide-chat-sash'), const Offset(-200, 0));
    await tester.pump();
    expect(_part('ide-sidebar'), findsNothing);
    expect(_width(tester, 'ide-chat'), 1020);
    // Opened again, as wide as it was; the chat gives way to it.
    await tester.tap(find.byIcon(Codicons.files));
    await tester.pump();
    expect(_width(tester, 'ide-sidebar'), 200);
    expect(_width(tester, 'ide-editor'), IdeColumns.minEditor);
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('dragged below half its minimum a part snaps shut, opens '
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

    await tester.drag(_part('ide-chat-sash'), const Offset(300, 0));
    await tester.pump();
    expect(_width(tester, 'ide-chat'), 0);
    expect(find.byKey(chatKey), findsNothing);
    // Its sash stays, as the gap by the window's side, to drag it out.
    expect(
      tester.getRect(_part('ide-chat-sash')).right,
      tester.view.physicalSize.width,
    );
    await tester.drag(_part('ide-chat-sash'), const Offset(-400, 0));
    await tester.pump();
    expect(_width(tester, 'ide-chat'), 400);
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
    await mouse.moveBy(const Offset(500, 0));
    await tester.pump();
    await tester.pump();
    expect(_width(tester, 'ide-editor'), IdeColumns.minEditor);
    expect(
      tester.getRect(_part('ide-editor')).contains(sash + const Offset(500, 0)),
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

  testWidgets('however narrow the window, the chat stays on the right', (
    tester,
  ) async {
    // Where the chat used to go below.
    await pumpWorkbench(tester, {'a.txt': 'a'}, size: const Size(740, 800));
    final editor = tester.getRect(_part('ide-editor'));
    final chat = tester.getRect(_part('ide-chat'));
    expect(chat.top, editor.top);
    expect(chat.bottom, editor.bottom);
    expect(chat.left, editor.right + IdeModernUI.gap);
    expect(chat.width, IdeColumns.minChat);
    // The side bar gave way first.
    expect(_part('ide-sidebar'), findsNothing);
  });
}
