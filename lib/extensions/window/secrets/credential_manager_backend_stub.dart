// Without dart:ffi (the web build) there is no Credential Manager; the web
// runs no extensions, so nothing asks for it.

import 'secret_backend.dart';

final class CredentialManagerBackend implements SecretBackend {
  @override
  String get kind => 'credential-manager';

  @override
  Future<String?> read(String account) => throw UnsupportedError(kind);

  @override
  Future<void> write(String account, String value) =>
      throw UnsupportedError(kind);

  @override
  Future<void> delete(String account) => throw UnsupportedError(kind);
}
