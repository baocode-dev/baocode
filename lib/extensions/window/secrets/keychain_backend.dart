// The macOS login keychain through `/usr/bin/security`: generic passwords
// of the service "BaoCode Extension Secrets", one an account.
//
// `security -i` reads a line of at most 4096 characters, and a value goes in
// hex (two characters a byte): longer values (an OAuth session list can be)
// are split into parts of [KeychainBackend.partSize] bytes, as the
// Credential Manager's, the first under the service above with `parts=<n>`
// in its comment, the others under `BaoCode Extension Secrets (part <i>)`.

import 'dart:convert';
import 'dart:typed_data';

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

  /// The bytes of a part: 2048 hex characters, which leave a command line
  /// room for the account.
  static const partSize = 1024;

  /// The longest line `security -i` reads whole (4096 with its line break,
  /// measured on macOS 26), less a margin.
  static const maxLine = 4000;

  @override
  String get kind => 'keychain';

  /// The service of [account]'s [part] (0 is the first).
  static String service({int part = 0}) => part == 0
      ? extensionSecretsService
      : '$extensionSecretsService (part ${part + 1})';

  /// [bytes] in parts of at most [partSize] (one, empty, for no bytes).
  static List<Uint8List> split(Uint8List bytes) => [
    for (var at = 0; at == 0 || at < bytes.length; at += partSize)
      Uint8List.sublistView(
        bytes,
        at,
        at + partSize < bytes.length ? at + partSize : bytes.length,
      ),
  ];

  /// The command `security -i` gets on stdin to keep [bytes] as [account]'s
  /// [part]; the first part's comment says how many [parts] there are.
  static String addCommand(
    String account,
    List<int> bytes, {
    int part = 0,
    int parts = 1,
  }) {
    // `-X` takes no empty value; an empty password is nothing secret.
    final password = bytes.isEmpty
        ? '-w ""'
        : '-X ${[for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join()}';
    final comment = part == 0 ? '-j ${quote('parts=$parts')} ' : '';
    final line =
        'add-generic-password -U -s ${quote(service(part: part))} '
        '-a ${quote(account)} $comment$password';
    if (line.length > maxLine) {
      throw SecretBackendException(
        'The key is too long for the keychain (${account.length} characters)',
      );
    }
    return '$line\n';
  }

  /// [text] as one word for `security -i` (double quotes; `\` escapes).
  /// It cannot take a line break: accounts have none ([secretAccount]).
  static String quote(String text) =>
      '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  /// The arguments of the command reading [account]'s [part], with its
  /// password when [password].
  static List<String> findArguments(
    String account, {
    int part = 0,
    bool password = true,
  }) => [
    'find-generic-password',
    '-s',
    service(part: part),
    '-a',
    account,
    if (password) '-g',
  ];

  /// The arguments of the command removing [account]'s [part].
  static List<String> deleteArguments(String account, {int part = 0}) => [
    'delete-generic-password',
    '-s',
    service(part: part),
    '-a',
    account,
  ];

  /// How many parts the value is in, from its first part's attributes
  /// (`find-generic-password`'s stdout): `"icmt"<blob>="parts=<n>"`; one
  /// without (a value kept before values were split).
  static int parseParts(String attributes) {
    final match = RegExp(r'"icmt"<blob>="parts=(\d+)"').firstMatch(attributes);
    final parts = match == null ? 1 : int.parse(match[1]!);
    return parts < 1 ? 1 : parts;
  }

  /// The password's bytes in `find-generic-password -g`'s output:
  /// `password: "…"` for printable ASCII, `password: 0x<hex>  "…"` for
  /// anything else (a part may end inside a character), `password: ` for
  /// none. Null when there is no such line.
  static List<int>? parsePasswordBytes(String output) {
    for (final line in const LineSplitter().convert(output)) {
      if (!line.startsWith('password:')) continue;
      final rest = line.substring('password:'.length).trimLeft();
      if (rest.isEmpty) return const [];
      final hex = RegExp(r'^0x([0-9A-Fa-f]*)').firstMatch(rest);
      if (hex != null) {
        final digits = hex[1]!;
        return [
          for (var i = 0; i + 1 < digits.length; i += 2)
            int.parse(digits.substring(i, i + 2), radix: 16),
        ];
      }
      if (rest.startsWith('"') && rest.endsWith('"') && rest.length >= 2) {
        return utf8.encode(rest.substring(1, rest.length - 1));
      }
      return utf8.encode(rest);
    }
    return null;
  }

  /// The password in `find-generic-password -g`'s output, as text (see
  /// [parsePasswordBytes]).
  static String? parsePassword(String output) {
    final bytes = parsePasswordBytes(output);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  /// How many parts [account]'s value is in; 0 when there is none.
  Future<int> _parts(String account) async {
    final result = await _run(
      securityPath,
      findArguments(account, password: false),
    );
    if (result.exitCode == notFound) return 0;
    if (result.exitCode != 0) {
      throw SecretBackendException.command('Reading the keychain', result);
    }
    return parseParts('${result.stdout}');
  }

  @override
  Future<String?> read(String account) async {
    final bytes = BytesBuilder(copy: false);
    var parts = 1;
    for (var part = 0; part < parts; part++) {
      final result = await _run(
        securityPath,
        findArguments(account, part: part),
      );
      if (result.exitCode == notFound) {
        if (part == 0) return null;
        throw SecretBackendException('Part ${part + 1} of a secret is missing');
      }
      if (result.exitCode != 0) {
        throw SecretBackendException.command('Reading the keychain', result);
      }
      if (part == 0) parts = parseParts('${result.stdout}');
      final password = parsePasswordBytes('${result.stderr}');
      if (password == null) {
        throw SecretBackendException('The keychain gave no password');
      }
      bytes.add(password);
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  @override
  Future<void> write(String account, String value) async {
    final oldParts = await _parts(account);
    final parts = split(utf8.encode(value));
    // The other parts first: the first one says how many there are. Then
    // the old value's parts past the new one's.
    final input = StringBuffer();
    for (var part = 1; part < parts.length; part++) {
      input.write(addCommand(account, parts[part], part: part));
    }
    input.write(addCommand(account, parts.first, parts: parts.length));
    for (var part = parts.length; part < oldParts; part++) {
      input.writeln(deleteArguments(account, part: part).map(quote).join(' '));
    }
    final result = await _run(securityPath, ['-i'], input: '$input');
    // `-i` exits with the last command's code and says "<command>:
    // returned <n>" when one fails.
    if (result.exitCode != 0 || '${result.stderr}'.contains(': returned ')) {
      throw SecretBackendException.command('Writing to the keychain', result);
    }
  }

  @override
  Future<void> delete(String account) async {
    final parts = await _parts(account);
    for (var part = 0; part < parts; part++) {
      final result = await _run(
        securityPath,
        deleteArguments(account, part: part),
      );
      if (result.exitCode != 0 && result.exitCode != notFound) {
        throw SecretBackendException.command(
          'Deleting from the keychain',
          result,
        );
      }
    }
  }
}
