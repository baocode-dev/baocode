/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/authentication/browser/authenticationService.ts
// (`AuthenticationService`).
//
// Deviations:
// - One per workspace (its extension host holds the providers); the access
//   lists it listens to are the app's.
// - The declared providers are read from the host's scanned extensions'
//   `contributes.authentication` when asked, not kept by an extension
//   point handler; no providers contributed by the embedder.
// - No XAA providers (`createOrGetXaaProvider`): only MCP asks for them, and
//   BaoCode has no MCP client in the workbench.

import 'dart:async';

import 'package:bao_editor/monaco/vs/base/common/glob.dart' as glob;
import 'package:bao_exthost/bao_exthost.dart';

import 'authentication_access_service.dart';
import 'authentication_ports.dart';
import 'authentication_types.dart';

/// `IAuthenticationProviderHostDelegate`: makes dynamic providers in an
/// extension host.
abstract interface class AuthenticationProviderHostDelegate {
  int get priority;

  /// Registers a dynamic provider; its id.
  Future<String> create(
    VsUri authorizationServer,
    Map<String, Object?> serverMetadata,
    Map<String, Object?>? resource, [
    String? clientId,
    String? clientSecret,
  ]);
}

final class AuthenticationService {
  AuthenticationService({
    required AuthenticationAccessService access,
    this.providerRegistrationTimeout = const Duration(seconds: 5),
  }) {
    _accessChanges = access.onDidChangeExtensionSessionAccess.listen((e) {
      // Extensions learn that they gained access to an account through a
      // change of the sessions.
      _onDidChangeSessions.add((
        providerId: e.providerId,
        label: e.accountName,
        event: const AuthSessionsChangeEvent(
          added: [],
          changed: [],
          removed: [],
        ),
      ));
    });
  }

  /// How long a provider has to register once its extension activated.
  final Duration providerRegistrationTimeout;

  /// The extension host whose extensions provide accounts; null until one
  /// runs.
  AuthenticationExtensionHost? host;

  late final StreamSubscription<Object?> _accessChanges;
  bool _disposed = false;

  /// Whether it was disposed (its providers unregistered).
  bool get isDisposed => _disposed;

  final _onDidRegisterAuthenticationProvider =
      StreamController<({String id, String label})>.broadcast(sync: true);
  final _onDidUnregisterAuthenticationProvider =
      StreamController<({String id, String label})>.broadcast(sync: true);
  final _onDidChangeSessions =
      StreamController<AuthProviderSessionsChange>.broadcast(sync: true);

  Stream<({String id, String label})> get onDidRegisterAuthenticationProvider =>
      _onDidRegisterAuthenticationProvider.stream;
  Stream<({String id, String label})>
  get onDidUnregisterAuthenticationProvider =>
      _onDidUnregisterAuthenticationProvider.stream;
  Stream<AuthProviderSessionsChange> get onDidChangeSessions =>
      _onDidChangeSessions.stream;

  final _providers = <String, AuthenticationProvider>{};
  final _providerSubscriptions = <String, StreamSubscription<Object?>>{};
  final _dynamicProviderIds = <String>{};
  final _delegates = <AuthenticationProviderHostDelegate>[];

  /// The providers the host's extensions declare (`contributes.
  /// authentication`), the first declaration of an id winning.
  List<AuthProviderInfo> get declaredProviders {
    final result = <AuthProviderInfo>[];
    for (final extension in host?.extensions ?? const <Map<String, Object?>>[]) {
      final contributes = extension['contributes'];
      if (contributes is! Map) continue;
      final authentication = contributes['authentication'];
      if (authentication is! List) continue;
      for (final provider in authentication) {
        if (provider is! Map) continue;
        final id = provider['id'];
        final label = provider['label'];
        if (id is! String || id.trim().isEmpty) continue;
        if (label is! String || label.trim().isEmpty) continue;
        if (result.any((p) => p.id == id)) continue;
        result.add((
          id: id,
          label: label,
          authorizationServerGlobs: switch (provider['authorizationServerGlobs']) {
            final List<Object?> globs => [for (final g in globs) '$g'],
            _ => null,
          },
        ));
      }
    }
    return result;
  }

  bool isAuthenticationProviderRegistered(String id) =>
      _providers.containsKey(id);

  bool isDynamicAuthenticationProvider(String id) =>
      _dynamicProviderIds.contains(id);

  void registerAuthenticationProvider(
    String id,
    AuthenticationProvider provider,
  ) {
    _providers[id] = provider;
    unawaited(_providerSubscriptions.remove(id)?.cancel());
    _providerSubscriptions[id] = provider.onDidChangeSessions.listen(
      (event) => _onDidChangeSessions.add((
        providerId: id,
        label: provider.label,
        event: event,
      )),
    );
    _onDidRegisterAuthenticationProvider.add((id: id, label: provider.label));
  }

  void unregisterAuthenticationProvider(String id) {
    final provider = _providers.remove(id);
    if (provider != null) {
      _dynamicProviderIds.remove(id);
      _onDidUnregisterAuthenticationProvider.add((
        id: id,
        label: provider.label,
      ));
    }
    unawaited(_providerSubscriptions.remove(id)?.cancel());
    provider?.dispose();
  }

  List<String> getProviderIds() => [
    for (final provider in _providers.values) provider.id,
  ];

  AuthenticationProvider getProvider(String id) =>
      _providers[id] ??
      (throw AuthenticationError(
        "No authentication provider '$id' is currently registered.",
      ));

  Future<List<AuthAccount>> getAccounts(String id) async {
    final sessions = await getSessions(id);
    final accounts = <AuthAccount>[];
    final seen = <String>{};
    for (final session in sessions) {
      if (seen.add(session.account.label)) accounts.add(session.account);
    }
    return accounts;
  }

  /// [scopeListOrRequest] is a list of scopes or a WWW-Authenticate request
  /// (`{wwwAuthenticate, fallbackScopes?}`); [options] has `account` and
  /// `authorizationServer` (a [VsUri]).
  Future<List<AuthSession>> getSessions(
    String id, {
    Object? scopeListOrRequest,
    AuthAccount? account,
    VsUri? authorizationServer,
    bool activateImmediate = false,
  }) async {
    if (_disposed) return [];
    final provider =
        _providers[id] ?? await _tryActivateProvider(id, activateImmediate);
    if (authorizationServer != null &&
        !_matchesProvider(provider, authorizationServer)) {
      throw AuthenticationError(
        "The authentication provider '$id' does not support the authorization "
        "server '${authorizationServer.toString(skipEncoding: true)}'.",
      );
    }
    final options = <String, Object?>{
      'account': ?account?.json,
      'authorizationServer': ?authorizationServer?.toJson(),
    };
    if (isWwwAuthenticateRequest(scopeListOrRequest)) {
      if (!provider.supportsChallenges) {
        throw AuthenticationError(
          "The authentication provider '$id' does not support getting "
          'sessions from challenges.',
        );
      }
      return provider.getSessionsFromChallenges(
        _constraint(scopeListOrRequest! as Map),
        options,
      );
    }
    return provider.getSessions(scopesOf(scopeListOrRequest), options);
  }

  Future<AuthSession> createSession(
    String id,
    Object? scopeListOrRequest, {
    bool activateImmediate = false,
    AuthAccount? account,
    VsUri? authorizationServer,
  }) async {
    if (_disposed) {
      throw const AuthenticationError('Authentication service is disposed.');
    }
    final provider =
        _providers[id] ?? await _tryActivateProvider(id, activateImmediate);
    // Upstream passes its options on as they are (`{...options}`).
    final options = <String, Object?>{
      'activateImmediate': activateImmediate,
      'account': ?account?.json,
      'authorizationServer': ?authorizationServer?.toJson(),
    };
    if (isWwwAuthenticateRequest(scopeListOrRequest)) {
      if (!provider.supportsChallenges) {
        throw AuthenticationError(
          "The authentication provider '$id' does not support creating "
          'sessions from challenges.',
        );
      }
      return provider.createSessionFromChallenges(
        _constraint(scopeListOrRequest! as Map),
        options,
      );
    }
    return provider.createSession(scopesOf(scopeListOrRequest) ?? [], options);
  }

  Future<void> removeSession(String id, String sessionId) async {
    if (_disposed) {
      throw const AuthenticationError('Authentication service is disposed.');
    }
    final provider = _providers[id];
    if (provider == null) {
      throw AuthenticationError(
        "No authentication provider '$id' is currently registered.",
      );
    }
    await provider.removeSession(sessionId);
  }

  static Map<String, Object?> _constraint(Map<Object?, Object?> request) => {
    'challenges': parseWwwAuthenticateHeader('${request['wwwAuthenticate']}'),
    'fallbackScopes': ?request['fallbackScopes'],
  };

  /// The provider of [authorizationServer] (and [resourceServer]),
  /// activating a declared one whose globs match it.
  Future<String?> getOrActivateProviderIdForServer(
    VsUri authorizationServer, [
    VsUri? resourceServer,
  ]) async {
    for (final provider in _providers.values) {
      if (_matchesProvider(provider, authorizationServer, resourceServer)) {
        return provider.id;
      }
    }
    final server = authorizationServer.toString(skipEncoding: true);
    final candidates = declaredProviders
        .where((p) => !_providers.containsKey(p.id))
        .where(
          (p) => (p.authorizationServerGlobs ?? const []).any(
            (g) => glob.match(g, server, const glob.IGlobOptions(ignoreCase: true)),
          ),
        );
    for (final declared in candidates) {
      final provider = await _tryActivateProvider(declared.id, true);
      if (_matchesProvider(provider, authorizationServer, resourceServer)) {
        return provider.id;
      }
    }
    return null;
  }

  Future<AuthenticationProvider?> createDynamicAuthenticationProvider(
    VsUri authorizationServer,
    Map<String, Object?> serverMetadata,
    Map<String, Object?>? resource, [
    String? clientId,
    String? clientSecret,
  ]) async {
    final delegate = _delegates.firstOrNull;
    if (delegate == null) return null;
    final providerId = await delegate.create(
      authorizationServer,
      serverMetadata,
      resource,
      clientId,
      clientSecret,
    );
    final provider = _providers[providerId];
    if (provider == null) return null;
    _dynamicProviderIds.add(providerId);
    return provider;
  }

  /// Adds [delegate]; call the result to remove it.
  void Function() registerAuthenticationProviderHostDelegate(
    AuthenticationProviderHostDelegate delegate,
  ) {
    _delegates
      ..add(delegate)
      ..sort((a, b) => b.priority - a.priority);
    return () => _delegates.remove(delegate);
  }

  bool _matchesProvider(
    AuthenticationProvider provider,
    VsUri authorizationServer, [
    VsUri? resourceServer,
  ]) {
    final providerResource = provider.resourceServer;
    if (resourceServer != null && providerResource != null) {
      if (providerResource.toString(skipEncoding: true).toLowerCase() !=
          resourceServer.toString(skipEncoding: true).toLowerCase()) {
        return false;
      }
    }
    final server = authorizationServer.toString(skipEncoding: true);
    for (final candidate in provider.authorizationServers) {
      final str = candidate.toString(skipEncoding: true);
      if (str.toLowerCase() == server.toLowerCase() ||
          glob.match(str, server, const glob.IGlobOptions(ignoreCase: true))) {
        return true;
      }
    }
    return false;
  }

  /// Activates [providerId]'s extension and waits for it to register the
  /// provider; it need not wait for the activation to end (#315841).
  Future<AuthenticationProvider> _tryActivateProvider(
    String providerId,
    bool activateImmediate,
  ) async {
    final registered = Completer<bool>();
    final subscription = onDidRegisterAuthenticationProvider.listen((e) {
      if (e.id == providerId && !registered.isCompleted) {
        registered.complete(true);
      }
    });
    try {
      final host = this.host;
      final Future<void> activation = host == null
          ? Future.value()
          : host
                .activateByEvent(
                  authenticationProviderActivationEvent(providerId),
                  immediate: activateImmediate,
                )
                .catchError((Object _) {});
      var provider = _providers[providerId];
      if (provider != null) return provider;
      if (_disposed) {
        throw const AuthenticationError('Authentication service is disposed.');
      }
      await Future.any([activation, registered.future]);
      provider = _providers[providerId];
      if (provider != null) return provider;
      final result = await raceTimeout(
        registered.future,
        providerRegistrationTimeout,
      );
      provider = _providers[providerId];
      if (provider != null) return provider;
      if (result == null) {
        throw AuthenticationError(
          "Timed out waiting for authentication provider '$providerId' to "
          'register.',
        );
      }
      throw AuthenticationError(
        "No authentication provider '$providerId' is currently registered.",
      );
    } finally {
      await subscription.cancel();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_accessChanges.cancel());
    for (final subscription in _providerSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _providerSubscriptions.clear();
    for (final provider in _providers.values) {
      provider.dispose();
    }
    _providers.clear();
    unawaited(_onDidRegisterAuthenticationProvider.close());
    unawaited(_onDidUnregisterAuthenticationProvider.close());
    unawaited(_onDidChangeSessions.close());
  }
}
