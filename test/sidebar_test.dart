import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/widgets/pixel_loader.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/mock_claude_code_transport.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/ide/ide_commands.dart' show ideUsesMacKeys;
import 'package:baocode/ide/ide_list.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:baocode/main.dart';
import 'package:baocode/search/search_palette.dart';
import 'package:baocode/chat/widgets/user_message_bubble.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/sidebar/sidebar_times.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:baocode/workspace/chat_grid_view.dart';
import 'package:baocode/workspace/chat_drag.dart';
import 'package:baocode/workspace/editor_launcher.dart';
import 'package:baocode/workspace/open_in_editor_button.dart';
import 'package:baocode/workspace/pin_window_button.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';

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

String chatTitle(WidgetTester tester) =>
    tester.widget<ChatScreen>(find.byType(ChatScreen)).title;

AgentThread threadNamed(Workspace workspace, String title) =>
    workspace.threads.firstWhere((thread) => thread.title == title);

/// Sessions Claude Code (the mock) keeps, in their projects.
class KeptCatalog implements SessionCatalog {
  KeptCatalog(this.records);

  final List<SessionRecord> records;

  @override
  Future<List<ProjectRecord>> projects() async => [
    for (final path in {for (final record in records) record.cwd})
      ProjectRecord(
        path: path,
        sessions: [
          for (final record in records)
            if (record.cwd == path) record,
        ],
      ),
  ];

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) async => const [];

  @override
  Future<void> delete(String id) async {}
}

/// A session titled `Chat <id>`, last active [minutesAgo].
SessionRecord kept(String id, String cwd, int minutesAgo) => SessionRecord(
  id: id,
  title: 'Chat $id',
  updatedAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
  cwd: cwd,
);

/// The app over the sessions [catalog] keeps, loaded.
Future<Workspace> pumpKept(
  WidgetTester tester,
  KeptCatalog catalog, {
  PreferenceStore? preferences,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late final KernelDescriptor claude;
  claude = KernelDescriptor(
    id: 'claude-code',
    label: 'Claude Code',
    icon: Icons.auto_awesome_rounded,
    description: '',
    catalog: catalog,
    create: (context) =>
        ClaudeCodeKernel(claude, context, start: MockClaudeCodeTransport.start),
  );
  final workspace = Workspace(kernels: [claude], preferences: preferences);
  await tester.pumpWidget(BaoCodeApp(workspace: workspace));
  await tester.runAsync(workspace.load);
  await tester.pump();
  return workspace;
}

AgentThread keptThread(Workspace workspace, String id) =>
    workspace.threads.firstWhere((thread) => thread.record?.id == id);

Future<void> clickChat(
  WidgetTester tester,
  String title, {
  LogicalKeyboardKey? holding,
}) async {
  if (holding != null) await tester.sendKeyDownEvent(holding);
  await tester.tap(inSidebar(find.text(title)));
  if (holding != null) await tester.sendKeyUpEvent(holding);
  await tester.pump();
}

LogicalKeyboardKey get multiSelectKey => ideUsesMacKeys
    ? LogicalKeyboardKey.metaLeft
    : LogicalKeyboardKey.controlLeft;

double top(WidgetTester tester, String text) =>
    tester.getTopLeft(inSidebar(find.text(text))).dy;

/// Drags with the mouse from [from] to where [to] is once the drag has
/// begun (the place to pin shows then), a few steps on the way.
Future<void> mouseDrag(
  WidgetTester tester,
  Offset from,
  Offset Function() to,
) async {
  final gesture = await tester.startGesture(
    from,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveBy(const Offset(0, -8));
  await tester.pump();
  from = from + const Offset(0, -8);
  final end = to();
  for (var i = 1; i <= 5; i++) {
    await gesture.moveTo(Offset.lerp(from, end, i / 5)!);
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

/// Right clicks [label] in the sidebar and picks [item] from its menu.
Future<void> pickFromMenu(
  WidgetTester tester,
  String label,
  String item,
) async {
  await tester.tap(inSidebar(find.text(label)), buttons: kSecondaryButton);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(item));
  await tester.pump(const Duration(milliseconds: 300));
}

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
    expect(inSidebar(find.text('baocode')), findsOneWidget);
    expect(inSidebar(find.text('cursor-docs')), findsOneWidget);
    expect(inSidebar(find.text('api-gateway')), findsOneWidget);
    // Pinned agents sit above the projects.
    expect(inSidebar(find.text('Pinned')), findsOneWidget);
    expect(
      tester.getTopLeft(inSidebar(find.text('Pinned'))).dy,
      lessThan(tester.getTopLeft(inSidebar(find.text('baocode'))).dy),
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
    await tester.tap(inSidebar(find.text('New Chat')));
    await tester.pump();
    final thread = workspace.selected;
    expect(thread.project.name, 'baocode');
    expect(chatTitle(tester), 'New Chat');

    // Asking again reuses the untouched one.
    await tester.tap(inSidebar(find.text('New Chat')).first);
    await tester.pump();
    expect(workspace.threads.where((t) => t.title == 'New Chat'), hasLength(1));

    thread.session.send(const ComposerMessage(text: '整理一下测试\n第二行'));
    await tester.pump();
    expect(chatTitle(tester), '整理一下测试');
    expect(inSidebar(find.byType(PixelLoader)), findsOneWidget);
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

    // Folded away, its project's header shows its dot, after the name.
    Finder dot() => find.descendant(
      of: find.byType(Sidebar),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Needs input',
      ),
    );
    expect(dot(), findsNothing);
    await tester.tap(inSidebar(find.text('api-gateway')));
    await tester.pump();
    expect(dot(), findsOneWidget);
    final name = tester.getRect(inSidebar(find.text('api-gateway')));
    final at = tester.getRect(dot());
    expect(at.left, greaterThan(name.right));
    expect(at.left - name.right, lessThan(12));
    expect(at.center.dy, moreOrLessEquals(name.center.dy, epsilon: 1));
    // The count at the end of the row; the name whole, the room between
    // them not split with it.
    expect(
      tester.getRect(find.byType(Sidebar)).right -
          tester.getRect(inSidebar(find.text('3'))).right,
      lessThan(20),
    );
    expect(
      tester
          .renderObject<RenderParagraph>(inSidebar(find.text('api-gateway')))
          .didExceedMaxLines,
      isFalse,
    );
    await tester.tap(inSidebar(find.text('api-gateway')));
    await tester.pump();
    expect(dot(), findsNothing);

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

  testWidgets('groups by date; Search finds agents in the palette', (
    tester,
  ) async {
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

    await tester.tap(inSidebar(find.text('Search')));
    await tester.pumpAndSettle();
    final palette = find.byType(SearchPalette);
    Finder inPalette(Finder finder) =>
        find.descendant(of: palette, matching: finder);
    await tester.enterText(
      inPalette(find.byType(TextField)),
      'nothing like it',
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(inPalette(find.text('No results')), findsOneWidget);

    await tester.enterText(inPalette(find.byType(TextField)), 'flaky');
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      inPalette(
        find.textContaining('Flaky integration test on CI', findRichText: true),
      ),
      findsWidgets,
    );
    expect(
      inPalette(find.textContaining('Rate limit', findRichText: true)),
      findsNothing,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(palette, findsNothing);
    expect(workspace.selected.title, 'Flaky integration test on CI');
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
      lessThan(tester.getTopLeft(inSidebar(find.text('baocode'))).dy),
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

  testWidgets('the archived button\'s menu unarchives them all, or deletes '
      'them all once confirmed', (tester) async {
    final workspace = await pumpApp(tester);
    final archived = workspace.threads.skip(1).take(2).toList();
    void archive() {
      for (final thread in archived) {
        workspace.setArchived(thread, true);
      }
    }

    Future<void> menu(String action) async {
      await tester.tap(
        inSidebar(find.text('Archived · 2')),
        buttons: kSecondaryButton,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text(action));
      await tester.pump(const Duration(milliseconds: 300));
    }

    archive();
    await tester.pump();
    await menu('Unarchive All');
    expect(archived.where((thread) => thread.archived), isEmpty);
    expect(inSidebar(find.textContaining('Archived')), findsNothing);

    archive();
    await tester.pump();
    await menu('Delete All Archived…');
    expect(find.text('Delete archived agents?'), findsOneWidget);
    await tester.tap(find.widgetWithText(GestureDetector, 'Delete').last);
    await tester.pump(const Duration(milliseconds: 300));
    for (final thread in archived) {
      expect(workspace.threads, isNot(contains(thread)));
    }
    expect(workspace.threads, isNotEmpty);
    expect(inSidebar(find.textContaining('Archived')), findsNothing);
  });

  testWidgets('shown, the archived agents\' heading has the same menu, on a '
      'right click or its … button (#90)', (tester) async {
    final workspace = await pumpApp(tester);
    final archived = workspace.threads.skip(1).take(2).toList();
    final heading = inSidebar(find.text('Archived'));
    Future<void> archiveAndShow() async {
      for (final thread in archived) {
        workspace.setArchived(thread, true);
      }
      await tester.pump();
      await tester.tap(inSidebar(find.text('Archived · 2')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(heading, findsOneWidget);
    }

    await archiveAndShow();
    await tester.tap(heading, buttons: kSecondaryButton);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Delete All Archived…'), findsOneWidget);
    await tester.tap(find.text('Unarchive All'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(archived.where((thread) => thread.archived), isEmpty);

    // Hovered, its … button opens it too.
    await archiveAndShow();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(heading));
    await tester.pump();
    await tester.tap(inSidebar(find.byIcon(Icons.more_horiz_rounded)));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Delete All Archived…'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Delete archived agents?'), findsOneWidget);
    await tester.tap(find.widgetWithText(GestureDetector, 'Delete').last);
    await tester.pump(const Duration(milliseconds: 300));
    for (final thread in archived) {
      expect(workspace.threads, isNot(contains(thread)));
    }
  });

  testWidgets('an agent\'s menu copies its session id, once it has one', (
    tester,
  ) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([kept('a1', '/tmp/a', 1), kept('a2', '/tmp/a', 2)]),
    );
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pickFromMenu(tester, 'Chat a2', 'Copy session ID');
    expect(copied, ['a2']);

    // A new agent has no session until its first message.
    workspace.create(project: workspace.projects.single);
    workspace.rename(workspace.selected, 'Fresh');
    await tester.pump();
    expect(workspace.selected.id, isNull);
    await tester.tap(inSidebar(find.text('Fresh')), buttons: kSecondaryButton);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Copy session ID'), findsNothing);
  });

  testWidgets('the archived agents of a project taken off the sidebar are '
      'listed', (tester) async {
    final records = [
      for (var i = 0; i < 12; i++) kept('monad$i', r'C:\monad', 60 * (i + 1)),
      kept('here0', r'C:\here', 1),
    ];
    final store = MemoryPreferenceStore({
      'sidebar': {
        'showArchived': true,
        'archived': [for (final record in records) record.id],
        // As "Remove from List" leaves a project: hidden, but its archived
        // agents are still counted by the footer.
        'hiddenProjects': {r'C:\monad': DateTime.now().toIso8601String()},
      },
    });
    final workspace = await pumpKept(
      tester,
      KeptCatalog(records),
      preferences: store,
    );
    expect(workspace.threads.where((thread) => thread.archived), hasLength(13));

    expect(inSidebar(find.text('Archived')), findsOneWidget);
    expect(
      inSidebar(find.textContaining(RegExp(r'^Chat here0 .*here$'))),
      findsOneWidget,
    );
    // Not listed under a project of its own, but among the archived ones,
    // its project named on its row, as any there.
    expect(
      inSidebar(find.textContaining(RegExp(r'^Chat monad0 .*monad$'))),
      findsOneWidget,
    );
    expect(inSidebar(find.text('monad')), findsNothing);
  });

  testWidgets('shown, the archived agents are scrolled to', (tester) async {
    final workspace = await pumpApp(tester);
    // Too short for them all.
    tester.view.physicalSize = const Size(1400, 480);
    final archived = workspace.threads.skip(1).toList();
    for (final thread in archived) {
      workspace.setArchived(thread, true);
    }
    await tester.pump();
    await tester.tap(inSidebar(find.text('Archived · ${archived.length}')));
    await tester.pumpAndSettle();
    final list = tester.state<ScrollableState>(
      inSidebar(find.byType(Scrollable)).last,
    );
    expect(list.position.maxScrollExtent, greaterThan(0));
    expect(list.position.pixels, list.position.maxScrollExtent);
  });

  testWidgets('shown from the top of a long list, the archived agents are '
      'scrolled to', (tester) async {
    // Far more than shows: the archived rows are not built until scrolled to.
    final records = [
      for (var p = 0; p < 12; p++)
        for (var i = 0; i < 8; i++)
          kept('p${p}t$i', '/proj$p', 60 * (p * 8 + i + 1)),
    ];
    final store = MemoryPreferenceStore({
      'sidebar': {
        'archived': [for (var i = 0; i < 7; i++) records[i * 10].id],
      },
    });
    await pumpKept(tester, KeptCatalog(records), preferences: store);
    await tester.tap(inSidebar(find.text('Archived · 7')));
    await tester.pumpAndSettle();
    final scrollable = inSidebar(find.byType(Scrollable)).last;
    final list = tester.state<ScrollableState>(scrollable);
    expect(list.position.pixels, list.position.maxScrollExtent);
    expect(
      tester
          .getRect(scrollable)
          .contains(tester.getCenter(inSidebar(find.text('Archived')))),
      isTrue,
    );
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
    final titleTop = tester.getTopLeft(row()).dy;
    await hover();
    expect(tester.getTopLeft(row()).dy, titleTop);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(tester.getTopLeft(row()).dy, titleTop);
    await hover();
    expect(inSidebar(find.text('55m')), findsNothing);
    expect(inSidebar(find.byIcon(Icons.push_pin_outlined)), findsOneWidget);
    expect(inSidebar(find.byIcon(Icons.inventory_2_outlined)), findsOneWidget);
    final rowBounds = tester.getRect(
      find.ancestor(of: row(), matching: find.byType(IdeListRow)),
    );
    for (final icon in [Icons.push_pin_outlined, Icons.inventory_2_outlined]) {
      final button = find.ancestor(
        of: inSidebar(find.byIcon(icon)),
        matching: find.byType(SidebarIconButton),
      );
      final bounds = tester.getRect(button);
      expect(bounds.top, greaterThanOrEqualTo(rowBounds.top));
      expect(bounds.bottom, lessThanOrEqualTo(rowBounds.bottom));
    }

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

  testWidgets('with the times turned off in the settings, the rows show none', (
    tester,
  ) async {
    addTearDown(() => SidebarTimes.shown.value = true);
    await pumpApp(tester);
    expect(inSidebar(find.text('55m')), findsOneWidget);

    SidebarTimes.shown.value = false;
    await tester.pump();
    expect(inSidebar(find.text('55m')), findsNothing);

    SidebarTimes.shown.value = true;
    await tester.pump();
    expect(inSidebar(find.text('55m')), findsOneWidget);
  });

  testWidgets('a clipped mixed-language title stays on its baseline when '
      'hover actions appear', (tester) async {
    final workspace = await pumpApp(tester);
    const title = '修复侧边栏 hover 文字跳动 🧪 — a long conversation title';
    workspace.rename(threadNamed(workspace, 'Rate limit per API key'), title);
    final border = Offset(tester.getTopRight(find.byType(Sidebar)).dx + 2, 400);
    await tester.dragFrom(border, const Offset(-100, 0));
    await tester.pumpAndSettle();
    final label = inSidebar(find.text(title));
    double baseline() {
      final paragraph = tester.renderObject<RenderParagraph>(label);
      final glyph = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 1),
          )
          .first;
      return paragraph.localToGlobal(Offset(0, glyph.bottom)).dy;
    }

    final before = baseline();
    final height = tester.getSize(label).height;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    for (var i = 0; i < 3; i++) {
      await mouse.moveTo(tester.getCenter(label));
      await tester.pump();
      expect(
        inSidebar(find.byIcon(Icons.inventory_2_outlined)),
        findsOneWidget,
      );
      expect(baseline(), before);
      expect(tester.getSize(label).height, height);
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(baseline(), before);
    }
  });

  testWidgets('the open chat keeps its selection outline after the list '
      'loses focus', (tester) async {
    await pumpKept(
      tester,
      KeptCatalog([kept('a1', '/tmp/a', 1), kept('a2', '/tmp/a', 2)]),
    );
    final title = inSidebar(find.text('Chat a1'));
    final row = find.ancestor(of: title, matching: find.byType(IdeListRow));
    await tester.tap(title);
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(tester.widget<IdeListRow>(row).focused, isFalse);
    expect(tester.widget<IdeListRow>(row).selected, isTrue);
    final container = tester
        .widgetList<Container>(
          find.descendant(of: row, matching: find.byType(Container)),
        )
        .firstWhere((widget) => widget.decoration != null);
    final outline = container.foregroundDecoration as BoxDecoration?;
    expect(outline?.border, isNotNull);
  });

  testWidgets('the selection follows the agent opened from elsewhere, a new '
      'one too', (tester) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([kept('a1', '/tmp/a', 1), kept('a2', '/tmp/a', 2)]),
    );
    IdeListRow rowOf(Finder title) => tester.widget<IdeListRow>(
      find.ancestor(of: title, matching: find.byType(IdeListRow)),
    );
    final a1 = inSidebar(find.text('Chat a1'));
    final a2 = inSidebar(find.text('Chat a2'));
    await tester.tap(a1);
    await tester.pumpAndSettle();
    expect(rowOf(a1).selected, isTrue);

    workspace.select(keptThread(workspace, 'a2'));
    await tester.pumpAndSettle();
    expect(rowOf(a1).selected, isFalse);
    expect(rowOf(a2).selected, isTrue);

    final created = workspace.create(project: workspace.selected.project);
    await tester.pumpAndSettle();
    expect(workspace.selected, same(created));
    expect(rowOf(a2).selected, isFalse);
    final rows = tester.widgetList<IdeListRow>(
      inSidebar(find.byType(IdeListRow)),
    );
    expect(rows.where((row) => row.selected), hasLength(1));
  });

  testWidgets('selected rows use the explorer colors as focus moves and '
      'Escape clears the highlight', (tester) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([kept('a1', '/tmp/a', 1), kept('a2', '/tmp/a', 2)]),
    );
    workspace.sidebarGrouping = SidebarGrouping.time.name;
    await tester.pump();
    final title = inSidebar(find.textContaining(RegExp(r'^Chat a1\s')));
    final row = find.ancestor(of: title, matching: find.byType(IdeListRow));
    BoxDecoration decoration() =>
        tester
                .widgetList<Container>(
                  find.descendant(of: row, matching: find.byType(Container)),
                )
                .firstWhere((widget) => widget.decoration != null)
                .decoration!
            as BoxDecoration;
    void expectForeground(Color color) {
      final text = tester.widget<Text>(title);
      expect(text.style!.color, color);
      final spans = (text.textSpan! as TextSpan).children!
          .whereType<TextSpan>();
      expect(spans.last.style!.color, color);
    }

    workspace.select(keptThread(workspace, 'a1'));
    await tester.pumpAndSettle();
    // Modifier clicks leave focus in the list.
    await tester.sendKeyDownEvent(multiSelectKey);
    await tester.tap(title);
    await tester.sendKeyUpEvent(multiSelectKey);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(tester.widget<IdeListRow>(row).focused, isTrue);
    expect(decoration().color, IdeListColors.activeSelection);
    expectForeground(IdeListColors.activeSelectionForeground);

    final listFocus = FocusManager.instance.primaryFocus!;
    listFocus.unfocus();
    await tester.pump();
    expect(tester.widget<IdeListRow>(row).focused, isFalse);
    expect(decoration().color, IdeListColors.activeSelection);
    expectForeground(IdeListColors.activeSelectionForeground);
    expect(tester.getSize(row).height, IdeListColors.rowHeight);
    expect(decoration().borderRadius, BorderRadius.circular(4));

    listFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tester.widget<IdeListRow>(row).selected, isFalse);
    expect(decoration().color, isNull);
    expect(
      find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Positioned && widget.left == 0 && widget.width == 2,
        ),
      ),
      findsNothing,
    );
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

  testWidgets('its icon buttons have the workbench hover, with the key that '
      'does the same', (tester) async {
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
        of: find.text('Hide sidebar (Ctrl+B)'),
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

    // The title bar's title at its left, not the conversation's column.
    final title = find.descendant(
      of: find.byType(ChatScreen),
      matching: find.text('Quota'),
    );
    expect(
      tester.getTopLeft(title).dx,
      tester.getTopLeft(find.byType(ChatScreen)).dx + 12,
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

  testWidgets('a click on another agent between two makes no double click', (
    tester,
  ) async {
    final workspace = await pumpApp(tester);
    final first = threadNamed(workspace, 'Rate limit per API key');
    final firstRow = inSidebar(find.textContaining('Rate limit per API key'));
    final other = workspace.threads.firstWhere(
      (thread) =>
          thread != first &&
          !thread.archived &&
          inSidebar(find.text(thread.title)).evaluate().isNotEmpty,
    );

    await tester.tap(firstRow);
    await tester.pump();
    await tester.tap(inSidebar(find.text(other.title)));
    await tester.pump();
    expect(workspace.selected, other);
    // Back at once: it opens, no rename.
    await tester.tap(firstRow);
    await tester.pump();
    expect(workspace.selected, first);
    expect(inSidebar(find.byType(TextField)), findsNothing);
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
    // The Fast Ide, until another is picked.
    expect(find.bySemanticsLabel('Open in Fast Ide'), findsOneWidget);
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
      const MethodChannel('baocode/window'),
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
      lessThan(tester.getTopLeft(find.bySemanticsLabel('Open in Fast Ide')).dx),
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

  testWidgets('collapsed groups stay so across a narrow window', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(inSidebar(find.text('api-gateway')));
    await tester.pump();
    expect(
      inSidebar(find.textContaining('Rate limit per API key')),
      findsNothing,
    );

    // Narrow, with the drawer closed, there is no sidebar; wide again, it
    // is built anew.
    tester.view.physicalSize = const Size(700, 900);
    await tester.pumpAndSettle();
    expect(find.byType(Sidebar), findsNothing);
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    expect(
      inSidebar(find.textContaining('Rate limit per API key')),
      findsNothing,
    );
    expect(inSidebar(find.text('3')), findsOneWidget);
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

  testWidgets('a project shows its five most recent agents, the rest on '
      'asking', (tester) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([for (var i = 1; i <= 7; i++) kept('a$i', '/tmp/a', i)]),
    );
    final group = Workspace.projectGroup('/tmp/a');
    // The new agent and four more; pinned ones would not count.
    expect(inSidebar(find.text('New Chat')), findsNWidgets(2));
    expect(inSidebar(find.text('Chat a4')), findsOneWidget);
    expect(inSidebar(find.text('Chat a5')), findsNothing);
    expect(inSidebar(find.text('Show more (3)')), findsOneWidget);

    await tester.tap(inSidebar(find.text('Show more (3)')));
    await tester.pump();
    expect(inSidebar(find.text('Chat a7')), findsOneWidget);
    expect(workspace.isExpanded(group), isTrue);
    await tester.tap(inSidebar(find.text('Show less')));
    await tester.pump();
    expect(inSidebar(find.text('Chat a7')), findsNothing);
    expect(workspace.isExpanded(group), isFalse);

    // The open one shows wherever it is.
    workspace.select(keptThread(workspace, 'a7'));
    await tester.pump();
    expect(inSidebar(find.text('Chat a7')), findsOneWidget);
    expect(inSidebar(find.text('Chat a6')), findsNothing);
    expect(inSidebar(find.text('Show more (1)')), findsOneWidget);
    // Keys go through the rows shown.
    expect(
      tester
          .widget<Sidebar>(find.byType(Sidebar))
          .link!
          .visibleThreads!
          .map((thread) => thread.record?.id),
      ['a1', 'a2', 'a3', 'a4', 'a5', 'a7'],
    );
  });

  testWidgets('the only project has a plain header that does not fold', (
    tester,
  ) async {
    await pumpKept(tester, KeptCatalog([kept('a1', '/tmp/a', 1)]));
    expect(inSidebar(find.byIcon(Icons.chevron_right_rounded)), findsNothing);
    await tester.tap(inSidebar(find.text('a')));
    await tester.pump();
    expect(inSidebar(find.text('Chat a1')), findsOneWidget);
  });

  testWidgets('a new agent is listed only while it shows', (tester) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([kept('a1', '/tmp/a', 1)]),
    );
    final created = workspace.selected;
    expect(created.untouched, isTrue);
    expect(inSidebar(find.text('New Chat')), findsNWidgets(2));

    await tester.tap(inSidebar(find.text('Chat a1')));
    await tester.pump();
    expect(workspace.threads, contains(created));
    expect(inSidebar(find.text('New Chat')), findsOneWidget);

    // Asked for again, it is the same one.
    await tester.tap(inSidebar(find.text('New Chat')));
    await tester.pump();
    expect(workspace.selected, same(created));
    expect(inSidebar(find.text('New Chat')), findsNWidgets(2));
  });

  testWidgets('a project and an agent show what their rows have no room '
      'for when hovered', (tester) async {
    await pumpKept(
      tester,
      KeptCatalog([kept('a1', '/tmp/a', 1), kept('b1', '/tmp/b', 2)]),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(inSidebar(find.text('b'))));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('/tmp/b'), findsOneWidget);
    // In the window's overlay, not the error style of text with no
    // Material above it.
    expect(
      find.ancestor(of: find.text('/tmp/b'), matching: find.byType(Material)),
      findsOneWidget,
    );

    await mouse.moveTo(tester.getCenter(inSidebar(find.text('Chat b1'))));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Chat b1'), findsNWidgets(2));
    expect(find.text('/tmp/b'), findsOneWidget);
  });

  testWidgets('Collapse All folds every project, Expand All unfolds them '
      '(#300)', (tester) async {
    await pumpKept(
      tester,
      KeptCatalog([kept('a1', '/tmp/a', 1), kept('b1', '/tmp/b', 2)]),
    );
    final collapse = inSidebar(
      find.widgetWithIcon(SidebarIconButton, Codicons.collapseAll),
    );
    expect(collapse, findsOneWidget);
    expect(inSidebar(find.text('Chat a1')), findsOneWidget);

    await tester.tap(collapse);
    await tester.pump();
    expect(inSidebar(find.text('Chat a1')), findsNothing);
    expect(inSidebar(find.text('Chat b1')), findsNothing);

    final expand = inSidebar(
      find.widgetWithIcon(SidebarIconButton, Codicons.expandAll),
    );
    await tester.tap(expand);
    await tester.pump();
    expect(inSidebar(find.text('Chat a1')), findsOneWidget);
    expect(inSidebar(find.text('Chat b1')), findsOneWidget);
  });

  testWidgets('an agent\'s hover says the model it runs on (#245)', (
    tester,
  ) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([kept('a1', '/tmp/a', 1), kept('b1', '/tmp/b', 2)]),
    );
    final thread = workspace.threads.firstWhere((t) => t.title == 'Chat b1');
    final models = thread.session.models!;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(inSidebar(find.text('Chat b1'))));
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.text(
        'Model: ${[?models.selected.group?.label, models.selected.label].join(' · ')}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a project header has a menu of what can be done there', (
    tester,
  ) async {
    final catalog = KeptCatalog([
      kept('a1', '/tmp/a', 1),
      kept('a2', '/tmp/a', 2),
      kept('b1', '/tmp/b', 3),
    ]);
    final workspace = await pumpKept(tester, catalog);
    final launched = <(Editor, String)>[];
    final launch = Sidebar.launch;
    Sidebar.launch = (editor, path) async {
      launched.add((editor, path));
      return true;
    };
    addTearDown(() => Sidebar.launch = launch);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pickFromMenu(tester, 'b', 'New Chat Here');
    expect(workspace.selected.project.path, '/tmp/b');
    expect(workspace.selected.untouched, isTrue);

    await pickFromMenu(tester, 'b', 'Show in Finder');
    expect(launched, [(Editor.folder, '/tmp/b')]);

    workspace.preferredEditor = Editor.vscode;
    await tester.pump();
    await pickFromMenu(tester, 'b', 'Open in VS Code');
    expect(launched.last, (Editor.vscode, '/tmp/b'));

    // The Fast Ide opens the project's folder, not the one it had open.
    workspace
      ..preferredEditor = Editor.fastIde
      ..openIdeFolder('/tmp/a')
      ..select(keptThread(workspace, 'a1'));
    await tester.pump();
    await pickFromMenu(tester, 'b', 'Open in Fast Ide');
    expect(workspace.layout, WorkspaceLayout.ide);
    expect(workspace.ideFolder, '/tmp/b');
    workspace.layout = WorkspaceLayout.chat;
    await tester.pump();
    // With the current agent's chat there, when it is the project's.
    workspace.select(keptThread(workspace, 'a1'));
    await tester.pump();
    await pickFromMenu(tester, 'a', 'Open in Fast Ide');
    expect(workspace.ideFolder, '/tmp/a');
    expect(workspace.ideChat('/tmp/a'), same(keptThread(workspace, 'a1')));
    workspace.layout = WorkspaceLayout.chat;
    await tester.pump();

    await pickFromMenu(tester, 'a', 'Copy path');
    expect(copied, ['/tmp/a']);

    // Ordered by time already: nothing to go back to.
    await tester.tap(inSidebar(find.text('a')), buttons: kSecondaryButton);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sort by Time'), findsNothing);
    await tester.tap(find.text('Archive All'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(keptThread(workspace, 'a1').archived, isTrue);
    expect(keptThread(workspace, 'a2').archived, isTrue);
    expect(inSidebar(find.text('Chat a1')), findsNothing);

    // Off the list until it is opened again...
    await pickFromMenu(tester, 'b', 'Remove from List');
    expect(inSidebar(find.text('b')), findsNothing);
    expect(inSidebar(find.text('Chat b1')), findsNothing);
    await tester.runAsync(() => workspace.openFolder('/tmp/b'));
    await tester.pump();
    expect(inSidebar(find.text('b')), findsOneWidget);
    expect(inSidebar(find.text('Chat b1')), findsOneWidget);

    // ...or a session there is new.
    await pickFromMenu(tester, 'b', 'Remove from List');
    workspace.select(keptThread(workspace, 'a1'));
    await tester.runAsync(workspace.refresh);
    await tester.pump();
    expect(inSidebar(find.text('Chat b1')), findsNothing);
    catalog.records.add(
      SessionRecord(
        id: 'b2',
        title: 'Chat b2',
        updatedAt: DateTime.now().add(const Duration(minutes: 1)),
        cwd: '/tmp/b',
      ),
    );
    await tester.runAsync(workspace.refresh);
    await tester.pump();
    expect(inSidebar(find.text('Chat b2')), findsOneWidget);
    expect(workspace.isHidden(workspace.selected.project), isFalse);
  });

  testWidgets('pinned projects stay on top, dragged among themselves; kept '
      'between runs', (tester) async {
    final store = MemoryPreferenceStore();
    final catalog = KeptCatalog([
      kept('a1', '/tmp/a', 1),
      kept('b1', '/tmp/b', 2),
      kept('c1', '/tmp/c', 3),
    ]);
    var workspace = await pumpKept(tester, catalog, preferences: store);
    List<String> order() => [
      for (final project in workspace.sidebarProjectsHere) project.name,
    ];
    // The headers' pins, not the menu's.
    final pin = inSidebar(
      find.byWidgetPredicate(
        (widget) =>
            widget is Icon &&
            widget.icon == Icons.push_pin &&
            widget.size == 11,
      ),
    );
    expect(pin, findsNothing);

    await pickFromMenu(tester, 'a', 'Pin');
    expect(order().first, 'a');
    expect(top(tester, 'a'), lessThan(top(tester, 'b')));
    expect(top(tester, 'a'), lessThan(top(tester, 'c')));
    expect(pin, findsOneWidget);

    // Not above the pinned one, nor it below the others.
    await mouseDrag(
      tester,
      tester.getCenter(inSidebar(find.text('c'))),
      () => tester.getTopLeft(inSidebar(find.text('a'))) + const Offset(20, 2),
    );
    expect(order().first, 'a');
    await mouseDrag(
      tester,
      tester.getCenter(inSidebar(find.text('a'))),
      () => tester.getCenter(inSidebar(find.text('Chat c1'))),
    );
    expect(order().first, 'a');

    // The last pinned on top of those pinned.
    await pickFromMenu(tester, 'b', 'Pin');
    expect(order().take(2), ['b', 'a']);
    expect(pin, findsNWidgets(2));

    // The next run.
    await tester.pumpWidget(const SizedBox());
    workspace = await pumpKept(tester, catalog, preferences: store);
    expect(order(), ['b', 'a', 'c']);

    await pickFromMenu(tester, 'b', 'Unpin');
    expect(order(), ['a', 'b', 'c']);
    expect(pin, findsOneWidget);
  });

  testWidgets('agents and projects keep the order they are dragged to', (
    tester,
  ) async {
    final store = MemoryPreferenceStore();
    final catalog = KeptCatalog([
      kept('a1', '/tmp/a', 1),
      kept('a2', '/tmp/a', 2),
      kept('a3', '/tmp/a', 3),
      kept('b1', '/tmp/b', 4),
    ]);
    var workspace = await pumpKept(tester, catalog, preferences: store);
    workspace.select(keptThread(workspace, 'a1'));
    await tester.pump();
    Project project(String path) =>
        workspace.projects.firstWhere((project) => project.path == path);

    // Above a1.
    await mouseDrag(
      tester,
      tester.getCenter(inSidebar(find.text('Chat a3'))),
      () =>
          tester.getTopLeft(inSidebar(find.text('Chat a1'))) +
          const Offset(20, 0),
    );
    expect(top(tester, 'Chat a3'), lessThan(top(tester, 'Chat a1')));
    expect(workspace.isManuallyOrdered(project('/tmp/a')), isTrue);
    // A drag no longer shows beside the conversations.
    expect(workspace.grid.length, 1);

    // Onto the place to pin it, there while it is dragged.
    final from = tester.getCenter(inSidebar(find.text('Chat a2')));
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    expect(inSidebar(find.text('Drop here to pin')), findsOneWidget);
    await gesture.moveTo(
      tester.getCenter(inSidebar(find.text('Drop here to pin'))),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(keptThread(workspace, 'a2').pinned, isTrue);
    expect(inSidebar(find.text('Drop here to pin')), findsNothing);

    // Project b above a.
    await mouseDrag(
      tester,
      tester.getCenter(inSidebar(find.text('b'))),
      () => tester.getTopLeft(inSidebar(find.text('a'))) + const Offset(20, 2),
    );
    expect(top(tester, 'b'), lessThan(top(tester, 'a')));

    // The next run.
    await tester.pumpWidget(const SizedBox());
    workspace = await pumpKept(tester, catalog, preferences: store);
    workspace.select(keptThread(workspace, 'a1'));
    await tester.pump();
    expect(top(tester, 'Chat a3'), lessThan(top(tester, 'Chat a1')));
    expect(top(tester, 'b'), lessThan(top(tester, 'a')));
    expect(keptThread(workspace, 'a2').pinned, isTrue);
    // The pinned row names its project too.
    expect(
      tester.getTopLeft(inSidebar(find.textContaining('Chat a2'))).dy,
      lessThan(top(tester, 'b')),
    );

    // By time again.
    await pickFromMenu(tester, 'a', 'Sort by Time');
    expect(top(tester, 'Chat a1'), lessThan(top(tester, 'Chat a3')));
    expect(workspace.isManuallyOrdered(project('/tmp/a')), isFalse);
  });

  testWidgets('the pinned agents keep the order they are dragged to', (
    tester,
  ) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([kept('a1', '/tmp/a', 1), kept('a2', '/tmp/a', 2)]),
    );
    final [a1, a2] = [keptThread(workspace, 'a1'), keptThread(workspace, 'a2')];
    workspace
      ..setPinned(a2, true)
      ..setPinned(a1, true);
    await tester.pump();
    // Their rows name the project too (`Chat a1  a`).
    Finder row(String title) => inSidebar(find.textContaining(title));
    double rowTop(String title) => tester.getTopLeft(row(title)).dy;
    // The last pinned on top.
    expect(rowTop('Chat a1'), lessThan(rowTop('Chat a2')));

    await mouseDrag(
      tester,
      tester.getCenter(row('Chat a2')),
      () => tester.getTopLeft(row('Chat a1')) + const Offset(20, 2),
    );
    expect(rowTop('Chat a2'), lessThan(rowTop('Chat a1')));
    expect(workspace.inPinnedOrder([a1, a2]), [a2, a1]);
  });

  testWidgets(
    'leaving the window during a chat drag removes its cursor layer',
    (tester) async {
      final workspace = await pumpKept(
        tester,
        KeptCatalog([kept('a1', '/tmp/a', 1), kept('a2', '/tmp/a', 2)]),
      );
      final drag = tester
          .widget<ChatDragLayer>(find.byType(ChatDragLayer))
          .drag;
      final gesture = await tester.startGesture(
        tester.getCenter(inSidebar(find.text('Chat a2'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump();
      expect(drag.thread, keptThread(workspace, 'a2'));
      Finder grabbingCursor() => find.descendant(
        of: find.byType(ChatDragLayer),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is MouseRegion &&
              widget.cursor == SystemMouseCursors.grabbing,
        ),
      );
      expect(grabbingCursor(), findsOneWidget);

      await gesture.removePointer();
      await tester.pump();
      expect(drag.thread, isNull);
      expect(drag.drop, isNull);
      expect(workspace.grid.length, 1);
      expect(grabbingCursor(), findsNothing);
    },
  );

  testWidgets('losing window focus cancels a chat drag', (tester) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([kept('a1', '/tmp/a', 1), kept('a2', '/tmp/a', 2)]),
    );
    final drag = tester.widget<ChatDragLayer>(find.byType(ChatDragLayer)).drag;
    final gesture = await tester.startGesture(
      tester.getCenter(inSidebar(find.text('Chat a2'))),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    expect(drag.thread, keptThread(workspace, 'a2'));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(drag.thread, isNull);
    expect(workspace.grid.length, 1);
    await gesture.up();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('a fresh press releases a drag whose original pointer was lost', (
    tester,
  ) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([kept('a1', '/tmp/a', 1), kept('a2', '/tmp/a', 2)]),
    );
    final a1 = keptThread(workspace, 'a1');
    final a2 = keptThread(workspace, 'a2');
    workspace.select(a1);
    await tester.pump();
    final drag = tester.widget<ChatDragLayer>(find.byType(ChatDragLayer)).drag;
    final original = await tester.startGesture(
      tester.getCenter(inSidebar(find.text('Chat a2'))),
      kind: PointerDeviceKind.mouse,
    );
    await original.moveBy(const Offset(0, -10));
    await tester.pump();
    expect(drag.thread, a2);
    // The original pointer never sends up, cancel or removed. Its topmost
    // cursor layer currently intercepts the entire window.
    final next = await tester.startGesture(
      tester.getCenter(inSidebar(find.text('Chat a2'))),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(drag.thread, isNull);
    expect(drag.drop, isNull);
    await next.up();
    await tester.pump();
    expect(workspace.selected, a1);
    await original.up();
    await tester.tap(inSidebar(find.text('Chat a2')));
    await tester.pump();
    expect(workspace.selected, a2);
  });

  testWidgets('a long sidebar builds only rows near its scroll position', (
    tester,
  ) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([
        for (var i = 0; i < 1200; i++) kept('t$i', '/tmp/a', i + 1),
      ]),
    );
    workspace.sidebarGrouping = SidebarGrouping.time.name;
    await tester.pump();
    expect(
      inSidebar(find.byType(ChatDragSource)).evaluate().length,
      lessThan(90),
    );
    expect(
      inSidebar(find.textContaining(RegExp(r'^Chat t0\s'))),
      findsOneWidget,
    );
    expect(
      inSidebar(find.textContaining(RegExp(r'^Chat t1199\s'))),
      findsNothing,
    );

    final list = tester.state<ScrollableState>(
      inSidebar(find.byType(Scrollable)).last,
    );
    for (var i = 0; i < 4; i++) {
      list.position.jumpTo(list.position.maxScrollExtent);
      await tester.pump();
    }
    expect(
      inSidebar(find.textContaining(RegExp(r'^Chat t1199\s'))),
      findsOneWidget,
    );
    expect(
      inSidebar(find.byType(ChatDragSource)).evaluate().length,
      lessThan(90),
    );
  });

  testWidgets('the list wheel scrolls and keyboard navigation reveals virtual '
      'rows without opening them', (tester) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([for (var i = 0; i < 120; i++) kept('t$i', '/tmp/a', i + 1)]),
    );
    workspace.sidebarGrouping = SidebarGrouping.time.name;
    await tester.pump();
    final first = inSidebar(find.textContaining(RegExp(r'^Chat t0\s')));
    await tester.sendKeyDownEvent(multiSelectKey);
    await tester.tap(first);
    await tester.sendKeyUpEvent(multiSelectKey);
    await tester.pump();
    final open = workspace.selected;
    final scrollable = inSidebar(find.byType(Scrollable)).last;
    final list = tester.state<ScrollableState>(scrollable);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(first),
        scrollDelta: const Offset(0, 300),
      ),
    );
    await tester.pumpAndSettle();
    expect(list.position.pixels, greaterThan(0));

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    final last = inSidebar(find.textContaining(RegExp(r'^Chat t119\s')));
    expect(last, findsOneWidget);
    expect(tester.getRect(scrollable).contains(tester.getCenter(last)), isTrue);
    expect(workspace.selected, same(open));

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(
      tester.getRect(scrollable).contains(tester.getCenter(first)),
      isTrue,
    );
    final atFirst = list.position.pixels;
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(list.position.pixels, greaterThan(atFirst));
    expect(workspace.selected, same(open));
  });

  for (final overHeader in [false, true]) {
    testWidgets(
      'trackpad pans over ${overHeader ? 'project headers' : 'chat rows'} '
      'scroll without starting a reorder',
      (tester) async {
        final workspace = await pumpKept(
          tester,
          KeptCatalog([
            for (var p = 0; p < 16; p++)
              for (var i = 0; i < 5; i++)
                kept('p${p}t$i', '/proj$p', p * 5 + i + 1),
          ]),
        );
        final scrollable = inSidebar(find.byType(Scrollable)).last;
        final position = tester.state<ScrollableState>(scrollable).position;
        final drag = tester
            .widget<ChatDragLayer>(find.byType(ChatDragLayer))
            .drag;
        final order = workspace.sidebarProjectsHere.toList();
        final open = workspace.selected;
        for (var attempt = 0; attempt < 3; attempt++) {
          position.jumpTo(0);
          await tester.pump();
          final target = inSidebar(
            find.text(overHeader ? 'proj1' : 'Chat p1t0'),
          );
          final at = tester.getCenter(target);
          final pointer = TestPointer(20 + attempt, PointerDeviceKind.trackpad);
          await tester.sendEventToBinding(pointer.panZoomStart(at));
          for (var i = 1; i <= 8; i++) {
            await tester.sendEventToBinding(
              pointer.panZoomUpdate(
                at,
                pan: Offset(0, -20.0 * i),
                timeStamp: Duration(milliseconds: i * 16),
              ),
            );
            await tester.pump(const Duration(milliseconds: 16));
            expect(drag.thread, isNull);
          }
          await tester.sendEventToBinding(
            pointer.panZoomEnd(timeStamp: const Duration(milliseconds: 144)),
          );
          await tester.pumpAndSettle();
          expect(position.pixels, greaterThan(50));
          expect(workspace.sidebarProjectsHere, orderedEquals(order));
          expect(workspace.selected, same(open));
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets('the sidebar honors custom list navigation keys', (tester) async {
    final previous = KeybindingService.instance;
    KeybindingService.instance = KeybindingService()
      ..userEntries = const [
        KeybindingEntry(
          command: 'list.focusDown',
          key: 'j',
          when: 'listFocus && !inputFocus',
        ),
      ];
    addTearDown(() => KeybindingService.instance = previous);
    final workspace = await pumpKept(
      tester,
      KeptCatalog([kept('a1', '/tmp/a', 1), kept('a2', '/tmp/a', 2)]),
    );
    await clickChat(tester, 'Chat a1', holding: multiSelectKey);
    final open = workspace.selected;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    final next = find.ancestor(
      of: inSidebar(find.text('Chat a2')),
      matching: find.byType(IdeListRow),
    );
    expect(tester.widget<IdeListRow>(next).focusedItem, isTrue);
    expect(workspace.selected, same(open));
  });

  testWidgets('dragging near the list edge scrolls and stops on release', (
    tester,
  ) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([for (var i = 0; i < 120; i++) kept('t$i', '/tmp/a', i + 1)]),
    );
    workspace.sidebarGrouping = SidebarGrouping.time.name;
    await tester.pump();
    final scrollable = inSidebar(find.byType(Scrollable)).last;
    final list = tester.state<ScrollableState>(scrollable);
    final first = inSidebar(find.textContaining(RegExp(r'^Chat t0\s')));
    final gesture = await tester.startGesture(
      tester.getCenter(first),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 8));
    await tester.pump();
    await gesture.moveTo(
      tester.getRect(scrollable).bottomCenter - const Offset(25, 5),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(list.position.pixels, greaterThan(0));
    await gesture.up();
    await tester.pump();
    final stopped = list.position.pixels;
    await tester.pump(const Duration(milliseconds: 100));
    expect(list.position.pixels, stopped);
  });

  testWidgets(
    'modifier clicks select without opening and drag a block in row order',
    (tester) async {
      final workspace = await pumpKept(
        tester,
        KeptCatalog([for (var i = 1; i <= 4; i++) kept('a$i', '/tmp/a', i)]),
      );
      final a1 = keptThread(workspace, 'a1');
      final a2 = keptThread(workspace, 'a2');
      final a3 = keptThread(workspace, 'a3');
      final a4 = keptThread(workspace, 'a4');
      await clickChat(tester, 'Chat a2');
      await clickChat(tester, 'Chat a4', holding: multiSelectKey);
      expect(workspace.selected, a2);

      final drag = tester
          .widget<ChatDragLayer>(find.byType(ChatDragLayer))
          .drag;
      final gesture = await tester.startGesture(
        tester.getCenter(inSidebar(find.text('Chat a4'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, -8));
      await tester.pump();
      expect(drag.threads, [a2, a4]);
      await gesture.moveTo(
        tester.getTopLeft(inSidebar(find.text('Chat a1'))) +
            const Offset(20, 2),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(workspace.inProjectOrder(a1.project, [a1, a2, a3, a4]), [
        a2,
        a4,
        a1,
        a3,
      ]);
      expect(workspace.grid.length, 1);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets('a batch drag cannot open only its first chat in the grid', (
    tester,
  ) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([
        kept('a1', '/tmp/a', 1),
        kept('a2', '/tmp/a', 2),
        kept('a3', '/tmp/a', 3),
      ]),
    );
    await clickChat(tester, 'Chat a2');
    await clickChat(tester, 'Chat a3', holding: multiSelectKey);
    final drag = tester.widget<ChatDragLayer>(find.byType(ChatDragLayer)).drag;
    final gesture = await tester.startGesture(
      tester.getCenter(inSidebar(find.text('Chat a3'))),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, -8));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(ChatGridView)));
    await tester.pump();
    expect(drag.drop, isNull);
    await gesture.up();
    await tester.pump();
    expect(workspace.grid.length, 1);
  });

  testWidgets(
    'Shift clicks and arrows extend selection without opening chats',
    (tester) async {
      final workspace = await pumpKept(
        tester,
        KeptCatalog([for (var i = 1; i <= 4; i++) kept('a$i', '/tmp/a', i)]),
      );
      await clickChat(tester, 'Chat a1');
      await clickChat(tester, 'Chat a3', holding: LogicalKeyboardKey.shiftLeft);
      expect(workspace.selected, keptThread(workspace, 'a1'));
      final drag = tester
          .widget<ChatDragLayer>(find.byType(ChatDragLayer))
          .drag;
      final arrow = await tester.startGesture(
        tester.getCenter(inSidebar(find.text('Chat a2'))),
        kind: PointerDeviceKind.mouse,
      );
      await arrow.moveBy(const Offset(0, -8));
      await tester.pump();
      expect(drag.threads.map((thread) => thread.id), ['a1', 'a2', 'a3']);
      await arrow.up();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      final extended = await tester.startGesture(
        tester.getCenter(inSidebar(find.text('Chat a4'))),
        kind: PointerDeviceKind.mouse,
      );
      await extended.moveBy(const Offset(0, -8));
      await tester.pump();
      expect(drag.threads.map((thread) => thread.id), ['a1', 'a2', 'a3', 'a4']);
      await extended.up();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      final cleared = await tester.startGesture(
        tester.getCenter(inSidebar(find.text('Chat a4'))),
        kind: PointerDeviceKind.mouse,
      );
      await cleared.moveBy(const Offset(0, -8));
      await tester.pump();
      expect(drag.threads.map((thread) => thread.id), ['a4']);
      await cleared.up();
    },
  );

  testWidgets('select all is scoped to the focused sidebar and shown rows', (
    tester,
  ) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([for (var i = 1; i <= 8; i++) kept('a$i', '/tmp/a', i)]),
    );
    await clickChat(tester, 'Chat a1');
    // Modifier selection keeps focus in the list; plain opening focuses chat.
    await clickChat(tester, 'Chat a2', holding: multiSelectKey);
    await tester.sendKeyDownEvent(multiSelectKey);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(multiSelectKey);
    await tester.pump();
    final shown = tester
        .widget<Sidebar>(find.byType(Sidebar))
        .link!
        .visibleThreads!;
    final drag = tester.widget<ChatDragLayer>(find.byType(ChatDragLayer)).drag;
    final gesture = await tester.startGesture(
      tester.getCenter(inSidebar(find.text('Chat a2'))),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, -8));
    await tester.pump();
    expect(drag.threads, shown);
    expect(drag.threads, isNot(contains(keptThread(workspace, 'a8'))));
    await gesture.up();
    expect(workspace.selected, keptThread(workspace, 'a1'));
  });

  testWidgets('a pinned batch returns to its project in the same order', (
    tester,
  ) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([for (var i = 1; i <= 4; i++) kept('a$i', '/tmp/a', i)]),
    );
    await clickChat(tester, 'Chat a2');
    await clickChat(tester, 'Chat a3', holding: multiSelectKey);
    await tester.tap(
      inSidebar(find.text('Chat a3')),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await tester.tap(find.text('Pin 2 Agents'));
    await tester.pump();
    final pinned = workspace.inPinnedOrder([
      keptThread(workspace, 'a2'),
      keptThread(workspace, 'a3'),
    ]);
    await mouseDrag(
      tester,
      tester.getCenter(inSidebar(find.textContaining('Chat a2'))),
      () =>
          tester.getTopLeft(inSidebar(find.text('Chat a1'))) +
          const Offset(20, 2),
    );
    expect(pinned.every((thread) => !thread.pinned), isTrue);
    expect(
      workspace.inProjectOrder(pinned.first.project, [
        for (var i = 1; i <= 4; i++) keptThread(workspace, 'a$i'),
      ]),
      [...pinned, keptThread(workspace, 'a1'), keptThread(workspace, 'a4')],
    );
  });

  testWidgets('scrolled rows use data coordinates for a batch reorder', (
    tester,
  ) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([for (var i = 0; i < 160; i++) kept('t$i', '/tmp/a', i + 1)]),
    );
    workspace.toggleExpanded(Workspace.projectGroup('/tmp/a'));
    await tester.pump();
    final list = tester.state<ScrollableState>(
      inSidebar(find.byType(Scrollable)).last,
    );
    list.position.jumpTo(IdeListColors.rowHeight * 90);
    await tester.pump();
    await clickChat(tester, 'Chat t100');
    await clickChat(tester, 'Chat t101', holding: multiSelectKey);
    await mouseDrag(
      tester,
      tester.getCenter(inSidebar(find.text('Chat t100'))),
      () =>
          tester.getTopLeft(inSidebar(find.text('Chat t95'))) +
          const Offset(20, 2),
    );
    final project = keptThread(workspace, 't0').project;
    final ordered = workspace.inProjectOrder(project, [
      for (var i = 0; i < 160; i++) keptThread(workspace, 't$i'),
    ]);
    expect(
      ordered.indexOf(keptThread(workspace, 't101')),
      ordered.indexOf(keptThread(workspace, 't100')) + 1,
    );
    expect(
      ordered.indexOf(keptThread(workspace, 't95')),
      ordered.indexOf(keptThread(workspace, 't101')) + 1,
    );
  });

  testWidgets('a selected context menu pins and archives the whole selection', (
    tester,
  ) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([
        kept('a1', '/tmp/a', 1),
        kept('a2', '/tmp/a', 2),
        kept('a3', '/tmp/a', 3),
      ]),
    );
    await clickChat(tester, 'Chat a2');
    await clickChat(tester, 'Chat a3', holding: multiSelectKey);
    await tester.tap(
      inSidebar(find.text('Chat a3')),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await tester.tap(find.text('Pin 2 Agents'));
    await tester.pump();
    expect(keptThread(workspace, 'a2').pinned, isTrue);
    expect(keptThread(workspace, 'a3').pinned, isTrue);

    await tester.tap(
      inSidebar(find.textContaining('Chat a3')),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await tester.tap(find.text('Archive 2 Agents'));
    await tester.pump();
    expect(keptThread(workspace, 'a2').archived, isTrue);
    expect(keptThread(workspace, 'a3').archived, isTrue);
  });

  testWidgets('the context menu can unpin and restore a selected batch', (
    tester,
  ) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([
        kept('a1', '/tmp/a', 1),
        kept('a2', '/tmp/a', 2),
        kept('a3', '/tmp/a', 3),
      ]),
    );
    await clickChat(tester, 'Chat a2');
    await clickChat(tester, 'Chat a3', holding: multiSelectKey);
    await tester.tap(
      inSidebar(find.text('Chat a3')),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    // Only what is done to them all, saying how many.
    expect(find.text('Rename'), findsNothing);
    expect(find.text('Fork'), findsNothing);
    await tester.tap(find.text('Pin 2 Agents'));
    await tester.pump();
    await tester.tap(
      inSidebar(find.textContaining('Chat a3')),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await tester.tap(find.text('Unpin 2 Agents'));
    await tester.pump();
    expect(keptThread(workspace, 'a2').pinned, isFalse);
    expect(keptThread(workspace, 'a3').pinned, isFalse);

    await tester.tap(
      inSidebar(find.text('Chat a3')),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await tester.tap(find.text('Archive 2 Agents'));
    await tester.pump();
    await tester.tap(inSidebar(find.text('Archived · 2')));
    await tester.pumpAndSettle();
    await tester.tap(inSidebar(find.textContaining('Chat a2')));
    await tester.pump();
    await tester.sendKeyDownEvent(multiSelectKey);
    await tester.tap(inSidebar(find.textContaining('Chat a3')));
    await tester.sendKeyUpEvent(multiSelectKey);
    await tester.pump();
    await tester.tap(
      inSidebar(find.textContaining('Chat a3')),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    expect(keptThread(workspace, 'a2').archived, isTrue);
    expect(keptThread(workspace, 'a3').archived, isTrue);
    expect(find.text('Unarchive 2 Agents'), findsOneWidget);
    await tester.tap(find.text('Unarchive 2 Agents'));
    await tester.pump();
    expect(keptThread(workspace, 'a2').archived, isFalse);
    expect(keptThread(workspace, 'a3').archived, isFalse);
  });

  testWidgets(
    'a mixed-project batch can pin but cannot move into one project',
    (tester) async {
      final workspace = await pumpKept(
        tester,
        KeptCatalog([
          kept('a1', '/tmp/a', 1),
          kept('a2', '/tmp/a', 2),
          kept('b1', '/tmp/b', 3),
        ]),
      );
      await clickChat(tester, 'Chat a1');
      await clickChat(tester, 'Chat b1', holding: multiSelectKey);
      final gesture = await tester.startGesture(
        tester.getCenter(inSidebar(find.text('Chat b1'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, -8));
      await tester.pump();
      await gesture.moveTo(
        tester.getCenter(inSidebar(find.text('Drop here to pin'))),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(keptThread(workspace, 'a1').pinned, isTrue);
      expect(keptThread(workspace, 'b1').pinned, isTrue);

      await mouseDrag(
        tester,
        tester.getCenter(inSidebar(find.textContaining('Chat b1'))),
        () =>
            tester.getTopLeft(inSidebar(find.text('Chat a2'))) +
            const Offset(20, 2),
      );
      expect(keptThread(workspace, 'a1').pinned, isTrue);
      expect(keptThread(workspace, 'b1').pinned, isTrue);
      expect(
        workspace.isManuallyOrdered(keptThread(workspace, 'a2').project),
        isFalse,
      );
    },
  );

  testWidgets(
    'a batch deletion confirms once and removes only selected chats',
    (tester) async {
      final workspace = await pumpKept(
        tester,
        KeptCatalog([
          kept('a1', '/tmp/a', 1),
          kept('a2', '/tmp/a', 2),
          kept('a3', '/tmp/a', 3),
        ]),
      );
      await clickChat(tester, 'Chat a2');
      await clickChat(tester, 'Chat a3', holding: multiSelectKey);
      await tester.tap(
        inSidebar(find.text('Chat a3')),
        buttons: kSecondaryButton,
      );
      await tester.pump();
      await tester.tap(find.text('Delete 2 Agents…'));
      await tester.pump();
      expect(find.text('Delete agents?'), findsOneWidget);
      expect(
        find.textContaining('2 agents and their conversations'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(GestureDetector, 'Delete').last);
      await tester.pump();
      expect(
        workspace.threads.map((thread) => thread.record?.id),
        contains('a1'),
      );
      expect(
        workspace.threads.map((thread) => thread.record?.id),
        isNot(contains('a2')),
      );
      expect(
        workspace.threads.map((thread) => thread.record?.id),
        isNot(contains('a3')),
      );
    },
  );
}
