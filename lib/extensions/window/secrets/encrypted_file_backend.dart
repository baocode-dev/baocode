// The extensions' secrets where the system keeps none (no Secret Service
// on Linux): one JSON file of values encrypted with a random key kept in a
// file of its own, both readable by the user only.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pinenacl/x25519.dart' show EncryptedMessage, SecretBox;

import '../json_state_store.dart';
import 'secret_backend.dart';

/// Secrets in [directory]: `secrets.json` maps each account to its value
/// encrypted (NaCl's secretbox: XSalsa20 and Poly1305, a random nonce each,
/// the account sealed in with the value so values cannot be swapped), and
/// `secrets.key` holds the 32 byte key. Both are 0600 in a 0700 folder.
///
/// It keeps secrets from whoever gets the one file without the other (a
/// backup, a synced folder), not from programs running as the user.
final class EncryptedFileBackend implements SecretBackend {
  EncryptedFileBackend(this.directory, {Random? random})
    : _random = random ?? Random.secure();

  final String directory;
  final Random _random;

  String get valuesPath => p.join(directory, 'secrets.json');
  String get keyPath => p.join(directory, 'secrets.key');

  Map<String, String>? _values;
  SecretBox? _box;
  Future<void> _last = Future.value();

  @override
  String get kind => 'encrypted-file';

  /// Runs [action] after every operation before it (the file is one for all
  /// accounts).
  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _last.then((_) => action());
    _last = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<String?> read(String account) => _locked(() async {
    final sealed = (await _load())[account];
    if (sealed == null) return null;
    final box = await _key(create: false);
    if (box == null) return null;
    try {
      final opened = jsonDecode(
        utf8.decode(
          box.decrypt(EncryptedMessage.fromList(base64.decode(sealed))),
        ),
      );
      if (opened is List && opened.length == 2 && opened[0] == account) {
        return opened[1] as String;
      }
    } on Object {
      // Not ours (another key, changed): as VS Code drops a secret it cannot
      // decrypt.
    }
    return null;
  });

  @override
  Future<void> write(String account, String value) => _locked(() async {
    final values = await _load();
    final box = (await _key(create: true))!;
    final sealed = box.encrypt(
      utf8.encode(jsonEncode([account, value])),
      nonce: _bytes(EncryptedMessage.nonceLength),
    );
    values[account] = base64.encode(sealed);
    await _save(values);
  });

  @override
  Future<void> delete(String account) => _locked(() async {
    final values = await _load();
    if (values.remove(account) != null) await _save(values);
  });

  Future<Map<String, String>> _load() async {
    if (_values case final values?) return values;
    final values = <String, String>{};
    try {
      final file = File(valuesPath);
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map) {
          for (final MapEntry(:key, :value) in json.entries) {
            if (key is String && value is String) values[key] = value;
          }
        }
      }
    } on Object {
      // A broken file starts over.
    }
    return _values = values;
  }

  Future<SecretBox?> _key({required bool create}) async {
    if (_box case final box?) return box;
    final file = File(keyPath);
    if (await file.exists()) {
      try {
        final key = base64.decode((await file.readAsString()).trim());
        if (key.length == SecretBox.keyLength) return _box = SecretBox(key);
      } on FormatException {
        // Made again below.
      }
    }
    if (!create) return null;
    final key = _bytes(SecretBox.keyLength);
    await _private(Directory(directory), directory: true);
    // Made empty and closed to others before the key goes in.
    await file.writeAsString('');
    await _private(file);
    await file.writeAsString(base64.encode(key), flush: true);
    // Values sealed with a key that is lost are no use.
    _values?.clear();
    return _box = SecretBox(key);
  }

  Future<void> _save(Map<String, String> values) async {
    await _private(Directory(directory), directory: true);
    await writeAtomically(valuesPath, jsonEncode(values));
    await _private(File(valuesPath));
  }

  Uint8List _bytes(int length) => Uint8List.fromList([
    for (var i = 0; i < length; i++) _random.nextInt(256),
  ]);

  static Future<void> _private(
    FileSystemEntity entity, {
    bool directory = false,
  }) async {
    if (directory) await (entity as Directory).create(recursive: true);
    if (Platform.isWindows) return;
    await Process.run('chmod', [directory ? '700' : '600', entity.path]);
  }
}
