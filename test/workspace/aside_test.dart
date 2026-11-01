// /btw: a question asked in a conversation of its own beside another,
// copied from all of that one so far and told it was asked on the side;
// listed under it in the sidebar, a card in it where it was copied up to,
// shown in its place, and detached, deleted or kept with it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_markdown/bao_markdown.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer_controller.dart';
import 'package:baocode/chat/widgets/agent_step.dart';
import 'package:baocode/ide/ide_list.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/mock_claude_code_transport.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/main.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _history = 'test/fixtures/claude_code/history.jsonl';

class _Catalog implements SessionCatalog {
  static final kept = SessionRecord(
    id: 'eafc328b-0000-4000-8000-000000000001',
    title: 'Write a.txt and read it back',
    updatedAt: DateTime(2026, 9, 27, 16),
    cwd: '/tmp/project',
    path: _history,
  );

  /// The copies made, kept as Claude Code keeps sessions: listed after.
  static final List<SessionRecord> forks = [];

  static final List<String> deleted = [];

  @override
  Future<List<ProjectRecord>> projects() async => [
    ProjectRecord(path: '/tmp/project', sessions: [kept, ...forks]),
  ];

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) async => const [];

  @override
  Future<void> delete(String id) async => deleted.add(id);
}

/// What each CLI started was sent, the last started's last.
final List<List<Map<String, Object?>>> _sent = [];

/// The mock CLI, what it is sent recorded; resumed, it tells the id it
/// was resumed by, as Claude Code does (the mock has one of its own).
class _Recording implements ClaudeCodeTransport {
  _Recording(this._cli, this._resumed) {
    _sent.add(written);
  }

  final ClaudeCodeTransport _cli;
  final String? _resumed;
  final List<Map<String, Object?>> written = [];

  @override
  Stream<Map<String, Object?>> get messages => _cli.messages.map(
    (message) => switch (_resumed) {
      final id? when message.containsKey('session_id') => {
        ...message,
        'session_id': id,
      },
      _ => message,
    },
  );

  @override
  void write(Map<String, Object?> message) {
    written.add(message);
    _cli.write(message);
  }

  @override
  void close() => _cli.close();

  @override
  Future<void> get exited => _cli.exited;
}

final KernelDescriptor _claude = KernelDescriptor(
  id: 'claude-code',
  label: 'Claude Code',
  icon: Icons.auto_awesome_rounded,
  description: '',
  catalog: _Catalog(),
  create: (context) => ClaudeCodeKernel(
    _claude,
    context,
    start: (launch) async =>
        _Recording(await MockClaudeCodeTransport.start(launch), launch.resume),
    readHistory: (session) async => [
      for (final line in File(session.path!).readAsLinesSync())
        if (line.isNotEmpty) (jsonDecode(line) as Map).cast<String, Object?>(),
    ],
    forkSession: (cwd, id, into, {before, title}) async {
      _Catalog.forks.add(
        SessionRecord(
          id: into,
          title: title ?? '',
          updatedAt: DateTime(2026, 9, 28),
          cwd: cwd,
          path: _history,
        ),
      );
      return _history;
    },
  ),
);

Future<Workspace> _pumpLoaded(
  WidgetTester tester, {
  PreferenceStore? preferences,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final workspace = Workspace(kernels: [_claude], preferences: preferences);
  await tester.pumpWidget(BaoCodeApp(workspace: workspace));
  await tester.runAsync(workspace.load);
  await tester.pump();
  return workspace;
}

Finder _inSidebar(Finder finder) =>
    find.descendant(of: find.byType(Sidebar), matching: finder);

/// The kept conversation, shown and its history read.
Future<AgentThread> _showKept(WidgetTester tester, Workspace workspace) async {
  final kept = workspace.threads.firstWhere(
    (thread) => thread.record?.id == _Catalog.kept.id,
  );
  workspace.select(kept);
  for (var i = 0; i < 20 && kept.session.forkEndsAt == null; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  return kept;
}

Future<AgentThread> _askBeside(
  WidgetTester tester,
  Workspace workspace,
  AgentThread from,
  String question,
) async {
  final aside = await tester.runAsync(
    () => workspace.askBeside(from, ComposerMessage(text: question)),
  );
  await tester.pump();
  return aside!;
}

/// Stops every agent, its timers run out.
Future<void> _stopAll(WidgetTester tester, Workspace workspace) async {
  for (final thread in workspace.threads) {
    if (thread.isOpen) thread.session.stop();
  }
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  tearDown(() {
    _Catalog.forks.clear();
    _Catalog.deleted.clear();
    _sent.clear();
  });

  testWidgets('/btw asks in a copy of the conversation, told it is on the '
      'side; listed under it, a card in it where it was copied up to', (
    tester,
  ) async {
    final workspace = await _pumpLoaded(tester);
    final kept = await _showKept(tester, workspace);
    final endsAt = kept.session.forkEndsAt;
    expect(endsAt, isNotNull);

    final aside = await _askBeside(
      tester,
      workspace,
      kept,
      'Which file was it?\nThe one written.',
    );
    expect(workspace.parentOf(aside), same(kept));
    expect(workspace.asidesOf(kept), [same(aside)]);
    expect(workspace.asidesAt(kept).keys, [endsAt]);
    expect(aside.title, 'Which file was it?');
    // Its choices are its parent's; not shown: the parent still is.
    expect(workspace.current, same(kept));

    // Sent the question, with the note before it.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    final user = _sent.last.lastWhere((message) => message['type'] == 'user');
    final content = (user['message']! as Map)['content']! as List;
    expect(
      content.map((block) => (block as Map)['text']),
      containsAllInOrder([
        Workspace.asideNote,
        'Which file was it?\nThe one written.',
      ]),
    );
    // After what it copied, read before it was asked; the note not shown.
    final asked = [
      for (var i = 0; i < aside.session.itemCount; i++)
        if (aside.session.itemAt(i) case UserMessageItem(:final text)) text,
    ];
    expect(asked.length, greaterThan(1));
    expect(asked.last, 'Which file was it?\nThe one written.');

    // Under it in the sidebar, once.
    await tester.pump();
    expect(_inSidebar(find.text('Which file was it?')), findsOneWidget);
    final parentRow = tester.getTopLeft(
      _inSidebar(find.text(kept.localizedTitle(englishLocalizations))),
    );
    final asideRow = tester.getTopLeft(
      _inSidebar(find.text('Which file was it?')),
    );
    expect(asideRow.dy, greaterThan(parentRow.dy));
    expect(asideRow.dx, greaterThan(parentRow.dx));

    // Its card in the conversation, a subagent's.
    expect(
      find.widgetWithText(AgentStep, 'Which file was it?'),
      findsOneWidget,
    );
    await _stopAll(tester, workspace);
  });

  testWidgets('an aside shows in place of its parent, the way back over '
      'it; an aside of an aside is listed under the same parent', (
    tester,
  ) async {
    final workspace = await _pumpLoaded(tester);
    final kept = await _showKept(tester, workspace);
    final aside = await _askBeside(tester, workspace, kept, 'First aside');

    // From its card.
    await tester.tap(find.widgetWithText(AgentStep, 'First aside'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(workspace.current, same(aside));
    expect(workspace.grid.contains(aside), isTrue);
    expect(workspace.grid.contains(kept), isFalse);

    // Asked from the aside: beside the same parent.
    for (var i = 0; i < 20 && aside.session.forkEndsAt == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    final second = await _askBeside(tester, workspace, aside, 'Second aside');
    expect(workspace.parentOf(second), same(kept));
    expect(workspace.asidesOf(kept), [same(aside), same(second)]);
    expect(workspace.asidesAt(aside), isNotEmpty);

    // Back.
    final title = kept.localizedTitle(englishLocalizations);
    await tester.tap(find.text(title).last);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(workspace.current, same(kept));
    expect(workspace.grid.contains(kept), isTrue);
    expect(workspace.grid.contains(aside), isFalse);
    await _stopAll(tester, workspace);
  });

  testWidgets('Esc goes back from an aside, from its input while it has '
      'nothing typed', (tester) async {
    final workspace = await _pumpLoaded(tester);
    final kept = await _showKept(tester, workspace);
    final aside = await _askBeside(tester, workspace, kept, 'Esc aside');
    await _stopAll(tester, workspace);
    await tester.tap(find.widgetWithText(AgentStep, 'Esc aside'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(workspace.current, same(aside));

    // Something typed: the key is the input's.
    final editor = tester.widget<MarkdownEditor>(
      find.byType(MarkdownEditor).last,
    );
    final controller = editor.controller as ComposerController;
    void type(String text) => controller.replace(
      0,
      controller.length,
      text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    type('half a question');
    editor.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(workspace.current, same(aside));

    type('');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(workspace.current, same(kept));
    expect(workspace.grid.contains(kept), isTrue);
    await _stopAll(tester, workspace);
  });

  testWidgets('a conversation folds its asides in the sidebar, but the one '
      'shown; kept folded between runs', (tester) async {
    final store = MemoryPreferenceStore();
    var workspace = await _pumpLoaded(tester, preferences: store);
    final kept = await _showKept(tester, workspace);
    final first = await _askBeside(tester, workspace, kept, 'Folded first');
    await _askBeside(tester, workspace, kept, 'Folded second');
    await _stopAll(tester, workspace);
    final title = kept.localizedTitle(englishLocalizations);
    final parentRow = _inSidebar(
      find.ancestor(of: find.text(title), matching: find.byType(IdeListRow)),
    ).first;

    // Its arrow, hovered.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(parentRow));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: parentRow,
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
    );
    await tester.pump();
    expect(workspace.asidesFolded(kept), isTrue);
    expect(_inSidebar(find.text('Folded first')), findsNothing);
    expect(_inSidebar(find.text('Folded second')), findsNothing);

    // The one shown is listed still.
    workspace.select(first);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(_inSidebar(find.text('Folded first')), findsOneWidget);
    expect(_inSidebar(find.text('Folded second')), findsNothing);
    await _stopAll(tester, workspace);

    // The next run, unfolded by its tag.
    await mouse.moveTo(const Offset(900, 450));
    await tester.pumpWidget(const SizedBox());
    workspace = await _pumpLoaded(tester, preferences: store);
    final again = workspace.threads.firstWhere(
      (thread) => thread.id == kept.id,
    );
    expect(workspace.asidesFolded(again), isTrue);
    await tester.tap(_inSidebar(find.text('2')));
    await tester.pump();
    expect(workspace.asidesFolded(again), isFalse);
    expect(_inSidebar(find.text('Folded second')), findsOneWidget);
    await _stopAll(tester, workspace);
  });

  testWidgets('detached, an aside is a conversation of its own; deleted, '
      'a parent takes its asides with it', (tester) async {
    final workspace = await _pumpLoaded(tester);
    final kept = await _showKept(tester, workspace);
    final detached = await _askBeside(tester, workspace, kept, 'Detached');
    final deleted = await _askBeside(tester, workspace, kept, 'Deleted');

    workspace.detach(detached);
    expect(workspace.parentOf(detached), isNull);
    expect(workspace.asidesOf(kept), [same(deleted)]);
    expect(workspace.asidesAt(kept).values.expand((a) => a), [same(deleted)]);

    // Shown, it gives way to its parent once archived.
    workspace.select(deleted);
    await tester.pump();
    workspace.setArchived(deleted, true);
    expect(workspace.current, same(kept));
    workspace.setArchived(deleted, false);

    workspace.delete(kept);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(workspace.threads, isNot(contains(deleted)));
    expect(workspace.threads, contains(detached));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(_Catalog.deleted, containsAll([kept.id, deleted.id]));
    expect(_Catalog.deleted, isNot(contains(detached.id)));
    await _stopAll(tester, workspace);
  });

  testWidgets('asides are kept between runs', (tester) async {
    final store = MemoryPreferenceStore();
    var workspace = await _pumpLoaded(tester, preferences: store);
    final kept = await _showKept(tester, workspace);
    final at = kept.session.forkEndsAt;
    final aside = await _askBeside(tester, workspace, kept, 'Kept aside');
    final id = aside.id;
    await _stopAll(tester, workspace);

    // The next run.
    await tester.pumpWidget(const SizedBox());
    workspace = await _pumpLoaded(tester, preferences: store);
    AgentThread thread(String? id) =>
        workspace.threads.firstWhere((thread) => thread.id == id);
    expect(workspace.parentOf(thread(id)), same(thread(_Catalog.kept.id)));
    expect(workspace.asidesAt(thread(_Catalog.kept.id)).keys, [at]);
    await _stopAll(tester, workspace);
  });
}
