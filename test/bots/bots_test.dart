import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:baocode/bots/bot.dart';
import 'package:baocode/bots/bot_files.dart';
import 'package:baocode/bots/bot_folders.dart';
import 'package:baocode/bots/bot_pacer.dart';
import 'package:baocode/bots/bot_permissions.dart';
import 'package:baocode/bots/bot_prompt.dart';
import 'package:baocode/bots/bot_tools.dart';
import 'package:baocode/bots/bots.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/queued_messages.dart';
import 'package:baocode/link/chat_codec.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/claude_sdk_tools.dart';
import 'package:baocode/kernel/claude_code/mock_claude_code_transport.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/images/image_tools.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('BotPacer', () {
    final start = DateTime(2026, 10, 29, 14);
    BotEvent event(String chat, BotEventKind kind, DateTime at) => BotEvent(
      chat: chat,
      title: 'Agent $chat',
      project: 'monad',
      kind: kind,
      at: at,
    );

    test('what comes close together is told at once, what needs the user '
        'first', () {
      final pacer = BotPacer();
      pacer
        ..add(event('a', BotEventKind.done, start))
        ..add(event('b', BotEventKind.failed, start.add(seconds(20))))
        ..add(event('c', BotEventKind.waiting, start.add(seconds(40))));
      expect(pacer.take(start.add(seconds(60))), isNull);
      final told = pacer.take(start.add(seconds(90)))!;
      expect(told.map((e) => e.chat), ['c', 'b', 'a']);
      expect(pacer.hasPending, isFalse);
    });

    test('an agent\'s latest only', () {
      final pacer = BotPacer()
        ..add(event('a', BotEventKind.waiting, start))
        ..add(event('a', BotEventKind.done, start.add(seconds(10))));
      final told = pacer.take(start.add(const Duration(minutes: 5)))!;
      expect(told.single.kind, BotEventKind.done);
    });

    test('told as soon as gathered, whatever the hour: the bot judges', () {
      final night = DateTime(2026, 10, 29, 23, 30);
      final pacer = BotPacer()..add(event('a', BotEventKind.failed, night));
      expect(pacer.dueAt(night), night.add(seconds(90)));
      expect(pacer.take(night.add(seconds(90))), isNotNull);
      // And again at once, of what came since.
      final later = night.add(minutes(2));
      pacer.add(event('b', BotEventKind.failed, later));
      expect(pacer.take(later.add(seconds(90))), isNotNull);
    });

    test('what was done long ago is not worth telling', () {
      final pacer = BotPacer()
        ..add(event('a', BotEventKind.done, start))
        ..add(event('b', BotEventKind.waiting, start));
      final told = pacer.take(start.add(const Duration(hours: 7)))!;
      expect(told.map((e) => e.chat), ['b']);
    });
  });

  group('what a bot is told', () {
    const bot = Bot(
      id: 'b',
      name: 'Mia',
      folder: '/bots/b',
      gender: 'female',
      signature: 'Tea first.',
      identity: 'An old friend, playful and kind.',
      style: 'Lowercase, lots of emoji.',
      abilities: {BotAbility.agents},
    );

    test('the rules first, then who the user made it', () {
      final told = botInstructions(bot, memory: 'Likes tea.');
      expect(told.indexOf('<bot_rules>'), 0);
      expect(told, contains('Keep strictly to the identity'));
      expect(told, contains('12356'));
      expect(told, contains('cannot approve or deny'));
      expect(
        told.indexOf('<bot_rules>'),
        lessThan(told.indexOf('An old friend')),
      );
      expect(told, contains('Your name is Mia.'));
      expect(told, contains('Your gender, as the user put it: female.'));
      expect(told, contains('Tea first.'));
      expect(told, contains('How you talk, in the user\'s words:'));
      expect(told, contains('Lowercase, lots of emoji.'));
      expect(told, contains('Likes tea.'));
    });

    test('all it is: its picture, when and where', () {
      final made = DateTime(2026, 10, 1, 9);
      final told = botInstructions(
        Bot(
          id: 'b',
          name: 'Mia',
          folder: '/bots/b',
          avatar: '🌸',
          created: made,
        ),
        memory: '',
        self: '- Grew up by the sea',
        computer: 'Leo 的 MacBook',
      );
      expect(
        told,
        contains(
          'Your picture (what the user sees beside your '
          'messages): the emoji 🌸.',
        ),
      );
      expect(told, contains('The user made you on Thursday 2026-10-01.'));
      expect(told, contains('("Leo 的 MacBook")'));
      // A person of its own, the same each time.
      expect(told, contains('<personality>'));
      expect(told, contains('Grew up by the sea'));
      // A picture of the user's choosing: looked at, if not noted.
      final pictured = botIdentity(
        const Bot(id: 'b', name: 'Mia', folder: '/b', avatar: 'avatar-1.png'),
      );
      expect(pictured, contains('bot_my_picture'));
      expect(
        botIdentity(const Bot(id: 'b', name: 'Mia', folder: '/b')),
        contains("your name's first letter"),
      );
    });

    test('when a bot was made, from its id if its card does not say', () {
      final at = DateTime(2026, 10, 29, 14);
      final id = 'b${at.microsecondsSinceEpoch.toRadixString(36)}';
      expect(BotFiles.read('/b/$id', '---\nname: x\n---\n')!.created, at);
      expect(
        BotFiles.read('/b/assistant', '---\nname: x\n---\n')!.created,
        isNull,
      );
    });

    test('what it may do, and may not', () {
      final told = botAbilities(bot);
      expect(told, contains('bot_list_chats'));
      expect(told, contains('bot_stop_chat'));
      expect(told, contains('You do not read or change files'));
      expect(
        botAbilities(const Bot(id: 'q', name: 'Q', folder: '/bots/q')),
        contains("You cannot see the user's agents"),
      );
      expect(told, contains('You cannot use the browser.'));
      // Pictures, every bot's.
      expect(told, contains('generate_image'));
    });

    test('what of Claude Code\'s it has: the web\'s, the browser\'s by '
        'the tool search; no files, no commands', () {
      Bot bot(Set<BotAbility> abilities) =>
          Bot(id: 'b1', name: 'Mia', folder: '/bots/b1', abilities: abilities);
      for (final abilities in [
        <BotAbility>{},
        {BotAbility.agents},
      ]) {
        expect(BotPermissions.tools(bot(abilities)), ['WebSearch', 'WebFetch']);
      }
      expect(BotPermissions.tools(bot({BotAbility.browser})), [
        'WebSearch',
        'WebFetch',
        'ToolSearch',
      ]);
      // Its files not shown it: its tools keep them.
      final told = botInstructions(bot(BotAbility.values.toSet()), memory: '');
      expect(told, contains('bot_remember'));
      expect(told, contains('bot_edit_me'));
      expect(told, isNot(contains('<your_files>')));
      expect(told, contains('received/image-3.png'));
    });

    test('pictures: made with the image model, or said there is none', () {
      const painter = Bot(id: 'p', name: 'Pia', folder: '/bots/p');
      expect(botAbilities(painter), contains('generate_image'));
      expect(
        botAbilities(painter, imageModel: false),
        contains('no image model turned on'),
      );
      // Emoji, not the app's stickers; pictures of its own.
      expect(botChatStyle, contains('emoji'));
      expect(botChatStyle, isNot(contains('bot_send_sticker')));
      expect(botChatStyle, contains('bot_send_image'));
    });
  });

  group('Bots', () {
    final launches = <ClaudeLaunch>[];
    late KernelDescriptor kernel;
    kernel = KernelDescriptor(
      id: 'claude-code',
      label: 'Claude Code',
      icon: Icons.auto_awesome_rounded,
      description: '',
      create: (context) => ClaudeCodeKernel(
        kernel,
        context,
        start: (launch) {
          launches.add(launch);
          return MockClaudeCodeTransport.start(launch);
        },
      ),
    );
    late Workspace workspace;
    late Bots bots;
    late MemoryBotFolders folders;
    late MemoryPreferenceStore store;
    late DateTime now;
    late String app;

    setUp(() async {
      launches.clear();
      app = Directory.systemTemp.createTempSync('bots-app').path;
      addTearDown(() => Directory(app).deleteSync(recursive: true));
      workspace = Workspace(kernels: [kernel], projects: [Project('app', app)]);
      folders = MemoryBotFolders();
      store = MemoryPreferenceStore();
      now = DateTime(2026, 10, 29, 14);
      bots = Bots(
        workspace: workspace,
        folders: folders,
        store: store,
        chinese: true,
        clock: () => now,
        computer: () async => 'Leo 的 MacBook',
      );
      await bots.start();
    });

    tearDown(() {
      bots.dispose();
      workspace.dispose();
    });

    Future<List<String>> offered(String cwd) async {
      final answer = await ClaudeSdkTools.handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/list',
      }, ClaudeSdkCall(cwd: cwd));
      return [
        for (final tool
            in ((answer['result'] as Map)['tools'] as List).cast<Map>())
          tool['name'] as String,
      ];
    }

    /// What the app told [bot]: its notes in its conversation.
    List<String> notes(Bot bot) {
      final session = bots.threadFor(bot).session;
      return [
        for (var i = 0; i < session.itemCount; i++)
          if (session.itemAt(i) case final UserMessageItem item)
            ?ChatCodec.botEvent(item),
      ];
    }

    /// The assistant, told of every agent: the user turned it on.
    Bot toldOfAll() {
      final assistant = bots.bots.single;
      return bots.save(
        id: assistant.id,
        name: assistant.name,
        identity: assistant.identity,
        abilities: {...assistant.abilities, BotAbility.proactive},
        // Not told of it, a turn of its own.
        by: assistant,
      );
    }

    test('start with the assistant, its abilities on but being told of '
        'every agent, kept', () async {
      final assistant = bots.bots.single;
      expect(assistant.assistant, isTrue);
      expect(assistant.name, '小宝');
      expect(assistant.abilities, {BotAbility.agents, BotAbility.browser});
      // Its card, a file of its folder.
      final card = utf8.decode(folders.files['${assistant.folder}/BOT.md']!);
      expect(card, contains('name: 小宝'));
      expect(card, contains('agents: true'));
      expect(card, contains('proactive: false'));
      expect(card, isNot(contains('files:')));
      expect(card, contains('assistant: true'));
      expect(store.preferences, isNot(contains('bots')));
    });

    test('a bot\'s folder is no project of the sidebar\'s', () {
      final bot = bots.bots.single;
      final thread = bots.threadFor(bot);
      expect(workspace.isHidden(thread.project), isTrue);
      expect(workspace.listsInSidebar(thread), isFalse);
      expect(bots.threadFor(bot), same(thread));
      expect(workspace.agentSetup!(bot.folder)!.settings, Bots.settings);
      // Named by none of what it is told.
      thread.session.send(const ComposerMessage(text: '<bao-event>x'));
      workspace.notifyListeners();
      expect(thread.title, isNot(contains('bao-event')));
      expect(workspace.agentSetup!(app), isNull);
    });

    test('its agent is told who it is, with its own tools only', () async {
      final bot = bots.bots.single;
      bots.threadFor(bot).session.send(const ComposerMessage(text: '在吗'));
      for (var i = 0; i < 50 && launches.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final launch = launches.single;
      expect(launch.cwd, bot.folder);
      expect(launch.instructions, contains('<bot_rules>'));
      expect(launch.instructions, contains('小宝'));
      // Its prompt in place of a coding agent's: none of the chat's notes
      // on citing code either.
      expect(launch.ownPrompt, isTrue);
      expect(launch.arguments, contains('--system-prompt'));
      expect(launch.arguments, isNot(contains('--append-system-prompt')));
      expect(launch.arguments.join(' '), isNot(contains('<citing_code>')));
      // What the user writes meanwhile, taken up as it talks.
      expect(
        workspace.agentSetup!(bot.folder)!.workspace().queuedMessages,
        QueuedMessages.duringTurn,
      );
      // Full access, nothing asked: the CLI accepting edits, the rest
      // approved by the kernel, what the CLI would ask about too.
      expect(launch.permissionMode, 'acceptEdits');
      expect(
        workspace.agentSetup!(bot.folder)!.workspace().approvesAll,
        isTrue,
      );
      expect(launch.sdkServers, [ClaudeSdkTools.server]);
      // The web's, the browser's tool search; no other.
      expect(launch.tools, ['WebSearch', 'WebFetch', 'ToolSearch']);
      expect(
        launch.arguments,
        containsAllInOrder(['--tools', 'WebSearch,WebFetch,ToolSearch']),
      );
      // Nothing it is made to ask about.
      expect(
        (launch.settings['permissions'] as Map?)?.containsKey('ask'),
        isNot(true),
      );
      // No project its to work in: the agents do.
      expect(launch.directories, isEmpty);
      // None of the user's MCP servers: their notices are not its to tell.
      expect(launch.arguments, contains('--strict-mcp-config'));
    });

    test(
      'a bot is offered its abilities\' tools; a project\'s agent none',
      () async {
        final assistant = bots.bots.single;
        final its = await offered(assistant.folder);
        expect(its, containsAll(['bot_list_chats', 'bot_stop_chat']));
        // Its tools as well as its files: they keep the same.
        for (final tool in [
          'bot_remember',
          'bot_later',
          'bot_cancel_later',
          'bot_my_picture',
          'bot_user_picture',
          'bot_list_bots',
          'bot_save_bot',
          'bot_delete_bot',
          'bot_edit_me',
        ]) {
          expect(its, contains(tool));
        }
        expect(await offered(app), isNot(contains('bot_list_chats')));
        expect(ClaudeSdkTools.serversFor(app), isEmpty);

        // A new one may do nothing until the user says.
        final mia = bots.save(
          name: 'Mia',
          identity: '',
          abilities: {BotAbility.agents},
        );
        final hers = await offered(mia.folder);
        expect(
          hers,
          containsAll(['bot_list_chats', 'bot_show_chat', 'bot_stop_chat']),
        );
        expect(hers, contains('bot_remember'));
        final none = bots.save(name: 'Quiet', identity: '', abilities: {});
        expect(await offered(none.folder), [
          'bot_say',
          'bot_later',
          'bot_cancel_later',
          'bot_send_image',
          'bot_remember',
          'bot_my_picture',
          'bot_user_picture',
          'bot_edit_me',
        ]);
        // The assistant's alone: its contacts looked after.
        expect(await offered(mia.folder), isNot(contains('bot_list_bots')));
        // Nor called, though named.
        final refused = await ClaudeSdkTools.handle({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/call',
          'params': {
            'name': 'bot_list_chats',
            'arguments': <String, Object?>{},
          },
        }, ClaudeSdkCall(cwd: none.folder));
        expect((refused['result'] as Map)['isError'], isTrue);
      },
    );

    test('bots are changed and deleted; the assistant stays', () {
      final mia = bots.save(name: ' Mia ', identity: 'x', abilities: {});
      expect(mia.name, 'Mia');
      final changed = bots.save(
        id: mia.id,
        name: 'Mia',
        avatar: '🌸',
        identity: 'y',
        abilities: {BotAbility.proactive},
        proactive: const BotProactive(perDay: 0),
      );
      expect(changed.avatar, '🌸');
      expect(bots.byId(mia.id)!.proactive.perDay, 0);
      bots.delete(mia.id);
      expect(bots.byId(mia.id), isNull);
      expect(folders.made, isNot(contains(mia.folder)));
      expect(() => bots.delete('assistant'), throwsStateError);
      expect(
        () => bots.save(name: ' ', identity: '', abilities: {}),
        throwsArgumentError,
      );
    });

    test('who it is, all the user wrote, kept; its model too', () async {
      final mia = bots.save(
        name: 'Mia',
        gender: ' female ',
        signature: 'Tea first.',
        identity: 'An old friend.',
        style: 'Short.',
        abilities: {},
      );
      expect(
        (mia.gender, mia.signature, mia.style),
        ('female', 'Tea first.', 'Short.'),
      );
      bots.setModel(mia, 'opus');
      expect(workspace.agentSetup!(mia.folder)!.settings, {
        ...Bots.settings,
        'model': 'opus',
      });
      await pumpEventQueue();
      final kept = BotFiles.read(
        mia.folder,
        utf8.decode(folders.files['${mia.folder}/BOT.md']!),
        style: utf8.decode(folders.files['${mia.folder}/STYLE.md']!),
      )!;
      expect(
        (kept.gender, kept.signature, kept.style, kept.model),
        ('female', 'Tea first.', 'Short.', 'opus'),
      );
    });

    test('its picture: kept in its folder, named by what it shows', () {
      final png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
      final mia = bots.save(
        name: 'Mia',
        identity: '',
        abilities: {},
        avatarImage: (bytes: png, type: 'image/png'),
      );
      expect(mia.avatar, matches(RegExp(r'^avatar-[0-9a-f]{12}\.png$')));
      expect(isAvatarImage(mia.avatar), isTrue);
      expect(folders.files[mia.avatarFile], png);
      expect(bots.avatarImage(mia), (bytes: png, type: 'image/png'));

      // Kept as it is, by its name; not another file by a name.
      final kept = bots.save(
        id: mia.id,
        name: 'Mia',
        avatar: mia.avatar,
        identity: 'x',
        abilities: {},
      );
      expect(kept.avatar, mia.avatar);
      expect(
        bots
            .save(
              id: mia.id,
              name: 'Mia',
              avatar: 'avatar-000000000000.png',
              identity: 'x',
              abilities: {},
            )
            .avatar,
        isNull,
      );
      // An emoji in its place: the file gone.
      final again = bots.save(
        id: mia.id,
        name: 'Mia',
        identity: '',
        abilities: {},
        avatarImage: (bytes: png, type: 'image/png'),
      );
      final emoji = bots.save(
        id: mia.id,
        name: 'Mia',
        avatar: '🌸',
        identity: '',
        abilities: {},
      );
      expect(emoji.avatar, '🌸');
      expect(folders.files, isNot(contains(again.avatarFile)));
      expect(bots.avatarImage(emoji), isNull);
    });

    test('pictures are made by those that may, the model not asked', () async {
      ClaudeSdkTools.register(
        ClaudeSdkTool(
          name: ImageTools.name,
          description: '',
          inputSchema: const {'type': 'object'},
          run: (input, call) async => '',
        ),
      );
      addTearDown(() => ClaudeSdkTools.unregister(ImageTools.name));
      final assistant = bots.bots.single;
      expect(await offered(assistant.folder), contains(ImageTools.name));
      final mia = bots.save(name: 'Mia', identity: '', abilities: {});
      expect(await offered(mia.folder), contains(ImageTools.name));
      // No one at the computer to pick the model for it.
      expect(ClaudeSdkTools.asksUser(assistant.folder), isFalse);
      expect(ClaudeSdkTools.asksUser(app), isTrue);
    });

    test('it sends pictures from the web', () async {
      Future<Map> call(
        Bot bot,
        String tool,
        Map<String, Object?> input,
      ) async =>
          (await ClaudeSdkTools.handle({
                'jsonrpc': '2.0',
                'id': 4,
                'method': 'tools/call',
                'params': {'name': tool, 'arguments': input},
              }, ClaudeSdkCall(cwd: bot.folder)))['result']
              as Map;
      final assistant = bots.bots.single;
      // No stickers of the app's now: emoji in its messages.
      expect(
        await offered(assistant.folder),
        isNot(contains('bot_send_sticker')),
      );
      expect(
        (await call(assistant, 'bot_send_image', {
          'url': 'https://example.com/cat.png',
        }))['isError'],
        isNot(isTrue),
      );
      expect(
        (await call(assistant, 'bot_send_image', {
          'url': 'file:///etc/x',
        }))['isError'],
        isTrue,
      );
    });

    Future<Map> call(Bot bot, String tool, Map<String, Object?> input) async =>
        (await ClaudeSdkTools.handle({
              'jsonrpc': '2.0',
              'id': 5,
              'method': 'tools/call',
              'params': {'name': tool, 'arguments': input},
            }, ClaudeSdkCall(cwd: bot.folder)))['result']
            as Map;

    test('it talks with bot_say, a pause after each message', () async {
      final paused = <String>[];
      BotTools.pause = (text) {
        paused.add(text);
        return Duration.zero;
      };
      addTearDown(() => BotTools.pause = BotTools.typingPause);
      final bot = bots.bots.single;
      final sent = await call(bot, 'bot_say', {'text': '等下 我看看'});
      expect(sent['isError'], isNot(isTrue));
      // The time told, as the conversation goes on.
      expect('${sent['content']}', contains('Thursday 2026-10-29 14:00'));
      expect(paused, ['等下 我看看']);
      expect((await call(bot, 'bot_say', {'text': ' '}))['isError'], isTrue);
      // As long as it takes to write, about; never long.
      expect(BotTools.typingPause('嗯'), const Duration(milliseconds: 600));
      expect(
        BotTools.typingPause('x' * 500),
        const Duration(milliseconds: 2400),
      );
    });

    test('it comes back later on its own, when it said', () async {
      final bot = bots.save(name: 'Mia', identity: '', abilities: {});
      final set = await call(bot, 'bot_later', {
        'minutes': 90,
        'note': 'Ask how the interview went',
      });
      expect(set['isError'], isNot(isTrue));
      expect('${set['content']}', contains('15:30'));
      expect(bots.laters(bot).single.at, DateTime(2026, 10, 29, 15, 30));
      // A line of its LATER.md.
      expect(
        utf8.decode(folders.files['${bot.folder}/LATER.md']!),
        '- 2026-10-29 15:30 Ask how the interview went\n',
      );
      // Not before its time.
      now = DateTime(2026, 10, 29, 15);
      bots.deliver();
      expect(bots.threadOf(bot)!.session.itemCount, 0);
      now = DateTime(2026, 10, 29, 15, 31);
      bots.deliver();
      final note = bots.threadOf(bot)!.session.itemAt(0) as UserMessageItem;
      expect(ChatCodec.botEvent(note), contains('Ask how the interview went'));
      expect(ChatCodec.botEvent(note), contains('Now: Thursday'));
      expect(bots.laters(bot), isEmpty);
      expect(folders.files, isNot(contains('${bot.folder}/LATER.md')));

      // At night too: the hour is its to mind, as it is told.
      now = DateTime(2026, 10, 29, 22, 30);
      await call(bot, 'bot_later', {'minutes': 60, 'note': 'Remind of x'});
      expect(bots.laters(bot).single.at, DateTime(2026, 10, 29, 23, 30));
      expect(botEvents, contains('Mind the time'));
      expect(
        (await call(bot, 'bot_later', {'minutes': 0, 'note': 'x'}))['isError'],
        isTrue,
      );
      // Every bot may: none is set up for it.
      expect(await offered(bot.folder), contains('bot_later'));
    });

    test('it keeps notes of itself, and sees its own picture', () async {
      final bot = bots.save(name: 'Mia', identity: '', abilities: {});
      await call(bot, 'bot_remember', {
        'about': 'self',
        'action': 'add',
        'text': 'Loves rainy days',
      });
      expect(bots.selfNotes(bot), '- Loves rainy days');
      expect(
        utf8.decode(folders.files['${bot.folder}/SELF.md']!),
        '- Loves rainy days\n',
      );
      expect(bots.memory(bot), isEmpty);
      expect(
        '${(await call(bot, 'bot_my_picture', {}))['content']}',
        contains("name's first letter"),
      );
      final png = base64.decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
        '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      );
      final pictured = bots.save(
        id: bot.id,
        name: bot.name,
        identity: bot.identity,
        abilities: bot.abilities,
        avatarImage: (bytes: png, type: 'image/png'),
      );
      final seen = await call(pictured, 'bot_my_picture', {});
      expect(
        (seen['content'] as List).map((c) => (c as Map)['type']),
        contains('image'),
      );
    });

    test('told what the user changed of it, its new picture to see', () async {
      final bot = bots.bots.single;
      final session = bots.threadFor(bot).session;
      final png = base64.decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
        '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      );
      bots.save(
        id: bot.id,
        name: '包包',
        signature: '今天也要开心',
        identity: bot.identity,
        abilities: bot.abilities.difference({BotAbility.browser}),
        avatarImage: (bytes: png, type: 'image/png'),
      );
      final note = [
        for (var i = 0; i < session.itemCount; i++) session.itemAt(i),
      ].whereType<UserMessageItem>().last;
      final told = ChatCodec.botEvent(note)!;
      expect(told, contains('Your name: now "包包".'));
      expect(told, contains('Your picture: a new one'));
      expect(told, contains('今天也要开心'));
      expect(told, contains('You may no longer: browser.'));
      expect(note.images, hasLength(1));
      // Nothing changed: nothing told.
      int notes() =>
          [for (var i = 0; i < session.itemCount; i++) session.itemAt(i)]
              .whereType<UserMessageItem>()
              .length;
      final count = notes();
      final now = bots.bots.single;
      bots.save(
        id: now.id,
        name: now.name,
        avatar: now.avatar,
        signature: now.signature,
        identity: now.identity,
        abilities: now.abilities,
      );
      expect(notes(), count);
    });

    test('what it remembers: kept by it, seen, changed and cleared', () async {
      final bot = bots.save(name: 'Mia', identity: '', abilities: {});
      Future<void> remember(String action, String text) =>
          ClaudeSdkTools.handle({
            'jsonrpc': '2.0',
            'id': 3,
            'method': 'tools/call',
            'params': {
              'name': 'bot_remember',
              'arguments': {'action': action, 'text': text},
            },
          }, ClaudeSdkCall(cwd: bot.folder));
      await remember('add', 'Name is Leo');
      await remember('add', 'Likes tea');
      expect(bots.memory(bot), '- Name is Leo\n- Likes tea');
      bots.setMemory(bot, 'Name is Leo');
      expect(bots.memory(bot), 'Name is Leo');
      expect(
        utf8.decode(folders.files['${bot.folder}/MEMORY.md']!),
        'Name is Leo\n',
      );
      bots.setMemory(bot, '');
      expect(bots.memory(bot), '');
      expect(folders.files, isNot(contains('${bot.folder}/MEMORY.md')));
    });

    test('it writes first of an agent done, in a note of the app\'s', () async {
      final bot = toldOfAll();
      final agent = workspace.startAgent(workspace.projectAt(app));
      agent.session.send(const ComposerMessage(text: 'build it'));
      for (var i = 0; i < 300 && !agent.session.isStreaming; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      workspace.notifyListeners();
      // Its turn over (stopped, not to wait for the mock's whole script).
      agent.session.stop();
      for (var i = 0; i < 300 && agent.session.isStreaming; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      workspace.notifyListeners();
      now = now.add(const Duration(minutes: 2));
      bots.deliver();
      expect(notes(bot).single, contains('done: "${agent.title}"'));
    });

    test('only a bot let be is told of every agent; another, of those it '
        'started or wrote to', () async {
      final assistant = toldOfAll();
      final mia = bots.save(
        name: 'Mia',
        identity: '',
        abilities: {BotAbility.agents},
      );
      Future<AgentThread> run() async {
        final agent = workspace.startAgent(workspace.projectAt(app));
        agent.session.send(const ComposerMessage(text: 'build it'));
        for (var i = 0; i < 300 && !agent.session.isStreaming; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        workspace.notifyListeners();
        return agent;
      }

      Future<void> finish(AgentThread agent) async {
        agent.session.stop();
        for (var i = 0; i < 300 && agent.session.isStreaming; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        workspace.notifyListeners();
        now = now.add(const Duration(minutes: 2));
        bots.deliver();
      }

      final first = await run();
      await finish(first);
      expect(notes(assistant), hasLength(1));
      expect(notes(mia), isEmpty);
      // One it started: told of it.
      final second = await run();
      bots.watch(mia, second);
      await finish(second);
      expect(notes(mia).single, contains('done: "${second.title}"'));
      await pumpEventQueue();
      expect(store.preferences['watching'], {
        mia.id: [BotTools.idOf(second)],
      });
    });

    test('it drops what it meant to come back to', () async {
      final bot = bots.save(name: 'Mia', identity: '', abilities: {});
      await call(bot, 'bot_later', {'minutes': 3, 'note': 'Remind of tea'});
      await call(bot, 'bot_later', {'minutes': 60, 'note': 'Ask about x'});
      final dropped = await call(bot, 'bot_cancel_later', {'note': 'TEA'});
      expect('${dropped['content']}', contains('Remind of tea'));
      expect([for (final l in bots.laters(bot)) l.note], ['Ask about x']);
      final none = await call(bot, 'bot_cancel_later', {'note': 'nope'});
      expect('${none['content']}', contains('Waiting:'));
      expect(botEvents, contains('Never send a message saying you won'));
    });

    test('the assistant looks after the other bots, and itself', () async {
      final assistant = bots.bots.single;
      int told(Bot bot) {
        final session = bots.threadFor(bot).session;
        return [for (var i = 0; i < session.itemCount; i++) session.itemAt(i)]
            .whereType<UserMessageItem>()
            .length;
      }

      final made = await call(assistant, 'bot_save_bot', {
        'name': '阿猫',
        'emoji': '🐱',
        'identity': '你是一只懒猫',
      });
      expect(made['isError'], isNot(isTrue));
      final cat = bots.bots.firstWhere((b) => b.name == '阿猫');
      expect(cat.avatar, '🐱');
      expect(cat.abilities, isEmpty);
      // Another's changed: it is told by whom.
      await call(assistant, 'bot_save_bot', {'bot': cat.id, 'signature': '困'});
      final catSession = bots.threadFor(cat).session;
      final note = [
        for (var i = 0; i < catSession.itemCount; i++) catSession.itemAt(i),
      ].whereType<UserMessageItem>().last;
      expect(ChatCodec.botEvent(note), contains('小宝 (the assistant'));
      expect(bots.byId(cat.id)!.identity, '你是一只懒猫');
      // Itself, a picture it made: cut square; not told what it did.
      final before = told(assistant);
      final file = File('$app/made.png')
        ..writeAsBytesSync(
          base64.decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAAB/qH1jAAAAEklEQVR4nGP4z8Dw'
            'HxkzoAsAAA8hD/EEN8afAAAAAElFTkSuQmCC',
          ),
        );
      final changed = await call(assistant, 'bot_save_bot', {
        'bot': assistant.id,
        'picture': file.path,
        'signature': '在呢',
      });
      expect(changed['isError'], isNot(isTrue), reason: '$changed');
      final self = bots.byId(assistant.id)!;
      expect(self.signature, '在呢');
      expect(isAvatarImage(self.avatar!), isTrue);
      expect(told(self), before);
      // Not itself deleted; another, yes.
      expect(
        (await call(assistant, 'bot_delete_bot', {
          'bot': assistant.id,
        }))['isError'],
        isTrue,
      );
      await call(assistant, 'bot_delete_bot', {'bot': cat.id});
      expect(bots.byId(cat.id), isNull);
      // None but the assistant does so.
      final mia = bots.save(name: 'Mia', identity: '', abilities: {});
      expect((await call(mia, 'bot_list_bots', {}))['isError'], isTrue);
      expect(botInstructions(self, memory: ''), contains('<contacts>'));
      expect(botInstructions(mia, memory: ''), isNot(contains('<contacts>')));
    });

    test('the bots know who the user is, their picture to see', () async {
      final bot = bots.save(name: 'Mia', identity: '', abilities: {});
      expect(
        '${(await call(bot, 'bot_user_picture', {}))['content']}',
        contains('none'),
      );
      final png = base64.decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
        '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      );
      bots.setMe(const BotUser(name: 'Leo', signature: '写代码的'), (
        bytes: png,
        type: 'image/png',
      ));
      expect(bots.me.name, 'Leo');
      expect(bots.myPicture!.bytes, png);
      final seen = await call(bot, 'bot_user_picture', {});
      expect(
        (seen['content'] as List).map((c) => (c as Map)['type']),
        contains('image'),
      );
      final told = workspace.agentSetup!(bot.folder)!.workspace().instructions;
      expect(told, contains('Their name: Leo.'));
      expect(told, contains('写代码的'));
      // Their USER.md, their picture beside it.
      final user = utf8.decode(folders.files['/bots/USER.md']!);
      expect(user, contains('name: Leo'));
      expect(user, contains('signature: 写代码的'));
      expect(user, contains('picture: me-'));
      // Its picture gone with it.
      bots.setMe(const BotUser(name: 'Leo'), null);
      expect(bots.myPicture, isNull);
      expect(
        folders.files.keys.where((f) => p.basename(f).startsWith('me-')),
        isEmpty,
      );
    });

    test('its files, read again after its turn; how far it is trusted stays '
        'the user\'s', () async {
      final assistant = bots.bots.single;
      void write(String path, String text) =>
          folders.writeFile(path, Uint8List.fromList(utf8.encode(text)));
      String read(String path) => utf8.decode(folders.files[path]!);
      final cardPath = '${assistant.folder}/BOT.md';
      // Its own card: its name, its to change; its abilities not.
      write(
        cardPath,
        read(cardPath)
            .replaceFirst('name: 小宝', 'name: 宝宝')
            .replaceFirst('agents: true', 'agents: false')
            .replaceFirst('browser: true', 'browser: false'),
      );
      // A bot it made, saying it is the assistant, on the computer.
      folders.make('/bots/cat');
      write(
        '/bots/cat/BOT.md',
        '---\nname: 阿猫\navatar: 🐱\nagents: true\nassistant: true\n'
            '---\n\n你是一只懒猫\n',
      );
      write('/bots/cat/LATER.md', '- 2026-10-29 16:00 喊用户喝水\nmine\n');
      write('/bots/USER.md', '---\nname: Leo\n---\n');
      // Its turn, done.
      final session = bots.threadFor(assistant).session;
      session.send(const ComposerMessage(text: 'hi'));
      for (var i = 0; i < 300 && !session.isStreaming; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      session.stop();
      for (var i = 0; i < 300 && bots.bots.first.name != '宝宝'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final self = bots.bots.first;
      expect(self.name, '宝宝');
      expect(self.can(BotAbility.agents), isTrue);
      expect(self.can(BotAbility.browser), isTrue);
      expect(read(cardPath), contains('agents: true'));
      expect(read(cardPath), contains('browser: true'));
      final cat = bots.byId('cat')!;
      expect(cat.avatar, '🐱');
      expect(cat.identity, '你是一只懒猫');
      expect(cat.assistant, isFalse);
      expect(cat.abilities, isEmpty);
      expect(cat.created, now);
      expect(read('/bots/cat/BOT.md'), contains('agents: false'));
      expect(bots.threadOf(cat), isNotNull);
      expect(bots.laters(cat).single.at, DateTime(2026, 10, 29, 16));
      expect(bots.me.name, 'Leo');
      // Come due: its line gone, what else it wrote kept.
      now = DateTime(2026, 10, 29, 16, 1);
      bots.deliver();
      expect(read('/bots/cat/LATER.md'), 'mine\n');
      // Gone with its folder.
      folders.delete('/bots/cat');
      bots.reload(by: self);
      expect(bots.byId('cat'), isNull);
      // The user, by hand: as they wrote it.
      write(
        cardPath,
        read(cardPath).replaceFirst('agents: true', 'agents: false'),
      );
      bots.reload();
      expect(bots.bots.first.can(BotAbility.agents), isFalse);
    });

    test('every bot changes its own profile: with bot_edit_me, or in its '
        'files, a picture by its path, cut square', () async {
      final wide = base64.decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAAB/qH1jAAAAEklEQVR4nGP4z8Dw'
        'HxkzoAsAAA8hD/EEN8afAAAAAElFTkSuQmCC',
      );
      final made = File('$app/made.png')..writeAsBytesSync(wide);
      Future<Bot> changed(String id, bool Function(Bot) done) async {
        for (var i = 0; i < 300 && !done(bots.byId(id)!); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        return bots.byId(id)!;
      }

      // Its tool, and told how.
      final mia = bots.save(name: 'Mia', identity: '', abilities: {});
      final told = workspace.agentSetup!(mia.folder)!.workspace().instructions;
      expect(told, contains('<your_profile>'));
      expect(told, contains('bot_edit_me'));
      await call(mia, 'bot_edit_me', {'emoji': '🐱', 'signature': '困'});
      expect(
        (bots.byId(mia.id)!.avatar, bots.byId(mia.id)!.signature),
        ('🐱', '困'),
      );
      await call(mia, 'bot_edit_me', {'picture': made.path});
      final pictured = bots.byId(mia.id)!;
      expect(isAvatarImage(pictured.avatar), isTrue);
      expect(pictured.name, 'Mia');
      // Not told what it did itself.
      final miaSession = bots.threadFor(mia).session;
      expect(
        [for (var i = 0; i < miaSession.itemCount; i++) miaSession.itemAt(i)]
            .whereType<UserMessageItem>(),
        isEmpty,
      );

      // Its card, the picture's path in it (by the user's hand).
      final self = bots.bots.first;
      final card = '${self.folder}/BOT.md';
      void write(String text) =>
          folders.writeFile(card, Uint8List.fromList(utf8.encode(text)));
      String read() => utf8.decode(folders.files[card]!);
      write(
        read().replaceFirst(
          'name: 小宝\n',
          'name: 小宝\navatar: ${made.path}\nsignature: 摸鱼中\n',
        ),
      );
      bots.reload(by: self);
      expect(bots.byId(self.id)!.signature, '摸鱼中');
      expect(bots.byId(self.id)!.avatar, isNull);
      final taken = await changed(self.id, (b) => b.avatar != null);
      expect(taken.avatar, matches(RegExp(r'^avatar-[0-9a-f]{12}\.png$')));
      expect(read(), contains('avatar: ${taken.avatar}'));
      final square = await decodeImageFromList(
        folders.files[taken.avatarFile]!,
      );
      expect((square.width, square.height), (2, 2));
      expect(made.existsSync(), isTrue);
      // One copied into its folder: taken, the copy gone.
      folders.writeFile('${self.folder}/cat.png', wide);
      write(read().replaceFirst('avatar: ${taken.avatar}', 'avatar: cat.png'));
      bots.reload(by: self);
      final again = await changed(self.id, (b) => b.avatar != taken.avatar);
      expect(again.avatar, matches(RegExp(r'^avatar-[0-9a-f]{12}\.png$')));
      expect(folders.files, isNot(contains('${self.folder}/cat.png')));
      // None there: as it was, and told.
      write(
        read().replaceFirst('avatar: ${again.avatar}', 'avatar: /no/x.png'),
      );
      bots.reload(by: self);
      final session = bots.threadFor(self).session;
      for (var i = 0; i < 300 && session.itemCount == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final note = session.itemAt(0) as UserMessageItem;
      expect(ChatCodec.botEvent(note), contains('/no/x.png could not be used'));
      expect(bots.byId(self.id)!.avatar, again.avatar);
      expect(read(), contains('avatar: ${again.avatar}'));
      // Edited by hand, then a tool, in one turn: neither lost.
      write(read().replaceFirst('signature: 摸鱼中', 'signature: 在线'));
      await call(self, 'bot_edit_me', {'emoji': '🐼'});
      expect(read(), contains('signature: 在线'));
      expect(read(), contains('avatar: 🐼'));
      expect(bots.byId(self.id)!.signature, '在线');
    });

    test(
      'a picture the user sends, kept in its folder for its tools',
      () async {
        final wide = base64.decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAAB/qH1jAAAAEklEQVR4nGP4z8Dw'
          'HxkzoAsAAA8hD/EEN8afAAAAAElFTkSuQmCC',
        );
        final mia = bots.save(name: 'Mia', identity: '', abilities: {});
        final session = bots.threadFor(mia).session;
        session.send(
          ComposerMessage(
            text: '[Image #3] 用这个当头像',
            images: [
              ImageAttachment(bytes: wide, mediaType: 'image/png', number: 3),
            ],
          ),
        );
        final kept = '${mia.folder}/${Bots.receivedPicture(3)}';
        for (var i = 0; i < 300 && !folders.files.containsKey(kept); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final png = await decodeImageFromList(folders.files[kept]!);
        expect((png.width, png.height), (4, 2));
        session.stop();
        // By its path from its folder.
        await call(mia, 'bot_edit_me', {'picture': 'received/image-3.png'});
        expect(isAvatarImage(bots.byId(mia.id)!.avatar), isTrue);
      },
    );

    test('the assistant\'s folder removed: it starts again, as new', () async {
      final first = bots.bots.first;
      final renamed = bots.save(
        id: first.id,
        name: '包包',
        identity: '另一个设定',
        abilities: first.abilities,
      );
      bots.setMemory(renamed, '- 喜欢乌龙茶');
      final old = bots.threadFor(renamed);
      expect(old.session.itemCount, greaterThan(0));
      folders.delete(renamed.folder);
      bots.reload();
      final fresh = bots.bots.first;
      expect(fresh.assistant, isTrue);
      expect(fresh.name, '小宝');
      expect(fresh.identity, isNot('另一个设定'));
      expect(bots.memory(fresh), isEmpty);
      expect(
        utf8.decode(folders.files['${fresh.folder}/BOT.md']!),
        contains('name: 小宝'),
      );
      final thread = bots.threadFor(fresh);
      expect(thread, isNot(same(old)));
      expect(thread.session.itemCount, 0);
    });

    test('a card, read back as written', () {
      final bot = Bot(
        id: 'b1',
        name: 'Mia: the cat',
        folder: '/bots/b1',
        avatar: '🐱',
        gender: '女',
        signature: '#1 lazy',
        identity: '你是一只懒猫\n\n爱睡觉',
        style: '短句',
        abilities: {BotAbility.agents},
        model: 'opus',
        created: DateTime(2026, 10, 29, 9, 5),
      );
      final card = BotFiles.cardText(bot);
      expect(card, startsWith('---\nname: "Mia: the cat"\navatar: 🐱\n'));
      expect(card, contains('signature: "#1 lazy"'));
      expect(card, contains('created: 2026-10-29 09:05'));
      expect(card, endsWith('---\n\n你是一只懒猫\n\n爱睡觉\n'));
      final back = BotFiles.read('/bots/b1', card, style: '短句\n')!;
      expect(BotFiles.cardText(back), card);
      expect(back.style, '短句');
      expect(back.abilities, {BotAbility.agents});
      // As a person writes one: little said.
      final little = BotFiles.read(
        '/bots/b2',
        '---\nname: Ann # mine\n---\nHi',
      )!;
      expect(little.name, 'Ann');
      expect(little.abilities, isEmpty);
      expect(little.identity, 'Hi');
      expect(BotFiles.read('/bots/b3', 'no card'), isNull);
    });

    test('it tells of an agent at work a long while, once', () async {
      final bot = toldOfAll();
      final agent = workspace.startAgent(workspace.projectAt(app));
      agent.session.send(const ComposerMessage(text: 'build it'));
      for (var i = 0; i < 300 && !agent.session.isStreaming; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      workspace.notifyListeners();
      addTearDown(agent.session.stop);
      now = now.add(const Duration(minutes: 29));
      bots.checkRunning();
      now = now.add(const Duration(minutes: 2));
      bots.checkRunning();
      now = now.add(const Duration(minutes: 2));
      bots.deliver();
      expect(notes(bot).single, contains('running: "${agent.title}"'));
      expect(notes(bot).single, contains('running for 31 min'));
      // Not again, while it runs on.
      now = now.add(const Duration(hours: 1));
      bots.checkRunning();
      now = now.add(const Duration(hours: 1));
      bots.deliver();
      expect(notes(bot), hasLength(1));
    });

    Future<AgentThread> runAndFinish() async {
      final agent = workspace.startAgent(workspace.projectAt(app));
      agent.session.send(const ComposerMessage(text: 'build it'));
      for (var i = 0; i < 300 && !agent.session.isStreaming; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      workspace.notifyListeners();
      agent.session.stop();
      for (var i = 0; i < 300 && agent.session.isStreaming; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      workspace.notifyListeners();
      now = now.add(const Duration(minutes: 2));
      return agent;
    }

    test('the assistant is told of no agent at first; of one it started, '
        'yes', () async {
      final assistant = bots.bots.single;
      expect(assistant.can(BotAbility.proactive), isFalse);
      await runAndFinish();
      bots.deliver();
      expect(notes(assistant), isEmpty);
      // An old card, saying nothing of it: off still.
      expect(
        BotFiles.read(
          '/bots/assistant',
          '---\nname: 小宝\nassistant: true\n---\n',
        )!.abilities,
        BotFiles.assistantAbilities,
      );
    });

    test('with no phone paired, told of nothing nor come back to', () async {
      var paired = false;
      bots.hasPhone = () => paired;
      final bot = toldOfAll();
      await runAndFinish();
      bots.later(bot, const Duration(minutes: 1), 'Ask how it went');
      now = now.add(const Duration(minutes: 5));
      bots.deliver();
      expect(notes(bot), isEmpty);
      // Paired: what it meant to come back to, now; what happened meanwhile
      // was never kept.
      paired = true;
      bots.phonesChanged();
      bots.deliver();
      expect(notes(bot).single, contains('Ask how it went'));
      expect(notes(bot).single, isNot(contains('done:')));
    });

    test('told it may ignore what happened to agents its chat does not '
        'need', () {
      expect(botEvents, contains('yours to ignore unless this chat needs it'));
      final bot = bots.bots.single;
      expect(
        botAbilities(bot),
        contains('only of the agents you started or wrote to'),
      );
      expect(
        botAbilities(bot.copyWith(abilities: {BotAbility.proactive})),
        contains('when any of the user'),
      );
    });
  });
}

Duration seconds(int n) => Duration(seconds: n);
Duration minutes(int n) => Duration(minutes: n);
