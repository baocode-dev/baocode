// Where the extensions' secrets (`vscode.SecretStorage`) are kept: the
// system's store (macOS Keychain, Windows Credential Manager, the Secret
// Service on Linux), else an encrypted file. VS Code keeps them encrypted
// with Electron's safeStorage in its state database instead; BaoCode has no
// safeStorage, so it uses the system's stores directly (see
// extension_secret_service.dart).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'credential_manager_backend.dart';
import 'encrypted_file_backend.dart';
import 'keychain_backend.dart';
import 'secret_tool_backend.dart';

/// The service name (Keychain), attribute (Secret Service) and target prefix
/// (Credential Manager) the extensions' secrets are kept under.
const extensionSecretsService = 'BaoCode Extension Secrets';

/// A store of secrets by account name ([secretAccount]).
abstract interface class SecretBackend {
  /// What it is, for logs and tests (`keychain`, `credential-manager`,
  /// `secret-tool`, `encrypted-file`).
  String get kind;

  /// The value of [account]; null when there is none.
  Future<String?> read(String account);

  /// Keeps [value] for [account], replacing what it had.
  Future<void> write(String account, String value);

  /// Removes [account]'s value; nothing when it has none.
  Future<void> delete(String account);

  /// The store of this system: Keychain on macOS, Credential Manager on
  /// Windows, the Secret Service where `secret-tool` is installed and
  /// answers; else an encrypted file in [fallbackDirectory], and
  /// [onFallback] called once, before the first secret goes into it.
  ///
  /// Probes on first use (so making it costs nothing).
  static SecretBackend forPlatform({
    required String fallbackDirectory,
    void Function()? onFallback,
    String? operatingSystem,
    SecretCommand? run,
    bool Function(String path)? fileExists,
  }) => ProbingSecretBackend(
    () => probeSecretBackend(
      operatingSystem: operatingSystem ?? Platform.operatingSystem,
      fallbackDirectory: fallbackDirectory,
      run: run ?? runSecretCommand,
      fileExists: fileExists ?? (path) => File(path).existsSync(),
    ),
    onFallback: onFallback,
  );
}

/// Picks the store of [operatingSystem] (see [SecretBackend.forPlatform]).
Future<SecretBackend> probeSecretBackend({
  required String operatingSystem,
  required String fallbackDirectory,
  required SecretCommand run,
  required bool Function(String path) fileExists,
}) async {
  switch (operatingSystem) {
    case 'macos' when fileExists(KeychainBackend.securityPath):
      return KeychainBackend(run: run);
    case 'windows':
      return CredentialManagerBackend();
    case 'linux' || 'freebsd' || 'openbsd':
      if (await SecretToolBackend.isAvailable(run)) {
        return SecretToolBackend(run: run);
      }
  }
  return EncryptedFileBackend(fallbackDirectory);
}

/// A [SecretBackend] chosen on first use; [onFallback] runs once, before the
/// first write, when the choice is the encrypted file.
final class ProbingSecretBackend implements SecretBackend {
  ProbingSecretBackend(this._probe, {this.onFallback});

  final Future<SecretBackend> Function() _probe;
  final void Function()? onFallback;
  Future<SecretBackend>? _chosen;
  bool _warned = false;

  /// The backend in use.
  Future<SecretBackend> get chosen => _chosen ??= _probe();

  @override
  String get kind => 'probing';

  @override
  Future<String?> read(String account) async => (await chosen).read(account);

  @override
  Future<void> write(String account, String value) async {
    final backend = await chosen;
    if (backend is EncryptedFileBackend && !_warned) {
      _warned = true;
      onFallback?.call();
    }
    await backend.write(account, value);
  }

  @override
  Future<void> delete(String account) async => (await chosen).delete(account);
}

/// The account name of [extensionId]'s secret [key]: `<extensionId>/<key>`,
/// with `%` and control characters (which `security -i` cannot take, and a
/// NUL no store can) written `%XX`, and `/` too in the extension id, so no
/// two (id, key) pairs share one.
String secretAccount(String extensionId, String key) =>
    '${_escape(extensionId, slash: true)}/${_escape(key, slash: false)}';

String _escape(String text, {required bool slash}) {
  final out = StringBuffer();
  for (final unit in text.codeUnits) {
    if (unit < 0x20 ||
        unit == 0x7f ||
        unit == 0x25 ||
        (slash && unit == 0x2f)) {
      out.write('%${unit.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    } else {
      out.writeCharCode(unit);
    }
  }
  return out.toString();
}

/// Runs [executable] with [arguments], [input] on its stdin (UTF-8).
typedef SecretCommand = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? input,
});

/// Runs a command for a store: its output decoded as UTF-8; killed after
/// two minutes (a store may wait for the user to unlock it).
Future<ProcessResult> runSecretCommand(
  String executable,
  List<String> arguments, {
  String? input,
}) async {
  final process = await Process.start(executable, arguments);
  final stdout = process.stdout.transform(utf8.decoder).join();
  final stderr = process.stderr.transform(utf8.decoder).join();
  try {
    if (input != null) process.stdin.add(utf8.encode(input));
    await process.stdin.close();
  } on Object {
    // It quit before reading: its exit code says why.
  }
  final code = await process.exitCode.timeout(
    const Duration(minutes: 2),
    onTimeout: () {
      process.kill();
      return -1;
    },
  );
  return ProcessResult(process.pid, code, await stdout, await stderr);
}

/// A store failed.
final class SecretBackendException implements Exception {
  SecretBackendException(this.message);

  final String message;

  /// [what] failed, from [result]'s exit code and output.
  factory SecretBackendException.command(String what, ProcessResult result) {
    final said = '${result.stderr}'.trim();
    return SecretBackendException(
      '$what failed${said.isEmpty ? ' (exit ${result.exitCode})' : ': $said'}',
    );
  }

  @override
  String toString() => message;
}
