import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:flutter_test/flutter_test.dart';

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
    expect(found.addrs, ['192.168.1.5:47100', '[2408:8207::5]:47100']);
    expect(
      LinkAdvert.parse(name: 'x', port: 1, attributes: {'v': '2', 'k': ''}),
      isNull,
    );
    expect(
      LinkAdvert.parse(name: 'x', port: 1, attributes: {'v': '1', 'k': 'abc'}),
      isNull,
    );
  });

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
}
