import 'dart:convert';
import 'dart:io';

import 'package:baocode/models/antigravity/antigravity_accounts_io.dart';
import 'package:baocode/models/antigravity/antigravity_api.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/proxy/model_proxy.dart';
import 'package:baocode/models/proxy/translate/antigravity_signature.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/usage/usage_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Answer = (int status, List<String> lines);

/// Google's token endpoint and Code Assist, on this machine.
class FakeGoogle {
  FakeGoogle._(this._server);

  static Future<FakeGoogle> start() async {
    final fake = FakeGoogle._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fake._server.listen(fake._handle);
    return fake;
  }

  final HttpServer _server;
  final List<({String path, Map<String, String> headers, String body})>
  requests = [];

  Answer Function(String path, Map<String, Object?> body) reply = (_, _) =>
      (404, const []);

  String get base => 'http://127.0.0.1:${_server.port}';

  AntigravityEndpoints get endpoints => AntigravityEndpoints(
    token: '$base/token',
    userInfo: '$base/userinfo',
    base: base,
    loadBase: base,
    versionFeed: '$base/feed',
  );

  Iterable<({String path, Map<String, String> headers, String body})> to(
    String path,
  ) => requests.where((r) => r.path == path);

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name] = values.join(','));
    requests.add((path: request.uri.path, headers: headers, body: body));
    Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      // The token endpoint's form.
      json = Uri(query: body).queryParameters;
    }
    final (status, lines) = request.uri.path == '/feed'
        ? (200, ['version: 2.10.0'])
        : reply(
            request.uri.path,
            json is Map<String, Object?> ? json : const {},
          );
    request.response.statusCode = status;
    for (final line in lines) {
      request.response.write('$line\n');
    }
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

const _models = {
  'models': {
    'gemini-4-neon-low': {'displayName': 'Gemini 4 Neon (Low)'},
    'gemini-4-neon-high': {'displayName': 'Gemini 4 Neon (High)'},
    'claude-opus-5-5-high': {'displayName': 'Claude Opus 5.5 (High)'},
  },
};

List<String> _stream(String text, {int thoughts = 0}) => [
  'data: ${jsonEncode({
    'response': {
      'responseId': 'r1',
      'candidates': [
        {
          'content': {
            'role': 'model',
            'parts': [
              {'text': text},
            ],
          },
          'finishReason': 'STOP',
        },
      ],
      'usageMetadata': {'promptTokenCount': 100, 'cachedContentTokenCount': 60, 'candidatesTokenCount': 5, if (thoughts > 0) 'thoughtsTokenCount': thoughts},
    },
  })}',
  '',
];

void main() {
  late FakeGoogle google;
  late MemorySecretStore secrets;
  late ModelProviders providers;
  late AntigravityAccounts accounts;
  late ModelProxy proxy;
  late UsageLedger ledger;
  const a = ProviderAccount(id: 'a@x', email: 'a@x', accountId: 'proj-a');
  const b = ProviderAccount(id: 'b@x', email: 'b@x', accountId: 'proj-b');

  ModelProvider provider() => providers.provider('ag')!;

  setUp(() async {
    HttpOverrides.global = null;
    google = await FakeGoogle.start();
    ledger = UsageLedger(MemoryUsageStorage());
    secrets = MemorySecretStore({
      ModelProvider.accountRefFor('ag', 'a@x'): 'refresh-a',
      ModelProvider.accountRefFor('ag', 'b@x'): 'refresh-b',
    });
    providers = ModelProviders.memory(
      secrets: secrets,
      providers: [
        const ModelProvider(
          id: 'ag',
          name: 'Antigravity',
          protocol: ProviderProtocol.antigravity,
          balance: AccountBalance.fillFirst,
          accounts: [a, b],
          models: [ProviderModel(id: 'gemini-4-neon')],
        ),
      ],
    );
    accounts = AntigravityAccounts(
      providers: () => providers,
      endpoints: google.endpoints,
    );
    proxy = ModelProxy(
      provider: (id) => providers.provider(id),
      key: (_) async => null,
      findProxy: (_) => 'DIRECT',
      antigravity: accounts,
      signatures: MemorySignatureStore(),
      usage: () => ledger,
      token: 'tok',
    );
  });

  tearDown(() async {
    await proxy.close();
    accounts.close();
    await google.close();
    ledger.dispose();
  });

  Answer common(String path, Map<String, Object?> body) => switch (path) {
    '/token' => (
      200,
      [
        jsonEncode({
          'access_token': 'access-${body['refresh_token'] ?? 'x'}',
          'expires_in': 3600,
        }),
      ],
    ),
    '/v1internal:loadCodeAssist' => (
      200,
      [
        jsonEncode({
          'currentTier': {'id': 'free-tier', 'name': 'Free'},
          'paidTier': {'id': 'g1-pro-tier', 'name': 'Google AI Pro'},
          'cloudaicompanionProject': 'proj-found',
        }),
      ],
    ),
    '/v1internal:fetchAvailableModels' => (200, [jsonEncode(_models)]),
    '/v1internal:retrieveUserQuotaSummary' => (200, ['{}']),
    _ => (404, const []),
  };

  Future<({int status, String text})> ask(
    String model, {
    String first = 'hi',
  }) async {
    final endpoint = await proxy.endpoint('ag');
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('${endpoint.baseUrl}/v1/messages'),
      );
      request.headers
        ..set('authorization', 'Bearer tok')
        ..contentType = ContentType.json;
      request.write(
        jsonEncode({
          'model': model,
          'stream': true,
          'max_tokens': 1000,
          'metadata': {
            'user_id': jsonEncode({'session_id': 'session-1'}),
          },
          'system': 'Be brief.',
          'messages': [
            {'role': 'user', 'content': first},
          ],
        }),
      );
      final response = await request.close();
      return (
        status: response.statusCode,
        text: await utf8.decodeStream(response),
      );
    } finally {
      client.close(force: true);
    }
  }

  test('goes as Antigravity, its variant picked by the effort', () async {
    google.reply = (path, body) => switch (path) {
      '/v1internal:streamGenerateContent' => (200, _stream('hello')),
      _ => common(path, body),
    };
    final answer = await ask('gemini-4-neon(high)');
    expect(answer.status, 200);
    expect(answer.text, contains('"text":"hello"'));
    expect(answer.text, contains('"cache_read_input_tokens":60'));
    final sent = google.to('/v1internal:streamGenerateContent').single;
    expect(sent.headers['authorization'], 'Bearer access-refresh-a');
    expect(sent.headers['user-agent'], startsWith('antigravity/hub/2.10.0 '));
    final body = jsonDecode(sent.body) as Map;
    expect(body['model'], 'gemini-4-neon-high');
    expect(body['project'], 'proj-a');
    expect(body['userAgent'], 'antigravity');
    expect(body['requestType'], 'agent');
    expect(body['requestId'], startsWith('agent-'));
    final request = body['request'] as Map;
    expect(request['systemInstruction'], {
      'role': 'user',
      'parts': [
        {'text': 'Be brief.'},
      ],
    });
    // The same conversation, the same session: its prompt cached.
    await ask('gemini-4-neon(low)');
    final again = jsonDecode(
      google.to('/v1internal:streamGenerateContent').last.body,
    ) as Map;
    expect(again['model'], 'gemini-4-neon-low');
    expect((again['request'] as Map)['sessionId'], request['sessionId']);
    await ask('gemini-4-neon(low)', first: 'another');
    final other = jsonDecode(
      google.to('/v1internal:streamGenerateContent').last.body,
    ) as Map;
    expect((other['request'] as Map)['sessionId'], isNot(request['sessionId']));
  });

  test('kept in usage: the account, the cache and the reasoning', () async {
    google.reply = (path, body) => switch (path) {
      '/v1internal:streamGenerateContent' => (
        200,
        _stream('hello', thoughts: 20),
      ),
      _ => common(path, body),
    };
    final answer = await ask('gemini-4-neon(high)');
    expect(answer.status, 200);
    ledger.flush();
    final call = (await ledger.ofSession('session-1')).single;
    expect(call.provider, 'ag');
    expect(call.providerName, 'Antigravity');
    expect(call.protocol, 'antigravity');
    expect(call.model, 'gemini-4-neon');
    expect(call.effort, 'high');
    expect(call.account, 'a@x');
    // Gemini's prompt counts its cached part too.
    expect(call.input, 40);
    expect(call.cacheRead, 60);
    expect(call.output, 25);
    expect(call.reasoning, 20);
    expect(call.status, 200);
    expect(call.failed, isFalse);
  });

  test('an account out of quota on a model gives way on it alone', () async {
    google.reply = (path, body) => switch (path) {
      '/v1internal:streamGenerateContent'
          when body['project'] == 'proj-a' &&
              '${body['model']}'.startsWith('gemini') =>
        (
          429,
          [
            jsonEncode({
              'error': {
                'code': 429,
                'message':
                    'You have exhausted your capacity on this model. Your '
                    'quota will reset after 2h0m0s.',
              },
            }),
          ],
        ),
      '/v1internal:streamGenerateContent' => (
        200,
        _stream('${body['project']}'),
      ),
      _ => common(path, body),
    };
    final answer = await ask('gemini-4-neon(high)');
    expect(answer.status, 200);
    expect(answer.text, contains('proj-b'));
    expect(accounts.limitedFor('ag', 'a@x', 'gemini-4-neon'), isNotNull);
    expect(accounts.limitedFor('ag', 'a@x', 'claude-opus-5-5'), isNull);
    // Claude's still go to the first.
    final claude = await ask('claude-opus-5-5(high)');
    expect(claude.text, contains('proj-a'));
    expect(
      accounts.accountForModel(provider(), model: 'gemini-4-neon')?.id,
      'b@x',
    );
  });

  test('every account out of quota is told, not retried', () async {
    google.reply = (path, body) => switch (path) {
      '/v1internal:streamGenerateContent' => (
        429,
        [
          jsonEncode({
            'error': {'message': 'Your quota will reset after 1h0m0s.'},
          }),
        ],
      ),
      _ => common(path, body),
    };
    final answer = await ask('gemini-4-neon(high)');
    expect(answer.status, 429);
    expect(answer.text, contains('out of quota'));
    expect(accounts.backAtFor(provider(), model: 'gemini-4-neon'), isNotNull);
    expect(accounts.backAtFor(provider(), model: 'claude-opus-5-5'), isNull);
  });

  test("an account without a project is set up, and it kept", () async {
    await providers.save(
      provider().copyWith(
        accounts: [const ProviderAccount(id: 'a@x', email: 'a@x')],
      ),
    );
    google.reply = (path, body) => switch (path) {
      '/v1internal:streamGenerateContent' => (200, _stream('ok')),
      _ => common(path, body),
    };
    final answer = await ask('gemini-4-neon(high)');
    expect(answer.status, 200);
    final body = jsonDecode(
      google.to('/v1internal:streamGenerateContent').single.body,
    ) as Map;
    expect(body['project'], 'proj-found');
    expect(provider().account('a@x')?.accountId, 'proj-found');
    expect(provider().account('a@x')?.plan, 'Google AI Pro');
  });

  test(
    'signing in: the browser back with its code, the account kept',
    () async {
      // A free port, for Google's 51121.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      final endpoints = AntigravityEndpoints(
        token: '${google.base}/token',
        userInfo: '${google.base}/userinfo',
        base: google.base,
        loadBase: google.base,
        versionFeed: '${google.base}/feed',
        callbackPort: port,
      );
      google.reply = (path, body) => switch (path) {
        '/token' when body['grant_type'] == 'authorization_code' => (
          200,
          [
            jsonEncode({
              'access_token': 'access-new',
              'refresh_token': 'refresh-new',
              'expires_in': 3600,
            }),
          ],
        ),
        '/userinfo' => (
          200,
          [
            jsonEncode({'email': 'New@X'}),
          ],
        ),
        _ => common(path, body),
      };
      final browser = HttpClient();
      final signIn = AntigravityAccounts(
        providers: () => providers,
        endpoints: endpoints,
        // The browser: Google sends it back with a code.
        openBrowser: (url) async {
          final asked = Uri.parse(url);
          final back = Uri.parse(asked.queryParameters['redirect_uri']!)
              .replace(
                queryParameters: {
                  'code': 'the-code',
                  'state': asked.queryParameters['state'],
                },
              );
          final response = await (await browser.getUrl(back)).close();
          await response.drain<void>();
          return true;
        },
      );
      addTearDown(() {
        signIn.close();
        browser.close(force: true);
      });

      final login = await signIn.login('ag');
      expect(login.url.queryParameters['client_id'], antigravityClientId);
      expect(
        login.url.queryParameters['redirect_uri'],
        'http://localhost:$port/oauth-callback',
      );
      expect(login.url.queryParameters['code_challenge_method'], 'S256');
      final account = await login.result;

      expect(account.id, 'new@x');
      final exchanged = Uri(query: google.to('/token').first.body)
          .queryParameters;
      expect(exchanged['code'], 'the-code');
      expect(exchanged['client_secret'], antigravityClientSecret);
      expect(exchanged['code_verifier'], isNotEmpty);
      expect(
        google.to('/userinfo').single.headers['authorization'],
        'Bearer access-new',
      );
      final kept = provider().account('new@x')!;
      expect(kept.accountId, 'proj-found');
      expect(kept.plan, 'Google AI Pro');
      expect(
        await secrets.read(ModelProvider.accountRefFor('ag', 'new@x')),
        'refresh-new',
      );
    },
  );

  test('the models listed are families with their levels', () async {
    google.reply = common;
    final models = await accounts.listModels(provider());
    expect(
      {for (final m in models) m.id: m.efforts},
      {
        'gemini-4-neon': ['low', 'high'],
        'claude-opus-5-5-high': <String>[],
      },
    );
  });
}
