// What authentication keeps for the whole app, shared by every workspace's
// extension host (VS Code keeps it in its application storage, shared by
// its windows): which extensions may use which accounts, when they used
// them, account preferences, and the dynamic providers' registrations.

import 'dart:async';

import '../json_state_store.dart';
import 'authentication_access_service.dart';
import 'authentication_ports.dart';
import 'authentication_usage_service.dart';
import 'dynamic_authentication_provider_storage.dart';

final class AuthenticationAppServices {
  /// [store] is the app's authentication state (by convention
  /// `<data>/User/globalStorage/authentication.json`); [secrets] the OS's
  /// secret storage. [trustedExtensionAuthAccess],
  /// [inheritAuthAccountPreference] and [authClientIdMetadataUrl] are
  /// product.json's.
  AuthenticationAppServices({
    required this.store,
    required this.secrets,
    Object? trustedExtensionAuthAccess,
    Map<String, List<String>> inheritAuthAccountPreference = const {},
    this.authClientIdMetadataUrl,
    DateTime Function()? now,
  }) : inheritAuthAccountPreference = Map.unmodifiable(
         inheritAuthAccountPreference,
       ),
       access = AuthenticationAccessService(
         store,
         trustedExtensionAuthAccess: trustedExtensionAuthAccess,
       ),
       usage = AuthenticationUsageService(
         store,
         trustedExtensionAuthAccess: trustedExtensionAuthAccess,
         now: now,
       ),
       dynamicProviders = DynamicAuthenticationProviderStorageService(
         store,
         secrets,
       );

  /// The services on the JSON file at [path], with product.json's fields
  /// read from [product] (the runtime's product.json, when known).
  factory AuthenticationAppServices.at(
    String path, {
    required AuthSecretStore secrets,
    Map<String, Object?> product = const {},
  }) => AuthenticationAppServices(
    store: JsonStateStore(path),
    secrets: secrets,
    trustedExtensionAuthAccess: product['trustedExtensionAuthAccess'],
    inheritAuthAccountPreference: switch (product['inheritAuthAccountPreference']) {
      final Map<Object?, Object?> map => {
        for (final MapEntry(:key, :value) in map.entries)
          if (value is List) '$key': [for (final id in value) '$id'],
      },
      _ => const {},
    },
    authClientIdMetadataUrl: product['authClientIdMetadataUrl'] as String?,
  );

  final JsonStateStore store;
  final AuthSecretStore secrets;
  final AuthenticationAccessService access;
  final AuthenticationUsageService usage;
  final DynamicAuthenticationProviderStorageService dynamicProviders;

  /// product.json's `inheritAuthAccountPreference`: parent extension id →
  /// the extensions that share its account preference.
  final Map<String, List<String>> inheritAuthAccountPreference;

  /// product.json's `authClientIdMetadataUrl`.
  final String? authClientIdMetadataUrl;

  /// Reads [store]; what reads it waits for this.
  Future<void> load() => store.load();

  Future<void> dispose() async {
    access.dispose();
    dynamicProviders.dispose();
    await store.dispose();
  }
}
