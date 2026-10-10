import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../model_provider.dart';
import '../model_providers.dart';
import '../model_runtime.dart' show UpstreamException;
import '../secret_store.dart';
import '../upstream.dart';
import 'codex_api.dart';
import 'codex_balancer.dart';
import 'codex_oauth.dart';
import 'codex_service.dart';
import 'codex_usage.dart';

/// The ChatGPT (Codex) providers' accounts while the app runs: signing in
/// to them, their access tokens (in memory; refreshed from the refresh
/// token kept in the keychain), how much of their quota is used, and
/// which takes a request ([CodexBalancer]).
class CodexAccounts extends CodexService {
  CodexAccounts({
    required this._providers,
    this.endpoints = const CodexEndpoints(),
    this._findProxy,
    this._openBrowser,
    DateTime Function()? now,
    this.loginTimeout = const Duration(minutes: 10),
  }) : _now = now ?? DateTime.now;

  final ModelProviders Function() _providers;
  final CodexEndpoints endpoints;
  final String Function(Uri url)? _findProxy;
  final Future<bool> Function(String url)? _openBrowser;
  final DateTime Function() _now;
  final Duration loginTimeout;

  final CodexBalancer _balancer = CodexBalancer();
  final Map<String, ({String access, DateTime expiresAt})> _tokens = {};
  final Map<String, Future<String>> _refreshing = {};
  final Map<String, CodexUsage> _usage = {};
  final Map<String, String> _errors = {};
  final Map<String, DateTime> _limited = {};

  /// Those whose refresh token no longer works: until signed in again.
  final Set<String> _signedOut = {};

  HttpClient? _client;

  static String _key(String providerId, String accountId) =>
      '$providerId/$accountId';

  HttpClient get _http => _client ??= HttpClient()
    ..connectionTimeout = const Duration(seconds: 30)
    ..idleTimeout = const Duration(seconds: 30)
    ..findProxy = _findProxy ?? (_) => 'DIRECT';

  void close() {
    _client?.close(force: true);
    _client = null;
  }

  // --- What is known ---------------------------------------------------------

  @override
  CodexUsage? usage(String providerId, String accountId) =>
      _usage[_key(providerId, accountId)];

  @override
  String? error(String providerId, String accountId) =>
      _errors[_key(providerId, accountId)];

  @override
  DateTime? limitedUntil(String providerId, String accountId) {
    final key = _key(providerId, accountId);
    final now = _now();
    final until = [?_limited[key], ?_usage[key]?.limitedUntil]
        .where((time) => time.isAfter(now))
        .fold<DateTime?>(
          null,
          (latest, time) =>
              latest == null || time.isAfter(latest) ? time : latest,
        );
    return until;
  }

  /// Whether account [accountId] is signed out: to be signed in again.
  bool signedOut(String providerId, String accountId) =>
      _signedOut.contains(_key(providerId, accountId));

  // --- Which account ---------------------------------------------------------

  /// [provider]'s accounts that can take a request now, but [exclude].
  List<ProviderAccount> available(
    ModelProvider provider, {
    Set<String> exclude = const {},
  }) => [
    for (final account in provider.accounts)
      if (account.enabled &&
          !exclude.contains(account.id) &&
          !signedOut(provider.id, account.id) &&
          limitedUntil(provider.id, account.id) == null)
        account,
  ];

  /// The account [session]'s request goes to, by [provider]'s balance;
  /// null when none can take it.
  ProviderAccount? pick(
    ModelProvider provider, {
    String? session,
    Set<String> exclude = const {},
  }) => _balancer.pick(
    provider.id,
    available(provider, exclude: exclude),
    provider.balance,
    session: session,
    used: (account) => usage(provider.id, account.id)?.mostUsed,
  );

  /// Account [account] out of quota until [until].
  void markLimited(
    ModelProvider provider,
    ProviderAccount account,
    DateTime until,
  ) {
    _limited[_key(provider.id, account.id)] = until;
    _balancer.forget(provider.id, account.id);
    notifyListeners();
  }

  /// What went wrong with [account]; null as it works again.
  void markError(ModelProvider provider, ProviderAccount account, String? e) {
    final key = _key(provider.id, account.id);
    if (_errors[key] == e) return;
    if (e == null) {
      _errors.remove(key);
    } else {
      _errors[key] = e;
    }
    notifyListeners();
  }

  /// What a reply's headers tell of [account]'s quota.
  void record(
    ModelProvider provider,
    ProviderAccount account,
    String? Function(String name) header,
  ) {
    final key = _key(provider.id, account.id);
    final usage = CodexUsage.fromHeaders(header, _now(), previous: _usage[key]);
    if (usage == null) return;
    _usage[key] = usage;
    notifyListeners();
  }

  // --- Tokens ----------------------------------------------------------------

  /// [account]'s access token: refreshed when about to expire, or when
  /// [rejected] (the one the backend refused) is still the one held. One
  /// refresh at a time: each gives a new refresh token, the old one void.
  /// Throws [CodexException].
  Future<String> accessToken(
    ModelProvider provider,
    ProviderAccount account, {
    String? rejected,
  }) async {
    final key = _key(provider.id, account.id);
    final held = _tokens[key];
    if (held != null &&
        held.access != rejected &&
        held.expiresAt.isAfter(_now().add(const Duration(minutes: 1)))) {
      return held.access;
    }
    if (_refreshing[key] case final running?) return running;
    // Not `=> remove(key)`: that is this future, which would wait on itself.
    final refresh = _refresh(provider.id, account).whenComplete(() {
      _refreshing.remove(key);
    });
    _refreshing[key] = refresh;
    return refresh;
  }

  Future<String> _refresh(String providerId, ProviderAccount account) async {
    final key = _key(providerId, account.id);
    final ref = ModelProvider.accountRefFor(providerId, account.id);
    final secrets = _providers().secrets;
    String? refreshToken;
    try {
      refreshToken = await secrets.read(ref);
    } on SecretStoreException catch (error) {
      throw _fail(key, 'The token could not be read: $error');
    }
    if (refreshToken == null || refreshToken.isEmpty) {
      throw _fail(key, 'Signed out: sign in again.', signedOut: true);
    }
    final (status, text) = await _postForm(
      endpoints.token,
      codexRefreshForm(refreshToken),
    );
    if (status >= 400) {
      final message = upstreamErrorMessage(status, text);
      // The refresh token refused (used, expired, revoked): only signing
      // in again helps.
      final refused = status == 400 || status == 401 || status == 403;
      throw _fail(
        key,
        refused
            ? 'Signed out ($message): sign in again.'
            : 'The token could not be refreshed: $message',
        signedOut: refused,
      );
    }
    final tokens = CodexTokens.fromJson(_decode(text), _now());
    if (tokens == null) {
      throw _fail(key, 'The token endpoint gave no access token.');
    }
    if (tokens.refresh case final rotated? when rotated != refreshToken) {
      try {
        await secrets.write(ref, rotated);
      } on SecretStoreException catch (error) {
        debugPrint('Refresh token of ${account.id} not kept: $error');
      }
    }
    _tokens[key] = (access: tokens.access, expiresAt: tokens.expiresAt);
    _signedOut.remove(key);
    if (_errors.remove(key) != null) notifyListeners();
    return tokens.access;
  }

  CodexException _fail(String key, String message, {bool signedOut = false}) {
    _errors[key] = message;
    if (signedOut) {
      _signedOut.add(key);
      _tokens.remove(key);
    }
    notifyListeners();
    return CodexException(message);
  }

  // --- Signing in ------------------------------------------------------------

  @override
  Future<CodexLogin> login(String providerId) async {
    final pkce = CodexPkce.generate();
    final state = codexState();
    final port = endpoints.callbackPort;
    final servers = <HttpServer>[];
    // The port is the one OpenAI has for this client: no other will do.
    // Another program on it (a proxy in Docker, the Codex CLI signing in),
    // the browser lands on it all the same, and its address is pasted.
    try {
      servers.add(await HttpServer.bind(InternetAddress.loopbackIPv4, port));
      // `localhost` may be ::1 first.
      try {
        servers.add(
          await HttpServer.bind(
            InternetAddress.loopbackIPv6,
            port,
            v6Only: true,
          ),
        );
      } on SocketException {
        // No IPv6 here.
      }
    } on SocketException {
      // Taken.
    }
    final url = codexAuthorizeUrl(
      endpoints,
      state: state,
      challenge: pkce.challenge,
    );
    final login = _Login(url, servers, state, loginTimeout);
    login._result = login._code.future.then(
      (code) => _signedIn(providerId, code, pkce.verifier),
    );
    if (_openBrowser case final open?) unawaited(open('$url'));
    return login;
  }

  Future<ProviderAccount> _signedIn(
    String providerId,
    String code,
    String verifier,
  ) async {
    final (status, text) = await _postForm(
      endpoints.token,
      codexCodeForm(endpoints, code: code, verifier: verifier),
    );
    if (status >= 400) {
      throw CodexException(
        'Sign-in failed: ${upstreamErrorMessage(status, text)}',
      );
    }
    final tokens = CodexTokens.fromJson(_decode(text), _now());
    final refreshToken = tokens?.refresh;
    if (tokens == null || refreshToken == null) {
      throw const CodexException('Sign-in gave no refresh token.');
    }
    final fromId = CodexIdentity.fromIdToken(tokens.idToken);
    final fromAccess = CodexIdentity.fromIdToken(tokens.access);
    final identity = CodexIdentity(
      email: fromId.email ?? fromAccess.email,
      accountId: fromId.accountId ?? fromAccess.accountId,
      userId: fromId.userId ?? fromAccess.userId,
      plan: fromId.plan ?? fromAccess.plan,
    );
    final providers = _providers();
    final provider = providers.provider(providerId);
    if (provider == null) {
      throw const CodexException('The provider was removed.');
    }
    final account = switch (provider.account(identity.key)) {
      final known? => known.copyWith(
        email: identity.email,
        plan: identity.plan,
        accountId: identity.accountId,
      ),
      null => ProviderAccount(
        id: identity.key,
        email: identity.email,
        plan: identity.plan,
        accountId: identity.accountId,
      ),
    };
    try {
      await providers.secrets.write(
        ModelProvider.accountRefFor(providerId, account.id),
        refreshToken,
      );
    } on SecretStoreException catch (error) {
      throw CodexException('The token could not be kept: $error');
    }
    final key = _key(providerId, account.id);
    _tokens[key] = (access: tokens.access, expiresAt: tokens.expiresAt);
    _signedOut.remove(key);
    _errors.remove(key);
    _limited.remove(key);
    await providers.save(
      (providers.provider(providerId) ?? provider).withAccount(account),
    );
    notifyListeners();
    unawaited(_fetchUsage(providerId, account));
    return account;
  }

  @override
  Future<void> removeAccount(String providerId, String accountId) async {
    final providers = _providers();
    if (providers.provider(providerId) case final provider?) {
      await providers.save(
        provider.copyWith(
          accounts: [
            for (final account in provider.accounts)
              if (account.id != accountId) account,
          ],
        ),
      );
    }
    try {
      await providers.secrets.delete(
        ModelProvider.accountRefFor(providerId, accountId),
      );
    } on SecretStoreException catch (error) {
      debugPrint('Token of $accountId not removed: $error');
    }
    final key = _key(providerId, accountId);
    _tokens.remove(key);
    _usage.remove(key);
    _errors.remove(key);
    _limited.remove(key);
    _signedOut.remove(key);
    _balancer.forget(providerId, accountId);
    notifyListeners();
  }

  // --- Quota and models ------------------------------------------------------

  @override
  Future<void> refreshUsage(ModelProvider provider) => Future.wait([
    for (final account in provider.accounts) _fetchUsage(provider.id, account),
  ]);

  Future<void> _fetchUsage(String providerId, ProviderAccount account) async {
    final key = _key(providerId, account.id);
    final provider = _providers().provider(providerId);
    if (provider == null) return;
    try {
      final (status, text) = await _get(provider, account, endpoints.usage);
      if (status >= 400) {
        _errors[key] = upstreamErrorMessage(status, text);
      } else {
        _usage[key] = CodexUsage.fromJson(_decode(text), _now());
        _errors.remove(key);
        if (_usage[key]?.limitReached == false) _limited.remove(key);
      }
    } on CodexException catch (error) {
      _errors[key] = error.message;
    } on Object catch (error) {
      _errors[key] = '$error';
    }
    notifyListeners();
  }

  /// The models [provider]'s backend lists, asked as one of its accounts.
  /// Throws [UpstreamException].
  Future<List<RemoteModel>> listModels(ModelProvider provider) async {
    final account = pick(provider);
    if (account == null) {
      throw UpstreamException(
        provider.accounts.isEmpty
            ? 'Sign in to a ChatGPT account first.'
            : 'No account can be used now.',
      );
    }
    try {
      final url = endpoints.models(codexVersionOf(provider));
      final (status, text) = await _get(provider, account, url);
      if (status >= 400) {
        throw UpstreamException(
          '${upstreamErrorMessage(status, text)} (GET $url)',
        );
      }
      return parseCodexModels(_decode(text));
    } on CodexException catch (error) {
      throw UpstreamException(error.message);
    } on SocketException catch (error) {
      throw UpstreamException('Could not connect: ${error.message}');
    } on TimeoutException {
      throw const UpstreamException('No answer in time.');
    }
  }

  /// GETs [url] as [account], its token refreshed once if refused.
  Future<(int, String)> _get(
    ModelProvider provider,
    ProviderAccount account,
    Uri url,
  ) async {
    String? rejected;
    for (var attempt = 0; ; attempt++) {
      final token = await accessToken(provider, account, rejected: rejected);
      final request = await _http.getUrl(url);
      codexHeaders(
        token,
        accountId: account.accountId,
        version: codexVersionOf(provider),
      ).forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final text = await utf8.decodeStream(response);
      if (response.statusCode == 401 && attempt == 0) {
        rejected = token;
        continue;
      }
      return (response.statusCode, text);
    }
  }

  Future<(int, String)> _postForm(Uri url, Map<String, String> form) async {
    try {
      final request = await _http.postUrl(url);
      request.headers
        ..contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        )
        ..set(HttpHeaders.acceptHeader, 'application/json');
      request.write(Uri(queryParameters: form).query);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      return (response.statusCode, await utf8.decodeStream(response));
    } on SocketException catch (error) {
      throw CodexException('Could not reach ${url.host}: ${error.message}');
    } on TimeoutException {
      throw CodexException('${url.host} did not answer in time.');
    } on HandshakeException catch (error) {
      throw CodexException('TLS failed: ${error.message}');
    }
  }

  static Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}

/// A sign-in waiting for the browser to come back to this machine.
class _Login implements CodexLogin {
  _Login(this.url, this._servers, this._state, Duration timeout) {
    for (final server in _servers) {
      server.listen((request) => unawaited(_handle(request)));
    }
    _timer = Timer(timeout, () {
      _finish(const CodexException('Sign-in took too long.'));
    });
  }

  @override
  final Uri url;
  final List<HttpServer> _servers;
  final String _state;
  final Completer<String> _code = Completer();
  late final Timer _timer;
  late Future<ProviderAccount> _result;

  @override
  Future<ProviderAccount> get result => _result;

  @override
  bool get listening => _servers.isNotEmpty;

  @override
  void submit(String callback) {
    final uri = Uri.tryParse(callback.trim());
    final query = uri?.queryParameters ?? const {};
    if (uri == null || !query.containsKey('state')) {
      throw const CodexException(
        'That is not the address sign-in came back to: it has no state.',
      );
    }
    if (query['state'] != _state) {
      throw const CodexException(
        'That address is of another sign-in: start again.',
      );
    }
    final code = query['code'];
    if (code == null || code.isEmpty) {
      final reason =
          query['error_description'] ?? query['error'] ?? 'No code was given.';
      _finish(CodexException('Sign-in failed: $reason'));
      return;
    }
    _finish(code);
  }

  @override
  void cancel() => _finish(const CodexCancelled());

  void _finish(Object outcome) {
    _timer.cancel();
    if (!_code.isCompleted) {
      if (outcome is String) {
        _code.complete(outcome);
      } else {
        _code.completeError(outcome);
      }
    }
    // After the page is answered.
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      for (final server in _servers) {
        unawaited(server.close(force: true));
      }
    });
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    if (request.uri.path != '/auth/callback') {
      response.statusCode = HttpStatus.notFound;
      return response.close();
    }
    final query = request.uri.queryParameters;
    final error = query['error'];
    final code = query['code'];
    final String page;
    if (query['state'] != _state) {
      response.statusCode = HttpStatus.badRequest;
      page = _page('Sign-in did not match', 'Start it again from BaoCode.');
    } else if (error != null || code == null || code.isEmpty) {
      response.statusCode = HttpStatus.badRequest;
      final reason =
          query['error_description'] ?? error ?? 'No code was given.';
      page = _page('Sign-in failed', reason);
      _finish(CodexException('Sign-in failed: $reason'));
    } else {
      page = _page(
        'Signed in',
        'You can close this page and go back to BaoCode.',
      );
      _finish(code);
    }
    response.headers.contentType = ContentType.html;
    response.write(page);
    await response.close();
  }

  static String _page(String title, String detail) {
    const escape = HtmlEscape();
    return '<!doctype html><meta charset="utf-8"><title>BaoCode</title>'
        '<body style="font-family:system-ui;text-align:center;margin-top:20vh">'
        '<h2>${escape.convert(title)}</h2><p>${escape.convert(detail)}</p>';
  }
}
