import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/mock_claude_code_transport.dart';
import 'package:baocode/main.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/workspace/agent_title.dart';
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
    readHistory: _readHistory,
  ),
);

Future<Workspace> pumpLoaded(
  WidgetTester tester, {
  PreferenceStore? preferences,
  PreferenceStore? drafts,
  KernelDescriptor? kernel,
  AgentTitler? titler,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final workspace = Workspace(
    kernels: [kernel ?? claude],
    preferences: preferences,
    drafts: drafts,
    titler: titler,
  );
  await tester.pumpWidget(BaoCodeApp(workspace: workspace));
  await tester.runAsync(workspace.load);
  await tester.pump();
  return workspace;
}

Finder inSidebar(Finder finder) =>
    find.descendant(of: find.byType(Sidebar), matching: finder);

/// Claude Code (the mock) keeping the titles it is given in [renames].
KernelDescriptor titledClaude(List<String> renames) {
  late final KernelDescriptor kernel;
  return kernel = KernelDescriptor(
    id: 'claude-code',
    label: 'Claude Code',
    icon: Icons.auto_awesome_rounded,
    description: '',
    catalog: FakeCatalog(),
    create: (context) => ClaudeCodeKernel(
      kernel,
      context,
      start: (launch) async =>
          _Renames(await MockClaudeCodeTransport.start(launch), renames),
      readHistory: _readHistory,
    ),
  );
}

Future<List<Map<String, Object?>>> _readHistory(SessionRecord session) async =>
    [
      for (final line in File(session.path!).readAsLinesSync())
        if (line.isNotEmpty) (jsonDecode(line) as Map).cast<String, Object?>(),
    ];

class _Renames implements ClaudeCodeTransport {
  _Renames(this._cli, this._renames);

  final ClaudeCodeTransport _cli;
  final List<String> _renames;

  @override
  Stream<Map<String, Object?>> get messages => _cli.messages;

  @override
  void write(Map<String, Object?> message) {
    if (message case {
      'type': 'control_request',
      'request': {'subtype': 'rename_session', 'title': final String title},
    }) {
      _renames.add(title);
    }
    _cli.write(message);
  }

  @override
  void close() => _cli.close();

  @override
  Future<void> get exited => _cli.exited;
}

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

  testWidgets('what is typed and not sent is there the next run', (
    tester,
  ) async {
    final drafts = MemoryPreferenceStore();
    var workspace = await pumpLoaded(tester, drafts: drafts);
    AgentThread keptThread() => workspace.threads.firstWhere(
      (thread) => thread.id == FakeCatalog.kept.id,
    );
    AgentThread newThread() =>
        workspace.threads.firstWhere((thread) => thread.id == null);
    final image = ImageAttachment(
      bytes: Uint8List.fromList([1, 2, 3]),
      mediaType: 'image/png',
      name: 'shot.png',
      number: 1,
    );
    keptThread().session.draft.save(
      Delta()..insert('Half a question\n'),
      const TextSelection.collapsed(offset: 4),
      [image],
    );
    workspace.create(project: keptThread().project);
    newThread().session.draft.save(
      Delta()..insert('Not asked yet\n'),
      const TextSelection(baseOffset: 0, extentOffset: 3),
      const [],
    );
    // Written once typing stops.
    await tester.pump(const Duration(milliseconds: 600));
    expect((await drafts.read()).keys, {
      FakeCatalog.kept.id,
      'new:/tmp/project',
    });

    await tester.pumpWidget(const SizedBox());
    workspace = await pumpLoaded(tester, drafts: drafts);
    final kept = keptThread().session.draft;
    expect(kept.content, Delta()..insert('Half a question\n'));
    expect(kept.selection, const TextSelection.collapsed(offset: 4));
    expect(kept.images.single.bytes, [1, 2, 3]);
    expect(kept.images.single.name, 'shot.png');
    expect(kept.images.single.number, 1);
    workspace.create(project: keptThread().project);
    final draft = newThread().session.draft;
    expect(draft.content, Delta()..insert('Not asked yet\n'));
    expect(
      draft.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );

    // Emptied: not kept.
    keptThread().session.draft.save(
      Delta()..insert('\n'),
      const TextSelection.collapsed(offset: 0),
      const [],
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect((await drafts.read()).keys, {'new:/tmp/project'});
  });

  testWidgets('an opened folder becomes the first project', (tester) async {
    final workspace = await pumpLoaded(tester);
    await tester.runAsync(() => workspace.openFolder('/tmp/other'));
    await tester.pump();
    expect(workspace.projects.first.path, '/tmp/other');
    expect(workspace.selected.project.path, '/tmp/other');
    expect(workspace.selected.session.kernelContext.cwd, '/tmp/other');
  });

  testWidgets('a new agent is titled after its first message, and the '
      'title is kept with its session', (tester) async {
    final renames = <String>[];
    final asked = <String>[];
    final generated = Completer<String?>();
    final workspace = await pumpLoaded(
      tester,
      kernel: titledClaude(renames),
      titler: (message) {
        asked.add(message);
        return generated.future;
      },
    );
    final thread = workspace.selected;
    final session = thread.session;

    // Its first line is the title meanwhile.
    session.send(const ComposerMessage(text: 'hi'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(asked, ['hi']);
    expect(thread.title, 'hi');
    generated.complete('Greeting');
    await tester.pump();
    expect(thread.title, 'Greeting');
    expect(inSidebar(find.text('Greeting')), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(renames, ['Greeting']);

    // Once.
    session.send(const ComposerMessage(text: 'Fix the flaky login test'));
    await tester.pump();
    expect(asked, hasLength(1));
    session.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a new agent asked with images alone is titled after the '
      'file, without the model', (tester) async {
    final renames = <String>[];
    final asked = <String>[];
    final workspace = await pumpLoaded(
      tester,
      kernel: titledClaude(renames),
      titler: (message) async {
        asked.add(message);
        return 'Generated';
      },
    );
    final thread = workspace.selected;
    thread.session.send(
      ComposerMessage(
        text: '[Image #1]',
        images: [
          ImageAttachment(
            bytes: Uint8List(0),
            mediaType: 'image/png',
            name: 'shot.png',
          ),
        ],
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(asked, isEmpty);
    expect(thread.title, 'Image: shot.png');
    expect(inSidebar(find.text('Image: shot.png')), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(renames, ['Image: shot.png']);
    thread.session.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a name the user gives stands over one generated meanwhile', (
    tester,
  ) async {
    final renames = <String>[];
    final generated = Completer<String?>();
    final workspace = await pumpLoaded(
      tester,
      kernel: titledClaude(renames),
      titler: (_) => generated.future,
    );
    final thread = workspace.selected;
    thread.session.send(
      const ComposerMessage(text: 'Fix the flaky login test in CI'),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    workspace.rename(thread, 'Login');
    generated.complete('Flaky login test');
    await tester.pump();
    expect(thread.title, 'Login');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(renames, ['Login']);
    thread.session.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a kept session keeps its title', (tester) async {
    final asked = <String>[];
    final workspace = await pumpLoaded(
      tester,
      titler: (message) async {
        asked.add(message);
        return 'Generated';
      },
    );
    await tester.tap(inSidebar(find.text('Write a.txt and read it back')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(workspace.selected.record, FakeCatalog.kept);
    expect(workspace.selected.session.itemCount, greaterThan(3));
    expect(asked, isEmpty);
    expect(workspace.selected.title, 'Write a.txt and read it back');
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

  testWidgets('what the sidebar shows is kept between runs', (tester) async {
    addTearDown(FakeCatalog.started.clear);
    FakeCatalog.started.add(
      SessionRecord(
        id: 'other',
        title: 'Another',
        updatedAt: DateTime(2026, 9, 26),
        cwd: '/tmp/other',
      ),
    );
    final store = MemoryPreferenceStore();
    var workspace = await pumpLoaded(tester, preferences: store);
    AgentThread thread(String id) =>
        workspace.threads.firstWhere((thread) => thread.record?.id == id);
    workspace
      ..setPinned(thread(FakeCatalog.kept.id), true)
      ..rename(thread(FakeCatalog.kept.id), 'Renamed')
      ..setArchived(thread('other'), true)
      ..sidebarGrouping = SidebarGrouping.time.name
      ..toggleCollapsed('today')
      ..showArchived = true;
    await tester.runAsync(() => workspace.openFolder('/tmp/opened'));

    // The next run.
    await tester.pumpWidget(const SizedBox());
    final renames = <String>[];
    workspace = await pumpLoaded(
      tester,
      preferences: store,
      kernel: titledClaude(renames),
    );
    final kept = thread(FakeCatalog.kept.id);
    expect(kept.pinned, isTrue);
    expect(kept.title, 'Renamed');
    expect(thread('other').archived, isTrue);
    expect(thread('other').pinned, isFalse);
    expect(workspace.sidebarGrouping, SidebarGrouping.time.name);
    expect(workspace.isCollapsed('today'), isTrue);
    expect(workspace.showArchived, isTrue);
    expect(
      workspace.projects.map((project) => project.path),
      contains('/tmp/opened'),
    );

    // Its CLI takes the name once running.
    workspace.select(kept);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(renames, ['Renamed']);
    kept.session.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('marks are dropped with the sessions gone, not when the '
      'catalog could not be read', (tester) async {
    final store = MemoryPreferenceStore({
      'sidebar': {
        'pinned': [FakeCatalog.kept.id, 'gone'],
        'archived': ['gone'],
        'names': {FakeCatalog.kept.id: FakeCatalog.kept.title, 'gone': 'x'},
        'folders': ['/tmp/project', '/tmp/opened'],
      },
    });
    late final KernelDescriptor failing;
    failing = KernelDescriptor(
      id: 'claude-code',
      label: 'Claude Code',
      icon: Icons.auto_awesome_rounded,
      description: '',
      catalog: _FailingCatalog(),
      create: (context) => ClaudeCodeKernel(
        failing,
        context,
        start: MockClaudeCodeTransport.start,
      ),
    );
    await pumpLoaded(tester, preferences: store, kernel: failing);
    expect((store.preferences['sidebar'] as Map)['pinned'], [
      FakeCatalog.kept.id,
      'gone',
    ]);

    await tester.pumpWidget(const SizedBox());
    await pumpLoaded(tester, preferences: store);
    final sidebar = store.preferences['sidebar'] as Map;
    expect(sidebar['pinned'], [FakeCatalog.kept.id]);
    expect(sidebar['archived'], isEmpty);
    // The catalog lists the name now: it is the CLI's.
    expect(sidebar['names'], isEmpty);
    // Listed by the catalog now.
    expect(sidebar['folders'], ['/tmp/opened']);
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

  group('the IDE', () {
    testWidgets('opens a folder apart from the chat: no agent there is '
        'listed, and the chat keeps its own', (tester) async {
      final workspace = await pumpLoaded(tester);
      final selected = workspace.selected;
      final projects = [...workspace.projects];

      workspace.openIdeFolder('/tmp/ide');
      await tester.pump();
      expect(workspace.ideFolder, '/tmp/ide');
      expect(workspace.recentFolders, ['/tmp/ide']);
      expect(workspace.projects, projects);
      expect(workspace.selected, same(selected));
      // A chat of its own there, which the sidebar does not list.
      final chat = workspace.ideChat('/tmp/ide')!;
      expect(chat.project.path, '/tmp/ide');
      expect(workspace.ideChats('/tmp/ide'), [chat]);
      expect(workspace.listsInSidebar(chat), isFalse);

      workspace.closeIdeFolder();
      expect(workspace.ideFolder, isNull);
      expect(workspace.recentFolders, ['/tmp/ide']);
    });

    testWidgets('lists a folder once an agent there is sent something', (
      tester,
    ) async {
      final workspace = await pumpLoaded(tester);
      workspace.openIdeFolder('/tmp/ide');
      final chat = workspace.ideChat('/tmp/ide')!;
      chat.session.send(const ComposerMessage(text: 'hi'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(workspace.projects.first.path, '/tmp/ide');
      expect(workspace.listsInSidebar(chat), isTrue);
      chat.session.stop();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('chats are tabs: a new one beside the shown, a closed one '
        'nothing was sent to dropped, the last replaced', (tester) async {
      final workspace = await pumpLoaded(tester);
      workspace.openIdeFolder('/tmp/ide');
      final first = workspace.ideChat('/tmp/ide')!;
      // An untouched one is reused, not another made.
      expect(workspace.newIdeChat('/tmp/ide'), same(first));

      final kept = workspace.threads.firstWhere(
        (thread) => thread.record?.id == FakeCatalog.kept.id,
      );
      workspace.openIdeChat('/tmp/ide', kept);
      expect(workspace.ideChats('/tmp/ide'), [first, kept]);
      expect(workspace.ideChat('/tmp/ide'), same(kept));

      workspace.closeIdeChat('/tmp/ide', first);
      expect(workspace.threads, isNot(contains(first)));
      expect(workspace.ideChats('/tmp/ide'), [kept]);

      // The agent goes on, out of the tabs; a new one takes their place.
      workspace.closeIdeChat('/tmp/ide', kept);
      expect(workspace.threads, contains(kept));
      final replaced = workspace.ideChats('/tmp/ide');
      expect(replaced, hasLength(1));
      expect(replaced.single.untouched, isTrue);
    });

    testWidgets("an agent opened in the IDE shows its folder, with it the "
        "chat's tab; kept between runs", (tester) async {
      final store = MemoryPreferenceStore();
      var workspace = await pumpLoaded(tester, preferences: store);
      final kept = workspace.threads.firstWhere(
        (thread) => thread.record?.id == FakeCatalog.kept.id,
      );
      final selected = workspace.selected;
      workspace
        ..openInIde(kept)
        ..addRecentFile('/tmp/project/a.txt');
      expect(workspace.layout, WorkspaceLayout.ide);
      expect(workspace.ideFolder, '/tmp/project');
      expect(workspace.ideChat('/tmp/project'), same(kept));
      expect(workspace.selected, same(selected));

      // The next run.
      await tester.pumpWidget(const SizedBox());
      workspace = await pumpLoaded(tester, preferences: store);
      expect(workspace.ideFolder, '/tmp/project');
      expect(workspace.recentFolders, ['/tmp/project']);
      expect(workspace.recentFiles, ['/tmp/project/a.txt']);
      expect(
        workspace.ideChat('/tmp/project')?.record?.id,
        FakeCatalog.kept.id,
      );

      workspace.clearRecent();
      expect(workspace.recentFolders, isEmpty);
      expect(workspace.recentFiles, isEmpty);
    });
  });
}

class _FailingCatalog implements SessionCatalog {
  @override
  Future<List<ProjectRecord>> projects() async => throw StateError('locked');

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) async => const [];

  @override
  Future<void> delete(String id) async {}
}
