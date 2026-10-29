import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:baocode/bots/bot.dart';
import 'package:baocode/bots/bot_folders.dart';
import 'package:baocode/bots/bot_pacer.dart';
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
    const often = BotProactive(perDay: 3, quietFrom: 0, quietTo: 0);

    test('what comes close together is told at once, what needs the user '
        'first', () {
      final pacer = BotPacer();
      pacer
        ..add(event('a', BotEventKind.done, start))
        ..add(event('b', BotEventKind.failed, start.add(seconds(20))))
        ..add(event('c', BotEventKind.waiting, start.add(seconds(40))));
      expect(pacer.take(often, start.add(seconds(60))), isNull);
      final told = pacer.take(often, start.add(seconds(90)))!;
      expect(told.map((e) => e.chat), ['c', 'b', 'a']);
      expect(pacer.hasPending, isFalse);
    });

    test('an agent\'s latest only', () {
      final pacer = BotPacer()
        ..add(event('a', BotEventKind.waiting, start))
        ..add(event('a', BotEventKind.done, start.add(seconds(10))));
      final told = pacer.take(often, start.add(const Duration(minutes: 5)))!;
      expect(told.single.kind, BotEventKind.done);
    });

    test('apart, and only so many a day', () {
      final pacer = BotPacer();
      var now = start;
      final sent = <DateTime>[];
      for (var i = 0; i < 6; i++) {
        pacer.add(event('$i', BotEventKind.failed, now));
        final due = pacer.dueAt(often, now)!;
        expect(pacer.take(often, due), isNotNull);
        sent.add(due);
        now = due;
      }
      expect(sent[1].difference(sent[0]), greaterThanOrEqualTo(minutes(20)));
      // The fourth, a day after the first.
      expect(
        sent[3].difference(sent[0]),
        greaterThanOrEqualTo(const Duration(days: 1)),
      );
    });

    test('never in the quiet hours, nor at all when set to none', () {
      const quiet = BotProactive(
        perDay: 5,
        quietFrom: 23 * 60,
        quietTo: 8 * 60,
      );
      final night = DateTime(2026, 10, 29, 23, 30);
      final pacer = BotPacer()..add(event('a', BotEventKind.failed, night));
      expect(pacer.dueAt(quiet, night), DateTime(2026, 10, 30, 8));
      expect(pacer.dueAt(const BotProactive(perDay: 0), night), isNull);
      expect(pacer.take(const BotProactive(perDay: 0), night), isNull);
    });

    test('what was done long ago is not worth telling', () {
      final pacer = BotPacer()
        ..add(event('a', BotEventKind.done, start))
        ..add(event('b', BotEventKind.waiting, start));
      final told = pacer.take(often, start.add(const Duration(hours: 7)))!;
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
      abilities: {BotAbility.viewChats},
    );

    test('the rules first, then who the user made it', () {
      final told = botInstructions(bot, memory: 'Likes tea.');
      expect(told.indexOf('<bot_rules>'), 0);
      expect(told, contains('say you are an AI'));
      expect(told, contains('No sexual or explicit content'));
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

    test('what it may do, and may not', () {
      final told = botAbilities(bot);
      expect(told, contains('bot_list_chats'));
      expect(told, contains('You cannot stop, retry or archive agents.'));
      expect(told, contains('You cannot use the browser.'));
      expect(told, contains('You cannot make pictures.'));
    });

    test('pictures: made with the image model, or said there is none', () {
      final painter = Bot(
        id: 'p',
        name: 'Pia',
        folder: '/bots/p',
        abilities: {BotAbility.images},
      );
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

    test('start with the assistant, every ability on, kept', () async {
      final assistant = bots.bots.single;
      expect(assistant.assistant, isTrue);
      expect(assistant.name, '小宝');
      expect(assistant.abilities, BotAbility.values.toSet());
      expect(folders.folders, contains(assistant.folder));
      await pumpEventQueue();
      expect(
        (store.preferences['bots'] as List).single,
        containsPair('id', 'assistant'),
      );
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
      expect(launch.permissionMode, 'dontAsk');
      expect(launch.sdkServers, [ClaudeSdkTools.server]);
      // The browser's tool search, as it may use it; no other.
      expect(launch.tools, ['ToolSearch']);
      expect(launch.arguments, containsAllInOrder(['--tools', 'ToolSearch']));
      // None of the user's MCP servers: their notices are not its to tell.
      expect(launch.arguments, contains('--strict-mcp-config'));
    });

    test(
      'a bot is offered its abilities\' tools; a project\'s agent none',
      () async {
        final assistant = bots.bots.single;
        expect(
          await offered(assistant.folder),
          containsAll(['bot_list_chats', 'bot_stop_chat', 'bot_remember']),
        );
        expect(await offered(app), isNot(contains('bot_list_chats')));
        expect(ClaudeSdkTools.serversFor(app), isEmpty);

        // A new one may do nothing until the user says.
        final mia = bots.save(
          name: 'Mia',
          identity: '',
          abilities: {BotAbility.viewChats},
        );
        final hers = await offered(mia.folder);
        expect(hers, containsAll(['bot_list_chats', 'bot_show_chat']));
        expect(hers, isNot(contains('bot_stop_chat')));
        expect(hers, isNot(contains('bot_read_file')));
        final none = bots.save(name: 'Quiet', identity: '', abilities: {});
        expect(await offered(none.folder), [
          'bot_say',
          'bot_send_image',
          'bot_remember',
        ]);
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
      expect(folders.folders, isNot(contains(mia.folder)));
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
      final kept = Bot.fromJson(
        (store.preferences['bots'] as List).last,
        root: folders.root!,
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

    test('the assistant has abilities that came since it was kept', () {
      final root = folders.root!;
      final assistant = Bot.fromJson({
        'id': 'assistant',
        'name': 'Bao',
        'assistant': true,
        'abilities': ['viewChats'],
      }, root: root)!;
      // Those the user had turned off stay off; the new ones are on.
      expect(assistant.can(BotAbility.images), isTrue);
      expect(assistant.can(BotAbility.browser), isFalse);
      // Not so for the user's own, as a new one has none.
      final mia = Bot.fromJson({
        'id': 'b1',
        'name': 'Mia',
        'abilities': ['viewChats'],
      }, root: root)!;
      expect(mia.can(BotAbility.images), isFalse);
      // Once kept with it, as the user left it.
      final off = Bot.fromJson(
        assistant.copyWith(abilities: {BotAbility.viewChats}).toJson(),
        root: root,
      )!;
      expect(off.abilities, {BotAbility.viewChats});
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
      expect(await offered(mia.folder), isNot(contains(ImageTools.name)));
      // No one at the computer to pick the model for it.
      expect(ClaudeSdkTools.asksUser(assistant.folder), isFalse);
      expect(ClaudeSdkTools.asksUser(app), isTrue);
    });

    test('it sends pictures from the web or a project', () async {
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

      // A project's picture: back as the picture, for the chat.
      final png = base64.decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
        '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      );
      File('$app/pic.png').writeAsBytesSync(png);
      final sent = await call(assistant, 'bot_send_image', {
        'project': 'app',
        'path': 'pic.png',
      });
      expect(sent['isError'], isNot(isTrue));
      expect(
        (sent['content'] as List).map((c) => (c as Map)['type']),
        contains('image'),
      );
      expect(
        (await call(assistant, 'bot_send_image', {
          'project': 'app',
          'path': '../outside.png',
        }))['isError'],
        isTrue,
      );
      // Not by one that may not read the projects' files.
      final mia = bots.save(name: 'Mia', identity: '', abilities: {});
      expect(
        (await call(mia, 'bot_send_image', {
          'project': 'app',
          'path': 'pic.png',
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

    test('it comes back later on its own, out of the quiet hours', () async {
      final bot = bots.bots.single;
      final set = await call(bot, 'bot_later', {
        'minutes': 90,
        'note': 'Ask how the interview went',
      });
      expect(set['isError'], isNot(isTrue));
      expect('${set['content']}', contains('15:30'));
      expect(bots.laters(bot).single.at, DateTime(2026, 10, 29, 15, 30));
      await pumpEventQueue();
      expect(store.preferences['later'], {
        'assistant': [
          {
            'at': DateTime(2026, 10, 29, 15, 30).millisecondsSinceEpoch,
            'note': 'Ask how the interview went',
          },
        ],
      });
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

      // At night, put off to the morning (quiet 23:00–08:00 by default).
      now = DateTime(2026, 10, 29, 22, 30);
      await call(bot, 'bot_later', {'minutes': 60, 'note': 'Remind of x'});
      expect(bots.laters(bot).single.at, DateTime(2026, 10, 30, 8));
      // Bad minutes; and none for one that may not write first.
      expect(
        (await call(bot, 'bot_later', {'minutes': 0, 'note': 'x'}))['isError'],
        isTrue,
      );
      final mia = bots.save(name: 'Mia', identity: '', abilities: {});
      expect(await offered(mia.folder), isNot(contains('bot_later')));
    });

    test('what it remembers: kept by it, seen, changed and cleared', () async {
      final bot = bots.bots.single;
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
      bots.setMemory(bot, '');
      expect(bots.memory(bot), '');
    });

    test('it writes first of an agent done, in a note of the app\'s', () async {
      final bot = bots.bots.single;
      final agent = workspace.startAgent(workspace.projects.single);
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
      final note = bots.threadOf(bot)!.session.itemAt(0);
      expect(note, isA<UserMessageItem>());
      expect(
        ChatCodec.botEvent(note as UserMessageItem),
        contains('done: "${agent.title}"'),
      );
    });

    test('it tells of an agent at work a long while, once', () async {
      final bot = bots.bots.single;
      final agent = workspace.startAgent(workspace.projects.single);
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
      final session = bots.threadOf(bot)!.session;
      expect(
        ChatCodec.botEvent(session.itemAt(0) as UserMessageItem),
        contains('running: "${agent.title}"'),
      );
      expect(
        ChatCodec.botEvent(session.itemAt(0) as UserMessageItem),
        contains('running for 31 min'),
      );
      // Not again, while it runs on.
      now = now.add(const Duration(hours: 1));
      bots.checkRunning();
      now = now.add(const Duration(hours: 1));
      bots.deliver();
      expect([
        for (var i = 0; i < session.itemCount; i++)
          if (session.itemAt(i) case final UserMessageItem item
              when ChatCodec.botEvent(item) != null)
            item,
      ], hasLength(1));
    });
  });
}

Duration seconds(int n) => Duration(seconds: n);
Duration minutes(int n) => Duration(minutes: n);
