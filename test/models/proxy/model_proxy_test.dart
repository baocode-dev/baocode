import 'dart:convert';
import 'dart:io';

import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/proxy/model_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

/// An upstream on this machine: answers each request with [reply], and
/// keeps what it was asked.
class FakeUpstream {
  FakeUpstream._(this._server);

  static Future<FakeUpstream> start() async {
    final upstream = FakeUpstream._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    upstream._server.listen(upstream._handle);
    return upstream;
  }

  final HttpServer _server;
  final List<
    ({String path, String query, Map<String, String> headers, Object? body})
  >
  requests = [];

  /// The status, and the lines of the answer.
  (int, List<String>) Function(Object? body) reply = (_) => (200, const []);

  String get base => 'http://127.0.0.1:${_server.port}/v1';

  Future<void> _handle(HttpRequest request) async {
    final text = await utf8.decodeStream(request);
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name] = values.join(','));
    final body = text.isEmpty ? null : jsonDecode(text);
    requests.add((
      path: request.uri.path,
      query: request.uri.query,
      headers: headers,
      body: body,
    ));
    final (status, lines) = reply(body);
    request.response.statusCode = status;
    for (final line in lines) {
      request.response.write('$line\n');
    }
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

/// What the proxy answered: its status, and its events' data, in order.
typedef ProxyAnswer = ({
  int status,
  String text,
  List<Map<String, Object?>> data,
});

Future<ProxyAnswer> post(
  Uri url,
  Map<String, Object?> body, {
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(url);
    headers.forEach(request.headers.set);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    return (
      status: response.statusCode,
      text: text,
      data: [
        for (final line in const LineSplitter().convert(text))
          if (line.startsWith('data: ') && line != 'data: [DONE]')
            (jsonDecode(line.substring(6)) as Map).cast<String, Object?>(),
      ],
    );
  } finally {
    client.close(force: true);
  }
}

void main() {
  late FakeUpstream upstream;
  late ModelProxy proxy;
  late ModelProvider provider;
  final errors = <String?>[];

  const tools = [
    {
      'name': 'Read',
      'description': 'Reads a file',
      'input_schema': {
        'type': 'object',
        'properties': {
          'file_path': {'type': 'string'},
        },
      },
    },
  ];

  setUp(() async {
    // Real sockets, on this machine: not the test binding's 400s.
    HttpOverrides.global = null;
    upstream = await FakeUpstream.start();
    errors.clear();
    provider = ModelProvider(
      id: 'gw',
      name: 'Gateway',
      protocol: ProviderProtocol.openaiChat,
      baseUrl: upstream.base,
      models: const [
        ProviderModel(id: 'gpt-5'),
        ProviderModel(id: 'plain'),
      ],
    );
    proxy = ModelProxy(
      provider: (id) => id == provider.id ? provider : null,
      key: (_) async => 'sk-upstream',
      onError: (_, error) => errors.add(error),
      findProxy: (_) => 'DIRECT',
      token: 'tok',
    );
  });

  tearDown(() async {
    await proxy.close();
    await upstream.close();
  });

  Future<Uri> messages([String path = '']) async {
    final endpoint = await proxy.endpoint('gw');
    expect(endpoint.token, 'tok');
    return Uri.parse('${endpoint.baseUrl}/v1/messages$path');
  }

  test('listens on this machine only, and answers only its token', () async {
    final url = await messages();
    expect(url.host, '127.0.0.1');
    final none = await post(url, {'model': 'gpt-5', 'messages': []});
    expect(none.status, 401);
    expect(jsonDecode(none.text), {
      'type': 'error',
      'error': {
        'type': 'authentication_error',
        'message': 'Not this proxy\'s token',
      },
    });
    final wrong = await post(
      url,
      {'model': 'gpt-5', 'messages': []},
      headers: {'x-api-key': 'tik'},
    );
    expect(wrong.status, 401);
    expect(upstream.requests, isEmpty);
  });

  test('counts tokens itself, as an estimate', () async {
    final answer = await post(
      await messages('/count_tokens'),
      {
        'model': 'gpt-5',
        'system': 'Be brief.',
        'messages': [
          {'role': 'user', 'content': 'hello there'},
        ],
      },
      headers: {'authorization': 'Bearer tok'},
    );
    expect(answer.status, 200);
    final tokens = (jsonDecode(answer.text) as Map)['input_tokens'] as int;
    expect(tokens, greaterThan(5));
    expect(upstream.requests, isEmpty);
  });

  test('Chat Completions: a tool call goes out and its stream comes back '
      'as Anthropic\'s', () async {
    upstream.reply = (_) => (
      200,
      [
        'data: {"id":"c1","object":"chat.completion.chunk","created":1,"model":"gpt-5","choices":[{"index":0,"delta":{"role":"assistant","content":"Reading."},"finish_reason":null}]}',
        '',
        'data: {"id":"c1","object":"chat.completion.chunk","created":1,"model":"gpt-5","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"Read","arguments":"{\\"file_path\\":"}}]},"finish_reason":null}]}',
        '',
        'data: {"id":"c1","object":"chat.completion.chunk","created":1,"model":"gpt-5","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"a.txt\\"}"}}]},"finish_reason":null}]}',
        '',
        'data: {"id":"c1","object":"chat.completion.chunk","created":1,"model":"gpt-5","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
        '',
        'data: {"id":"c1","object":"chat.completion.chunk","created":1,"model":"gpt-5","choices":[],"usage":{"prompt_tokens":11,"completion_tokens":7,"total_tokens":18}}',
        '',
        'data: [DONE]',
      ],
    );
    final answer = await post(
      await messages(),
      {
        'model': 'gpt-5(high)',
        'max_tokens': 1000,
        'stream': true,
        'system': 'You are Claude Code.',
        'tools': tools,
        'messages': [
          {'role': 'user', 'content': 'read a.txt'},
          {
            'role': 'assistant',
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_0',
                'name': 'Read',
                'input': {'file_path': 'b.txt'},
              },
            ],
          },
          {
            'role': 'user',
            'content': [
              {'type': 'tool_result', 'tool_use_id': 'toolu_0', 'content': 'B'},
            ],
          },
        ],
      },
      headers: {'x-api-key': 'tok'},
    );

    // What went upstream: OpenAI's request, its key, the effort asked for.
    final sent = upstream.requests.single;
    expect(sent.path, '/v1/chat/completions');
    expect(sent.headers['authorization'], 'Bearer sk-upstream');
    final body = sent.body! as Map;
    expect(body['model'], 'gpt-5');
    expect(body['stream'], isTrue);
    expect(body['stream_options'], {'include_usage': true});
    expect(body['reasoning_effort'], 'high');
    expect((body['tools'] as List).single, {
      'type': 'function',
      'function': {
        'name': 'Read',
        'description': 'Reads a file',
        'parameters': {
          'type': 'object',
          'properties': {
            'file_path': {'type': 'string'},
          },
        },
      },
    });
    final sentMessages = (body['messages'] as List).cast<Map>();
    expect(sentMessages.map((m) => m['role']), [
      'system',
      'user',
      'assistant',
      'tool',
    ]);
    expect(sentMessages[2]['tool_calls'], [
      {
        'id': 'toolu_0',
        'type': 'function',
        'function': {'name': 'Read', 'arguments': '{"file_path":"b.txt"}'},
      },
    ]);
    expect(sentMessages[3], {
      'role': 'tool',
      'tool_call_id': 'toolu_0',
      'name': 'Read',
      'content': 'B',
    });

    // What came back: Anthropic's events.
    expect(answer.status, 200);
    final types = [for (final event in answer.data) event['type']];
    expect(types.first, 'message_start');
    expect(types.last, 'message_stop');
    final starts = [
      for (final event in answer.data)
        if (event['type'] == 'content_block_start')
          event['content_block']! as Map,
    ];
    expect(starts.map((block) => block['type']), ['text', 'tool_use']);
    expect(starts[1]['id'], 'call_1');
    expect(starts[1]['name'], 'Read');
    final arguments = [
      for (final event in answer.data)
        if (event case {
          'type': 'content_block_delta',
          'delta': {
            'type': 'input_json_delta',
            'partial_json': final String json,
          },
        })
          json,
    ].join();
    expect(jsonDecode(arguments), {'file_path': 'a.txt'});
    final delta = answer.data.lastWhere((e) => e['type'] == 'message_delta');
    expect((delta['delta']! as Map)['stop_reason'], 'tool_use');
    expect((delta['usage']! as Map)['output_tokens'], 7);
    expect(errors, [null]);
  });

  test('a model with no effort, or Disable, is not asked to think', () async {
    upstream.reply = (_) => (
      200,
      [
        'data: {"id":"c","choices":[{"index":0,"delta":{"content":"hi"},"finish_reason":"stop"}]}',
        'data: [DONE]',
      ],
    );
    await post(
      await messages(),
      {
        'model': 'plain',
        'stream': true,
        'thinking': {'type': 'enabled', 'budget_tokens': 4000},
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      },
      headers: {'authorization': 'Bearer tok'},
    );
    expect(
      (upstream.requests.single.body! as Map).containsKey('reasoning_effort'),
      isFalse,
    );
    await post(
      await messages(),
      {
        'model': 'gpt-5(none)',
        'stream': true,
        'thinking': {'type': 'enabled', 'budget_tokens': 4000},
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      },
      headers: {'authorization': 'Bearer tok'},
    );
    expect(
      (upstream.requests.last.body! as Map).containsKey('reasoning_effort'),
      isFalse,
    );
  });

  test('an upstream\'s error goes back as Anthropic\'s, and is told', () async {
    upstream.reply = (_) => (401, ['{"error":{"message":"bad key"}}']);
    final answer = await post(
      await messages(),
      {
        'model': 'gpt-5',
        'stream': true,
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      },
      headers: {'authorization': 'Bearer tok'},
    );
    expect(answer.status, 401);
    expect(jsonDecode(answer.text), {
      'type': 'error',
      'error': {'type': 'authentication_error', 'message': 'HTTP 401: bad key'},
    });
    expect(errors, ['HTTP 401: bad key']);
  });

  test('Chat Completions without streaming', () async {
    upstream.reply = (_) => (
      200,
      [
        jsonEncode({
          'id': 'c2',
          'model': 'gpt-5',
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': 'Done.'},
              'finish_reason': 'stop',
            },
          ],
          'usage': {'prompt_tokens': 3, 'completion_tokens': 2},
        }),
      ],
    );
    final answer = await post(
      await messages(),
      {
        'model': 'gpt-5',
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      },
      headers: {'authorization': 'Bearer tok'},
    );
    expect(answer.status, 200);
    final message = jsonDecode(answer.text) as Map;
    expect(message['type'], 'message');
    expect(message['content'], [
      {'type': 'text', 'text': 'Done.'},
    ]);
    expect(message['stop_reason'], 'end_turn');
  });

  test('Responses: a tool call goes out and its stream comes back as '
      'Anthropic\'s', () async {
    provider = provider.copyWith(protocol: ProviderProtocol.openaiResponses);
    upstream.reply = (_) => (
      200,
      [
        'event: response.created',
        'data: {"type":"response.created","response":{"id":"resp_1","model":"gpt-5"}}',
        '',
        'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_9","name":"Read"},"output_index":0}',
        'data: {"type":"response.function_call_arguments.delta","delta":"{\\"file_path\\":\\"a.txt\\"}","output_index":0}',
        'data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_9","name":"Read","arguments":"{\\"file_path\\":\\"a.txt\\"}"},"output_index":0}',
        'data: {"type":"response.completed","response":{"usage":{"input_tokens":5,"output_tokens":4}}}',
      ],
    );
    final answer = await post(
      await messages(),
      {
        'model': 'gpt-5(low)',
        'stream': true,
        'tools': tools,
        'messages': [
          {'role': 'user', 'content': 'read a.txt'},
        ],
      },
      headers: {'authorization': 'Bearer tok'},
    );
    final sent = upstream.requests.single;
    expect(sent.path, '/v1/responses');
    final body = sent.body! as Map;
    expect(body['model'], 'gpt-5');
    expect(body['stream'], isTrue);
    expect(body['reasoning'], {'effort': 'low', 'summary': 'auto'});
    expect((body['tools'] as List).single, containsPair('name', 'Read'));
    expect(
      (body['input'] as List).cast<Map>().map((item) => item['role']),
      contains('user'),
    );

    final starts = [
      for (final event in answer.data)
        if (event['type'] == 'content_block_start')
          event['content_block']! as Map,
    ];
    expect(starts.single['type'], 'tool_use');
    expect(starts.single['id'], 'call_9');
    final delta = answer.data.lastWhere((e) => e['type'] == 'message_delta');
    expect((delta['delta']! as Map)['stop_reason'], 'tool_use');
    expect(answer.data.last['type'], 'message_stop');
  });

  group('Fast mode', () {
    for (final fast in [false, true]) {
      test(
        'Responses uses Fast only when the model requests it ($fast)',
        () async {
          provider = provider.copyWith(
            protocol: ProviderProtocol.openaiResponses,
          );
          upstream.reply = (_) => (200, const []);
          await post(
            await messages(),
            {
              'model': fast ? 'gpt-5(high;fast)' : 'gpt-5(high)',
              'stream': true,
              'messages': [
                {'role': 'user', 'content': 'hi'},
              ],
            },
            headers: {'authorization': 'Bearer tok'},
          );
          final sent = upstream.requests.single.body! as Map;
          expect(sent['model'], 'gpt-5');
          expect(sent['reasoning'], containsPair('effort', 'high'));
          expect(sent['service_tier'], fast ? 'priority' : isNull);
        },
      );
    }

    for (final explicit in <Map<String, Object?>>[
      {'speed': 'fast'},
      {'service_tier': 'fast'},
      {'service_tier': 'priority'},
      {'speed': 'standard'},
      {'service_tier': 'auto'},
      {'service_tier': 'default'},
    ]) {
      for (final fast in [false, true]) {
        test('Responses respects $explicit with Fast $fast', () async {
          provider = provider.copyWith(
            protocol: ProviderProtocol.openaiResponses,
          );
          upstream.reply = (_) => (200, const []);
          await post(
            await messages(),
            {
              'model': fast ? 'gpt-5(high;fast)' : 'gpt-5(high)',
              'stream': true,
              'messages': [],
              ...explicit,
            },
            headers: {'authorization': 'Bearer tok'},
          );
          final sent = upstream.requests.single.body! as Map;
          expect(
            sent['service_tier'],
            explicit.values.any((v) => v == 'fast' || v == 'priority')
                ? 'priority'
                : isNull,
          );
        });
      }
    }

    test('Chat Completions ignores the Fast model suffix', () async {
      upstream.reply = (_) => (200, const []);
      await post(
        await messages(),
        {'model': 'gpt-5(high;fast)', 'stream': true, 'messages': []},
        headers: {'authorization': 'Bearer tok'},
      );
      expect(
        upstream.requests.single.body! as Map,
        isNot(contains('service_tier')),
      );
    });
  });

  group('prompt_cache_key', () {
    const session = '3f1c2a9e-0d4b-4c6e-9a7f-1b2c3d4e5f60';
    Map<String, Object?> request(String userId) => {
      'metadata': {'user_id': userId},
    };

    test('is the session\'s, hashed: the same for each of its requests, '
        'another for another session', () {
      final key = promptCacheKey(
        request(jsonEncode({'device_id': 'd', 'session_id': session})),
      );
      expect(key, matches(RegExp(r'^baocode-[0-9a-f]{32}$')));
      expect(key, isNot(contains(session)));
      // The older form names the same session.
      expect(
        promptCacheKey(request('user_abc_account__session_$session')),
        key,
      );
      expect(
        promptCacheKey(request(jsonEncode({'session_id': 'other'}))),
        isNot(key),
      );
    });

    test('is none without a session', () {
      expect(promptCacheKey(const {}), isNull);
      expect(promptCacheKey(request('')), isNull);
      expect(promptCacheKey(request('user_abc')), isNull);
      expect(promptCacheKey(request(jsonEncode({'device_id': 'd'}))), isNull);
    });

    test('#307 falls back on the session header for a user_id the user set',
        () {
      final key = promptCacheKey(
        request(jsonEncode({'device_id': 'd', 'session_id': session})),
      );
      expect(promptCacheKey(request('abcdefghijk'), header: session), key);
      expect(promptCacheKey(const {}, header: session), key);
      // The body's own session is taken over the header.
      expect(
        promptCacheKey(
          request(jsonEncode({'session_id': session})),
          header: 'other',
        ),
        key,
      );
      expect(sessionId(request('abcdefghijk'), header: ' '), isNull);
    });

    test('#307 an overridden user_id still sends the key, by the header',
        () async {
      provider = provider.copyWith(protocol: ProviderProtocol.openaiResponses);
      upstream.reply = (_) => (200, const []);
      final body = {
        'model': 'gpt-5',
        'stream': true,
        'metadata': {'user_id': 'abcdefghijk'},
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      };
      await post(
        await messages(),
        body,
        headers: {
          'authorization': 'Bearer tok',
          'x-claude-code-session-id': session,
        },
      );
      expect(
        (upstream.requests.last.body! as Map)['prompt_cache_key'],
        promptCacheKey(body, header: session),
      );
      expect(promptCacheKey(body, header: session), isNotNull);
    });

    for (final protocol in [
      ProviderProtocol.openaiChat,
      ProviderProtocol.openaiResponses,
    ]) {
      test('goes to ${protocol.id} upstreams, unless turned off', () async {
        provider = provider.copyWith(protocol: protocol);
        upstream.reply = (_) => (200, const []);
        final body = {
          'model': 'gpt-5',
          'stream': true,
          'metadata': {
            'user_id': jsonEncode({'session_id': session}),
          },
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        };
        await post(
          await messages(),
          body,
          headers: {'authorization': 'Bearer tok'},
        );
        expect(
          (upstream.requests.last.body! as Map)['prompt_cache_key'],
          promptCacheKey(body),
        );

        provider = provider.copyWith(promptCacheKey: false);
        await post(
          await messages(),
          body,
          headers: {'authorization': 'Bearer tok'},
        );
        expect(
          (upstream.requests.last.body! as Map).containsKey('prompt_cache_key'),
          isFalse,
        );
      });
    }
  });

  test('an upstream is asked with the provider\'s custom headers, their '
      'variables filled, a key not overwritten', () async {
    const session = '3f1c2a9e-0d4b-4c6e-9a7f-1b2c3d4e5f60';
    provider = provider.copyWith(
      headers: {
        'x-session-id': '{{CLAUDE_SESSION_ID}}',
        'x-model': '{{ANTHROPIC_MODEL}}',
        'x-tenant': 'acme',
        // The user agent may be the upstream's own client's.
        'User-Agent': 'opencode/1.17.12',
        // A key must not go from here, and no auth header is overwritten.
        'authorization': 'Bearer nope',
        'x-api-key': 'nope',
      },
    );
    upstream.reply = (_) => (200, const []);
    await post(
      await messages(),
      {
        'model': 'gpt-5',
        'stream': true,
        'metadata': {
          'user_id': jsonEncode({'session_id': session}),
        },
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      },
      headers: {'authorization': 'Bearer tok'},
    );
    final sent = upstream.requests.single.headers;
    expect(sent['x-session-id'], session);
    expect(sent['x-model'], 'gpt-5');
    expect(sent['x-tenant'], 'acme');
    expect(sent['user-agent'], 'opencode/1.17.12');
    expect(sent['authorization'], 'Bearer sk-upstream');
    expect(sent.containsKey('x-api-key'), isFalse);
  });

  test('a conversation goes to the upstream\'s own endpoint, a model\'s '
      'own address over it', () async {
    final origin = Uri.parse(upstream.base).origin;
    provider = provider.copyWith(
      endpointUrl: () => '$origin/gateway/chat',
      models: [
        const ProviderModel(id: 'gpt-5'),
        ProviderModel(id: 'plain', endpointUrl: '$origin/plain/chat'),
      ],
    );
    for (final (model, path) in [
      ('gpt-5', '/gateway/chat'),
      ('plain', '/plain/chat'),
    ]) {
      await post(
        await messages(),
        {
          'model': model,
          'stream': true,
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        },
        headers: {'authorization': 'Bearer tok'},
      );
      expect(upstream.requests.last.path, path, reason: model);
    }
  });

  test('an unknown provider or endpoint is not found', () async {
    final endpoint = await proxy.endpoint('gw');
    final base = endpoint.baseUrl.replaceFirst('/p/gw', '');
    final unknown = await post(
      Uri.parse('$base/p/nope/v1/messages'),
      {'model': 'x', 'messages': []},
      headers: {'authorization': 'Bearer tok'},
    );
    expect(unknown.status, 404);
    final path = await post(
      Uri.parse('$base/elsewhere'),
      const {},
      headers: {'authorization': 'Bearer tok'},
    );
    expect(path.status, 404);
  });

  group('another upstream\'s model, and Anthropic\'s API', () {
    late FakeUpstream anthropic;
    late ModelProxy routing;
    late ModelProvider claude;

    setUp(() async {
      anthropic = await FakeUpstream.start();
      claude = ModelProvider(
        id: 'an',
        name: 'Claude',
        baseUrl: anthropic.base,
        auth: ProviderAuth.apiKey,
        headers: const {'x-tenant': 'acme'},
        roles: const ProviderRoles(subagent: '@gw/plain'),
      );
      routing = ModelProxy(
        provider: (id) => {'gw': provider, 'an': claude}[id],
        key: (id) async => 'sk-$id',
        onError: (_, error) => errors.add(error),
        findProxy: (_) => 'DIRECT',
        token: 'tok',
      );
    });

    tearDown(() async {
      await routing.close();
      await anthropic.close();
    });

    Future<Uri> on(String id, [String path = '']) async =>
        Uri.parse('${(await routing.endpoint(id)).baseUrl}/v1/messages$path');

    test('passes a request to Anthropic\'s API as it came, the key and '
        'its headers set here, and its stream back as it comes', () async {
      const events = [
        'event: message_start',
        'data: {"type":"message_start","message":{"id":"m1"}}',
        '',
        'event: message_stop',
        'data: {"type":"message_stop"}',
        '',
      ];
      anthropic.reply = (_) => (200, events);
      final body = {
        'model': 'claude-opus-4-5',
        'stream': true,
        'max_tokens': 100,
        'output_config': {'effort': 'high'},
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': 'hi',
                'cache_control': {'type': 'ephemeral'},
              },
            ],
          },
        ],
      };
      final url = await on('an');
      final answer = await post(
        url.replace(query: 'beta=true'),
        body,
        headers: {
          'x-api-key': 'tok',
          'anthropic-version': '2023-06-01',
          'anthropic-beta': 'interleaved-thinking-2025-05-14',
          'user-agent': 'claude-cli/9.9.9 (external, cli)',
        },
      );
      expect(answer.status, 200);
      expect(answer.text, '${events.join('\n')}\n');
      final sent = anthropic.requests.single;
      expect(sent.path, '/v1/messages');
      expect(sent.body, body);
      expect(sent.headers['x-api-key'], 'sk-an');
      expect(sent.headers.containsKey('authorization'), isFalse);
      expect(sent.headers['anthropic-beta'], 'interleaved-thinking-2025-05-14');
      expect(sent.headers['anthropic-version'], '2023-06-01');
      expect(sent.headers['user-agent'], 'claude-cli/9.9.9 (external, cli)');
      expect(sent.headers['x-tenant'], 'acme');
      expect(upstream.requests, isEmpty);
      expect(errors.last, isNull);
    });

    test('a model of another upstream goes there, by its own name', () async {
      upstream.reply = (_) => (
        200,
        [
          'data: {"id":"c1","object":"chat.completion.chunk","created":1,"model":"plain","choices":[{"index":0,"delta":{"role":"assistant","content":"Hi."},"finish_reason":"stop"}]}',
          '',
          'data: [DONE]',
        ],
      );
      final answer = await post(
        await on('an'),
        {
          'model': '@gw/plain',
          'max_tokens': 100,
          'stream': true,
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        },
        headers: {'x-api-key': 'tok'},
      );
      expect(answer.status, 200);
      expect(anthropic.requests, isEmpty);
      final sent = upstream.requests.single;
      expect((sent.body! as Map)['model'], 'plain');
      expect(sent.headers['authorization'], 'Bearer sk-gw');

      // And the other way: an OpenAI session's subagents on Anthropic.
      anthropic.reply = (_) => (200, const ['{"id":"m2"}']);
      final back = await post(
        await on('gw'),
        {
          'model': '@an/claude-haiku-4-5',
          'max_tokens': 100,
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        },
        headers: {'x-api-key': 'tok'},
      );
      expect(back.status, 200);
      expect(
        (anthropic.requests.single.body! as Map)['model'],
        'claude-haiku-4-5',
      );
    });

    test('Anthropic\'s errors come back as they are; a count it has none '
        'of is estimated', () async {
      const error =
          '{"type":"error","error":{"type":"overloaded_error","message":"busy"}}';
      anthropic.reply = (_) => (529, const [error]);
      final failed = await post(
        await on('an'),
        {'model': 'claude-opus-4-5', 'messages': []},
        headers: {'x-api-key': 'tok'},
      );
      expect(failed.status, 529);
      expect(failed.text.trim(), error);
      expect(errors.last, contains('busy'));

      anthropic.reply = (_) => (404, const ['{}']);
      final counted = await post(
        await on('an', '/count_tokens'),
        {
          'model': 'claude-opus-4-5',
          'messages': [
            {'role': 'user', 'content': 'hello there'},
          ],
        },
        headers: {'x-api-key': 'tok'},
      );
      expect(counted.status, 200);
      expect(anthropic.requests.last.path, '/v1/messages/count_tokens');
      expect((jsonDecode(counted.text) as Map)['input_tokens'], greaterThan(0));
    });

    test('Anthropic\'s API at an address of its own: the endpoint\'s query '
        'kept, tokens counted under it', () async {
      final origin = Uri.parse(anthropic.base).origin;
      claude = claude.copyWith(endpointUrl: () => '$origin/relay/msg?k=1');
      await post(
        (await on('an')).replace(query: 'beta=true'),
        {'model': 'claude-opus-4-5', 'messages': []},
        headers: {'x-api-key': 'tok'},
      );
      expect(anthropic.requests.last.path, '/relay/msg');
      expect(anthropic.requests.last.query, 'k=1&beta=true');
      expect(anthropic.requests.last.headers['x-api-key'], 'sk-an');
      await post(
        await on('an', '/count_tokens'),
        {'model': 'claude-opus-4-5', 'messages': []},
        headers: {'x-api-key': 'tok'},
      );
      expect(anthropic.requests.last.path, '/relay/msg/count_tokens');
    });

    test('a model\'s endpoint type and address apart: Anthropic\'s API '
        'spoken to at its own address', () async {
      final origin = Uri.parse(anthropic.base).origin;
      provider = provider.withModel(
        ProviderModel(
          id: 'claude-x',
          protocol: ProviderProtocol.anthropic,
          endpointUrl: '$origin/x/messages',
        ),
      );
      await post(
        await messages(),
        {'model': 'claude-x', 'messages': []},
        headers: {'authorization': 'Bearer tok'},
      );
      expect(anthropic.requests.single.path, '/x/messages');
      expect(upstream.requests, isEmpty);
    });

    test('Claude Code\'s own, or an upstream not here, is not found', () async {
      for (final model in ['@claude-code/sonnet', '@gone/x']) {
        final answer = await post(
          await on('an'),
          {'model': model, 'messages': []},
          headers: {'x-api-key': 'tok'},
        );
        expect(answer.status, 404, reason: model);
      }
      expect(anthropic.requests, isEmpty);
      expect(upstream.requests, isEmpty);
    });
  });

  group('a model at an endpoint of its own', () {
    late FakeUpstream relay;
    late ModelProxy routing;
    late ModelProvider mixed;

    setUp(() async {
      relay = await FakeUpstream.start();
      // A relay serving each API at one base URL: its GPT at Chat
      // Completions, as the upstream is set, its Claude at Messages, one
      // more at Responses. Its auth set for its Claude.
      mixed = ModelProvider(
        id: 'rl',
        name: 'Relay',
        protocol: ProviderProtocol.openaiChat,
        baseUrl: relay.base,
        auth: ProviderAuth.apiKey,
        models: const [
          ProviderModel(id: 'gpt-5'),
          ProviderModel(
            id: 'claude-sonnet-4-5',
            protocol: ProviderProtocol.anthropic,
          ),
          ProviderModel(
            id: 'gpt-5-codex',
            protocol: ProviderProtocol.openaiResponses,
          ),
        ],
      );
      routing = ModelProxy(
        provider: (id) => {'rl': mixed, 'gw': provider}[id],
        key: (id) async => 'sk-$id',
        onError: (_, error) => errors.add(error),
        findProxy: (_) => 'DIRECT',
        token: 'tok',
      );
    });

    tearDown(() async {
      await routing.close();
      await relay.close();
    });

    Future<Uri> on(String id, [String path = '']) async =>
        Uri.parse('${(await routing.endpoint(id)).baseUrl}/v1/messages$path');

    final hi = [
      {'role': 'user', 'content': 'hi'},
    ];

    test('its Claude goes to the Messages API as it came, the key as '
        'x-api-key', () async {
      relay.reply = (_) => (200, const ['{"id":"m1"}']);
      final body = {
        'model': 'claude-sonnet-4-5',
        'max_tokens': 100,
        'output_config': {'effort': 'high'},
        'messages': hi,
      };
      final answer = await post(
        await on('rl'),
        body,
        headers: {'x-api-key': 'tok'},
      );
      expect(answer.status, 200);
      final sent = relay.requests.single;
      expect(sent.path, '/v1/messages');
      expect(sent.body, body);
      expect(sent.headers['x-api-key'], 'sk-rl');
      expect(sent.headers.containsKey('authorization'), isFalse);
      expect(sent.headers['anthropic-version'], '2023-06-01');

      // Its count too, at the Messages API.
      relay.reply = (_) => (200, const ['{"input_tokens":7}']);
      final counted = await post(
        await on('rl', '/count_tokens'),
        {'model': 'claude-sonnet-4-5', 'messages': hi},
        headers: {'x-api-key': 'tok'},
      );
      expect(jsonDecode(counted.text), {'input_tokens': 7});
      expect(relay.requests.last.path, '/v1/messages/count_tokens');
    });

    test('its GPT goes to Chat Completions, translated, the effort after '
        'its name, the key a bearer token', () async {
      relay.reply = (_) => (
        200,
        [
          'data: {"id":"c1","object":"chat.completion.chunk","created":1,"model":"gpt-5","choices":[{"index":0,"delta":{"role":"assistant","content":"Hi."},"finish_reason":"stop"}]}',
          '',
          'data: [DONE]',
        ],
      );
      final answer = await post(
        await on('rl'),
        {
          'model': 'gpt-5(high)',
          'max_tokens': 100,
          'stream': true,
          'messages': hi,
        },
        headers: {'x-api-key': 'tok'},
      );
      expect(answer.status, 200);
      final sent = relay.requests.single;
      expect(sent.path, '/v1/chat/completions');
      expect((sent.body! as Map)['model'], 'gpt-5');
      expect((sent.body! as Map)['reasoning_effort'], 'high');
      expect(sent.headers['authorization'], 'Bearer sk-rl');
      expect(sent.headers.containsKey('x-api-key'), isFalse);
      expect(sent.headers.containsKey('anthropic-version'), isFalse);
    });

    test('one at Responses goes there', () async {
      await post(
        await on('rl'),
        {
          'model': 'gpt-5-codex(low)',
          'max_tokens': 100,
          'stream': true,
          'messages': hi,
        },
        headers: {'x-api-key': 'tok'},
      );
      final sent = relay.requests.single;
      expect(sent.path, '/v1/responses');
      expect((sent.body! as Map)['model'], 'gpt-5-codex');
      expect((sent.body! as Map)['reasoning'], containsPair('effort', 'low'));
    });

    test('picked from another upstream, at its own endpoint too', () async {
      relay.reply = (_) => (200, const ['{"id":"m2"}']);
      final answer = await post(
        await on('gw'),
        {'model': '@rl/claude-sonnet-4-5', 'max_tokens': 100, 'messages': hi},
        headers: {'x-api-key': 'tok'},
      );
      expect(answer.status, 200);
      final sent = relay.requests.single;
      expect(sent.path, '/v1/messages');
      expect((sent.body! as Map)['model'], 'claude-sonnet-4-5');
      expect(upstream.requests, isEmpty);
    });
  });
}
