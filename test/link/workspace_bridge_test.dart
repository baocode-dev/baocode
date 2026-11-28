import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart';
import 'package:bao_remote/claude.dart' show ClaudeHistoryPage;
import 'package:baocode/chat/chat_session.dart' show ComposerMessage, UserPlace;
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/reply_suggestions.dart';
import 'package:baocode/bots/bot_folders.dart';
import 'package:baocode/bots/bot_groups.dart';
import 'package:baocode/bots/bots.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/models/codex/codex_service.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/link/chat_codec.dart';
import 'package:baocode/link/link_quota.dart';
import 'package:baocode/link/workspace_bridge.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kernel_test.dart' show FakeCli;

/// A conversation of six turns (a prompt and an answer each), read three
/// at a time from its end: u4..u6, then u1..u3.
void main() {
  Map<String, Object?> prompt(String id) => {
    'type': 'user',
    'uuid': id,
    'message': {'role': 'user', 'content': id},
  };

  Map<String, Object?> answer(String id) => {
    'type': 'assistant',
    'uuid': 'a-$id',
    'message': {
      'id': 'm-$id',
      'role': 'assistant',
      'model': 'claude-opus-5-5',
      'content': [
        {'type': 'text', 'text': 'answer $id'},
      ],
    },
  };

  ClaudeHistoryPage page(List<String> ids, {String? earlier}) =>
      ClaudeHistoryPage([
        for (final id in ids) ...[prompt(id), answer(id)],
      ], earlier: earlier);

  final asked = <String?>[];

  late Workspace workspace;
  late FakeCli cli;
  late WorkspaceBridge bridge;
  late LinkPeer phone;
  late String id;
  final updates = <LinkSessionUpdate>[];

  setUp(() async {
    asked.clear();
    updates.clear();
    late final KernelDescriptor descriptor;
    descriptor = KernelDescriptor(
      id: 'claude-code',
      label: 'Claude Code',
      icon: Icons.auto_awesome_rounded,
      description: '',
      catalog: _KeptCatalog(),
      create: (context) => ClaudeCodeKernel(
        descriptor,
        KernelContext(
          cwd: '/p',
          resume: SessionRecord(
            id: 's',
            title: 't',
            updatedAt: DateTime(2026),
            cwd: '/p',
          ),
        ),
        start: (_) async => cli = FakeCli(),
        readHistoryPage: (session, {required turns, before}) async {
          asked.add(before);
          return switch (before) {
            null => page(['u4', 'u5', 'u6'], earlier: 'u4'),
            'u4' => page(['u1', 'u2', 'u3']),
            _ => page(const []),
          };
        },
      ),
    );
    workspace = Workspace(
      projects: const [Project('p', '/p')],
      kernels: [descriptor],
    );
    final thread = workspace.startAgent(workspace.projects.first);
    thread.session.attach();
    await pumpEventQueue();
    id = WorkspaceBridge.idOf(thread);

    final LinkPeer desktop;
    (phone, desktop) = await peers();
    bridge = WorkspaceBridge(
      workspace: workspace,
      peer: desktop,
      device: () => const DeviceInfo(name: 'Mac', kind: 'mac', system: 'macOS'),
      quota: LinkQuota(
        providers: ModelProviders.memory(),
        codex: CodexUnavailable(),
      ),
      throttle: const Duration(milliseconds: 10),
    )..start();
    final sub = phone.events
        .where((e) => e.name == LinkEvents.session)
        .listen(
          (e) => updates.add(
            LinkSessionUpdate.fromJson(e.data! as Map<String, Object?>),
          ),
        );
    addTearDown(sub.cancel);
  });

  tearDown(() {
    bridge.dispose();
    workspace.dispose();
  });

  Future<LinkSessionUpdate> open([int? window]) async =>
      LinkSessionUpdate.fromJson(
        (await bridge.handle(LinkMethods.open, {
              'session': id,
              'window': ?window,
            }))!
            as Map<String, Object?>,
      );

  List<String> texts(List<Object?> items) => [
    for (final json in items)
      switch (ChatCodec.decode(json)) {
        UserMessageItem(:final text) => text,
        _ => '-',
      },
  ];

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await pumpEventQueue();
  }

  group('without a window', () {
    test('gives everything, and says nothing of earlier', () async {
      final opened = await open();
      expect(opened.start, 0);
      expect(opened.count, 6);
      expect(opened.earlier, isNull);
      expect(opened.toJson().containsKey('earlier'), isFalse);
    });

    test('an earlier call is refused', () async {
      await open();
      expect(
        bridge.handle(LinkMethods.earlier, {'session': id}),
        throwsA(isA<LinkRemoteException>()),
      );
    });

    test(
      'is sent all again from the start once the desktop prepends',
      () async {
        await open();
        final session = workspace.threads.first.session;
        await session.loadEarlier();
        await settle();
        final update = updates.last;
        expect(update.start, 0);
        expect(update.count, 12);
        expect(update.earlier, isNull);
      },
    );
  });

  group('with a window', () {
    test('gives the last items, counted from the first of them', () async {
      final opened = await open(4);
      expect(opened.start, 0);
      expect(opened.count, 4);
      expect(texts(opened.items), ['u5', '-', 'u6', '-']);
      expect(opened.earlier, isTrue);
    });

    test(
      'opened again with what the phone has: only what is new comes',
      () async {
        final first = await open(4);
        final have = [for (final item in first.items) linkDigest(item)];
        final session = workspace.threads.first.session;
        session.send(const ComposerMessage(text: 'more'));
        await settle();
        final again = LinkSessionUpdate.fromJson(
          (await bridge.handle(LinkMethods.open, {
                'session': id,
                'window': 4,
                'have': have,
              }))!
              as Map<String, Object?>,
        );
        // From where the phone's first item is: its four left out.
        expect(again.start, 4);
        expect(again.count, greaterThan(4));
        expect(texts(again.items).first, 'more');
        expect(again.earlier, isTrue);
        // What the desktop does not have (another conversation's): all of it.
        final other = LinkSessionUpdate.fromJson(
          (await bridge.handle(LinkMethods.open, {
                'session': id,
                'window': 4,
                'have': [linkDigest('elsewhere')],
              }))!
              as Map<String, Object?>,
        );
        expect(other.start, 0);
        expect(other.count, 4);
      },
    );

    test('a window beyond the items has all, and no earlier', () async {
      final opened = await open(100);
      expect(opened.count, 6);
      // u3's history is not read yet.
      expect(opened.earlier, isTrue);
    });

    test('a new item is a delta counted from the first', () async {
      await open(4);
      final session = workspace.threads.first.session;
      session.send(const ComposerMessage(text: 'more'));
      await settle();
      final update = updates.last;
      expect(update.start, 4);
      expect(update.count, greaterThan(4));
      expect(texts(update.items).first, 'more');
    });

    test(
      'the desktop reading earlier changes nothing but what is known',
      () async {
        await open(4);
        final session = workspace.threads.first.session;
        await session.loadEarlier();
        await settle();
        // Nothing of the phone's items changed: no update, or one of nothing.
        for (final update in updates) {
          expect(update.items, isEmpty);
          expect(update.count, 4);
        }
        // Its next item lands after the window, not at the shifted index.
        session.send(const ComposerMessage(text: 'more'));
        await settle();
        expect(updates.last.start, 4);
      },
    );

    test('earlier gives the items before, oldest first', () async {
      await open(4);
      final reply =
          (await bridge.handle(LinkMethods.earlier, {
                'session': id,
                'count': 2,
              }))!
              as Map<String, Object?>;
      expect(texts(reply['items']! as List), ['u4', '-']);
      expect(reply['earlier'], isTrue);
      final more =
          (await bridge.handle(LinkMethods.earlier, {'session': id}))!
              as Map<String, Object?>;
      // The window reached the start: the desktop read earlier ones.
      expect(asked, [null, 'u4']);
      expect(texts(more['items']! as List), [
        'u1', '-', 'u2', '-', 'u3', '-', //
      ]);
      expect(more['earlier'], isFalse);
    });

    test('deltas stay right after earlier', () async {
      await open(2);
      await bridge.handle(LinkMethods.earlier, {'session': id, 'count': 4});
      updates.clear();
      final session = workspace.threads.first.session;
      session.send(const ComposerMessage(text: 'more'));
      await settle();
      // 2 + 4 items now; the new one comes right after them.
      expect(updates.last.start, 6);
      expect(texts(updates.last.items).first, 'more');
    });

    test(
      'earlier reads the history when the window reaches the first',
      () async {
        await open(6);
        expect(asked, [null]);
        final reply =
            (await bridge.handle(LinkMethods.earlier, {
                  'session': id,
                  'count': 4,
                }))!
                as Map<String, Object?>;
        expect(asked, [null, 'u4']);
        expect(texts(reply['items']! as List), ['u2', '-', 'u3', '-']);
        expect(reply['earlier'], isTrue);
      },
    );

    test('earlier of a session not followed is refused', () async {
      expect(
        bridge.handle(LinkMethods.earlier, {'session': id}),
        throwsA(isA<LinkRemoteException>()),
      );
    });
  });

  test('a new agent keeps its id here, its session\'s as its alias', () async {
    late final KernelDescriptor descriptor;
    late FakeCli fake;
    descriptor = KernelDescriptor(
      id: 'claude-code',
      label: 'Claude Code',
      icon: Icons.auto_awesome_rounded,
      description: '',
      create: (context) => ClaudeCodeKernel(
        descriptor,
        context,
        start: (_) async => fake = FakeCli(),
      ),
    );
    final fresh = Workspace(
      projects: const [Project('p', '/p')],
      kernels: [descriptor],
    );
    addTearDown(fresh.dispose);
    final thread = fresh.startAgent(fresh.projects.first);
    thread.session.attach();
    // Given work, as session_new does: listed from then on.
    thread.session.send(ComposerMessage(text: 'go'));
    await pumpEventQueue();
    final (_, desktop) = await peers();
    final newBridge = WorkspaceBridge(
      workspace: fresh,
      peer: desktop,
      device: () => const DeviceInfo(name: 'Mac', kind: 'mac', system: 'macOS'),
    );
    addTearDown(newBridge.dispose);
    // Nothing said in it yet: the phone is told of it by an id given here.
    final phoneId = WorkspaceBridge.idOf(thread);
    expect(thread.id, isNull);
    expect(phoneId, startsWith('new-'));
    expect(newBridge.state().sessions.single.alias, isNull);

    // Its session's own id, once its process gives one: what the agents'
    // tools call it, and so what a bot's card names it by. The phone's id
    // does not change under it.
    fake.push({'type': 'system', 'subtype': 'init', 'session_id': 'k1'});
    await pumpEventQueue();
    expect(thread.id, 'k1');
    expect(WorkspaceBridge.idOf(thread), phoneId);
    final summary = newBridge.state().sessions.single;
    expect(summary.id, phoneId);
    expect(summary.alias, 'k1');
    expect(SessionSummary.fromJson(summary.toJson()).alias, 'k1');
  });

  test('a conversation read anew is followed anew, all of it sent', () async {
    await workspace.refresh();
    final kept = workspace.threads.firstWhere(
      (thread) => thread.record?.id == 'k',
    );
    final keptId = WorkspaceBridge.idOf(kept);
    await bridge.handle(LinkMethods.open, {'session': keptId, 'window': 2});
    await settle();
    final was = kept.session;
    updates.clear();

    workspace.reload(kept);
    await settle();
    expect(identical(kept.session, was), isFalse);
    // All of it again, of the conversation read anew: as it opened, its
    // history as it is read.
    expect(updates, isNotEmpty);
    expect(updates.map((update) => update.session), everyElement(keptId));
    expect(updates.first.start, 0);
    expect(texts(updates.last.items), ['u4', '-', 'u5', '-', 'u6', '-']);
    // Earlier ones from the conversation read anew.
    final earlier = await bridge.handle(LinkMethods.earlier, {
      'session': keptId,
      'count': 2,
    });
    expect(earlier, isNotNull);
  });

  test('a message from the phone tells the agent so, unseen', () async {
    await bridge.handle(LinkMethods.send, {'session': id, 'text': 'go'});
    await settle();
    final content = (cli.users.last['message']! as Map)['content']! as List;
    expect(
      [for (final block in content) (block as Map)['text']],
      // The user's, as one written at the computer is: suggestions asked
      // for too.
      [UserPlace.phone.note, ReplySuggestions.on, 'go'],
    );
  });

  test('streamed text goes as what was added, and adds up the same', () async {
    final mirror = LinkSessionMirror()
      ..opened(
        jsonDecode(
          jsonEncode(await bridge.handle(LinkMethods.open, {'session': id})),
        ) as Map<String, Object?>,
      );
    final wire = <Map<String, Object?>>[];
    final sub = phone.events
        .where((e) => e.name == LinkEvents.session)
        .listen((e) => wire.add(e.data! as Map<String, Object?>));
    addTearDown(sub.cancel);
    await bridge.handle(LinkMethods.send, {'session': id, 'text': 'go'});
    await settle();
    Future<void> stream(Map<String, Object?> event) async {
      cli.push({'type': 'stream_event', 'event': event});
      await settle();
    }

    await stream({
      'type': 'message_start',
      'message': {
        'id': 'm-live',
        'usage': {'input_tokens': 1},
      },
    });
    await stream({
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    });
    for (final words in ['Once ', 'upon ', 'a ', 'time']) {
      await stream({
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'text_delta', 'text': words},
      });
    }
    final whole = [for (final update in wire) mirror.apply(update)];
    expect(whole, everyElement(isNotNull));
    expect(wire.where((w) => w['append'] != null), isNotEmpty);
    expect(wire.skip(1).where((w) => w['partial'] != true), isEmpty);

    final fresh = await open();
    final last = whole.last!;
    expect(last['count'], fresh.count);
    final items = last['items']! as List;
    expect(
      jsonEncode(items),
      jsonEncode(fresh.items.sublist(fresh.count - items.length)),
    );
    expect(jsonEncode(fresh.items), contains('Once upon a time'));
  });

  test('a task\'s output is watched: what was added, then all again', () async {
    var text = 'one\n';
    final sent = <LinkOutput>[];
    final watch = OutputWatch(
      session: 's',
      task: 't',
      text: text,
      read: () async => text,
      emit: sent.add,
      every: const Duration(milliseconds: 5),
    );
    addTearDown(watch.dispose);
    text += 'two\n';
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(sent.single.text, 'two\n');
    expect(sent.single.offset, text.length);
    expect(sent.single.reset, isFalse);

    // Cut and written again: the phone is sent its tail whole.
    text = 'fresh\n';
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(sent.last.reset, isTrue);
    expect(sent.last.text, 'fresh\n');

    // More at once than the phone keeps: its tail, whole.
    text += 'x' * (LinkLimits.output + 10);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(sent.last.reset, isTrue);
    expect(sent.last.text.length, LinkLimits.output);
    final count = sent.length;
    watch.dispose();
    text += 'more';
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(sent, hasLength(count));
  });

  test('a plan is not started while none awaits', () async {
    await open();
    expect(
      bridge.handle(LinkMethods.startPlan, {'session': id}),
      throwsA(
        isA<LinkRemoteException>().having(
          (e) => e.code,
          'code',
          LinkErrors.notFound,
        ),
      ),
    );
  });

  group('edit', () {
    test('an answer is not a message to edit', () async {
      await open();
      expect(
        bridge.handle(LinkMethods.edit, {
          'session': id,
          'index': 1,
          'text': 'again',
        }),
        throwsA(
          isA<LinkRemoteException>().having(
            (e) => e.code,
            'code',
            LinkErrors.notFound,
          ),
        ),
      );
    });

    test('the index is counted from the phone\'s first item', () async {
      // a5, u6, a6: the phone's 1 is the session's u6.
      final first = await open(3);
      expect(texts(first.items), ['-', 'u6', '-']);
      await bridge.handle(LinkMethods.edit, {
        'session': id,
        'index': 1,
        'text': 'u6 again',
      });
      // Counted from the session's first, its 1 would be an answer.
      expect(
        bridge.handle(LinkMethods.edit, {
          'session': id,
          'index': 0,
          'text': 'a5 is no message',
        }),
        throwsA(isA<LinkRemoteException>()),
      );
    });

    test('what sending a message again would put back of the files is '
        'asked by the same index', () async {
      await open(3);
      // Nothing the agent changed is known: nothing to ask.
      expect(
        await bridge.handle(LinkMethods.rewindPlan, {
          'session': id,
          'index': 1,
        }),
        {'files': <Object?>[], 'setting': 'ask'},
      );
      expect(
        bridge.handle(LinkMethods.rewindPlan, {'session': id, 'index': 0}),
        throwsA(isA<LinkRemoteException>()),
      );
    });
  });

  group('image', () {
    test('a file that is not a picture is refused', () async {
      expect(
        bridge.handle(LinkMethods.image, {'project': '/p', 'path': 'a.txt'}),
        throwsA(isA<LinkRemoteException>()),
      );
    });

    test('a picture not there is not found', () async {
      expect(
        bridge.handle(LinkMethods.image, {'project': '/p', 'path': 'x.png'}),
        throwsA(
          isA<LinkRemoteException>().having(
            (e) => e.code,
            'code',
            LinkErrors.notFound,
          ),
        ),
      );
    });
  });

  test('a bot\'s agent: its model the user picks, not how it asks', () async {
    late final KernelDescriptor descriptor;
    descriptor = KernelDescriptor(
      id: 'claude-code',
      label: 'Claude Code',
      icon: Icons.auto_awesome_rounded,
      description: '',
      create: (context) =>
          ClaudeCodeKernel(descriptor, context, start: (_) async => FakeCli()),
    );
    final workspace = Workspace(kernels: [descriptor]);
    addTearDown(workspace.dispose);
    final bots = Bots(workspace: workspace, folders: MemoryBotFolders());
    await bots.start();
    addTearDown(bots.dispose);
    final (_, desktop) = await peers();
    final withBots = WorkspaceBridge(
      workspace: workspace,
      peer: desktop,
      device: () => const DeviceInfo(name: 'Mac', kind: 'mac', system: 'macOS'),
      bots: bots,
    );
    addTearDown(withBots.dispose);
    final assistant = bots.bots.single;
    final thread = bots.threadFor(assistant);
    final session = WorkspaceBridge.idOf(thread);
    expect(
      withBots.handle(LinkMethods.choose, {
        'session': session,
        'kind': 'permission',
        'option': 'bypassPermissions',
      }),
      throwsA(
        isA<LinkRemoteException>().having(
          (e) => e.code,
          'code',
          LinkErrors.unsupported,
        ),
      ),
    );
    final models = thread.session.models!;
    final other = models.options.firstWhere((o) => o != models.selected);
    await withBots.handle(LinkMethods.choose, {
      'session': session,
      'kind': 'model',
      'option': other.id,
    });
    expect(bots.byId('assistant')!.model, other.id);
    expect(
      withBots.state().bots.single,
      isA<LinkBot>().having((b) => b.model, 'model', other.label),
    );
  });

  test('a bot\'s picture: sent with it, asked for, kept', () async {
    final workspace = Workspace();
    addTearDown(workspace.dispose);
    final bots = Bots(workspace: workspace, folders: MemoryBotFolders());
    await bots.start();
    addTearDown(bots.dispose);
    final (_, desktop) = await peers();
    final withBots = WorkspaceBridge(
      workspace: workspace,
      peer: desktop,
      device: () => const DeviceInfo(name: 'Mac', kind: 'mac', system: 'macOS'),
      bots: bots,
    );
    addTearDown(withBots.dispose);
    final jpeg = base64.encode([255, 216, 255, 1, 2, 3]);
    final made = (await withBots.handle(LinkMethods.saveBot, {
      'name': 'Mia',
      'identity': '',
      'abilities': <String>[],
      'avatarImage': {'data': jpeg, 'type': 'image/jpeg'},
    }) as Map)['bot'];
    final mia = LinkBot.fromJson(made as Map<String, Object?>);
    expect(mia.hasAvatarImage, isTrue);
    expect(mia.avatar, endsWith('.jpg'));
    expect(await withBots.handle(LinkMethods.botAvatar, {'bot': mia.id}), {
      'type': 'image/jpeg',
      'data': jpeg,
    });
    // Kept by its name as other things change.
    await withBots.handle(LinkMethods.saveBot, {
      'bot': mia.id,
      'name': 'Mia B.',
      'avatar': mia.avatar,
      'identity': '',
      'abilities': <String>[],
    });
    expect(bots.byId(mia.id)!.avatar, mia.avatar);
    // What is not a picture, or too large, is refused.
    for (final image in [
      {'data': jpeg, 'type': 'text/html'},
      {
        'data': base64.encode(List.filled(LinkLimits.avatar + 1, 0)),
        'type': 'image/png',
      },
    ]) {
      expect(
        withBots.handle(LinkMethods.saveBot, {
          'bot': mia.id,
          'name': 'Mia',
          'identity': '',
          'abilities': <String>[],
          'avatarImage': image,
        }),
        throwsA(isA<LinkRemoteException>()),
      );
    }
    // None for one with an emoji.
    expect(
      withBots.handle(LinkMethods.botAvatar, {'bot': 'assistant'}),
      throwsA(
        isA<LinkRemoteException>().having(
          (e) => e.code,
          'code',
          LinkErrors.notFound,
        ),
      ),
    );
  });

  test('a group: made, its messages sent and read, its new ones as they '
      'come to a phone that has it open', () async {
    final workspace = Workspace();
    addTearDown(workspace.dispose);
    final bots = Bots(workspace: workspace, folders: MemoryBotFolders());
    await bots.start();
    addTearDown(bots.dispose);
    bots.groups.tell = (_, _, _) {};
    final mia = bots.save(name: 'Mia', identity: '', abilities: {});
    final (phone, desktop) = await peers();
    final withBots = WorkspaceBridge(
      workspace: workspace,
      peer: desktop,
      device: () => const DeviceInfo(name: 'Mac', kind: 'mac', system: 'macOS'),
      bots: bots,
    )..start();
    addTearDown(withBots.dispose);
    final made = LinkGroup.fromJson(
      ((await withBots.handle(LinkMethods.saveGroup, {
                'name': '江湖',
                'members': ['assistant', mia.id],
                'gap': 30,
              }))!
              as Map)['group']
          as Map<String, Object?>,
    );
    expect(made.members, ['assistant', mia.id]);
    expect(made.gap, 30);
    expect(withBots.state().groups.single.name, '江湖');
    final png = base64.encode([137, 80, 78, 71]);
    final send = {
      'group': made.id,
      'text': ' 你们好 ',
      'images': [
        {'data': png, 'type': 'image/png'},
      ],
      'id': 'm1',
    };
    expect(await withBots.handle(LinkMethods.sendGroup, send), {'seq': 1});
    // Sent again, as when the link dropped: once.
    expect(await withBots.handle(LinkMethods.sendGroup, send), {'seq': 1});
    expect(withBots.state().groups.single.unread, 0);
    // Mia has its conversation, as the phone sees.
    final room = withBots.state().groups.single;
    expect(['assistant', mia.id], contains(room.holder));
    expect(room.passesLeft, BotGroups.passes);
    final opened =
        (await withBots.handle(LinkMethods.openGroup, {'group': made.id}))!
            as Map;
    expect(opened['more'], isFalse);
    final first = LinkGroupMessage.fromJson(
      (opened['messages'] as List).single as Map<String, Object?>,
    );
    expect((first.text, first.mine), ('你们好', true));
    expect(
      await withBots.handle(LinkMethods.groupImage, {
        'group': made.id,
        'image': first.images.single,
      }),
      {'type': 'image/png', 'data': png},
    );
    // Mia told of it, and answers.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final came = phone.events
        .firstWhere((e) => e.name == LinkEvents.group)
        .timeout(const Duration(seconds: 5));
    bots.groups.turnEnded(made.id, mia.id, '<bot_say>嗨</bot_say>');
    final event = (await came).data! as Map;
    expect(event['group'], made.id);
    expect(
      [
        for (final m in event['messages'] as List)
          LinkGroupMessage.fromJson(m as Map<String, Object?>).from,
      ],
      [mia.id],
    );
    await withBots.handle(LinkMethods.deleteGroup, {'group': made.id});
    expect(withBots.state().groups, isEmpty);
  });

  test('a bot\'s files open from its chat: by their full path', () async {
    final workspace = Workspace();
    addTearDown(workspace.dispose);
    final bots = Bots(workspace: workspace, folders: MemoryBotFolders());
    await bots.start();
    addTearDown(bots.dispose);
    final (_, desktop) = await peers();
    final withBots = WorkspaceBridge(
      workspace: workspace,
      peer: desktop,
      device: () => const DeviceInfo(name: 'PC', kind: 'pc', system: 'Win'),
      bots: bots,
    );
    addTearDown(withBots.dispose);
    final folder = Directory.systemTemp.createTempSync('bot_files');
    addTearDown(() => folder.deleteSync(recursive: true));
    final pdf = File('${folder.path}/简历.pdf')
      ..writeAsBytesSync([37, 80, 68, 70, 0, 1, 2]);
    final notes = File('${folder.path}/notes.md')..writeAsStringSync('# Hi');
    // As its reply links them, though the bot is in no project.
    expect(
      await withBots.handle(LinkMethods.read, {
        'bot': 'assistant',
        'path': notes.path,
      }),
      containsPair('text', '# Hi'),
    );
    expect(
      await withBots.handle(LinkMethods.read, {
        'bot': 'assistant',
        'path': pdf.path,
      }),
      {'binary': true},
    );
    final download = await withBots.handle(LinkMethods.download, {
      'bot': 'assistant',
      'path': pdf.path,
    }) as Map;
    expect(base64.decode(download['data'] as String), pdf.readAsBytesSync());
    // In pieces, of any size: a stretch at a time from the disk.
    final video = File('${folder.path}/clip.mp4')
      ..writeAsBytesSync([
        for (var i = 0; i < LinkLimits.download + 3; i++) i % 256,
      ]);
    final inPieces = await withBots.handle(LinkMethods.download, {
      'bot': 'assistant',
      'path': video.path,
      'pieces': true,
    }) as LinkPieces;
    expect(inPieces.size, video.lengthSync());
    final parts = await inPieces.bytes.toList();
    expect(parts.every((p) => p.length <= LinkLimits.piece), isTrue);
    expect([for (final p in parts) ...p], video.readAsBytesSync());
    expect(
      withBots.handle(LinkMethods.download, {
        'bot': 'assistant',
        'path': '${folder.path}/none.mp4',
        'pieces': true,
      }),
      throwsA(isA<LinkRemoteException>()),
    );
    expect(
      withBots.handle(LinkMethods.read, {'bot': 'nobody', 'path': pdf.path}),
      throwsA(
        isA<LinkRemoteException>().having(
          (e) => e.code,
          'code',
          LinkErrors.notFound,
        ),
      ),
    );
  });

  test('a file from the phone: kept for the agent, by its name', () async {
    final workspace = Workspace();
    addTearDown(workspace.dispose);
    final bots = Bots(workspace: workspace, folders: MemoryBotFolders());
    await bots.start();
    addTearDown(bots.dispose);
    final (_, desktop) = await peers();
    final uploads = Directory.systemTemp.createTempSync('phone_uploads');
    addTearDown(() => uploads.deleteSync(recursive: true));
    final withBots = WorkspaceBridge(
      workspace: workspace,
      peer: desktop,
      device: () => const DeviceInfo(name: 'PC', kind: 'pc', system: 'Win'),
      bots: bots,
      uploadsOf: (_, _) => '${uploads.path}/phone',
    );
    addTearDown(withBots.dispose);
    final bytes = [80, 75, 3, 4, 0, 1, 2];
    Future<Map> upload(String name) async => await withBots.handle(
      LinkMethods.upload,
      {'bot': 'assistant', 'name': name, 'data': base64.encode(bytes)},
    ) as Map;
    final first = (await upload('报价单.xlsx'))['path'] as String;
    expect(first, startsWith('${uploads.path}/phone/'));
    expect(first, endsWith('/报价单.xlsx'));
    expect(File(first).readAsBytesSync(), bytes);
    // The same name again: a folder of its own, the first one kept.
    final second = (await upload('报价单.xlsx'))['path'] as String;
    expect(second, isNot(first));
    expect(File(first).existsSync(), isTrue);
    expect(
      await withBots.handle(LinkMethods.upload, {
        'bot': 'assistant',
        'name': 'big.bin',
        'data': base64.encode(Uint8List(LinkLimits.upload + 1)),
      }),
      containsPair('tooLarge', true),
    );
  });

  test('a file from the phone in pieces: of any size', () async {
    final workspace = Workspace();
    addTearDown(workspace.dispose);
    final bots = Bots(workspace: workspace, folders: MemoryBotFolders());
    await bots.start();
    addTearDown(bots.dispose);
    final (phone, desktop) = await peers();
    final uploads = Directory.systemTemp.createTempSync('phone_uploads');
    addTearDown(() => uploads.deleteSync(recursive: true));
    final withBots = WorkspaceBridge(
      workspace: workspace,
      peer: desktop,
      device: () => const DeviceInfo(name: 'PC', kind: 'pc', system: 'Win'),
      bots: bots,
      uploadsOf: (_, _) => '${uploads.path}/phone',
    );
    addTearDown(withBots.dispose);
    desktop.onRequest = withBots.handle;
    final bytes = Uint8List.fromList([
      for (var i = 0; i < LinkLimits.upload + 5; i++) i % 253,
    ]);
    final answer = await phone.callWithPieces(
      LinkMethods.uploadPieces,
      {'bot': 'assistant', 'name': '录屏.mov'},
      bytes.length,
      Stream.fromIterable([
        Uint8List.sublistView(bytes, 0, 1000),
        Uint8List.sublistView(bytes, 1000),
      ]),
    ) as Map;
    final path = answer['path'] as String;
    expect(path, startsWith('${uploads.path}/phone/'));
    expect(path, endsWith('/录屏.mov'));
    expect(File(path).readAsBytesSync(), bytes);
    // Cut short: nothing of it left.
    final folders = uploads.listSync(recursive: true).whereType<File>().length;
    Stream<Uint8List> half() async* {
      yield Uint8List(10);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      throw const FileSystemException('gone');
    }

    await expectLater(
      phone.callWithPieces(
        LinkMethods.uploadPieces,
        {'bot': 'assistant', 'name': 'half.bin'},
        100,
        half(),
      ),
      throwsA(anything),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      uploads.listSync(recursive: true).whereType<File>(),
      hasLength(folders),
    );
  });

  test('a file from the phone keeps its name, not its folders', () {
    expect(WorkspaceBridge.uploadName('../../etc/passwd'), 'passwd');
    expect(WorkspaceBridge.uploadName(r'C:\x\a:b?.txt'), 'a_b_.txt');
    expect(WorkspaceBridge.uploadName('..'), 'file');
    expect(WorkspaceBridge.uploadName(null), 'file');
    expect(WorkspaceBridge.uploadName('合同 v2.docx'), '合同 v2.docx');
  });

  test('the plan\'s limits, as the phone reads them', () async {
    ClaudeCodeKernel.forgetAccount();
    addTearDown(ClaudeCodeKernel.forgetAccount);
    final opened = await open();
    expect(opened.quota, isNull);
    workspace.threads.first.session.send(const ComposerMessage(text: 'hi'));
    await settle();
    cli.push({
      'type': 'rate_limit_event',
      'rate_limit_info': {
        'status': 'allowed',
        'unifiedWindows': {
          'five_hour': {'utilization': 0.4, 'resetsAt': 4102444800},
          'seven_day': {'utilization': 1.0, 'resetsAt': 4102531200},
          'seven_day_opus': {'utilization': 0.25, 'resetsAt': 4102531200},
        },
      },
    });
    await settle();
    final quota = updates.last.quota!;
    expect(quota['provider'], isA<String>());
    expect(quota['back'], 4102531200000);
    expect((quota['accounts']! as List).single, {
      'windows': [
        {'minutes': 300, 'left': 60, 'resets': 4102444800000},
        {'minutes': 10080, 'left': 0, 'resets': 4102531200000},
        {'minutes': 10080, 'name': 'Opus', 'left': 75, 'resets': 4102531200000},
      ],
    });
  });

  test(
    'with acks, a stalled phone never accumulates stale updates and jumps '
    'straight to the latest state once it acks',
    () async {
      // A fresh pair without a mirror so we control acks manually.
      final (rawPhone, rawDesktop) = await peers();
      final ackBridge = WorkspaceBridge(
        workspace: workspace,
        peer: rawDesktop,
        device: () => const DeviceInfo(name: 'M', kind: 'mac', system: 'macOS'),
        throttle: const Duration(milliseconds: 5),
        acks: true,
        maxInFlight: 1,
      )..start();
      addTearDown(() async {
        ackBridge.dispose();
        await rawPhone.close();
        await rawDesktop.close();
      });
      final received = <Map<String, Object?>>[];
      rawPhone.events
          .where((e) => e.name == LinkEvents.session)
          .listen((e) => received.add(e.data! as Map<String, Object?>));

      final id = WorkspaceBridge.idOf(workspace.threads.first);
      await ackBridge.handle(LinkMethods.open, {'session': id});

      final session = workspace.threads.first.session;
      session.send(const ComposerMessage(text: 'go'));
      await Future<void>.delayed(const Duration(milliseconds: 25));
      // First update went out (seq 1); without an ack, further chunks coalesce.
      expect(received, hasLength(1));
      expect(received.first['seq'], 1);

      for (final chunk in ['one ', 'two ', 'three ', 'four']) {
        cli.push({
          'type': 'stream_event',
          'event': {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': chunk},
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      cli.push({'type': 'result', 'is_error': false});
      await Future<void>.delayed(const Duration(milliseconds: 25));

      // Still paused at 1 unacked frame — zero queue buildup!
      expect(received, hasLength(1));

      // Phone catches up and acks seq 1 -> desktop sends ONE update with the
      // final finished state (live: false) instead of replaying every chunk.
      await rawPhone.emit(LinkEvents.ack, {'session': id, 'seq': 1});
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(received, hasLength(2));
      expect(received.last['seq'], 2);
      expect(received.last['live'], isFalse);
    },
  );

  test('streaming thinking items use append patches', () {
    final slimmer = LinkSessionSlimmer();
    final t0 = DateTime(2026, 11, 27, 10, 0);
    final first = ChatCodec.encode(
      ThinkingItem(text: 'step 1', tokens: 10, startedAt: t0),
    );
    final second = ChatCodec.encode(
      ThinkingItem(text: 'step 1\nstep 2', tokens: 25, startedAt: t0),
    );
    final patch = jsonAppendPatch(first, second);
    expect(patch?.$1, ['text']);
    expect(patch?.$2, '\nstep 2');
    final wire = slimmer.encode(
      LinkSessionUpdate(
        session: 's',
        start: 0,
        count: 1,
        items: [second],
        live: true,
      ),
      before: first,
    );
    expect(wire['append'], {
      'index': 0,
      'path': ['text'],
      'text': '\nstep 2',
    });
  });

  test(
    'reopening with have snaps to the latest window when many items came since',
    () async {
      final id = WorkspaceBridge.idOf(workspace.threads.first);
      final session = workspace.threads.first.session;
      session.send(const ComposerMessage(text: 'm0'));
      cli.push({'type': 'result', 'is_error': false});
      await settle();
      final first = LinkSessionUpdate.fromJson(
        (await bridge.handle(LinkMethods.open, {'session': id, 'window': 2}))!
            as Map<String, Object?>,
      );
      final have = [for (final item in first.items) linkDigest(item)];

      // Add more turns than the window (2) so the gap exceeds window.
      for (var i = 1; i <= 4; i++) {
        session.send(ComposerMessage(text: 'm$i'));
        cli.push({'type': 'result', 'is_error': false});
        await settle();
      }
      final again = LinkSessionUpdate.fromJson(
        (await bridge.handle(LinkMethods.open, {
              'session': id,
              'window': 2,
              'have': have,
            }))!
            as Map<String, Object?>,
      );
      expect(again.start, 0);
      expect(again.count, 2);
      expect(again.items, hasLength(2));
      expect(again.earlier, isTrue);
    },
  );

  test(
    'queued messages sync to the phone and can be moved, cancelled, or sent now',
    () async {
      final opened = await open();
      expect(opened.queued, isEmpty);

      // Start a turn, then send three messages with now: false so they queue
      // (q1 is handed to the CLI, q2 & q3 are held in the kernel queue).
      await bridge.handle(LinkMethods.send, {'session': id, 'text': 'turn 1'});
      final r1 =
          (await bridge.handle(LinkMethods.send, {
                'session': id,
                'text': 'queued 1',
                'now': false,
              }))!
              as Map<String, Object?>;
      final r2 =
          (await bridge.handle(LinkMethods.send, {
                'session': id,
                'text': 'queued 2',
                'now': false,
              }))!
              as Map<String, Object?>;
      final r3 =
          (await bridge.handle(LinkMethods.send, {
                'session': id,
                'text': 'queued 3',
                'now': false,
              }))!
              as Map<String, Object?>;
      final q1 = r1['turn'] as String;
      final q2 = r2['turn'] as String;
      final q3 = r3['turn'] as String;
      await settle();

      List<String> queuedTexts(LinkSessionUpdate u) => [
        for (final entry in u.queued ?? const <Map<String, Object?>>[])
          (ChatCodec.decode(entry['item']) as UserMessageItem).text,
      ];
      expect(queuedTexts(updates.last), ['queued 1', 'queued 2', 'queued 3']);

      // Reorder q3 ahead of q2.
      await bridge.handle(LinkMethods.moveQueued, {
        'session': id,
        'id': q3,
        'index': 1,
      });
      await settle();
      expect(queuedTexts(updates.last), ['queued 1', 'queued 3', 'queued 2']);

      // Cancel q2 (held in queue, so it cancels immediately).
      final cancelled =
          (await bridge.handle(LinkMethods.cancelQueued, {
                'session': id,
                'id': q2,
              }))!
              as Map<String, Object?>;
      expect(cancelled['cancelled'], isTrue);
      await settle();
      expect(queuedTexts(updates.last), ['queued 1', 'queued 3']);

      // Send q1 now (interrupts turn 1).
      await bridge.handle(LinkMethods.sendQueuedNow, {'session': id, 'id': q1});
      await settle();
      expect(
        cli.written.any(
          (m) =>
              m['type'] == 'control_request' &&
              (m['request'] as Map?)?['subtype'] == 'interrupt',
        ),
        isTrue,
      );
    },
  );
}

/// A phone's end and a desktop's, connected.
Future<(LinkPeer, LinkPeer)> peers() async {
  final (a, b) = MemoryLinkConnection.pair(
    a: LinkIdentity.generate().id,
    b: LinkIdentity.generate().id,
  );
  final accepted = LinkPeer.accept(b);
  final connected = await LinkPeer.connect(a);
  return (connected, await accepted);
}

/// Lists one kept session in the project.
class _KeptCatalog implements SessionCatalog {
  @override
  Future<List<ProjectRecord>> projects() async => [
    ProjectRecord(
      path: '/p',
      sessions: [
        SessionRecord(
          id: 'k',
          title: 'kept',
          updatedAt: DateTime(2026),
          cwd: '/p',
        ),
      ],
    ),
  ];

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) async => const [];

  @override
  Future<void> delete(String id) async {}
}
