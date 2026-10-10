import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:baocode/models/codex/codex_accounts_io.dart';
import 'package:baocode/models/codex/codex_api.dart';
import 'package:baocode/models/codex/codex_balancer.dart';
import 'package:baocode/models/codex/codex_oauth.dart';
import 'package:baocode/models/codex/codex_service.dart';
import 'package:baocode/models/codex/codex_usage.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/proxy/model_proxy.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/models/upstream.dart';
import 'package:flutter_test/flutter_test.dart';

String jwt(Map<String, Object?> claims) {
  String part(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part(claims)}.sig';
}

String idToken({
  String email = 'a@example.com',
  String account = 'ws-a',
  String user = 'user-a',
  String plan = 'plus',
}) => jwt({
  'email': email,
  'https://api.openai.com/auth': {
    'chatgpt_account_id': account,
    'chatgpt_user_id': user,
    'chatgpt_plan_type': plan,
  },
});

/// The shape of an OpenAI reasoning `encrypted_content` (Fernet's).
String gptSignature() {
  final payload = List<int>.filled(1 + 8 + 16 + 16 + 32, 0);
  payload[0] = 0x80;
  for (var i = 9; i < payload.length; i++) {
    payload[i] = i;
  }
  return base64Url.encode(payload).replaceAll('=', '');
}

typedef Answer = (int status, Map<String, String> headers, List<String> lines);

/// OpenAI's auth and ChatGPT's backend, on this machine.
class FakeOpenAI {
  FakeOpenAI._(this._server);

  static Future<FakeOpenAI> start() async {
    final fake = FakeOpenAI._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fake._server.listen(fake._handle);
    return fake;
  }

  final HttpServer _server;
  final List<
    ({
      String path,
      Map<String, String> query,
      Map<String, String> headers,
      String body,
    })
  >
  requests = [];

  Answer Function(String path, Map<String, String> headers, String body) reply =
      (_, _, _) => (404, const {}, const []);

  String get base => 'http://127.0.0.1:${_server.port}';

  CodexEndpoints endpoints({int callbackPort = 1455}) => CodexEndpoints(
    auth: base,
    backend: '$base/backend-api',
    callbackPort: callbackPort,
  );

  Iterable<
    ({
      String path,
      Map<String, String> query,
      Map<String, String> headers,
      String body,
    })
  >
  to(String path) => requests.where((r) => r.path == path);

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name] = values.join(','));
    requests.add((
      path: request.uri.path,
      query: request.uri.queryParameters,
      headers: headers,
      body: body,
    ));
    final (status, answerHeaders, lines) = reply(
      request.uri.path,
      headers,
      body,
    );
    request.response.statusCode = status;
    answerHeaders.forEach(request.response.headers.set);
    for (final line in lines) {
      request.response.write('$line\n');
    }
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

Answer tokens(String access, {String? refresh, String? id}) => (
  200,
  const {},
  [
    jsonEncode({
      'access_token': access,
      'refresh_token': ?refresh,
      'id_token': ?id,
      'expires_in': 3600,
    }),
  ],
);

Map<String, String> form(String body) => Uri.splitQueryString(body);

const _stream = [
  'data: {"type":"response.created","response":{"id":"resp_1","model":"gpt-5"}}',
  '',
  'data: {"type":"response.output_text.delta","delta":"hi","output_index":0}',
  'data: {"type":"response.completed","response":{"usage":{"input_tokens":5,"output_tokens":1}}}',
];

void main() {
  final now = DateTime(2026, 10, 10, 12);

  group('sign-in', () {
    test('PKCE: the challenge is the S256 of the verifier', () {
      final pkce = CodexPkce.generate(Random(1));
      expect(pkce.verifier, matches(RegExp(r'^[A-Za-z0-9_-]{128}$')));
      expect(pkce.challenge, CodexPkce.challengeOf(pkce.verifier));
      // RFC 7636's example.
      expect(
        CodexPkce.challengeOf('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('the authorize URL is the Codex CLI\'s', () {
      final url = codexAuthorizeUrl(
        const CodexEndpoints(),
        state: 's',
        challenge: 'c',
      );
      expect(url.origin, 'https://auth.openai.com');
      expect(url.path, '/oauth/authorize');
      expect(url.queryParameters, {
        'client_id': codexClientId,
        'response_type': 'code',
        'redirect_uri': 'http://localhost:1455/auth/callback',
        'scope': 'openid email profile offline_access',
        'state': 's',
        'code_challenge': 'c',
        'code_challenge_method': 'S256',
        'prompt': 'login',
        'id_token_add_organizations': 'true',
        'codex_cli_simplified_flow': 'true',
      });
    });

    test('who an ID token is of; the same key signing in again', () {
      final identity = CodexIdentity.fromIdToken(idToken());
      expect(identity.email, 'a@example.com');
      expect(identity.accountId, 'ws-a');
      expect(identity.userId, 'user-a');
      expect(identity.plan, 'plus');
      expect(identity.key, matches(RegExp(r'^[0-9a-f]{12}$')));
      expect(CodexIdentity.fromIdToken(idToken()).key, identity.key);
      expect(
        CodexIdentity.fromIdToken(idToken(account: 'ws-b')).key,
        isNot(identity.key),
      );
      expect(CodexIdentity.fromIdToken('nonsense').email, isNull);
    });

    test('tokens expire as told, else as the JWT says', () {
      final told = CodexTokens.fromJson({
        'access_token': 'a',
        'refresh_token': 'r',
        'expires_in': 60,
      }, now)!;
      expect(told.refresh, 'r');
      expect(told.expiresAt, now.add(const Duration(minutes: 1)));
      final exp = now.add(const Duration(hours: 5));
      final fromJwt = CodexTokens.fromJson({
        'access_token': jwt({'exp': exp.millisecondsSinceEpoch ~/ 1000}),
      }, now)!;
      expect(fromJwt.expiresAt, exp);
      expect(CodexTokens.fromJson({'refresh_token': 'r'}, now), isNull);
    });
  });

  group('quota', () {
    test('as /wham/usage answers', () {
      final usage = CodexUsage.fromJson({
        'plan_type': 'pro',
        'rate_limit': {
          'allowed': true,
          'limit_reached': false,
          'primary_window': {
            'used_percent': 42,
            'limit_window_seconds': 18000,
            'reset_after_seconds': 600,
          },
          'secondary_window': {
            'used_percent': 100,
            'limit_window_seconds': 604800,
            'reset_at':
                now.add(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000,
          },
        },
        'credits': {'has_credits': true, 'balance': '12.5'},
      }, now);
      expect(usage.plan, 'pro');
      expect(usage.primary!.usedPercent, 42);
      expect(usage.primary!.minutes, 300);
      expect(usage.primary!.resetsAt, now.add(const Duration(minutes: 10)));
      expect(usage.secondary!.minutes, 10080);
      expect(usage.mostUsed, 100);
      expect(usage.credits, '12.5');
      // The week used up: until it starts over.
      expect(usage.limitedUntil, now.add(const Duration(days: 2)));
    });

    test('as a reply\'s headers tell, over what was known', () {
      final previous = CodexUsage.fromJson({
        'plan_type': 'plus',
        'rate_limit': {
          'secondary_window': {'used_percent': 10},
        },
      }, now);
      final headers = {
        'x-codex-primary-used-percent': '55.5',
        'x-codex-primary-window-minutes': '300',
        'x-codex-primary-reset-after-seconds': '120',
      };
      final usage = CodexUsage.fromHeaders(
        (name) => headers[name],
        now,
        previous: previous,
      )!;
      expect(usage.primary!.usedPercent, 55.5);
      expect(usage.primary!.resetsAt, now.add(const Duration(minutes: 2)));
      expect(usage.secondary!.usedPercent, 10);
      expect(usage.plan, 'plus');
      expect(usage.limitedUntil, isNull);
      expect(CodexUsage.fromHeaders((_) => null, now), isNull);
    });

    test('a usage limit reached, as an answer or an event', () {
      final at = now.add(const Duration(hours: 3));
      expect(
        codexLimitReset(
          429,
          jsonEncode({
            'error': {
              'type': 'usage_limit_reached',
              'resets_at': at.millisecondsSinceEpoch ~/ 1000,
            },
          }),
          now,
        ),
        at,
      );
      expect(
        codexLimitResetOf({
          'type': 'response.failed',
          'response': {
            'error': {'code': 'usage_limit_reached', 'resets_in_seconds': 30},
          },
        }, now),
        now.add(const Duration(seconds: 30)),
      );
      expect(
        codexLimitReset(429, '{"error":{"type":"usage_limit_reached"}}', now),
        now.add(const Duration(minutes: 5)),
      );
      expect(codexLimitReset(429, '{"error":{"type":"other"}}', now), isNull);
      expect(codexLimitReset(429, 'not json', now), isNull);
    });
  });

  group('balance', () {
    const a = ProviderAccount(id: 'a');
    const b = ProviderAccount(id: 'b');
    const c = ProviderAccount(id: 'c');

    test('round robin takes turns; a conversation stays where it went', () {
      final balancer = CodexBalancer();
      final picks = [
        for (var i = 0; i < 4; i++)
          balancer.pick('p', [a, b, c], AccountBalance.roundRobin)!.id,
      ];
      expect(picks, ['a', 'b', 'c', 'a']);
      final first = balancer.pick(
        'p',
        [a, b, c],
        AccountBalance.roundRobin,
        session: 's',
      );
      for (var i = 0; i < 3; i++) {
        expect(
          balancer.pick(
            'p',
            [a, b, c],
            AccountBalance.roundRobin,
            session: 's',
          ),
          first,
        );
      }
      // Its account gone: another, kept from then on.
      final others = [a, b, c].where((x) => x != first).toList();
      final moved = balancer.pick(
        'p',
        others,
        AccountBalance.roundRobin,
        session: 's',
      );
      expect(others, contains(moved));
      expect(
        balancer.pick('p', [a, b, c], AccountBalance.roundRobin, session: 's'),
        moved,
      );
      balancer.forget('p', moved!.id);
      expect(
        balancer.pick('p', [a, b, c], AccountBalance.roundRobin, session: 't'),
        isNotNull,
      );
    });

    test('fill first takes the first that can', () {
      final balancer = CodexBalancer();
      expect(balancer.pick('p', [a, b], AccountBalance.fillFirst), a);
      expect(
        balancer.pick('p', [a, b], AccountBalance.fillFirst, session: 's'),
        a,
      );
      expect(
        balancer.pick('p', [b, c], AccountBalance.fillFirst, session: 's'),
        b,
      );
      expect(balancer.pick('p', [], AccountBalance.fillFirst), isNull);
    });

    test('most remaining takes the least used, unknown as unused', () {
      final balancer = CodexBalancer();
      final used = {'a': 80.0, 'b': 20.0};
      expect(
        balancer.pick(
          'p',
          [a, b],
          AccountBalance.mostRemaining,
          used: (x) => used[x.id],
        ),
        b,
      );
      expect(
        balancer.pick(
          'p',
          [a, b, c],
          AccountBalance.mostRemaining,
          used: (x) => used[x.id],
        ),
        c,
      );
    });

    test('a provider keeps its accounts and balance', () {
      final provider = ModelProvider(
        id: 'cx',
        name: 'ChatGPT',
        protocol: ProviderProtocol.codex,
        balance: AccountBalance.mostRemaining,
        accounts: const [
          ProviderAccount(id: 'a', email: 'a@x', plan: 'plus', accountId: 'w'),
          ProviderAccount(id: 'b', enabled: false),
        ],
      );
      final again = ModelProvider.fromJson(
        jsonDecode(jsonEncode(provider.toJson())) as Map<String, Object?>,
      )!;
      expect(again.protocol, ProviderProtocol.codex);
      expect(again.balance, AccountBalance.mostRemaining);
      expect(again.accounts, provider.accounts);
      expect(again.connected, isTrue);
      expect(again.host, 'chatgpt.com');
      expect(provider.copyWith(accounts: const []).connected, isFalse);
      expect(AccountBalance.parse('nonsense'), AccountBalance.roundRobin);
    });
  });

  group('requests', () {
    test('as the backend takes them', () {
      final request = prepareCodexRequest({
        'model': 'gpt-5',
        'stream': false,
        'service_tier': 'auto',
        'max_output_tokens': 100,
        'temperature': 1,
        'previous_response_id': 'r',
        'tools': [
          {'type': 'web_search'},
        ],
      });
      expect(request['instructions'], '');
      expect(request['stream'], isTrue);
      expect(request['store'], isFalse);
      expect(request.containsKey('service_tier'), isFalse);
      expect(request.containsKey('max_output_tokens'), isFalse);
      expect(request.containsKey('temperature'), isFalse);
      expect(request.containsKey('previous_response_id'), isFalse);
      expect(request['include'], [
        'reasoning.encrypted_content',
        'web_search_call.action.sources',
      ]);
      expect(
        prepareCodexRequest({'service_tier': 'priority'})['service_tier'],
        'priority',
      );
    });

    test('reasoning items are dropped for another account', () {
      final request = <String, Object?>{
        'input': [
          {'type': 'message', 'role': 'user'},
          {'type': 'reasoning', 'encrypted_content': 'x'},
        ],
      };
      expect(stripReasoningItems(request), isTrue);
      expect(request['input'], [
        {'type': 'message', 'role': 'user'},
      ]);
      expect(stripReasoningItems(request), isFalse);
      expect(
        isInvalidEncryptedContent(
          '{"error":{"code":"invalid_encrypted_content"}}',
        ),
        isTrue,
      );
    });

    test('the models it lists, with their efforts', () {
      final models = parseCodexModels({
        'models': [
          {
            'slug': 'gpt-5.5',
            'display_name': 'GPT-5.5',
            'context_window': 272000,
            'visibility': 'list',
            'supported_reasoning_levels': [
              {'effort': 'low'},
              {'effort': 'high'},
            ],
            'input_modalities': ['text', 'image'],
          },
          {'slug': 'hidden', 'visibility': 'hide'},
          {'slug': 'internal', 'supported_in_api': false},
          {'slug': 'gpt-5.5'},
        ],
      });
      expect(models.map((m) => m.id), ['gpt-5.5']);
      final model = models.single;
      expect(model.label, 'GPT-5.5');
      expect(model.contextWindow, 272000);
      expect(model.efforts, ['low', 'high']);
      expect(model.images, isTrue);
    });
  });

  group('accounts', () {
    late FakeOpenAI openai;
    late MemorySecretStore secrets;
    late ModelProviders providers;
    late CodexAccounts accounts;
    const a = ProviderAccount(id: 'a', email: 'a@x', accountId: 'ws-a');
    const b = ProviderAccount(id: 'b', email: 'b@x', accountId: 'ws-b');

    ModelProvider provider() => providers.provider('cx')!;

    setUp(() async {
      HttpOverrides.global = null;
      openai = await FakeOpenAI.start();
      secrets = MemorySecretStore({
        ModelProvider.accountRefFor('cx', 'a'): 'refresh-a',
        ModelProvider.accountRefFor('cx', 'b'): 'refresh-b',
      });
      providers = ModelProviders.memory(
        secrets: secrets,
        providers: [
          const ModelProvider(
            id: 'cx',
            name: 'ChatGPT',
            protocol: ProviderProtocol.codex,
            balance: AccountBalance.fillFirst,
            accounts: [a, b],
            models: [ProviderModel(id: 'gpt-5')],
          ),
        ],
      );
      accounts = CodexAccounts(
        providers: () => providers,
        endpoints: openai.endpoints(),
      );
    });

    tearDown(() async {
      accounts.close();
      await openai.close();
    });

    test('a token is refreshed once at a time, its successor kept', () async {
      var n = 0;
      openai.reply = (path, _, body) {
        final token = form(body)['refresh_token']!;
        n++;
        return tokens('access-$n', refresh: '$token-next');
      };
      final both = await Future.wait([
        accounts.accessToken(provider(), a),
        accounts.accessToken(provider(), a),
      ]);
      expect(both, ['access-1', 'access-1']);
      expect(openai.to('/oauth/token'), hasLength(1));
      final sent = form(openai.to('/oauth/token').single.body);
      expect(sent['grant_type'], 'refresh_token');
      expect(sent['client_id'], codexClientId);
      expect(
        await secrets.read(ModelProvider.accountRefFor('cx', 'a')),
        'refresh-a-next',
      );
      // Held: not refreshed again, unless refused.
      expect(await accounts.accessToken(provider(), a), 'access-1');
      expect(
        await accounts.accessToken(provider(), a, rejected: 'access-1'),
        'access-2',
      );
      expect(
        form(openai.to('/oauth/token').last.body)['refresh_token'],
        'refresh-a-next',
      );
    });

    test('a refresh token refused signs the account out', () async {
      openai.reply = (_, _, _) =>
          (401, const {}, ['{"error":{"message":"refresh_token_reused"}}']);
      await expectLater(
        accounts.accessToken(provider(), a),
        throwsA(isA<CodexException>()),
      );
      expect(accounts.signedOut('cx', 'a'), isTrue);
      expect(accounts.error('cx', 'a'), contains('sign in again'));
      expect(accounts.available(provider()), [b]);
    });

    test('quota and models, asked as an account', () async {
      openai.reply = (path, headers, _) => switch (path) {
        '/oauth/token' => tokens('access'),
        '/backend-api/wham/usage' => (
          200,
          const {},
          [
            jsonEncode({
              'plan_type': 'pro',
              'rate_limit': {
                'primary_window': {'used_percent': 30},
              },
            }),
          ],
        ),
        '/backend-api/codex/models' => (
          200,
          const {},
          [
            jsonEncode({
              'models': [
                {'slug': 'gpt-5', 'visibility': 'list'},
              ],
            }),
          ],
        ),
        _ => (404, const {}, const []),
      };
      await accounts.refreshUsage(provider());
      expect(accounts.usage('cx', 'a')!.primary!.usedPercent, 30);
      expect(accounts.usage('cx', 'b')!.plan, 'pro');
      final usage = openai.to('/backend-api/wham/usage').first.headers;
      expect(usage['authorization'], 'Bearer access');
      expect(usage['originator'], codexOriginator);
      expect(usage['user-agent'], codexUserAgent());
      expect(usage['user-agent'], contains(codexClientVersion));
      expect(['ws-a', 'ws-b'], contains(usage['chatgpt-account-id']));

      final models = await accounts.listModels(provider());
      expect(models.map((m) => m.id), ['gpt-5']);
      final asked = openai.to('/backend-api/codex/models').single;
      expect(asked.headers['chatgpt-account-id'], 'ws-a');
      expect(asked.query['client_version'], codexClientVersion);

      // A version of the provider's own: asked as that Codex CLI.
      await providers.save(provider().copyWith(clientVersion: () => '0.170.0'));
      await accounts.listModels(provider());
      final newer = openai.to('/backend-api/codex/models').last;
      expect(newer.query['client_version'], '0.170.0');
      expect(newer.headers['user-agent'], codexUserAgent('0.170.0'));
    });

    test('signing in: the browser comes back, the account is added', () async {
      final port = await () async {
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = socket.port;
        await socket.close();
        return port;
      }();
      Uri? opened;
      accounts = CodexAccounts(
        providers: () => providers,
        endpoints: openai.endpoints(callbackPort: port),
        openBrowser: (url) async {
          opened = Uri.parse(url);
          return true;
        },
      );
      openai.reply = (path, _, body) => switch (path) {
        '/oauth/token' => tokens(
          'access-c',
          refresh: 'refresh-c',
          id: idToken(email: 'c@x', account: 'ws-c', user: 'user-c'),
        ),
        _ => (
          200,
          const {},
          [
            jsonEncode({
              'rate_limit': {
                'primary_window': {'used_percent': 5},
              },
            }),
          ],
        ),
      };
      final login = await accounts.login('cx');
      expect(opened, login.url);
      final state = login.url.queryParameters['state']!;
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final wrong = await (await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/auth/callback?code=x&state=nope'),
      )).close();
      expect(wrong.statusCode, 400);
      await wrong.drain<void>();

      final page = await (await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:$port/auth/callback?code=c0de&state=$state',
        ),
      )).close();
      expect(page.statusCode, 200);
      await page.drain<void>();

      final account = await login.result;
      expect(account.email, 'c@x');
      expect(account.accountId, 'ws-c');
      expect(account.plan, 'plus');
      final exchanged = form(openai.to('/oauth/token').single.body);
      expect(exchanged['grant_type'], 'authorization_code');
      expect(exchanged['code'], 'c0de');
      expect(
        CodexPkce.challengeOf(exchanged['code_verifier']!),
        login.url.queryParameters['code_challenge'],
      );
      expect(provider().accounts.map((x) => x.id), ['a', 'b', account.id]);
      expect(
        await secrets.read(ModelProvider.accountRefFor('cx', account.id)),
        'refresh-c',
      );

      await accounts.removeAccount('cx', account.id);
      expect(provider().accounts, [a, b]);
      expect(
        await secrets.read(ModelProvider.accountRefFor('cx', account.id)),
        isNull,
      );
    });

    test('signing in can be cancelled', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      accounts = CodexAccounts(
        providers: () => providers,
        endpoints: openai.endpoints(callbackPort: port),
      );
      final login = await accounts.login('cx');
      login.cancel();
      await expectLater(login.result, throwsA(isA<CodexCancelled>()));
    });

    test('with the port taken, the address signed in to is pasted', () async {
      final taken = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(taken.close);
      accounts = CodexAccounts(
        providers: () => providers,
        endpoints: openai.endpoints(callbackPort: taken.port),
        openBrowser: (_) async => true,
      );
      openai.reply = (path, _, body) => switch (path) {
        '/oauth/token' => tokens(
          'access-c',
          refresh: 'refresh-c',
          id: idToken(email: 'c@x', account: 'ws-c', user: 'user-c'),
        ),
        _ => (200, const {}, ['{}']),
      };
      final login = await accounts.login('cx');
      expect(login.listening, isFalse);
      final state = login.url.queryParameters['state']!;
      final back = 'http://localhost:${taken.port}/auth/callback';
      expect(
        () => login.submit('$back?code=c0de'),
        throwsA(isA<CodexException>()),
      );
      expect(
        () => login.submit('$back?code=c0de&state=nope'),
        throwsA(isA<CodexException>()),
      );
      login.submit('  $back?code=c0de&state=$state  ');
      final account = await login.result;
      expect(account.email, 'c@x');
      expect(form(openai.to('/oauth/token').single.body)['code'], 'c0de');
      expect(provider().accounts.map((x) => x.id), ['a', 'b', account.id]);
    });

    test('a pasted address that says sign-in failed fails it', () async {
      final taken = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(taken.close);
      accounts = CodexAccounts(
        providers: () => providers,
        endpoints: openai.endpoints(callbackPort: taken.port),
      );
      final login = await accounts.login('cx');
      final state = login.url.queryParameters['state']!;
      login.submit(
        'http://localhost:${taken.port}/auth/callback'
        '?error=access_denied&state=$state',
      );
      await expectLater(
        login.result,
        throwsA(
          isA<CodexException>().having(
            (e) => e.message,
            'message',
            contains('access_denied'),
          ),
        ),
      );
      expect(openai.to('/oauth/token'), isEmpty);
    });

    group('through the proxy', () {
      late ModelProxy proxy;
      final errors = <String?>[];

      setUp(() {
        errors.clear();
        proxy = ModelProxy(
          provider: (id) => providers.provider(id),
          key: (_) async => null,
          onError: (_, error) => errors.add(error),
          findProxy: (_) => 'DIRECT',
          codex: accounts,
          token: 'tok',
        );
      });

      tearDown(() => proxy.close());

      Future<({int status, String text})> ask() async {
        final endpoint = await proxy.endpoint('cx');
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
              'model': 'gpt-5(high)',
              'stream': true,
              'max_tokens': 1000,
              'system': 'Be brief.',
              'messages': [
                {'role': 'user', 'content': 'hi'},
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

      test('goes as the Codex CLI, its quota learned from the reply', () async {
        openai.reply = (path, _, _) => switch (path) {
          '/oauth/token' => tokens('access-a'),
          _ => (
            200,
            const {
              'content-type': 'text/event-stream',
              'x-codex-primary-used-percent': '12',
              'x-codex-primary-window-minutes': '300',
            },
            _stream,
          ),
        };
        final answer = await ask();
        expect(answer.status, 200);
        expect(answer.text, contains('"text":"hi"'));
        final sent = openai.to('/backend-api/codex/responses').single;
        expect(sent.headers['authorization'], 'Bearer access-a');
        expect(sent.headers['chatgpt-account-id'], 'ws-a');
        expect(sent.headers['originator'], codexOriginator);
        expect(sent.headers['accept'], 'text/event-stream');
        final body = jsonDecode(sent.body) as Map;
        expect(body['model'], 'gpt-5');
        expect(body['reasoning'], containsPair('effort', 'high'));
        expect(body['store'], isFalse);
        expect(body['stream'], isTrue);
        expect(body['include'], ['reasoning.encrypted_content']);
        expect(body.containsKey('max_output_tokens'), isFalse);
        expect(accounts.usage('cx', 'a')!.primary!.usedPercent, 12);
        expect(errors.last, isNull);
      });

      test(
        'a token refused is refreshed, and the request sent again',
        () async {
          var refreshed = 0;
          openai.reply = (path, headers, _) {
            if (path == '/oauth/token') {
              refreshed++;
              return tokens('access-$refreshed');
            }
            return headers['authorization'] == 'Bearer access-1'
                ? (401, const {}, const ['{"error":{"message":"expired"}}'])
                : (200, const {}, _stream);
          };
          final answer = await ask();
          expect(answer.status, 200);
          expect(refreshed, 2);
          expect(
            openai
                .to('/backend-api/codex/responses')
                .map((r) => r.headers['authorization']),
            ['Bearer access-1', 'Bearer access-2'],
          );
        },
      );

      test('an account out of quota gives way to the next', () async {
        final resets = now.add(const Duration(hours: 2));
        openai.reply = (path, headers, body) {
          if (path == '/oauth/token') {
            return tokens('access-${form(body)['refresh_token']}');
          }
          return headers['chatgpt-account-id'] == 'ws-a'
              ? (
                  429,
                  const {},
                  [
                    jsonEncode({
                      'error': {
                        'type': 'usage_limit_reached',
                        'message': 'You have hit your usage limit.',
                        'resets_in_seconds': 7200,
                      },
                    }),
                  ],
                )
              : (200, const {}, _stream);
        };
        final answer = await ask();
        expect(answer.status, 200);
        expect(
          openai
              .to('/backend-api/codex/responses')
              .map((r) => r.headers['chatgpt-account-id']),
          ['ws-a', 'ws-b'],
        );
        expect(accounts.limitedUntil('cx', 'a'), isNotNull);
        expect(accounts.limitedUntil('cx', 'a')!.isAfter(resets), isFalse);
        expect(accounts.available(provider()), [b]);

        // Then straight to the one that can.
        await ask();
        expect(
          openai
              .to('/backend-api/codex/responses')
              .last
              .headers['chatgpt-account-id'],
          'ws-b',
        );
      });

      test('so does one whose stream says so first', () async {
        openai.reply = (path, headers, body) {
          if (path == '/oauth/token') {
            return tokens('access-${form(body)['refresh_token']}');
          }
          return headers['chatgpt-account-id'] == 'ws-a'
              ? (
                  200,
                  const {},
                  [
                    'event: error',
                    'data: {"type":"error","error":{"type":"usage_limit_reached","message":"limit","resets_in_seconds":60}}',
                  ],
                )
              : (200, const {}, _stream);
        };
        final answer = await ask();
        expect(answer.status, 200);
        expect(answer.text, contains('"text":"hi"'));
        expect(accounts.limitedUntil('cx', 'a'), isNotNull);
      });

      test('none left: the last account\'s error', () async {
        openai.reply = (path, _, _) => path == '/oauth/token'
            ? tokens('access')
            : (
                429,
                const {},
                ['{"error":{"type":"usage_limit_reached","message":"limit"}}'],
              );
        final answer = await ask();
        expect(answer.status, 429);
        expect(answer.text, contains('limit'));
        expect(openai.to('/backend-api/codex/responses'), hasLength(2));
        expect(errors.last, isNotNull);
      });

      test('reasoning another account encrypted is dropped', () async {
        openai.reply = (path, _, body) {
          if (path == '/oauth/token') return tokens('access');
          final input = (jsonDecode(body) as Map)['input'] as List;
          return input.any((item) => item is Map && item['type'] == 'reasoning')
              ? (
                  400,
                  const {},
                  ['{"error":{"code":"invalid_encrypted_content"}}'],
                )
              : (200, const {}, _stream);
        };
        final endpoint = await proxy.endpoint('cx');
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.postUrl(
          Uri.parse('${endpoint.baseUrl}/v1/messages'),
        );
        request.headers
          ..set('authorization', 'Bearer tok')
          ..contentType = ContentType.json;
        request.write(
          jsonEncode({
            'model': 'gpt-5(high)',
            'stream': true,
            'messages': [
              {'role': 'user', 'content': 'hi'},
              {
                'role': 'assistant',
                'content': [
                  {
                    'type': 'thinking',
                    'thinking': 'hmm',
                    'signature': gptSignature(),
                  },
                  {'type': 'text', 'text': 'ok'},
                ],
              },
              {'role': 'user', 'content': 'again'},
            ],
          }),
        );
        final response = await request.close();
        await response.drain<void>();
        expect(response.statusCode, 200);
        final sent = [
          for (final r in openai.to('/backend-api/codex/responses'))
            ((jsonDecode(r.body) as Map)['input'] as List)
                .whereType<Map>()
                .map((item) => item['type'] ?? item['role'])
                .toList(),
        ];
        expect(sent, hasLength(2));
        expect(sent.first, contains('reasoning'));
        expect(sent.last, isNot(contains('reasoning')));
      });
    });
  });

  test('upstream URLs of a Codex provider are the backend\'s', () {
    const provider = ModelProvider(
      id: 'cx',
      name: 'ChatGPT',
      protocol: ProviderProtocol.codex,
    );
    expect(
      UpstreamUrls.conversation(provider),
      const CodexEndpoints().responses,
    );
    expect(UpstreamUrls.models(provider), [const CodexEndpoints().models()]);
  });
}
