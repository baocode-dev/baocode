import 'dart:convert';
import 'dart:io';

import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/proxy/model_proxy.dart';
import 'package:baocode/usage/usage_ledger.dart';
import 'package:baocode/usage/usage_record.dart';
import 'package:flutter_test/flutter_test.dart';

/// An upstream on this machine (never a real API): answers with [reply],
/// and keeps the headers it was asked with.
class _Upstream {
  _Upstream._(this._server);

  static Future<_Upstream> start() async {
    final upstream = _Upstream._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    upstream._server.listen(upstream._handle);
    return upstream;
  }

  final HttpServer _server;
  final List<Map<String, String>> headers = [];
  (int, List<String>) Function() reply = () => (200, const []);

  String get base => 'http://127.0.0.1:${_server.port}/v1';

  Future<void> _handle(HttpRequest request) async {
    await utf8.decodeStream(request);
    final seen = <String, String>{};
    request.headers.forEach((name, values) => seen[name] = values.join(','));
    headers.add(seen);
    final (status, lines) = reply();
    request.response.statusCode = status;
    for (final line in lines) {
      request.response.write('$line\n');
    }
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

Future<int> _post(Uri url, Object body, Map<String, String> headers) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(url);
    headers.forEach(request.headers.set);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

void main() {
  late _Upstream upstream;
  late ModelProxy proxy;
  late UsageLedger ledger;
  late MemoryUsageStorage storage;
  late Map<String, ModelProvider> providers;

  const session = '11111111-2222-3333-4444-555555555555';

  Map<String, Object?> request({String model = 'gpt-5(high)'}) => {
    'model': model,
    'stream': true,
    'metadata': {
      'user_id': jsonEncode({'session_id': session}),
    },
    'system': 'You are an agent for Claude Code.',
    'tools': [
      {
        'name': 'Read',
        'input_schema': {'type': 'object'},
      },
    ],
    'messages': [
      {'role': 'user', 'content': 'Find where the proxy keeps usage'},
      {
        'role': 'assistant',
        'content': [
          {
            'type': 'tool_use',
            'id': 'tu1',
            'name': 'Read',
            'input': {'file_path': 'a.dart'},
          },
        ],
      },
      {
        'role': 'user',
        'content': [
          {'type': 'tool_result', 'tool_use_id': 'tu1', 'content': 'x' * 4000},
        ],
      },
    ],
  };

  setUp(() async {
    HttpOverrides.global = null;
    upstream = await _Upstream.start();
    storage = MemoryUsageStorage();
    ledger = UsageLedger(storage);
    providers = {
      'gw': ModelProvider(
        id: 'gw',
        name: 'Gateway',
        protocol: ProviderProtocol.openaiChat,
        baseUrl: upstream.base,
        models: const [ProviderModel(id: 'gpt-5')],
      ),
      'relay': ModelProvider(
        id: 'relay',
        name: 'Relay',
        protocol: ProviderProtocol.anthropic,
        baseUrl: upstream.base.replaceFirst('/v1', ''),
        models: const [ProviderModel(id: 'claude-x')],
      ),
    };
    proxy = ModelProxy(
      provider: (id) => providers[id],
      key: (_) async => 'sk-test',
      findProxy: (_) => 'DIRECT',
      usage: () => ledger,
      token: 'tok',
    );
  });

  tearDown(() async {
    await proxy.close();
    await upstream.close();
    ledger.dispose();
  });

  Future<Uri> url(String provider, [String path = '']) async {
    final endpoint = await proxy.endpoint(provider);
    return Uri.parse('${endpoint.baseUrl}/v1/messages$path');
  }

  test('keeps a translated call: its tokens, the cache, reasoning, who '
      'asked and the tools', () async {
    upstream.reply = () => (
      200,
      [
        'data: {"id":"c1","object":"chat.completion.chunk","created":1,"model":"gpt-5-2026","choices":[{"index":0,"delta":{"role":"assistant","content":"Found it."},"finish_reason":null}]}',
        '',
        'data: {"id":"c1","object":"chat.completion.chunk","created":1,"model":"gpt-5-2026","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}',
        '',
        'data: {"id":"c1","object":"chat.completion.chunk","created":1,"model":"gpt-5-2026","choices":[],"usage":{"prompt_tokens":1200,"completion_tokens":80,"prompt_tokens_details":{"cached_tokens":1000},"completion_tokens_details":{"reasoning_tokens":30}}}',
        '',
        'data: [DONE]',
      ],
    );
    final status = await _post(await url('gw'), request(), {
      'authorization': 'Bearer tok',
      'x-claude-code-request-class': 'subagent',
      'x-claude-code-agent-id': 'agent-7',
      'x-claude-code-agent-type': 'Explore',
      'x-claude-code-prompt-id': 'p-1',
      'x-claude-code-prev-tool-durations': 'Read=120;Bash%20X=3400',
    });
    expect(status, 200);
    ledger.flush();
    final calls = await ledger.ofSession(session);
    expect(calls, hasLength(1));
    final call = calls.single;
    expect(call.provider, 'gw');
    expect(call.providerName, 'Gateway');
    expect(call.model, 'gpt-5');
    expect(call.effort, 'high');
    expect(call.upstreamModel, 'gpt-5-2026');
    expect(call.session, session);
    expect(call.requestClass, UsageClass.subagent);
    expect(call.agentId, 'agent-7');
    expect(call.agentType, 'Explore');
    expect(call.promptId, 'p-1');
    expect(call.cacheRead, 1000);
    expect(call.input, 200);
    expect(call.output, 80);
    expect(call.reasoning, 30);
    expect(call.stopReason, 'end_turn');
    expect(call.status, 200);
    expect(call.failed, isFalse);
    expect(call.firstToken, isNotNull);
    expect(call.toolTimes, {'Read': 120, 'Bash X': 3400});
    expect(call.toolResults['Read'], greaterThan(900));
    expect(call.context!.toolResult, greaterThan(900));
    expect(call.task, 'Find where the proxy keeps usage');
    expect(call.messages, 3);
    expect(call.toolCount, 1);
  });

  test('keeps a call passed through to an Anthropic upstream, its hints '
      'not passed on', () async {
    upstream.reply = () => (
      200,
      [
        'event: message_start',
        'data: {"type":"message_start","message":{"model":"claude-x","usage":{"input_tokens":12,"cache_read_input_tokens":3000,"cache_creation_input_tokens":500,"output_tokens":1}}}',
        '',
        'event: content_block_start',
        'data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t","name":"Bash","input":{}}}',
        '',
        'event: content_block_delta',
        'data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{}"}}',
        '',
        'event: message_delta',
        'data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":42}}',
        '',
        'event: message_stop',
        'data: {"type":"message_stop"}',
      ],
    );
    final status = await _post(await url('relay'), request(model: 'claude-x'), {
      'x-api-key': 'tok',
      'x-claude-code-request-class': 'main',
      'x-claude-code-prev-tool-durations': 'Read=5',
    });
    expect(status, 200);
    final seen = upstream.headers.single;
    expect(seen.containsKey('x-claude-code-request-class'), isFalse);
    expect(seen.containsKey('x-claude-code-prev-tool-durations'), isFalse);
    ledger.flush();
    final call = (await ledger.ofSession(session)).single;
    expect(call.protocol, 'anthropic');
    expect(call.requestClass, UsageClass.main);
    expect(call.input, 12);
    expect(call.cacheRead, 3000);
    expect(call.cacheWrite, 500);
    expect(call.output, 42);
    expect(call.prompt, 3512);
    expect(call.toolCalls, {'Bash': 1});
    expect(call.stopReason, 'tool_use');
    expect(call.upstreamModel, isNull);
    expect(call.responseBytes, greaterThan(0));
  });

  test('keeps a failed call with what the upstream said', () async {
    upstream.reply = () =>
        (429, ['{"error":{"message":"Rate limited, slow down"}}']);
    await _post(await url('gw'), request(), {'authorization': 'Bearer tok'});
    ledger.flush();
    final call = (await ledger.ofSession(session)).single;
    expect(call.status, 429);
    expect(call.failed, isTrue);
    expect(call.error, contains('Rate limited'));
    expect(call.output, 0);
  });

  test('debugging, keeps each request whole: as asked, sent, answered and '
      'answered back, the keys cut down', () async {
    ledger.trace = true;
    upstream.reply = () => (
      200,
      [
        'data: {"id":"c1","object":"chat.completion.chunk","created":1,"model":"gpt-5","choices":[{"index":0,"delta":{"role":"assistant","content":"Hi"},"finish_reason":"stop"}]}',
        '',
        'data: [DONE]',
      ],
    );
    await _post(await url('gw'), request(), {'authorization': 'Bearer tok'});
    ledger.flush();
    final call = (await ledger.ofSession(session)).single;
    final trace = (await ledger.traceOf(call))!;
    expect(trace.request!.body, contains('Find where the proxy keeps usage'));
    expect(trace.request!.headers['authorization'], 'Bearer ••••');
    final sent = trace.sent.single;
    expect(sent.url, '${upstream.base}/chat/completions');
    expect(sent.headers['authorization'], 'Bearer ••••');
    expect(jsonDecode(sent.body), containsPair('model', 'gpt-5'));
    expect(trace.received.single.status, 200);
    expect(trace.received.single.body, contains('"content":"Hi"'));
    expect(trace.answer!.status, 200);
    expect(trace.answer!.body, contains('content_block_delta'));
    expect(trace.passedOn, isFalse);

    // Passed through: the answer is the upstream's own.
    upstream.reply = () => (
      200,
      [
        'event: message_start',
        'data: {"type":"message_start","message":{"usage":{"input_tokens":3}}}',
      ],
    );
    await _post(await url('relay'), request(model: 'claude-x'), {
      'x-api-key': 'tok',
    });
    ledger.flush();
    final passed = (await ledger.ofSession(session)).last;
    final through = (await ledger.traceOf(passed))!;
    expect(through.passedOn, isTrue);
    expect(through.received.single.body, contains('message_start'));
    // The upstream's key, however it goes, only by its ends.
    expect(
      through.sent.single.headers.values.where((v) => v.contains('sk-test')),
      isEmpty,
    );
    expect(through.sent.single.headers.values.join(), contains('••••'));
  });

  test('keeps no count of tokens, and nothing while turned off', () async {
    await _post(await url('gw', '/count_tokens'), request(), {
      'authorization': 'Bearer tok',
    });
    ledger.enabled = false;
    upstream.reply = () => (200, const ['data: [DONE]']);
    await _post(await url('gw'), request(), {'authorization': 'Bearer tok'});
    ledger.flush();
    expect(storage.lines, isEmpty);
  });
}
