// Plain Dart, no Flutter: tool/release_manifest.dart imports it too.

import 'dart:convert';

import 'package:pinenacl/ed25519.dart';

/// The Ed25519 key releases are signed with: the public half, base64. The
/// private half is kept off the repository (docs/auto-update.md);
/// tool/release_manifest.dart signs with it.
const updatePublicKey = 'iBSgPUxNeT4jvgaua22aN/jCDwG+ry8rGc17kMcU4II=';

/// What a release's signature covers, and checking it. Not the file
/// itself (a few hundred megabytes, read whole): its SHA-256, which the
/// download is checked against, with the version and platform it is for,
/// so a signed installer cannot be passed off as another version (an old
/// one, to downgrade) or another platform's.
abstract final class UpdateSignature {
  /// The bytes signed: `baocode-update-v1`, then the version, platform,
  /// size and SHA-256 (lowercase hex), a line each.
  static Uint8List payload({
    required String version,
    required String platform,
    required int size,
    required String sha256,
  }) => utf8.encode(
    'baocode-update-v1\n$version\n$platform\n$size\n${sha256.toLowerCase()}\n',
  );

  /// Whether [signature] (base64) is [publicKey]'s (base64) over [payload].
  static bool verify({
    required Uint8List payload,
    required String signature,
    String publicKey = updatePublicKey,
  }) {
    try {
      final key = VerifyKey(base64.decode(publicKey));
      return key.verify(
        signature: Signature(base64.decode(signature)),
        message: payload,
      );
    } on Object {
      // A forged or malformed signature, or a key that is not one.
      return false;
    }
  }

  /// Signs [payload] with the 32-byte [seed] (base64): the release tool's.
  static String sign({required Uint8List payload, required String seed}) {
    final key = SigningKey.fromSeed(base64.decode(seed.trim()));
    return base64.encode(key.sign(payload).signature.asTypedList);
  }

  /// The public key (base64) of the 32-byte [seed] (base64).
  static String publicKeyOf(String seed) => base64.encode(
    SigningKey.fromSeed(base64.decode(seed.trim())).verifyKey.asTypedList,
  );

  /// A new private key: 32 random bytes, base64.
  static String generateSeed() =>
      base64.encode(SigningKey.generate().seed.asTypedList);
}
