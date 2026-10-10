/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/authentication/common/authentication.ts (the
// session, account and provider types, `AllowedExtension`,
// `isAuthenticationWwwAuthenticateRequest`,
// `getDynamicAuthenticationProviderId`, `INTERNAL_AUTH_PROVIDER_PREFIX`),
// src/vs/base/common/oauth.ts (`scopesMatch`, `parseWWWAuthenticateHeader`,
// `isAuthorizationTokenResponse`) and
// src/vs/workbench/services/authentication/browser/authenticationService.ts
// (`getAuthenticationProviderActivationEvent`).
//
// Deviations: sessions and accounts stay the JSON maps the extension host
// sends (read through extension types), so what goes back is what came.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

/// `INTERNAL_AUTH_PROVIDER_PREFIX`: providers whose changes extensions are
/// not told of, and that the accounts menu does not show.
const internalAuthProviderPrefix = '__';

/// `getAuthenticationProviderActivationEvent`.
String authenticationProviderActivationEvent(String id) =>
    'onAuthenticationRequest:$id';

/// An `AuthenticationSessionAccount` as sent: `{id, label, icon?}`.
extension type const AuthAccount(Map<String, Object?> json) {
  String get id => '${json['id']}';
  String get label => '${json['label']}';
}

/// An `AuthenticationSession` as sent: `{id, accessToken, account, scopes,
/// idToken?}`.
extension type const AuthSession(Map<String, Object?> json) {
  String get id => '${json['id']}';
  String get accessToken => '${json['accessToken']}';
  AuthAccount get account => AuthAccount(switch (json['account']) {
    final Map<Object?, Object?> map => map.cast<String, Object?>(),
    _ => const <String, Object?>{},
  });
  List<String> get scopes => switch (json['scopes']) {
    final List<Object?> list => [for (final s in list) '$s'],
    _ => const [],
  };
}

/// Sessions from a JSON list.
List<AuthSession> authSessionsFrom(Object? list) => switch (list) {
  final List<Object?> items => [
    for (final item in items)
      if (item is Map) AuthSession(item.cast<String, Object?>()),
  ],
  _ => const [],
};

/// `AuthenticationSessionsChangeEvent`.
final class AuthSessionsChangeEvent {
  const AuthSessionsChangeEvent({this.added, this.removed, this.changed});

  /// From what the extension host sends (`$sendDidChangeSessions`).
  factory AuthSessionsChangeEvent.fromJson(Map<String, Object?> json) =>
      AuthSessionsChangeEvent(
        added: json['added'] == null ? null : authSessionsFrom(json['added']),
        removed: json['removed'] == null
            ? null
            : authSessionsFrom(json['removed']),
        changed: json['changed'] == null
            ? null
            : authSessionsFrom(json['changed']),
      );

  final List<AuthSession>? added;
  final List<AuthSession>? removed;
  final List<AuthSession>? changed;
}

/// `onDidChangeSessions`'s event of the service: which provider, and what.
typedef AuthProviderSessionsChange = ({
  String providerId,
  String label,
  AuthSessionsChangeEvent event,
});

/// `AuthenticationProviderInformation`.
typedef AuthProviderInfo = ({
  String id,
  String label,
  List<String>? authorizationServerGlobs,
});

/// `AllowedExtension`: an extension's access to an account.
final class AllowedExtension {
  AllowedExtension({
    required this.id,
    required this.name,
    this.allowed,
    this.lastUsed,
    this.trusted,
  });

  factory AllowedExtension.fromJson(Map<Object?, Object?> json) =>
      AllowedExtension(
        id: '${json['id']}',
        name: '${json['name'] ?? json['id']}',
        allowed: json['allowed'] as bool?,
        lastUsed: (json['lastUsed'] as num?)?.toInt(),
        trusted: json['trusted'] as bool?,
      );

  String id;
  String name;

  /// True or null: the extension may use the account; false: it may not.
  bool? allowed;
  int? lastUsed;

  /// From product.json's `trustedExtensionAuthAccess`.
  bool? trusted;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'allowed': ?allowed,
    'lastUsed': ?lastUsed,
    'trusted': ?trusted,
  };
}

/// `IAuthenticationProvider`: a provider registered with the service (an
/// extension's, through the extension host).
abstract interface class AuthenticationProvider {
  String get id;
  String get label;
  bool get supportsMultipleAccounts;
  List<VsUri> get authorizationServers;
  VsUri? get resourceServer;

  /// Whether [getSessionsFromChallenges] and [createSessionFromChallenges]
  /// are supported.
  bool get supportsChallenges;

  Stream<AuthSessionsChangeEvent> get onDidChangeSessions;

  /// A custom consent message (`confirmation`); null for the default.
  String? confirmation(String extensionName, bool recreatingSession);

  Future<List<AuthSession>> getSessions(
    List<String>? scopes,
    Map<String, Object?> options,
  );
  Future<AuthSession> createSession(
    List<String> scopes,
    Map<String, Object?> options,
  );
  Future<void> removeSession(String sessionId);
  Future<List<AuthSession>> getSessionsFromChallenges(
    Map<String, Object?> constraint,
    Map<String, Object?> options,
  );
  Future<AuthSession> createSessionFromChallenges(
    Map<String, Object?> constraint,
    Map<String, Object?> options,
  );

  void dispose();
}

/// An error whose message is what the extension sees (upstream's
/// `new Error(message)`).
final class AuthenticationError implements Exception {
  const AuthenticationError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// `isAuthenticationWwwAuthenticateRequest`: `{wwwAuthenticate, fallbackScopes?}`.
bool isWwwAuthenticateRequest(Object? value) =>
    value is Map && value['wwwAuthenticate'] is String;

/// The scopes of a scope list or a WWW-Authenticate request's fallback.
List<String>? scopesOf(Object? scopeListOrRequest) =>
    switch (scopeListOrRequest) {
      final List<Object?> list => [for (final s in list) '$s'],
      final Map<Object?, Object?> request => switch (request['fallbackScopes']) {
        final List<Object?> list => [for (final s in list) '$s'],
        _ => null,
      },
      _ => null,
    };

/// `scopesMatch`: the same scopes in any order.
bool scopesMatch(List<String>? scopes1, List<String>? scopes2) {
  if (identical(scopes1, scopes2)) return true;
  if (scopes1 == null || scopes2 == null) return false;
  if (scopes1.length != scopes2.length) return false;
  final a = [...scopes1]..sort();
  final b = [...scopes2]..sort();
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// `parseWWWAuthenticateHeader`: the challenges (`{scheme, params}`) of a
/// WWW-Authenticate header.
List<Map<String, Object?>> parseWwwAuthenticateHeader(String header) {
  final challenges = <Map<String, Object?>>[];
  final tokens = <String>[];
  var current = StringBuffer();
  var inQuotes = false;
  for (final char in header.split('')) {
    if (char == '"') {
      inQuotes = !inQuotes;
      current.write(char);
    } else if (char == ',' && !inQuotes) {
      if (current.toString().trim().isNotEmpty) {
        tokens.add(current.toString().trim());
      }
      current = StringBuffer();
    } else {
      current.write(char);
    }
  }
  if (current.toString().trim().isNotEmpty) {
    tokens.add(current.toString().trim());
  }

  String unquote(String value) =>
      value.replaceFirst(RegExp(r'^"'), '').replaceFirst(RegExp(r'"$'), '');

  ({String scheme, Map<String, String> params})? challenge;
  void push() {
    final c = challenge;
    if (c != null) challenges.add({'scheme': c.scheme, 'params': c.params});
  }

  for (final token in tokens) {
    if (!token.contains('=')) {
      push();
      challenge = (scheme: token.trim(), params: {});
      continue;
    }
    final spaceIndex = token.indexOf(' ');
    if (spaceIndex > 0) {
      final beforeSpace = token.substring(0, spaceIndex);
      final afterSpace = token.substring(spaceIndex + 1);
      if (!beforeSpace.contains('=') && afterSpace.contains('=')) {
        push();
        challenge = (scheme: beforeSpace.trim(), params: {});
        final equalIndex = afterSpace.indexOf('=');
        if (equalIndex > 0) {
          final key = afterSpace.substring(0, equalIndex).trim();
          final value = unquote(afterSpace.substring(equalIndex + 1).trim());
          if (key.isNotEmpty) challenge.params[key] = value;
        }
        continue;
      }
    }
    final c = challenge;
    if (c != null) {
      final equalIndex = token.indexOf('=');
      if (equalIndex > 0) {
        final key = token.substring(0, equalIndex).trim();
        final value = unquote(token.substring(equalIndex + 1).trim());
        if (key.isNotEmpty) c.params[key] = value;
      }
    }
  }
  push();
  return challenges;
}

/// `isAuthorizationTokenResponse`.
bool isAuthorizationTokenResponse(Object? value) =>
    value is Map &&
    value['access_token'] != null &&
    value['token_type'] != null;

/// `getDynamicAuthenticationProviderId`.
String dynamicAuthenticationProviderId(
  VsUri authorizationServer,
  Map<String, Object?>? resource,
) => resource != null
    ? '${authorizationServer.toString(skipEncoding: true)} ${resource['resource']}'
    : authorizationServer.toString(skipEncoding: true);

/// Strips VS Code's mnemonic marks (`&&Allow` → `Allow`).
String withoutMnemonic(String label) => label.replaceAll('&&', '');

/// Completes with [future]'s value, or null after [timeout]
/// (`raceTimeout`).
Future<T?> raceTimeout<T>(Future<T> future, Duration timeout) {
  final completer = Completer<T?>();
  final timer = Timer(timeout, () {
    if (!completer.isCompleted) completer.complete(null);
  });
  future.then(
    (value) {
      timer.cancel();
      if (!completer.isCompleted) completer.complete(value);
    },
    onError: (Object error, StackTrace stack) {
      timer.cancel();
      if (!completer.isCompleted) completer.completeError(error, stack);
    },
  );
  return completer.future;
}
