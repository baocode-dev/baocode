import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../network/tls.dart';
import '../codex/codex_balancer.dart';
import '../codex/codex_oauth.dart';
import '../codex/codex_service.dart';
import '../codex/codex_usage.dart';
import '../codex/loopback_login_io.dart';
import '../model_provider.dart';
import '../model_providers.dart';
import '../model_runtime.dart' show UpstreamException;
import '../proxy/prompt_cache_key.dart';
import '../secret_store.dart';
import '../upstream.dart';
import 'antigravity_api.dart';

/// The Antigravity providers' Google accounts while the app runs: signing
/// in to them, their access tokens (in memory; refreshed from the refresh
/// token kept in the keychain), the project each one's requests are made
/// in, its models and how much of their quota is used, and which takes a
/// request ([CodexBalancer]). Its quota is of groups of models: one used
/// up keeps an account from those models alone.
class AntigravityAccounts extends CodexService {
  AntigravityAccounts({
    required this._providers,
    this.endpoints = const AntigravityEndpoints(),
    this._findProxy,
    this._openBrowser,
    DateTime Function()? now,
    this.loginTimeout = const Duration(minutes: 10),
  }) : _now = now ?? DateTime.now;

  final ModelProviders Function() _providers;
  final AntigravityEndpoints endpoints;
  final String Function(Uri url)? _findProxy;
  final Future<bool> Function(String url)? _openBrowser;
  final DateTime Function() _now;
  final Duration loginTimeout;

  final CodexBalancer _balancer = CodexBalancer();
  final Map<String, ({String access, DateTime expiresAt})> _tokens = {};
  final Map<String, _AccountRequests> _requests = {};
  final Map<String, CodexUsage> _usage = {};
  final Map<String, List<AntigravityModel>> _models = {};
  final Map<String, String> _errors = {};

  /// Out of quota on a model, by its id, until then.
  final Map<String, Map<String, DateTime>> _limited = {};
  final Set<String> _signedOut = {};

  /// Each account's tiers, as `loadCodeAssist` last said.
  final Map<String, AntigravityLoad> _loads = {};

  String _version = antigravityFallbackVersion;
  DateTime? _versionAt;

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

  /// What its requests say they are.
  String get userAgent => antigravityUserAgent(
    _version,
    os: switch (Platform.operatingSystem) {
      'macos' => 'darwin',
      final os => os,
    },
    arch: switch (Abi.current()) {
      Abi.macosArm64 || Abi.linuxArm64 || Abi.windowsArm64 => 'arm64',
      _ => 'amd64',
    },
  );

  /// Antigravity's version as its feed says now, asked at most every six
  /// hours.
  Future<void> loadVersion() async {
    final at = _versionAt;
    if (at != null && _now().difference(at) < const Duration(hours: 6)) return;
    _versionAt = _now();
    try {
      final request = await _http.getUrl(Uri.parse(endpoints.versionFeed));
      request.headers.set(HttpHeaders.userAgentHeader, 'electron-builder');
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final text = await utf8.decodeStream(response);
      if (response.statusCode == 200) {
        _version = parseAntigravityVersion(text) ?? _version;
      }
    } on Object catch (error) {
      debugPrint('Antigravity version not asked: $error');
    }
  }

  // --- What is known ---------------------------------------------------------

  @override
  CodexUsage? usage(String providerId, String accountId) =>
      _usage[_key(providerId, accountId)];

  @override
  String? error(String providerId, String accountId) =>
      _errors[_key(providerId, accountId)];

  /// Until when [accountId] can take no request for [model]: out of its
  /// quota, by a reply or the groups its quota is of; with no model, only
  /// when every group of its quota is used up.
  DateTime? limitedFor(String providerId, String accountId, String? model) {
    final key = _key(providerId, accountId);
    final now = _now();
    final times = <DateTime>[];
    final limited = _limited[key] ?? const {};
    if (model != null) {
      if (limited[model] case final until?) times.add(until);
    } else if (limited.isNotEmpty) {
      // Each model it lists out: it all is, until the first is back.
      final models = {
        for (final m in _models[key] ?? const <AntigravityModel>[])
          splitAntigravityId(m.id).$1,
      };
      final out = limited.entries
          .where((e) => e.value.isAfter(now))
          .map((e) => e.key)
          .toSet();
      if (models.isNotEmpty && models.every(out.contains)) {
        times.add(
          limited.values
              .where((t) => t.isAfter(now))
              .reduce((a, b) => a.isBefore(b) ? a : b),
        );
      }
    }
    if (_usage[key] case final usage?) {
      final windows = model == null ? usage.windows : usage.windowsFor(model);
      final used = [
        for (final window in windows)
          if (window.usedPercent >= 100) window,
      ];
      if (model != null) {
        times.addAll(used.map((w) => w.resetsAt).nonNulls);
      } else if (used.isNotEmpty) {
        // Every group used up: back as the first is.
        final groups = {for (final w in windows) w.name ?? ''};
        final out = {for (final w in used) w.name ?? ''};
        if (groups.length == out.length) {
          final resets = used.map((w) => w.resetsAt).nonNulls;
          if (resets.isNotEmpty) {
            times.add(resets.reduce((a, b) => a.isAfter(b) ? a : b));
          }
        }
      }
    }
    final future = times.where((time) => time.isAfter(now));
    if (future.isEmpty) return null;
    return future.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  @override
  DateTime? limitedUntil(String providerId, String accountId) =>
      limitedFor(providerId, accountId, null);

  @override
  DateTime? limitedUntilFor(
    String providerId,
    String accountId, {
    String? model,
  }) => limitedFor(providerId, accountId, model);

  @override
  bool signedOut(String providerId, String accountId) =>
      _signedOut.contains(_key(providerId, accountId));

  // --- Which account ---------------------------------------------------------

  /// [provider]'s accounts that can take a request for [model] now, but
  /// [exclude].
  List<ProviderAccount> available(
    ModelProvider provider, {
    String? model,
    Set<String> exclude = const {},
  }) => [
    for (final account in provider.accounts)
      if (account.enabled &&
          !exclude.contains(account.id) &&
          !signedOut(provider.id, account.id) &&
          limitedFor(provider.id, account.id, model) == null)
        account,
  ];

  double? _used(
    ModelProvider provider,
    ProviderAccount account,
    String? model,
  ) {
    final windows = usage(provider.id, account.id)?.windowsFor(model);
    if (windows == null || windows.isEmpty) return null;
    return windows.map((w) => w.usedPercent).reduce((a, b) => a > b ? a : b);
  }

  /// The account [session]'s request for [model] goes to, by [provider]'s
  /// balance; null when none can take it.
  ProviderAccount? pick(
    ModelProvider provider, {
    String? session,
    String? model,
    Set<String> exclude = const {},
  }) => _balancer.pick(
    provider.id,
    available(provider, model: model, exclude: exclude),
    provider.balance,
    session: session,
    used: (account) => _used(provider, account, model),
  );

  @override
  ProviderAccount? accountFor(ModelProvider provider, {String? session}) =>
      accountForModel(provider, session: session);

  @override
  ProviderAccount? accountForModel(
    ModelProvider provider, {
    String? session,
    String? model,
  }) => _balancer.peek(
    provider.id,
    available(provider, model: model),
    provider.balance,
    session: session == null ? null : promptCacheKeyOf(session),
    used: (account) => _used(provider, account, model),
  );

  @override
  DateTime? backAt(ModelProvider provider) => backAtFor(provider);

  @override
  DateTime? backAtFor(ModelProvider provider, {String? model}) {
    DateTime? first;
    for (final account in provider.accounts) {
      if (!account.enabled || signedOut(provider.id, account.id)) continue;
      final until = limitedFor(provider.id, account.id, model);
      if (until == null) return null;
      if (first == null || until.isBefore(first)) first = until;
    }
    return first;
  }

  /// [account] out of quota on [model] until [until].
  void markLimited(
    ModelProvider provider,
    ProviderAccount account,
    String model,
    DateTime until,
  ) {
    final key = _key(provider.id, account.id);
    _limited.putIfAbsent(key, () => {})[model] = until;
    _balancer.forget(provider.id, account.id);
    notifyListeners();
    // The groups it is of learned, and the others of each.
    unawaited(_fetchUsage(provider.id, account));
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

  // --- Tokens ----------------------------------------------------------------

  /// [account]'s access token: refreshed when about to expire, or when
  /// [rejected] (the one refused) is still the one held. Throws
  /// [CodexException].
  Future<String> accessToken(
    ModelProvider provider,
    ProviderAccount account, {
    String? rejected,
  }) async {
    final key = _key(provider.id, account.id);
    final held = _tokens[key];
    if (held != null &&
        held.access != rejected &&
        held.expiresAt.isAfter(_now().add(const Duration(minutes: 2)))) {
      return held.access;
    }
    final requests = _requests.putIfAbsent(key, _AccountRequests.new);
    if (requests.token case final running?) return running;
    final refresh = _refresh(provider.id, account, requests).whenComplete(() {
      requests.token = null;
    });
    requests.token = refresh;
    return refresh;
  }

  bool _current(
    String providerId,
    String accountId,
    _AccountRequests requests,
  ) =>
      identical(_requests[_key(providerId, accountId)], requests) &&
      _providers().provider(providerId)?.account(accountId) != null;

  Future<String> _refresh(
    String providerId,
    ProviderAccount account,
    _AccountRequests requests,
  ) async {
    final key = _key(providerId, account.id);
    final ref = ModelProvider.accountRefFor(providerId, account.id);
    final secrets = _providers().secrets;
    void checkCurrent() {
      if (!_current(providerId, account.id, requests)) {
        throw const CodexException('The account changed.');
      }
    }

    String? refreshToken;
    try {
      refreshToken = await secrets.read(ref);
    } on SecretStoreException catch (error) {
      checkCurrent();
      throw _fail(key, 'The token could not be read: $error');
    }
    checkCurrent();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw _fail(key, 'Signed out: sign in again.', signedOut: true);
    }
    final (status, text) = await _postForm(
      Uri.parse(endpoints.token),
      antigravityRefreshForm(refreshToken),
    );
    checkCurrent();
    if (status >= 400) {
      final message = upstreamErrorMessage(status, text);
      final refused = status == 400 || status == 401 || status == 403;
      throw _fail(
        key,
        refused
            ? 'Signed out ($message): sign in again.'
            : 'The token could not be refreshed: $message',
        signedOut: refused,
      );
    }
    final tokens = _GoogleTokens.fromJson(_decode(text), _now());
    if (tokens == null) {
      throw _fail(key, 'The token endpoint gave no access token.');
    }
    if (tokens.refresh case final rotated? when rotated != refreshToken) {
      try {
        await secrets.write(ref, rotated);
      } on SecretStoreException catch (error) {
        debugPrint('Refresh token of ${account.id} not kept: $error');
      }
      checkCurrent();
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

  // --- Its project -----------------------------------------------------------

  /// The project [account]'s requests are made in: the one kept with it,
  /// else found (and the account set up, the first time) as Antigravity
  /// does. Throws [CodexException].
  Future<String> project(
    ModelProvider provider,
    ProviderAccount account,
  ) async {
    if (account.accountId case final project? when project.isNotEmpty) {
      return project;
    }
    final key = _key(provider.id, account.id);
    final requests = _requests.putIfAbsent(key, _AccountRequests.new);
    if (requests.project case final running?) return running;
    final found = _findProject(provider, account).whenComplete(() {
      requests.project = null;
    });
    requests.project = found;
    return found;
  }

  Future<String> _findProject(
    ModelProvider provider,
    ProviderAccount account,
  ) async {
    final token = await accessToken(provider, account);
    final (project, plan) = await _setUp(token);
    final providers = _providers();
    if (providers.provider(provider.id) case final now?) {
      if (now.account(account.id) case final known?) {
        await providers.save(
          now.withAccount(known.copyWith(accountId: project, plan: plan)),
        );
      }
    }
    return project;
  }

  /// What `loadCodeAssist` says of the account [token] is of: its project,
  /// plan and tiers; kept as [key]'s.
  Future<AntigravityLoad> _load(String token, {String? key}) async {
    await loadVersion();
    final (status, text) = await _post(
      token,
      endpoints.method('loadCodeAssist', at: endpoints.loadBase),
      {
        'metadata': {'ideType': 'ANTIGRAVITY'},
      },
    );
    if (status >= 400) {
      throw CodexException(
        'Antigravity could not be set up: ${upstreamErrorMessage(status, text)}',
      );
    }
    final load = AntigravityLoad.fromJson(_decode(text));
    if (key != null) _loads[key] = load;
    return load;
  }

  /// The project and plan of the account [token] is of: `loadCodeAssist`,
  /// then `onboardUser` when it has none yet.
  Future<(String, String?)> _setUp(String token) async {
    final load = await _load(token);
    if (load.project case final project?) return (project, load.plan);
    for (var i = 0; i < 5; i++) {
      final (status, text) = await _post(
        token,
        endpoints.method('onboardUser'),
        antigravityOnboardBody(load.defaultTier, _version),
        headers: {
          HttpHeaders.userAgentHeader:
              '$userAgent google-api-nodejs-client/10.3.0',
          'x-goog-api-client': 'gl-node/22.21.1',
        },
      );
      if (status >= 400) {
        throw CodexException(
          'Antigravity could not be set up: '
          '${upstreamErrorMessage(status, text)}',
        );
      }
      final json = _decode(text);
      if (json case {'done': true}) {
        final project = switch (json) {
          {'response': {'cloudaicompanionProject': final Object? value}} =>
            AntigravityLoad.projectOf(value),
          _ => null,
        };
        if (project != null) return (project, load.plan);
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw CodexException(switch (load.ineligible) {
      final why? => 'Antigravity will not serve this Google account: $why',
      null =>
        'Antigravity gave this Google account no project: sign in to the '
            'Antigravity app with it once, then try again.',
    });
  }

  // --- Signing in ------------------------------------------------------------

  @override
  Future<CodexLogin> login(String providerId) async {
    final pkce = CodexPkce.generate();
    final state = codexState();
    // The port is the one Google has for Antigravity's client.
    final servers = await bindLoopback(endpoints.callbackPort);
    final url = antigravityAuthorizeUrl(
      endpoints,
      state: state,
      challenge: pkce.challenge,
    );
    final login = LoopbackLogin(
      url,
      servers,
      state,
      loginTimeout,
      path: AntigravityEndpoints.callbackPath,
      exchange: (code) => _signedIn(providerId, code, pkce.verifier),
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
      Uri.parse(endpoints.token),
      antigravityCodeForm(endpoints, code: code, verifier: verifier),
    );
    if (status >= 400) {
      throw CodexException(
        'Sign-in failed: ${upstreamErrorMessage(status, text)}',
      );
    }
    final tokens = _GoogleTokens.fromJson(_decode(text), _now());
    final refreshToken = tokens?.refresh;
    if (tokens == null || refreshToken == null) {
      throw const CodexException('Sign-in gave no refresh token.');
    }
    final email = await _whoIs(tokens.access);
    final (project, plan) = await _setUp(tokens.access);
    final providers = _providers();
    final provider = providers.provider(providerId);
    if (provider == null) {
      throw const CodexException('The provider was removed.');
    }
    final id = email.toLowerCase();
    final account = switch (provider.account(id)) {
      final known? => known.copyWith(
        email: email,
        plan: plan,
        accountId: project,
      ),
      null => ProviderAccount(
        id: id,
        email: email,
        plan: plan,
        accountId: project,
      ),
    };
    final key = _key(providerId, account.id);
    _requests.remove(key);
    try {
      await providers.secrets.write(
        ModelProvider.accountRefFor(providerId, account.id),
        refreshToken,
      );
    } on SecretStoreException {
      throw const CodexException('The token could not be kept.');
    }
    _requests.remove(key);
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

  /// The address of the Google account [access] is of.
  Future<String> _whoIs(String access) async {
    try {
      final request = await _http.getUrl(Uri.parse(endpoints.userInfo));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $access');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final text = await utf8.decodeStream(response);
      if (response.statusCode >= 400) {
        throw CodexException(
          'Who signed in is not known: '
          '${upstreamErrorMessage(response.statusCode, text)}',
        );
      }
      return switch (_decode(text)) {
        {'email': final String email} when email.isNotEmpty => email,
        _ => throw const CodexException('Google did not say who signed in.'),
      };
    } on SocketException catch (error) {
      throw CodexException('Could not reach Google: ${error.message}');
    } on TimeoutException {
      throw const CodexException('Google did not answer in time.');
    }
  }

  @override
  Future<void> removeAccount(String providerId, String accountId) async {
    final key = _key(providerId, accountId);
    _requests.remove(key);
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
    _requests.remove(key);
    _tokens.remove(key);
    _usage.remove(key);
    _models.remove(key);
    _errors.remove(key);
    _limited.remove(key);
    _loads.remove(key);
    _signedOut.remove(key);
    _balancer.forget(providerId, accountId);
    notifyListeners();
  }

  // --- Quota and models ------------------------------------------------------

  @override
  Future<void> refreshUsage(ModelProvider provider, {bool force = true}) =>
      Future.wait([
        for (final account in provider.accounts)
          _fetchUsage(provider.id, account, force: force),
      ]);

  Future<void> _fetchUsage(
    String providerId,
    ProviderAccount account, {
    bool force = true,
  }) {
    final key = _key(providerId, account.id);
    final provider = _providers().provider(providerId);
    final current = provider?.account(account.id);
    if (current == null) return Future.value();
    final requests = _requests.putIfAbsent(key, _AccountRequests.new);
    if (requests.usage case final running?) return running;
    final previous = _usage[key];
    if (!force && !_stale(previous, requests.usageAttemptedAt)) {
      return Future.value();
    }
    requests.usageAttemptedAt = _now();
    final fetch = _queryUsage(provider!, current, requests, previous)
        .whenComplete(() {
          requests.usage = null;
        });
    requests.usage = fetch;
    return fetch;
  }

  bool _stale(CodexUsage? usage, DateTime? tried) {
    final now = _now();
    if (usage != null &&
        usage.windows.any(
          (window) => switch (window.resetsAt) {
            final at? =>
              at.isAfter(usage.at) &&
                  !at.isAfter(now) &&
                  (tried == null || tried.isBefore(at)),
            null => false,
          },
        )) {
      return true;
    }
    final last = [?usage?.at, ?tried].fold<DateTime?>(
      null,
      (latest, at) => latest == null || at.isAfter(latest) ? at : latest,
    );
    return last == null || now.difference(last) >= CodexService.usageMaxAge;
  }

  Future<void> _queryUsage(
    ModelProvider provider,
    ProviderAccount account,
    _AccountRequests requests,
    CodexUsage? previous,
  ) async {
    final key = _key(provider.id, account.id);
    bool current() =>
        _current(provider.id, account.id, requests) &&
        identical(_usage[key], previous);
    try {
      final models = await _fetchModels(provider, account);
      Object? summary;
      try {
        final (status, text) = await _call(
          provider,
          account,
          'retrieveUserQuotaSummary',
          {'project': await project(provider, account)},
        );
        if (status < 400) summary = _decode(text);
      } on Object catch (error) {
        debugPrint('Quota groups of ${account.id} not asked: $error');
      }
      if (!current()) return;
      _models[key] = models;
      final usage = antigravityUsage(
        models: models,
        summary: summary,
        now: _now(),
        plan: _loads[key]?.plan ?? account.plan,
      );
      _usage[key] = usage;
      _errors.remove(key);
      // What a reply said is out, the quota of its group now says is not:
      // started over early.
      _limited[key]?.removeWhere((model, _) {
        final group = [
          for (final window in usage.windows)
            if (window.models?.contains(model) ?? false) window,
        ];
        return group.isNotEmpty && group.every((w) => w.usedPercent < 100);
      });
    } on CodexException catch (error) {
      if (!current()) return;
      _errors[key] = error.message;
    } on Object catch (error) {
      if (!current()) return;
      _errors[key] = '$error';
    }
    notifyListeners();
  }

  /// [account]'s models as `fetchAvailableModels` lists them, its tier
  /// named as Antigravity asks: the one it pays for, else the one it is
  /// on, else none, as Google takes them. Throws [CodexException].
  Future<List<AntigravityModel>> _fetchModels(
    ModelProvider provider,
    ProviderAccount account,
  ) async {
    final key = _key(provider.id, account.id);
    final projectId = await project(provider, account);
    if (!_loads.containsKey(key)) {
      try {
        await _load(await accessToken(provider, account), key: key);
      } on Object catch (error) {
        debugPrint('Tiers of ${account.id} not asked: $error');
      }
    }
    final load = _loads[key];
    final tiers = <String?>{?load?.paidTier, ?load?.tier, null};
    var status = 0;
    var text = '';
    for (final tier in tiers) {
      (status, text) = await _call(provider, account, 'fetchAvailableModels', {
        'project': projectId,
        if (tier != null) 'entitlement': {'userTier': tier},
      });
      // A tier Google will not take from it: the next, down to none.
      if (status != 400) break;
    }
    if (status >= 400) {
      throw CodexException(upstreamErrorMessage(status, text));
    }
    return parseAntigravityModels(_decode(text));
  }

  /// The ids [account] lists, asked when not known yet.
  Future<List<String>> modelIds(
    ModelProvider provider,
    ProviderAccount account,
  ) async {
    final key = _key(provider.id, account.id);
    if (_models[key] == null) {
      await _fetchUsage(provider.id, account, force: false);
    }
    return [
      for (final model in _models[key] ?? const <AntigravityModel>[]) model.id,
    ];
  }

  /// The models [provider]'s accounts list, asked as one of them. Throws
  /// [UpstreamException].
  Future<List<RemoteModel>> listModels(ModelProvider provider) async {
    final account = pick(provider);
    if (account == null) {
      throw UpstreamException(
        provider.accounts.isEmpty
            ? 'Sign in to a Google account first.'
            : 'No account can be used now.',
      );
    }
    try {
      await loadVersion();
      final models = await _fetchModels(provider, account);
      _models[_key(provider.id, account.id)] = models;
      return antigravityRemoteModels(models);
    } on CodexException catch (error) {
      throw UpstreamException(error.message);
    } on SocketException catch (error) {
      throw UpstreamException('Could not connect: ${error.message}');
    } on TimeoutException {
      throw const UpstreamException('No answer in time.');
    }
  }

  /// Headers of a request as [account]'s, with [token].
  Map<String, String> headers(String token) => {
    HttpHeaders.authorizationHeader: 'Bearer $token',
    HttpHeaders.userAgentHeader: userAgent,
  };

  /// Code Assist's [method] with [body] as [account], its token refreshed
  /// once if refused.
  Future<(int, String)> _call(
    ModelProvider provider,
    ProviderAccount account,
    String method,
    Object body,
  ) async {
    String? rejected;
    for (var attempt = 0; ; attempt++) {
      final token = await accessToken(provider, account, rejected: rejected);
      final (status, text) = await _post(token, endpoints.method(method), body);
      if (status == 401 && attempt == 0) {
        rejected = token;
        continue;
      }
      return (status, text);
    }
  }

  Future<(int, String)> _post(
    String token,
    Uri url,
    Object body, {
    Map<String, String> headers = const {},
  }) async {
    try {
      final request = await _http.postUrl(url);
      this.headers(token).forEach(request.headers.set);
      headers.forEach(request.headers.set);
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      return (response.statusCode, await utf8.decodeStream(response));
    } on SocketException catch (error) {
      throw CodexException('Could not reach ${url.host}: ${error.message}');
    } on TimeoutException {
      throw CodexException('${url.host} did not answer in time.');
    } on HandshakeException catch (error) {
      throw CodexException('TLS failed: ${handshakeFailure(error)}');
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
      throw CodexException('TLS failed: ${handshakeFailure(error)}');
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

/// Requests belong to one sign-in, not a later account with the same id.
class _AccountRequests {
  Future<String>? token;
  Future<String>? project;
  Future<void>? usage;
  DateTime? usageAttemptedAt;
}

/// What Google's token endpoint gives.
class _GoogleTokens {
  const _GoogleTokens(this.access, this.refresh, this.expiresAt);

  final String access;
  final String? refresh;
  final DateTime expiresAt;

  static _GoogleTokens? fromJson(Object? json, DateTime now) {
    if (json is! Map) return null;
    final access = json['access_token'];
    if (access is! String || access.isEmpty) return null;
    return _GoogleTokens(
      access,
      switch (json['refresh_token']) {
        final String refresh when refresh.isNotEmpty => refresh,
        _ => null,
      },
      now.add(
        Duration(
          seconds: switch (json['expires_in']) {
            final num seconds => seconds.toInt(),
            _ => 3600,
          },
        ),
      ),
    );
  }
}
