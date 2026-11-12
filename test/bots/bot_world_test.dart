import 'dart:io';

import 'package:baocode/bots/bot.dart';
import 'package:baocode/bots/bot_folders.dart';
import 'package:baocode/bots/bot_groups.dart';
import 'package:baocode/bots/bot_world.dart';
import 'package:baocode/bots/bots.dart';
import 'package:baocode/chat/chat_session.dart';
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
  late BotWorld world;
  late MemoryBotFolders folders;
  late DateTime now;
  late Bot mia, leo;

  /// What each bot was told in a group, in turn; what the world was sent
  /// (the user's words, the app's reminder); who was moved to write to the
  /// user.
  late List<(String, String)> told;
  late List<({String said, String reminder})> worldTold;
  late List<(String, String)> reached;

  setUp(() async {
    final app = Directory.systemTemp.createTempSync('world-app').path;
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
    worldTold = [];
    reached = [];
    groups = bots.groups
      ..quiet = const Duration(milliseconds: 5)
      ..stagger = const Duration(milliseconds: 20)
      ..tell = (group, member, note) => told.add((member, note));
    world = bots.world
      ..modelOf = (() => '@up/world')
      ..gather = const Duration(milliseconds: 5)
      ..lazily = const Duration(milliseconds: 5)
      ..waitFor = const Duration(milliseconds: 150)
      ..tell = ((said, reminder) =>
          worldTold.add((said: said, reminder: reminder)))
      ..reached = (bot, note) => reached.add((bot.name, note));
  });

  tearDown(() {
    bots.dispose();
    workspace.dispose();
  });

  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  /// What the world was sent of the groups (not of WORLD.md alone).
  List<({String said, String reminder})> asked() => [
    for (final told in worldTold)
      if (told.reminder.contains('- In "')) told,
  ];
  List<String> toldNames() => [
    for (final (who, _) in told) bots.byId(who)!.name,
  ];

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

  Future<({String text, bool error})> wake(
    String who,
    String where, {
    String after = '0s',
    String why = 'x',
  }) => call(world.folder!, BotWorld.wakeTool, {
    'who': who,
    'where': where,
    'after': after,
    'why': why,
  });

  test('how long a wake is put off, as it says', () {
    expect(BotWorld.duration('5'), const Duration(seconds: 5));
    expect(BotWorld.duration('40s'), const Duration(seconds: 40));
    expect(BotWorld.duration('1.5m'), const Duration(seconds: 90));
    expect(BotWorld.duration('2h'), const Duration(hours: 2));
    expect(BotWorld.duration('soon'), isNull);
  });

  test('its tool for it alone; Read and its tool its only ones', () {
    expect(bots.offersTool(world.folder!, BotWorld.wakeTool), isTrue);
    expect(bots.offersTool(world.folder!, 'bot_send'), isFalse);
    expect(bots.offersTool(mia.folder, BotWorld.wakeTool), isFalse);
    expect(bots.offersTool('/some/project', BotWorld.wakeTool), isFalse);
  });

  test('off without a model: the app\'s own rules', () async {
    world.modelOf = () => null;
    final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
    groups.send(group.id, text: '你们好');
    await wait(120);
    expect(worldTold, isEmpty);
    expect(told, isNotEmpty);
  });

  test('the user\'s words in a group said to the world, the rest a reminder '
      'of where it is; it wakes whom it will, each told why', () async {
    final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
    groups.send(group.id, text: '@Mia 在吗');
    await wait(40);
    // Called on: told at once, the world or not.
    expect(toldNames(), ['Mia']);
    expect(asked(), hasLength(1));
    final first = asked().single;
    expect(first.said, '@Mia 在吗');
    expect(first.reminder, contains('Now: Thursday 2026-11-12 14:00.'));
    expect(first.reminder, contains('said to you'));
    expect(
      first.reminder,
      contains(
        '- In "江湖" (group ${group.id}; its chat: ${groups.chatFile(group.id)}, lines ',
      ),
    );
    expect(first.reminder, contains('#1 用户 (the words above)'));
    expect(first.reminder, contains('"江湖" may have'));
    final woken = await wake('Leo', group.id, why: '板板在群里问人');
    expect(woken.error, isFalse);
    expect(woken.text, contains('Waking Leo in "江湖"'));
    await wait(20);
    expect(toldNames(), ['Mia', 'Leo']);
    expect(told.last.$2, contains('Why you read it now: 板板在群里问人.'));
    // Decided: the rules not called on after it, the turn done.
    world.ended();
    await wait(200);
    expect(toldNames(), ['Mia', 'Leo']);
  });

  test('woken already: said so, when', () async {
    final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
    groups.send(group.id, text: '大家好');
    await wait(30);
    expect((await wake('Leo', '江湖', after: '30s')).text, contains('Waking'));
    final again = await wake('Leo', group.id);
    expect(again.text, contains('already'));
    groups.send(group.id, text: '还有人吗');
    await wait(30);
    // A new message of the user's: what was to be is no more.
    expect(worldTold.last.reminder, isNot(contains('To be woken already')));
    await wake('Leo', group.id, after: '30s', why: '板板又问');
    world.note('- Mia read "江湖" and kept quiet.');
    await wait(30);
    expect(worldTold.last.said, isEmpty);
    expect(worldTold.last.reminder, contains('To be woken already:'));
    expect(
      worldTold.last.reminder,
      contains('- Leo in "江湖" at 14:00:30 (板板又问).'),
    );
  });

  test('a wake that does not go: told why', () async {
    final group = groups.save(name: '江湖', members: [mia.id]);
    groups.send(group.id, text: '你好');
    await wait(30);
    final outsider = await wake('Leo', group.id);
    expect(outsider.error, isTrue);
    expect(outsider.text, contains('not in "江湖"'));
    expect((await wake('Nobody', group.id)).text, contains('No one'));
    expect((await wake('Mia', 'nowhere')).text, contains('No group'));
    expect(
      (await wake('Mia', group.id, after: 'soon')).text,
      contains('not a time'),
    );
  });

  test('asked of everyone: each told in turn, the world or not', () async {
    final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
    groups.send(group.id, text: '每个人给我私发一条消息');
    await wait(60);
    expect(toldNames(), ['Mia', 'Leo']);
    expect(told.last.$2, contains('asked everyone'));
  });

  test('the world says nothing in time: the app\'s rules', () async {
    final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
    groups.send(group.id, text: '大家好');
    await wait(60);
    expect(asked(), hasLength(1));
    expect(told, isEmpty);
    await wait(200);
    expect(told, isNotEmpty);
  });

  test('its turn ends in an error: the app\'s rules; ends waking no one: '
      'no one', () async {
    final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
    groups.send(group.id, text: '大家好');
    await wait(40);
    world.ended(failed: true);
    await wait(200);
    expect(told, isNotEmpty);

    told.clear();
    groups.send(group.id, text: '收到');
    await wait(40);
    world.ended();
    await wait(200);
    expect(told, isEmpty);
  });

  test('a chat in private, and WORLD.md changed: where, told lazily', () async {
    final file = bots.timelineFile(mia);
    world.private(mia, file, 7);
    world.private(mia, file, 9);
    groups.save(name: '江湖', members: [mia.id, leo.id]);
    await wait(30);
    final reminder = worldTold.last.reminder;
    expect(
      reminder,
      contains('- 用户 and Mia, in private: from line 7 of $file.'),
    );
    expect(reminder, contains('WORLD.md changed'));
  });

  test('reminded who is at work, and where', () async {
    final session = bots.threadFor(mia).session;
    session.send(const ComposerMessage(text: '在吗'));
    for (var i = 0; i < 300 && !session.isStreaming; i++) {
      await wait(10);
    }
    world.note('- Leo read "江湖" and kept quiet.');
    await wait(30);
    expect(
      worldTold.last.reminder,
      contains('At work now:\n- Mia, in private with 用户 since '),
    );
    session.stop();
  });

  test('woken in private: if it may write first, at any hour', () async {
    now = DateTime(2026, 11, 13, 23, 30);
    final refused = await wake('Leo', BotWorld.inPrivate);
    expect(refused.error, isTrue);
    expect(refused.text, contains('turned off Leo writing to them first'));
    final sent = await wake('Mia', BotWorld.inPrivate, why: '答应三点汇报');
    expect(sent.text, contains('Waking Mia in private'));
    await wait(20);
    expect([for (final (who, _) in reached) who], ['Mia']);
    expect(reached.first.$2, contains('答应三点汇报'));
  });

  test('asked in a group to write in private, a bot sends it itself: '
      'even one not let write first, while the user spoke lately; else it '
      'is told why not', () async {
    final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
    now = DateTime(2026, 11, 12, 23, 40);
    groups.send(group.id, text: '你们每个人私发我一条消息');
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
    final dir = Directory.systemTemp.createTempSync('world-pictures');
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
