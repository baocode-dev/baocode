import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/mock_claude_code_transport.dart';
import 'package:baocode/main.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/workspace/editor_launcher.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';

/// Sessions as Claude Code keeps them: one recorded, in one project, and
/// any [started] since (e.g. in a terminal).
class FakeCatalog implements SessionCatalog {
  static final List<SessionRecord> started = [];

  static final kept = SessionRecord(
    id: 'eafc328b',
    title: 'Write a.txt and read it back',
    updatedAt: DateTime(2026, 9, 27, 16),
    cwd: '/tmp/project',
    path: 'test/fixtures/claude_code/history.jsonl',
  );

  @override
  Future<List<ProjectRecord>> projects() async => [
    for (final session in started)
      ProjectRecord(path: session.cwd, sessions: [session]),
    ProjectRecord(path: '/tmp/project', sessions: [kept]),
  ];

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) async => const [];

  /// Sessions deleted, in order.
  static final List<String> deleted = [];

  @override
  Future<void> delete(String id) async => deleted.add(id);
}

final KernelDescriptor claude = KernelDescriptor(
  id: 'claude-code',
  label: 'Claude Code',
  icon: Icons.auto_awesome_rounded,
  description: '',
  catalog: FakeCatalog(),
  create: (context) => ClaudeCodeKernel(
    claude,
    context,
    start: MockClaudeCodeTransport.start,
    readHistory: (session) async => [
      for (final line in File(session.path!).readAsLinesSync())
        if (line.isNotEmpty) (jsonDecode(line) as Map).cast<String, Object?>(),
    ],
  ),
);

Future<Workspace> pumpLoaded(
  WidgetTester tester, {
  PreferenceStore? preferences,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final workspace = Workspace(kernels: [claude], preferences: preferences);
  await tester.pumpWidget(BaoCodeApp(workspace: workspace));
  await tester.runAsync(workspace.load);
  await tester.pump();
  return workspace;
}

Finder inSidebar(Finder finder) =>
    find.descendant(of: find.byType(Sidebar), matching: finder);

void main() {
  testWidgets('lists the kept sessions; one opens with its history', (
    tester,
  ) async {
    final workspace = await pumpLoaded(tester);
    expect(workspace.projects.map((p) => p.name), ['project']);
    // A new agent in the most recent project, beside the kept session.
    expect(workspace.selected.record, isNull);
    expect(
      inSidebar(find.text('Write a.txt and read it back')),
      findsOneWidget,
    );

    await tester.tap(inSidebar(find.text('Write a.txt and read it back')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final thread = workspace.selected;
    expect(thread.record, FakeCatalog.kept);
    expect(
      tester.widget<ChatScreen>(find.byType(ChatScreen)).session,
      thread.session,
    );
    expect(thread.session.itemCount, greaterThan(3));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('No dedicated todo tool'), findsOneWidget);
    // Continuing it keeps its kernel.
    expect(thread.session.kernelLocked, isTrue);

    // Deleted, it goes from Claude Code too, once its agent has stopped.
    addTearDown(FakeCatalog.deleted.clear);
    await tester.tap(
      inSidebar(find.text('Write a.txt and read it back')),
      buttons: kSecondaryButton,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Delete'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('from Claude Code too'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(FakeCatalog.deleted, ['eafc328b']);
    expect(inSidebar(find.text('Write a.txt and read it back')), findsNothing);
    // Listed again by the kernel meanwhile, it stays deleted.
    await tester.runAsync(workspace.refresh);
    await tester.pump();
    expect(inSidebar(find.text('Write a.txt and read it back')), findsNothing);
  });

  testWidgets('an opened folder becomes the first project', (tester) async {
    final workspace = await pumpLoaded(tester);
    await tester.runAsync(() => workspace.openFolder('/tmp/other'));
    await tester.pump();
    expect(workspace.projects.first.path, '/tmp/other');
    expect(workspace.selected.project.path, '/tmp/other');
    expect(workspace.selected.session.kernelContext.cwd, '/tmp/other');
  });

  testWidgets('a new agent starts in the mode and approvals picked last', (
    tester,
  ) async {
    final workspace = await pumpLoaded(tester);
    final first = workspace.selected.session;
    await tester.pump();
    expect(first.modes!.selected.id, 'agent');
    expect(first.permissions!.selected.id, 'default');
    first.modes!.onSelected(
      first.modes!.options.firstWhere((mode) => mode.id == 'ask'),
    );
    first.permissions!.onSelected(
      first.permissions!.options.firstWhere((p) => p.id == 'acceptEdits'),
    );
    await tester.pump();

    first.send(const ComposerMessage(text: 'hi'));
    await tester.pump();
    workspace.create();
    await tester.pump();
    final second = workspace.selected.session;
    expect(second, isNot(first));
    expect(second.kernelContext.settings, {
      KernelChoiceKind.mode.name: 'ask',
      KernelChoiceKind.permission.name: 'acceptEdits',
    });
    expect(second.modes!.selected.id, 'ask');
    expect(second.permissions!.selected.id, 'acceptEdits');
    first.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the file manager, kept by its old name, is still the one '
      'picked', (tester) async {
    final store = MemoryPreferenceStore({'editor': 'finder'});
    final workspace = await pumpLoaded(tester, preferences: store);
    expect(workspace.preferredEditor, Editor.folder);
  });

  testWidgets('the Fast Ide is kept as the editor like the apps are', (
    tester,
  ) async {
    final store = MemoryPreferenceStore({'editor': 'fastIde'});
    final workspace = await pumpLoaded(tester, preferences: store);
    expect(workspace.preferredEditor, Editor.fastIde);
  });

  testWidgets('choices are kept between runs: a new agent starts with the '
      'last ones, a kept session with its own', (tester) async {
    final store = MemoryPreferenceStore({
      'editor': 'zed',
      'settings': {'mode': 'plan', 'permission': 'bypassPermissions'},
      'agents': {
        FakeCatalog.kept.id: {'mode': 'ask', 'permission': 'acceptEdits'},
      },
    });
    final workspace = await pumpLoaded(tester, preferences: store);
    expect(workspace.preferredEditor, Editor.zed);
    final first = workspace.selected.session;
    await tester.pump();
    expect(first.modes!.selected.id, 'plan');
    expect(first.permissions!.selected.id, 'bypassPermissions');

    // Picked again: kept for the next run.
    first.permissions!.onSelected(
      first.permissions!.options.firstWhere((p) => p.id == 'default'),
    );
    await tester.pump();
    expect((store.preferences['settings'] as Map)['permission'], 'default');

    // Reopened, a kept session is as it was left.
    final kept = workspace.threads.firstWhere(
      (thread) => thread.record?.id == FakeCatalog.kept.id,
    );
    expect(kept.session.kernelContext.settings, {
      KernelChoiceKind.mode.name: 'ask',
      KernelChoiceKind.permission.name: 'acceptEdits',
    });
    first.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('back in the app, sessions started elsewhere are listed', (
    tester,
  ) async {
    addTearDown(FakeCatalog.started.clear);
    final workspace = await pumpLoaded(tester);
    final before = workspace.threads.length;
    // This run's agent, once the CLI named its session.
    final ours = workspace.selected.session;
    ours.send(const ComposerMessage(text: 'hi'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(ours.sessionId, isNotNull);

    SessionRecord record(String id, String cwd) => SessionRecord(
      id: id,
      title: 'Started in a terminal ($id)',
      updatedAt: DateTime(2026, 9, 28),
      cwd: cwd,
    );
    FakeCatalog.started.addAll([
      record('terminal-1', '/tmp/project'),
      record('terminal-2', '/tmp/elsewhere'),
      record(ours.sessionId!, '/tmp/project'),
    ]);
    await tester.runAsync(workspace.refresh);
    await tester.pump();
    expect(workspace.threads.length, before + 2);
    expect(
      inSidebar(find.text('Started in a terminal (terminal-1)')),
      findsOneWidget,
    );
    expect(workspace.projects.first.path, '/tmp/elsewhere');

    // Taken off the list, it stays off.
    workspace.delete(
      workspace.threads.firstWhere((t) => t.record?.id == 'terminal-1'),
    );
    await tester.runAsync(workspace.refresh);
    await tester.pump();
    expect(workspace.threads.length, before + 1);
    ours.stop();
    await tester.pump(const Duration(seconds: 1));
  });
}
