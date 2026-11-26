import 'dart:io';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/images/image_tools.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/claude_core_setting.dart';
import 'package:baocode/kernel/claude_code/claude_storage.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/welcome.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../kernel_test.dart' show FakeCli;

/// [Welcome], in a temporary folder: the demo as exported, read from the
/// repository's assets, played at once.
class _Welcome extends Welcome {
  _Welcome(this.root);

  final Directory root;

  @override
  Future<String> folder() async {
    final dir = Directory(p.join(root.path, 'BaoCode'));
    await dir.create();
    return dir.path;
  }

  @override
  Future<({WelcomeRecording recording, String path})?> demo(
    String folder,
    String localeName,
  ) async {
    final locale = WelcomeDemo.localeFor(localeName);
    final (:recording, :path) = await Welcome.keep(
      File(WelcomeDemo.asset(locale)).readAsStringSync(),
      folder,
      locale,
      root.path,
    );
    return (
      recording: WelcomeRecording(
        notice: recording.notice,
        prompt: recording.prompt,
        messages: [
          for (final line in recording.messages) (at: 0, message: line.message),
        ],
      ),
      path: path,
    );
  }
}

void main() {
  late Directory root;
  late List<ClaudeLaunch> launches;
  late KernelDescriptor claude;

  setUp(() {
    // Its calls shown as pictures, with no image model, as the app has it.
    ImageTools.start();
    root = Directory.systemTemp.createTempSync('welcome');
    launches = [];
    claude = KernelDescriptor(
      id: 'claude-code',
      label: 'Claude Code',
      icon: Icons.auto_awesome_rounded,
      description: '',
      create: (context) => ClaudeCodeKernel(
        claude,
        context,
        start: (launch) async {
          launches.add(launch);
          return FakeCli();
        },
        readHistoryPage: ClaudeStorage.readPage,
      ),
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  Workspace workspace(MemoryPreferenceStore store) {
    final workspace = Workspace(
      kernels: [claude],
      preferences: store,
      welcome: _Welcome(root),
    );
    addTearDown(workspace.dispose);
    return workspace;
  }

  Future<List<ChatItem>> itemsOf(AgentThread thread) async {
    final session = thread.session;
    for (var i = 0; i < 50 && session.loadingHistory; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return [for (var i = 0; i < session.itemCount; i++) session.itemAt(i)];
  }

  test('a new user starts in their folder, on the demo', () async {
    final store = MemoryPreferenceStore();
    final first = workspace(store);
    await first.load();
    final folder = p.join(root.path, 'BaoCode');
    expect(first.projects.map((project) => project.path), [folder]);
    final demo = first.current!;
    expect(demo.id, WelcomeDemo.sessionId);
    expect(demo.title, 'Demo: a rate limiter, compared and rewritten');

    // Played as it opens.
    Future<List<ChatItem>> played(int prompts) async {
      var items = <ChatItem>[];
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        items = await itemsOf(demo);
        if (items.whereType<UserMessageItem>().length == prompts * 2 &&
            !demo.session.isStreaming &&
            items.last is NoticeItem) {
          break;
        }
      }
      return items;
    }

    var items = await played(1);
    expect(items.first, isA<NoticeItem>());
    expect(
      items
          .whereType<UserMessageItem>()
          .where((item) => item.fromAgent == null)
          .map((item) => item.text),
      [startsWith('Move our rate-limiting middleware')],
    );
    expect(items.last, isA<NoticeItem>());
    expect(
      items.whereType<ToolCallItem>().map((item) => item.tool),
      contains('WebSearch'),
    );
    // The agent and a subagent talking: its question, and the answer.
    expect(
      items.whereType<UserMessageItem>().where(
        (item) => item.fromAgent != null,
      ),
      [
        isA<UserMessageItem>().having(
          (item) => item.fromAgent,
          'from',
          'Look up the RateLimit headers',
        ),
      ],
    );
    expect(
      items.whereType<ToolCallItem>().where(
        (item) => item.kind == ToolKind.message,
      ),
      hasLength(1),
    );
    // A picture made, though there is no image model here.
    final picture = items.whereType<ToolCallItem>().singleWhere(
      (item) => item.kind == ToolKind.image,
    );
    expect(picture.images, hasLength(1));
    expect(picture.imageFiles, [p.join(folder, 'store', 'boss-fight.webp')]);
    final agents = items.whereType<AgentItem>().toList();
    expect(agents, hasLength(3));
    expect(agents.every((agent) => agent.children.isNotEmpty), isTrue);
    expect(
      agents.every((agent) => agent.status == CommandStatus.succeeded),
      isTrue,
    );
    // Paths in the user's folder; nothing of Claude Code's run.
    expect(
      items.whereType<CodeDiffItem>().map((item) => item.path),
      everyElement(startsWith(folder)),
    );
    expect(launches, isEmpty);
    expect(demo.shownStatus, ThreadStatus.idle);
    // No model set up: offered one, as a new conversation would be.
    final core = ClaudeCore.current;
    addTearDown(() => ClaudeCore.current = core);
    ClaudeCore.current = () => ClaudeCore.builtin;
    expect(demo.session.health.noModel, isTrue);
    expect(demo.session.health.noModelNote, startsWith('This is a demo.'));
    ClaudeCore.current = () => ClaudeCore.cli;
    expect(demo.session.health.noModel, isFalse);

    // Ends offering what to send next; what is sent plays it again.
    expect(demo.session.replySuggestions, hasLength(3));
    demo.session.send(const ComposerMessage(text: 'Hello'));
    items = await played(2);
    expect(first.threads, [demo]);
    expect(
      items
          .whereType<UserMessageItem>()
          .where((item) => item.fromAgent == null)
          .map((item) => item.text),
      [startsWith('Move our rate-limiting middleware'), 'Hello'],
    );
    expect(items.whereType<AgentItem>(), hasLength(6));
    expect(launches, isEmpty);
  });

  test('the demo stays listed till deleted', () async {
    final store = MemoryPreferenceStore();
    await workspace(store).load();

    final again = workspace(store);
    await again.load();
    final demo = again.threads.singleWhere(
      (thread) => thread.id == WelcomeDemo.sessionId,
    );
    again.delete(demo);
    await Future<void>.delayed(Duration.zero);

    final after = workspace(store);
    await after.load();
    expect(after.threads.where((t) => t.id == WelcomeDemo.sessionId), isEmpty);
    expect(after.projects, hasLength(1));

    // Asked for again, from the palette.
    await after.showWelcomeDemo();
    expect(after.current?.id, WelcomeDemo.sessionId);
    expect(after.projects, hasLength(1));
  });

  test('one with projects already is not shown the demo', () async {
    final elsewhere = Directory(p.join(root.path, 'code'))..createSync();
    final store = MemoryPreferenceStore({
      'sidebar': {
        'folders': [elsewhere.path],
      },
    });
    final workspace_ = workspace(store);
    await workspace_.load();
    expect(workspace_.projects.map((project) => project.path), [
      elsewhere.path,
    ]);
    expect(
      workspace_.threads.where((t) => t.id == WelcomeDemo.sessionId),
      isEmpty,
    );
    expect(store.preferences['welcomed'], isTrue);
  });
}
