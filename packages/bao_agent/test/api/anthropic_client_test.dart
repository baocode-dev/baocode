import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_agent/bao_agent.dart';
import 'package:bao_agent/src/api/sse.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_model.dart';

void main() {
  late FakeApi api;

  setUp(() async => api = await FakeApi.start());
  tearDown(() => api.close());

  AnthropicClient client({
    String? key = 'sk-test',
    String? token,
    Map<String, String> headers = const {},
    String? base,
    int maxRetries = 3,
  }) => AnthropicClient(
    ApiConfig(
      baseUrl: base ?? api.baseUrl,
      apiKey: key,
      authToken: token,
      headers: headers,
      maxRetries: maxRetries,
    ),
  );

  const request = ModelRequest(
    {
      'model': 'claude-opus-5-5',
      'max_tokens': 100,
      'tools': [],
      'messages': [
        {'role': 'user', 'content': 'hi'},
      ],
    },
    betas: ['a-beta', 'b-beta'],
  );

  test('streams the answer, signed and with its betas', () async {
    api.model.script.add(Reply.text('Hello there'));
    final events = await client(headers: {'x-custom': 'yes'})
        .stream(request)
        .toList();
    expect(events.first['type'], 'message_start');
    expect((events.first['message'] as Map)['_request_id'], 'req_1');
    expect(events.last['type'], 'message_stop');
    final text = events
        .where((e) => e['type'] == 'content_block_delta')
        .map((e) => (e['delta'] as Map)['text'])
        .join();
    expect(text, 'Hello there');
    final sent = api.headers.single;
    expect(sent['x-api-key'], 'sk-test');
    expect(sent['anthropic-version'], '2023-06-01');
    expect(sent['anthropic-beta'], 'a-beta,b-beta');
    expect(sent['x-custom'], 'yes');
    expect(api.model.requests.single.body['stream'], isTrue);
    expect(api.model.requests.single.body.containsKey('metadata'), isFalse);
  });

  test('what a request is for goes with it, the kind only where the '
      'environment asks for it', () async {
    expect(requestHints(const {}, requestClass: 'main'), isEmpty);
    expect(requestHints(const {}, requestClass: 'subagent', agentId: 'a1'), {
      'x-claude-code-agent-id': 'a1',
    });
    final hints = requestHints(
      const {'CLAUDE_CODE_GATEWAY_HINT_HEADERS': '1'},
      requestClass: 'subagent',
      agentId: 'a1',
      agentType: 'Explore',
    );
    expect(hints, {
      'x-claude-code-agent-id': 'a1',
      'x-claude-code-request-class': 'subagent',
      'x-claude-code-agent-type': 'Explore',
    });
    api.model.script.add(Reply.text('ok'));
    await client().stream(request.copyWith(headers: hints)).toList();
    expect(api.headers.single['x-claude-code-request-class'], 'subagent');
    expect(api.headers.single['x-claude-code-agent-id'], 'a1');
  });

  test('the session goes with every request as metadata.user_id', () async {
    api.model.script.add(Reply.text('ok'));
    await AnthropicClient(
      ApiConfig(baseUrl: api.baseUrl, apiKey: 'sk-test', userId: 'u-1'),
    ).stream(request).drain<void>();
    expect(api.model.requests.single.body['metadata'], {'user_id': 'u-1'});
  });

  test(
    'a token is sent as a bearer; a base naming /v1 is taken as is',
    () async {
      api.model.script.add(Reply.text('ok'));
      await client(
        key: null,
        token: 'tok',
        base: '${api.baseUrl}/v1/',
      ).stream(request).drain<void>();
      expect(api.headers.single['authorization'], 'Bearer tok');
      expect(api.headers.single.containsKey('x-api-key'), isFalse);
      expect(const ApiConfig(apiKey: '').hasCredentials, isFalse);
      expect(const ApiConfig().firstParty, isTrue);
      expect(ApiConfig(baseUrl: api.baseUrl).firstParty, isFalse);
    },
  );

  test('overloaded: retried after the time asked, the caller told', () async {
    api.troubles.addAll([
      const HttpTrouble(
        529,
        type: 'overloaded_error',
        message: 'Overloaded',
        headers: {'retry-after-ms': '10'},
      ),
      const HttpTrouble(
        429,
        type: 'rate_limit_error',
        headers: {'retry-after': '0'},
      ),
    ]);
    api.model.script.add(Reply.text('finally'));
    final retries = <RetryInfo>[];
    final events = await client()
        .stream(request, onRetry: retries.add)
        .toList();
    expect(events.last['type'], 'message_stop');
    expect(retries.map((r) => r.status), [529, 429]);
    expect(retries.first.delay, const Duration(milliseconds: 10));
    expect(retries.first.message, 'Overloaded');
  });

  test('a reply scripted to fail, a path that is not the API\'s', () async {
    api.model.script.add(
      Reply.failing(
        const ApiError('bad model', status: 404, type: 'not_found_error'),
      ),
    );
    final error = await client()
        .stream(request)
        .drain<void>()
        .then<ApiError?>((_) => null, onError: (Object e) => e as ApiError);
    expect((error!.status, error.type), (404, 'not_found_error'));
    final http = HttpClient();
    addTearDown(http.close);
    final response = await (await http.getUrl(
      Uri.parse('${api.baseUrl}/v1/other'),
    )).close();
    await response.drain<void>();
    expect(response.statusCode, 404);
  });

  test('a request the API refuses is not retried', () async {
    api.troubles.add(
      const HttpTrouble(
        400,
        type: 'invalid_request_error',
        message: 'prompt is too long: 300000 tokens',
      ),
    );
    final error = await client()
        .stream(request)
        .drain<void>()
        .then<ApiError?>((_) => null, onError: (Object e) => e as ApiError);
    expect(error!.status, 400);
    expect(error.type, 'invalid_request_error');
    expect(error.promptTooLong, isTrue);
    expect(error.retryable, isFalse);
    expect('$error', 'API Error 400: prompt is too long: 300000 tokens');
    expect(api.headers, hasLength(1));
  });

  test(
    'x-should-retry: false is heeded; a refused key is said to be one',
    () async {
      api.troubles.add(
        const HttpTrouble(500, headers: {'x-should-retry': 'false'}),
      );
      await expectLater(
        client().stream(request).drain<void>(),
        throwsA(isA<ApiError>()),
      );
      expect(api.headers, hasLength(1));
      api.troubles.add(
        const HttpTrouble(
          401,
          type: 'authentication_error',
          message: 'invalid x-api-key',
        ),
      );
      await expectLater(
        client().stream(request).drain<void>(),
        throwsA(
          isA<ApiError>().having(
            (e) => e.authentication,
            'authentication',
            isTrue,
          ),
        ),
      );
    },
  );

  test('an error mid-answer, or a dropped connection: started over', () async {
    api.troubles.addAll([const StreamTrouble('overloaded_error'), const Cut()]);
    api.model.script.add(Reply.text('whole'));
    final events = await client().stream(request, onRetry: (_) {}).toList();
    final restarts = events.where((e) => e['type'] == 'stream_restart');
    expect(restarts, hasLength(2));
    final afterLast = events.sublist(
      events.lastIndexWhere((e) => e['type'] == 'stream_restart') + 1,
    );
    expect(afterLast.first['type'], 'message_start');
    expect(afterLast.last['type'], 'message_stop');
  });

  test('gives up after its retries', () async {
    api.troubles.addAll([
      for (var i = 0; i < 3; i++)
        const HttpTrouble(503, headers: {'retry-after-ms': '1'}),
    ]);
    await expectLater(
      client(maxRetries: 2).stream(request).drain<void>(),
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 503)),
    );
    expect(api.headers, hasLength(3));
  });

  test('a server not there: retryable', () async {
    final error = await client(base: 'http://127.0.0.1:1', maxRetries: 0)
        .stream(request)
        .drain<void>()
        .then<ApiError?>((_) => null, onError: (Object e) => e as ApiError);
    expect(error!.retryable, isTrue);
    expect(error.message, contains('Could not reach'));
  });

  test('stopped while waiting to retry', () async {
    api.troubles.add(const HttpTrouble(529, headers: {'retry-after': '60'}));
    final cancel = CancelToken();
    final done = client()
        .stream(request, cancel: cancel, onRetry: (_) => cancel.cancel('user'))
        .drain<void>();
    await expectLater(done, throwsA(isA<Cancelled>()));
  });

  test('the models, page by page', () async {
    api.models = [
      {'id': 'one'},
      {'id': 'two'},
      {'id': 'three'},
    ];
    final models = await client().models();
    expect(models!.map((m) => m['id']), ['one', 'two', 'three']);
    expect(await client(base: 'http://127.0.0.1:1').models(), isNull);
  });

  group('SseDecoder', () {
    Future<List<SseEvent>> decode(String text) =>
        Stream.value(text).transform(const SseDecoder()).toList();

    test(
      'events, comments, lines of data, the last without a blank line',
      () async {
        final events = await decode(
          ': hello\n\nevent: a\ndata: {"x": 1}\n\ndata: one\ndata: two\nid: 7\n\ndata:no-space',
        );
        expect(events.map((e) => e.event), ['a', null, null]);
        expect(events[0].json, {'x': 1});
        expect(events[1].data, 'one\ntwo');
        expect(events[1].json, isNull);
        expect(events[2].data, 'no-space');
      },
    );

    test('split anywhere', () async {
      final chunks = ['data: {"a"', ': 2}\n', '\n'];
      final events = await Stream.fromIterable(chunks)
          .transform(const SseDecoder())
          .toList();
      expect(events.single.json, {'a': 2});
    });
  });

  test('ApiError says what it is', () {
    expect(const ApiError('x', status: 403).authentication, isTrue);
    expect(
      const ApiError('x', type: 'permission_error').authentication,
      isTrue,
    );
    expect(const ApiError('x').toString(), 'API Error: x');
    expect(
      const ApiError('context window exceeded', status: 400).promptTooLong,
      isTrue,
    );
    expect(
      jsonEncode(
        const ModelRequest({'model': 'm'}).copyWith(betas: ['b']).betas,
      ),
      '["b"]',
    );
  });
}
