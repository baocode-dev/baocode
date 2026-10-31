import 'dart:convert';
import 'dart:typed_data';

import 'package:pinenacl/digests.dart';
import 'package:pinenacl/ed25519.dart' show SigningKey;
import 'package:pinenacl/tweetnacl.dart';

/// An end's lasting key pair (Ed25519): a desktop's, or a phone's. Its
/// public key is its id on the network (iroh's EndpointId): what is dialled,
/// what the other end proves it is talking to, what is paired. The private
/// one never leaves the device.
class LinkIdentity {
  LinkIdentity._(this.privateKey, this.publicKey);

  /// A new key pair.
  factory LinkIdentity.generate() =>
      LinkIdentity.fromPrivateKey(TweetNaCl.randombytes(32));

  /// The pair of [privateKey], the 32-byte seed.
  factory LinkIdentity.fromPrivateKey(Uint8List privateKey) {
    if (privateKey.length != 32) {
      throw ArgumentError.value(
        privateKey.length,
        'privateKey',
        'not 32 bytes',
      );
    }
    final signing = SigningKey.fromSeed(Uint8List.fromList(privateKey));
    return LinkIdentity._(
      Uint8List.fromList(privateKey),
      Uint8List.fromList(signing.verifyKey),
    );
  }

  /// As [toJson] wrote it; null for a key of before (X25519, link v1),
  /// which pairs no more.
  static LinkIdentity? fromJson(Map<String, Object?> json) {
    if (json['kind'] != kind) return null;
    final key = json['privateKey'];
    if (key is! String) return null;
    try {
      return LinkIdentity.fromPrivateKey(decodeKey(key));
    } on Object {
      return null;
    }
  }

  static const kind = 'ed25519';

  /// The seed iroh takes as the secret key.
  final Uint8List privateKey;
  final Uint8List publicKey;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'privateKey': encodeKey(privateKey),
  };

  /// The id: [publicKey] in hex, as iroh writes an EndpointId.
  String get id => deviceIdOf(publicKey);

  /// [publicKey] as both screens show it (see [fingerprintOf]).
  String get fingerprint => fingerprintOf(publicKey);
}

/// [length] random bytes, from the system's secure generator.
Uint8List randomBytes(int length) => TweetNaCl.randombytes(length);

/// A key as text: base64url, unpadded.
String encodeKey(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List decodeKey(String text) =>
    base64Url.decode(base64Url.normalize(text.trim()));

/// SHA-256 of [publicKey], its first 16 bytes in groups of four hex digits
/// (`7F3A 91C2 …`): a key as people read it.
String fingerprintOf(Uint8List publicKey) {
  final hash = Hash.sha256(publicKey);
  final hex = [
    for (final byte in hash.take(16))
      byte.toRadixString(16).padLeft(2, '0').toUpperCase(),
  ].join();
  return [for (var i = 0; i < hex.length; i += 4) hex.substring(i, i + 4)]
      .join(' ');
}

/// A device's id, the same on both ends and on the network: its public
/// key in lower-case hex (64 digits), iroh's EndpointId.
String deviceIdOf(Uint8List publicKey) =>
    [for (final byte in publicKey) byte.toRadixString(16).padLeft(2, '0')]
        .join();

/// The public key of the id [id] ([deviceIdOf]); null for one that is
/// not 64 hex digits.
Uint8List? keyOfDeviceId(String id) {
  if (id.length != 64) return null;
  final key = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    final byte = int.tryParse(id.substring(i * 2, i * 2 + 2), radix: 16);
    if (byte == null) return null;
    key[i] = byte;
  }
  return key;
}

/// What both screens show while pairing, to be compared: four groups of
/// three digits from the hash of the two public keys (the desktop's first).
/// The connection proves each end holds its key; the codes matching proves
/// those are the keys the two people mean, not those of one in the middle.
List<String> safetyCode(Uint8List desktopKey, Uint8List phoneKey) {
  final hash = Hash.sha256(
    Uint8List.fromList([
      ...utf8.encode('baocode-safety-v2'),
      ...desktopKey,
      ...phoneKey,
    ]),
  );
  return [
    for (var i = 0; i < 4; i++)
      ((hash[i * 3] << 16 | hash[i * 3 + 1] << 8 | hash[i * 3 + 2]) % 1000)
          .toString()
          .padLeft(3, '0'),
  ];
}
