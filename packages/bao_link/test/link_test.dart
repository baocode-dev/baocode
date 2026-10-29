import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bao_link/bao_link_io.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  test('a desktop\'s advert reads back, and others are left out', () {
    final key = LinkIdentity.generate().publicKey;
    final advert = LinkAdvert(
      name: 'Mac',
      key: key,
      port: 47100,
      pairing: true,
    );
    final found = LinkAdvert.parse(
      name: 'Mac',
      port: 47100,
      attributes: advert.attributes,
      addresses: ['fe80::1', '2408:8207::5', '192.168.1.5', 'fe80::2%en0'],
    )!;
    expect(found.id, advert.id);
    expect(found.pairing, isTrue);
    expect(found.sameAs(advert), isTrue);
    // IPv4 first; not link-local.
    expect(
      [for (final e in found.endpoints) '$e'],
      ['192.168.1.5:47100', '[2408:8207::5]:47100'],
    );
    expect(
      LinkAdvert.parse(name: 'x', port: 1, attributes: {'v': '2', 'k': ''}),
      isNull,
    );
    expect(
      LinkAdvert.parse(name: 'x', port: 1, attributes: {'v': '1', 'k': 'abc'}),
      isNull,
    );
  });

  final desktop = LinkIdentity.generate();
  final phone = LinkIdentity.generate();

  Future<(SecureChannel, SecureChannel)> handshake({
    Uint8List? serverKey,
  }) async {
    final (a, b) = MemoryLinkSocket.pair();
    final accepted = SecureChannel.accept(b, identity: desktop);
    final connected = await SecureChannel.connect(
      a,
      identity: phone,
      serverKey: serverKey ?? desktop.publicKey,
    );
    return (connected, await accepted);
  }

  test('a session update tells of earlier items only when it is asked', () {
    const plain = LinkSessionUpdate(
      session: 's',
      start: 0,
      items: [],
      count: 0,
    );
    expect(plain.toJson().containsKey('earlier'), isFalse);
    expect(LinkSessionUpdate.fromJson(plain.toJson()).earlier, isNull);
    for (final earlier in [true, false]) {
      final update = LinkSessionUpdate(
        session: 's',
        start: 0,
        items: const [],
        count: 0,
        earlier: earlier,
      );
      expect(update.toJson()['earlier'], earlier);
      expect(LinkSessionUpdate.fromJson(update.toJson()).earlier, earlier);
    }
  });

  test('a bot\'s picture is told from an emoji by its file\'s name', () {
    expect(isAvatarImage('avatar-0a1b2c3d4e5f.jpg'), isTrue);
    expect(isAvatarImage('avatar-0a1b2c3d4e5f.PNG'), isFalse);
    expect(isAvatarImage('🌸'), isFalse);
    expect(isAvatarImage('../x.png'), isFalse);
    expect(isAvatarImage(null), isFalse);
    expect(
      const LinkBot(
        id: 'b',
        name: 'Mia',
        avatar: 'avatar-1.webp',
      ).hasAvatarImage,
      isTrue,
    );
  });

  test('the stickers the app comes with, each once', () {
    final ids = [for (final sticker in builtInStickers) sticker.id];
    expect(ids.toSet(), hasLength(ids.length));
    expect(builtInSticker('happy')?.zh, '开心');
    expect(builtInSticker('nope'), isNull);
  });

  test('the bots go to the phone, and back as they were', () {
    final state = LinkState.fromJson(
      jsonDecode(
        jsonEncode(
          LinkState(
            device: const DeviceInfo(name: 'mac', kind: 'mac', system: 'macos'),
            bots: [
              LinkBot(
                id: 'assistant',
                name: 'Bao',
                assistant: true,
                abilities: BotAbility.values.toSet(),
                session: 's-1',
                status: BotStatus.typing,
                unread: 2,
                last: 'Done.',
                updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
              ),
              const LinkBot(
                id: 'b1',
                name: 'Mia',
                avatar: '🌸',
                gender: 'female',
                signature: 'Tea first.',
                identity: 'kind',
                style: 'short',
                proactive: BotProactive(perDay: 0),
                model: 'Opus',
              ),
            ],
          ).toJson(),
        ),
      ) as Map<String, Object?>,
    );
    final [bao, mia] = state.bots;
    expect(bao.assistant, isTrue);
    expect(bao.abilities, BotAbility.values.toSet());
    expect(
      (bao.session, bao.status, bao.unread, bao.last),
      ('s-1', BotStatus.typing, 2, 'Done.'),
    );
    expect(bao.updatedAt, DateTime.fromMillisecondsSinceEpoch(1000));
    expect(mia.abilities, isEmpty);
    expect((mia.avatar, mia.identity), ('🌸', 'kind'));
    expect(
      (mia.gender, mia.signature, mia.style, mia.model),
      ('female', 'Tea first.', 'short', 'Opus'),
    );
    expect(
      (bao.gender, bao.signature, bao.style, bao.model),
      ('', '', '', null),
    );
    expect(mia.proactive, const BotProactive(perDay: 0));
    // None, from a desktop before them.
    expect(
      LinkState.fromJson(const {'device': <String, Object?>{}}).bots,
      isEmpty,
    );
  });

  test('quiet hours may span midnight, or be none', () {
    const night = BotProactive(quietFrom: 23 * 60, quietTo: 8 * 60);
    expect(night.isQuiet(23 * 60 + 30), isTrue);
    expect(night.isQuiet(7 * 60), isTrue);
    expect(night.isQuiet(12 * 60), isFalse);
    const lunch = BotProactive(quietFrom: 12 * 60, quietTo: 13 * 60);
    expect(lunch.isQuiet(12 * 60 + 30), isTrue);
    expect(lunch.isQuiet(13 * 60), isFalse);
    expect(const BotProactive(quietFrom: 0, quietTo: 0).isQuiet(0), isFalse);
  });

  group('SecureChannel', () {
    test(
      'both ends learn the other\'s key, and messages go both ways',
      () async {
        final (client, server) = await handshake();
        expect(server.peerKey, phone.publicKey);
        expect(client.peerKey, desktop.publicKey);
        final toServer = server.messages.first;
        client.send(_bytes('hi desktop'));
        expect(utf8.decode(await toServer), 'hi desktop');
        final toClient = client.messages.take(2).toList();
        server
          ..send(_bytes('one'))
          ..send(_bytes('two'));
        expect(
          [for (final m in await toClient) utf8.decode(m)],
          ['one', 'two'],
        );
        await client.close();
        await server.done;
      },
    );

    test('a phone with another desktop\'s key does not get in', () async {
      final other = LinkIdentity.generate();
      final (a, b) = MemoryLinkSocket.pair();
      final accepted = SecureChannel.accept(b, identity: desktop);
      unawaited(
        SecureChannel.connect(
          a,
          identity: phone,
          serverKey: other.publicKey,
        ).then((_) {}, onError: (_) {}),
      );
      await expectLater(accepted, throwsA(isA<LinkHandshakeException>()));
    });

    test('what is sent is not readable on the wire', () async {
      final (a, b) = MemoryLinkSocket.pair();
      final wire = <Uint8List>[];
      final tap = _TapSocket(a, wire);
      final accepted = SecureChannel.accept(b, identity: desktop);
      final client = await SecureChannel.connect(
        tap,
        identity: phone,
        serverKey: desktop.publicKey,
      );
      final server = await accepted;
      final got = server.messages.first;
      client.send(_bytes('secret words'));
      await got;
      for (final frame in wire) {
        expect(
          latin1.decode(frame, allowInvalid: true),
          isNot(contains('secret')),
        );
      }
      // Nor the phone's lasting key, sealed in the hello.
      final hello = wire.first;
      expect(_contains(hello, phone.publicKey), isFalse);
    });

    test('a tampered message ends the connection', () async {
      final (a, b) = MemoryLinkSocket.pair();
      final tamper = _TamperSocket(a);
      final accepted = SecureChannel.accept(b, identity: desktop);
      final client = await SecureChannel.connect(
        tamper,
        identity: phone,
        serverKey: desktop.publicKey,
      );
      final server = await accepted;
      tamper.flip = true;
      client.send(_bytes('hello'));
      await expectLater(
        server.messages.first,
        throwsA(isA<LinkHandshakeException>()),
      );
    });
  });

  group('LinkPeer', () {
    test('requests are answered, errors and events carried', () async {
      final (client, server) = await handshake();
      final desktopPeer = LinkPeer(
        server,
        onRequest: (method, params) => switch (method) {
          'echo' => params['x'],
          _ => throw const LinkRemoteException('notFound', 'nope'),
        },
      );
      final phonePeer = LinkPeer(client);
      expect(await phonePeer.call('echo', {'x': 42}), 42);
      await expectLater(
        phonePeer.call('other'),
        throwsA(
          isA<LinkRemoteException>().having((e) => e.code, 'code', 'notFound'),
        ),
      );
      final event = phonePeer.events.first;
      desktopPeer.emit('state', {'a': 1});
      expect((await event).data, {'a': 1});
      final pending = expectLater(
        phonePeer.call('never-answered-after-close'),
        throwsA(anything),
      );
      await desktopPeer.close();
      await phonePeer.done;
      await pending;
    });
  });

  group('PairingOffer', () {
    test('goes through its URI as it was', () {
      final offer = PairingOffer(
        name: 'Leo 的 MacBook Pro',
        key: desktop.publicKey,
        token: Uint8List.fromList(List.generate(16, (i) => i)),
        expires: DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000),
        endpoints: const [
          DirectEndpoint('192.168.1.5', 47100),
          DirectEndpoint('2408:8207::1', 47100),
          DirectEndpoint('home.example.com', 443),
          DirectEndpoint('link.example.com', 443, secure: true),
        ],
        relay: RelayEndpoint(Uri.parse('wss://relay.baocode.dev'), 'room'),
      );
      final parsed = PairingOffer.parse(offer.uri);
      expect(parsed.name, offer.name);
      expect(parsed.key, offer.key);
      expect(parsed.token, offer.token);
      expect(parsed.expires, offer.expires);
      expect(parsed.endpoints, offer.endpoints);
      expect(parsed.relay, offer.relay);
      expect(
        () => PairingOffer.parse('https://example.com'),
        throwsFormatException,
      );
    });

    test('addresses parse with and without ports', () {
      expect(
        DirectEndpoint.parse('10.0.0.2'),
        const DirectEndpoint('10.0.0.2', defaultLinkPort),
      );
      expect(DirectEndpoint.parse('[::1]:80'), const DirectEndpoint('::1', 80));
      expect(
        DirectEndpoint.parse('fe80::1'),
        const DirectEndpoint('fe80::1', defaultLinkPort),
      );
      expect(DirectEndpoint.parse('a.b:9'), const DirectEndpoint('a.b', 9));
      expect(() => DirectEndpoint.parse('a.b:x'), throwsFormatException);
      expect(
        DirectEndpoint.parse('a.b', defaultPort: 9),
        const DirectEndpoint('a.b', 9),
      );
    });

    test('addresses with a scheme: wss over TLS, on 443 or 80 by default', () {
      const tls = DirectEndpoint('link.example.com', 443, secure: true);
      expect(DirectEndpoint.parse('wss://link.example.com'), tls);
      expect(DirectEndpoint.parse('https://link.example.com/'), tls);
      expect(
        DirectEndpoint.parse('WSS://link.example.com:443/baocode-link'),
        tls,
      );
      expect(
        DirectEndpoint.parse('wss://[2408::1]:8443'),
        const DirectEndpoint('2408::1', 8443, secure: true),
      );
      expect(
        DirectEndpoint.parse('ws://link.example.com', defaultPort: 9),
        const DirectEndpoint('link.example.com', 80),
      );
      expect(
        DirectEndpoint.parse('http://link.example.com:8080'),
        const DirectEndpoint('link.example.com', 8080),
      );
      expect('$tls', 'wss://link.example.com:443');
      expect(DirectEndpoint.parse('$tls'), tls);
      expect(tls, isNot(const DirectEndpoint('link.example.com', 443)));
    });

    test('the safety code is the same on both ends, and differs per pair', () {
      final code = safetyCode(desktop.publicKey, phone.publicKey);
      expect(code, hasLength(4));
      expect(code.every((group) => RegExp(r'^\d{3}$').hasMatch(group)), isTrue);
      expect(safetyCode(desktop.publicKey, phone.publicKey), code);
      expect(
        safetyCode(desktop.publicKey, LinkIdentity.generate().publicKey),
        isNot(code),
      );
    });

    test('identities go through JSON', () {
      final again = LinkIdentity.fromJson(desktop.toJson());
      expect(again.publicKey, desktop.publicKey);
      expect(
        desktop.fingerprint,
        matches(RegExp(r'^([0-9A-F]{4} ){7}[0-9A-F]{4}$')),
      );
    });
  });

  test('over a real WebSocket, on the loopback', () async {
    final server = await LinkServer.bind(0);
    final port = server.port;
    final accepted = server.sockets.first.then(
      (socket) => SecureChannel.accept(socket, identity: desktop),
    );
    final (socket, endpoint) = await LinkConnector.connect([
      // Not listening: the race goes on to the next.
      const DirectEndpoint('127.0.0.1', 1),
      DirectEndpoint('127.0.0.1', port),
    ]);
    expect(endpoint, DirectEndpoint('127.0.0.1', port));
    final client = await SecureChannel.connect(
      socket,
      identity: phone,
      serverKey: desktop.publicKey,
    );
    final channel = await accepted;
    final big = Uint8List(3 * 1024 * 1024)..fillRange(0, 10, 7);
    final got = channel.messages.first;
    client.send(big);
    expect((await got).length, big.length);
    await client.close();
  });

  test('a relay alone is not reached yet', () async {
    await expectLater(
      LinkConnector.connect(
        const [],
        relay: RelayEndpoint(Uri.parse('wss://relay.example'), 'r'),
      ),
      throwsA(isA<LinkRelayUnavailableException>()),
    );
  });
}

bool _contains(Uint8List haystack, Uint8List needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var found = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        found = false;
        break;
      }
    }
    if (found) return true;
  }
  return false;
}

class _TapSocket implements LinkSocket {
  _TapSocket(this._inner, this.wire);

  final LinkSocket _inner;
  final List<Uint8List> wire;

  @override
  Stream<Uint8List> get messages => _inner.messages;

  @override
  void send(Uint8List message) {
    wire.add(message);
    _inner.send(message);
  }

  @override
  Future<void> close() => _inner.close();
}

class _TamperSocket implements LinkSocket {
  _TamperSocket(this._inner);

  final LinkSocket _inner;
  bool flip = false;

  @override
  Stream<Uint8List> get messages => _inner.messages;

  @override
  void send(Uint8List message) {
    if (flip) message = Uint8List.fromList(message)..[message.length - 1] ^= 1;
    _inner.send(message);
  }

  @override
  Future<void> close() => _inner.close();
}
