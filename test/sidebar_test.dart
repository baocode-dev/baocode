import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/chat_screen.dart';
import 'package:monad/chat/chat_session.dart';
import 'package:monad/kernel/kernel_types.dart';
import 'package:monad/ide/ide_hover.dart';
import 'package:monad/main.dart';
import 'package:monad/chat/widgets/user_message_bubble.dart';
import 'package:monad/sidebar/sidebar.dart';
import 'package:monad/theme/codicons.dart';
import 'package:monad/theme/workbench_theme.dart';
import 'package:monad/workspace/editor_launcher.dart';
import 'package:monad/workspace/open_in_editor_button.dart';
import 'package:monad/workspace/pin_window_button.dart';
import 'package:monad/workspace/workspace.dart';

Future<Workspace> pumpApp(WidgetTester tester, {double width = 1400}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final workspace = Workspace.mock();
  await tester.pumpWidget(MonadApp(workspace: workspace));
  await tester.pump();
  return workspace;
}

Finder inSidebar(Finder finder) =>
    find.descendant(of: find.byType(Sidebar), matching: finder);

String chatTitle(WidgetTester tester) =>
    tester.widget<ChatScreen>(find.byType(ChatScreen)).title;

AgentThread threadNamed(Workspace workspace, String title) =>
    workspace.threads.firstWhere((thread) => thread.title == title);

/// Runs the mock script until it asks its question.
Future<void> runUntilQuestion(WidgetTester tester, ChatSession session) async {
  for (var i = 0; i < 400 && session.pendingInteraction == null; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(session.pendingInteraction, isNotNull);
}

void main() {
  testWidgets('lists agents by project and opens the one clicked', (
    tester,
  ) async {
    final workspace = await pumpApp(tester);
    expect(inSidebar(find.text('monad')), findsOneWidget);
    expect(inSidebar(find.text('cursor-docs')), findsOneWidget);
    expect(inSidebar(find.text('api-gateway')), findsOneWidget);
    // Pinned agents sit above the projects.
    expect(inSidebar(find.text('Pinned')), findsOneWidget);
    expect(
      tester.getTopLeft(inSidebar(find.text('Pinned'))).dy,
      lessThan(tester.getTopLeft(inSidebar(find.text('monad'))).dy),
    );
    expect(chatTitle(tester), 'Optimize virtual list scrolling');

    await tester.tap(inSidebar(find.textContaining('Rate limit per API key')));
    await tester.pump();
    expect(chatTitle(tester), 'Rate limit per API key');
    expect(workspace.selected.title, 'Rate limit per API key');

    // Collapsing a project hides its agents and shows how many there are.
    await tester.tap(inSidebar(find.text('api-gateway')));
    await tester.pump();
    expect(
      inSidebar(find.textContaining('Rate limit per API key')),
      findsNothing,
    );
    expect(inSidebar(find.text('3')), findsOneWidget);
  });

  testWidgets('a new agent is named by its first message', (tester) async {
    final workspace = await pumpApp(tester);
    await tester.tap(inSidebar(find.text('New Agent')));
    await tester.pump();
    final thread = workspace.selected;
    expect(thread.project.name, 'monad');
    expect(chatTitle(tester), 'New Agent');
    expect(find.text('Plan, build, anything'), findsOneWidget);

    // Asking again reuses the untouched one.
    await tester.tap(inSidebar(find.text('New Agent')).first);
    await tester.pump();
    expect(
      workspace.threads.where((t) => t.title == 'New Agent'),
      hasLength(1),
    );

    thread.session.send(const ComposerMessage(text: '整理一下测试\n第二行'));
    await tester.pump();
    expect(chatTitle(tester), '整理一下测试');
    expect(find.text('Plan, build, anything'), findsNothing);
    expect(inSidebar(find.byType(CircularProgressIndicator)), findsOneWidget);
    thread.session.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('shows which background agents need attention', (tester) async {
    final workspace = await pumpApp(tester);
    final background = threadNamed(workspace, 'Rate limit per API key');
    background.session.send(const ComposerMessage(text: '加一个限流'));
    await tester.pump();
    expect(background.status, ThreadStatus.running);

    await runUntilQuestion(tester, background.session);
    expect(background.status, ThreadStatus.needsInput);

    // Grouped by status, it is at the top.
    await tester.tap(inSidebar(find.text('By project')));
    await tester.pump();
    await tester.tap(find.text('Status'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(inSidebar(find.text('Needs input')), findsOneWidget);
    expect(
      tester.getTopLeft(inSidebar(find.text('Needs input'))).dy,
      lessThan(tester.getTopLeft(inSidebar(find.text('Done'))).dy),
    );

    // It finishes out of view: unread until opened.
    background.session.answer(
      const QuestionAnswer([
        ['随内容自动增高，最多 8 行'],
      ]),
    );
    for (var i = 0; i < 200 && background.session.isStreaming; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(background.status, ThreadStatus.unread);
    expect(inSidebar(find.text('Unread')), findsOneWidget);
    await tester.tap(inSidebar(find.textContaining('Rate limit per API key')));
    await tester.pump();
    expect(background.status, ThreadStatus.idle);
    // Its background task settles.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('groups by date and filters by search', (tester) async {
    final workspace = await pumpApp(tester);
    // The mock's times are ages back from now, so their calendar days depend
    // on the time of day: its only unpinned thread of a day ago (a day and
    // six hours) is two days ago before 6 am. One today, one yesterday.
    final now = DateTime.now();
    threadNamed(workspace, 'Rate limit per API key').updatedAt = now;
    threadNamed(workspace, 'Migrate auth middleware to JWT').updatedAt =
        DateTime(now.year, now.month, now.day - 1, 12);
    await tester.tap(inSidebar(find.text('By project')));
    await tester.pump();
    await tester.tap(find.text('Date'));
    await tester.pump(const Duration(milliseconds: 200));
    for (final label in ['Today', 'Yesterday', 'Previous 7 days', 'Older']) {
      expect(inSidebar(find.text(label)), findsOneWidget);
    }

    await tester.enterText(inSidebar(find.byType(TextField)), 'flaky');
    await tester.pump();
    expect(
      inSidebar(find.textContaining('Flaky integration test on CI')),
      findsOneWidget,
    );
    expect(inSidebar(find.textContaining('Rate limit')), findsNothing);
    expect(inSidebar(find.text('Today')), findsNothing);

    await tester.enterText(
      inSidebar(find.byType(TextField)),
      'nothing like it',
    );
    await tester.pump();
    expect(inSidebar(find.text('No matching agents')), findsOneWidget);
  });

  testWidgets('renames, pins, archives and deletes from the menu', (
    tester,
  ) async {
    final workspace = await pumpApp(tester);
    final thread = threadNamed(workspace, 'Rate limit per API key');
    Finder row() => inSidebar(find.textContaining(thread.title));

    Future<void> menu(String action) async {
      await tester.tap(row(), buttons: kSecondaryButton);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text(action));
      await tester.pump(const Duration(milliseconds: 200));
    }

    await menu('Rename');
    await tester.enterText(inSidebar(find.byType(TextField)).last, 'Throttle');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(thread.title, 'Throttle');
    expect(row(), findsOneWidget);

    await menu('Pin');
    expect(thread.pinned, isTrue);
    expect(
      tester.getTopLeft(row()).dy,
      lessThan(tester.getTopLeft(inSidebar(find.text('monad'))).dy),
    );

    await menu('Archive');
    expect(thread.archived, isTrue);
    expect(row(), findsNothing);
    await tester.tap(inSidebar(find.text('Archived · 1')));
    await tester.pump();
    expect(row(), findsOneWidget);

    await menu('Delete');
    await tester.tap(find.widgetWithText(GestureDetector, 'Delete').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(workspace.threads, isNot(contains(thread)));
    expect(row(), findsNothing);
  });

  testWidgets('hovered, a row offers pin and archive in place of its time', (
    tester,
  ) async {
    final workspace = await pumpApp(tester);
    final thread = threadNamed(workspace, 'Rate limit per API key');
    Finder row() => inSidebar(find.textContaining(thread.title));
    // No kernel mark on the rows.
    expect(inSidebar(find.byIcon(thread.kernel.icon)), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    Future<void> hover() async {
      await mouse.moveTo(tester.getCenter(row()));
      await tester.pump();
    }

    expect(inSidebar(find.text('55m')), findsOneWidget);
    await hover();
    expect(inSidebar(find.text('55m')), findsNothing);
    expect(inSidebar(find.byIcon(Icons.push_pin_outlined)), findsOneWidget);
    expect(inSidebar(find.byIcon(Icons.inventory_2_outlined)), findsOneWidget);

    // Pinned, it looks the same: the pin shows only on hover, filled.
    await tester.tap(inSidebar(find.byIcon(Icons.push_pin_outlined)));
    await tester.pump();
    expect(thread.pinned, isTrue);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(inSidebar(find.byIcon(Icons.push_pin)), findsNothing);
    await hover();
    expect(inSidebar(find.byIcon(Icons.push_pin)), findsOneWidget);

    await tester.tap(inSidebar(find.byIcon(Icons.inventory_2_outlined)));
    await tester.pump();
    expect(thread.archived, isTrue);
    expect(thread.pinned, isFalse);
  });

  testWidgets('high contrast themes outline the hovered row, as the IDE '
      'lists do', (tester) async {
    final themes = WorkbenchThemeService.instance;
    final before = themes.colorTheme;
    addTearDown(
      () => themes.restore(
        setting: before.settingsId,
        data: before.isLoaded ? before.toStorage() : null,
      ),
    );
    await tester.runAsync(
      () => themes.setColorTheme('Default High Contrast', preview: true),
    );
    final outline = themes.colors.get('contrastActiveBorder');
    expect(outline, isNotNull);
    final workspace = await pumpApp(tester);
    final thread = threadNamed(workspace, 'Rate limit per API key');
    Color? rowOutline() {
      final row = tester
          .widgetList<Container>(
            find.ancestor(
              of: inSidebar(find.textContaining(thread.title)),
              matching: find.byType(Container),
            ),
          )
          .firstWhere((container) => container.decoration != null);
      final decoration = row.foregroundDecoration as BoxDecoration?;
      return (decoration?.border as Border?)?.top.color;
    }

    expect(rowOutline(), isNull);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(
      location: tester.getCenter(inSidebar(find.textContaining(thread.title))),
    );
    await tester.pump();
    expect(rowOutline(), outline);
  });

  testWidgets('its icon buttons have the workbench hover', (tester) async {
    await pumpApp(tester);
    final button = inSidebar(find.bySemanticsLabel('Hide sidebar'));
    expect(button, findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(button));
    await tester.pump();
    await tester.pump(ideHoverDelay + const Duration(milliseconds: 150));
    expect(
      find.ancestor(
        of: find.text('Hide sidebar'),
        matching: find.byType(IdeHoverBox),
      ),
      findsOneWidget,
    );
  });

  testWidgets('deleting the open agent opens the most recent one', (
    tester,
  ) async {
    final workspace = await pumpApp(tester);
    final open = workspace.selected;
    workspace.delete(open);
    await tester.pump();
    expect(workspace.selected.title, 'Sticky user message on scroll');
    expect(chatTitle(tester), 'Sticky user message on scroll');
  });

  testWidgets('⌘B hides and shows the sidebar', (tester) async {
    await pumpApp(tester);
    expect(tester.getSize(find.byType(Sidebar)).width, 260);
    final chatLeft = tester.getTopLeft(find.byType(ChatScreen)).dx;
    // Its toggles have the IDE's layout icons, open or not.
    IconData icon(String tooltip) => tester
        .widget<SidebarIconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is SidebarIconButton && widget.tooltip == tooltip,
          ),
        )
        .icon;
    expect(icon('Hide sidebar'), Codicons.layoutSidebarLeft);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(ChatScreen)).dx, lessThan(chatLeft));
    expect(find.bySemanticsLabel('Show sidebar'), findsOneWidget);
    expect(icon('Show sidebar'), Codicons.layoutSidebarLeftOff);

    await tester.tap(find.bySemanticsLabel('Show sidebar'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(ChatScreen)).dx, chatLeft);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('drags the border to resize', (tester) async {
    await pumpApp(tester);
    final border = Offset(tester.getTopRight(find.byType(Sidebar)).dx + 2, 400);
    await tester.dragFrom(border, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Sidebar)).width, closeTo(340, 20));
    await tester.dragFrom(border + const Offset(80, 0), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Sidebar)).width, 200);
  });

  testWidgets('in a narrow window it is a drawer', (tester) async {
    final workspace = await pumpApp(tester, width: 700);
    expect(find.byType(Sidebar), findsNothing);
    final chatWidth = tester.getSize(find.byType(ChatScreen)).width;
    expect(chatWidth, 700);

    await tester.tap(find.bySemanticsLabel('Show sidebar'));
    await tester.pumpAndSettle();
    expect(find.byType(Sidebar), findsOneWidget);
    expect(tester.getSize(find.byType(ChatScreen)).width, chatWidth);

    // Opening an agent closes it.
    await tester.tap(inSidebar(find.textContaining('Rate limit per API key')));
    await tester.pumpAndSettle();
    expect(workspace.selected.title, 'Rate limit per API key');
    expect(find.byType(Sidebar), findsNothing);
  });

  testWidgets('double clicks rename an agent, in the list or the title', (
    tester,
  ) async {
    final workspace = await pumpApp(tester);
    final thread = threadNamed(workspace, 'Rate limit per API key');
    final row = inSidebar(find.textContaining('Rate limit per API key'));

    // The first click opens it straight away; the second renames.
    await tester.tap(row);
    await tester.pump();
    expect(workspace.selected, thread);
    await tester.tap(row);
    await tester.pump();
    await tester.enterText(inSidebar(find.byType(TextField)).last, 'Quota');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(thread.title, 'Quota');

    // The title bar, left-aligned by the chat's edge.
    final title = find.descendant(
      of: find.byType(ChatScreen),
      matching: find.text('Quota'),
    );
    expect(
      tester.getTopLeft(title).dx,
      lessThan(tester.getTopLeft(find.byType(ChatScreen)).dx + 20),
    );
    await tester.tap(title);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(title);
    await tester.pump();
    final field = find.descendant(
      of: find.byType(ChatScreen),
      matching: find.byType(TextField),
    );
    await tester.enterText(field.first, 'Quota per key');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(thread.title, 'Quota per key');
    expect(inSidebar(find.textContaining('Quota per key')), findsOneWidget);
    // The double tap's timers run out.
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('the chevron switches the editor; the button opens it', (
    tester,
  ) async {
    final opened = <Editor>[];
    OpenInEditorButton.launch = (editor, path) async {
      opened.add(editor);
      return true;
    };
    addTearDown(() => OpenInEditorButton.launch = openInEditor);
    final workspace = await pumpApp(tester);
    expect(find.bySemanticsLabel('Open in VS Code'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Choose editor'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Zed'));
    await tester.pump(const Duration(milliseconds: 200));
    // Picking only switches: nothing opens until the button is pressed.
    expect(workspace.preferredEditor, Editor.zed);
    expect(opened, isEmpty);
    await tester.tap(find.bySemanticsLabel('Open in Zed'));
    await tester.pump();
    expect(opened, [Editor.zed]);
    // The Fast Ide is one of the choices: kept, and opened as the layout.
    await tester.tap(find.bySemanticsLabel('Choose editor'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Fast Ide'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(workspace.preferredEditor, Editor.fastIde);
    expect(workspace.layout, WorkspaceLayout.chat);
    await tester.tap(find.bySemanticsLabel('Open in Fast Ide'));
    await tester.pump();
    expect(workspace.layout, WorkspaceLayout.ide);
    expect(opened, [Editor.zed]);
    workspace.layout = WorkspaceLayout.chat;
    await tester.pump();
  });

  testWidgets('an opened agent shows its stuck message from the first frame', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(inSidebar(find.textContaining('Rate limit per API key')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey(('sticky', 0))).hitTestable(),
      findsOneWidget,
    );
    expect(find.byType(UserMessageBubble).hitTestable(), findsNWidgets(2));
  });

  testWidgets('past its limit, the border waits for the pointer to return', (
    tester,
  ) async {
    await pumpApp(tester);
    double width() => tester.getSize(find.byType(Sidebar)).width;
    final gesture = await tester.startGesture(const Offset(262, 400));
    // Follows the pointer exactly, slop included.
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(width(), 300);
    // Far past the maximum (420), then back part of the way: still at max.
    await gesture.moveBy(const Offset(300, 0));
    await tester.pump();
    expect(width(), 420);
    await gesture.moveBy(const Offset(-150, 0));
    await tester.pump();
    expect(width(), 420);
    // Back past the border: follows again.
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();
    expect(width(), 350);
    // Same below the minimum (200).
    await gesture.moveBy(const Offset(-400, 0));
    await tester.pump();
    expect(width(), 200);
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    expect(width(), 200);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the pin keeps the window on top', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('monad/window'),
      (call) async {
        calls.add(call);
        return null;
      },
    );
    await pumpApp(tester);
    final pin = find.byType(PinWindowButton);
    // Left of the editor button.
    expect(
      tester.getTopRight(pin).dx,
      lessThan(tester.getTopLeft(find.bySemanticsLabel('Open in VS Code')).dx),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(pin));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Pin window on top'), findsOneWidget);
    await mouse.removePointer();
    await tester.pump(const Duration(milliseconds: 300));

    // The pin's calls, the window's appearance aside.
    Iterable<MethodCall> onTop() =>
        calls.where((call) => call.method == 'setAlwaysOnTop');
    await tester.tap(pin);
    await tester.pump();
    expect(onTop().single.arguments, isTrue);
    expect(tester.widget<PinWindowButton>(pin).pinned, isTrue);

    // Stays pinned in another agent.
    await tester.tap(inSidebar(find.textContaining('Rate limit per API key')));
    await tester.pump();
    expect(tester.widget<PinWindowButton>(pin).pinned, isTrue);
    await tester.tap(pin);
    await tester.pump();
    expect(onTop().last.arguments, isFalse);
    await tester.pump(const Duration(seconds: 1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('the pin is disabled where the window cannot stay on top', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byType(PinWindowButton));
    await tester.pump();
    expect(
      tester.widget<PinWindowButton>(find.byType(PinWindowButton)).pinned,
      isFalse,
    );
  });

  testWidgets('the drawer resizes too, sharing its width with the docked '
      'sidebar', (tester) async {
    await pumpApp(tester);
    double width() => tester.getSize(find.byType(Sidebar)).width;
    var border = Offset(tester.getTopRight(find.byType(Sidebar)).dx + 2, 400);
    await tester.dragFrom(border, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(width(), 320);

    // Narrow window: the drawer opens at that width.
    tester.view.physicalSize = const Size(700, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Show sidebar'));
    await tester.pumpAndSettle();
    expect(width(), 320);
    expect(tester.getTopLeft(find.byType(Sidebar)).dx, 0);

    // Its border drags like the docked one, and a click on it keeps the
    // drawer open.
    border = Offset(tester.getTopRight(find.byType(Sidebar)).dx + 2, 400);
    await tester.tapAt(border);
    await tester.pumpAndSettle();
    expect(find.byType(Sidebar), findsOneWidget);
    final gesture = await tester.startGesture(border);
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(width(), 240);
    await gesture.moveBy(const Offset(-200, 0));
    await tester.pump();
    expect(width(), 200);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(Sidebar), findsOneWidget);

    // Back to a wide window: docked at the new width.
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    expect(width(), 200);
  });

  testWidgets('never wider than the window less 20', (tester) async {
    await pumpApp(tester);
    double width() => tester.getSize(find.byType(Sidebar)).width;
    await tester.dragFrom(
      Offset(tester.getTopRight(find.byType(Sidebar)).dx + 2, 400),
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();
    expect(width(), 420);

    // A narrow browser window: the drawer is capped, and cannot be dragged
    // past the cap (its border would leave the window).
    tester.view.physicalSize = const Size(380, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Show sidebar'));
    await tester.pumpAndSettle();
    expect(width(), 360);
    final border = Offset(tester.getTopRight(find.byType(Sidebar)).dx + 2, 400);
    expect(border.dx, lessThan(380));
    final gesture = await tester.startGesture(border);
    await gesture.moveBy(const Offset(15, 0));
    await tester.pump();
    expect(width(), 360);
    await gesture.moveBy(const Offset(-75, 0));
    await tester.pump();
    expect(width(), 300);
    await gesture.up();
    await tester.pumpAndSettle();

    // What was set within the cap is kept.
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    expect(width(), 300);
  });

  testWidgets('an open drawer follows the window as it grows', (tester) async {
    await pumpApp(tester);
    await tester.dragFrom(
      Offset(tester.getTopRight(find.byType(Sidebar)).dx + 2, 400),
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(380, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Show sidebar'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Sidebar)).width, 360);

    // Resizing the window: every frame fits, at the new width at once.
    for (final width in <double>[400, 420, 460, 600]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(Sidebar)).width,
        (width - 20).clamp(0.0, 420.0),
      );
    }
  });
}
