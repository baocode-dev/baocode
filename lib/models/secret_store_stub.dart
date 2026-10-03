import 'secret_store.dart';

/// The web has no keychain to ask: kept for this run.
SecretStore systemSecretStore() => MemorySecretStore();
