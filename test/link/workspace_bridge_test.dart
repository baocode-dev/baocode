import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:bao_remote/claude.dart' show ClaudeHistoryPage;
import 'package:baocode/chat/chat_session.dart' show ComposerMessage;
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/bots/bot_folders.dart';
import 'package:baocode/bots/bots.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/link/chat_codec.dart';
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
        start: (_) async => FakeCli(),
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
}

/// A phone's end and a desktop's, connected.
Future<(LinkPeer, LinkPeer)> peers() async {
  final (a, b) = MemoryLinkSocket.pair();
  final desktop = LinkIdentity.generate();
  final accepted = SecureChannel.accept(b, identity: desktop);
  final connected = await SecureChannel.connect(
    a,
    identity: LinkIdentity.generate(),
    serverKey: desktop.publicKey,
  );
  return (LinkPeer(connected), LinkPeer(await accepted));
}
