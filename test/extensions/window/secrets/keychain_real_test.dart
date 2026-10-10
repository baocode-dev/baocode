// The real macOS login keychain (tagged `exthost`, so not in the default
// run): `flutter test --run-skipped --tags exthost <this file>`. What it
// writes is under a random extension id and deleted afterwards, also when
// it fails.
@Tags(['exthost'])
library;

import 'dart:io';
import 'dart:math';

import 'package:baocode/extensions/window/secrets/extension_secret_service.dart';
import 'package:baocode/extensions/window/secrets/keychain_backend.dart';
import 'package:baocode/extensions/window/secrets/secret_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final extensionId =
      'baocode-test.secrets-${Random.secure().nextInt(1 << 32).toRadixString(16)}';
  const values = {
    'plain': 'hunter2',
    'unicode': '密码 pässwörd 😀',
    'quotes':
        r'a"b\c'
        "'d",
    'lines': 'line1\nline2\r\n',
    'hexlike': '610a62',
    'empty': '',
    'key with spaces/and "quotes"': 'x',
    'key\nwith a line break': 'y',
  };

  tearDown(() async {
    for (final key in [...values.keys, 'long']) {
      for (var part = 0; part < 6; part++) {
        await Process.run(KeychainBackend.securityPath, [
          'delete-generic-password',
          '-s',
          KeychainBackend.service(part: part),
          '-a',
          secretAccount(extensionId, key),
        ]);
      }
    }
  });

  /// Whether the keychain has [key]'s [part].
  Future<bool> hasPart(String key, int part) async =>
      (await Process.run(KeychainBackend.securityPath, [
        'find-generic-password',
        '-s',
        KeychainBackend.service(part: part),
        '-a',
        secretAccount(extensionId, key),
      ])).exitCode ==
      0;

  test('keeps, reads and deletes secrets in the login keychain', () async {
    final temp = await Directory.systemTemp.createTemp('keychain');
    addTearDown(() => temp.delete(recursive: true));
    final secrets = ExtensionSecretService(
      backend: KeychainBackend(),
      keyIndexPath: p.join(temp.path, 'secret-keys.json'),
    );
    addTearDown(secrets.dispose);
    final changes = <ExtensionSecretChange>[];
    secrets.changes.listen(changes.add);

    final long = List.generate(5000, (i) => '${i % 10}').join();
    for (final MapEntry(:key, :value) in {...values, 'long': long}.entries) {
      await secrets.set(extensionId, key, value);
    }
    for (final MapEntry(:key, :value) in {...values, 'long': long}.entries) {
      expect(await secrets.get(extensionId, key), value, reason: key);
    }
    // Nothing secret on a command line: `security` itself shows the item.
    final shown = await Process.run(KeychainBackend.securityPath, [
      'find-generic-password',
      '-s',
      extensionSecretsService,
      '-a',
      '$extensionId/plain',
      '-w',
    ]);
    expect('${shown.stdout}'.trim(), 'hunter2');

    expect(await secrets.keys(extensionId), [...values.keys, 'long']);
    // 5000 bytes are more than `security -i` reads in a line: in parts.
    expect(await hasPart('long', 4), isTrue);
    expect(await hasPart('long', 5), isFalse);
    await secrets.set(extensionId, 'long', '${long.substring(0, 1500)}é');
    expect(
      await secrets.get(extensionId, 'long'),
      '${long.substring(0, 1500)}é',
    );
    expect(await hasPart('long', 1), isTrue);
    expect(await hasPart('long', 2), isFalse);
    await secrets.set(extensionId, 'plain', 'changed');
    expect(await secrets.get(extensionId, 'plain'), 'changed');
    for (final key in [...values.keys, 'long']) {
      await secrets.delete(extensionId, key);
      expect(await secrets.get(extensionId, key), isNull, reason: key);
    }
    expect(await secrets.keys(extensionId), isEmpty);
    expect(changes, hasLength((values.length + 1) * 2 + 2));
  }, skip: Platform.isMacOS ? false : 'macOS only');
}
