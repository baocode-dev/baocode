import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/update/update_signature.dart';

void main() {
  final seed = UpdateSignature.generateSeed();
  final publicKey = UpdateSignature.publicKeyOf(seed);
  final payload = UpdateSignature.payload(
    version: '1.2.0+12',
    platform: 'windows-x64',
    size: 1234,
    sha256: 'AB' * 32,
  );

  group('UpdateSignature', () {
    test('signs the version, platform, size and digest', () {
      expect(
        utf8.decode(payload),
        'baocode-update-v1\n1.2.0+12\nwindows-x64\n1234\n${'ab' * 32}\n',
      );
    });

    test('verifies what its key signed', () {
      final signature = UpdateSignature.sign(payload: payload, seed: seed);
      expect(base64.decode(signature), hasLength(64));
      expect(
        UpdateSignature.verify(
          payload: payload,
          signature: signature,
          publicKey: publicKey,
        ),
        isTrue,
      );
    });

    test('refuses another payload, key, or a malformed signature', () {
      final signature = UpdateSignature.sign(payload: payload, seed: seed);
      final other = UpdateSignature.payload(
        version: '1.1.0',
        platform: 'windows-x64',
        size: 1234,
        sha256: 'ab' * 32,
      );
      expect(
        UpdateSignature.verify(
          payload: other,
          signature: signature,
          publicKey: publicKey,
        ),
        isFalse,
        reason: 'an older version passed off as this one',
      );
      expect(
        UpdateSignature.verify(
          payload: payload,
          signature: signature,
          publicKey: UpdateSignature.publicKeyOf(
            UpdateSignature.generateSeed(),
          ),
        ),
        isFalse,
      );
      final bytes = base64.decode(signature)..[0] ^= 1;
      expect(
        UpdateSignature.verify(
          payload: payload,
          signature: base64.encode(bytes),
          publicKey: publicKey,
        ),
        isFalse,
      );
      for (final bad in [
        '',
        'not base64!',
        base64.encode([1, 2, 3]),
      ]) {
        expect(
          UpdateSignature.verify(
            payload: payload,
            signature: bad,
            publicKey: publicKey,
          ),
          isFalse,
          reason: bad,
        );
      }
    });

    test("the app's key is an Ed25519 public key", () {
      expect(base64.decode(updatePublicKey), hasLength(32));
      // And not the test's.
      final signature = UpdateSignature.sign(payload: payload, seed: seed);
      expect(
        UpdateSignature.verify(payload: payload, signature: signature),
        isFalse,
      );
    });
  });
}
