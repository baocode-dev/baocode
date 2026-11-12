import 'dart:io';

import 'package:baocode/bots/bot.dart';
import 'package:baocode/bots/bot_folders.dart';
import 'package:baocode/bots/bot_groups.dart';
import 'package:baocode/bots/bots.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_sdk_tools.dart';
import 'package:baocode/kernel/claude_code/mock_claude_code_transport.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late KernelDescriptor kernel;
  kernel = KernelDescriptor(
    id: 'claude-code',
    label: 'Claude Code',
    icon: Icons.auto_awesome_rounded,
    description: '',
    create: (context) =>
        ClaudeCodeKernel(kernel, context, start: MockClaudeCodeTransport.start),
  );
  late Workspace workspace;
  late Bots bots;
  late BotGroups groups;
  late MemoryBotFolders folders;
  late DateTime now;
  late Bot mia, leo;

  /// What each bot was told in a group, in turn.
  late List<(String, String)> told;

  setUp(() async {
    final app = Directory.systemTemp.createTempSync('send-app').path;
    addTearDown(() => Directory(app).deleteSync(recursive: true));
    workspace = Workspace(kernels: [kernel], projects: [Project('app', app)]);
    folders = MemoryBotFolders();
    now = DateTime(2026, 11, 12, 14);
    bots = Bots(
      workspace: workspace,
      folders: folders,
      store: MemoryPreferenceStore(),
      chinese: true,
      clock: () => now,
      computer: () async => 'Mac',
    );
    await bots.start();
    mia = bots.save(
      name: 'Mia',
      identity: '',
      abilities: {BotAbility.proactive},
      chatOnly: true,
    );
    leo = bots.save(
      name: 'Leo',
      identity: '',
      abilities: {},
      writesFirst: false,
    );
    told = [];
    groups = bots.groups
      ..tell = (group, member, note) => told.add((member, note));
  });

  tearDown(() {
    bots.dispose();
    workspace.dispose();
  });

  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  /// What a tool of the app's called from [cwd] with [arguments] gave:
  /// its text, and whether it was an error.
  Future<({String text, bool error})> call(
    String cwd,
    String tool,
    Map<String, Object?> arguments,
  ) async {
    final result =
        (await ClaudeSdkTools.handle({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'tools/call',
              'params': {'name': tool, 'arguments': arguments},
            }, ClaudeSdkCall(cwd: cwd)))['result']
            as Map;
    return (
      text: [
        for (final part in result['content'] as List) (part as Map)['text'],
      ].join(),
      error: result['isError'] == true,
    );
  }

  test('asked in a group to write in private, a bot sends it itself: '
      'even one not let write first, while the user spoke lately; else it '
      'is told why not', () async {
    final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
    now = DateTime(2026, 11, 12, 23, 40);
    groups.send(group.id, text: '@Leo 你们每个人私发我一条消息');
    await wait(60);
    expect(groups.answering(leo.id), group.id);
    final sent = await call(leo.folder, 'bot_send', {
      'to': 'private',
      'text': '我是 Leo',
    });
    expect(sent.error, isFalse);
    expect(sent.text, contains('Sent to the user'));
    // Long after the user spoke, and Leo not let write first: told why.
    now = now.add(const Duration(minutes: 20));
    final held = await call(leo.folder, 'bot_send', {
      'to': 'private',
      'text': '还是我',
    });
    expect(held.error, isTrue);
    expect(held.text, contains('turned off Leo writing to them first'));
  });

  test('a picture from a file sent with bot_send: to a group with the '
      'message; to the group it answers, with its reply', () async {
    final dir = Directory.systemTemp.createTempSync('send-pictures');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/a.png')
      ..writeAsBytesSync([137, 80, 78, 71, 13, 10, 26, 10, 1, 2]);
    final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
    final sent = await call(mia.folder, 'bot_send', {
      'to': '江湖',
      'images': [file.path],
    });
    expect(sent.error, isFalse);
    expect(groups.messages(group.id).last.images, ['1-1.png']);
    expect(
      (await call(mia.folder, 'bot_send', {
        'to': '江湖',
        'images': ['${dir.path}/none.png'],
      })).text,
      contains('No file'),
    );
    groups.send(group.id, text: '@Mia 图呢');
    await wait(40);
    expect(groups.answering(mia.id), group.id);
    final held = await call(mia.folder, 'bot_send', {
      'to': group.id,
      'images': [file.path],
    });
    expect(held.text, contains('go with your reply'));
    groups.turnEnded(group.id, mia.id, '<bot_say>这张</bot_say>');
    expect(groups.messages(group.id).last.images, ['3-1.png']);
  });

  test(
    'saying in a group with the tool: not the one it is answering',
    () async {
      final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
      groups.send(group.id, text: '@Mia 在吗');
      await wait(40);
      expect(groups.answering(mia.id), group.id);
      expect(() => groups.say(group.id, mia.id, '在'), throwsStateError);
    },
  );
}
