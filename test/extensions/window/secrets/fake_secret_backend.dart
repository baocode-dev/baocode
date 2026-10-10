import 'dart:async';

import 'package:baocode/extensions/window/secrets/secret_backend.dart';

/// Secrets in memory; each operation logged and, when [delay] is set,
/// finishing after it (so operations can overlap).
final class FakeSecretBackend implements SecretBackend {
  FakeSecretBackend({this.delay});

  final Duration? delay;
  final values = <String, String>{};
  final log = <String>[];

  /// Accounts whose reads fail.
  final failReads = <String>{};

  @override
  String get kind => 'fake';

  Future<void> _wait() async {
    if (delay case final delay?) await Future<void>.delayed(delay);
  }

  @override
  Future<String?> read(String account) async {
    log.add('read $account');
    await _wait();
    if (failReads.contains(account)) throw SecretBackendException('locked');
    return values[account];
  }

  @override
  Future<void> write(String account, String value) async {
    log.add('write $account=$value');
    await _wait();
    values[account] = value;
  }

  @override
  Future<void> delete(String account) async {
    log.add('delete $account');
    await _wait();
    values.remove(account);
  }
}
