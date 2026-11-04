import 'dart:convert';

import 'codex_oauth.dart';
import 'codex_service.dart';

/// The same sign-in, whether exported by Codex CLI, CLIProxyAPI or Sub2API.
/// Claims from a file describe an account, not proof that its tokens work.
class CodexCredential {
  const CodexCredential({
    required this.refreshToken,
    required this.identity,
    this.accessToken,
    this.expiresAt,
  });

  final String refreshToken;
  final String? accessToken;
  final DateTime? expiresAt;
  final CodexIdentity identity;
}

/// A file's entry, including entries of another vendor or with missing tokens.
class CodexCredentialEntry {
  const CodexCredentialEntry.valid(CodexCredential this.credential)
    : error = null;
  const CodexCredentialEntry.invalid(String this.error) : credential = null;

  final CodexCredential? credential;
  final String? error;
}

/// Reads one object, an array, or Sub2API's accounts envelope. Errors never
/// include JSON or token values. No request is made and no source is changed.
List<CodexCredentialEntry> parseCodexCredentials(String contents) {
  if (contents.length > 4 * 1024 * 1024) {
    throw const CodexException('The credential file is too large.');
  }
  var text = contents.trim();
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xfeff) {
    text = text.substring(1).trim();
  }
  Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    throw const CodexException('The credential file is not valid JSON.');
  }
  final entries = switch (json) {
    {'accounts': final List accounts} => accounts,
    final List accounts => accounts,
    final Map account when !account.containsKey('accounts') => [account],
    _ => throw const CodexException(
      'Expected an account or an accounts array.',
    ),
  };
  if (entries.isEmpty || entries.length > 100) {
    throw const CodexException('Import between 1 and 100 accounts at a time.');
  }
  return [for (final entry in entries) _entry(entry)];
}

CodexCredentialEntry _entry(Object? value) {
  try {
    return CodexCredentialEntry.valid(_credential(value));
  } on CodexException catch (error) {
    return CodexCredentialEntry.invalid(error.message);
  }
}

String? _read(Map map, String key, [String? alias]) {
  for (final name in [key, ?alias]) {
    if (map[name] case final String text when text.trim().isNotEmpty) {
      return text.trim();
    }
  }
  return null;
}

CodexCredential _credential(Object? value) {
  if (value is! Map) {
    throw const CodexException('Not an account object.');
  }
  final Map source;
  String? email = _read(value, 'email');
  String? workspace;
  if (value['credentials'] case final Map credentials) {
    if (_read(value, 'platform')?.toLowerCase() != 'openai') {
      throw const CodexException('Not a ChatGPT account.');
    }
    if (_read(value, 'type')?.toLowerCase() != 'oauth') {
      throw const CodexException(
        'Not an OAuth sign-in; add API keys as an upstream instead.',
      );
    }
    source = credentials;
    email = _read(source, 'email') ?? email;
    final name = _read(value, 'name');
    if (email == null && name != null && name.contains('@')) email = name;
    workspace = _read(source, 'chatgpt_account_id', 'account_id');
  } else {
    final type = _read(value, 'type')?.toLowerCase();
    final mode = _read(value, 'auth_mode');
    if ((type != null && type != 'codex') ||
        (mode != null && mode != 'chatgpt') ||
        value.containsKey('claudeAiOauth')) {
      throw const CodexException('Not a ChatGPT OAuth sign-in.');
    }
    source = switch (value['tokens']) {
      final Map tokens => tokens,
      null => value,
      _ => throw const CodexException('Invalid tokens object.'),
    };
    workspace = _read(source, 'account_id', 'accountId');
  }
  final refresh = _read(source, 'refresh_token', 'refreshToken');
  if (refresh == null) {
    if (_read(value, 'OPENAI_API_KEY') != null ||
        _read(source, 'api_key', 'apiKey') != null) {
      throw const CodexException('An API key is not a ChatGPT sign-in.');
    }
    throw const CodexException(
      'No refresh token; sign in to this account instead.',
    );
  }
  final access = _read(source, 'access_token', 'accessToken');
  final idToken = _read(source, 'id_token', 'idToken');
  final fromId = CodexIdentity.fromIdToken(idToken);
  final fromAccess = CodexIdentity.fromIdToken(access);
  if ((workspace != null &&
          ((fromId.accountId != null && fromId.accountId != workspace) ||
              (fromAccess.accountId != null &&
                  fromAccess.accountId != workspace))) ||
      (fromId.accountId != null &&
          fromAccess.accountId != null &&
          fromId.accountId != fromAccess.accountId) ||
      (fromId.userId != null &&
          fromAccess.userId != null &&
          fromId.userId != fromAccess.userId)) {
    throw const CodexException('The tokens describe different accounts.');
  }
  final identity = CodexIdentity(
    email: fromId.email ?? fromAccess.email ?? email,
    userId: fromId.userId ?? fromAccess.userId,
    accountId: workspace ?? fromId.accountId ?? fromAccess.accountId,
    plan: fromId.plan ?? fromAccess.plan,
  );
  if ((identity.userId ?? identity.email) == null ||
      identity.accountId == null) {
    throw const CodexException(
      'Missing account identity or workspace; sign in instead.',
    );
  }
  final claims = access == null ? null : jwtClaims(access);
  return CodexCredential(
    refreshToken: refresh,
    accessToken: access,
    // When the access token is out; none, nothing to use until renewed.
    expiresAt: access == null
        ? null
        : _epoch(claims?['exp']) ??
              _epoch(source['expires_at']) ??
              DateTime.tryParse(_read(source, 'expired') ?? ''),
    identity: identity,
  );
}

DateTime? _epoch(Object? value) {
  final number = switch (value) {
    final num n => n,
    final String s => num.tryParse(s),
    _ => null,
  };
  if (number == null || !number.isFinite || number <= 0) return null;
  final milliseconds = number < 1000000000000 ? number * 1000 : number;
  if (milliseconds > 8640000000000000) return null;
  return DateTime.fromMillisecondsSinceEpoch(milliseconds.toInt(), isUtc: true);
}
