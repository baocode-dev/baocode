// Over a new chat's input, the folder it is to work in: a project, none
// (the Desktop), or one picked in Finder; it goes once a message is sent.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/main.dart';
import 'package:baocode/workspace/new_chat_folder_bar.dart';
import 'package:baocode/workspace/workspace.dart';

const _window = MethodChannel('baocode/window');
const _desktop = '/Users/me/Desktop';

final _mac = TargetPlatformVariant.only(TargetPlatform.macOS);

/// The app on the mock workspace, a new agent open in its first project.
Future<Workspace> _pumpNew(WidgetTester tester) async {
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
  final desktop = NewChatFolderBar.desktop;
  final pick = NewChatFolderBar.pickDirectory;
  NewChatFolderBar.desktop = () => _desktop;
  addTearDown(() {
    NewChatFolderBar.desktop = desktop;
    NewChatFolderBar.pickDirectory = pick;
  });
  final workspace = Workspace.mock();
  await tester.pumpWidget(BaoCodeApp(workspace: workspace));
  workspace.create();
  await tester.pump();
  return workspace;
}

Finder get _bar => find.byType(NewChatFolderBar);

/// Kept sessions found only once [found] completes, as Claude Code's are
/// after all of them are read.
class _SlowCatalog implements SessionCatalog {
  final found = Completer<List<SessionRecord>>();

  @override
  Future<List<ProjectRecord>> projects() async => const [];

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) => found.future;

  @override
  Future<void> delete(String id) async {}
}

void main() {
  testWidgets('a new chat waits in the middle, under where it works', (
    tester,
  ) async {
    final workspace = await _pumpNew(tester);
    expect(workspace.selected.project.name, 'baocode');
    expect(_bar, findsOneWidget);
    expect(
      find.descendant(of: _bar, matching: find.text('baocode')),
      findsOneWidget,
    );
    expect(find.text('Open from Finder'), findsOneWidget);
    // Its input is halfway down, not at the bottom.
    final bar = tester.getTopLeft(_bar).dy;
    expect(bar, lessThan(900 / 2));
    expect(bar, greaterThan(900 / 4));
  }, variant: _mac);

  testWidgets('a hidden project is not offered for a new chat', (tester) async {
    final workspace = await _pumpNew(tester);
    final hidden = workspace.projects.firstWhere(
      (project) => project.path == '~/code/cursor-docs',
    );
    workspace.hideProject(hidden);
    await tester.pump();

    await tester.tap(find.descendant(of: _bar, matching: find.text('baocode')));
    await tester.pumpAndSettle();
    expect(find.text('cursor-docs'), findsNothing);
  }, variant: _mac);

  testWidgets('no folder has it work in the Desktop, in its place', (
    tester,
  ) async {
    final workspace = await _pumpNew(tester);
    final was = workspace.selected;
    await tester.tap(find.descendant(of: _bar, matching: find.text('baocode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No folder'));
    await tester.pumpAndSettle();

    final moved = workspace.selected;
    expect(moved.project.path, _desktop);
    expect(moved.session.kernelContext.cwd, _desktop);
    // The untouched one is gone, not left behind in the sidebar.
    expect(workspace.threads, isNot(contains(was)));
    expect(
      find.descendant(of: _bar, matching: find.text('No folder')),
      findsOneWidget,
    );
  }, variant: _mac);

  testWidgets('a folder picked in Finder becomes its project', (tester) async {
    final workspace = await _pumpNew(tester);
    NewChatFolderBar.pickDirectory = () async => '/tmp/picked';
    await tester.tap(find.text('Open from Finder'));
    await tester.pumpAndSettle();

    expect(workspace.selected.project.path, '/tmp/picked');
    expect(workspace.projects.first.path, '/tmp/picked');
    expect(
      find.descendant(of: _bar, matching: find.text('picked')),
      findsOneWidget,
    );
  }, variant: _mac);

  testWidgets('it goes once a message is sent, the input to the bottom', (
    tester,
  ) async {
    final workspace = await _pumpNew(tester);
    workspace.selected.session.send(const ComposerMessage(text: 'hello'));
    await tester.pump();
    expect(_bar, findsNothing);
    // An agent with a conversation has none either.
    workspace.select(workspace.threads.first);
    await tester.pump();
    expect(_bar, findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }, variant: _mac);

  test(
    'a new folder is moved to at once, its kept sessions listed after',
    () async {
      final catalog = _SlowCatalog();
      final mock = MockKernels.claudeCode;
      final kernel = KernelDescriptor(
        id: mock.id,
        label: mock.label,
        icon: mock.icon,
        description: mock.description,
        create: mock.create,
        catalog: catalog,
      );
      final workspace = Workspace(
        projects: const [Project('a', '/tmp/a')],
        kernels: [kernel],
      );
      addTearDown(workspace.dispose);
      final was = workspace.create();

      final moved = workspace.moveNew(was, _desktop);
      expect(workspace.selected, same(moved));
      expect(moved.project.path, _desktop);
      expect(workspace.threads, [moved]);

      catalog.found.complete([
        SessionRecord(
          id: 'kept',
          title: 'Earlier on the Desktop',
          updatedAt: DateTime(2026, 9, 30),
          cwd: _desktop,
        ),
      ]);
      await pumpEventQueue();
      expect(workspace.threads.map((thread) => thread.title), [
        'New Chat',
        'Earlier on the Desktop',
      ]);
      expect(workspace.selected, same(moved));
    },
  );
}
