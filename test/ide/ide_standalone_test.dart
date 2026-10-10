import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/ide/ide_chat_title.dart';
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/main.dart';
import 'package:baocode/workspace/workspace.dart';

const _window = MethodChannel('baocode/window');
const _open = MethodChannel('baocode/open');

/// The app over the mock agents, its window's calls answered.
Future<Workspace> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _window,
    (call) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _window,
      null,
    ),
  );
  final workspace = Workspace.mock();
  await tester.pumpWidget(BaoCodeApp(workspace: workspace));
  await tester.pump();
  return workspace;
}

Future<void> _showIde(WidgetTester tester, Workspace workspace) async {
  workspace.layout = WorkspaceLayout.ide;
  await tester.pump();
  await tester.pump();
}

IdeWorkbenchState _ide(WidgetTester tester) =>
    tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

void main() {
  testWidgets('with no folder, the IDE asks for one: in the explorer and in '
      'the chat; the chat\'s agent stays as it was', (tester) async {
    final workspace = await _pumpApp(tester);
    final current = workspace.current;
    await _showIde(tester, workspace);
    expect(workspace.ideFolder, isNull);
    expect(
      tester
          .widget<IdeWorkbench>(find.byType(IdeWorkbench))
          .workspace
          .hasFolder,
      isFalse,
    );
    expect(find.text('No Folder Opened'), findsOneWidget);
    expect(find.text('Open a folder to chat with an agent in it.'), findsOne);
    expect(find.byType(IdeChatTitle), findsNothing);
    expect(workspace.current, same(current));
  });

  testWidgets('New Text File opens Untitled-1, then Untitled-2', (
    tester,
  ) async {
    final workspace = await _pumpApp(tester);
    await _showIde(tester, workspace);
    expect(
      _ide(tester).runCommand('workbench.action.files.newUntitledFile'),
      isTrue,
    );
    await tester.pump();
    expect(find.text('Untitled-1'), findsWidgets);
    _ide(tester).runCommand('workbench.action.files.newUntitledFile');
    await tester.pump();
    expect(find.text('Untitled-2'), findsWidgets);
    final docs = tester
        .widget<IdeWorkbench>(find.byType(IdeWorkbench))
        .workspace
        .documents;
    expect([for (final doc in docs) doc.isUntitled], [true, true]);
  });

  testWidgets('an agent opened in the IDE is its folder\'s, its chat a tab; '
      'the chat layout keeps its own agent', (tester) async {
    final workspace = await _pumpApp(tester);
    final current = workspace.current!;
    final other = workspace.threads.firstWhere(
      (thread) => thread.project != current.project,
    );
    workspace.openInIde(other);
    await tester.pump();
    await tester.pump();
    expect(workspace.layout, WorkspaceLayout.ide);
    expect(workspace.ideFolder, other.project.path);
    final title = tester.widget<IdeChatTitle>(find.byType(IdeChatTitle));
    expect(title.tabs, [other]);
    expect(title.current, same(other));

    workspace.layout = WorkspaceLayout.chat;
    await tester.pump();
    expect(workspace.current, same(current));
  });

  testWidgets('a folder opened in the IDE is not a project, its new chat '
      'not listed, until it is sent something', (tester) async {
    final workspace = await _pumpApp(tester);
    const folder = '/nonexistent/scratch-folder';
    workspace.openIdeFolder(folder);
    await _showIde(tester, workspace);
    final draft = workspace.newIdeChat(folder);
    await tester.pump();
    expect(draft.project.path, folder);
    expect(
      workspace.projects.map((project) => project.path),
      isNot(contains(folder)),
    );
    expect(workspace.listsInSidebar(draft), isFalse);

    workspace.layout = WorkspaceLayout.chat;
    await tester.pump();
    await tester.pump();
    expect(find.text('scratch-folder'), findsNothing);
  });

  testWidgets('a folder from the code command opens in the IDE, though the '
      'main window is the chat; the chat keeps its agent', (tester) async {
    final folder = Directory.systemTemp.createTempSync('baocode-code-open');
    addTearDown(() => folder.deleteSync(recursive: true));
    var pending = <String>[folder.path];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_open, (
      call,
    ) async {
      if (call.method != 'takePending') return null;
      final taken = pending;
      pending = [];
      return taken;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _open,
        null,
      ),
    );
    final workspace = await _pumpApp(tester);
    final current = workspace.current;
    final threads = {...workspace.threads};
    expect(workspace.layout, WorkspaceLayout.chat);
    for (var i = 0; i < 50 && workspace.ideFolder == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(workspace.ideFolder, folder.path);
    expect(workspace.layout, WorkspaceLayout.ide);
    expect(workspace.current, same(current));
    // Only the IDE's own new chat in the folder, not listed.
    for (final thread in workspace.threads.where((t) => !threads.contains(t))) {
      expect(thread.project.path, folder.path);
      expect(workspace.listsInSidebar(thread), isFalse);
    }
    expect(
      workspace.projects.map((project) => project.path),
      isNot(contains(folder.path)),
    );
  });

  testWidgets('the chat tabs scroll sideways under a thin bar of their own', (
    tester,
  ) async {
    final workspace = await _pumpApp(tester);
    final thread = workspace.current!;
    workspace.openInIde(thread);
    await tester.pump();
    await tester.pump();
    final folder = thread.project.path;
    final others = [
      for (final t in workspace.threads)
        if (t.project == thread.project && t != thread) t,
    ];
    expect(others.length, greaterThan(3));
    for (final t in others) {
      workspace.openIdeChat(folder, t);
    }
    await tester.pump();
    await tester.pump();
    final title = find.byType(IdeChatTitle);
    final bars = find.descendant(
      of: title,
      matching: find.byType(RawScrollbar),
    );
    expect(bars, findsOneWidget);
    expect(tester.widget<RawScrollbar>(bars).thickness, 3);
    // Not the platform's own thicker one besides.
    expect(
      find.descendant(of: title, matching: find.byType(Scrollbar)),
      findsNothing,
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: title, matching: find.byType(Scrollable)),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    // The chat shown, the last opened, its tab scrolled into view.
    expect(workspace.ideChat(folder), others.last);
    expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);
  });

  testWidgets('the agent history shows a spinner for a running agent, '
      'until it stops', (tester) async {
    final workspace = await _pumpApp(tester);
    final thread = workspace.current!;
    final other = workspace.threads.firstWhere(
      (t) => t != thread && t.project == thread.project && !t.archived,
    );
    workspace.openInIde(thread);
    await tester.pump();
    await tester.pump();
    other.session.send(const ComposerMessage(text: '跑一下'));
    await tester.pump();
    expect(other.status, ThreadStatus.running);

    await tester.tap(find.byTooltip('Agent History'));
    await tester.pump();
    final spinners = find.descendant(
      of: find.byType(IdeQuickInput),
      matching: find.byType(CircularProgressIndicator),
    );
    expect(spinners, findsOneWidget);

    other.session.stop();
    await tester.pump(const Duration(seconds: 1));
    expect(spinners, findsNothing);
  });

  testWidgets('a dot follows an agent\'s title in the history when it '
      'finished unseen; a running tab spins before its title, hovered too', (
    tester,
  ) async {
    final workspace = await _pumpApp(tester);
    final thread = workspace.current!;
    final unread = workspace.threads.firstWhere(
      (t) => t.project == thread.project && t.status == ThreadStatus.unread,
    );
    final other = workspace.threads.firstWhere(
      (t) =>
          t != thread &&
          t != unread &&
          t.project == thread.project &&
          !t.archived,
    );
    workspace.openInIde(thread);
    await tester.pump();
    await tester.pump();
    final dots = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
    );

    await tester.tap(find.byTooltip('Agent History'));
    await tester.pump();
    expect(
      find.descendant(of: find.byType(IdeQuickInput), matching: dots),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    final folder = thread.project.path;
    workspace.openIdeChat(folder, other);
    workspace.openIdeChat(folder, thread);
    await tester.pump();
    other.session.send(const ComposerMessage(text: '跑一下'));
    await tester.pump();
    final title = find.byType(IdeChatTitle);
    final spinner = find.descendant(
      of: title,
      matching: find.byType(CircularProgressIndicator),
    );
    expect(spinner, findsOneWidget);
    final tab = find.descendant(of: title, matching: find.text(other.title));
    expect(tester.getTopRight(spinner).dx, lessThan(tester.getTopLeft(tab).dx));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(tab));
    await tester.pump();
    expect(spinner, findsOneWidget);
    other.session.stop();
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.descendant(
        of: title,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
  });

  testWidgets('a chat tab dragged goes where it is dropped, and stays there', (
    tester,
  ) async {
    final workspace = await _pumpApp(tester);
    final thread = workspace.current!;
    final folder = thread.project.path;
    final others = [
      for (final t in workspace.threads)
        if (t.project == thread.project && t != thread && !t.archived) t,
    ].take(2).toList();
    workspace.openInIde(thread);
    for (final t in others) {
      workspace.openIdeChat(folder, t);
    }
    await tester.pump();
    await tester.pump();
    expect(workspace.ideChats(folder), [thread, ...others]);

    final title = find.byType(IdeChatTitle);
    Finder tab(AgentThread t) =>
        find.descendant(of: title, matching: find.text(t.title));
    final first = tester.getTopLeft(tab(thread));
    final gesture = await tester.startGesture(
      tester.getCenter(tab(others.last)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(-10, 0));
    await tester.pump();
    await gesture.moveTo(first + const Offset(4, 4));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(workspace.ideChats(folder), [others.last, thread, others.first]);
    // A click is still a click (the tabs as wide as the editor's, it may
    // be scrolled out).
    await tester.ensureVisible(tab(thread));
    await tester.pump();
    await tester.tap(tab(thread));
    await tester.pump();
    expect(workspace.ideChat(folder), same(thread));
    expect(workspace.ideChats(folder), [others.last, thread, others.first]);
  });

  testWidgets('a chat tab\'s right click closes it, the others, those to '
      'its right or all, and pins its agent', (tester) async {
    final workspace = await _pumpApp(tester);
    final thread = workspace.current!;
    final folder = thread.project.path;
    final others = [
      for (final t in workspace.threads)
        if (t.project == thread.project && t != thread && !t.archived) t,
    ].take(3).toList();
    workspace.openInIde(thread);
    for (final t in others) {
      workspace.openIdeChat(folder, t);
    }
    await tester.pump();
    await tester.pump();
    expect(workspace.ideChats(folder), [thread, ...others]);

    final title = find.byType(IdeChatTitle);
    Future<void> choose(AgentThread t, String item) async {
      final tab = find.descendant(of: title, matching: find.text(t.title));
      await tester.ensureVisible(tab);
      await tester.pumpAndSettle();
      await tester.tap(tab, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    await choose(others.first, 'Close to the Right');
    expect(workspace.ideChats(folder), [thread, others.first]);
    expect(workspace.ideChat(folder), same(others.first));

    await choose(thread, 'Close Others');
    expect(workspace.ideChats(folder), [thread]);
    expect(workspace.ideChat(folder), same(thread));

    expect(thread.pinned, isFalse);
    await choose(thread, 'Pin');
    expect(thread.pinned, isTrue);

    await choose(thread, 'Close All');
    // A new one takes the last's place; the agents go on.
    final tabs = workspace.ideChats(folder);
    expect(tabs, hasLength(1));
    expect(tabs.single.untouched, isTrue);
    expect(workspace.threads, containsAll([thread, ...others]));
  });

  testWidgets('⌘W/Ctrl+W from the chat closes its tab shown, the next '
      'then; from an editor, the editor', (tester) async {
    final workspace = await _pumpApp(tester);
    final thread = workspace.current!;
    final folder = thread.project.path;
    final other = workspace.threads.firstWhere(
      (t) => t.project == thread.project && t != thread && !t.archived,
    );
    workspace.openInIde(thread);
    workspace.openIdeChat(folder, other);
    await tester.pump();
    await tester.pump();
    _ide(tester).runCommand('workbench.action.files.newUntitledFile');
    await tester.pump();
    List<Object> docs() => tester
        .widget<IdeWorkbench>(find.byType(IdeWorkbench))
        .workspace
        .documents;
    expect(docs(), hasLength(1));

    Future<void> closeKey() async {
      final modifier = defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byType(QuillEditor));
    await tester.pumpAndSettle();
    await closeKey();
    expect(workspace.ideChats(folder), [thread]);
    expect(docs(), hasLength(1));

    // The keyboard went to the chat shown next.
    await closeKey();
    final tabs = workspace.ideChats(folder);
    expect(tabs, hasLength(1));
    expect(tabs.single.untouched, isTrue);
    expect(docs(), hasLength(1));

    _ide(tester).runCommand('workbench.action.focusActiveEditorGroup');
    await tester.pumpAndSettle();
    await closeKey();
    expect(docs(), isEmpty);
    expect(workspace.ideChats(folder), tabs);
  });
}
