// The Secret Service (GNOME Keyring, KWallet, KeePassXC…) through
// libsecret's `secret-tool`: items with the attributes
// `service = BaoCode Extension Secrets` and `account = <account>`.

import 'secret_backend.dart';

/// The Secret Service. Values go on `secret-tool store`'s stdin, never in
/// its command line; `lookup` prints them as they are (no line break when
/// its output is not a terminal).
final class SecretToolBackend implements SecretBackend {
  SecretToolBackend({SecretCommand? run}) : _run = run ?? runSecretCommand;

  final SecretCommand _run;

  static const executable = 'secret-tool';

  /// The account used to see whether the Secret Service answers.
  static const probeAccount = '.baocode-probe';

  @override
  String get kind => 'secret-tool';

  /// The attributes of [account]'s item.
  static List<String> attributes(String account) => [
    'service',
    extensionSecretsService,
    'account',
    account,
  ];

  static List<String> storeArguments(String account) => [
    'store',
    '--label=$extensionSecretsService: $account',
    ...attributes(account),
  ];

  static List<String> lookupArguments(String account) => [
    'lookup',
    ...attributes(account),
  ];

  static List<String> clearArguments(String account) => [
    'clear',
    ...attributes(account),
  ];

  /// Whether `secret-tool` is installed and a Secret Service answers (a
  /// lookup that finds nothing exits 1 and says nothing; one with no
  /// service, or no D-Bus session, says why).
  static Future<bool> isAvailable(SecretCommand run) async {
    try {
      final which = await run('which', [executable]);
      if (which.exitCode != 0) return false;
      final probe = await run(executable, lookupArguments(probeAccount));
      return probe.exitCode == 0 || '${probe.stderr}'.trim().isEmpty;
    } on Object {
      return false;
    }
  }

  @override
  Future<String?> read(String account) async {
    final result = await _run(executable, lookupArguments(account));
    if (result.exitCode != 0) {
      if ('${result.stderr}'.trim().isEmpty) return null;
      throw SecretBackendException.command('Reading the keyring', result);
    }
    return '${result.stdout}';
  }

  @override
  Future<void> write(String account, String value) async {
    final result = await _run(
      executable,
      storeArguments(account),
      input: value,
    );
    if (result.exitCode != 0) {
      throw SecretBackendException.command('Writing to the keyring', result);
    }
  }

  @override
  Future<void> delete(String account) async {
    final result = await _run(executable, clearArguments(account));
    // Clearing what is not there exits 1 and says nothing.
    if (result.exitCode != 0 && '${result.stderr}'.trim().isNotEmpty) {
      throw SecretBackendException.command('Deleting from the keyring', result);
    }
  }
}
