import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/ide/ide_modern_ui.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/main.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/workspace/chat_grid.dart';
import 'package:baocode/workspace/chat_grid_view.dart';
import 'package:baocode/workspace/editor_launcher.dart';
import 'package:baocode/workspace/open_in_editor_button.dart';
import 'package:baocode/workspace/title_bar_double_click.dart';
import 'package:baocode/workspace/workspace.dart';

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

/// Near the middle of [rect]'s [side].
Offset near(Rect rect, PaneSide side) => switch (side) {
  PaneSide.left => Offset(rect.left + 30, rect.center.dy),
  PaneSide.right => Offset(rect.right - 30, rect.center.dy),
  PaneSide.top => Offset(rect.center.dx, rect.top + 60),
  PaneSide.bottom => Offset(rect.center.dx, rect.bottom - 60),
};

void main() {
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
    final left = tester.getRect(pane(first));
    final right = tester.getRect(pane(second));
    // Where it was, the first gives the second half its room; a line
    // between them, down the whole height.
    expect(left.topLeft, grid.topLeft);
    expect(right.right, grid.right);
    expect(right.left - left.right, ChatGridView.gap);
    expect(left.height, grid.height);
    // As the sidebar's border.
    expect(lineColor(tester), AppColors.border);
    final drawn = tester.getRect(line());
    expect(drawn.width, 1);
    expect(drawn.height, grid.height);
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
    // Below another, a double click on its title bar is not the window's.
    expect(tester.widget<ChatScreen>(pane(second)).windowTitleBar, isTrue);
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

    // Clicked in the sidebar, one shown already is focused where it is.
    final left = tester.getRect(pane(first));
    await tester.tap(inSidebar(find.textContaining(first)));
    await tester.pumpAndSettle();
    expect(paneTitles(tester), unorderedEquals([first, second]));
    expect(tester.getRect(pane(first)), left);
    expect(workspace.current!.title, first);
    expect(tester.widget<ChatScreen>(pane(first)).focused, isTrue);
    expect(tester.widget<ChatScreen>(pane(second)).focused, isFalse);

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

  testWidgets('the window\'s tools, in the top right pane, are the focused '
      'agent\'s: a click on them, or on another pane\'s close, leaves the '
      'focus; Fast Ide opens the focused agent', (tester) async {
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
    Finder tool(String label) => find.descendant(
      of: pane(second),
      matching: find.bySemanticsLabel(label),
    );

    await tester.tap(tool('Open in VS Code'));
    await tester.pump();
    expect(opened, [focused.project.path]);
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

    workspace.preferredEditor = Editor.fastIde;
    await tester.pump();
    await tester.tap(tool('Open in Fast Ide'));
    await tester.pump();
    await tester.pump();
    expect(workspace.layout, WorkspaceLayout.ide);
    expect(workspace.current, same(focused));
    final ide = find.byType(IdeWorkbench);
    expect(tester.widget<IdeWorkbench>(ide).project.path, focused.project.path);
    expect(find.descendant(of: ide, matching: pane(first)), findsOneWidget);
    expect(opened, hasLength(1));
    workspace.layout = WorkspaceLayout.chat;
    await tester.pump();
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
    expect(lineColor(tester), AppColors.border);
    expect(tester.getSize(line()).width, 1);
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
    expect(grown, [
      {'width': needed - 700, 'height': 0.0},
    ]);
    expect(paneTitles(tester), unorderedEquals([first, second]));

    // The window grew as asked: the panes have it all.
    tester.view.physicalSize = Size(needed, 900);
    await tester.pumpAndSettle();
    expect(gridRect(tester).width, needed);
    expect(tester.getRect(pane(first)).width, ChatGridView.minPane.width);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('the title and the buttons keep to the conversation\'s column, '
      'alone or side by side', (tester) async {
    await pumpApp(tester);
    void expectInColumn(String title, Finder rightmost) {
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
      expect(tester.getTopLeft(text).dx, composer.left);
      expect(
        tester
            .getTopRight(find.descendant(of: pane(title), matching: rightmost))
            .dx,
        composer.right,
      );
    }

    // A wide window: the column in the middle, well in from the sides.
    final composer = tester.getRect(find.byType(ChatComposer));
    expect(composer.left - gridRect(tester).left, greaterThan(100));
    expectInColumn(first, find.byType(OpenInEditorButton));

    await dropAgent(tester, second, near(gridRect(tester), PaneSide.right));
    expectInColumn(first, find.bySemanticsLabel('Close pane'));
    expectInColumn(second, find.bySemanticsLabel('Close pane'));
  });

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
