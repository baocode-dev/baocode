import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart' show linkGroupUser;
import 'package:baocode/bots/bot.dart';
import 'package:baocode/bots/bot_folders.dart';
import 'package:baocode/bots/bot_groups.dart';
import 'package:baocode/bots/bot_prompt.dart' show botEventMessage;
import 'package:baocode/bots/bots.dart';
import 'package:baocode/link/chat_codec.dart';
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
    // Looked at in 10ms at full attention, 160ms at none; as worked out.
    groups = bots.groups
      ..glance = const Duration(milliseconds: 10)
      ..glanceSpan = 16
      ..random = null
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

  BotAttention attentionOf(String group, Bot bot) =>
      groups.attention(group).firstWhere((a) => a.member == bot.id);

  test('pulled by what the user says, each looks soon; called on, at '
      'once; the rest overhear', () async {
    final group = groups.save(name: 'g', members: [mia.id, leo.id, ann.id]);
    groups.send(group.id, text: '@Ann 你先说');
    await wait(5);
    expect(toldNames(), ['Ann']);
    expect(told.single.$2, contains('You were called on'));
    expect(attentionOf(group.id, ann).value, 1);
    expect(attentionOf(group.id, ann).why, '被用户 @（#1）');
    // Half as pulled: in 40ms.
    final mias = attentionOf(group.id, mia);
    expect(mias.value, 0.5);
    expect(mias.why, '旁听：用户 @ 了别人（#1）');
    expect(mias.glance, isNotNull);
    await wait(70);
    expect(toldNames(), unorderedEquals(['Ann', 'Mia', 'Leo']));
    expect(attentionOf(group.id, mia).glance, isNull);
  });

  test('asked of everyone: each at once', () async {
    final group = groups.save(name: 'g', members: [mia.id, leo.id]);
    groups.send(group.id, text: '所有人报个到');
    await wait(5);
    expect(toldNames(), unorderedEquals(['Mia', 'Leo']));
    expect(attentionOf(group.id, leo).why, '用户叫了所有人（#1）');
  });

  test('what a bot says pulls the others as warm as its group is lively, '
      'of what it answered; one at work reads it once done', () async {
    final group = groups.save(name: 'g', members: [mia.id, leo.id]);
    groups.send(group.id, text: '@Mia 你好');
    await wait(5);
    expect(toldNames(), ['Mia']);
    groups.turnEnded(group.id, mia.id, '<bot_say>你好呀</bot_say>');
    final leos = attentionOf(group.id, leo);
    expect(leos.value, closeTo(0.6, 1e-9));
    expect(leos.why, 'Mia说话了（#2，热度 0.60）');
    await wait(60);
    // Told of both at once.
    expect(toldNames(), ['Mia', 'Leo']);
    expect(told.last.$2, contains('#1–#2'));
    // Mia, called on before, still all attention: looks in 10ms.
    groups.turnEnded(group.id, leo.id, '<bot_say>嗨</bot_say>');
    expect(attentionOf(group.id, mia).value, 1);
    expect(attentionOf(group.id, mia).glance, isNotNull);
    await wait(30);
    expect(toldNames(), ['Mia', 'Leo', 'Mia']);
    // Less lively now: her answer to Leo's 0.6 is 0.18, too faint to pull.
    groups
      ..setLively(group.id, 0.3)
      ..faint = 0.2
      ..turnEnded(group.id, mia.id, '<bot_say>聊啥</bot_say>');
    expect(attentionOf(group.id, leo).glance, isNull);
    expect(groups.byId(group.id)!.lively, 0.3);
  });

  test('bots answering bots fade out', () async {
    final group = groups.save(name: 'g', members: [mia.id, leo.id]);
    var n = 0;
    groups.tell = (group, member, note) {
      told.add((member, note));
      // Each answers what it is told, a moment after.
      Timer(const Duration(milliseconds: 2), () {
        groups.turnEnded(group, member, '<bot_say>${n++}</bot_say>');
      });
    };
    groups.send(group.id, text: '聊聊');
    await wait(900);
    final said = groups.messages(group.id).length;
    // They talked among themselves a while, then stopped.
    expect(said, greaterThan(4));
    await wait(300);
    expect(groups.messages(group.id).length, said);
  });

  test(
    'one that keeps quiet is pulled less each time, till called on',
    () async {
      final group = groups.save(name: 'g', members: [mia.id]);
      for (var i = 0; i < 4; i++) {
        groups.send(group.id, text: 'x$i');
        await wait(150);
        expect(told, hasLength(i + 1));
        groups.turnEnded(group.id, mia.id, '');
      }
      expect(attentionOf(group.id, mia).why, '看了没说话（连续 4 次）');
      // A sixteenth as pulled: too faint.
      groups.send(group.id, text: 'y');
      await wait(200);
      expect(told, hasLength(4));
      groups.send(group.id, text: '@Mia 在吗');
      await wait(5);
      expect(told, hasLength(5));
      expect(told.last.$2, contains('#5–#6'));
    },
  );

  test('replies that crossed: each sent as it is; each reads the other\'s '
      'once done', () async {
    final group = groups.save(name: 'g', members: [mia.id, leo.id]);
    groups.send(group.id, text: '@Mia @Leo 嗨');
    await wait(5);
    expect(toldNames(), unorderedEquals(['Mia', 'Leo']));
    told.clear();
    groups.turnEnded(group.id, leo.id, '<bot_say>嗨嗨</bot_say>');
    // Mia wrote hers meanwhile: sent too, not held.
    groups.turnEnded(group.id, mia.id, '<bot_say>嗨</bot_say>');
    expect(
      [for (final message in groups.messages(group.id)) message.text],
      ['@Mia @Leo 嗨', '<bot_say>嗨嗨</bot_say>', '<bot_say>嗨</bot_say>'],
    );
    await wait(60);
    final notes = {for (final (who, note) in told) name(who): note};
    expect(notes['Mia'], contains('## #2 · Leo'));
    expect(notes['Leo'], contains('## #3 · Mia'));
  });

  test('one bot, one conversation: told of its life, its files and how '
      'groups go, its chats read even if it only chats', () {
    final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
    final setup = workspace.agentSetup!(mia.folder)!.workspace();
    expect(setup.instructions, contains('Your name is Mia.'));
    expect(setup.instructions, contains('<your_life>'));
    expect(setup.instructions, contains('<group_chats>'));
    expect(setup.instructions, contains('/bots/WORLD.md'));
    expect(
      setup.instructions,
      contains('/bots/${mia.id}/timeline/2026-11-12.md'),
    );
    expect(setup.tools, contains('Read'));
    // The world they share: everyone, and who is in which group.
    final world = utf8.decode(folders.files['/bots/WORLD.md']!);
    expect(world, contains('- Mia'));
    expect(world, contains('[only chats]'));
    expect(
      world,
      contains('- "江湖": 用户, Mia, Leo. Its chat: ${groups.chatFile(group.id)}'),
    );
  });

  test('told of a group with what is new in it, its first line the '
      "group's; what each heard and said, in its timeline", () async {
    final group = groups.save(name: '江湖', members: [mia.id, leo.id]);
    groups.send(group.id, text: '@Mia 晚上吃啥');
    await wait(20);
    final note = told.single.$2;
    expect(
      note,
      startsWith(
        '[group ${group.id}] The group chat "江湖": you, 用户 (the user), Leo.',
      ),
    );
    expect(note, contains('## #1 · 用户 · 2026-11-12 14:00\n@Mia 晚上吃啥'));
    expect(note, contains(groups.chatFile(group.id)));
    expect(
      ChatCodec.botGroupOf(UserMessageItem(text: botEventMessage(note))),
      group.id,
    );
    groups.turnEnded(group.id, mia.id, '<bot_say>火锅！</bot_say>');
    String timeline(Bot bot) =>
        utf8.decode(folders.files['/bots/${bot.id}/timeline/2026-11-12.md']!);
    expect(timeline(mia), contains('- 14:00 [群·江湖 #1] 用户: @Mia 晚上吃啥'));
    expect(timeline(mia), contains('- 14:00 [群·江湖 #2] 我: 火锅！'));
    expect(timeline(leo), contains('- 14:00 [群·江湖 #2] Mia: 火锅！'));
    expect(bots.timeline(leo).count, 2);
  });

  test("what a bot said to a group: after the group's note, till the user "
      'wrote to it', () {
    final items = <ChatItem>[
      UserMessageItem(text: '在吗'),
      AssistantTextItem('<bot_say>在</bot_say>'),
      UserMessageItem(text: botEventMessage('[group g1] new')),
      AssistantTextItem('<bot_say>大家好</bot_say>'),
      // Sent the user in private from the group's turn: theirs.
      const ToolCallItem(
        kind: ToolKind.other,
        target: '',
        tool: 'bot_send',
        input: {'to': 'private', 'text': '私下跟你说'},
      ),
      UserMessageItem(text: '你在群里说啥了'),
      AssistantTextItem('<bot_say>打了个招呼</bot_say>'),
    ];
    expect(ChatCodec.botPlaces(items), [
      null,
      null,
      'g1',
      'g1',
      null,
      null,
      null,
    ]);
    expect(ChatCodec.botSentToUser(items[4]), '私下跟你说');
    // What it says to the group after it, its reply all the same.
    expect(
      BotGroups.replyTo([
        ...items.take(5),
        AssistantTextItem('<bot_say>发过去了</bot_say>'),
      ], 'g1'),
      '<bot_say>大家好</bot_say><bot_say>发过去了</bot_say>',
    );
    // As the phone has it.
    expect(
      ChatCodec.botSentToUser(ChatCodec.decode(ChatCodec.encode(items[4]))!),
      '私下跟你说',
    );
    expect(BotGroups.replyTo(items, 'g1'), '<bot_say>大家好</bot_say>');
    expect(BotGroups.replyTo(items, 'g2'), '');
  });

  test('pictures a bot made in its turn at a group: with its reply there', () {
    final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 1, 2]);
    final made = ImageAttachment(bytes: png, mediaType: 'image/png');
    final items = <ChatItem>[
      UserMessageItem(text: botEventMessage('[group g1] new')),
      ToolCallItem(
        kind: ToolKind.image,
        target: '',
        tool: 'generate_image',
        images: [made],
      ),
      // A picture read is not one sent.
      ToolCallItem(kind: ToolKind.read, target: 'a.png', images: [made]),
      ToolCallItem(
        kind: ToolKind.image,
        target: '',
        status: ToolStatus.failed,
        images: [made],
      ),
      AssistantTextItem('<bot_say>就这张</bot_say>'),
    ];
    expect(BotGroups.picturesTo(items, 'g1'), [made]);
    expect(BotGroups.picturesTo(items, 'g2'), isEmpty);

    final group = groups.save(name: 'g', members: [mia.id, leo.id]);
    groups.send(group.id, text: '@Mia 发张图');
    groups.turnEnded(group.id, mia.id, '', images: [made]);
    final sent = groups.messages(group.id).last;
    expect((sent.from, sent.text), (mia.id, ''));
    expect(sent.images, ['2-1.png']);
    expect(groups.image(group.id, '2-1.png')!.bytes, png);
    // Of itself, with a picture.
    final said = groups.say(group.id, leo.id, '看', images: [made]);
    expect(said.images, ['3-1.png']);
  });

  test('a bot says something in a group of itself: the others told', () async {
    final group = groups.save(name: 'g', members: [mia.id, leo.id]);
    final said = groups.say(group.id, mia.id, '今晚八点开会');
    expect(said.from, mia.id);
    expect(groups.messages(group.id).single.text, '<bot_say>今晚八点开会</bot_say>');
    await wait(60);
    expect(toldNames(), ['Leo']);
    expect(() => groups.say(group.id, ann.id, 'x'), throwsStateError);
  });

  test('one gone from a group: what it said there still under its name', () {
    final group = groups.save(name: 'g', members: [mia.id, leo.id]);
    groups.say(group.id, leo.id, '我先走了');
    bots.delete(leo.id);
    groups.send(group.id, text: '再见');
    final chat = utf8.decode(folders.files[groups.chatFile(group.id)]!);
    expect(chat, contains('## #1 · Leo · '));
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
