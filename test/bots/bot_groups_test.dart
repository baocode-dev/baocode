import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart' show linkGroupUser;
import 'package:baocode/bots/bot.dart';
import 'package:baocode/bots/bot_folders.dart';
import 'package:baocode/bots/bot_groups.dart';
import 'package:baocode/bots/bots.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/mock_claude_code_transport.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
  late Bot mia, leo, ann;

  /// What each bot was told, in turn.
  late List<(String, String)> told;

  setUp(() async {
    final app = Directory.systemTemp.createTempSync('groups-app').path;
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
      computer: () async => 'Leo 的 MacBook',
    );
    await bots.start();
    mia = bots.save(name: 'Mia', identity: '', abilities: {}, chatOnly: true);
    leo = bots.save(name: 'Leo', identity: '', abilities: {});
    ann = bots.save(name: 'Ann', identity: '', abilities: {});
    told = [];
    groups = bots.groups
      ..quiet = const Duration(milliseconds: 5)
      ..stagger = const Duration(milliseconds: 40)
      ..tell = (group, member, note) => told.add((member, note));
  });

  tearDown(() {
    bots.dispose();
    workspace.dispose();
  });

  String name(String id) => bots.byId(id)!.name;
  List<String> toldNames() => [for (final (who, _) in told) name(who)];
  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  test('a group kept: its members those there are, named after them if '
      'not named', () {
    final group = groups.save(name: '', members: [mia.id, leo.id, 'nobody']);
    expect(group.members, [mia.id, leo.id]);
    expect(group.name, 'Mia、Leo');
    final kept = jsonDecode(
      utf8.decode(folders.files['/bots/groups/groups.json']!),
    ) as List;
    expect((kept.single as Map)['members'], [mia.id, leo.id]);
  });

  test('what is said kept, and as the bots read it: each message under its '
      'number, who and when; pictures by their files', () async {
    final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
    groups.send(
      group.id,
      text: '你们好',
      images: [
        ImageAttachment(
          bytes: Uint8List.fromList([1, 2]),
          mediaType: 'image/jpeg',
        ),
      ],
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    groups.turnEnded(
      group.id,
      mia.id,
      '<bot_say>[laughs] 嗨</bot_say><bot_narrate>她挥挥手</bot_narrate>',
    );
    final messages = groups.messages(group.id);
    expect(messages.map((m) => (m.seq, m.from)), [
      (1, linkGroupUser),
      (2, mia.id),
    ]);
    expect(messages.first.images, ['1-1.jpg']);
    expect(groups.image(group.id, '1-1.jpg')!.type, 'image/jpeg');
    expect(groups.image(group.id, '../groups.json'), isNull);
    final chat = utf8.decode(folders.files[groups.chatFile(group.id)]!);
    expect(chat, contains('# 江湖'));
    expect(chat, contains('## #1 · 用户 · 2026-11-12 14:00\n你们好\n![picture]('));
    expect(chat, contains('## #2 · Mia · 2026-11-12 14:00\n嗨\n*她挥挥手*'));
    // Kept: there again when the app starts again.
    final again = BotGroups(bots)..start();
    addTearDown(again.dispose);
    expect(again.messages(group.id), hasLength(2));
  });

  test('told once the user stops, one after another: who is called on '
      'first, then who is named, then the quietest', () async {
    final group = groups.save(name: 'g', members: [mia.id, leo.id, ann.id]);
    groups.send(group.id, text: '在吗');
    groups.send(group.id, text: '@Ann 你先说，Leo 也听听');
    await wait(20);
    // At once, the one called on; not yet the others.
    expect(toldNames(), ['Ann']);
    expect(told.single.$2, contains('#1–#2'));
    expect(told.single.$2, contains('You were called on'));
    await wait(110);
    expect(toldNames(), ['Ann', 'Leo', 'Mia']);
  });

  test('a reply sent once done; the others told of it, while the user\'s '
      'turn lets the bots say more', () async {
    final group = groups.save(name: 'g', members: [mia.id, leo.id]);
    groups.send(group.id, text: '@Mia 你好');
    await wait(20);
    expect(toldNames(), ['Mia']);
    groups.turnEnded(group.id, mia.id, '<bot_say>你好呀</bot_say>');
    await wait(80);
    // Leo, woken by the user's words, then told of Mia's too: once.
    expect(toldNames().where((n) => n == 'Leo'), hasLength(1));
    expect(groups.messages(group.id).last.text, '<bot_say>你好呀</bot_say>');
  });

  test('a reply held if the group went on while it wrote: told what came, '
      'to send it or not', () async {
    final group = groups.save(name: 'g', members: [mia.id, leo.id]);
    groups.send(group.id, text: '@Mia @Leo 嗨');
    await wait(80);
    expect(toldNames(), unorderedEquals(['Mia', 'Leo']));
    told.clear();
    groups.turnEnded(group.id, leo.id, '<bot_say>嗨嗨</bot_say>');
    told.clear();
    // Mia wrote the same meanwhile: held, told of Leo's.
    groups.turnEnded(group.id, mia.id, '<bot_say>嗨</bot_say>');
    expect(groups.messages(group.id), hasLength(2));
    expect(toldNames(), ['Mia']);
    expect(told.single.$2, contains('Your reply is held'));
    // Its answer then: sent.
    groups.turnEnded(group.id, mia.id, '<bot_say>Leo 说得对</bot_say>');
    expect(groups.messages(group.id).last.from, mia.id);
  });

  test('the bots say so much, then wait for the user', () async {
    groups.budget = 2;
    final group = groups.save(name: 'g', members: [mia.id, leo.id]);
    groups.send(group.id, text: '聊聊');
    await wait(100);
    groups.turnEnded(group.id, mia.id, '<bot_say>一</bot_say>');
    await wait(60);
    groups.turnEnded(group.id, leo.id, '<bot_say>二</bot_say>');
    told.clear();
    await wait(100);
    // None left: no one told of Leo's.
    expect(told, isEmpty);
    groups.send(group.id, text: '继续');
    await wait(100);
    expect(toldNames(), unorderedEquals(['Mia', 'Leo']));
  });

  test('one that keeps quiet is told less, till called on', () async {
    groups.lurk = 2;
    final group = groups.save(name: 'g', members: [mia.id]);
    for (var i = 0; i < 2; i++) {
      groups.send(group.id, text: 'x$i');
      await wait(30);
      groups.turnEnded(group.id, mia.id, '');
    }
    told.clear();
    groups.send(group.id, text: 'x');
    await wait(30);
    groups.send(group.id, text: 'y');
    await wait(30);
    expect(told, isEmpty);
    // The third time: told.
    groups.send(group.id, text: 'z');
    await wait(30);
    expect(toldNames(), ['Mia']);
    groups.turnEnded(group.id, mia.id, '');
    told.clear();
    groups.send(group.id, text: '@Mia 在吗');
    await wait(30);
    expect(toldNames(), ['Mia']);
  });

  test('a bot\'s conversation of a group: told of the group with who it '
      'is, its chat read even if it only chats; not the sidebar\'s', () {
    final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
    final path = BotGroups.memberFolder(mia, group.id);
    expect(bots.botAt(path)?.id, mia.id);
    final setup = workspace.agentSetup!(path)!.workspace();
    expect(setup.instructions, contains('Your name is Mia.'));
    expect(setup.instructions, contains('<group_chat>'));
    expect(setup.instructions, contains('"江湖"'));
    expect(setup.instructions, contains('- Leo'));
    expect(setup.instructions, contains(groups.chatFile(group.id)));
    expect(setup.tools, contains('Read'));
    // Its own chat: no group in it.
    final own = workspace.agentSetup!(mia.folder)!.workspace();
    expect(own.instructions, isNot(contains('<group_chat>')));
    expect(own.tools, isNot(contains('Read')));
  });

  test('deleted: its messages and its bots\' conversations of it gone; a '
      'bot deleted leaves its groups', () {
    final group = groups.save(name: 'g', members: [mia.id, leo.id]);
    groups.send(group.id, text: 'hi');
    bots.delete(leo.id);
    expect(groups.byId(group.id)!.members, [mia.id]);
    groups.delete(group.id);
    expect(groups.groups, isEmpty);
    expect(
      folders.files.keys.where(
        (k) => p.isWithin('/bots/groups/${group.id}', k),
      ),
      isEmpty,
    );
  });
}
