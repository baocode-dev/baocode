import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/ide/ide_chat_title.dart';
import 'package:baocode/ide/ide_welcome.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/main.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/window/app_windows.dart';
import 'package:baocode/window/window_settings.dart';
import 'package:baocode/workbench.dart';
import 'package:baocode/workspace/workspace.dart';

import 'fake_window_host.dart';

/// The app with windows of its own, each a view of the test's engine: the
/// chat's (the test's view) and those the IDE opens.
Future<(AppWindows, FakeWindowHost, Workspace)> _pumpApp(
  WidgetTester tester, {
  WindowSettings Function()? settings,
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
  final workspace = Workspace.mock();
  final windows = AppWindows(
    host: host,
    workspace: workspace,
    l10n: () => englishLocalizations,
    settings: settings,
    isDirectory: (path) async => true,
    nextFrame: () => tester.binding.endOfFrame,
  );
  await windows.start();
  await tester.pumpWidget(
    BaoCodeApp(workspace: workspace, windows: windows),
    wrapWithView: false,
  );
  await tester.pump();
  return (windows, host, workspace);
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
      'conversation alone, a view of its own; closed, it goes', (tester) async {
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
    expect(_inView(window.viewId, find.byType(Sidebar)), findsNothing);
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
    var settings = const WindowSettings();
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

    settings = const WindowSettings();
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
}
