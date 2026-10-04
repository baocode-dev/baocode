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
  final List<({String path, Map<String, String> headers, Object? body})>
  requests = [];

  /// The status, and the lines of the answer.
  (int, List<String>) Function(Object? body) reply = (_) => (200, const []);

  String get base => 'http://127.0.0.1:${_server.port}/v1';

  Future<void> _handle(HttpRequest request) async {
    final text = await utf8.decodeStream(request);
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name] = values.join(','));
    final body = text.isEmpty ? null : jsonDecode(text);
    requests.add((path: request.uri.path, headers: headers, body: body));
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
      environment: () async => const {},
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
    expect(body['reasoning'], {'effort': 'low'});
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
}
