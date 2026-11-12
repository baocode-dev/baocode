import 'dart:convert';
import 'dart:io';

import 'package:baocode/bots/bot.dart';
import 'package:baocode/bots/bot_folders.dart';
import 'package:baocode/bots/bot_groups.dart';
import 'package:baocode/bots/bot_world.dart';
import 'package:baocode/bots/bots.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
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

  /// What each bot was told in a group, in turn; what the world was told;
  /// who was moved to write to the user.
  late List<(String, String)> told;
  late List<String> worldTold;
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
    leo = bots.save(name: 'Leo', identity: '', abilities: {});
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
      ..tell = worldTold.add
      ..reached = (bot, note) => reached.add((bot.name, note));
  });

  tearDown(() {
    bots.dispose();
    workspace.dispose();
  });

  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));
  List<String> toldNames() => [
    for (final (who, _) in told) bots.byId(who)!.name,
  ];

  test('its reply read: its acts, by names or ids, durations as said; '
      'those of no one known left out', () {
    final acts = WorldActs.parse(
      '<state who="Mia">在午睡，有点烦</state>\n'
      '<wake who="Leo" group="g1" after="40s">Mia 说他错了</wake>\n'
      '<wake who="Nobody" group="g1">x</wake>\n'
      '<reach who="${mia.id}" after="2h">答应三点汇报</reach>\n'
      '<next_look after="30m"/>',
      who: (name) =>
          bots.byId(name) ?? bots.bots.where((b) => b.name == name).firstOrNull,
    );
    expect(acts, hasLength(4));
    final state = acts[0] as WorldState;
    expect((state.who, state.text), (mia.id, '在午睡，有点烦'));
    final wake = acts[1] as WorldWake;
    expect(
      (wake.who, wake.group, wake.after, wake.why),
      (leo.id, 'g1', const Duration(seconds: 40), 'Mia 说他错了'),
    );
    final reach = acts[2] as WorldReach;
    expect((reach.who, reach.after), (mia.id, const Duration(hours: 2)));
    expect((acts[3] as WorldLook).after, const Duration(minutes: 30));
    expect(WorldActs.duration('5'), const Duration(seconds: 5));
    expect(WorldActs.duration('1.5m'), const Duration(seconds: 90));
    expect(WorldActs.duration('soon'), isNull);
  });

  test('off without a model: the app\'s own rules', () async {
    world.modelOf = () => null;
    final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
    groups.send(group.id, text: '你们好');
    await wait(120);
    expect(worldTold, isEmpty);
    expect(told, isNotEmpty);
  });

  test('a group\'s message told the world, who says who answers and when: '
      'only them, told why; the one called on told at once', () async {
    final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
    groups.send(group.id, text: '@Mia 在吗');
    await wait(40);
    // Called on: told at once, the world or not.
    expect(toldNames(), ['Mia']);
    expect(worldTold, hasLength(1));
    expect(worldTold.single, contains('Now: '));
    expect(worldTold.single, contains('- Mia: (nothing said yet)'));
    expect(worldTold.single, contains('In the group "江湖" (group ${group.id}'));
    expect(worldTold.single, contains('@Mia 在吗'));
    world.answered(
      '<state who="Leo">在加班，烦躁</state>'
      '<wake who="Leo" group="${group.id}" after="0s">用户在群里问人</wake>',
    );
    await wait(20);
    expect(toldNames(), ['Mia', 'Leo']);
    expect(told.last.$2, contains('Why you read it now: 用户在群里问人.'));
    expect(told.last.$2, contains('How they are now: You: 在加班，烦躁.'));
    // Decided: the rules not called on after it.
    await wait(200);
    expect(toldNames(), ['Mia', 'Leo']);
    // How everyone is, kept.
    final kept = utf8.decode(folders.files[world.nowFile]!);
    expect(kept, contains('- Leo: 在加班，烦躁 (14:00)'));
  });

  test('the world says nothing in time: the app\'s rules', () async {
    final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
    groups.send(group.id, text: '大家好');
    await wait(60);
    expect(worldTold, hasLength(1));
    expect(told, isEmpty);
    await wait(200);
    expect(told, isNotEmpty);
  });

  test(
    'a reply with nothing in it (an error) leaves it to the rules too',
    () async {
      final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
      groups.send(group.id, text: '大家好');
      await wait(40);
      world.answered('API Error: overloaded');
      await wait(200);
      expect(told, isNotEmpty);
    },
  );

  test('one moved to write first: by day, if it may, not past the day\'s '
      'count', () async {
    world.answered('<reach who="Leo" after="0s">x</reach>');
    for (var i = 0; i < 4; i++) {
      world.answered('<reach who="Mia" after="0s">答应三点汇报</reach>');
    }
    await wait(20);
    // Leo may not write first; Mia so many times a day.
    expect(
      [for (final (who, _) in reached) who],
      [for (var i = 0; i < BotWorld.reachesADay; i++) 'Mia'],
    );
    expect(reached.first.$2, contains('答应三点汇报'));
    // At night, no one.
    reached.clear();
    now = DateTime(2026, 11, 13, 23, 30);
    world.answered('<reach who="Mia" after="0s">想他了</reach>');
    await wait(20);
    expect(reached, isEmpty);
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
