import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart' show linkGroupUser;
import 'package:baocode/bots/bot.dart';
import 'package:baocode/bots/bot_folders.dart';
import 'package:baocode/bots/bot_group_prompt.dart';
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
    groups = bots.groups
      ..random = Random(1)
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
    expect(
      chat,
      contains('## #1 · 用户 · 2026-11-12 14:00:00\n你们好\n![picture]('),
    );
    expect(chat, contains('## #2 · Mia · 2026-11-12 14:00:00\n嗨\n*她挥挥手*'));
    // Kept: there again when the app starts again.
    final again = BotGroups(bots)..start();
    addTearDown(again.dispose);
    expect(again.messages(group.id), hasLength(2));
  });

  String? holder(BotGroup group) => groups.relay(group.id).holder;

  test('the user speaks: it goes to whom they call on; else to the bot '
      'that spoke last; else to one at random', () async {
    final group = groups.save(name: 'g', members: [mia.id, leo.id, ann.id]);
    groups.send(group.id, text: '你好 @Leo @Ann');
    expect(toldNames(), ['Leo']);
    expect(holder(group), leo.id);
    final note = told.single.$2;
    expect(note, contains('Now: 2026-11-12 14:00:00.'));
    expect(note, contains('## #1 · 用户 · 2026-11-12 14:00:00 · new\n你好'));
    expect(note, contains('Why you are told now: 用户 called on you (@).'));
    expect(note, contains('In it: you (Leo), 用户 (the user), Mia, Ann.'));
    expect(note, contains('<bot_next>name</bot_next>'));
    expect(note, contains('No <bot_next> means the conversation stops'));
    groups.turnEnded(group.id, leo.id, '<bot_say>好</bot_say>');
    expect(holder(group), isNull);
    now = now.add(const Duration(minutes: 5));
    groups.send(group.id, text: '在吗');
    expect(toldNames(), ['Leo', 'Leo']);
    expect(told.last.$2, contains('you were the last to speak here'));
    expect(
      told.last.$2,
      contains('You last looked at it: 2026-11-12 14:00:00.'),
    );
    // #1 seen before; #2 its own; #3 new.
    expect(told.last.$2, contains('· 2026-11-12 14:00:00\n你好'));
    expect(told.last.$2, contains('## #3 · 用户 · 2026-11-12 14:05:00 · new'));
    final fresh = groups.save(name: 'h', members: [mia.id, ann.id]);
    groups.send(fresh.id, text: '大家好');
    expect([mia.id, ann.id], contains(holder(fresh)));
    expect(told.last.$2, contains('no one here has yet: you start'));
  });

  test(
    'passed on as it says, as many times as it may; then it stops',
    () async {
      final group = groups.save(name: 'g', members: [mia.id, leo.id]);
      groups.send(group.id, text: '@Mia 聊聊');
      var turns = 0;
      for (var who = holder(group); who != null; who = holder(group)) {
        turns++;
        groups.turnEnded(
          group.id,
          who,
          '<bot_say>$turns</bot_say>',
          next: who == mia.id ? 'Leo' : 'Mia',
        );
      }
      // The user's, then eight passes.
      expect(turns, 9);
      expect(
        told[1].$2,
        contains('Why you are told now: Mia handed the conversation to you.'),
      );
      expect(told.last.$2, contains('Hand it to no one now'));
      expect(told.last.$2, isNot(contains('<bot_next>name')));
    },
  );

  test('passed to no one, to the user, or to itself: it stops', () {
    final group = groups.save(name: 'g', members: [mia.id, leo.id]);
    for (final next in [null, '用户', 'Mia', ' ']) {
      told.clear();
      groups.send(group.id, text: '@Mia 嗯');
      groups.turnEnded(group.id, mia.id, '', next: next);
      expect(holder(group), isNull);
      expect(toldNames(), ['Mia']);
    }
  });

  test('passed by a name without what is in brackets, or by its start: '
      'to them; to one not there: back, told who is', () {
    final bo = bots.save(name: '小包（私人助理）', identity: '', abilities: {});
    final group = groups.save(name: 'g', members: [mia.id, leo.id, bo.id]);
    groups.send(group.id, text: '@Mia 嗯');
    groups.turnEnded(group.id, mia.id, '<bot_say>好</bot_say>', next: '@小包');
    expect(holder(group), bo.id);
    groups.turnEnded(group.id, bo.id, '<bot_say>在</bot_say>', next: 'Le');
    expect(holder(group), leo.id);
    groups.turnEnded(group.id, leo.id, '<bot_say>嗯</bot_say>', next: '苏九娘');
    expect(holder(group), leo.id);
    expect(
      told.last.$2,
      contains(
        'Why you are told now: you wrote <bot_next>苏九娘</bot_next>, but '
        'there is no 苏九娘 in this group, so it reached no one.',
      ),
    );
    expect(told.last.$2, contains('Hand it to one of Mia, 小包（私人助理）'));
    groups.turnEnded(group.id, leo.id, '');
    expect(holder(group), isNull);
    expect(groups.relay(group.id).left, BotGroups.passes - 3);
  });

  test('quoting: the user quoting a bot has it answer; a bot quotes by its '
      'number; each read with what it quotes', () {
    final group = groups.save(name: 'g', members: [mia.id, leo.id]);
    groups.say(group.id, leo.id, '我昨天吃了布丁');
    groups.send(group.id, text: '真的吗', ref: 1);
    expect(holder(group), leo.id);
    expect(told.last.$2, contains('用户 answered your message (quoted it)'));
    expect(told.last.$2, contains('> re #1 · Leo: 我昨天吃了布丁\n真的吗'));
    final reply = BotGroups.replyTo([
      UserMessageItem(text: botEventMessage(told.last.$2)),
      const AssistantTextItem(
        '<bot_say ref="2">真的</bot_say><bot_narrate>他点头</bot_narrate>',
      ),
    ], group.id);
    expect(
      reply,
      '<bot_say ref="2">真的</bot_say><bot_narrate>他点头</bot_narrate>',
    );
    groups.turnEnded(group.id, leo.id, reply, next: 'Mia');
    expect(told.last.$2, contains('> re #2 · 用户: 真的吗\n真的'));
    expect(groups.messages(group.id)[1].ref, 1);
    // One quoting none before it: none.
    groups.send(group.id, text: '嗯', ref: 99);
    expect(groups.messages(group.id).last.ref, isNull);
  });

  test("told the group's rules, and a reply as an example", () {
    final group = groups.save(
      name: 'g',
      members: [mia.id, leo.id],
      rules: '只说中文',
    );
    groups.send(group.id, text: '@Mia 嗨');
    final note = told.last.$2;
    expect(
      note,
      contains("The group's rules, which everyone here keeps to:\n只说中文"),
    );
    expect(note, contains('<bot_say ref="1">哈哈 才不是我</bot_say>'));
    expect(note, contains('<bot_next>Leo</bot_next>'));
    expect(groups.messages(group.id).where((m) => m.notice), isEmpty);
    groups.save(id: group.id, name: 'g', members: [mia.id, leo.id], rules: '');
    expect(groups.messages(group.id).last.text, '用户 修改了群规');
  });

  test(
    'passed on at most as the group says: at least two; none, unbounded',
    () {
      final group = groups.save(
        name: 'g',
        members: [mia.id, leo.id],
        passes: 1,
      );
      expect(group.passes, 2);
      groups.send(group.id, text: '@Mia 聊');
      expect(groups.relay(group.id).left, 2);
      groups.save(
        id: group.id,
        name: 'g',
        members: [mia.id, leo.id],
        passes: 0,
      );
      groups.turnEnded(group.id, mia.id, '');
      groups.send(group.id, text: '@Mia 再聊');
      expect(groups.relay(group.id).left, BotGroups.unbounded);
    },
  );

  test('handed on by a bot: told after the group\'s gap; the user speaking '
      'meanwhile, it goes as they say', () async {
    final group = groups.save(
      name: 'g',
      members: [mia.id, leo.id, ann.id],
      gap: 1,
    );
    expect(group.gap, 1);
    // The user's: at once.
    groups.send(group.id, text: '@Mia 聊');
    expect(toldNames(), ['Mia']);
    groups.turnEnded(group.id, mia.id, '<bot_say>嗯</bot_say>', next: 'Leo');
    expect(holder(group), leo.id);
    expect(toldNames(), ['Mia']);
    expect(groups.typing(group.id), isEmpty);
    await wait(1100);
    expect(toldNames(), ['Mia', 'Leo']);

    groups.turnEnded(group.id, leo.id, '<bot_say>好</bot_say>', next: 'Mia');
    groups.send(group.id, text: '@Ann 你呢');
    expect(toldNames(), ['Mia', 'Leo', 'Ann']);
    await wait(1100);
    expect(toldNames(), ['Mia', 'Leo', 'Ann']);
    expect(holder(group), ann.id);
  });

  test('one that cannot take it, busy elsewhere or its turn failed: '
      'another who is free has it, told why', () {
    final group = groups.save(name: 'g', members: [mia.id, leo.id, ann.id]);
    final other = groups.save(name: '别处', members: [leo.id, mia.id]);
    groups.send(other.id, text: '@Leo 忙吗');
    groups.send(group.id, text: '@Mia 你先');
    groups.turnEnded(group.id, mia.id, '<bot_say>好</bot_say>', next: 'Leo');
    // Leo at work in the other: Ann, not Mia who passed it.
    expect(holder(group), ann.id);
    expect(
      told.last.$2,
      contains(
        'Why you are told now: Mia passed it to Leo, but Leo is busy in '
        '"别处"; so it is yours.',
      ),
    );
    groups.turnEnded(group.id, ann.id, '', failed: true);
    expect(holder(group), mia.id);
    expect(told.last.$2, contains('but Ann ran into an error; so it is yours'));
  });

  test(
    'one not done in time: another has it; its words still said after',
    () async {
      groups.stuck = const Duration(milliseconds: 30);
      final group = groups.save(name: 'g', members: [mia.id, leo.id]);
      groups.send(group.id, text: '@Mia 在吗');
      await wait(60);
      expect(holder(group), leo.id);
      expect(
        told.last.$2,
        contains('用户 called on Mia, but Mia did not answer in 0 seconds'),
      );
      groups.turnEnded(group.id, mia.id, '<bot_say>来了</bot_say>', next: 'Leo');
      expect(groups.messages(group.id).last.text, '<bot_say>来了</bot_say>');
      expect(holder(group), leo.id);
      expect(toldNames(), ['Mia', 'Leo']);
    },
  );

  test('the user speaking while one is at work on it: once it is done, it '
      'goes as when they spoke', () {
    final group = groups.save(name: 'g', members: [mia.id, leo.id, ann.id]);
    groups.send(group.id, text: '@Mia 一');
    groups.send(group.id, text: '@Leo 二');
    expect(toldNames(), ['Mia']);
    groups.turnEnded(group.id, mia.id, '<bot_say>嗯</bot_say>', next: 'Ann');
    expect(toldNames(), ['Mia', 'Leo']);
    expect(told.last.$2, contains('用户 called on you'));
    expect(told.last.$2, contains('## #3 · Mia · 2026-11-12 14:00:00 · new'));
  });

  test('told the latest twenty, each cut past its length, where all of it '
      'is said', () {
    final group = groups.save(name: 'g', members: [mia.id]);
    for (var i = 1; i <= 24; i++) {
      groups.say(group.id, mia.id, i == 20 ? 'x' * 600 : '$i');
    }
    groups.send(group.id, text: '@Mia 看看');
    final note = told.single.$2;
    expect(
      note,
      contains('The latest messages (#6–#25), the new ones marked:'),
    );
    expect(note, isNot(contains('## #5 ·')));
    expect(note, contains('${'x' * 500}… (cut: all of it at lines'));
    expect(note, isNot(contains('x' * 501)));
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
    expect(note, startsWith('[group ${group.id}] The group chat "江湖".'));
    expect(note, contains('In it: you (Mia), 用户 (the user), Leo.'));
    expect(note, contains('## #1 · 用户 · 2026-11-12 14:00:00 · new\n@Mia 晚上吃啥'));
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

  test('a bot says something in a group of itself: there for whoever has '
      'it next, no one woken', () {
    final group = groups.save(name: 'g', members: [mia.id, leo.id]);
    final said = groups.say(group.id, mia.id, '今晚八点开会');
    expect(said.from, mia.id);
    expect(groups.messages(group.id).single.text, '<bot_say>今晚八点开会</bot_say>');
    expect(told, isEmpty);
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
