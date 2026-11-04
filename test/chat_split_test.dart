import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/chat/widgets/hover_scroll_text.dart';
import 'package:baocode/chat/widgets/inline_rename_field.dart';
import 'package:baocode/ide/ide_modern_ui.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/main.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/workspace/islands.dart';
import 'package:baocode/workspace/back_to_chat_button.dart';
import 'package:baocode/workspace/chat_drag.dart';
import 'package:baocode/workspace/chat_grid.dart';
import 'package:baocode/workspace/chat_grid_view.dart';
import 'package:baocode/workspace/editor_launcher.dart';
import 'package:baocode/chat/side_panel/side_panel_view.dart';
import 'package:baocode/workspace/open_in_editor_button.dart';
import 'package:baocode/workspace/pane_tabs.dart';
import 'package:baocode/workspace/title_bar_double_click.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:baocode/workspace/chat_terminal.dart';
import 'package:baocode/workspace/pin_window_button.dart';
import 'package:baocode/workspace/window_header/window_header.dart';
import 'package:baocode/l10n/app_localizations_en.dart';

const first = 'Optimize virtual list scrolling';
const second = 'Rate limit per API key';
const third = 'Rewrite the agents quickstart';
const fourth = 'Flaky integration test on CI';
const fifth = 'Broken anchors in API reference';

Future<Workspace> pumpApp(WidgetTester tester, {double width = 1400}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final workspace = Workspace.mock();
  await tester.pumpWidget(BaoCodeApp(workspace: workspace));
  await tester.pump();
  return workspace;
}

Finder inSidebar(Finder finder) =>
    find.descendant(of: find.byType(Sidebar), matching: finder);

Rect gridRect(WidgetTester tester) => tester.getRect(find.byType(ChatGridView));

/// The pane of the agent titled [title].
Finder pane(String title) => find.byWidgetPredicate(
  (widget) => widget is ChatScreen && widget.title == title,
);

List<String> paneTitles(WidgetTester tester) => [
  for (final screen in tester.widgetList<ChatScreen>(find.byType(ChatScreen)))
    screen.title,
];

/// The line between the columns (or, [column] false, the rows).
Finder line({bool column = true}) => find.descendant(
  of: find.byKey(ValueKey(column ? 'column sash' : 'row sash')),
  matching: find.byType(DecoratedBox),
);

Color? lineColor(WidgetTester tester) =>
    (tester.widget<DecoratedBox>(line()).decoration as BoxDecoration).color;

/// Where the agent dragged would go, shown over the grid.
Finder preview() => find.descendant(
  of: find.byType(ChatGridView),
  matching: find.byType(AnimatedPositioned),
);

/// Presses the agent titled [title] in the sidebar and drags it to [to],
/// the mouse still down.
Future<TestGesture> dragAgent(
  WidgetTester tester,
  String title,
  Offset to,
) async {
  final gesture = await tester.startGesture(
    tester.getCenter(inSidebar(find.textContaining(title))),
    kind: PointerDeviceKind.mouse,
    pointer: 7,
  );
  await gesture.moveBy(const Offset(12, 0));
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  return gesture;
}

Future<void> dropAgent(WidgetTester tester, String title, Offset to) async {
  final gesture = await dragAgent(tester, title, to);
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Drags a pane by its title, leaving the mouse down over [to].
Future<TestGesture> dragTitle(
  WidgetTester tester,
  String title,
  Offset to, {
  bool empty = false,
}) async {
  final titleText = find.descendant(
    of: pane(title),
    matching: find.text(title),
  );
  final text = tester.getRect(titleText);
  final gesture = await tester.startGesture(
    empty ? Offset(text.right + 12, text.center.dy) : text.center,
    kind: PointerDeviceKind.mouse,
    pointer: 9,
  );
  await gesture.moveBy(const Offset(12, 0));
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  return gesture;
}

/// Near the middle of [rect]'s [side].
Offset near(Rect rect, PaneSide side) => switch (side) {
  PaneSide.left => Offset(rect.left + 30, rect.center.dy),
  PaneSide.right => Offset(rect.right - 30, rect.center.dy),
  PaneSide.top => Offset(rect.center.dx, rect.top + 60),
  PaneSide.bottom => Offset(rect.center.dx, rect.bottom - 60),
};

void main() {
  testWidgets("the mouse's back and forward buttons go through the agents "
      'selected, as a browser through its pages (#516)', (tester) async {
    final workspace = await pumpApp(tester);
    final start = workspace.current!;
    final others = workspace.threads
        .where((thread) => thread != start && !thread.archived)
        .take(2)
        .toList();
    Future<void> side(int buttons) async {
      await tester.tapAt(
        gridRect(tester).center,
        buttons: buttons,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
    }

    workspace.select(others[0]);
    await tester.pumpAndSettle();
    workspace.select(others[1]);
    await tester.pumpAndSettle();

    await side(kBackMouseButton);
    expect(workspace.current, others[0]);
    await side(kBackMouseButton);
    expect(workspace.current, start);
    // Nothing further back.
    await side(kBackMouseButton);
    expect(workspace.current, start);

    await side(kForwardMouseButton);
    expect(workspace.current, others[0]);
    // Another picked: nothing ahead any more.
    workspace.select(start);
    await tester.pumpAndSettle();
    await side(kForwardMouseButton);
    expect(workspace.current, start);
    await side(kBackMouseButton);
    expect(workspace.current, others[0]);
  });

  testWidgets('an agent dragged to the right of the chat opens beside it', (
    tester,
  ) async {
    final workspace = await pumpApp(tester);
    expect(line(), findsNothing);
    expect(line(column: false), findsNothing);
    final grid = gridRect(tester);
    final gesture = await dragAgent(tester, second, near(grid, PaneSide.right));
    // The right half, where it would go.
    expect(preview(), findsOneWidget);
    await tester.pumpAndSettle();
    final shown = tester.getRect(preview());
    expect(shown.left, closeTo(grid.center.dx + ChatGridView.gap / 2 + 4, 1));
    expect(shown.right, closeTo(grid.right - 4, 1));
    // Not yet.
    expect(paneTitles(tester), [first]);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(preview(), findsNothing);
    expect(paneTitles(tester), unorderedEquals([first, second]));
    // Under the window's one row over them all, as the one conversation's
    // card was; no row under their cards, a gap from the window's foot.
    final panes = gridRect(tester);
    expect(panes.top, grid.top + AppMetrics.titleBarHeight);
    expect(panes.bottom, grid.bottom - Islands.gap);
    final left = tester.getRect(pane(first));
    final right = tester.getRect(pane(second));
    // Where it was, the first gives the second half its room; a line
    // between them, down the whole height.
    expect(left.topLeft, panes.topLeft);
    expect(right.right, panes.right);
    expect(right.left - left.right, ChatGridView.gap);
    expect(left.height, panes.height);
    // In the gap between their cards: nothing there at rest.
    expect(lineColor(tester), Colors.transparent);
    final drawn = tester.getRect(line());
    expect(drawn.width, 0);
    expect(drawn.height, panes.height);
    expect(drawn.center.dx, closeTo((left.right + right.left) / 2, .5));
    // The one dropped is focused; the other is still in view.
    expect(workspace.current!.title, second);
    expect(workspace.grid.length, 2);
  });

  testWidgets('and above or below it', (tester) async {
    await pumpApp(tester);
    await dropAgent(tester, second, near(gridRect(tester), PaneSide.top));
    final top = tester.getRect(pane(second));
    final bottom = tester.getRect(pane(first));
    expect(top.bottom + ChatGridView.gap, bottom.top);
    expect(top.width, gridRect(tester).width);
    expect(tester.getRect(line(column: false)).width, gridRect(tester).width);
    // Under the window's row, a double click on a card's title bar is not
    // the window's, at the top or not.
    expect(tester.widget<ChatScreen>(pane(second)).windowTitleBar, isFalse);
    expect(tester.widget<ChatScreen>(pane(first)).windowTitleBar, isFalse);
  });

  testWidgets('released elsewhere, or after a right click or Esc, nothing '
      'changes', (tester) async {
    await pumpApp(tester);
    final right = near(gridRect(tester), PaneSide.right);

    // Back over the sidebar.
    var gesture = await dragAgent(tester, second, right);
    expect(preview(), findsOneWidget);
    await gesture.moveTo(tester.getCenter(find.byType(Sidebar)));
    await tester.pump();
    expect(preview(), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(paneTitles(tester), [first]);

    // A right click on the way.
    gesture = await dragAgent(tester, second, right);
    await gesture.updateWithCustomEvent(
      PointerMoveEvent(
        pointer: 7,
        device: 1,
        kind: PointerDeviceKind.mouse,
        position: right,
        buttons: kPrimaryButton | kSecondaryButton,
      ),
    );
    await tester.pump();
    expect(preview(), findsNothing);
    await gesture.moveTo(right + const Offset(-10, 0));
    await tester.pump();
    expect(preview(), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(paneTitles(tester), [first]);

    // Esc.
    gesture = await dragAgent(tester, second, right);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(preview(), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(paneTitles(tester), [first]);

    // A click that slips a little still opens the agent.
    gesture = await tester.startGesture(
      tester.getCenter(inSidebar(find.textContaining(second))),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(3, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(paneTitles(tester), [second]);
  });

  testWidgets('a project\'s New Agent dragged beside the chat opens a new '
      'agent there; released elsewhere, none is left', (tester) async {
    final workspace = await pumpApp(tester);
    final project = workspace.current!.project;
    final count = workspace.threads.length;
    // The project's header shows its button with the pointer over it.
    final header = inSidebar(find.text(project.name));
    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(location: tester.getCenter(header.first));
    await tester.pump();
    final add = find.descendant(
      of: find.byType(ChatNewDragSource),
      matching: find.byIcon(Icons.add_rounded),
    );
    expect(add, findsOneWidget);

    Future<TestGesture> dragNew(Offset to) async {
      // Its button shows again with the pointer back over the header.
      await hover.moveTo(tester.getCenter(header.first));
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(add),
        kind: PointerDeviceKind.mouse,
        pointer: 8,
      );
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump();
      await gesture.moveTo(to);
      await tester.pump();
      return gesture;
    }

    // Released over the sidebar: nothing, and no agent left behind.
    var gesture = await dragNew(near(gridRect(tester), PaneSide.right));
    expect(preview(), findsOneWidget);
    await gesture.moveTo(tester.getCenter(find.byType(Sidebar)));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(paneTitles(tester), [first]);
    expect(workspace.threads.length, count);

    // Beside the chat: a new agent of the project there, the chat still in
    // view, the new one focused.
    gesture = await dragNew(near(gridRect(tester), PaneSide.right));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(workspace.grid.length, 2);
    expect(paneTitles(tester), contains(first));
    final added = workspace.current!;
    expect(added.title, isNot(first));
    expect(added.project, same(project));
    expect(added.untouched, isTrue);
    expect(workspace.threads.length, count + 1);
  });

  testWidgets('a third beside either, a fourth beside the one with a whole '
      'column; four full, one only takes a pane\'s place', (tester) async {
    final workspace = await pumpApp(tester);
    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));

    // Side by side, each splits top or bottom only: near the left of the
    // right pane, the drop is its place.
    var gesture = await dragAgent(
      tester,
      third,
      near(tester.getRect(pane(second)), PaneSide.left),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(preview()), tester.getRect(pane(second)).deflate(4));
    await gesture.moveTo(near(tester.getRect(pane(second)), PaneSide.bottom));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(paneTitles(tester), unorderedEquals([first, second, third]));
    var left = tester.getRect(pane(first));
    var top = tester.getRect(pane(second));
    var bottom = tester.getRect(pane(third));
    expect(left.height, gridRect(tester).height);
    expect(top.left, bottom.left);
    expect(top.bottom + ChatGridView.gap, bottom.top);

    await dropAgent(tester, fourth, near(left, PaneSide.top));
    expect(workspace.grid.length, 4);
    // A strict 2×2: the lines across both halves.
    left = tester.getRect(pane(first));
    top = tester.getRect(pane(second));
    bottom = tester.getRect(pane(third));
    final corner = tester.getRect(pane(fourth));
    expect(corner.bottom, top.bottom);
    expect(left.top, bottom.top);
    expect(corner.right, left.right);

    // Full: near an edge is the pane's place too.
    await dropAgent(tester, fifth, near(bottom, PaneSide.right));
    expect(paneTitles(tester), unorderedEquals([first, second, fifth, fourth]));
    expect(tester.getRect(pane(fifth)), bottom);
    expect(workspace.current!.title, fifth);
  });

  testWidgets('a click in a pane focuses it; the sidebar replaces the '
      'focused one; an agent shown already is focused where it is', (
    tester,
  ) async {
    final workspace = await pumpApp(tester);
    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    expect(workspace.current!.title, second);
    expect(tester.widget<ChatScreen>(pane(first)).focused, isFalse);
    // The focused one outlined in the drop preview's line.
    final frame = find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).border ==
              Border.all(color: ChatGridView.frameColor),
    );
    // One frame, its card's outline: the whole pane, no row over it nor
    // under it.
    bool framed(String title) {
      final shown = tester.getRect(frame);
      final rect = tester.getRect(pane(title));
      bool near(double a, double b) => (a - b).abs() < .5;
      return near(shown.left, rect.left) &&
          near(shown.right, rect.right) &&
          near(shown.top, rect.top) &&
          near(shown.bottom, rect.bottom);
    }

    expect(framed(second), isTrue);
    expect(framed(first), isFalse);

    // Clicked in the sidebar, one shown already is focused where it is.
    final left = tester.getRect(pane(first));
    await tester.tap(inSidebar(find.textContaining(first)));
    await tester.pumpAndSettle();
    expect(paneTitles(tester), unorderedEquals([first, second]));
    expect(tester.getRect(pane(first)), left);
    expect(workspace.current!.title, first);
    expect(tester.widget<ChatScreen>(pane(first)).focused, isTrue);
    expect(tester.widget<ChatScreen>(pane(second)).focused, isFalse);
    expect(framed(first), isTrue);
    expect(framed(second), isFalse);

    await tester.tapAt(tester.getRect(pane(second)).center);
    await tester.pump();
    expect(workspace.current!.title, second);

    // Another takes the focused one's place.
    final right = tester.getRect(pane(second));
    await tester.tap(inSidebar(find.textContaining(third)));
    await tester.pumpAndSettle();
    expect(paneTitles(tester), unorderedEquals([first, third]));
    expect(tester.getRect(pane(third)), right);

    // Dragged, one shown already: its own pane is where it goes, focused.
    final gesture = await dragAgent(tester, first, right.center);
    await tester.pumpAndSettle();
    expect(tester.getRect(preview()), left.deflate(4));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(paneTitles(tester), unorderedEquals([first, third]));
    expect(workspace.current!.title, first);
  });

  testWidgets('a closed pane gives its place to the one beside it; '
      'archived, an agent\'s pane closes', (tester) async {
    final workspace = await pumpApp(tester);
    expect(find.bySemanticsLabel('Close pane'), findsNothing);
    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    await dropAgent(
      tester,
      third,
      near(tester.getRect(pane(second)), PaneSide.bottom),
    );
    expect(find.bySemanticsLabel('Close pane'), findsNWidgets(3));

    await tester.tap(
      find.descendant(
        of: pane(third),
        matching: find.bySemanticsLabel('Close pane'),
      ),
    );
    await tester.pumpAndSettle();
    expect(paneTitles(tester), unorderedEquals([first, second]));
    expect(tester.getRect(pane(second)).height, gridRect(tester).height);
    expect(workspace.current!.title, second);
    // Still in the sidebar, running as it was.
    expect(inSidebar(find.textContaining(third)), findsOneWidget);

    workspace.setArchived(workspace.current!, true);
    await tester.pumpAndSettle();
    expect(paneTitles(tester), [first]);
    expect(tester.getRect(pane(first)), gridRect(tester));
    expect(workspace.current!.title, first);
    expect(find.bySemanticsLabel('Close pane'), findsNothing);
  });

  testWidgets('on macOS a top pane\'s title bar drags the pane, not the '
      'window; alone, the window', (tester) async {
    const channel = MethodChannel('baocode/window');
    var windowDrags = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'dragWindow') windowDrags++;
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    final workspace = await pumpApp(tester);
    final away = Offset(gridRect(tester).center.dx, gridRect(tester).top + 80);

    // Alone, by its title (a long one leaves little else) or beside it.
    var gesture = await dragTitle(tester, first, away);
    await gesture.up();
    await tester.pumpAndSettle();
    gesture = await dragTitle(tester, first, away, empty: true);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(windowDrags, 2);

    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    gesture = await dragTitle(
      tester,
      first,
      tester.getRect(pane(second)).center,
      empty: true,
    );
    expect(preview(), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(windowDrags, 2);
    expect(workspace.grid.cells.first.title, second);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a title dragged to another pane\'s center swaps their places '
      'without rebuilding their conversations', (tester) async {
    final workspace = await pumpApp(tester);
    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    final left = tester.getRect(pane(first));
    final right = tester.getRect(pane(second));
    final firstState = tester.state(pane(first));
    final secondState = tester.state(pane(second));
    final firstSession = tester.widget<ChatScreen>(pane(first)).session;
    final sidebarOrder = workspace.threads.toList();

    final gesture = await dragTitle(tester, first, right.center);
    expect(preview(), findsOneWidget);
    expect(tester.getRect(preview()), right.deflate(4));
    // Only the preview moves before release.
    expect(tester.getRect(pane(first)), left);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.getRect(pane(first)), right);
    expect(tester.getRect(pane(second)), left);
    expect(tester.state(pane(first)), same(firstState));
    expect(tester.state(pane(second)), same(secondState));
    expect(tester.widget<ChatScreen>(pane(first)).session, same(firstSession));
    expect(workspace.current!.title, first);
    expect(workspace.threads, sidebarOrder);
    expect(preview(), findsNothing);
  });

  testWidgets(
    'the empty title bar drags a pane to an edge, changing two '
    'columns to two rows',
    (tester) async {
      final workspace = await pumpApp(tester);
      await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
      final before = workspace.grid.panes.toSet();
      final gesture = await dragTitle(
        tester,
        first,
        near(tester.getRect(pane(second)), PaneSide.bottom),
        empty: true,
      );
      expect(preview(), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(workspace.grid.panes.toSet(), before);
      expect(workspace.grid.columnsSplit, isFalse);
      expect(workspace.grid.rowsSplit, isTrue);
      final bottom = tester.getRect(pane(first));
      final top = tester.getRect(pane(second));
      expect(bottom.width, gridRect(tester).width);
      expect(top.width, gridRect(tester).width);
      expect(bottom.top, top.bottom + ChatGridView.gap);
    },
    variant: TargetPlatformVariant(const {
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets('a lower pane\'s title can move it without losing another pane', (
    tester,
  ) async {
    final workspace = await pumpApp(tester);
    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    await dropAgent(
      tester,
      third,
      near(tester.getRect(pane(first)), PaneSide.bottom),
    );
    final before = workspace.grid.panes.toSet();
    final gesture = await dragTitle(
      tester,
      third,
      near(tester.getRect(pane(second)), PaneSide.bottom),
      empty: true,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(workspace.grid.panes.toSet(), before);
    expect(tester.getRect(pane(first)).height, gridRect(tester).height);
    expect(
      tester.getRect(pane(third)).top,
      tester.getRect(pane(second)).bottom + ChatGridView.gap,
    );
  });

  testWidgets('a title drag cancelled, dropped outside or on its own pane '
      'does not rearrange the grid', (tester) async {
    final workspace = await pumpApp(tester);
    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    final original = workspace.grid.cells;
    final right = tester.getRect(pane(second));

    var gesture = await dragTitle(tester, first, right.center);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(workspace.grid.cells, original);
    expect(preview(), findsNothing);

    gesture = await dragTitle(tester, first, const Offset(20, 80));
    expect(preview(), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(workspace.grid.cells, original);

    gesture = await dragTitle(
      tester,
      first,
      tester.getRect(pane(first)).center,
    );
    expect(preview(), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(workspace.grid.cells, original);
  });

  testWidgets('side by side, each pane names its project; alone, none '
      'does', (tester) async {
    await pumpApp(tester);
    Finder project(String title, String name) => find.descendant(
      of: pane(title),
      matching: find.byWidgetPredicate(
        (widget) => widget is HoverScrollText && widget.text == name,
      ),
    );
    expect(project(first, 'baocode'), findsNothing);
    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    expect(project(first, 'baocode'), findsOneWidget);
    expect(project(second, 'api-gateway'), findsOneWidget);
  });

  test('a project on another computer is labelled with its name', () {
    final workspace = Workspace();
    expect(workspace.projectLabel(const Project('api', '/code/api')), 'api');
    final remote = Project.at('ssh://devbox/home/me/api');
    expect(workspace.projectLabel(remote), 'api · devbox');
    workspace.renameHost('devbox', 'Build box');
    expect(workspace.projectLabel(remote), 'api · Build box');
  });

  testWidgets('title double clicks still rename, and toolbar buttons never '
      'start a pane drag', (tester) async {
    final workspace = await pumpApp(tester);
    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    final original = workspace.grid.cells;
    final title = find.descendant(of: pane(first), matching: find.text(first));
    await tester.tap(title, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(title, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.byType(InlineRenameField), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final editor = find.descendant(
      of: pane(second),
      matching: find.byType(SidePanelToggle),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(editor),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(tester.getRect(pane(first)).center);
    await tester.pump();
    expect(preview(), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(workspace.grid.cells, original);
  });

  testWidgets('a sidebar agent already shown still only focuses its pane', (
    tester,
  ) async {
    final workspace = await pumpApp(tester);
    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    final original = workspace.grid.cells;
    await dropAgent(tester, first, tester.getRect(pane(second)).center);
    expect(workspace.grid.cells, original);
    expect(workspace.current!.title, first);
  });

  testWidgets(
    'one Open in Editor for the panes, the focused one\'s project\'s; '
    'a click on another pane\'s close leaves the focus; Fast Ide opens '
    'the focused agent',
    (tester) async {
      final opened = <String>[];
      OpenInEditorButton.launch = (editor, path) async {
        opened.add(path);
        return true;
      };
      addTearDown(() => OpenInEditorButton.launch = openInEditor);
      final workspace = await pumpApp(tester);
      // An app to launch first; the Fast Ide (the default) below.
      workspace.preferredEditor = Editor.vscode;
      await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
      await dropAgent(
        tester,
        third,
        near(tester.getRect(pane(second)), PaneSide.bottom),
      );
      await tester.tapAt(tester.getRect(pane(first)).center);
      await tester.pump();
      final focused = workspace.current!;
      expect(focused.title, first);
      final right = workspace.threads.firstWhere(
        (thread) => thread.title == second,
      );
      expect(right.project, isNot(focused.project));
      Finder tool(String label) => find.bySemanticsLabel(label);
      // The window's, not one in each pane.
      expect(find.byType(OpenInEditorButton), findsOneWidget);
      for (final title in [first, second, third]) {
        expect(
          find.descendant(
            of: pane(title),
            matching: find.byType(OpenInEditorButton),
          ),
          findsNothing,
        );
      }

      // The focused agent's project.
      await tester.tap(tool('Open in VS Code'));
      await tester.pump();
      expect(opened, [focused.project.path]);
      expect(workspace.current, same(focused));

      // Another pane focused, its project's.
      await tester.tapAt(tester.getRect(pane(second)).center);
      await tester.pump();
      await tester.tap(tool('Open in VS Code'));
      await tester.pump();
      expect(opened, [focused.project.path, right.project.path]);
      await tester.tapAt(tester.getRect(pane(first)).center);
      await tester.pump();
      expect(workspace.current, same(focused));

      await tester.tap(
        find.descendant(
          of: pane(third),
          matching: find.bySemanticsLabel('Close pane'),
        ),
      );
      await tester.pumpAndSettle();
      expect(paneTitles(tester), unorderedEquals([first, second]));
      expect(workspace.current, same(focused));

      // The focused agent's chat in the IDE.
      workspace.preferredEditor = Editor.fastIde;
      await tester.pump();
      await tester.tap(tool('Open in Fast Ide'));
      await tester.pump();
      await tester.pump();
      expect(workspace.layout, WorkspaceLayout.ide);
      expect(workspace.current, same(focused));
      final ide = find.byType(IdeWorkbench);
      expect(
        tester.widget<IdeWorkbench>(ide).project.path,
        focused.project.path,
      );
      expect(opened, hasLength(2));
      workspace.layout = WorkspaceLayout.chat;
      await tester.pump();
    },
    variant: TargetPlatformVariant(const {
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'side by side, each pane has the side panel\'s rail of its own agent, '
    'under its title bar, clear of its close button; a page picked there '
    'focuses the pane and shows its agent\'s',
    (tester) async {
      // Room for the window's tools in the right pane beside the panel.
      final workspace = await pumpApp(tester, width: 1800);
      await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
      await tester.tapAt(tester.getRect(pane(second)).center);
      await tester.pumpAndSettle();
      expect(workspace.current!.title, second);

      final rails = tester.widgetList(find.byType(SidePanelRail)).toList();
      expect(rails, hasLength(2));
      Rect railOf(String title) {
        final paneRect = tester.getRect(pane(title));
        return [
          for (final rail in find.byType(SidePanelRail).evaluate())
            tester.getRect(find.byWidget(rail.widget)),
        ].singleWhere((rect) => paneRect.contains(rect.center));
      }

      for (final title in [first, second]) {
        final paneRect = tester.getRect(pane(title));
        final rail = railOf(title);
        expect(rail.right, paneRect.right - AgentSidePanelArea.railRight);
        // Under the row along its card's top, there being none over it.
        expect(
          rail.top - paneRect.top,
          ChatScreen.cardHeaderHeight + AgentSidePanelArea.railRight,
        );
        final close = tester.getRect(
          find.descendant(
            of: pane(title),
            matching: find.bySemanticsLabel('Close pane'),
          ),
        );
        expect(rail.overlaps(close), isFalse);
      }

      // The left pane's, not focused: it is, and the panel shows its agent.
      final left = find.byWidgetPredicate(
        (widget) =>
            widget is SidePanelRail &&
            tester
                .getRect(pane(first))
                .contains(tester.getCenter(find.byWidget(widget))),
      );
      await tester.tap(
        find
            .descendant(of: left, matching: find.byType(SidebarIconButton))
            .first,
      );
      await tester.pumpAndSettle();
      expect(workspace.current!.title, first);
      final view = tester.widget<AgentSidePanelView>(
        find.byType(AgentSidePanelView),
      );
      expect(view.session, same(workspace.current!.session));
      // Its own shown, its rail gives way to it; the other pane's, hidden
      // there, is still there.
      expect(find.byType(SidePanelRail), findsOneWidget);
      expect(railOf(second), isNotNull);
    },
    variant: TargetPlatformVariant(const {
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'a pane\'s side panel button is its own agent\'s: it focuses '
    'the pane and shows its panel',
    (tester) async {
      // Room for a panel beside each pane.
      final workspace = await pumpApp(tester, width: 1800);
      await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
      await tester.tapAt(tester.getRect(pane(first)).center);
      await tester.pumpAndSettle();
      expect(workspace.current!.title, first);
      bool shownIn(String title) => tester
          .widget<SidePanelToggle>(
            find.descendant(
              of: pane(title),
              matching: find.byType(SidePanelToggle),
            ),
          )
          .shown;
      expect(shownIn(first), isFalse);
      expect(shownIn(second), isFalse);

      // The right pane's, another pane's agent focused: it is focused, and
      // its panel shows.
      await tester.tap(
        find.descendant(
          of: pane(second),
          matching: find.byType(SidePanelToggle),
        ),
      );
      await tester.pumpAndSettle();
      expect(workspace.current!.title, second);
      expect(shownIn(second), isTrue);
      expect(shownIn(first), isFalse);

      // The left pane's again: its agent's panel too, the right one's still
      // shown beside its own pane, each its agent's.
      await tester.tap(
        find.descendant(
          of: pane(first),
          matching: find.byType(SidePanelToggle),
        ),
      );
      await tester.pumpAndSettle();
      expect(workspace.current!.title, first);
      expect(shownIn(first), isTrue);
      expect(shownIn(second), isTrue);
      final views = tester
          .widgetList<AgentSidePanelView>(find.byType(AgentSidePanelView))
          .toList();
      expect(views, hasLength(2));
      for (final title in [first, second]) {
        final view = tester.widget<AgentSidePanelView>(
          find.descendant(
            of: find.ancestor(
              of: pane(title),
              matching: find.byType(AgentSidePanelArea),
            ),
            matching: find.byType(AgentSidePanelView),
          ),
        );
        expect(
          view.session,
          same(tester.widget<ChatScreen>(pane(title)).session),
        );
      }

      // Hidden in the left one, the right one's stays.
      await tester.tap(
        find.descendant(
          of: pane(first),
          matching: find.byType(SidePanelToggle),
        ),
      );
      await tester.pumpAndSettle();
      expect(shownIn(first), isFalse);
      expect(shownIn(second), isTrue);
      expect(find.byType(AgentSidePanelView), findsOneWidget);
    },
    variant: TargetPlatformVariant(const {
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets('under Windows\' header, one conversation or several, the '
      'terminal and side panel buttons are on the cards, as on macOS; the pin '
      'and the editor\'s in the header', (tester) async {
    await pumpApp(tester);
    Finder inHeader(Type type) => find.descendant(
      of: find.byType(WindowHeader),
      matching: find.byType(type),
    );
    expect(inHeader(SidePanelToggle), findsNothing);
    expect(
      find.descendant(of: pane(first), matching: find.byType(SidePanelToggle)),
      findsOneWidget,
    );
    expect(inHeader(OpenInEditorButton), findsOneWidget);
    expect(inHeader(PinWindowButton), findsOneWidget);

    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    expect(inHeader(SidePanelToggle), findsNothing);
    expect(inHeader(ChatTerminalToggle), findsNothing);
    expect(inHeader(OpenInEditorButton), findsOneWidget);
    expect(inHeader(PinWindowButton), findsOneWidget);
    for (final title in [first, second]) {
      expect(
        find.descendant(
          of: pane(title),
          matching: find.byType(SidePanelToggle),
        ),
        findsOneWidget,
      );
      // The window's, in its header alone.
      for (final type in [PinWindowButton, OpenInEditorButton]) {
        expect(
          find.descendant(of: pane(title), matching: find.byType(type)),
          findsNothing,
        );
      }
    }

    await tester.tap(
      find.descendant(
        of: pane(second),
        matching: find.bySemanticsLabel('Close pane'),
      ),
    );
    await tester.pumpAndSettle();
    expect(inHeader(SidePanelToggle), findsNothing);
    expect(
      find.descendant(of: pane(first), matching: find.byType(SidePanelToggle)),
      findsOneWidget,
    );
    expect(inHeader(OpenInEditorButton), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a pane clicked, the sidebar goes to its agent\'s row; in a '
      'folded project to its header, the project left folded', (tester) async {
    final workspace = await pumpApp(tester);
    // Too short for the whole list.
    tester.view.physicalSize = const Size(1400, 480);
    AgentThread agent(String title) =>
        workspace.threads.firstWhere((thread) => thread.title == title);
    workspace.openBeside(agent(second), agent(first), PaneSide.right);
    await tester.pumpAndSettle();
    final scrollable = inSidebar(find.byType(Scrollable)).last;
    final list = tester.state<ScrollableState>(scrollable);
    expect(list.position.maxScrollExtent, greaterThan(0));
    bool shown(Finder finder) =>
        tester.getRect(scrollable).contains(tester.getCenter(finder));
    // Well within the list, not at its top or bottom edge.
    bool seen(Finder finder) {
      final view = tester.getRect(scrollable);
      final at = tester.getCenter(finder).dy;
      return at >= view.top + view.height * .15 &&
          at <= view.top + view.height * .85;
    }

    list.position.jumpTo(0);
    await tester.pump();
    final row = inSidebar(find.textContaining(second));
    await tester.tapAt(tester.getRect(pane(first)).center);
    await tester.pump();
    await tester.tapAt(tester.getRect(pane(second)).center);
    await tester.pumpAndSettle();
    expect(workspace.current!.title, second);
    expect(list.position.pixels, greaterThan(0));
    expect(seen(row), isTrue);
    expect(shown(inSidebar(find.text(agent(second).project.name))), isTrue);

    // Its project folded: left so, its header brought to instead.
    final project = agent(second).project;
    final group = Workspace.projectGroup(project.path);
    workspace.toggleCollapsed(group);
    // Shorter still, for the folded list to scroll too.
    tester.view.physicalSize = const Size(1400, 340);
    await tester.tapAt(tester.getRect(pane(first)).center);
    await tester.pumpAndSettle();
    expect(row, findsNothing);
    expect(list.position.maxScrollExtent, greaterThan(0));
    list.position.jumpTo(0);
    await tester.pump();
    await tester.tapAt(tester.getRect(pane(second)).center);
    await tester.pumpAndSettle();
    expect(workspace.isCollapsed(group), isTrue);
    expect(row, findsNothing);
    expect(list.position.pixels, greaterThan(0));
    expect(shown(inSidebar(find.text(project.name))), isTrue);
  });

  testWidgets('a row clicked to open its agent stays under the pointer, '
      'near the list\'s edge too', (tester) async {
    final workspace = await pumpApp(tester);
    tester.view.physicalSize = const Size(1400, 480);
    await tester.pumpAndSettle();
    final scrollable = inSidebar(find.byType(Scrollable)).last;
    final list = tester.state<ScrollableState>(scrollable);
    list.position.jumpTo(0);
    await tester.pump();
    final view = tester.getRect(scrollable);
    // An agent not open whose row's middle is in the list's last 15%,
    // scrolled to be all shown there.
    final near = workspace.threads.firstWhere((thread) {
      if (identical(thread, workspace.current)) return false;
      final finder = inSidebar(find.text(thread.title));
      return finder.evaluate().length == 1 &&
          tester.getRect(finder).center.dy > view.top + view.height * .85;
    });
    final row = inSidebar(find.text(near.title));
    list.position.jumpTo(
      math.max(0, tester.getRect(row).bottom - (view.bottom - 4)),
    );
    await tester.pump();
    final at = list.position.pixels;
    expect(
      tester.getRect(row).center.dy,
      greaterThan(view.top + view.height * .85),
    );
    expect(tester.getRect(row).bottom, lessThanOrEqualTo(view.bottom));

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(workspace.current, near);
    expect(list.position.pixels, at);
  });

  testWidgets('an agent of a project a pane shows, or a new one there, goes '
      'over that pane, whichever is focused', (tester) async {
    final workspace = await pumpApp(tester);
    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    final firstThread = workspace.threads.firstWhere((t) => t.title == first);
    final secondThread = workspace.threads.firstWhere((t) => t.title == second);
    expect(workspace.current, secondThread);
    final sibling = workspace.threads.firstWhere(
      (t) => t.project == firstThread.project && t != firstThread,
    );

    workspace.select(sibling);
    await tester.pumpAndSettle();
    expect(workspace.grid.panes, unorderedEquals([sibling, secondThread]));
    expect(workspace.grid.under(sibling), [firstThread]);

    workspace.select(secondThread);
    final created = workspace.create(project: firstThread.project);
    await tester.pumpAndSettle();
    expect(workspace.grid.panes, unorderedEquals([created, secondThread]));
    expect(workspace.grid.under(created), [firstThread, sibling]);
  });

  testWidgets('shown as tabs, a pane\'s agents switch by a click or the '
      'keys, and the arrows go to the pane that way', (tester) async {
    final workspace = await pumpApp(tester);
    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    AgentThread agent(String title) =>
        workspace.threads.firstWhere((thread) => thread.title == title);
    workspace.select(agent(third));
    await tester.pumpAndSettle();
    expect(workspace.grid.tabs(agent(third)), [agent(second), agent(third)]);
    // Behind the layers button until shown as tabs.
    Finder tab(String title) =>
        find.descendant(of: find.byType(PaneTabs), matching: find.text(title));
    expect(tab(second), findsNothing);
    workspace.paneTabs = true;
    await tester.pumpAndSettle();
    expect(tab(second), findsOneWidget);
    expect(tab(third), findsOneWidget);
    // In place of the title.
    expect(
      find.descendant(of: pane(third), matching: find.byType(PaneTabs)),
      findsOneWidget,
    );

    await tester.tap(tab(second));
    await tester.pumpAndSettle();
    expect(workspace.current, agent(second));
    expect(paneTitles(tester), unorderedEquals([first, second]));
    // Its order stays as the tabs switch.
    expect(workspace.grid.tabs(agent(second)), [agent(second), agent(third)]);

    Future<void> press(LogicalKeyboardKey arrow, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(arrow);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await press(LogicalKeyboardKey.arrowRight, shift: true);
    expect(workspace.current, agent(third));
    await press(LogicalKeyboardKey.arrowRight, shift: true);
    expect(workspace.current, agent(second));
    await press(LogicalKeyboardKey.arrowLeft);
    expect(workspace.current, agent(first));
    await press(LogicalKeyboardKey.arrowLeft);
    expect(workspace.current, agent(first));
    await press(LogicalKeyboardKey.arrowRight);
    expect(workspace.current, agent(second));

    // Closed from its tab, one under the pane goes; the pane stays.
    await tester.tap(tab(third));
    await tester.pumpAndSettle();
    workspace.closeCovered(agent(third), agent(second));
    await tester.pumpAndSettle();
    expect(workspace.grid.tabs(agent(third)), [agent(third)]);
    expect(tab(third), findsNothing);

    // Turned off from the layers button's menu, where it was turned on.
    workspace.select(agent(second));
    await tester.pumpAndSettle();
    expect(tab(second), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('1 conversation under this one'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show as Tabs'));
    await tester.pumpAndSettle();
    expect(workspace.paneTabs, isFalse);
    expect(find.byType(PaneTabs), findsNothing);
  });

  testWidgets('a tab\'s Close Others leaves it alone in its pane, whichever '
      'tab showed', (tester) async {
    final workspace = await pumpApp(tester);
    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    AgentThread agent(String title) =>
        workspace.threads.firstWhere((thread) => thread.title == title);
    workspace.select(agent(third));
    await tester.pumpAndSettle();
    final created = workspace.create(project: agent(second).project);
    workspace.paneTabs = true;
    await tester.pumpAndSettle();
    Finder tab(AgentThread thread) => find.descendant(
      of: find.byType(PaneTabs),
      matching: find.text(thread.localizedTitle(AppLocalizationsEn())),
    );
    // The first tab shown, the one kept under it.
    await tester.tap(tab(agent(second)));
    await tester.pumpAndSettle();
    expect(workspace.grid.under(agent(second)), [agent(third), created]);

    await tester.ensureVisible(tab(created));
    await tester.pumpAndSettle();
    await tester.tap(tab(created), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close Others'));
    await tester.pumpAndSettle();
    expect(workspace.grid.panes, unorderedEquals([agent(first), created]));
    expect(workspace.grid.under(created), isEmpty);
    expect(find.byType(PaneTabs), findsNothing);
  });

  testWidgets('the sidebar shows an agent over the focused pane: not built '
      'while covered, back where it was once the other closes', (tester) async {
    final workspace = await pumpApp(tester);
    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    final right = tester.getRect(pane(second));
    await tester.tap(inSidebar(find.textContaining(third)));
    await tester.pumpAndSettle();
    expect(paneTitles(tester), unorderedEquals([first, third]));
    expect(pane(second), findsNothing);
    // The pane says what is under it, and its close button what comes back.
    final layers = find.descendant(
      of: pane(third),
      matching: find.bySemanticsLabel('1 conversation under this one'),
    );
    expect(layers, findsOneWidget);
    expect(
      find.descendant(
        of: pane(third),
        matching: find.bySemanticsLabel('Close pane, back to $second'),
      ),
      findsOneWidget,
    );
    // Its menu shows the one under it again, the other going under.
    await tester.tap(layers);
    await tester.pumpAndSettle();
    await tester.tap(find.text(second).last);
    await tester.pumpAndSettle();
    expect(paneTitles(tester), unorderedEquals([first, second]));
    expect(workspace.grid.under(workspace.current!).single.title, third);
    workspace.select(workspace.threads.firstWhere((t) => t.title == third));
    await tester.pumpAndSettle();
    expect(workspace.grid.under(workspace.current!).single.title, second);

    // Dragged to a pane's middle: the preview says it goes over it.
    final gesture = await dragAgent(
      tester,
      fourth,
      tester.getRect(pane(first)).center,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Over $first, which shows again once this closes'),
      findsOneWidget,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(workspace.grid.under(workspace.current!).single.title, first);
    workspace.closePane(workspace.current!);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: pane(third),
        matching: find.bySemanticsLabel('Close pane, back to $second'),
      ),
    );
    await tester.pumpAndSettle();
    expect(paneTitles(tester), unorderedEquals([first, second]));
    expect(tester.getRect(pane(second)), right);
    // Another pane's close leaves the focus where it was.
    expect(workspace.current!.title, first);

    // Covered, picked from another pane, it shows again in its own, over
    // the one that covered it.
    AgentThread agent(String title) =>
        workspace.threads.firstWhere((thread) => thread.title == title);
    workspace.select(agent(second));
    workspace.select(agent(third));
    workspace.select(agent(first));
    workspace.select(agent(second));
    await tester.pumpAndSettle();
    expect(paneTitles(tester), unorderedEquals([first, second]));
    expect(workspace.grid.under(agent(second)), [agent(third)]);
    workspace.closePane(agent(second));
    await tester.pumpAndSettle();
    expect(paneTitles(tester), unorderedEquals([first, third]));
  });

  testWidgets('the lines drag, each shared by the panes either side of it', (
    tester,
  ) async {
    await pumpApp(tester);
    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    await dropAgent(
      tester,
      third,
      near(tester.getRect(pane(first)), PaneSide.bottom),
    );
    await dropAgent(
      tester,
      fourth,
      near(tester.getRect(pane(second)), PaneSide.bottom),
    );
    final before = tester.getRect(pane(first));
    // The column line, in the gap under the pointer: as thick as the IDE's
    // sashes while dragged, in their color.
    final gesture = await tester.startGesture(
      Offset(before.right + ChatGridView.gap / 2, before.center.dy),
    );
    await gesture.moveBy(const Offset(-50, 0));
    await gesture.moveBy(const Offset(-50, 0));
    await tester.pumpAndSettle();
    expect(lineColor(tester), IdeModernUI.sashHover);
    expect(tester.getSize(line()).width, IdeModernUI.gap);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(lineColor(tester), Colors.transparent);
    expect(tester.getSize(line()).width, 0);
    expect(tester.getRect(pane(first)).width, before.width - 100);
    expect(tester.getRect(pane(third)).width, before.width - 100);
    expect(
      tester.getRect(pane(fourth)).left,
      tester.getRect(pane(second)).left,
    );

    // No narrower than a pane's least.
    await tester.dragFrom(
      Offset(
        tester.getRect(pane(first)).right + ChatGridView.gap / 2,
        before.center.dy,
      ),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(pane(third)).width, ChatGridView.minPane.width);
  });

  testWidgets('four panes: the heights in one column move apart from the '
      'other\'s', (tester) async {
    await pumpApp(tester);
    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    await dropAgent(
      tester,
      third,
      near(tester.getRect(pane(first)), PaneSide.bottom),
    );
    await dropAgent(
      tester,
      fourth,
      near(tester.getRect(pane(second)), PaneSide.bottom),
    );
    final left = tester.getRect(pane(first));
    final right = tester.getRect(pane(second));
    expect(left.bottom, right.bottom);
    await tester.dragFrom(
      Offset(left.center.dx, left.bottom + ChatGridView.gap / 2),
      const Offset(0, 60),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(pane(first)).height, left.height + 60);
    expect(tester.getRect(pane(second)), right);
    expect(tester.getRect(pane(fourth)).top, right.bottom + ChatGridView.gap);
  });

  testWidgets('too narrow for two, the window grows to fit once released; '
      'where it cannot, nothing is dropped', (tester) async {
    var room = <String, double>{'width': 400, 'height': 0};
    final grown = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('baocode/window'),
      (call) async {
        switch (call.method) {
          case 'windowRoom':
            return room;
          case 'growWindow':
            grown.add(call.arguments);
        }
        return null;
      },
    );
    await pumpApp(tester, width: 900);
    final grid = gridRect(tester);
    final needed = 2 * ChatGridView.minPane.width + ChatGridView.gap;
    expect(grid.width, lessThan(needed));

    var gesture = await dragAgent(tester, second, near(grid, PaneSide.right));
    await tester.pumpAndSettle();
    expect(find.text('The window grows to fit'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(grown, [
      {'width': needed - grid.width, 'height': 0.0},
    ]);
    expect(paneTitles(tester), unorderedEquals([first, second]));

    // Out of room: said so, and released, nothing.
    room = {'width': 0, 'height': 0};
    await tester.tap(
      find.descendant(
        of: pane(second),
        matching: find.bySemanticsLabel('Close pane'),
      ),
    );
    await tester.pumpAndSettle();
    gesture = await dragAgent(tester, second, near(grid, PaneSide.right));
    await tester.pumpAndSettle();
    expect(find.text('Not enough room on this screen'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(grown, hasLength(1));
    expect(paneTitles(tester), [first]);

    // Above or below, there is height enough.
    await dropAgent(tester, second, near(grid, PaneSide.bottom));
    expect(paneTitles(tester), unorderedEquals([first, second]));
    expect(grown, hasLength(1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('from the drawer: it gets out of the way, and stays out as '
      'the window grows past the narrow width', (tester) async {
    final grown = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('baocode/window'),
      (call) async {
        switch (call.method) {
          case 'windowRoom':
            return {'width': 500.0, 'height': 500.0};
          case 'growWindow':
            grown.add(call.arguments);
        }
        return null;
      },
    );
    await pumpApp(tester, width: 700);
    await tester.tap(find.bySemanticsLabel('Show sidebar'));
    await tester.pumpAndSettle();
    final gesture = await dragAgent(tester, second, const Offset(650, 450));
    await tester.pumpAndSettle();
    expect(find.byType(Sidebar), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    final needed = 2 * ChatGridView.minPane.width + ChatGridView.gap;
    // The window's room less the gaps about the cards.
    expect(grown, [
      {'width': needed - (700 - 2 * Islands.gap), 'height': 0.0},
    ]);
    expect(paneTitles(tester), unorderedEquals([first, second]));

    // The window grew as asked: the panes have it all.
    tester.view.physicalSize = Size(needed + 2 * Islands.gap, 900);
    await tester.pumpAndSettle();
    expect(gridRect(tester).width, needed);
    expect(tester.getRect(pane(first)).width, ChatGridView.minPane.width);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('the title keeps to the pane\'s start, after its close '
      'button side by side, and the buttons to its end', (tester) async {
    await pumpApp(tester);

    void expectPlaced(String title, Finder rightmost, {bool close = false}) {
      final composer = tester.getRect(
        find.descendant(of: pane(title), matching: find.byType(ChatComposer)),
      );
      final text = find.descendant(
        of: find.descendant(
          of: pane(title),
          matching: find.byType(TitleBarDoubleClick),
        ),
        matching: find.text(title),
      );
      final start = tester.getRect(pane(title)).left + 12;
      if (close) {
        final button = tester.getRect(
          find.descendant(
            of: pane(title),
            matching: find.bySemanticsLabel('Close pane'),
          ),
        );
        expect(button.left, start);
        expect(tester.getTopLeft(text).dx, button.right + 4);
      } else {
        expect(tester.getTopLeft(text).dx, start);
        // No further in than the input (as far in, on a narrow card).
        expect(tester.getTopLeft(text).dx, lessThanOrEqualTo(composer.left));
      }
      expect(
        tester
            .getTopRight(find.descendant(of: pane(title), matching: rightmost))
            .dx,
        tester.getRect(pane(title)).right -
            // The side panel's toggle with its padding (2), on the card.
            // Alone, the window's: as far from its edge as the IDE's.
            (close ? ChatScreen.cardHeaderEnd + 2 : 8 - Islands.gap),
      );
    }

    // A wide window: the column in the middle, well in from the sides.
    final composer = tester.getRect(find.byType(ChatComposer));
    expect(composer.left - gridRect(tester).left, greaterThan(100));
    expectPlaced(first, find.byType(OpenInEditorButton));
    final editor = tester.getRect(find.byType(OpenInEditorButton));

    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    // Each pane keeps the buttons its own agent's, its side panel's at the
    // end; the editor's is the window's, where it was.
    expectPlaced(first, find.byType(SidePanelToggle), close: true);
    expectPlaced(second, find.byType(SidePanelToggle), close: true);
    expect(tester.getRect(find.byType(OpenInEditorButton)), editor);
  });

  testWidgets(
    'Open in Editor is where the IDE\'s Back to Chat is, one conversation '
    'shown or several',
    (tester) async {
      final workspace = await pumpApp(tester, width: 1600);
      final one = tester.getRect(find.byType(OpenInEditorButton));
      await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
      expect(find.byType(OpenInEditorButton), findsOneWidget);
      expect(tester.getRect(find.byType(OpenInEditorButton)), one);
      workspace.layout = WorkspaceLayout.ide;
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(BackToChatButton)), one);
      workspace.layout = WorkspaceLayout.chat;
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant(const {
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets('dragging the sidebar\'s border or a line lays the chats out '
      'anew without building them: as thick as the IDE\'s sashes', (
    tester,
  ) async {
    await pumpApp(tester);
    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    ChatScreen screen() => tester.widget<ChatScreen>(pane(first));
    MarkdownView message() => tester.widget<MarkdownView>(
      find
          .descendant(of: pane(first), matching: find.byType(MarkdownView))
          .first,
    );
    final left = tester.getRect(pane(first));

    // The sidebar's border: built again as the drag begins (the band, the
    // cursor), then only laid out as it goes.
    final band = find.byWidgetPredicate(
      (widget) =>
          widget is AnimatedContainer &&
          widget.constraints?.maxWidth == IdeModernUI.gap,
    );
    var gesture = await tester.startGesture(
      Offset(tester.getTopRight(find.byType(Sidebar)).dx + 2, 400),
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(band, findsOneWidget);
    var built = (screen: screen(), message: message());
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(tester.getRect(pane(first)).left, left.left + 60);
    expect(identical(screen(), built.screen), isTrue);
    expect(identical(message(), built.message), isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(band, findsNothing);

    // A line between panes: the panes not built again at all.
    built = (screen: screen(), message: message());
    final now = tester.getRect(pane(first));
    gesture = await tester.startGesture(
      Offset(now.right + ChatGridView.gap / 2, now.center.dy),
    );
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    expect(tester.getRect(pane(first)).width, now.width - 40);
    expect(identical(screen(), built.screen), isTrue);
    expect(identical(message(), built.message), isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
