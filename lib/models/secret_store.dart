// Where the providers' keys are kept: the system's keychain, not
// settings.json, which keeps only where to find them
// ([ModelProvider.keyRef]).

import 'secret_store_stub.dart'
    if (dart.library.io) 'secret_store_io.dart'
    as platform;

/// Secrets by id, kept by the system.
abstract interface class SecretStore {
  /// The app's: the system's keychain where there is one.
  static SecretStore instance = platform.systemSecretStore();

  /// The secret kept as [id]; null when there is none. Throws
  /// [SecretStoreException] when the store cannot be read.
  Future<String?> read(String id);

  /// Keeps [value] as [id], in place of what was. Throws
  /// [SecretStoreException].
  Future<void> write(String id, String value);

  /// Removes [id], if kept.
  Future<void> delete(String id);
}

class SecretStoreException implements Exception {
  const SecretStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Kept in memory only: under test, and on the web.
class MemorySecretStore implements SecretStore {
  MemorySecretStore([Map<String, String>? values]) : _values = {...?values};

  final Map<String, String> _values;

  @override
  Future<String?> read(String id) async => _values[id];

  @override
  Future<void> write(String id, String value) async => _values[id] = value;

  @override
  Future<void> delete(String id) async => _values.remove(id);
}
