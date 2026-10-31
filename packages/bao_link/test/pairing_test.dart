import 'dart:convert';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final desktop = LinkIdentity.generate();
  final phone = LinkIdentity.generate();

  test('an offer goes through its URI as it was', () {
    final offer = PairingOffer(
      name: 'Leo 的 MacBook Pro',
      key: desktop.publicKey,
      token: Uint8List.fromList(List.generate(16, (i) => i)),
      expires: DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000),
      relays: const ['https://relay-hk1.baocode.dev/'],
      addrs: const ['192.168.1.5:47100', '[2408:8207::1]:47100'],
    );
    final parsed = PairingOffer.parse(offer.uri);
    expect(parsed.name, offer.name);
    expect(parsed.key, offer.key);
    expect(parsed.token, offer.token);
    expect(parsed.expires, offer.expires);
    expect(parsed.address, offer.address);
    expect(parsed.address.id, desktop.id);
    expect(
      () => PairingOffer.parse('https://example.com'),
      throwsFormatException,
    );
  });

  test('a code of before says the desktop needs updating', () {
    final old = base64Url
        .encode(
          utf8.encode(
            jsonEncode({'v': 1, 'n': 'Mac', 'k': 'a', 't': 'b', 'x': 1}),
          ),
        )
        .replaceAll('=', '');
    expect(
      () => PairingOffer.parse('baocode://pair?d=$old'),
      throwsA(
        isA<PairingVersionException>().having((e) => e.older, 'older', true),
      ),
    );
  });

  test('addresses go through JSON, and a bad id is none', () {
    final address = LinkAddress(
      desktop.id,
      relays: const ['https://r'],
      addrs: const ['10.0.0.2:1'],
    );
    expect(LinkAddress.fromJson(address.toJson()), address);
    expect(LinkAddress.fromJson({'id': 'abc'}), isNull);
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

  test('identities go through JSON; one of before is none', () {
    final again = LinkIdentity.fromJson(desktop.toJson())!;
    expect(again.publicKey, desktop.publicKey);
    expect(desktop.id, hasLength(64));
    expect(keyOfDeviceId(desktop.id), desktop.publicKey);
    expect(keyOfDeviceId('zz'), isNull);
    expect(
      desktop.fingerprint,
      matches(RegExp(r'^([0-9A-F]{4} ){7}[0-9A-F]{4}$')),
    );
    // An X25519 key of link v1.
    expect(
      LinkIdentity.fromJson({'privateKey': encodeKey(Uint8List(32))}),
      isNull,
    );
  });

  test('an Ed25519 key from its seed, as RFC 8032 has it', () {
    // RFC 8032, 7.1, test 1.
    final seed = Uint8List.fromList([
      for (var i = 0; i < 64; i += 2)
        int.parse(
          '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60'
              .substring(i, i + 2),
          radix: 16,
        ),
    ]);
    expect(
      LinkIdentity.fromPrivateKey(seed).id,
      'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
    );
  });

  test('relay URLs: bare hosts are https, paths are not relays', () {
    expect(parseRelayUrl('relay.example.com'), 'https://relay.example.com');
    expect(parseRelayUrl(' http://10.0.0.1:3340 '), 'http://10.0.0.1:3340');
    expect(parseRelayUrl('https://r.example/x'), isNull);
    expect(parseRelayUrl('ftp://r.example'), isNull);
    expect(parseRelayUrl(''), isNull);
    expect(linkRelays(), defaultLinkRelays);
    expect(linkRelays(['my.relay', 'bad url/x', defaultLinkRelays.first]), [
      ...defaultLinkRelays,
      'https://my.relay',
    ]);
    expect(defaultLinkRelays.length, greaterThanOrEqualTo(2));
  });

  test('LAN addresses are told from those across the internet', () {
    expect(isLanAddress('192.168.1.5:47100'), isTrue);
    expect(isLanAddress('10.1.2.3:1'), isTrue);
    expect(isLanAddress('172.20.0.1:1'), isTrue);
    expect(isLanAddress('[fd00::1]:1'), isTrue);
    expect(isLanAddress('[fe80::1]:1'), isTrue);
    expect(isLanAddress('8.8.8.8:1'), isFalse);
    expect(isLanAddress('172.40.0.1:1'), isFalse);
    expect(isLanAddress('[2408:8207::1]:1'), isFalse);
  });

  test('paths go through JSON', () {
    const path = LinkPath(
      LinkPathKind.relay,
      rtt: Duration(milliseconds: 42),
      relay: 'https://r',
    );
    expect(LinkPath.fromJson(path.toJson()), path);
    expect(LinkPath.fromJson(null), LinkPath.none);
  });
}
