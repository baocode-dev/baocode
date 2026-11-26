import 'dart:io';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/claude_storage.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/welcome.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../kernel_test.dart' show FakeCli;

/// [Welcome], in a temporary folder: the demo as exported, read from the
/// repository's assets.
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
  Future<String?> demo(String folder, String localeName) async {
    final locale = WelcomeDemo.localeFor(localeName);
    final text = File(WelcomeDemo.asset(locale)).readAsStringSync();
    final file = File(p.join(root.path, 'demo.$locale.jsonl'))
      ..writeAsStringSync(WelcomeDemo.place(text, folder));
    return file.path;
  }
}

void main() {
  late Directory root;
  late List<ClaudeLaunch> launches;
  late KernelDescriptor claude;

  setUp(() {
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

    final items = await itemsOf(demo);
    expect(items.first, isA<NoticeItem>());
    expect(items.whereType<UserMessageItem>(), hasLength(2));
    expect(items.last, isA<NoticeItem>());
    // Its paths are the user's folder's.
    final file = File(p.join(root.path, 'demo.en.jsonl')).readAsStringSync();
    expect(file, isNot(contains(WelcomeDemo.folder)));
    expect(file, contains(folder));
    expect(launches, isEmpty);
    // Nothing of it still at work.
    expect(demo.shownStatus, ThreadStatus.idle);

    // What is sent there starts a conversation of their own.
    demo.session.send(const ComposerMessage(text: 'Hello'));
    final mine = first.current!;
    expect(mine, isNot(demo));
    expect(mine.project.path, folder);
    expect(first.threads, containsAll([demo, mine]));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(launches, hasLength(1));
    expect(launches.single.resume, isNull);
    expect((await itemsOf(demo)).whereType<UserMessageItem>(), hasLength(2));
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
