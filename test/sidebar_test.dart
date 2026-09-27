import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/chat_screen.dart';
import 'package:monad/chat/chat_session.dart';
import 'package:monad/main.dart';
import 'package:monad/chat/widgets/user_message_bubble.dart';
import 'package:monad/sidebar/sidebar.dart';
import 'package:monad/workspace/editor_launcher.dart';
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
  for (var i = 0; i < 400 && session.pendingQuestion == null; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(session.pendingQuestion, isNotNull);
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
    background.session.answerQuestion('随内容自动增高');
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
    await pumpApp(tester);
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

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(ChatScreen)).dx, lessThan(chatLeft));
    expect(find.bySemanticsLabel('Show sidebar'), findsOneWidget);

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
    final workspace = await pumpApp(tester, width: 800);
    expect(find.byType(Sidebar), findsNothing);
    final chatWidth = tester.getSize(find.byType(ChatScreen)).width;
    expect(chatWidth, 800);

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

  testWidgets('opens the project in the chosen editor', (tester) async {
    final workspace = await pumpApp(tester);
    expect(find.bySemanticsLabel('Open in VS Code'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Choose editor'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Zed'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(workspace.preferredEditor, Editor.zed);
    expect(find.bySemanticsLabel('Open in Zed'), findsOneWidget);
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
}
