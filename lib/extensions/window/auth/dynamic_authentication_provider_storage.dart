/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/authentication/browser/dynamicAuthenticationProviderStorageService.ts
// and ../common/dynamicAuthenticationProviderStorage.ts.
//
// Deviations: the provider list is in the app's JsonStateStore (upstream's
// application storage), the secrets in an [AuthSecretStore].

import 'dart:async';
import 'dart:convert';

import '../json_state_store.dart';
import 'authentication_ports.dart';
import 'authentication_types.dart';

/// `DynamicAuthenticationProviderInfo`.
typedef DynamicAuthProviderInfo = ({
  String providerId,
  String label,
  String authorizationServer,
  String clientId,
});

/// `DynamicAuthenticationProviderTokensChangeEvent`.
typedef DynamicAuthProviderTokensChange = ({
  String authProviderId,
  String clientId,
  List<Map<String, Object?>>? tokens,
});

final class DynamicAuthenticationProviderStorageService {
  DynamicAuthenticationProviderStorageService(this._store, this._secrets) {
    // Tokens are stored under a JSON key; a change to one is a change of
    // the provider's tokens.
    _secretChanges = _secrets.onDidChange.listen((key) {
      Object? payload;
      try {
        payload = jsonDecode(key);
      } on FormatException {
        return;
      }
      if (payload is! Map || payload['isDynamicAuthProvider'] != true) return;
      final authProviderId = '${payload['authProviderId']}';
      final clientId = '${payload['clientId']}';
      _queue = _queue.then((_) async {
        final tokens = await getSessionsForDynamicAuthProvider(
          authProviderId,
          clientId,
        );
        if (!_onDidChangeTokens.isClosed) {
          _onDidChangeTokens.add((
            authProviderId: authProviderId,
            clientId: clientId,
            tokens: tokens,
          ));
        }
      }).catchError((Object _) {});
    });
  }

  static const _providersKey = 'dynamicAuthProviders';

  final JsonStateStore _store;
  final AuthSecretStore _secrets;
  late final StreamSubscription<String> _secretChanges;
  Future<void> _queue = Future.value();

  final _onDidChangeTokens =
      StreamController<DynamicAuthProviderTokensChange>.broadcast(sync: true);

  Stream<DynamicAuthProviderTokensChange> get onDidChangeTokens =>
      _onDidChangeTokens.stream;

  static String _registrationKey(String providerId) =>
      'dynamicAuthProvider:clientRegistration:$providerId';

  static String _tokensKey(String authProviderId, String clientId) =>
      jsonEncode({
        'isDynamicAuthProvider': true,
        'authProviderId': authProviderId,
        'clientId': clientId,
      });

  Future<({String? clientId, String? clientSecret})?> getClientRegistration(
    String providerId,
  ) async {
    final key = _registrationKey(providerId);
    final value = await _secrets.get(key);
    if (value != null) {
      try {
        final json = jsonDecode(value);
        if (json is Map &&
            (json['clientId'] != null || json['clientSecret'] != null)) {
          return (
            clientId: json['clientId'] as String?,
            clientSecret: json['clientSecret'] as String?,
          );
        }
      } on FormatException {
        await _secrets.delete(key);
      }
    }
    final provider = _storedProviders()
        .where((p) => p.providerId == providerId)
        .firstOrNull;
    return provider != null && provider.clientId.isNotEmpty
        ? (clientId: provider.clientId, clientSecret: null)
        : null;
  }

  String? getClientId(String providerId) => _storedProviders()
      .where((p) => p.providerId == providerId)
      .firstOrNull
      ?.clientId;

  Future<void> storeClientRegistration(
    String providerId,
    String authorizationServer,
    String clientId, [
    String? clientSecret,
    String? label,
  ]) async {
    _trackProvider(providerId, authorizationServer, clientId, label);
    await _secrets.set(
      _registrationKey(providerId),
      jsonEncode({'clientId': clientId, 'clientSecret': ?clientSecret}),
    );
  }

  void _trackProvider(
    String providerId,
    String authorizationServer,
    String clientId,
    String? label,
  ) {
    final providers = _storedProviders();
    final index = providers.indexWhere((p) => p.providerId == providerId);
    final hasLabel = label != null && label.isNotEmpty;
    final info = (
      providerId: providerId,
      label: hasLabel
          ? label
          : (index == -1 ? providerId : providers[index].label),
      authorizationServer: authorizationServer,
      clientId: clientId,
    );
    if (index == -1) {
      providers.add(info);
    } else {
      providers[index] = info;
    }
    _storeProviders(providers);
  }

  List<DynamicAuthProviderInfo> _storedProviders() {
    final stored = _store.get(_providersKey) ?? '[]';
    try {
      final json = jsonDecode(stored);
      if (json is! List) return [];
      return [
        for (final p in json)
          if (p is Map)
            (
              providerId: '${p['providerId']}',
              label: '${p['label'] ?? p['providerId']}',
              // Migration: `issuer` was its name before.
              authorizationServer:
                  '${p['authorizationServer'] ?? p['issuer'] ?? ''}',
              clientId: '${p['clientId'] ?? ''}',
            ),
      ];
    } on FormatException {
      return [];
    }
  }

  void _storeProviders(List<DynamicAuthProviderInfo> providers) => _store.set(
    _providersKey,
    jsonEncode([
      for (final p in providers)
        {
          'providerId': p.providerId,
          'label': p.label,
          'authorizationServer': p.authorizationServer,
          'clientId': p.clientId,
        },
    ]),
  );

  List<DynamicAuthProviderInfo> getInteractedProviders() => _storedProviders();

  Future<void> removeDynamicProvider(String providerId) async {
    final providers = _storedProviders();
    final info = providers.where((p) => p.providerId == providerId).firstOrNull;
    _storeProviders([
      for (final p in providers)
        if (p.providerId != providerId) p,
    ]);
    if (info != null) {
      await _secrets.delete(_tokensKey(providerId, info.clientId));
    }
    await _secrets.delete(_registrationKey(providerId));
  }

  Future<List<Map<String, Object?>>?> getSessionsForDynamicAuthProvider(
    String authProviderId,
    String clientId,
  ) async {
    final key = _tokensKey(authProviderId, clientId);
    final value = await _secrets.get(key);
    if (value == null) return null;
    Object? parsed;
    try {
      parsed = jsonDecode(value);
    } on FormatException {
      parsed = null;
    }
    if (parsed is! List ||
        !parsed.every(
          (t) =>
              t is Map &&
              t['created_at'] is num &&
              isAuthorizationTokenResponse(t),
        )) {
      await _secrets.delete(key);
      return null;
    }
    return [for (final t in parsed) (t as Map).cast<String, Object?>()];
  }

  Future<void> setSessionsForDynamicAuthProvider(
    String authProviderId,
    String clientId,
    List<Map<String, Object?>> sessions,
  ) => _secrets.set(_tokensKey(authProviderId, clientId), jsonEncode(sessions));

  void dispose() {
    unawaited(_secretChanges.cancel());
    unawaited(_onDidChangeTokens.close());
  }
}
