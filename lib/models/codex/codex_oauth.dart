/// Signing in to ChatGPT as the Codex CLI does: OAuth with PKCE, back to
/// this machine; the tokens it gives, and who they are of.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'codex_api.dart';

/// PKCE's pair: the verifier kept here, its challenge sent.
class CodexPkce {
  const CodexPkce(this.verifier, this.challenge);

  /// 96 random bytes, as the Codex CLI's.
  factory CodexPkce.generate([Random? random]) {
    final source = random ?? Random.secure();
    final verifier = _base64Url([
      for (var i = 0; i < 96; i++) source.nextInt(256),
    ]);
    return CodexPkce(verifier, challengeOf(verifier));
  }

  final String verifier;
  final String challenge;

  /// S256's.
  static String challengeOf(String verifier) =>
      _base64Url(sha256.convert(ascii.encode(verifier)).bytes);
}

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// A random `state`, to know the sign-in that comes back is this one.
String codexState([Random? random]) {
  final source = random ?? Random.secure();
  return [
    for (var i = 0; i < 32; i++)
      source.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// Where the browser signs in.
Uri codexAuthorizeUrl(
  CodexEndpoints endpoints, {
  required String state,
  required String challenge,
}) => endpoints.authorize.replace(
  queryParameters: {
    'client_id': codexClientId,
    'response_type': 'code',
    'redirect_uri': endpoints.redirectUri,
    'scope': 'openid email profile offline_access',
    'state': state,
    'code_challenge': challenge,
    'code_challenge_method': 'S256',
    'prompt': 'login',
    'id_token_add_organizations': 'true',
    'codex_cli_simplified_flow': 'true',
  },
);

/// The form a code is exchanged with.
Map<String, String> codexCodeForm(
  CodexEndpoints endpoints, {
  required String code,
  required String verifier,
}) => {
  'grant_type': 'authorization_code',
  'client_id': codexClientId,
  'code': code,
  'redirect_uri': endpoints.redirectUri,
  'code_verifier': verifier,
};

/// The form a refresh token is exchanged with.
Map<String, String> codexRefreshForm(String refreshToken) => {
  'client_id': codexClientId,
  'grant_type': 'refresh_token',
  'refresh_token': refreshToken,
  'scope': 'openid profile email',
};

/// What the token endpoint gives.
class CodexTokens {
  const CodexTokens({
    required this.access,
    required this.expiresAt,
    this.refresh,
    this.idToken,
  });

  final String access;

  /// A new one each refresh: the one before it no longer works.
  final String? refresh;
  final String? idToken;
  final DateTime expiresAt;

  /// Null when [json] has no access token.
  static CodexTokens? fromJson(Object? json, DateTime now) {
    if (json is! Map) return null;
    final access = json['access_token'];
    if (access is! String || access.isEmpty) return null;
    String? read(String key) => switch (json[key]) {
      final String value when value.isNotEmpty => value,
      _ => null,
    };
    final idToken = read('id_token');
    final expiresIn = switch (json['expires_in']) {
      final num seconds when seconds > 0 => seconds.toInt(),
      _ => null,
    };
    return CodexTokens(
      access: access,
      refresh: read('refresh_token'),
      idToken: idToken,
      expiresAt:
          (expiresIn == null ? null : now.add(Duration(seconds: expiresIn))) ??
          jwtExpiry(access) ??
          now.add(const Duration(hours: 1)),
    );
  }
}

/// Who an ID token is of, and in which ChatGPT workspace.
class CodexIdentity {
  const CodexIdentity({this.email, this.accountId, this.userId, this.plan});

  final String? email;

  /// The workspace (`chatgpt_account_id`), sent with each request.
  final String? accountId;
  final String? userId;

  /// `free`, `plus`, `pro`, `team`…
  final String? plan;

  static CodexIdentity fromIdToken(String? idToken) {
    final claims = idToken == null ? null : jwtClaims(idToken);
    if (claims == null) return const CodexIdentity();
    final auth = switch (claims['https://api.openai.com/auth']) {
      final Map auth => auth,
      _ => const {},
    };
    String? read(Map map, String key) => switch (map[key]) {
      final String value when value.trim().isNotEmpty => value.trim(),
      _ => null,
    };
    return CodexIdentity(
      email: read(claims, 'email'),
      accountId: read(auth, 'chatgpt_account_id'),
      userId: read(auth, 'chatgpt_user_id') ?? read(auth, 'user_id'),
      plan: read(auth, 'chatgpt_plan_type'),
    );
  }

  /// An account's own id, from who signed in to which workspace: signing
  /// in again finds the same.
  String get key {
    final who = userId ?? email ?? '';
    final digest = sha256.convert(utf8.encode('$who|${accountId ?? ''}'));
    return '$digest'.substring(0, 12);
  }
}

/// A JWT's claims, unverified (it came from the token endpoint, over TLS).
Map<String, Object?>? jwtClaims(String jwt) {
  final parts = jwt.split('.');
  if (parts.length < 2) return null;
  try {
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    return switch (jsonDecode(payload)) {
      final Map<String, Object?> claims => claims,
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

/// When a JWT expires (`exp`).
DateTime? jwtExpiry(String jwt) => switch (jwtClaims(jwt)?['exp']) {
  final num exp => DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000),
  _ => null,
};
