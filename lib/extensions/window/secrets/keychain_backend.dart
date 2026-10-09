// The macOS login keychain through `/usr/bin/security`: generic passwords
// of the service "BaoCode Extension Secrets", one an account.

import 'dart:convert';

import 'secret_backend.dart';

/// The login keychain. A secret is never in a command line (where `ps`
/// shows it): it is added by `security -i`, which reads the command, the
/// value in hex in it, from stdin. Reads use `-g`, whose output tells text
/// from hex (`-w` prints a value that is not plain ASCII in hex, the same as
/// a value that is that hex).
final class KeychainBackend implements SecretBackend {
  KeychainBackend({SecretCommand? run}) : _run = run ?? runSecretCommand;

  final SecretCommand _run;

  static const securityPath = '/usr/bin/security';

  /// `security`'s exit code for "The specified item could not be found".
  static const notFound = 44;

  @override
  String get kind => 'keychain';

  /// The command `security -i` gets on stdin to keep [value] for [account].
  static String addCommand(String account, String value) {
    final bytes = utf8.encode(value);
    // `-X` takes no empty value; an empty password is nothing secret.
    final password = bytes.isEmpty
        ? '-w ""'
        : '-X ${[for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join()}';
    return 'add-generic-password -U -s ${quote(extensionSecretsService)} '
        '-a ${quote(account)} $password\n';
  }

  /// [text] as one word for `security -i` (double quotes; `\` escapes).
  /// It cannot take a line break: accounts have none ([secretAccount]).
  static String quote(String text) =>
      '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  /// The arguments of the command reading [account].
  static List<String> findArguments(String account) => [
    'find-generic-password',
    '-s',
    extensionSecretsService,
    '-a',
    account,
    '-g',
  ];

  /// The arguments of the command removing [account].
  static List<String> deleteArguments(String account) => [
    'delete-generic-password',
    '-s',
    extensionSecretsService,
    '-a',
    account,
  ];

  /// The password in `find-generic-password -g`'s output: `password: "…"`
  /// for printable ASCII, `password: 0x<hex>  "…"` for anything else,
  /// `password: ` for none. Null when there is no such line.
  static String? parsePassword(String output) {
    for (final line in const LineSplitter().convert(output)) {
      if (!line.startsWith('password:')) continue;
      final rest = line.substring('password:'.length).trimLeft();
      if (rest.isEmpty) return '';
      final hex = RegExp(r'^0x([0-9A-Fa-f]*)').firstMatch(rest);
      if (hex != null) {
        final digits = hex[1]!;
        return utf8.decode([
          for (var i = 0; i + 1 < digits.length; i += 2)
            int.parse(digits.substring(i, i + 2), radix: 16),
        ], allowMalformed: true);
      }
      if (rest.startsWith('"') && rest.endsWith('"') && rest.length >= 2) {
        return rest.substring(1, rest.length - 1);
      }
      return rest;
    }
    return null;
  }

  @override
  Future<String?> read(String account) async {
    final result = await _run(securityPath, findArguments(account));
    if (result.exitCode == notFound) return null;
    if (result.exitCode != 0) {
      throw SecretBackendException.command('Reading the keychain', result);
    }
    final password = parsePassword('${result.stderr}');
    if (password == null) {
      throw SecretBackendException('The keychain gave no password');
    }
    return password;
  }

  @override
  Future<void> write(String account, String value) async {
    final result = await _run(securityPath, [
      '-i',
    ], input: addCommand(account, value));
    // `-i` exits with the last command's code and says "<command>:
    // returned <n>" when one fails.
    if (result.exitCode != 0 || '${result.stderr}'.contains(': returned ')) {
      throw SecretBackendException.command('Writing to the keychain', result);
    }
  }

  @override
  Future<void> delete(String account) async {
    final result = await _run(securityPath, deleteArguments(account));
    if (result.exitCode != 0 && result.exitCode != notFound) {
      throw SecretBackendException.command(
        'Deleting from the keychain',
        result,
      );
    }
  }
}
