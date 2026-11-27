import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/ide/ide_chat_title.dart';
import 'package:baocode/ide/ide_welcome.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/main.dart';
import 'package:baocode/search/search_palette.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/window/app_windows.dart';
import 'package:baocode/window/window_settings.dart';
import 'package:baocode/workbench.dart';
import 'package:baocode/workspace/open_in_editor_button.dart';
import 'package:baocode/workspace/workspace.dart';

import '../kernel_test.dart' show FakeCli;
import 'fake_window_host.dart';

/// The app with windows of its own, each a view of the test's engine: the
/// chat's (the test's view) and those the IDE opens.
Future<(AppWindows, FakeWindowHost, Workspace)> _pumpApp(
  WidgetTester tester, {
  WindowSettings Function()? settings,
  Workspace? workspace,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final messenger = tester.binding.defaultBinaryMessenger;
  for (final name in [
    'baocode/window',
    for (var id = 1; id < 6; id++) 'baocode/window.$id',
  ]) {
    messenger.setMockMethodCallHandler(
      MethodChannel(name),
      (call) async => null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(MethodChannel(name), null),
    );
  }
  final host = FakeWindowHost(tester.view);
  final resolved = workspace ?? Workspace.mock();
  final windows = AppWindows(
    host: host,
    workspace: resolved,
    l10n: () => englishLocalizations,
    settings:
        settings ?? () => const WindowSettings(ideWindows: IdeWindows.separate),
    isDirectory: (path) async => true,
    nextFrame: () => tester.binding.endOfFrame,
  );
  await windows.start();
  await tester.pumpWidget(
    BaoCodeApp(workspace: resolved, windows: windows),
    wrapWithView: false,
  );
  await tester.pump();
  return (windows, host, resolved);
}

/// Opens [folder]'s window, the frames it takes drawn.
Future<AppWindow> _open(
  WidgetTester tester,
  AppWindows windows,
  String folder, {
  AgentThread? thread,
}) async {
  final opening = windows.showFolder(folder, thread: thread);
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  return (await opening)!;
}

Finder _inView(int viewId, Finder finder) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is View && widget.view.viewId == viewId,
  ),
  matching: finder,
);

/// The desktop semantics check (test/semantics_tree.dart) keeps one tree
/// for all views; the windows' own (their accessibility) are left out.
void _testWindows(String description, WidgetTesterCallback callback) =>
    testWidgets(description, callback, semanticsEnabled: false);

void main() {
  _testWindows('an IDE window is a view of its own: its workbench the IDE, '
      'the chat\'s window without it', (tester) async {
    final (windows, host, workspace) = await _pumpApp(tester);
    expect(find.byType(Workbench), findsOneWidget);
    expect(find.byType(IdeWorkbench), findsNothing);

    final window = await _open(tester, windows, '~/code/baocode');
    expect(find.byType(Workbench), findsNWidgets(2));
    expect(_inView(window.viewId, find.byType(IdeWorkbench)), findsOneWidget);
    expect(_inView(0, find.byType(IdeWorkbench)), findsNothing);
    expect(window.delegate, isNotNull);
    expect(window.delegate!.ideSpace, isNotNull);
    expect(host.titles[window.viewId], 'baocode — BaoCode');

    // Asking the IDE in the chat's window goes to the IDE's.
    workspace.layout = WorkspaceLayout.ide;
    await tester.pump();
    await tester.pump();
    expect(_inView(0, find.byType(IdeWorkbench)), findsNothing);
    expect(host.created, hasLength(1));
  });

  _testWindows('the same agent in both windows is the same, its tab the '
      'IDE\'s chat', (tester) async {
    final (windows, _, workspace) = await _pumpApp(tester);
    final thread = workspace.threads.first;
    final window = await _open(
      tester,
      windows,
      thread.project.path,
      thread: thread,
    );
    workspace.openInIde(thread);
    await tester.pump();
    await tester.pump();
    final title = tester.widget<IdeChatTitle>(
      _inView(window.viewId, find.byType(IdeChatTitle)),
    );
    expect(title.tabs, contains(same(thread)));
    expect(title.current, same(thread));
  });

  _testWindows('an agent\'s window (Open with BaoCode): its agent\'s '
      'conversation, a view of its own; closed, it goes', (tester) async {
    final (windows, host, workspace) = await _pumpApp(tester);
    final opening = windows.openAgent(['~/code/baocode']);
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    final thread = (await opening)!;
    final window = windows.agentWindows.single;
    expect(find.byType(Workbench), findsNWidgets(2));
    final chat = _inView(window.viewId, find.byType(ChatScreen));
    expect(chat, findsOneWidget);
    expect(tester.widget<ChatScreen>(chat).session, same(thread.session));
    // Wide, its sidebar is docked, as the chat's window's.
    expect(_inView(window.viewId, find.byType(Sidebar)), findsOneWidget);
    expect(_inView(window.viewId, find.byType(IdeWorkbench)), findsNothing);
    // The chat's window keeps its own.
    expect(_inView(0, find.byType(Sidebar)), findsOneWidget);
    expect(workspace.current, isNot(same(thread)));

    final closing = windows.requestClose(window);
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(await closing, isTrue);
    expect(find.byType(Workbench), findsOneWidget);
    expect(host.views, isEmpty);
    expect(workspace.threads, isNot(contains(thread)));
  });

  testWidgets(
    'an agent\'s window has the sidebar, as the chat\'s: '
    'its toggle slides it out while narrow; an agent picked there shows in '
    'the window in place of its own',
    (tester) async {
      final (windows, host, workspace) = await _pumpApp(tester);
      final opening = windows.openAgent(['~/code/baocode']);
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      final thread = (await opening)!;
      final window = windows.agentWindows.single;
      host.views[window.viewId]!.physicalSize = const Size(520, 760);
      await tester.pump();
      await tester.pump();
      final sidebar = _inView(window.viewId, find.byType(Sidebar));
      expect(sidebar, findsNothing);

      final current = workspace.current;
      await tester.tap(
        _inView(
          window.viewId,
          find.widgetWithIcon(SidebarIconButton, Codicons.layoutSidebarLeftOff),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(sidebar, findsOneWidget);
      expect(tester.widget<Sidebar>(sidebar).current, same(thread));

      final other = workspace.threads.firstWhere(
        (t) => !identical(t, thread) && !t.untouched,
      );
      await tester.tap(
        find.descendant(of: sidebar, matching: find.text(other.title)).first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(window.thread, same(other));
      expect(
        tester
            .widget<ChatScreen>(_inView(window.viewId, find.byType(ChatScreen)))
            .session,
        same(other.session),
      );
      expect(host.titles[window.viewId], contains(other.title));
      // The chat's window keeps its own; the new agent nothing was sent to
      // goes, as with its window closed.
      expect(workspace.current, same(current));
      expect(workspace.threads, isNot(contains(thread)));
    },
    semanticsEnabled: false,
    // Its toggle is the header's on Windows, by the traffic lights on macOS.
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );

  for (final ideWindows in IdeWindows.values) {
    _testWindows('an agent\'s window\'s Open in Fast Ide shows its project\'s '
        'IDE there, the agent its chat, the window behind left alone '
        '(${ideWindows.name})', (tester) async {
      final (windows, host, workspace) = await _pumpApp(
        tester,
        settings: () => WindowSettings(ideWindows: ideWindows),
      );
      final opening = windows.openAgent(['~/code/baocode']);
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      final thread = (await opening)!;
      final window = windows.agentWindows.single;
      final layout = workspace.layout;

      await tester.tap(
        find
            .descendant(
              of: _inView(window.viewId, find.byType(OpenInEditorButton)),
              matching: find.text('Fast Ide'),
            )
            .first,
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      final ide = _inView(window.viewId, find.byType(IdeWorkbench));
      expect(ide, findsOneWidget);
      expect(window.delegate!.ideSpace!.root, '~/code/baocode');
      final title = tester.widget<IdeChatTitle>(
        _inView(window.viewId, find.byType(IdeChatTitle)),
      );
      expect(title.current, same(thread));
      // No other window opens or comes up for it.
      expect(host.created, hasLength(1));
      expect(windows.active, same(window));
      expect(workspace.layout, layout);
      expect(_inView(0, find.byType(IdeWorkbench)), findsNothing);

      tester.widget<IdeWorkbench>(ide).onBack();
      await tester.pump();
      await tester.pump();
      expect(ide, findsNothing);
      expect(_inView(window.viewId, find.byType(ChatScreen)), findsOneWidget);
    });
  }

  _testWindows('a window closed goes, its view and its workbench', (
    tester,
  ) async {
    final (windows, host, _) = await _pumpApp(tester);
    final window = await _open(tester, windows, '~/code/baocode');
    final closing = windows.requestClose(window);
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(await closing, isTrue);
    expect(find.byType(Workbench), findsOneWidget);
    expect(host.views, isEmpty);
    expect(window.delegate, isNull);
  });

  _testWindows('Open Folder in a window builds it anew for the folder', (
    tester,
  ) async {
    final (windows, _, _) = await _pumpApp(tester);
    final window = await _open(tester, windows, '~/code/baocode');
    final before = window.delegate;
    final replacing = windows.replaceFolder(window, '~/code/cursor-docs');
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    await replacing;
    expect(window.folder, '~/code/cursor-docs');
    expect(window.delegate, isNotNull);
    expect(window.delegate, isNot(same(before)));
    expect(find.byType(Workbench), findsNWidgets(2));
  });

  _testWindows('Switch Window shows in the window it was asked in', (
    tester,
  ) async {
    final (windows, _, _) = await _pumpApp(tester);
    final window = await _open(tester, windows, '~/code/baocode');
    windows.switchWindow(window);
    await tester.pump();
    await tester.pump();
    expect(
      _inView(window.viewId, find.text('Select a window to switch to')),
      findsOneWidget,
    );
    expect(_inView(0, find.text('Select a window to switch to')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
  });

  _testWindows('window.ideWindows switched: the IDE moves into the main '
      'window, and back to a window of its own', (tester) async {
    var settings = const WindowSettings(ideWindows: IdeWindows.separate);
    final (windows, host, _) = await _pumpApp(tester, settings: () => settings);
    final window = await _open(tester, windows, '~/code/baocode');

    settings = const WindowSettings(ideWindows: IdeWindows.mainWindow);
    windows.settingsChanged();
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(windows.multi, isFalse);
    expect(host.views, isEmpty);
    expect(window.delegate, isNull);
    expect(find.byType(Workbench), findsOneWidget);
    expect(_inView(0, find.byType(IdeWorkbench)), findsOneWidget);
    expect(windows.chat.delegate!.ideSpace!.root, '~/code/baocode');

    settings = const WindowSettings(ideWindows: IdeWindows.separate);
    windows.settingsChanged();
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(windows.multi, isTrue);
    expect(host.created, hasLength(2));
    final moved = windows.ideWindows.single;
    expect(moved.folder, '~/code/baocode');
    expect(_inView(moved.viewId, find.byType(IdeWorkbench)), findsOneWidget);
    // The main window's IDE is gone, not only hidden.
    expect(
      _inView(0, find.byType(IdeWorkbench, skipOffstage: false)),
      findsNothing,
    );
  });

  _testWindows('the IDE in the main window: New Window (⇧⌘N) from the chat '
      'shows its start page there', (tester) async {
    final (windows, host, _) = await _pumpApp(
      tester,
      settings: () => const WindowSettings(ideWindows: IdeWindows.mainWindow),
    );
    expect(windows.started, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(host.created, isEmpty);
    expect(_inView(0, find.byType(IdeStartPage)), findsOneWidget);
  });

  _testWindows('an agent\'s window has the search palette (Ctrl+Shift+P), '
      'its commands the window\'s, Preferences: Color Theme among them', (
    tester,
  ) async {
    final (windows, _, _) = await _pumpApp(tester);
    final opening = windows.openAgent(['~/code/baocode']);
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    await opening;
    final window = windows.agentWindows.single;
    // The keyboard is the agent's window's (its composer has the focus).
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<View>()
          ?.view
          .viewId,
      window.viewId,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(_inView(window.viewId, find.byType(SearchPalette)), findsOneWidget);
    expect(_inView(0, find.byType(SearchPalette)), findsNothing);
    final palette = tester.widget<SearchPalette>(
      _inView(window.viewId, find.byType(SearchPalette)),
    );
    expect(
      palette.actions.map((action) => action.id),
      contains('workbench.action.selectTheme'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 200));
  });

  _testWindows('writing a plan in the chat window does not switch to or open '
      'the plan file in an open IDE window behind it', (tester) async {
    final temp = Directory.systemTemp.createTempSync('baocode_plan_window_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final planFile = File('${temp.path}/.claude/plans/grow-input.md')
      ..createSync(recursive: true)
      ..writeAsStringSync('# Grow the input\n\nLet it grow.');
    final projectDir = Directory('${temp.path}/proj')..createSync();

    final cli = FakeCli();
    late final KernelDescriptor descriptor;
    descriptor = KernelDescriptor(
      id: 'claude-code',
      label: 'Claude Code',
      icon: Codicons.sparkle,
      description: '',
      create: (context) =>
          ClaudeCodeKernel(descriptor, context, start: (_) async => cli),
    );
    final project = Project.at(projectDir.path);
    final custom = Workspace(projects: [project], kernels: [descriptor]);
    final thread = custom.startAgent(project);
    custom.select(thread);

    final (windows, host, workspace) = await _pumpApp(
      tester,
      workspace: custom,
    );

    // Open the IDE window with this thread as its chat tab, then go back to
    // the chat window (IDE stays open behind it).
    final ideWindow = await _open(
      tester,
      windows,
      project.path,
      thread: thread,
    );
    windows.showChat();
    await tester.pump();
    await tester.pump();
    expect(windows.active, same(windows.chat));
    expect(host.focused, windows.chat.viewId);
    final ideSpace = ideWindow.delegate!.ideSpace!;
    expect(ideSpace.documents, isEmpty);

    Future<void> flushIo() async {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    // Start a turn in plan mode and emit a plan write while the chat window is
    // in front.
    thread.session.send(const ComposerMessage(text: 'plan this'));
    await flushIo();
    await tester.pump(const Duration(milliseconds: 100));

    void writePlan(String id) {
      cli
        ..push({
          'type': 'assistant',
          'parent_tool_use_id': null,
          'message': {
            'role': 'assistant',
            'content': [
              {
                'type': 'tool_use',
                'id': id,
                'name': 'Write',
                'input': {
                  'file_path': planFile.path,
                  'content': '# Grow the input\n\nLet it grow.',
                },
              },
            ],
          },
        })
        ..push({
          'type': 'user',
          'parent_tool_use_id': null,
          'message': {
            'role': 'user',
            'content': [
              {'type': 'tool_result', 'tool_use_id': id, 'content': 'ok'},
            ],
          },
          'tool_use_result': {'type': 'create', 'filePath': planFile.path},
        });
    }

    final logBefore = host.log.length;
    writePlan('p1');
    await flushIo();
    expect(thread.session.plan?.path, planFile.path);

    // Must stay in the chat window and NOT open the plan file in the IDE.
    expect(windows.active, same(windows.chat));
    expect(
      host.log.sublist(logBefore),
      isNot(contains('focus ${ideWindow.viewId}')),
    );
    expect(ideSpace.documents, isEmpty);

    // When the IDE window is in front but its chat panel is hidden, writing a
    // plan still must not open the plan file in the IDE.
    host.events!.windowFocused(ideWindow.viewId);
    ideSpace.layout.chat = false;
    await tester.pump();
    await tester.pump();
    final logWhenHidden = host.log.length;
    writePlan('p2');
    await flushIo();
    expect(ideSpace.documents, isEmpty);
    expect(host.log.sublist(logWhenHidden), isEmpty);

    // When the IDE window is in front and its chat panel shows this thread,
    // writing a plan opens it directly in the IDE without stealing window focus.
    ideSpace.layout.chat = true;
    await tester.pump();
    await tester.pump();
    final logWhenShown = host.log.length;
    final ideChat = tester.widget<ChatScreen>(
      _inView(ideWindow.viewId, find.byType(ChatScreen)),
    );
    expect(ideChat.followPlan?.call(), isTrue);
    writePlan('p3');
    await flushIo();
    // Wait until the real file read completes.
    for (var i = 0; i < 20 && ideSpace.documents.isEmpty; i++) {
      await flushIo();
    }
    expect(
      ideSpace.documents.map((doc) => doc.path),
      contains(planFile.path),
    );
    expect(host.log.sublist(logWhenShown), isEmpty);
    expect(workspace.current, same(thread));
    cli.push({'type': 'result', 'subtype': 'success', 'is_error': false});
    await tester.pump(const Duration(milliseconds: 300));
  });
}
