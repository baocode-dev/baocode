// The user's accounts on forges (GitHub, GitLab; theirs, or a company's
// own): signed in from the browser (OAuth's device flow, no secret on
// this machine but the token) or with a token they made. The tokens are
// kept in the system's keychain (SecretStore), the rest in the app's
// global storage. Nothing is written to a forge but what the user
// confirms (docs/stash.md).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/secret_store.dart';
import 'forge_api.dart';
import 'forge_ref.dart';

/// BaoCode's OAuth apps' ids (public: a device flow needs no secret). Empty
/// until they are registered: only tokens can be used then.
const githubClientId = '';
const gitlabClientId = '';

/// What the device flow asks for: GitHub's `repo` (issues and pull
/// requests, private ones too, to read and comment), GitLab's `api`.
const _githubScopes = 'repo read:user';
const _gitlabScopes = 'api';

/// Where the accounts are kept in the app's global storage (their
/// tokens are in the keychain).
const forgeAccountsKey = 'forge.accounts';

enum ForgeSignIn {
  /// From the browser, with a code.
  browser,

  /// With a token the user made.
  token,
}

/// An account, signed in.
@immutable
class ForgeAccount {
  const ForgeAccount({
    required this.kind,
    required this.host,
    required this.login,
    this.name,
    this.via = ForgeSignIn.token,
  });

  final ForgeKind kind;
  final String host;
  final String login;
  final String? name;
  final ForgeSignIn via;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'host': host,
    'login': login,
    'name': ?name,
    'via': via.name,
  };

  static ForgeAccount? fromJson(Object? json) => switch (json) {
    {'host': final String host, 'login': final String login} =>
      switch (ForgeKind.parse(json['kind'])) {
        final kind? => ForgeAccount(
          kind: kind,
          host: host,
          login: login,
          name: json['name'] as String?,
          via: ForgeSignIn.values.byName(
            json['via'] == 'browser' ? 'browser' : 'token',
          ),
        ),
        null => null,
      },
    _ => null,
  };
}

/// A device flow under way: the code the user enters at [verificationUrl].
@immutable
class ForgeDeviceCode {
  const ForgeDeviceCode({
    required this.kind,
    required this.host,
    required this.userCode,
    required this.verificationUrl,
    required this.deviceCode,
    required this.interval,
    required this.expiresAt,
  });

  final ForgeKind kind;
  final String host;
  final String userCode;
  final Uri verificationUrl;
  final String deviceCode;
  final Duration interval;
  final DateTime expiresAt;
}

/// A token, and what renews it (GitLab's last two hours).
@immutable
class _Token {
  const _Token(this.access, {this.refresh, this.expiresAt});

  final String access;
  final String? refresh;
  final DateTime? expiresAt;

  String encode() => jsonEncode({
    'access': access,
    'refresh': ?refresh,
    'expiresAt': ?expiresAt?.toIso8601String(),
  });

  static _Token? decode(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      return switch (jsonDecode(text)) {
        {'access': final String access} && final Map json => _Token(
          access,
          refresh: json['refresh'] as String?,
          expiresAt: switch (json['expiresAt']) {
            final String at => DateTime.tryParse(at),
            _ => null,
          },
        ),
        _ => _Token(text),
      };
    } on FormatException {
      // A bare token, as one pasted.
      return _Token(text);
    }
  }

  static _Token fromOAuth(Map json, DateTime now) => _Token(
    json['access_token'] as String,
    refresh: json['refresh_token'] as String?,
    expiresAt: switch (json['expires_in']) {
      final num seconds => now.add(Duration(seconds: seconds.toInt())),
      _ => null,
    },
  );
}

/// The user's forge accounts, one a host; what asks a forge goes through
/// [apiFor].
class ForgeAccounts extends ChangeNotifier {
  ForgeAccounts({
    required this.http,
    SecretStore? secrets,
    this.read,
    this.write,
    DateTime Function()? clock,
    this.githubClient = githubClientId,
    this.gitlabClient = gitlabClientId,
  }) : _secrets = secrets ?? SecretStore.instance,
       _clock = clock ?? DateTime.now {
    for (final json in switch (read?.call()) {
      final List<Object?> list => list,
      _ => const <Object?>[],
    }) {
      if (ForgeAccount.fromJson(json) case final account?) {
        _accounts[account.host] = account;
      }
    }
  }

  /// The app's, once main() has made it.
  static ForgeAccounts? current;

  final ForgeHttp http;
  final SecretStore _secrets;
  final DateTime Function() _clock;

  /// The accounts as kept (a JSON list), and keeping them; not kept
  /// without.
  final Object? Function()? read;
  final Future<void> Function(Object? json)? write;

  final String githubClient;
  final String gitlabClient;

  final Map<String, ForgeAccount> _accounts = {};

  /// The token of each host as the keychain answered it, kept: what arrives
  /// while a read is under way waits for that same read, and none reads the
  /// keychain twice for an answer it has. A read on Windows runs a program
  /// (PowerShell, DPAPI), and the app asks for a token once per request (see
  /// the stash's refresh, which asks every linked issue at once): one program
  /// for each of them was the hang.
  final Map<String, Future<String?>> _tokens = {};

  /// Each host's refresh under way (GitLab's): the requests that find the
  /// token expired as it goes wait for it, not refresh it again. A refresh
  /// token is good for one refresh only, so a second would be refused (and
  /// would write the keychain once more).
  final Map<String, Future<_Token>> _refreshing = {};

  List<ForgeAccount> get accounts => List.unmodifiable(_accounts.values);

  ForgeAccount? accountFor(String host) => _accounts[host.toLowerCase()];

  /// What [host] is: its account's forge, else github.com's or gitlab.com's.
  ForgeKind? kindOf(String host) =>
      _accounts[host.toLowerCase()]?.kind ?? publicForgeKind(host);

  /// Whether signing in from the browser works for [kind] on [host]: on
  /// its public service, with BaoCode's app registered.
  bool canSignInFromBrowser(ForgeKind kind, String host) =>
      host == kind.publicHost &&
      switch (kind) {
        ForgeKind.github => githubClient.isNotEmpty,
        ForgeKind.gitlab => gitlabClient.isNotEmpty,
      };

  static String _secretId(String host) => 'forge.$host';

  /// The API of [host], signed in; null without an account there.
  ForgeApi? apiFor(String host) {
    final account = accountFor(host);
    if (account == null) return null;
    Future<String> token() => _accessToken(account);
    return switch (account.kind) {
      ForgeKind.github => GitHubApi(
        host: account.host,
        http: http,
        token: token,
      ),
      ForgeKind.gitlab => GitLabApi(
        host: account.host,
        http: http,
        token: token,
      ),
    };
  }

  /// [ref]'s API: its host's, signed in; null without an account there.
  ForgeApi? apiOf(ForgeRef ref) => apiFor(ref.repo.host);

  Future<String> _accessToken(ForgeAccount account) async {
    final read = _tokenOf(account.host);
    final _Token? token;
    try {
      token = _Token.decode(await read);
    } on Object {
      // Answered, not kept: the keychain may read it the next time. Until
      // that read answers them all, none of the requests that arrive starts
      // one of its own (one program for each was the hang).
      if (identical(_tokens[account.host], read)) _tokens.remove(account.host);
      rethrow;
    }
    if (token == null) {
      throw const ForgeException('Not signed in.', status: 401);
    }
    final expires = token.expiresAt;
    final refresh = token.refresh;
    if (expires == null ||
        refresh == null ||
        _clock().isBefore(expires.subtract(const Duration(minutes: 2)))) {
      return token.access;
    }
    final host = account.host;
    if (_refreshing[host] case final refreshing?) {
      return (await refreshing).access;
    }
    late final Future<_Token> refreshing;
    refreshing = _refresh(account, refresh).whenComplete(() {
      if (identical(_refreshing[host], refreshing)) _refreshing.remove(host);
    });
    _refreshing[host] = refreshing;
    return (await refreshing).access;
  }

  /// [host]'s token as the keychain has it, read once: the requests that
  /// arrive while it is under way wait on that same read.
  Future<String?> _tokenOf(String host) =>
      _tokens[host] ??= _secrets.read(_secretId(host));

  /// A new token for [refresh] (GitLab's): kept in place of the old one.
  Future<_Token> _refresh(ForgeAccount account, String refresh) async {
    final response = await http.send(
      'POST',
      Uri.https(account.host, '/oauth/token'),
      headers: const {'Accept': 'application/json'},
      form: {
        'grant_type': 'refresh_token',
        'refresh_token': refresh,
        'client_id': gitlabClient,
      },
    );
    final json = response.ok ? response.json : null;
    if (json is! Map || json['access_token'] is! String) {
      throw const ForgeException('The sign-in expired.', status: 401);
    }
    final token = _Token.fromOAuth(json, _clock());
    await _secrets.write(_secretId(account.host), token.encode());
    _tokens.remove(account.host);
    return token;
  }

  /// Signs in to [host] (a [kind] forge) with [token]: asks who it is of,
  /// and keeps it. Throws [ForgeException] when it is not taken.
  Future<ForgeAccount> signInWithToken(
    ForgeKind kind,
    String host,
    String token,
  ) => _signIn(kind, _hostOf(host), _Token(token.trim()), ForgeSignIn.token);

  Future<ForgeAccount> _signIn(
    ForgeKind kind,
    String host,
    _Token token,
    ForgeSignIn via,
  ) async {
    Future<String> access() async => token.access;
    final api = switch (kind) {
      ForgeKind.github => GitHubApi(host: host, http: http, token: access),
      ForgeKind.gitlab => GitLabApi(host: host, http: http, token: access),
    };
    final me = await api.me();
    await _secrets.write(_secretId(host), token.encode());
    _tokens.remove(host);
    _refreshing.remove(host);
    final account = ForgeAccount(
      kind: kind,
      host: host,
      login: me.login,
      name: me.name,
      via: via,
    );
    _accounts[host] = account;
    await _keep();
    notifyListeners();
    return account;
  }

  /// Signs out of [host]: its token deleted from this machine (the user is
  /// told to revoke it on the forge too).
  Future<void> signOut(String host) async {
    host = _hostOf(host);
    if (_accounts.remove(host) == null) return;
    await _secrets.delete(_secretId(host));
    _tokens.remove(host);
    _refreshing.remove(host);
    await _keep();
    notifyListeners();
  }

  Future<void> _keep() async =>
      write?.call([for (final account in _accounts.values) account.toJson()]);

  /// A host as typed (`https://gitlab.example.com/`), bare.
  static String _hostOf(String typed) {
    final text = typed.trim();
    final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
    return (uri?.host.isNotEmpty ?? false ? uri!.host : text).toLowerCase();
  }

  // --- Signing in from the browser ---------------------------------------------

  /// Starts signing in to [kind]'s public service from the browser: the
  /// code the user enters there. Throws [ForgeException].
  Future<ForgeDeviceCode> startDeviceFlow(ForgeKind kind) async {
    final host = kind.publicHost;
    final response = await http.send(
      'POST',
      switch (kind) {
        ForgeKind.github => Uri.https(host, '/login/device/code'),
        ForgeKind.gitlab => Uri.https(host, '/oauth/authorize_device'),
      },
      headers: const {'Accept': 'application/json'},
      form: {
        'client_id': switch (kind) {
          ForgeKind.github => githubClient,
          ForgeKind.gitlab => gitlabClient,
        },
        'scope': switch (kind) {
          ForgeKind.github => _githubScopes,
          ForgeKind.gitlab => _gitlabScopes,
        },
      },
    );
    final json = response.ok ? response.json : null;
    if (json is! Map || json['device_code'] is! String) {
      throw ForgeException(
        forgeErrorMessage(response) ?? 'HTTP ${response.status}',
        status: response.status,
      );
    }
    final url =
        (json['verification_uri_complete'] ?? json['verification_uri'])
            as String;
    return ForgeDeviceCode(
      kind: kind,
      host: host,
      userCode: json['user_code'] as String,
      verificationUrl: Uri.parse(url),
      deviceCode: json['device_code'] as String,
      interval: Duration(seconds: (json['interval'] as num?)?.toInt() ?? 5),
      expiresAt: _clock().add(
        Duration(seconds: (json['expires_in'] as num?)?.toInt() ?? 900),
      ),
    );
  }

  /// Waits for the user to enter [code] (asking every [ForgeDeviceCode.
  /// interval], longer when told to slow down), then signs in with the
  /// token it gives. Throws [ForgeException] when it is refused or
  /// expires; stops when [cancelled] says.
  Future<ForgeAccount> finishDeviceFlow(
    ForgeDeviceCode code, {
    bool Function()? cancelled,
    Future<void> Function(Duration)? wait,
  }) async {
    final sleep = wait ?? (duration) => Future<void>.delayed(duration);
    var interval = code.interval;
    while (true) {
      if (cancelled?.call() ?? false) {
        throw const ForgeException('Cancelled.');
      }
      if (_clock().isAfter(code.expiresAt)) {
        throw const ForgeException('The code expired.');
      }
      await sleep(interval);
      if (cancelled?.call() ?? false) {
        throw const ForgeException('Cancelled.');
      }
      final response = await http.send(
        'POST',
        switch (code.kind) {
          ForgeKind.github => Uri.https(code.host, '/login/oauth/access_token'),
          ForgeKind.gitlab => Uri.https(code.host, '/oauth/token'),
        },
        headers: const {'Accept': 'application/json'},
        form: {
          'client_id': switch (code.kind) {
            ForgeKind.github => githubClient,
            ForgeKind.gitlab => gitlabClient,
          },
          'device_code': code.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      );
      final json = response.json;
      if (json is! Map) {
        throw ForgeException(
          'HTTP ${response.status}',
          status: response.status,
        );
      }
      if (json['access_token'] is String) {
        return _signIn(
          code.kind,
          code.host,
          _Token.fromOAuth(json, _clock()),
          ForgeSignIn.browser,
        );
      }
      switch (json['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += const Duration(seconds: 5);
        case final String error:
          throw ForgeException(
            json['error_description'] as String? ?? error,
            status: response.status,
          );
        default:
          throw ForgeException(
            'HTTP ${response.status}',
            status: response.status,
          );
      }
    }
  }
}
