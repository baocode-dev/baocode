import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/customize/customization_store.dart';
import 'package:baocode/icons/project_icon.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/kernel/agent_kernel.dart' show KernelChoiceKind;
import 'package:baocode/link/chat_codec.dart';
import 'package:baocode/link/link_host.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/workspace/project_workspace.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fake_link_platform.dart';

void main() {
  late FakeLinkPlatform platform;
  late Workspace workspace;
  late LinkHost host;
  final phone = LinkIdentity.generate();

  late Directory config;

  setUp(() async {
    platform = FakeLinkPlatform();
    workspace = Workspace.mock();
    config = await Directory.systemTemp.createTemp('link_host_test');
    host = LinkHost(
      workspace: workspace,
      platform: platform,
      customizations: CustomizationStore(
        configDir: config.path,
        homeDir: config.path,
      ),
      filesOf: (project) => (
        files: _MemoryFiles({
          '~/code/baocode/README.md': '# BaoCode',
          '~/code/baocode/lib/chat/chat_history_view.dart': 'class View {}',
          '~/code/baocode/assets/logo.png': null,
          '~/code/baocode/node_modules/x/index.js': '',
        }),
        paths: p.posix,
      ),
    );
    await host.load();
  });

  tearDown(() => config.delete(recursive: true));

  tearDown(() => host.dispose());

  /// A phone's connection to the host, over the memory network.
  Future<LinkPeer> connect(LinkIdentity identity) async {
    final connection = await platform
        .phone(identity)
        .connect(LinkAddress(host.id));
    return LinkPeer.connect(connection);
  }

  Future<LinkPeer> pair() async {
    final offer = (await host.beginPairing())!;
    final peer = await connect(phone);
    final hello = await peer.call(LinkMethods.hello, {
      'name': 'iPhone',
      'system': 'iOS 26.1',
      'token': encodeKey(offer.token),
    }) as Map;
    expect(hello['pairing'], isTrue);
    expect(host.pending!.code, safetyCode(offer.key, phone.publicKey));
    await peer.call(LinkMethods.confirm);
    return peer;
  }

  test('a phone pairs with the code shown, and is kept', () async {
    expect(host.enabled, isFalse);
    final peer = await pair();
    expect(host.enabled, isTrue);
    expect(host.status, LinkHostStatus.listening);
    expect(host.phones.single.name, 'iPhone');
    expect(host.justPaired?.id, deviceIdOf(phone.publicKey));
    expect(host.offer, isNull);
    expect(host.isConnected(deviceIdOf(phone.publicKey)), isTrue);
    expect((platform.kept['phones']! as List).length, 1);
    await peer.close();

    // Known: it gets in without a code, after a restart too.
    final again = LinkHost(workspace: workspace, platform: platform);
    addTearDown(again.dispose);
    await host.setEnabled(false);
    await again.load();
    await again.setEnabled(true);
    expect(again.phones.single.id, deviceIdOf(phone.publicKey));
    final peer2 = await connect(phone);
    final hello =
        await peer2.call(LinkMethods.hello, {'name': 'iPhone'}) as Map;
    expect((hello['device'] as Map)['name'], 'Test Mac');
    final device = DeviceInfo.fromJson(
      hello['device']! as Map<String, Object?>,
    );
    expect(device.addrs.first, '192.168.1.5:47100');
    expect(device.relays, contains(defaultLinkRelays.first));
  });

  test('the offer tells where the desktop is: relays, addresses', () async {
    final offer = (await host.beginPairing())!;
    expect(offer.id, host.id);
    expect(offer.relays, defaultLinkRelays);
    expect(offer.addrs, ['192.168.1.5:47100']);
    final parsed = PairingOffer.parse(offer.uri);
    expect(parsed.address.id, host.id);
    expect(parsed.address.relays, offer.relays);
  });

  test('one relay picked: kept to, told and bound to alone; automatic '
      'again, all of BaoCode\'s', () async {
    await host.setEnabled(true);
    expect(platform.boundRelays, defaultLinkRelays);
    // The one in use picked at first.
    await host.setRelayMode(LinkRelayMode.pinned);
    expect(host.relays, [defaultLinkRelays.first]);
    expect(platform.boundRelays, host.relays);

    await host.pinRelay(defaultLinkRelays.last);
    expect(platform.boundRelays, [defaultLinkRelays.last]);

    // One at an address of one's own.
    await host.pinRelay('https://relay.example.com');
    expect(platform.boundRelays, ['https://relay.example.com']);
    expect(platform.kept['relayMode'], 'pinned');
    expect(platform.kept['pinnedRelay'], 'https://relay.example.com');
    final offer = (await host.beginPairing())!;
    expect(offer.relays, ['https://relay.example.com']);

    await host.setRelayMode(LinkRelayMode.auto);
    expect(platform.boundRelays, defaultLinkRelays);
  });

  test('relays of one\'s own kept before there was a choice: the first '
      'picked', () async {
    host.dispose();
    platform.kept = {
      'relays': ['https://relay.example.com', 'https://relay.other.com'],
    };
    host = LinkHost(workspace: workspace, platform: platform);
    await host.load();
    expect(host.relayMode, LinkRelayMode.pinned);
    expect(host.relays, ['https://relay.example.com']);
  });

  test(
    'a connected phone\'s path is shown, and counted once settled',
    () async {
      platform.network.path = const LinkPath(
        LinkPathKind.direct,
        rtt: Duration(milliseconds: 42),
      );
      host.dispose();
      host = LinkHost(
        workspace: workspace,
        platform: platform,
        pathSettle: const Duration(milliseconds: 50),
      );
      await host.load();
      final peer = await pair();
      final id = deviceIdOf(phone.publicKey);
      expect(host.pathOf(id)?.kind, LinkPathKind.direct);
      expect(host.pathOf(id)?.rtt, const Duration(milliseconds: 42));
      await _until(() => host.pathCounts.pending != null);
      expect(host.pathCounts.pending, {'direct': 1});
      host.pathCountsSent({'direct': 1});
      expect(host.pathCounts.pending, isNull);
      await peer.close();
      await _until(() => host.pathOf(id) == null);
    },
  );

  test('phones paired over the old link are kept to pair again', () async {
    platform.kept = {
      'version': 1,
      'identity': {
        'privateKey': encodeKey(Uint8List(32)),
        'publicKey': encodeKey(Uint8List(32)),
      },
      'enabled': true,
      'port': 47100,
      'phones': [
        {
          'key': encodeKey(Uint8List(32)),
          'name': 'Old iPhone',
          'system': 'iOS 18',
          'pairedAt': 1700000000000,
        },
      ],
    };
    host.dispose();
    host = LinkHost(workspace: workspace, platform: platform);
    await host.load();
    expect(host.phones, isEmpty);
    expect(host.legacyPhones.single.name, 'Old iPhone');
    expect(host.id, hasLength(64));
    expect(host.enabled, isTrue);
    expect(platform.kept['version'], 2);
    expect((platform.kept['identity']! as Map)['kind'], 'ed25519');
    expect(platform.kept['legacyPhones'], hasLength(1));

    // Paired again under the same name: no longer listed as old.
    final offer = (await host.beginPairing())!;
    final again = await connect(phone);
    await again.call(LinkMethods.hello, {
      'name': 'Old iPhone',
      'token': encodeKey(offer.token),
    });
    await again.call(LinkMethods.confirm);
    expect(host.phones.single.name, 'Old iPhone');
    expect(host.legacyPhones, isEmpty);

    // Or let go.
    host.dispose();
    platform.kept = {
      ...platform.kept,
      'legacyPhones': [
        {'name': 'iPad', 'system': 'iPadOS', 'pairedAt': 1700000000000},
      ],
    };
    host = LinkHost(workspace: workspace, platform: platform);
    await host.load();
    host.forgetLegacy(host.legacyPhones.single);
    expect(host.legacyPhones, isEmpty);
    expect(platform.kept['legacyPhones'], isNull);
  });

  test(
    'a phone without the code, or with a wrong one, is turned away',
    () async {
      final offer = (await host.beginPairing())!;
      final stranger = await connect(LinkIdentity.generate());
      await expectLater(
        stranger.call(LinkMethods.hello, {'name': 'x'}),
        throwsA(
          isA<LinkRemoteException>().having((e) => e.code, 'code', 'unpaired'),
        ),
      );
      await expectLater(
        stranger.call(LinkMethods.state),
        throwsA(isA<LinkRemoteException>()),
      );
      final wrong = await connect(LinkIdentity.generate());
      final token = [...offer.token]..[0] ^= 1;
      await expectLater(
        wrong.call(LinkMethods.hello, {'token': encodeKey(token)}),
        throwsA(
          isA<LinkRemoteException>().having((e) => e.code, 'code', 'badToken'),
        ),
      );
      expect(host.phones, isEmpty);
    },
  );

  test(
    'codes that do not match, said on the desktop, end the pairing',
    () async {
      final offer = (await host.beginPairing())!;
      final peer = await connect(phone);
      await peer.call(LinkMethods.hello, {'token': encodeKey(offer.token)});
      host.rejectPending();
      await peer.done;
      expect(host.phones, isEmpty);
      expect(host.offer, isNull);
    },
  );

  test('the phone lists, follows and drives the agents', () async {
    final peer = await pair();
    final state = LinkState.fromJson(
      (await peer.call(LinkMethods.state))! as Map<String, Object?>,
    );
    expect(state.device.name, 'Test Mac');
    expect(
      [for (final p in state.projects) p.name],
      ['baocode', 'cursor-docs', 'api-gateway'],
    );
    expect(state.projects.first.branch, 'main');
    final first = state.sessions.firstWhere(
      (s) => s.title == 'Sticky user message on scroll',
    );
    expect(first.project, '~/code/baocode');

    final opened = LinkSessionUpdate.fromJson(
      (await peer.call(LinkMethods.open, {'session': first.id}))!
          as Map<String, Object?>,
    );
    expect(opened.start, 0);
    expect(opened.count, opened.items.length);
    expect(opened.items, isNotEmpty);
    final items = [for (final json in opened.items) ChatCodec.decode(json)];
    expect(items, everyElement(isNotNull));
    expect(opened.changes.first['path'], 'lib/chat/chat_history_view.dart');
    expect([
      for (final c in opened.choices) c.kind,
    ], containsAll(['model', 'mode', 'permission']));

    final updates = <LinkSessionUpdate>[];
    final sub = peer.events
        .where((e) => e.name == LinkEvents.session)
        .listen(
          (e) => updates.add(
            LinkSessionUpdate.fromJson(e.data! as Map<String, Object?>),
          ),
        );
    addTearDown(sub.cancel);
    await peer.call(LinkMethods.send, {
      'session': first.id,
      'text': 'hello from the phone',
    });
    await _until(() => updates.any((u) => u.live));
    final update = updates.firstWhere((u) => u.live);
    // Only what changed: from the end of what was there.
    expect(update.start, greaterThanOrEqualTo(opened.count - 1));
    final sent = [
      for (final u in updates)
        for (final json in u.items) ChatCodec.decode(json),
    ];
    expect(
      sent.whereType<UserMessageItem>().map((m) => m.text),
      contains('hello from the phone'),
    );

    // A new agent, in a project.
    final created = await peer.call(LinkMethods.send, {
      'project': '~/code/cursor-docs',
      'text': 'new one',
    }) as Map;
    final thread = workspace.threads.firstWhere(
      (t) => t.isOpen && t.title == 'new one',
    );
    expect(thread.project.path, '~/code/cursor-docs');
    expect(created['session'], isA<String>());
    // Not shown on the desktop.
    expect(workspace.current, isNot(thread));

    await peer.call(LinkMethods.pin, {'session': first.id, 'pinned': true});
    expect(
      workspace.threads.firstWhere((t) => t.title == first.title).pinned,
      isTrue,
    );
  });

  test('a new agent from the phone starts as picked there', () async {
    final peer = await pair();
    final draft =
        (await peer.call(LinkMethods.draft, {'project': '~/code/cursor-docs'}))!
            as Map;
    final id = draft['session']! as String;
    // The same one until it is started.
    expect(
      ((await peer.call(LinkMethods.draft, {'project': '~/code/cursor-docs'}))!
          as Map)['session'],
      id,
    );
    Future<List<String>> listed() async => [
      for (final s in LinkState.fromJson(
        (await peer.call(LinkMethods.state))! as Map<String, Object?>,
      ).sessions)
        s.id,
    ];
    expect(await listed(), isNot(contains(id)));

    final opened = LinkSessionUpdate.fromJson(
      (await peer.call(LinkMethods.open, {'session': id}))!
          as Map<String, Object?>,
    );
    expect(opened.items, isEmpty);
    final mode = opened.choices.firstWhere((c) => c.kind == 'mode');
    final other = mode.options.firstWhere((o) => o.id != mode.selected);
    await peer.call(LinkMethods.choose, {
      'session': id,
      'kind': 'mode',
      'option': other.id,
    });

    await peer.call(LinkMethods.send, {'session': id, 'text': 'drafted'});
    final thread = workspace.threads.firstWhere((t) => t.title == 'drafted');
    expect(thread.project.path, '~/code/cursor-docs');
    expect(thread.session.selected(KernelChoiceKind.mode), other.id);
    expect(await listed(), contains(id));
    // The next one is another.
    expect(
      ((await peer.call(LinkMethods.draft, {'project': '~/code/cursor-docs'}))!
          as Map)['session'],
      isNot(id),
    );
    await expectLater(
      peer.call(LinkMethods.draft, {'project': '/etc'}),
      throwsA(isA<LinkRemoteException>()),
    );
  });

  test('the phone reads the projects\' files, and only theirs', () async {
    final peer = await pair();
    // An agent open there, with its changes.
    workspace.threads
        .firstWhere((t) => t.title == 'Sticky user message on scroll')
        .session
        .attach();
    final listed =
        (await peer.call(LinkMethods.files, {'project': '~/code/baocode'}))!
            as Map;
    // Not what the index leaves out (node_modules).
    expect(listed['paths'], [
      'README.md',
      'assets/logo.png',
      'lib/chat/chat_history_view.dart',
    ]);
    expect(
      listed['changes'],
      containsPair('lib/chat/chat_history_view.dart', 'modified'),
    );

    final read =
        (await peer.call(LinkMethods.read, {
              'project': '~/code/baocode',
              'path': 'lib/chat/chat_history_view.dart',
            }))!
            as Map;
    expect(read['text'], 'class View {}');
    final image =
        (await peer.call(LinkMethods.read, {
              'project': '~/code/baocode',
              'path': 'assets/logo.png',
            }))!
            as Map;
    expect(image['binary'], isTrue);

    for (final (project, path) in [
      ('~/code/baocode', '../../.ssh/id_ed25519'),
      ('~/code/baocode', ''),
      ('~', 'code/baocode/README.md'),
    ]) {
      await expectLater(
        peer.call(LinkMethods.read, {'project': project, 'path': path}),
        throwsA(
          isA<LinkRemoteException>().having((e) => e.code, 'code', 'notFound'),
        ),
      );
    }
    // Nor a new agent in a folder not listed.
    await expectLater(
      peer.call(LinkMethods.send, {'project': '/etc', 'text': 'hi'}),
      throwsA(isA<LinkRemoteException>()),
    );
  });

  test('a workspace\'s files are its folders\', each under its name', () async {
    host.dispose();
    final multi = Workspace(
      kernels: [MockKernels.claudeCode],
      workspaceDirectories: _WorkspaceDirectories(),
    );
    final made = multi.createWorkspace('web', ['/code/site', '/code/api'])!;
    host = LinkHost(
      workspace: multi,
      platform: platform,
      filesOf: (project) => (
        files: _MemoryFiles({
          '${made.path}/web.code-workspace': '{}',
          '/code/site/index.html': '<p>',
          '/code/api/main.go': 'package main',
          '/code/api/go.mod': 'module api',
        }),
        paths: p.posix,
      ),
    );
    await host.load();
    final peer = await pair();

    final listed =
        (await peer.call(LinkMethods.files, {'project': made.path}))! as Map;
    expect(listed['paths'], ['site/index.html', 'api/go.mod', 'api/main.go']);
    final read =
        (await peer.call(LinkMethods.read, {
              'project': made.path,
              'path': 'api/main.go',
            }))!
            as Map;
    expect(read['text'], 'package main');
    for (final path in [
      'site/../api/main.go',
      'web.code-workspace',
      '/code/api/main.go',
      'api',
    ]) {
      await expectLater(
        peer.call(LinkMethods.read, {'project': made.path, 'path': path}),
        throwsA(isA<LinkRemoteException>()),
        reason: path,
      );
    }

    // A file named from the phone, by its path for the agent.
    await peer.call(LinkMethods.send, {
      'project': made.path,
      'text': 'look at @api/main.go',
      'mentions': ['api/main.go'],
    });
    expect(
      multi.threads.map((t) => t.title),
      contains('look at @/code/api/main.go'),
    );
  });

  test('the phone lists the skills and servers here', () async {
    final skill = Directory(p.join(config.path, 'skills', 'review'));
    await skill.create(recursive: true);
    await File(
      p.join(skill.path, 'SKILL.md'),
    ).writeAsString('---\nname: review\ndescription: Reviews a change\n---\n');
    await File(p.join(config.path, '.claude.json')).writeAsString(
      jsonEncode({
        'mcpServers': {
          'github': {'command': 'gh-mcp'},
        },
      }),
    );
    final peer = await pair();
    final items = [
      for (final json
          in ((await peer.call(LinkMethods.extensions))! as Map)['items']
              as List)
        LinkExtension.fromJson(json as Map<String, Object?>),
    ];
    final review = items.singleWhere((e) => e.kind == 'skill');
    expect(review.name, 'review');
    expect(review.description, 'Reviews a change');
    expect(review.scope, 'user');
    expect(review.project, isNull);
    expect(items.singleWhere((e) => e.kind == 'mcp').name, 'github');
  });

  test(
    'the phone is told of the projects\' icons, and reads their pictures',
    () async {
      final peer = await pair();
      final projects = workspace.sidebarProjects;
      final svg = await workspace.icons.add(
        Uint8List.fromList(
          utf8.encode(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"/>',
          ),
        ),
        name: 'logo',
      );
      workspace
        ..setIcon(projects[0], const EmojiIcon('🚀'))
        ..setIcon(projects[1], LibraryIcon(svg.id));
      final state = LinkState.fromJson(
        (await peer.call(LinkMethods.state))! as Map<String, Object?>,
      );
      final icons = {for (final p in state.projects) p.id: p.icon};
      expect(icons[projects[0].path], {'type': 'emoji', 'emoji': '🚀'});
      expect(icons[projects[1].path], {'type': 'image', 'id': svg.id});

      final image = (await peer.call(LinkMethods.icon, {'id': svg.id}))! as Map;
      expect(image['kind'], 'svg');
      expect(base64Decode(image['data'] as String), svg.bytes);
      await expectLater(
        peer.call(LinkMethods.icon, {'id': 'nope'}),
        throwsA(
          isA<LinkRemoteException>().having((e) => e.code, 'code', 'notFound'),
        ),
      );
    },
  );

  test('a message from the phone brings its images', () async {
    final peer = await pair();
    final state = LinkState.fromJson(
      (await peer.call(LinkMethods.state))! as Map<String, Object?>,
    );
    final first = state.sessions.firstWhere(
      (s) => s.title == 'Sticky user message on scroll',
    );
    await peer.call(LinkMethods.open, {'session': first.id});
    await peer.call(LinkMethods.send, {
      'session': first.id,
      'text': 'like this',
      'images': [
        {
          'data': base64.encode(Uint8List.fromList([1, 2, 3])),
          'type': 'image/png',
        },
        {'data': 'not base64!', 'type': 'image/png'},
        {'data': '', 'type': 'text/html'},
      ],
    });
    final thread = workspace.threads.firstWhere((t) => t.title == first.title);
    final session = thread.session;
    final sent = [for (var i = 0; i < session.itemCount; i++) session.itemAt(i)]
        .whereType<UserMessageItem>()
        .last;
    expect(sent.text, matches(RegExp(r'^like this\n\[Image #\d+\]$')));
  });

  test('it is advertised on the LAN while phones may connect', () async {
    await host.setEnabled(true);
    await host.advertising;
    final advert = platform.advertised.single;
    expect(advert.name, 'Test Mac');
    expect(advert.port, 47100);
    expect(advert.pairing, isFalse);
    expect(
      advert.key,
      LinkIdentity.fromJson(platform.kept['identity']! as Map<String, Object?>)!
          .publicKey,
    );

    // Pairing: says so, to be listed among the phones' nearby ones.
    await host.beginPairing();
    await host.advertising;
    expect(platform.advertised.single.pairing, isTrue);
    host.endPairing();
    await host.advertising;
    expect(platform.advertised.single.pairing, isFalse);

    host.setDiscoverable(false);
    await host.advertising;
    expect(platform.advertised, isEmpty);
    expect(platform.kept['discoverable'], isFalse);
    host.setDiscoverable(true);
    await host.advertising;
    expect(platform.advertised, hasLength(1));
    await host.setEnabled(false);
    await host.advertising;
    expect(platform.advertised, isEmpty);
  });

  test('a phone that found it nearby pairs once allowed here', () async {
    await host.setEnabled(true);
    final early = await connect(phone);
    await expectLater(
      early.call(LinkMethods.hello, {'name': 'iPhone', 'request': true}),
      throwsA(
        isA<LinkRemoteException>().having((e) => e.code, 'code', 'notPairing'),
      ),
    );

    final offer = (await host.beginPairing())!;
    final peer = await connect(phone);
    final hello = await peer.call(LinkMethods.hello, {
      'name': 'iPhone',
      'system': 'iOS 26.1',
      'request': true,
    }) as Map;
    expect(hello['pairing'], isTrue);
    expect(hello['approval'], isTrue);
    final pending = host.pending!;
    expect(pending.needsApproval, isTrue);
    expect(pending.code, safetyCode(offer.key, phone.publicKey));
    // No longer listed as pairing: one at a time.
    await host.advertising;
    expect(platform.advertised.single.pairing, isFalse);

    // Matched on the phone: not kept until allowed here.
    var confirmed = false;
    final confirm = peer
        .call(LinkMethods.confirm)
        .whenComplete(() => confirmed = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(confirmed, isFalse);
    expect(host.phones, isEmpty);
    host.approvePending();
    final answer = await confirm as Map;
    expect((answer['device'] as Map)['name'], 'Test Mac');
    expect(host.phones.single.name, 'iPhone');
    expect(host.isConnected(deviceIdOf(phone.publicKey)), isTrue);
    expect(await peer.call(LinkMethods.state), isA<Map>());
  });

  test('a phone found nearby, turned down here, is not kept', () async {
    await host.beginPairing();
    final stranger = LinkIdentity.generate();
    final peer = await connect(stranger);
    await peer.call(LinkMethods.hello, {'name': 'x', 'request': true});
    // Another at the same time waits its turn.
    final other = await connect(LinkIdentity.generate());
    await expectLater(
      other.call(LinkMethods.hello, {'name': 'y', 'request': true}),
      throwsA(isA<LinkRemoteException>().having((e) => e.code, 'code', 'busy')),
    );
    final confirm = peer.call(LinkMethods.confirm);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    host.rejectPending();
    await expectLater(
      confirm,
      throwsA(
        isA<LinkRemoteException>().having((e) => e.code, 'code', 'rejected'),
      ),
    );
    await peer.done;
    expect(host.phones, isEmpty);
    expect(host.offer, isNull);
  });

  test('unpaired on the desktop, the phone is told and let go', () async {
    final peer = await pair();
    final told = peer.events.firstWhere((e) => e.name == LinkEvents.unpaired);
    host.unpair(host.phones.single);
    await told;
    await peer.done;
    expect(host.phones, isEmpty);
  });
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

/// Files kept in memory, by absolute path; null for a binary one.
class _MemoryFiles implements IdeFileService {
  _MemoryFiles(this.files);

  final Map<String, String?> files;

  @override
  Future<List<IdeFile>> list(String directory) async {
    final entries = <String, bool>{};
    for (final path in files.keys) {
      if (!p.posix.isWithin(directory, path)) continue;
      final rest = p.posix.relative(path, from: directory).split('/');
      entries[rest.first] = rest.length > 1;
    }
    return [
      for (final MapEntry(key: name, value: directory_) in entries.entries)
        IdeFile(p.posix.join(directory, name), name, isDirectory: directory_),
    ];
  }

  @override
  Future<String> read(String path, {bool force = false}) async {
    if (!files.containsKey(path)) throw IdeFileNotFoundException(path);
    return files[path] ?? (throw IdeBinaryFileException(path));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Workspaces' folders under /data/workspaces, nothing written.
class _WorkspaceDirectories extends ProjectWorkspaceDirectories {
  @override
  String? get root => '/data/workspaces';

  @override
  void write(ProjectWorkspace workspace) {}
}
